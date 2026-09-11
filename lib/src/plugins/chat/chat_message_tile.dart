import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../models/bookmark.dart';
import '../../models/post_flag.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../shell/cooked_html.dart';
import '../../shell/emoji_picker.dart';
import '../../shell/hover_action_toolbar.dart';
import '../../shell/platform.dart';
import '../../shell/post_flag_editor.dart';
import '../../shell/reaction_presentation.dart';
import '../../shell/relative_time.dart';
import '../../shell/route_aware_selection_area.dart';
import '../../shell/shell_sheet.dart';
import '../../shell/site_emoji_text.dart';
import '../../shell/user_card.dart';
import '../../shell/user_status.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_bookmark_ui.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_emoji_usage.dart';
import 'chat_message.dart';
import 'chat_preview.dart';
import 'chat_preview_body.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';
import 'chat_uploads.dart';
import 'chat_user_avatar.dart';

class ChatMessageTile extends StatelessWidget {
  const ChatMessageTile({
    super.key,
    required this.siteUrl,
    required this.messageId,
    required this.chained,
    this.endsGroup = true,
    this.contextThreadId,
    this.onOpenThread,
    this.onJumpToMessage,
    this.onReply,
    this.onEdit,
    this.showThreadSummary = true,
    this.onSelect,
    this.selecting = false,
    this.selected = false,
    this.onSelectedChanged,
  });

  final String siteUrl;
  final int messageId;

  /// Pane context, rather than the message's thread id, determines core's share URL.
  final int? contextThreadId;

  final bool chained;

  /// Whether this is the last visible message in a consecutive-sender run.
  /// DMs share their timestamp and optional avatar here; channel rows ignore it.
  final bool endsGroup;

  final ValueChanged<ChatThreadPreview>? onOpenThread;

  final ValueChanged<int>? onJumpToMessage;

  final ValueChanged<ChatMessage>? onReply;

  final ValueChanged<ChatMessage>? onEdit;

  /// Thread views suppress the original message's recursive thread summary.
  final bool showThreadSummary;
  final VoidCallback? onSelect;
  final bool selecting;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  static const double gutter = 42;

  static const double minimumUnchainedHeight = 58;

  static const double minimumChainedHeight = 28;

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

  static Key timestampKey(int messageId) =>
      ValueKey<String>('chat-message-timestamp-$messageId');

  static Key bodySelectionKey(int messageId) =>
      ValueKey<String>('chat-message-body-selection-$messageId');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatMessage?>(
      valueListenable: PluginUiScope.require(
        context,
        chatControllerService,
      ).messageRef(siteUrl, messageId),
      builder: (context, message, _) {
        // The stream may lag one frame behind permanent deletion.
        if (message == null) return const SizedBox.shrink();
        Widget tile([Widget? directMessageActions]) => _Tile(
          siteUrl: siteUrl,
          message: message,
          chained: chained,
          endsGroup: endsGroup,
          onOpenThread: onOpenThread,
          onJumpToMessage: onJumpToMessage,
          showThreadSummary: showThreadSummary,
          directMessageActions: directMessageActions,
        );
        if (selecting) {
          return Semantics(
            selected: selected,
            label: 'Select chat message ${message.id}',
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: DCheckbox(
                    key: ValueKey('chat-message-selector-${message.id}'),
                    semanticLabel: 'Select message ${message.id}',
                    value: selected,
                    onChanged: onSelectedChanged == null
                        ? null
                        : (value) => onSelectedChanged!(value ?? false),
                  ),
                ),
                Expanded(child: tile()),
              ],
            ),
          );
        }
        final chat = PluginUiScope.require(context, chatControllerService);
        final canReply =
            onReply != null &&
            contextThreadId == null &&
            chat.canReplyToMessage(siteUrl, message);
        final canBookmark = chat.canBookmarkMessage(siteUrl, message);
        final canEdit = onEdit != null && chat.canEditMessage(siteUrl, message);
        final canDelete = chat.canDeleteMessage(siteUrl, message);
        final canRestore = chat.canRestoreMessage(siteUrl, message);
        final canPin = chat.canPinMessage(siteUrl, message);
        final canRebake = chat.canRebakeMessage(siteUrl, message);
        final canAddReaction = chat.canAddReactionToMessage(siteUrl, message);
        final flagTypes = chat.availableChatFlagTypes(
          siteUrl,
          message,
          PluginUiScope.require(
            context,
            chatShellService,
          ).postFlagTypesFor(siteUrl),
        );
        final canCopyLink = message.id > 0 && !message.isOptimistic;
        final canCopyText =
            message.raw.isNotEmpty &&
            switch (Theme.of(context).platform) {
              TargetPlatform.android || TargetPlatform.iOS => true,
              _ => false,
            };
        return canReply ||
                canBookmark ||
                canEdit ||
                canDelete ||
                canRestore ||
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
                onReply: canReply ? () => onReply!(message) : null,
                onEdit: onEdit,
                canBookmark: canBookmark,
                canCopyLink: canCopyLink,
                canCopyText: canCopyText,
                flagTypes: flagTypes,
                onSelect: onSelect,
                childBuilder: tile,
              )
            : tile();
      },
    );
  }
}

class _OpenChatMessageActionsIntent extends Intent {
  const _OpenChatMessageActionsIntent();
}

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
    required this.childBuilder,
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
  final Widget Function(Widget? directMessageActions) childBuilder;

  @override
  State<_ChatMessageActions> createState() => _ChatMessageActionsState();
}

