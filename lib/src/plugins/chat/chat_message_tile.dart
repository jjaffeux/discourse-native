import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../data/emoji_picker_store.dart';
import '../../models/bookmark.dart';
import '../../models/post_flag.dart';
import '../../shell/bookmark_ui.dart';
import '../../shell/cooked_html.dart';
import '../../shell/emoji_picker.dart';
import '../../shell/hover_action_toolbar.dart';
import '../../shell/platform.dart';
import '../../shell/post_flag_editor.dart';
import '../../shell/relative_time.dart';
import '../../shell/shell_scope.dart';
import '../../shell/shell_sheet.dart';
import '../../shell/user_card.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../plugin_scope.dart';
import '../plugin_services.dart';
import '../reactions/reaction_pill.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_message.dart';
import 'chat_preview.dart';
import 'chat_preview_body.dart';
import 'chat_uploads.dart';
import 'chat_user_avatar.dart';

/// One message, drawn from whichever record the store holds under [messageId].
///
/// The indirection is the point, and it is `_StoredPost`'s: editing a message,
/// deleting it or reacting to it writes one record, and only the row watching
/// that record is rebuilt. It is also what lets the stream be a list of ints.
class ChatMessageTile extends StatelessWidget {
  const ChatMessageTile({
    super.key,
    required this.siteUrl,
    required this.messageId,
    required this.chained,
    this.contextThreadId,
    this.onOpenThread,
    this.onJumpToMessage,
    this.onReplyInThread,
    this.onEdit,
    this.showThreadSummary = true,
    this.onSelect,
    this.selecting = false,
    this.selected = false,
    this.onSelectedChanged,
  });

  final String siteUrl;
  final int messageId;

  /// The thread pane containing this row, if any.
  ///
  /// A message can carry a thread id even while it is rendered in its parent
  /// channel. Core chooses the share URL from the pane context instead, so the
  /// caller supplies that context explicitly.
  final int? contextThreadId;

  /// Whether this row belongs to the run above it, and so draws no avatar, no
  /// name and no time. Decided by `buildChatStream` over the whole list, since
  /// it is a fact about two messages rather than about one.
  final bool chained;

  /// Opens the thread summarized by this message, when it has replies.
  ///
  /// The tile deliberately hands the typed preview back to its owner rather
  /// than knowing about routes. A channel can open the newest reply, while a
  /// different host can make another navigation choice without changing this
  /// presentation widget.
  final ValueChanged<ChatThreadPreview>? onOpenThread;

  /// Jumps to the message named by this message's direct-reply indicator.
  final ValueChanged<int>? onJumpToMessage;

  /// Opens or creates this message's thread from the adaptive action surface.
  final ValueChanged<ChatMessage>? onReplyInThread;

  /// Hands an editable message to the channel or thread's pinned composer.
  final ValueChanged<ChatMessage>? onEdit;

  /// Whether to draw the thread summary embedded on an original message.
  ///
  /// Thread views set this false because their responses include the original
  /// message, where another link into the thread would be recursive.
  final bool showThreadSummary;
  final VoidCallback? onSelect;
  final bool selecting;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  /// Width of the avatar plus its gutter, so a chained row's body lines up with
  /// the one above it.
  static const double gutter = 42;

  /// A speaker header plus one body line and the row's vertical padding.
  static const double minimumUnchainedHeight = 58;

  /// One body line and the tighter padding used inside a speaker run.
  static const double minimumChainedHeight = 28;

  /// The height a live-edge row needs to contain its desktop hover actions.
  static const double hoverActionsTop = 4;
  static const double minimumHoverActionsHeight =
      hoverActionsTop + HoverActionButton.height;

  static Key threadPreviewKey(int threadId) =>
      ValueKey<String>('chat-thread-preview-$threadId');

  static Key actionsKey(int messageId) =>
      ValueKey<String>('chat-message-actions-$messageId');

  static Key replyIndicatorKey(int messageId) =>
      ValueKey<String>('chat-reply-indicator-$messageId');

  static Key editedIndicatorKey(int messageId) =>
      ValueKey<String>('chat-message-edited-$messageId');

  static Key bodySelectionKey(int messageId) =>
      ValueKey<String>('chat-message-body-selection-$messageId');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatMessage?>(
      valueListenable: PluginScope.require(
        context,
        chatControllerService,
      ).messageRef(siteUrl, messageId),
      builder: (context, message, _) {
        // Gone for good, in the frame before the stream that named it is
        // rewritten without it.
        if (message == null) return const SizedBox.shrink();
        final tile = _Tile(
          siteUrl: siteUrl,
          message: message,
          chained: chained,
          onOpenThread: onOpenThread,
          onJumpToMessage: onJumpToMessage,
          showThreadSummary: showThreadSummary,
        );
        if (selecting) {
          return Semantics(
            selected: selected,
            label: 'Select chat message ${message.id}',
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Checkbox(
                    key: ValueKey('chat-message-selector-${message.id}'),
                    value: selected,
                    onChanged: onSelectedChanged == null
                        ? null
                        : (value) => onSelectedChanged!(value ?? false),
                  ),
                ),
                Expanded(child: tile),
              ],
            ),
          );
        }
        final canReplyInThread =
            onReplyInThread != null &&
            !message.isDeleted &&
            !message.isOptimistic &&
            (message.threadId == null || message.thread != null);
        final chat = PluginScope.require(context, chatControllerService);
        final canBookmark = chat.canBookmarkMessage(siteUrl, message);
        final canEdit = onEdit != null && chat.canEditMessage(siteUrl, message);
        final canDelete = chat.canDeleteMessage(siteUrl, message);
        final canPin = chat.canPinMessage(siteUrl, message);
        final canRebake = chat.canRebakeMessage(siteUrl, message);
        final canAddReaction = chat.canAddReactionToMessage(siteUrl, message);
        final flagTypes = chat.availableChatFlagTypes(
          siteUrl,
          message,
          ShellScope.read(context).postFlagTypesFor(siteUrl),
        );
        final canCopyLink = message.id > 0 && !message.isOptimistic;
        final canCopyText =
            message.raw.isNotEmpty &&
            switch (Theme.of(context).platform) {
              TargetPlatform.android || TargetPlatform.iOS => true,
              _ => false,
            };
        return canReplyInThread ||
                canBookmark ||
                canEdit ||
                canDelete ||
                canPin ||
                canRebake ||
                canAddReaction ||
                flagTypes.isNotEmpty ||
                canCopyLink ||
                onSelect != null
            ? _ChatMessageActions(
                focusKey: actionsKey(message.id),
                siteUrl: siteUrl,
                message: message,
                contextThreadId: contextThreadId,
                onReply: canReplyInThread
                    ? () => onReplyInThread!(message)
                    : null,
                onEdit: onEdit,
                canBookmark: canBookmark,
                canCopyLink: canCopyLink,
                canCopyText: canCopyText,
                flagTypes: flagTypes,
                onSelect: onSelect,
                child: tile,
              )
            : tile;
      },
    );
  }
}

class _OpenChatMessageActionsIntent extends Intent {
  const _OpenChatMessageActionsIntent();
}

/// One-action variant of the post menu interaction used by chat messages.
class _ChatMessageActions extends StatefulWidget {
  const _ChatMessageActions({
    required this.focusKey,
    required this.siteUrl,
    required this.message,
    required this.contextThreadId,
    required this.onReply,
    required this.onEdit,
    required this.canBookmark,
    required this.canCopyLink,
    required this.canCopyText,
    required this.flagTypes,
    required this.onSelect,
    required this.child,
  });

  final Key focusKey;
  final String siteUrl;
  final ChatMessage message;
  final int? contextThreadId;
  final VoidCallback? onReply;
  final ValueChanged<ChatMessage>? onEdit;
  final bool canBookmark;
  final bool canCopyLink;
  final bool canCopyText;
  final List<PostFlagType> flagTypes;
  final VoidCallback? onSelect;
  final Widget child;

  @override
  State<_ChatMessageActions> createState() => _ChatMessageActionsState();
}