class _ChatMessageActionsState extends State<_ChatMessageActions> {
  final _dropdown = DDropdownMenuController();
  bool _focused = false;
  bool _hovered = false;
  bool _hoverSuppressed = false;
  bool _pointerInside = false;
  bool _moreActionsOpen = false;
  bool _pinning = false;
  bool _rebaking = false;
  bool _restoring = false;
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
    _moreActionsOpen = false;
    if (!_hovered && !_dropdown.isOpen) return;
    _hovered = false;

    void refresh() {
      if (!mounted) return;
      _dropdown.close();
      setState(() {});
    }

    // New viewport dimensions can start a scroll activity during layout.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        refresh();
      });
      return;
    }
    refresh();
  }

  void _pointerEntered() {
    _pointerInside = true;
    if (_hoverSuppressed || _hovered) return;
    setState(() => _hovered = true);
  }

  void _pointerMoved() {
    _pointerInside = true;
    if (_scroll?.isScrollingNotifier.value == true) return;
    _hoverSuppressed = false;
    if (!_hovered) setState(() => _hovered = true);
  }

  void _pointerExited() {
    _pointerInside = false;
    if (_moreActionsOpen) return;
    if (_hovered) setState(() => _hovered = false);
  }

  void _moreActionsOpened() {
    _moreActionsOpen = true;
  }

  void _moreActionsClosed() {
    _moreActionsOpen = false;
    if (!_pointerInside && _hovered) setState(() => _hovered = false);
  }

  @override
  void dispose() {
    _detachScroll();
    _dropdown.dispose();
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
    DToast.show(context, message);
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
    DToast.show(context, notice);
  }

  Future<void> _bookmark() => showChatMessageBookmarkMenu(
    context: context,
    host: PluginUiScope.require(context, chatBookmarkHostService),
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
    final chat = PluginUiScope.require(context, chatControllerService);
    final error = await chat.deleteMessage(widget.siteUrl, widget.message.id);
    if (!mounted || error == null) return;
    DToast.show(context, error, type: DToastType.error);
  }

  Future<void> _restore() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    final chat = PluginUiScope.require(context, chatControllerService);
    final error = await chat.restoreMessage(widget.siteUrl, widget.message.id);
    if (!mounted) return;
    setState(() => _restoring = false);
    if (error == null) return;
    DToast.show(context, error, type: DToastType.error);
  }

  Future<void> _togglePin() async {
    if (_pinning) return;
    setState(() => _pinning = true);
    final chat = PluginUiScope.require(context, chatControllerService);
    final error = await chat.setMessagePinned(
      widget.siteUrl,
      widget.message.id,
      pinned: !widget.message.pinned,
    );
    if (!mounted) return;
    setState(() => _pinning = false);
    if (error == null) return;
    DToast.show(context, error, type: DToastType.error);
  }

  Future<void> _rebake() async {
    if (_rebaking) return;
    setState(() => _rebaking = true);
    final chat = PluginUiScope.require(context, chatControllerService);
    final error = await chat.rebakeMessage(widget.siteUrl, widget.message.id);
    if (!mounted) return;
    setState(() => _rebaking = false);
    DToast.show(
      context,
      error ?? 'HTML rebuild queued.',
      type: error == null ? DToastType.success : DToastType.error,
    );
  }

  Future<void> _flag(List<PostFlagType> flagTypes) async {
    final chat = PluginUiScope.require(context, chatControllerService);
    await showShellSheet<void>(
      context: context,
      title: 'Thanks for keeping our community civil!',
      dialogOnDesktop: true,
      builder: (sheetContext) => PostFlagEditor(
        siteUrl: widget.siteUrl,
        targetUsername: widget.message.author.username,
        flagTypes: flagTypes,
        minimumMessageLength: chat.flagMessageMinimumLength(widget.siteUrl),
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
    final bookmarkHost = PluginUiScope.require(
      context,
      chatBookmarkHostService,
    );
    final chat = PluginUiScope.require(context, chatControllerService);
    final canEdit = chat.canEditMessage(widget.siteUrl, widget.message);
    final canDelete = chat.canDeleteMessage(widget.siteUrl, widget.message);
    final canRestore = chat.canRestoreMessage(widget.siteUrl, widget.message);
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
    final bookmarkBusy = bookmarkHost.bookmarkWriteInFlight(
      siteUrl: widget.siteUrl,
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
              title: const Text('Reply'),
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
                  ? const SizedBox.square(dimension: 18, child: DSpinner())
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
                  ? const SizedBox.square(dimension: 18, child: DSpinner())
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
          if (canRestore)
            ListTile(
              minTileHeight: 52,
              leading: _restoring
                  ? const SizedBox.square(dimension: 18, child: DSpinner())
                  : const DIcon(DIcons.arrowRotateLeft, size: 18),
              title: const Text('Restore deleted message'),
              subtitle: _restoring ? const Text('Restoring…') : null,
              enabled: !_restoring,
              onTap: _restoring
                  ? null
                  : () {
                      Navigator.of(sheetContext).pop();
                      unawaited(_restore());
                    },
            ),
          if (canRebake)
            ListTile(
              minTileHeight: 52,
              leading: _rebaking
                  ? const SizedBox.square(dimension: 18, child: DSpinner())
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

  void _runDropdownAction(VoidCallback action) {
    _dropdown.close();
    // Let the menu restore focus before an action opens another overlay or
    // moves focus to the composer. The message remains the callback owner.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  Widget _directMessageDropdown({
    required bool bookmarkBusy,
    required bool canAddReaction,
    required bool canEdit,
    required bool canDelete,
    required bool canRestore,
    required bool canPin,
    required bool canRebake,
    required List<PostFlagType> flagTypes,
  }) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final canReply =
        widget.onReply != null &&
        chat.canReplyToMessage(widget.siteUrl, widget.message);
    final canBookmark = chat.canBookmarkMessage(widget.siteUrl, widget.message);
    Widget item(
      String name,
      String label,
      DIconData icon,
      VoidCallback action, {
      bool busy = false,
      bool destructive = false,
    }) => DDropdownMenuItem(
      key: ValueKey('chat-message-$name-${widget.message.id}'),
      leading: busy ? const DSpinner() : DIcon(icon, size: 16),
      onPressed: busy ? null : () => _runDropdownAction(action),
      closeOnSelect: false,
      variant: destructive
          ? DDropdownMenuItemVariant.destructive
          : DDropdownMenuItemVariant.standard,
      child: Text(label),
    );

    return EmojiPickerAnchor(
      child: Builder(
        builder: (anchorContext) => DDropdownMenu(
          controller: _dropdown,
          onOpenChange: (open, _) {
            setState(() {
              _moreActionsOpen = open;
              if (!open && !_pointerInside) _hovered = false;
            });
          },
          content: DDropdownMenuContent(
            semanticLabel: 'Message actions',
            align: DPopoverAlign.end,
            width: 220,
            children: [
              if (canReply) item('reply', 'Reply', DIcons.reply, _reply),
              if (canAddReaction)
                item(
                  'react',
                  'Add reaction',
                  DIcons.farFaceSmile,
                  () => unawaited(_pickReaction(anchorContext)),
                  busy: _reactionPickerOpening,
                ),
              if (canBookmark)
                item(
                  'bookmark',
                  widget.message.bookmark == null
                      ? 'Bookmark'
                      : 'Edit bookmark',
                  _bookmarkIcon(widget.message.bookmark),
                  () => unawaited(_bookmark()),
                  busy: bookmarkBusy,
                ),
              if (canPin)
                item(
                  'pin',
                  widget.message.pinned ? 'Unpin' : 'Pin',
                  DIcons.thumbtack,
                  () => unawaited(_togglePin()),
                  busy: _pinning,
                ),
              if (widget.canCopyLink)
                item(
                  'copy-link',
                  'Copy link',
                  DIcons.link,
                  () => unawaited(_copyLink()),
                ),
              if (widget.canCopyText)
                item(
                  'copy-text',
                  'Copy text',
                  DIcons.copy,
                  () => unawaited(_copyText()),
                ),
              if (canEdit && widget.onEdit != null)
                item('edit', 'Edit', DIcons.pencil, _edit),
              if (flagTypes.isNotEmpty)
                item(
                  'flag',
                  'Flag',
                  DIcons.flag,
                  () => unawaited(_flag(flagTypes)),
                ),
              if (canRestore)
                item(
                  'restore',
                  'Restore deleted message',
                  DIcons.arrowRotateLeft,
                  () => unawaited(_restore()),
                  busy: _restoring,
                ),
              if (canRebake)
                item(
                  'rebake',
                  'Rebuild HTML',
                  DIcons.arrowsRotate,
                  () => unawaited(_rebake()),
                  busy: _rebaking,
                ),
              if (canDelete)
                item(
                  'delete',
                  'Delete',
                  DIcons.trashCan,
                  () => unawaited(_delete()),
                  destructive: true,
                ),
              if (widget.onSelect case final select?)
                item('select', 'Select', DIcons.list, select),
            ],
          ),
          child: DDropdownMenuTrigger(
            builder: (context, state) {
              final visible =
                  _moreActionsOpen ||
                  (!_hoverSuppressed && (_hovered || _focused));
              // Preserve the trailing slot and keyboard access while hidden;
              // the trigger becomes visible when the message receives focus.
              return Opacity(
                opacity: visible ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !visible,
                  child: ExcludeSemantics(
                    excluding: !visible,
                    child: DButton.iconOnly(
                      key: ValueKey(
                        'chat-message-more-actions-${widget.message.id}',
                      ),
                      tooltip: 'More message actions',
                      icon: const DIcon(DIcons.chevronDown, size: 16),
                      size: DButtonSize.extraSmall,
                      variant: DButtonVariant.secondary,
                      focusNode: state.focusNode,
                      hasPopup: true,
                      expanded: state.open,
                      onPressed: state.toggle,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final bookmarkHost = PluginUiScope.require(
      context,
      chatBookmarkHostService,
    );
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(
        widget.siteUrl,
        widget.message.channelId,
      ),
      builder: (context, channel, _) => ValueListenableBuilder<bool>(
        valueListenable: bookmarkHost.bookmarkWriteInFlightListenable(
          siteUrl: widget.siteUrl,
          targetId: widget.message.id,
        ),
        builder: (context, bookmarkBusy, _) {
          return _build(
            context,
            useDropdown: channel?.isDirectMessage == true && !context.isTouch,
            bookmarkBusy: bookmarkBusy,
            canEdit: chat.canEditMessage(widget.siteUrl, widget.message),
            canDelete: chat.canDeleteMessage(widget.siteUrl, widget.message),
            canRestore: chat.canRestoreMessage(widget.siteUrl, widget.message),
            canPin: chat.canPinMessage(widget.siteUrl, widget.message),
            canRebake: chat.canRebakeMessage(widget.siteUrl, widget.message),
            flagTypes: chat.availableChatFlagTypes(
              widget.siteUrl,
              widget.message,
              widget.flagTypes,
            ),
          );
        },
      ),
    );
  }

  Widget _build(
    BuildContext context, {
    required bool useDropdown,
    required bool bookmarkBusy,
    required bool canEdit,
    required bool canDelete,
    required bool canRestore,
    required bool canPin,
    required bool canRebake,
    required List<PostFlagType> flagTypes,
  }) {
    final bookmarkLabel = widget.message.bookmark == null
        ? 'Bookmark'
        : 'Edit bookmark';
    final chat = PluginUiScope.require(context, chatControllerService);
    final canAddReaction = chat.canAddReactionToMessage(
      widget.siteUrl,
      widget.message,
    );
    final hasSecondaryActions =
        widget.canCopyLink ||
        canEdit ||
        widget.onSelect != null ||
        canPin ||
        flagTypes.isNotEmpty ||
        canDelete ||
        canRestore ||
        canRebake;
    final semanticsActions = <CustomSemanticsAction, VoidCallback>{
      if (canAddReaction && !_reactionPickerOpening)
        const CustomSemanticsAction(label: 'Add reaction'): () =>
            unawaited(_pickReaction()),
      if (widget.onReply != null)
        const CustomSemanticsAction(label: 'Reply'): _reply,
      if (widget.canCopyLink)
        const CustomSemanticsAction(label: 'Copy link'): () =>
            unawaited(_copyLink()),
      if (canEdit) const CustomSemanticsAction(label: 'Edit'): _edit,
      if (widget.onSelect != null)
        const CustomSemanticsAction(label: 'Select'): widget.onSelect!,
      if (canDelete)
        const CustomSemanticsAction(label: 'Delete'): () =>
            unawaited(_delete()),
      if (canRestore && !_restoring)
        const CustomSemanticsAction(label: 'Restore deleted message'): () =>
            unawaited(_restore()),
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
                  if (useDropdown) {
                    _dropdown.open(DPopoverInteraction.keyboard);
                  } else {
                    unawaited(_showActions());
                  }
                  return null;
                },
              ),
        },
        child: Focus(
          key: widget.focusKey,
          onFocusChange: useDropdown
              ? (focused) {
                  if (mounted && _focused != focused) {
                    setState(() => _focused = focused);
                  }
                }
              : null,
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
                onSecondaryTap: useDropdown
                    ? () => _dropdown.open(DPopoverInteraction.mouse)
                    : () => unawaited(_showActions()),
                child: Stack(
                  // Desktop action targets may be taller than chained rows.
                  clipBehavior: Clip.none,
                  children: [
                    widget.childBuilder(
                      useDropdown
                          ? _directMessageDropdown(
                              bookmarkBusy: bookmarkBusy,
                              canAddReaction: canAddReaction,
                              canEdit: canEdit,
                              canDelete: canDelete,
                              canRestore: canRestore,
                              canPin: canPin,
                              canRebake: canRebake,
                              flagTypes: flagTypes,
                            )
                          : null,
                    ),
                    if (_hovered && !useDropdown)
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
                            if (widget.canBookmark)
                              HoverActionButton(
                                tooltip: bookmarkLabel,
                                onPressed: bookmarkBusy
                                    ? null
                                    : () => unawaited(_bookmark()),
                                color: widget.message.bookmark == null
                                    ? null
                                    : Theme.of(context).colorScheme.primary,
                                icon: bookmarkBusy
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: DSpinner(),
                                      )
                                    : DIcon(
                                        _bookmarkIcon(widget.message.bookmark),
                                        size: 16,
                                      ),
                              ),
                            if (widget.onReply != null)
                              HoverActionButton(
                                tooltip: 'Reply',
                                onPressed: _reply,
                                icon: const DIcon(DIcons.reply, size: 16),
                              ),
                            if (hasSecondaryActions)
                              MenuAnchor(
                                alignmentOffset: const Offset(0, 4),
                                onOpen: _moreActionsOpened,
                                onClose: _moreActionsClosed,
                                style: MenuStyle(
                                  backgroundColor: WidgetStatePropertyAll(
                                    Theme.of(context).shell.floating,
                                  ),
                                  surfaceTintColor:
                                      const WidgetStatePropertyAll(
                                        Colors.transparent,
                                      ),
                                  maximumSize: const WidgetStatePropertyAll(
                                    Size(300, 440),
                                  ),
                                ),
                                menuChildren: [
                                  if (widget.canCopyLink)
                                    MenuItemButton(
                                      key: ValueKey(
                                        'chat-message-copy-link-${widget.message.id}',
                                      ),
                                      onPressed: () => unawaited(_copyLink()),
                                      leadingIcon: const DIcon(
                                        DIcons.link,
                                        size: 16,
                                      ),
                                      child: const Text('Copy link'),
                                    ),
                                  if (canEdit)
                                    MenuItemButton(
                                      key: ValueKey(
                                        'chat-message-edit-${widget.message.id}',
                                      ),
                                      onPressed: _edit,
                                      leadingIcon: const DIcon(
                                        DIcons.pencil,
                                        size: 16,
                                      ),
                                      child: const Text('Edit'),
                                    ),
                                  if (widget.onSelect != null)
                                    MenuItemButton(
                                      key: ValueKey(
                                        'chat-message-select-${widget.message.id}',
                                      ),
                                      onPressed: widget.onSelect,
                                      leadingIcon: const DIcon(
                                        DIcons.list,
                                        size: 16,
                                      ),
                                      child: const Text('Select'),
                                    ),
                                  if (canPin)
                                    MenuItemButton(
                                      key: ValueKey(
                                        'chat-message-pin-${widget.message.id}',
                                      ),
                                      onPressed: _pinning
                                          ? null
                                          : () => unawaited(_togglePin()),
                                      leadingIcon: _pinning
                                          ? const SizedBox.square(
                                              dimension: 16,
                                              child: DSpinner(),
                                            )
                                          : const DIcon(
                                              DIcons.thumbtack,
                                              size: 16,
                                            ),
                                      child: Text(
                                        widget.message.pinned ? 'Unpin' : 'Pin',
                                      ),
                                    ),
                                  if (flagTypes.isNotEmpty)
                                    MenuItemButton(
                                      key: ValueKey(
                                        'chat-message-flag-${widget.message.id}',
                                      ),
                                      onPressed: () =>
                                          unawaited(_flag(flagTypes)),
                                      leadingIcon: const DIcon(
                                        DIcons.flag,
                                        size: 16,
                                      ),
                                      child: const Text('Flag'),
                                    ),
                                  if (canDelete)
                                    MenuItemButton(
                                      key: ValueKey(
                                        'chat-message-delete-${widget.message.id}',
                                      ),
                                      onPressed: () => unawaited(_delete()),
                                      leadingIcon: const DIcon(
                                        DIcons.trashCan,
                                        size: 16,
                                      ),
                                      style: MenuItemButton.styleFrom(
                                        foregroundColor: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                        iconColor: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                      child: const Text('Delete'),
                                    ),
                                  if (canRestore)
                                    MenuItemButton(
                                      key: ValueKey(
                                        'chat-message-restore-${widget.message.id}',
                                      ),
                                      onPressed: _restoring
                                          ? null
                                          : () => unawaited(_restore()),
                                      leadingIcon: _restoring
                                          ? const SizedBox.square(
                                              dimension: 16,
                                              child: DSpinner(),
                                            )
                                          : const DIcon(
                                              DIcons.arrowRotateLeft,
                                              size: 16,
                                            ),
                                      child: const Text(
                                        'Restore deleted message',
                                      ),
                                    ),
                                  if (canRebake)
                                    MenuItemButton(
                                      key: ValueKey(
                                        'chat-message-rebake-${widget.message.id}',
                                      ),
                                      onPressed: _rebaking
                                          ? null
                                          : () => unawaited(_rebake()),
                                      leadingIcon: _rebaking
                                          ? const SizedBox.square(
                                              dimension: 16,
                                              child: DSpinner(),
                                            )
                                          : const DIcon(
                                              DIcons.arrowsRotate,
                                              size: 16,
                                            ),
                                      child: const Text('Rebuild HTML'),
                                    ),
                                ],
                                builder: (context, menu, child) =>
                                    HoverActionButton(
                                      key: ValueKey(
                                        'chat-message-more-actions-${widget.message.id}',
                                      ),
                                      tooltip: 'More message actions',
                                      onPressed: menu.isOpen
                                          ? menu.close
                                          : menu.open,
                                      icon: const DIcon(
                                        DIcons.ellipsisVertical,
                                        size: 16,
                                      ),
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
    required this.endsGroup,
    required this.onOpenThread,
    required this.onJumpToMessage,
    required this.showThreadSummary,
    this.directMessageActions,
  });

  final String siteUrl;
  final ChatMessage message;
  final bool chained;
  final bool endsGroup;
  final ValueChanged<ChatThreadPreview>? onOpenThread;
  final ValueChanged<int>? onJumpToMessage;
  final bool showThreadSummary;
  final Widget? directMessageActions;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(siteUrl, message.channelId),
      builder: (context, channel, _) {
        if (channel?.isDirectMessage != true) return _channelMessage(context);
        return PluginServiceSelector<ChatController, int?>(
          service: chatControllerService,
          select: (chat) => chat.currentUserFor(siteUrl)?.id,
          builder: (context, userId, _) => _directMessage(
            context,
            outgoing: userId != null && userId == message.author.id,
            showIdentity: channel!.isGroup,
          ),
        );
      },
    );
  }

  Widget? _body(
    BuildContext context, {
    TextStyle? textStyle,
    TextStyle? linkStyle,
    bool contentSized = false,
  }) {
    final messageTextStyle = textStyle ?? Theme.of(context).textTheme.bodyLarge;
    return switch (message) {
      ChatMessage(canonicalReceived: true, cooked: final cooked)
          when cooked.isNotEmpty =>
        CookedHtml(
          html: cooked,
          textStyle: messageTextStyle,
          linkStyle: linkStyle,
          siteUrl: siteUrl,
          compactParagraphs: true,
          contentSized: contentSized,
          mentionedUserStatuses: message.mentionedUserStatuses,
        ),
      ChatMessage(
        canonicalReceived: false,
        preview: ProjectedPreview(:final document),
      ) =>
        ChatPreviewBody(
          document: document,
          textStyle: messageTextStyle,
          previewEngine: PluginUiScope.require(
            context,
            chatControllerService,
          ).previewEngine,
        ),
      ChatMessage(
        canonicalReceived: false,
        optimisticRaw: final raw?,
        preview: final preview,
      )
          when preview is! ProjectedPreview =>
        Text(raw, style: messageTextStyle),
      _ => null,
    };
  }

  Widget _channelMessage(BuildContext context) {
    final theme = Theme.of(context);
    final messageBody = _body(context);

    final tile = Padding(
      key: ValueKey('chat-message-${message.id}'),
      // Match core's speaker and chained-message spacing.
      padding: EdgeInsets.fromLTRB(16, chained ? 2.4 : 10.4, 16, 2.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.replyTo case final reply? when !chained)
            _ReplyIndicator(
              siteUrl: siteUrl,
              reply: reply,
              onJump: onJumpToMessage == null
                  ? null
                  : () => onJumpToMessage!(reply.id),
            ),
          DMessage(
            avatarAlignment: DMessageAvatarAlignment.top,
            spacing: 0,
            children: [
              DMessageAvatar(
                minimumExtent: 0,
                shiftForFooter: false,
                child: SizedBox(
                  width: ChatMessageTile.gutter,
                  // Align loosens the gutter's tight width before sizing the
                  // avatar; SizedBox alone would be clamped back to gutter width.
                  child: chained
                      ? const SizedBox.shrink()
                      : Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: UserCardTarget.avatar(
                              username: message.author.username,
                              siteUrl: siteUrl,
                              semanticLabel: message.author.flair == null
                                  ? null
                                  : 'View profile for @${message.author.username}, ${message.author.flair!.label}',
                              child: ChatUserAvatar(
                                siteUrl: siteUrl,
                                userId: message.author.id,
                                url: message.author.avatarUrl,
                                flair: message.author.flair,
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
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
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
              ),
              DMessageContent(
                spacing: 0,
                alignChildren: false,
                flushMetadata: true,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!chained)
                              _Header(siteUrl: siteUrl, message: message),
                            if (messageBody != null)
                              _MessageBodySelection(
                                selectionKey: ChatMessageTile.bodySelectionKey(
                                  message.id,
                                ),
                                child: messageBody,
                              ),
                            if (message.uploads.isNotEmpty)
                              ChatUploads(
                                siteUrl: siteUrl,
                                uploads: message.uploads,
                              ),
                            if (message.edited)
                              Text(
                                key: ChatMessageTile.editedIndicatorKey(
                                  message.id,
                                ),
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

  Widget _directMessage(
    BuildContext context, {
    required bool outgoing,
    required bool showIdentity,
  }) {
    final theme = Theme.of(context);
    final bubbleAlign = outgoing ? DBubbleAlign.end : DBubbleAlign.start;
    final hasBody = message.canonicalReceived
        ? message.cooked.isNotEmpty
        : switch (message.preview) {
            ProjectedPreview(:final document) => document.nodes.isNotEmpty,
            _ => message.optimisticRaw?.isNotEmpty == true,
          };
    final showTimestamp = endsGroup && message.createdAt != null;
    final hasMetadata =
        showTimestamp ||
        message.edited ||
        message.pinned ||
        message.bookmark != null ||
        message.delivery != ChatMessageDelivery.sent;

    return Padding(
      key: ValueKey('chat-message-${message.id}'),
      padding: EdgeInsetsDirectional.fromSTEB(
        DSpacing.lg,
        chained ? DSpacing.sm : DSpacing.lg,
        DSpacing.lg,
        0,
      ),
      child: DMessage(
        align: outgoing ? DMessageAlign.end : DMessageAlign.start,
        children: [
          if (showIdentity)
            DMessageAvatar(
              child: !endsGroup
                  ? null
                  : UserCardTarget.avatar(
                      username: message.author.username,
                      siteUrl: siteUrl,
                      semanticLabel: message.author.flair == null
                          ? null
                          : 'View profile for @${message.author.username}, ${message.author.flair!.label}',
                      child: ChatUserAvatar(
                        siteUrl: siteUrl,
                        userId: message.author.id,
                        url: message.author.avatarUrl,
                        flair: message.author.flair,
                        size: 32,
                        fallback: _AvatarFallback(
                          name: message.author.displayName,
                          background: theme.shell.floating,
                        ),
                      ),
                    ),
            ),
          DMessageContent(
            children: [
              if (showIdentity && !outgoing && !chained)
                DMessageHeader(
                  spacing: DSpacing.xs,
                  children: [
                    UserCardTarget(
                      username: message.author.username,
                      siteUrl: siteUrl,
                      child: Text(message.author.displayName),
                    ),
                    UserStatusMessage(
                      siteUrl: siteUrl,
                      userId: message.author.id,
                      status: message.author.status,
                      size: 15,
                    ),
                    if (message.author.isStaff)
                      _Tag(label: 'staff', color: theme.colorScheme.primary),
                    if (message.isWebhook)
                      _Tag(
                        label: 'bot',
                        color: theme.discourse.primaryVeryHigh,
                        isBot: true,
                      ),
                  ],
                ),
              if (message.replyTo case final reply? when !chained)
                _ReplyIndicator(
                  siteUrl: siteUrl,
                  reply: reply,
                  onJump: onJumpToMessage == null
                      ? null
                      : () => onJumpToMessage!(reply.id),
                  bubbleAlign: bubbleAlign,
                ),
              if (hasBody)
                DBubble(
                  align: bubbleAlign,
                  variant: outgoing
                      ? DBubbleVariant.primary
                      : DBubbleVariant.muted,
                  children: [
                    DBubbleContent(
                      child: Builder(
                        builder: (context) {
                          final style = DefaultTextStyle.of(context).style;
                          final body = _MessageBodySelection(
                            selectionKey: ChatMessageTile.bodySelectionKey(
                              message.id,
                            ),
                            child: _body(
                              context,
                              textStyle: style,
                              contentSized: true,
                              linkStyle: DText.linkStyleOf(context).copyWith(
                                color: outgoing ? style.color : null,
                                decorationColor: outgoing ? style.color : null,
                              ),
                            )!,
                          );
                          return directMessageActions == null
                              ? body
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  spacing: DSpacing.xs,
                                  children: [
                                    Flexible(child: body),
                                    directMessageActions!,
                                  ],
                                );
                        },
                      ),
                    ),
                  ],
                ),
              if (message.uploads.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DSpacing.xs,
                  children: [
                    Flexible(
                      child: ChatUploads(
                        siteUrl: siteUrl,
                        uploads: message.uploads,
                        alignment: outgoing
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                      ),
                    ),
                    if (!hasBody && directMessageActions != null)
                      directMessageActions!,
                  ],
                ),
              if (!hasBody &&
                  message.uploads.isEmpty &&
                  directMessageActions != null)
                directMessageActions!,
              if (message.reactions.isNotEmpty)
                _Reactions(
                  siteUrl: siteUrl,
                  message: message,
                  messageFooter: true,
                ),
              if (message.thread case final thread?
                  when showThreadSummary && thread.replyCount > 0)
                _ThreadSummaryCard(
                  siteUrl: siteUrl,
                  thread: thread,
                  onOpen: onOpenThread == null
                      ? null
                      : () => onOpenThread!(thread),
                  bubbleAlign: bubbleAlign,
                ),
              if (hasMetadata)
                DMessageFooter(
                  spacing: DSpacing.sm,
                  children: [
                    if (message.createdAt case final at? when showTimestamp)
                      Text(
                        relativeTime(at),
                        key: ChatMessageTile.timestampKey(message.id),
                      ),
                    if (message.edited)
                      Text(
                        '(edited)',
                        key: ChatMessageTile.editedIndicatorKey(message.id),
                      ),
                    if (message.pinned)
                      Semantics(
                        label: 'Pinned chat message',
                        child: const DIcon(DIcons.thumbtack, size: 14),
                      ),
                    if (message.bookmark case final bookmark?)
                      Semantics(
                        label: bookmark.reminderAt == null
                            ? 'Bookmarked chat message'
                            : 'Chat message bookmarked with a reminder',
                        child: DIcon(_bookmarkIcon(bookmark), size: 14),
                      ),
                    if (message.delivery == ChatMessageDelivery.sending)
                      const DMessageStatus(
                        state: DMessageDeliveryState.pending,
                      ),
                    if (message.delivery == ChatMessageDelivery.failed)
                      DMessageStatus(
                        state: DMessageDeliveryState.failed,
                        label:
                            message.sendError == null ||
                                message.sendError!.isEmpty
                            ? null
                            : 'Failed to send: ${message.sendError}',
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
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

/// Keeps selectable text out of keyboard traversal.
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
  Widget build(BuildContext context) => RouteAwareSelectionArea(
    selectionAreaKey: widget.selectionKey,
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
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        UserStatusMessage(
          siteUrl: siteUrl,
          userId: message.author.id,
          status: message.author.status,
          size: 15,
          leadingGap: 4,
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

class _ReplyIndicator extends StatelessWidget {
  const _ReplyIndicator({
    required this.siteUrl,
    required this.reply,
    required this.onJump,
    this.bubbleAlign,
  });

  final String siteUrl;
  final ChatReplyTo reply;
  final VoidCallback? onJump;
  final DBubbleAlign? bubbleAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final preview = Row(
      children: [
        DIcon(
          DIcons.share,
          size: DiscourseTypography.sm,
          color: theme.discourse.primaryLowMid,
        ),
        const SizedBox(width: 8),
        ChatUserAvatar(
          siteUrl: siteUrl,
          userId: reply.userId,
          url: reply.avatarUrl,
          flair: reply.flair,
          size: 20,
          fallback: ColoredBox(color: theme.shell.floating),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: SiteEmojiText.plain(
            reply.excerpt,
            siteUrl: siteUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.discourse.primaryHigh,
            ),
          ),
        ),
      ],
    );
    final label =
        'Jump to message from @${reply.username}'
        '${reply.flair == null ? '' : ', ${reply.flair!.label}'}: ${reply.excerpt}';
    if (bubbleAlign case final align?) {
      return DBubble(
        align: align,
        variant: DBubbleVariant.outline,
        children: [
          DBubbleContent(
            key: ChatMessageTile.replyIndicatorKey(reply.id),
            action: DBubbleContentAction.link,
            onPressed: onJump,
            semanticLabel: label,
            child: preview,
          ),
        ],
      );
    }
    return Semantics(
      link: onJump != null,
      enabled: onJump != null,
      label: label,
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
            child: preview,
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
  final chat = PluginUiScope.require(context, chatControllerService);
  final emoji = PluginUiScope.require(context, chatEmojiHostService);
  if (!chat.canAddReactionToMessage(siteUrl, message)) return;
  final lease = chat.captureSession(siteUrl);
  final toast = DToast.maybeOf(context);

  bool stillOwnsMessage() {
    if (!lease.isCurrent) return false;
    if (context.mounted) {
      if (!identical(
        PluginUiScope.maybe(context, chatControllerService),
        chat,
      )) {
        return false;
      }
    }
    return chat.messageRef(siteUrl, message.id).value != null;
  }

  final picked = await showEmojiPicker(
    context: context,
    anchorContext: anchorContext,
    siteUrl: siteUrl,
    pickerContext: chatEmojiUsageContext,
    store: emoji.preferences,
    loadCatalog: ({refresh = false}) =>
        emoji.loadCatalog(siteUrl, refresh: refresh),
    loadSearchAliases: ({refresh = false}) =>
        emoji.loadSearchAliases(siteUrl, refresh: refresh),
  );
  if (picked == null || !stillOwnsMessage()) return;
  final current = chat.messageRef(siteUrl, message.id).value;
  if (current == null || !chat.canAddReactionToMessage(siteUrl, current)) {
    return;
  }

  unawaited(
    emoji.preferences.trackEmoji(
      siteUrl: siteUrl,
      context: chatEmojiUsageContext,
      emoji: picked,
    ),
  );
  unawaited(
    chat.addMessageReaction(siteUrl, message.id, picked).then((error) {
      if (error == null || !stillOwnsMessage() || toast?.isDisposed != false) {
        return;
      }
      toast!.add(DToastOptions(description: error, type: DToastType.error));
    }),
  );
}

class _Reactions extends StatelessWidget {
  const _Reactions({
    required this.siteUrl,
    required this.message,
    this.messageFooter = false,
  });

  final String siteUrl;
  final ChatMessage message;
  final bool messageFooter;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(siteUrl, message.channelId),
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final canAdd = chat.canAddReactionToMessage(siteUrl, message);
    bool canToggle(ChatReaction reaction) => reaction.reacted
        ? chat.canRemoveReactionFromMessage(siteUrl, message)
        : canAdd;

    final children = <Widget>[
      for (final reaction in message.reactions)
        ReactionPill(
          key: ValueKey('chat-reaction-pill-${message.id}-${reaction.emoji}'),
          siteUrl: siteUrl,
          reaction: reaction.emoji,
          count: reaction.count,
          selected: reaction.reacted,
          onTapHint: canToggle(reaction)
              ? reaction.reacted
                    ? 'remove your reaction'
                    : 'add this reaction'
              : null,
          interactionOwner: chat,
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
    ];
    return messageFooter
        ? DMessageFooter(
            key: const ValueKey('chat-reactions'),
            spacing: DSpacing.xs,
            children: children,
          )
        : ReactionPills(
            key: const ValueKey('chat-reactions'),
            children: children,
          );
  }

  Future<void> _pickReaction(BuildContext context) => _pickChatMessageReaction(
    context: context,
    siteUrl: siteUrl,
    message: message,
  );
}

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

class _ThreadSummaryCard extends StatelessWidget {
  const _ThreadSummaryCard({
    required this.siteUrl,
    required this.thread,
    required this.onOpen,
    this.bubbleAlign,
  });

  final String siteUrl;
  final ChatThreadPreview thread;
  final VoidCallback? onOpen;
  final DBubbleAlign? bubbleAlign;

  static const double _maximumWidth = 600;
  static const double _minimumHeight = 44;
  static const double _latestAvatarSize = 32;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(10);
    final label = _semanticsLabel;

    if (bubbleAlign case final align?) {
      return DBubble(
        align: align,
        variant: DBubbleVariant.outline,
        children: [
          DBubbleContent(
            key: ChatMessageTile.threadPreviewKey(thread.threadId),
            action: DBubbleContentAction.link,
            onPressed: onOpen,
            semanticLabel: label,
            child: _ThreadSummaryContents(siteUrl: siteUrl, thread: thread),
          ),
        ],
      );
    }
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
      if (user?.flair case final flair?) label.write(', ${flair.label}');
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
          flair: user?.flair,
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
              OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.start,
                spacing: 8,
                overflowSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
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
                      UserStatusMessage(
                        siteUrl: siteUrl,
                        userId: user?.id,
                        status: user?.status,
                        size: 14,
                        leadingGap: 4,
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_participantTotal(thread) > 0)
                        _ThreadParticipants(siteUrl: siteUrl, thread: thread),
                      Text(
                        _replyCountLabel(thread.replyCount),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (_nonEmpty(thread.lastReplyExcerpt) case final excerpt?) ...[
                const SizedBox(height: 2),
                SiteEmojiText.plain(
                  excerpt,
                  siteUrl: siteUrl,
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
                          flair: user.flair,
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
            ? Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: DiscourseTypography.xs * 0.1,
              )
            : Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