class _ChatMessageActionsState extends State<_ChatMessageActions> {
  bool _hovered = false;
  bool _hoverSuppressed = false;
  bool _pinning = false;
  bool _rebaking = false;
  bool _reactionPickerOpening = false;
  ScrollPosition? _scroll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _scroll)) return;
    _detachScroll();
    _scroll = position;
    position?.addListener(_hideHoverForScroll);
    position?.isScrollingNotifier.addListener(_onScrollingChanged);
    if (position?.isScrollingNotifier.value == true) {
      _hoverSuppressed = true;
      _hovered = false;
    }
  }

  void _detachScroll() {
    _scroll?.removeListener(_hideHoverForScroll);
    _scroll?.isScrollingNotifier.removeListener(_onScrollingChanged);
  }

  void _onScrollingChanged() {
    if (_scroll?.isScrollingNotifier.value == true) _hideHoverForScroll();
  }

  void _hideHoverForScroll() {
    _hoverSuppressed = true;
    if (_hovered) setState(() => _hovered = false);
  }

  void _pointerEntered() {
    if (_hoverSuppressed || _hovered) return;
    setState(() => _hovered = true);
  }

  void _pointerMoved() {
    if (_scroll?.isScrollingNotifier.value == true) return;
    _hoverSuppressed = false;
    if (!_hovered) setState(() => _hovered = true);
  }

  void _pointerExited() {
    if (_hovered) setState(() => _hovered = false);
  }

  @override
  void dispose() {
    _detachScroll();
    super.dispose();
  }

  void _reply() {
    widget.onReply?.call();
  }

  String get _messageUrl {
    final siteUrl = widget.siteUrl.endsWith('/')
        ? widget.siteUrl.substring(0, widget.siteUrl.length - 1)
        : widget.siteUrl;
    final threadSegment = switch (widget.contextThreadId) {
      final threadId? => '/t/$threadId',
      null => '',
    };
    return '$siteUrl/chat/c/-/${widget.message.channelId}'
        '$threadSegment/${widget.message.id}';
  }

  Future<void> _copyLink() async {
    String message;
    try {
      await Clipboard.setData(ClipboardData(text: _messageUrl));
      message = 'Link copied!';
    } catch (_) {
      message = "Couldn't copy link.";
    }
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyText() async {
    String notice;
    try {
      await Clipboard.setData(ClipboardData(text: widget.message.raw));
      notice = 'Message copied!';
    } catch (_) {
      notice = "Couldn't copy message.";
    }
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(notice)));
  }

  Future<void> _bookmark() => showChatMessageBookmarkMenu(
    context: context,
    controller: ShellScope.read(context),
    siteUrl: widget.siteUrl,
    messageId: widget.message.id,
    bookmark: widget.message.bookmark,
    cooked: widget.message.cooked,
  );

  Future<void> _pickReaction([BuildContext? anchorContext]) async {
    if (_reactionPickerOpening) return;
    setState(() => _reactionPickerOpening = true);
    try {
      await _pickChatMessageReaction(
        context: context,
        anchorContext: anchorContext,
        siteUrl: widget.siteUrl,
        message: widget.message,
      );
    } finally {
      if (mounted) setState(() => _reactionPickerOpening = false);
    }
  }

  void _edit() => widget.onEdit?.call(widget.message);

  Future<void> _delete() async {
    final chat = PluginScope.require(context, chatControllerService);
    final error = await chat.deleteMessage(widget.siteUrl, widget.message.id);
    if (!mounted || error == null) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _togglePin() async {
    if (_pinning) return;
    setState(() => _pinning = true);
    final chat = PluginScope.require(context, chatControllerService);
    final error = await chat.setMessagePinned(
      widget.siteUrl,
      widget.message.id,
      pinned: !widget.message.pinned,
    );
    if (!mounted) return;
    setState(() => _pinning = false);
    if (error == null) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _rebake() async {
    if (_rebaking) return;
    setState(() => _rebaking = true);
    final chat = PluginScope.require(context, chatControllerService);
    final error = await chat.rebakeMessage(widget.siteUrl, widget.message.id);
    if (!mounted) return;
    setState(() => _rebaking = false);
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(error ?? 'HTML rebuild queued.')));
  }

  Future<void> _flag(List<PostFlagType> flagTypes) async {
    final shell = ShellScope.read(context);
    final chat = PluginScope.require(context, chatControllerService);
    await showShellSheet<void>(
      context: context,
      title: 'Thanks for keeping our community civil!',
      dialogOnDesktop: true,
      builder: (sheetContext) => PostFlagEditor(
        siteUrl: widget.siteUrl,
        targetUsername: widget.message.author.username,
        flagTypes: flagTypes,
        minimumMessageLength: shell
            .siteConfigFor(widget.siteUrl)
            .minPersonalMessagePostLength,
        save: (type, {message}) => chat.flagMessage(
          widget.siteUrl,
          widget.message.id,
          type,
          message: message,
        ),
        onComplete: () => Navigator.of(sheetContext).pop(),
        submitLabel: 'Flag message',
        targetNoun: 'message',
      ),
    );
  }

  Future<void> _showActions() {
    final shell = ShellScope.read(context);
    final chat = PluginScope.require(context, chatControllerService);
    final canEdit = chat.canEditMessage(widget.siteUrl, widget.message);
    final canDelete = chat.canDeleteMessage(widget.siteUrl, widget.message);
    final canPin = chat.canPinMessage(widget.siteUrl, widget.message);
    final canRebake = chat.canRebakeMessage(widget.siteUrl, widget.message);
    final canAddReaction = chat.canAddReactionToMessage(
      widget.siteUrl,
      widget.message,
    );
    final flagTypes = chat.availableChatFlagTypes(
      widget.siteUrl,
      widget.message,
      widget.flagTypes,
    );
    final bookmarkBusy = shell.bookmarkWriteInFlight(
      siteUrl: widget.siteUrl,
      topicId: 0,
      targetType: BookmarkTargetType.chatMessage,
      targetId: widget.message.id,
    );
    final bookmarkLabel = widget.message.bookmark == null
        ? 'Bookmark'
        : 'Edit bookmark';
    return showShellSheet<void>(
      context: context,
      title: 'Message actions',
      padding: EdgeInsets.zero,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canAddReaction)
            ListTile(
              minTileHeight: 52,
              leading: const DIcon(DIcons.farFaceSmile, size: 18),
              title: const Text('Add reaction'),
              enabled: !_reactionPickerOpening,
              onTap: _reactionPickerOpening
                  ? null
                  : () {
                      Navigator.of(sheetContext).pop();
                      unawaited(_pickReaction());
                    },
            ),
          if (widget.onReply != null)
            ListTile(
              minTileHeight: 52,
              leading: const DIcon(DIcons.reply, size: 18),
              title: const Text('Reply in thread'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _reply();
              },
            ),
          if (widget.canCopyLink)
            ListTile(
              minTileHeight: 52,
              leading: const DIcon(DIcons.link, size: 18),
              title: const Text('Copy link'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_copyLink());
              },
            ),
          if (widget.canCopyText)
            ListTile(
              minTileHeight: 52,
              leading: const DIcon(DIcons.copy, size: 18),
              title: const Text('Copy text'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_copyText());
              },
            ),
          if (canEdit)
            ListTile(
              minTileHeight: 52,
              leading: const DIcon(DIcons.pencil, size: 18),
              title: const Text('Edit'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _edit();
              },
            ),
          if (widget.onSelect != null)
            ListTile(
              minTileHeight: 52,
              leading: const DIcon(DIcons.list, size: 18),
              title: const Text('Select'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.onSelect!();
              },
            ),
          if (widget.canBookmark)
            ListTile(
              minTileHeight: 52,
              leading: bookmarkBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  : DIcon(_bookmarkIcon(widget.message.bookmark), size: 18),
              title: Text(bookmarkLabel),
              subtitle: bookmarkBusy ? const Text('Saving…') : null,
              enabled: !bookmarkBusy,
              onTap: bookmarkBusy
                  ? null
                  : () {
                      Navigator.of(sheetContext).pop();
                      unawaited(_bookmark());
                    },
            ),
          if (canPin)
            ListTile(
              minTileHeight: 52,
              leading: _pinning
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  : const DIcon(DIcons.thumbtack, size: 18),
              title: Text(widget.message.pinned ? 'Unpin' : 'Pin'),
              subtitle: _pinning ? const Text('Saving…') : null,
              enabled: !_pinning,
              onTap: _pinning
                  ? null
                  : () {
                      Navigator.of(sheetContext).pop();
                      unawaited(_togglePin());
                    },
            ),
          if (flagTypes.isNotEmpty)
            ListTile(
              minTileHeight: 52,
              leading: const DIcon(DIcons.flag, size: 18),
              title: const Text('Flag'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_flag(flagTypes));
              },
            ),
          if (canDelete)
            ListTile(
              minTileHeight: 52,
              leading: DIcon(
                DIcons.trashCan,
                size: 18,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                'Delete',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_delete());
              },
            ),
          if (canRebake)
            ListTile(
              minTileHeight: 52,
              leading: _rebaking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  : const DIcon(DIcons.arrowsRotate, size: 18),
              title: const Text('Rebuild HTML'),
              subtitle: _rebaking ? const Text('Starting…') : null,
              enabled: !_rebaking,
              onTap: _rebaking
                  ? null
                  : () {
                      Navigator.of(sheetContext).pop();
                      unawaited(_rebake());
                    },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = PluginScope.require(context, chatControllerService);
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(
        widget.siteUrl,
        widget.message.channelId,
      ),
      builder: (context, _, _) => ShellSelector<bool>(
        select: (shell) => shell.bookmarkWriteInFlight(
          siteUrl: widget.siteUrl,
          topicId: 0,
          targetType: BookmarkTargetType.chatMessage,
          targetId: widget.message.id,
        ),
        builder: (context, bookmarkBusy, _) => _build(
          context,
          bookmarkBusy: bookmarkBusy,
          canEdit: chat.canEditMessage(widget.siteUrl, widget.message),
          canDelete: chat.canDeleteMessage(widget.siteUrl, widget.message),
          canPin: chat.canPinMessage(widget.siteUrl, widget.message),
          canRebake: chat.canRebakeMessage(widget.siteUrl, widget.message),
          flagTypes: chat.availableChatFlagTypes(
            widget.siteUrl,
            widget.message,
            widget.flagTypes,
          ),
        ),
      ),
    );
  }

  Widget _build(
    BuildContext context, {
    required bool bookmarkBusy,
    required bool canEdit,
    required bool canDelete,
    required bool canPin,
    required bool canRebake,
    required List<PostFlagType> flagTypes,
  }) {
    final bookmarkLabel = widget.message.bookmark == null
        ? 'Bookmark'
        : 'Edit bookmark';
    final chat = PluginScope.require(context, chatControllerService);
    final canAddReaction = chat.canAddReactionToMessage(
      widget.siteUrl,
      widget.message,
    );
    final semanticsActions = <CustomSemanticsAction, VoidCallback>{
      if (canAddReaction && !_reactionPickerOpening)
        const CustomSemanticsAction(label: 'Add reaction'): () =>
            unawaited(_pickReaction()),
      if (widget.onReply != null)
        const CustomSemanticsAction(label: 'Reply in thread'): _reply,
      if (widget.canCopyLink)
        const CustomSemanticsAction(label: 'Copy link'): () =>
            unawaited(_copyLink()),
      if (canEdit) const CustomSemanticsAction(label: 'Edit'): _edit,
      if (widget.onSelect != null)
        const CustomSemanticsAction(label: 'Select'): widget.onSelect!,
      if (canDelete)
        const CustomSemanticsAction(label: 'Delete'): () =>
            unawaited(_delete()),
      if (canRebake && !_rebaking)
        const CustomSemanticsAction(label: 'Rebuild HTML'): () =>
            unawaited(_rebake()),
      if (canPin && !_pinning)
        CustomSemanticsAction(
          label: widget.message.pinned ? 'Unpin' : 'Pin',
        ): () =>
            unawaited(_togglePin()),
      if (flagTypes.isNotEmpty)
        const CustomSemanticsAction(label: 'Flag'): () =>
            unawaited(_flag(flagTypes)),
      if (widget.canBookmark && !bookmarkBusy)
        CustomSemanticsAction(label: bookmarkLabel): () =>
            unawaited(_bookmark()),
    };
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.f10, shift: true):
            _OpenChatMessageActionsIntent(),
        SingleActivator(LogicalKeyboardKey.contextMenu):
            _OpenChatMessageActionsIntent(),
      },
      child: Actions(
        actions: {
          _OpenChatMessageActionsIntent:
              CallbackAction<_OpenChatMessageActionsIntent>(
                onInvoke: (_) {
                  unawaited(_showActions());
                  return null;
                },
              ),
        },
        child: Focus(
          key: widget.focusKey,
          child: Semantics(
            customSemanticsActions: semanticsActions,
            child: MouseRegion(
              onEnter: (_) => _pointerEntered(),
              onHover: (_) => _pointerMoved(),
              onExit: (_) => _pointerExited(),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onLongPress: context.isTouch
                    ? () => unawaited(_showActions())
                    : null,
                onSecondaryTap: () => unawaited(_showActions()),
                child: Stack(
                  // Chained rows can be shorter than the 44-pixel desktop
                  // action targets positioned over them.
                  clipBehavior: Clip.none,
                  children: [
                    widget.child,
                    if (_hovered)
                      Positioned(
                        top: ChatMessageTile.hoverActionsTop,
                        right: 12,
                        child: HoverActionToolbar(
                          children: [
                            if (canAddReaction)
                              EmojiPickerAnchor(
                                child: Builder(
                                  builder: (anchorContext) => HoverActionButton(
                                    tooltip: 'Add reaction',
                                    onPressed: _reactionPickerOpening
                                        ? null
                                        : () => unawaited(
                                            _pickReaction(anchorContext),
                                          ),
                                    icon: const DIcon(
                                      DIcons.farFaceSmile,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            if (widget.onReply != null)
                              HoverActionButton(
                                tooltip: 'Reply in thread',
                                onPressed: _reply,
                                icon: const DIcon(DIcons.reply, size: 16),
                              ),
                            if (widget.canCopyLink)
                              HoverActionButton(
                                tooltip: 'Copy link',
                                onPressed: () => unawaited(_copyLink()),
                                icon: const DIcon(DIcons.link, size: 16),
                              ),
                            if (canEdit)
                              HoverActionButton(
                                tooltip: 'Edit',
                                onPressed: _edit,
                                icon: const DIcon(DIcons.pencil, size: 16),
                              ),
                            if (widget.onSelect != null)
                              HoverActionButton(
                                tooltip: 'Select',
                                onPressed: widget.onSelect,
                                icon: const DIcon(DIcons.list, size: 16),
                              ),
                            if (widget.canBookmark)
                              HoverActionButton(
                                tooltip: bookmarkLabel,
                                onPressed: bookmarkBusy
                                    ? null
                                    : () => unawaited(_bookmark()),
                                icon: bookmarkBusy
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child:
                                            CircularProgressIndicator.adaptive(
                                              strokeWidth: 2,
                                            ),
                                      )
                                    : DIcon(
                                        _bookmarkIcon(widget.message.bookmark),
                                        size: 16,
                                      ),
                              ),
                            if (canPin)
                              HoverActionButton(
                                tooltip: widget.message.pinned
                                    ? 'Unpin'
                                    : 'Pin',
                                onPressed: _pinning
                                    ? null
                                    : () => unawaited(_togglePin()),
                                icon: _pinning
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child:
                                            CircularProgressIndicator.adaptive(
                                              strokeWidth: 2,
                                            ),
                                      )
                                    : const DIcon(DIcons.thumbtack, size: 16),
                              ),
                            if (flagTypes.isNotEmpty)
                              HoverActionButton(
                                tooltip: 'Flag',
                                onPressed: () => unawaited(_flag(flagTypes)),
                                icon: const DIcon(DIcons.flag, size: 16),
                              ),
                            if (canDelete)
                              HoverActionButton(
                                tooltip: 'Delete',
                                color: Theme.of(context).colorScheme.error,
                                onPressed: () => unawaited(_delete()),
                                icon: const DIcon(DIcons.trashCan, size: 16),
                              ),
                            if (canRebake)
                              HoverActionButton(
                                tooltip: 'Rebuild HTML',
                                onPressed: _rebaking
                                    ? null
                                    : () => unawaited(_rebake()),
                                icon: _rebaking
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child:
                                            CircularProgressIndicator.adaptive(
                                              strokeWidth: 2,
                                            ),
                                      )
                                    : const DIcon(
                                        DIcons.arrowsRotate,
                                        size: 16,
                                      ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.siteUrl,
    required this.message,
    required this.chained,
    required this.onOpenThread,
    required this.onJumpToMessage,
    required this.showThreadSummary,
  });

  final String siteUrl;
  final ChatMessage message;
  final bool chained;
  final ValueChanged<ChatThreadPreview>? onOpenThread;
  final ValueChanged<int>? onJumpToMessage;
  final bool showThreadSummary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messageTextStyle = theme.textTheme.bodyLarge?.copyWith(height: 1.4);
    final messageBody = switch (message) {
      ChatMessage(canonicalReceived: true, cooked: final cooked)
          when cooked.isNotEmpty =>
        CookedHtml(
          html: cooked,
          textStyle: messageTextStyle,
          siteUrl: siteUrl,
          compactParagraphs: true,
        ),
      ChatMessage(
        canonicalReceived: false,
        preview: ProjectedPreview(:final document),
      ) =>
        ChatPreviewBody(document: document, textStyle: messageTextStyle),
      ChatMessage(
        canonicalReceived: false,
        optimisticRaw: final raw?,
        preview: final preview,
      )
          when preview is! ProjectedPreview =>
        Text(raw, style: messageTextStyle),
      _ => null,
    };

    final tile = Padding(
      key: ValueKey('chat-message-${message.id}'),
      // Core's desktop chat uses 0.65rem above a new speaker and 0.15rem
      // around a chained message, with 1rem at either side.
      padding: EdgeInsets.fromLTRB(16, chained ? 2.4 : 10.4, 16, 2.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Above the message rather than beside it, which is where Discourse
          // puts it: it is context for what follows, not part of it.
          if (message.replyTo case final reply? when !chained)
            _ReplyIndicator(
              siteUrl: siteUrl,
              reply: reply,
              onJump: onJumpToMessage == null
                  ? null
                  : () => onJumpToMessage!(reply.id),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: ChatMessageTile.gutter,
                // Aligned rather than handed straight to the gutter: a fixed
                // width is a *tight* constraint, and a SizedBox cannot shrink
                // below one it is given — `tightFor(...).enforce(incoming)`
                // clamps it straight back. Without this the avatar came out
                // gutter-wide and avatar-tall, and ClipOval drew the ellipse
                // that made of it. Align loosens what it passes down, so the
                // 28 asked for below is the 28 that arrives.
                child: chained
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: UserCardTarget(
                            username: message.author.username,
                            siteUrl: siteUrl,
                            child: ChatUserAvatar(
                              siteUrl: siteUrl,
                              userId: message.author.id,
                              url: message.author.avatarUrl,
                              size: 28,
                              fallback: ColoredBox(
                                color: theme.shell.floating,
                                child: Center(
                                  child: Text(
                                    message.author.username.isEmpty
                                        ? '?'
                                        : message
                                              .author
                                              .username
                                              .characters
                                              .first
                                              .toUpperCase(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!chained) _Header(siteUrl: siteUrl, message: message),
                    if (messageBody != null)
                      _MessageBodySelection(
                        selectionKey: ChatMessageTile.bodySelectionKey(
                          message.id,
                        ),
                        child: messageBody,
                      ),
                    if (message.uploads.isNotEmpty)
                      ChatUploads(siteUrl: siteUrl, uploads: message.uploads),
                    if (message.edited)
                      Text(
                        key: ChatMessageTile.editedIndicatorKey(message.id),
                        '(edited)',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.discourse.whisper,
                        ),
                      ),
                    if (message.reactions.isNotEmpty)
                      _Reactions(siteUrl: siteUrl, message: message),
                    if (message.thread case final thread?
                        when showThreadSummary && thread.replyCount > 0)
                      _ThreadSummaryCard(
                        siteUrl: siteUrl,
                        thread: thread,
                        onOpen: onOpenThread == null
                            ? null
                            : () => onOpenThread!(thread),
                      ),
                    if (message.delivery == ChatMessageDelivery.failed)
                      _DeliveryStatus(message: message),
                  ],
                ),
              ),
              if (message.pinned)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: Semantics(
                    label: 'Pinned chat message',
                    child: DIcon(
                      DIcons.thumbtack,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              if (message.bookmark case final bookmark?)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: Semantics(
                    label: bookmark.reminderAt == null
                        ? 'Bookmarked chat message'
                        : 'Chat message bookmarked with a reminder',
                    child: DIcon(
                      _bookmarkIcon(bookmark),
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: chained
            ? ChatMessageTile.minimumChainedHeight
            : ChatMessageTile.minimumUnchainedHeight,
      ),
      child: tile,
    );
  }
}

class _DeliveryStatus extends StatelessWidget {
  const _DeliveryStatus({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (message.delivery) {
      ChatMessageDelivery.failed => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            if (message.sendError case final error?)
              Flexible(
                child: Text(
                  error,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
      ChatMessageDelivery.sending ||
      ChatMessageDelivery.sent => const SizedBox.shrink(),
    };
  }
}

/// Keeps message text selectable without inserting an otherwise invisible
/// stop into the row's keyboard traversal order.
class _MessageBodySelection extends StatefulWidget {
  const _MessageBodySelection({
    required this.selectionKey,
    required this.child,
  });

  final Key selectionKey;
  final Widget child;

  @override
  State<_MessageBodySelection> createState() => _MessageBodySelectionState();
}

class _MessageBodySelectionState extends State<_MessageBodySelection> {
  late final FocusNode _focusNode = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectionArea(
    key: widget.selectionKey,
    focusNode: _focusNode,
    child: widget.child,
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.siteUrl, required this.message});

  final String siteUrl;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Flexible(
          child: UserCardTarget(
            username: message.author.username,
            siteUrl: siteUrl,
            child: Text(
              message.author.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (message.author.isStaff) ...[
          const SizedBox(width: 4),
          _Tag(label: 'staff', color: theme.colorScheme.primary),
        ],
        if (message.isWebhook) ...[
          const SizedBox(width: 4),
          _Tag(
            label: 'bot',
            color: theme.discourse.primaryVeryHigh,
            isBot: true,
          ),
        ],
        if (message.createdAt case final at?) ...[
          const SizedBox(width: 4),
          Text(
            relativeTime(at),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.discourse.primaryHigh,
            ),
          ),
        ],
      ],
    );
  }
}

/// What this message is answering, one line above it.
class _ReplyIndicator extends StatelessWidget {
  const _ReplyIndicator({
    required this.siteUrl,
    required this.reply,
    required this.onJump,
  });

  final String siteUrl;
  final ChatReplyTo reply;
  final VoidCallback? onJump;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      link: onJump != null,
      enabled: onJump != null,
      label: 'Jump to message from @${reply.username}: ${reply.excerpt}',
      onTap: onJump,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(
            left: ChatMessageTile.gutter,
            bottom: 2,
          ),
          child: InkWell(
            key: ChatMessageTile.replyIndicatorKey(reply.id),
            onTap: onJump,
            mouseCursor: onJump == null
                ? MouseCursor.defer
                : SystemMouseCursors.click,
            child: Row(
              children: [
                DIcon(
                  DIcons.share,
                  size: DiscourseTypography.fontDown1,
                  color: theme.discourse.primaryLowMid,
                ),
                const SizedBox(width: 8),
                ChatUserAvatar(
                  siteUrl: siteUrl,
                  userId: reply.userId,
                  url: reply.avatarUrl,
                  size: 20,
                  fallback: ColoredBox(color: theme.shell.floating),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    reply.excerpt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.discourse.primaryHigh,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _pickChatMessageReaction({
  required BuildContext context,
  required String siteUrl,
  required ChatMessage message,
  BuildContext? anchorContext,
}) async {
  final controller = ShellScope.read(context);
  final chat = PluginScope.require(context, chatControllerService);
  if (!chat.canAddReactionToMessage(siteUrl, message)) return;
  final lease = controller.lifecycle.capture(siteUrl);
  final messenger = ScaffoldMessenger.maybeOf(context);

  final picked = await showEmojiPicker(
    context: context,
    anchorContext: anchorContext,
    siteUrl: siteUrl,
    pickerContext: EmojiPickerContext.chat,
    store: controller.emojiPickerStore,
    loadCatalog: ({refresh = false}) => refresh
        ? controller.refreshEmojiCatalog(siteUrl)
        : controller.ensureEmojiCatalog(siteUrl),
    loadSearchAliases: ({refresh = false}) => refresh
        ? controller.refreshEmojiSearchAliases(siteUrl)
        : controller.ensureEmojiSearchAliases(siteUrl),
  );
  if (picked == null || !lease.isCurrent) return;
  if (context.mounted &&
      !identical(ShellScope.maybeRead(context), controller)) {
    return;
  }
  final current = chat.messageRef(siteUrl, message.id).value;
  if (current == null || !chat.canAddReactionToMessage(siteUrl, current)) {
    return;
  }

  unawaited(
    controller.emojiPickerStore.trackEmoji(
      siteUrl: siteUrl,
      context: EmojiPickerContext.chat,
      emoji: picked,
    ),
  );
  unawaited(
    chat.addMessageReaction(siteUrl, message.id, picked).then((error) {
      if (error == null ||
          !lease.isCurrent ||
          messenger == null ||
          !messenger.mounted) {
        return;
      }
      if (!identical(ShellScope.maybeRead(messenger.context), controller)) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }),
  );
}

class _Reactions extends StatelessWidget {
  const _Reactions({required this.siteUrl, required this.message});

  final String siteUrl;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final chat = PluginScope.require(context, chatControllerService);
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(siteUrl, message.channelId),
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final controller = ShellScope.identityOf(context);
    final chat = PluginScope.require(context, chatControllerService);
    final canAdd = chat.canAddReactionToMessage(siteUrl, message);
    bool canToggle(ChatReaction reaction) => reaction.reacted
        ? chat.canRemoveReactionFromMessage(siteUrl, message)
        : canAdd;

    return ReactionPills(
      key: const ValueKey('chat-reactions'),
      children: [
        for (final reaction in message.reactions)
          ReactionPill(
            key: ValueKey('chat-reaction-pill-${message.id}-${reaction.emoji}'),
            siteUrl: siteUrl,
            reaction: reaction.emoji,
            count: reaction.count,
            selected: reaction.reacted,
            onTapHint: !canToggle(reaction)
                ? 'show who reacted'
                : reaction.reacted
                ? 'remove your reaction'
                : 'add this reaction',
            interactionOwner: controller,
            onToggle: canToggle(reaction)
                ? () => chat.toggleMessageReaction(
                    siteUrl,
                    message.id,
                    reaction.emoji,
                  )
                : null,
            loadReactors: () => chat.loadMessageReactors(
              siteUrl: siteUrl,
              channelId: message.channelId,
              messageId: message.id,
              filter: reaction.emoji,
            ),
            reactorsBuilder: (_) => _ChatReactorList(
              siteUrl: siteUrl,
              message: message,
              filter: reaction.emoji,
            ),
            visualKey: ValueKey('chat-reaction-${reaction.emoji}'),
          ),
        if (canAdd)
          ReactionPickerButton(
            key: ValueKey('chat-reaction-picker-${message.id}'),
            onOpenPicker: _pickReaction,
          ),
      ],
    );
  }

  Future<void> _pickReaction(BuildContext context) => _pickChatMessageReaction(
    context: context,
    siteUrl: siteUrl,
    message: message,
  );
}

/// Chat's API adapter into the same reactor list topic posts use.
class _ChatReactorList extends StatelessWidget {
  const _ChatReactorList({
    required this.siteUrl,
    required this.message,
    required this.filter,
  });

  final String siteUrl;
  final ChatMessage message;
  final String filter;

  @override
  Widget build(BuildContext context) =>
      PluginServiceSelector<ChatController, ChatController>(
        service: chatControllerService,
        select: (controller) => controller,
        builder: (context, chat, child) {
          return ReactionUsersList(
            siteUrl: siteUrl,
            source: chat,
            query: (
              siteUrl: siteUrl,
              channelId: message.channelId,
              messageId: message.id,
              filter: filter,
            ),
            select: () => (
              reactors: chat.messageReactors(
                siteUrl,
                message.channelId,
                message.id,
                filter: filter,
              ),
              error: chat.messageReactorsError(
                siteUrl,
                message.channelId,
                message.id,
                filter: filter,
              ),
            ),
            load: () => chat.loadMessageReactors(
              siteUrl: siteUrl,
              channelId: message.channelId,
              messageId: message.id,
              filter: filter,
            ),
          );
        },
      );
}

/// The latest activity behind a message that started a thread.
///
/// One target owns the whole card. Its compact names, avatars, count and
/// excerpt are context for that action rather than separate profile controls.
class _ThreadSummaryCard extends StatelessWidget {
  const _ThreadSummaryCard({
    required this.siteUrl,
    required this.thread,
    required this.onOpen,
  });

  final String siteUrl;
  final ChatThreadPreview thread;
  final VoidCallback? onOpen;

  static const double _maximumWidth = 600;
  static const double _minimumHeight = 44;
  static const double _latestAvatarSize = 32;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(10);
    final label = _semanticsLabel;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maximumWidth),
        child: SizedBox(
          width: double.infinity,
          child: Semantics(
            key: ChatMessageTile.threadPreviewKey(thread.threadId),
            container: true,
            link: onOpen != null,
            label: label,
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                mouseCursor: onOpen == null
                    ? MouseCursor.defer
                    : SystemMouseCursors.click,
                borderRadius: radius,
                hoverColor: theme.shell.hover,
                focusColor: theme.shell.hover,
                onTap: onOpen,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: _minimumHeight),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: ExcludeSemantics(
                      child: _ThreadSummaryContents(
                        siteUrl: siteUrl,
                        thread: thread,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _semanticsLabel {
    final replies = _replyCountLabel(thread.replyCount);
    final user = thread.lastReplyUser;
    final name =
        _nonEmpty(user?.displayName) ?? _nonEmpty(thread.lastReplyUsername);
    final excerpt = _nonEmpty(thread.lastReplyExcerpt);
    final time = switch (thread.lastReplyAt) {
      final at? => relativeTime(at),
      null => null,
    };
    final participants = _participantTotal(thread);

    final label = StringBuffer('Open thread with $replies.');
    if (name != null || excerpt != null || time != null) {
      label.write(' Latest reply');
      if (name != null) label.write(' from $name');
      if (time != null) label.write(', $time');
      if (excerpt != null) label.write(': $excerpt');
      label.write('.');
    }
    if (participants > 0) {
      label.write(
        ' $participants ${participants == 1 ? 'participant' : 'participants'}.',
      );
    }
    return label.toString();
  }
}

class _ThreadSummaryContents extends StatelessWidget {
  const _ThreadSummaryContents({required this.siteUrl, required this.thread});

  final String siteUrl;
  final ChatThreadPreview thread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = thread.lastReplyUser;
    final name =
        _nonEmpty(user?.displayName) ?? _nonEmpty(thread.lastReplyUsername);
    final avatarUrl = user?.avatarUrl ?? thread.lastReplyAvatarUrl;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChatUserAvatar(
          siteUrl: siteUrl,
          userId: user?.id ?? 0,
          url: avatarUrl,
          size: _ThreadSummaryCard._latestAvatarSize,
          fallback: _AvatarFallback(
            name: name,
            background: theme.shell.floating,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (name != null)
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (name != null && thread.lastReplyAt != null)
                          const SizedBox(width: 4),
                        if (thread.lastReplyAt case final at?)
                          Text(
                            relativeTime(at),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.discourse.primaryHigh,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_participantTotal(thread) > 0) ...[
                    const SizedBox(width: 8),
                    _ThreadParticipants(siteUrl: siteUrl, thread: thread),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    _replyCountLabel(thread.replyCount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (_nonEmpty(thread.lastReplyExcerpt) case final excerpt?) ...[
                const SizedBox(height: 2),
                Text(
                  excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ThreadParticipants extends StatelessWidget {
  const _ThreadParticipants({required this.siteUrl, required this.thread});

  final String siteUrl;
  final ChatThreadPreview thread;

  static const double _avatarSize = 22;
  static const double _avatarStep = 14;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final users = _visibleParticipants(thread.participantUsers);
    final hidden = (_participantTotal(thread) - users.length).clamp(0, 1 << 31);
    final stackWidth = users.isEmpty
        ? 0.0
        : _avatarSize + ((users.length - 1) * _avatarStep);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (users.isNotEmpty)
          SizedBox(
            width: stackWidth,
            height: _avatarSize,
            child: Stack(
              children: [
                for (final (index, user) in users.indexed)
                  Positioned(
                    left: index * _avatarStep,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(1),
                        child: ChatUserAvatar(
                          siteUrl: siteUrl,
                          userId: user.id,
                          url: user.avatarUrl,
                          size: _avatarSize - 4,
                          fallback: _AvatarFallback(
                            name: user.displayName,
                            background: theme.shell.floating,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (hidden > 0) ...[
          if (users.isNotEmpty) const SizedBox(width: 4),
          Text(
            '+$hidden',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.name, required this.background});

  final String? name;
  final Color background;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: background,
    child: Center(
      child: Text(
        switch (_nonEmpty(name)) {
          final name? => name.characters.first.toUpperCase(),
          null => '?',
        },
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

String _replyCountLabel(int count) => count == 1 ? '1 reply' : '$count replies';

String? _nonEmpty(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

int _participantTotal(ChatThreadPreview thread) {
  final serialized = thread.participantUsers.length;
  final reported = thread.participantCount ?? serialized;
  return reported < serialized ? serialized : reported;
}

List<ChatMessageAuthor> _visibleParticipants(
  List<ChatMessageAuthor> participants,
) => participants.length <= 3
    ? participants
    : [participants[0], participants[1], participants.last];

DIconData _bookmarkIcon(Bookmark? bookmark) {
  if (bookmark == null) return DIcons.farBookmark;
  return bookmark.reminderAt == null
      ? DIcons.bookmark
      : DIcons.discourseBookmarkClock;
}

/// The same shape `TopicView` gives a post's staff tag.
class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, this.isBot = false});

  final String label;
  final Color color;
  final bool isBot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: isBot
            ? Theme.of(context).colorScheme.surfaceContainerHigh
            : color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isBot ? label.toUpperCase() : label,
        style: isBot
            ? TextStyle(
                color: color,
                fontSize: DiscourseTypography.fontDown3,
                height: DiscourseTypography.lineHeightMedium,
                fontWeight: FontWeight.w700,
                letterSpacing: DiscourseTypography.fontDown3 * 0.1,
              )
            : Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
