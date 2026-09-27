import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../models/forum_workspace.dart';
import 'chat_bookmark_ui.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_emoji_usage.dart';
import 'chat_message.dart';
import 'chat_preview.dart';
import 'chat_preview_body.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';
import 'chat_stream_target.dart';
import 'chat_uploads.dart';
import 'chat_user_avatar.dart';

class ChatMessageTile extends StatelessWidget {
  const ChatMessageTile({
    super.key,
    required this.siteUrl,
    required this.messageId,
    required this.chained,
    this.joinsNext = false,
    this.endsGroup = true,
    this.followsReactions = false,
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

  /// Whether the following bubble continues this visible sender run.
  final bool joinsNext;

  /// Whether this is the last visible message in a consecutive-sender run.
  /// Adds breathing room after the final bubble; avatars mark the first row.
  final bool endsGroup;
  final bool followsReactions;

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

  static double hoverActionsHeight(BuildContext context) =>
      hoverActionsTop +
      math.max(
        context.isTouch ? 48 : 0,
        DControlStyle.scaledHeight(
          DControlSize.regular,
          MediaQuery.textScalerOf(context),
          context: context,
        ),
      );

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
        return _MessageAccessScope(
          siteUrl: siteUrl,
          channelId: message.channelId,
          builder: (context) => _row(context, message),
        );
      },
    );
  }

  Widget _row(BuildContext context, ChatMessage message) {
    Widget tile([
      Widget? messageActions,
      Widget? messageReaction,
      Widget? messageReply,
    ]) => _Tile(
      siteUrl: siteUrl,
      message: message,
      chained: chained,
      joinsNext: joinsNext,
      endsGroup: endsGroup,
      followsReactions: followsReactions,
      onOpenThread: onOpenThread,
      onJumpToMessage: onJumpToMessage,
      showThreadSummary: showThreadSummary,
      messageActions: messageActions,
      messageReaction: messageReaction,
      messageReply: messageReply,
    );
    if (selecting) {
      return DMessageSurface(
        child: Semantics(
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
            onReply: onReply != null && contextThreadId == null
                ? () => onReply!(message)
                : null,
            onEdit: onEdit,
            canCopyLink: canCopyLink,
            canCopyText: canCopyText,
            flagTypes: flagTypes,
            onSelect: onSelect,
            childBuilder: tile,
          )
        : DMessageSurface(child: tile());
  }
}

/// Redraws a message row when its channel changes what the reader may do with
/// the message, and never for the rest of the channel record: the reader's
/// dwell replaces that record every half second while reading, and redrawing
/// each held row for it rebuilt every message's HTML.
class _MessageAccessScope extends StatefulWidget {
  const _MessageAccessScope({
    required this.siteUrl,
    required this.channelId,
    required this.builder,
  });

  final String siteUrl;
  final int channelId;
  final WidgetBuilder builder;

  @override
  State<_MessageAccessScope> createState() => _MessageAccessScopeState();
}

class _MessageAccessScopeState extends State<_MessageAccessScope> {
  ValueListenable<ChatChannel?>? _channel;
  ChatMessageAccess? _access;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watchChannel();
  }

  @override
  void didUpdateWidget(_MessageAccessScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.channelId != widget.channelId) {
      _watchChannel();
    }
  }

  void _watchChannel() {
    final channel = PluginUiScope.require(
      context,
      chatControllerService,
    ).channelRef(widget.siteUrl, widget.channelId);
    if (identical(channel, _channel)) return;
    _channel?.removeListener(_channelChanged);
    _channel = channel..addListener(_channelChanged);
    _access = channel.value?.messageAccess;
  }

  void _channelChanged() {
    final access = _channel?.value?.messageAccess;
    if (access == _access) return;
    setState(() => _access = access);
  }

  @override
  void dispose() {
    _channel?.removeListener(_channelChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
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
  final bool canCopyLink;
  final bool canCopyText;
  final List<PostFlagType> flagTypes;
  final VoidCallback? onSelect;
  final Widget Function(
    Widget? messageActions,
    Widget? messageReaction,
    Widget? messageReply,
  )
  childBuilder;

  @override
  State<_ChatMessageActions> createState() => _ChatMessageActionsState();
}

class _ChatMessageActionsState extends State<_ChatMessageActions> {
  final _dropdown = DDropdownMenuController();
  final _sheet = DSheetController<void>();
  // Hover/focus chrome changes independently of the selectable message body.
  final _interaction = ValueNotifier(0);
  // Run after dismissal so focus restoration cannot steal focus from a picker
  // or the composer opened by the action.
  VoidCallback? _pendingSheetAction;
  bool _focused = false;
  bool _hovered = false;
  bool _hoverSuppressed = false;
  bool _pointerInside = false;
  bool _moreActionsOpen = false;
  bool _sheetOpen = false;
  bool _pinning = false;
  bool _rebaking = false;
  bool _restoring = false;
  final _menuReactionAnchor = GlobalKey();
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

  void _refreshInteraction() => _interaction.value++;

  void _hideHoverForScroll() {
    _hoverSuppressed = true;
    _moreActionsOpen = false;
    if (!_hovered && !_focused && !_dropdown.isOpen) return;
    _hovered = false;

    void refresh() {
      if (!mounted) return;
      _dropdown.close();
      _refreshInteraction();
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
    _hovered = true;
    _refreshInteraction();
  }

  void _pointerMoved() {
    _pointerInside = true;
    if (_scroll?.isScrollingNotifier.value == true) return;
    _hoverSuppressed = false;
    if (!_hovered) {
      _hovered = true;
      _refreshInteraction();
    }
  }

  void _pointerExited() {
    _pointerInside = false;
    if (_moreActionsOpen) return;
    if (_hovered) {
      _hovered = false;
      _refreshInteraction();
    }
  }

  @override
  void dispose() {
    _detachScroll();
    _dropdown.dispose();
    _sheet.dispose();
    _interaction.dispose();
    super.dispose();
  }

  void _reply() {
    if (PluginUiScope.require(
      context,
      chatControllerService,
    ).canReplyToMessage(widget.siteUrl, widget.message)) {
      widget.onReply?.call();
    }
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

  void _runDropdownAction(VoidCallback action) {
    _dropdown.close();
    // Let the menu restore focus before an action opens another overlay or
    // moves focus to the composer. The message remains the callback owner.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  Widget _messageReaction({required bool enabled}) => ListenableBuilder(
    listenable: _interaction,
    child: EmojiPickerAnchor(
      child: Builder(
        builder: (anchorContext) => DButton.iconOnly(
          key: ValueKey('chat-message-react-${widget.message.id}'),
          tooltip: 'Add reaction',
          icon: const DIcon(DIcons.farFaceSmile),
          size: DButtonSize.regular,
          density: DButtonDensity.chatMessageAction,
          variant: DButtonVariant.transparentBackground,
          interactiveBackgroundColor: Colors.transparent,
          onPressed: !enabled || _reactionPickerOpening
              ? null
              : () => unawaited(_pickReaction(anchorContext)),
        ),
      ),
    ),
    builder: (context, child) {
      final visible =
          enabled &&
          (context.isTouch ||
              _reactionPickerOpening ||
              (!_hoverSuppressed && (_hovered || _focused)));
      return Opacity(
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: ExcludeSemantics(excluding: !visible, child: child!),
        ),
      );
    },
  );

  Widget _messageReply() => ListenableBuilder(
    listenable: _interaction,
    child: DButton.iconOnly(
      key: ValueKey('chat-message-reply-action-${widget.message.id}'),
      tooltip: 'Reply',
      icon: const DIcon(DIcons.reply),
      size: DButtonSize.regular,
      density: DButtonDensity.chatMessageAction,
      variant: DButtonVariant.transparentBackground,
      interactiveBackgroundColor: Colors.transparent,
      onPressed: _reply,
    ),
    builder: (context, child) {
      final visible = !_hoverSuppressed && (_hovered || _focused);
      return Opacity(
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: ExcludeSemantics(excluding: !visible, child: child!),
        ),
      );
    },
  );

  Widget _messageActions({
    required Widget Function(Widget? trigger) childBuilder,
    required bool bookmarkBusy,
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
    }) {
      if (context.isTouch) {
        return DButton(
          key: ValueKey('chat-message-$name-${widget.message.id}'),
          icon: DIcon(icon),
          loading: busy,
          alignment: AlignmentDirectional.centerStart,
          variant: destructive
              ? DButtonVariant.destructive
              : DButtonVariant.transparentBackground,
          onPressed: busy
              ? null
              : () {
                  _pendingSheetAction = action;
                  _sheet.close();
                },
          label: Text(label),
        );
      }
      return DDropdownMenuItem(
        key: ValueKey('chat-message-$name-${widget.message.id}'),
        leading: busy ? const DSpinner() : DIcon(icon, size: 16),
        onPressed: busy ? null : () => _runDropdownAction(action),
        closeOnSelect: false,
        variant: destructive
            ? DDropdownMenuItemVariant.destructive
            : DDropdownMenuItemVariant.standard,
        child: Text(label),
      );
    }

    final items = <Widget>[
      if (widget.message.createdAt case final at?) ...[
        if (context.isTouch)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
            child: Text(
              _messageDate(context, at),
              key: ChatMessageTile.timestampKey(widget.message.id),
            ),
          )
        else
          DDropdownMenuLabel(
            child: Text(
              _messageDate(context, at),
              key: ChatMessageTile.timestampKey(widget.message.id),
            ),
          ),
        if (context.isTouch)
          const DSeparator()
        else
          const DDropdownMenuSeparator(),
      ],
      if (canReply) item('reply', 'Reply', DIcons.reply, _reply),
      if (chat.canAddReactionToMessage(widget.siteUrl, widget.message))
        item(
          'react-menu',
          'React',
          DIcons.farFaceSmile,
          () => unawaited(_pickReaction(_menuReactionAnchor.currentContext)),
          busy: _reactionPickerOpening,
        ),
      if (canBookmark)
        item(
          'bookmark',
          widget.message.bookmark == null ? 'Bookmark' : 'Edit bookmark',
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
        item('flag', 'Flag', DIcons.flag, () => unawaited(_flag(flagTypes))),
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
    ];
    if (context.isTouch) {
      return DSheet<void>(
        controller: _sheet,
        onOpenChanged: (details) {
          _sheetOpen = details.open;
          _refreshInteraction();
        },
        onOpenChangeComplete: (open) {
          if (open) return;
          final action = _pendingSheetAction;
          _pendingSheetAction = null;
          if (mounted) action?.call();
        },
        trigger: DSheetTrigger(builder: (context, open) => childBuilder(null)),
        content: DSheetContent(
          side: DSheetSide.bottom,
          topBottomMaxHeightFactor: .85,
          children: [
            const DSheetHeader(
              children: [DSheetTitle(child: Text('Message actions'))],
            ),
            DSheetBody(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items,
              ),
            ),
          ],
        ),
      );
    }
    return DDropdownMenu(
      controller: _dropdown,
      onOpenChange: (open, _) {
        _moreActionsOpen = open;
        if (!open && !_pointerInside) _hovered = false;
        _refreshInteraction();
      },
      content: DDropdownMenuContent(
        semanticLabel: 'Message actions',
        align: DPopoverAlign.end,
        width: 220,
        children: items,
      ),
      child: childBuilder(
        EmojiPickerAnchor(
          key: _menuReactionAnchor,
          child: DDropdownMenuTrigger(
            builder: (context, state) => ListenableBuilder(
              listenable: _interaction,
              child: DButton.iconOnly(
                key: ValueKey('chat-message-more-actions-${widget.message.id}'),
                tooltip: 'More message actions',
                icon: const DIcon(DIcons.chevronDown),
                size: DButtonSize.small,
                variant: DButtonVariant.transparentBackground,
                focusNode: state.focusNode,
                hasPopup: true,
                expanded: state.open,
                onPressed: state.toggle,
              ),
              builder: (context, child) {
                final visible =
                    context.isTouch ||
                    _moreActionsOpen ||
                    (!_hoverSuppressed && (_hovered || _focused));
                // Preserve the trailing slot and keyboard access while hidden;
                // the trigger becomes visible when the message receives focus.
                return Opacity(
                  opacity: visible ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !visible,
                    child: ExcludeSemantics(excluding: !visible, child: child!),
                  ),
                );
              },
            ),
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
    // The enclosing tile's access scope redraws these when the channel changes
    // a permission.
    return ValueListenableBuilder<bool>(
      valueListenable: bookmarkHost.bookmarkWriteInFlightListenable(
        siteUrl: widget.siteUrl,
        targetId: widget.message.id,
      ),
      builder: (context, bookmarkBusy, _) {
        return _build(
          context,

          bookmarkBusy: bookmarkBusy,
          canEdit:
              widget.onEdit != null &&
              chat.canEditMessage(widget.siteUrl, widget.message),
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
    );
  }

  Widget _build(
    BuildContext context, {
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
    final semanticsActions = <CustomSemanticsAction, VoidCallback>{
      if (canAddReaction && !_reactionPickerOpening)
        const CustomSemanticsAction(label: 'Add reaction'): () =>
            unawaited(_pickReaction()),
      if (widget.onReply != null &&
          chat.canReplyToMessage(widget.siteUrl, widget.message))
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
      if (chat.canBookmarkMessage(widget.siteUrl, widget.message) &&
          !bookmarkBusy)
        CustomSemanticsAction(label: bookmarkLabel): () =>
            unawaited(_bookmark()),
    };
    Widget messageRow(Widget? messageActions) => Shortcuts(
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
                  context.isTouch
                      ? _sheet.open()
                      : _dropdown.open(DPopoverInteraction.keyboard);
                  return null;
                },
              ),
        },
        child: Focus(
          key: widget.focusKey,
          onFocusChange: (focused) {
            if (mounted && _focused != focused) {
              _focused = focused;
              _refreshInteraction();
            }
          },
          child: Semantics(
            customSemanticsActions: semanticsActions,
            child: MouseRegion(
              onEnter: (_) => _pointerEntered(),
              onHover: (_) => _pointerMoved(),
              onExit: (_) => _pointerExited(),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onLongPress: context.isTouch
                    ? () {
                        unawaited(HapticFeedback.lightImpact());
                        _sheet.open();
                      }
                    : null,
                onSecondaryTap: () => context.isTouch
                    ? _sheet.open()
                    : _dropdown.open(DPopoverInteraction.mouse),
                child: widget.childBuilder(
                  messageActions,
                  canAddReaction && !context.isTouch
                      ? _messageReaction(enabled: true)
                      : null,
                  widget.onReply != null &&
                          !context.isTouch &&
                          chat.canReplyToMessage(widget.siteUrl, widget.message)
                      ? _messageReply()
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // The popup belongs outside the message's semantic grouping. Its trigger
    // remains in the bubble, while the menu keeps independent native AX nodes.
    return _messageActions(
      bookmarkBusy: bookmarkBusy,
      canEdit: canEdit,
      canDelete: canDelete,
      canRestore: canRestore,
      canPin: canPin,
      canRebake: canRebake,
      flagTypes: flagTypes,
      childBuilder: (trigger) => ListenableBuilder(
        listenable: _interaction,
        child: messageRow(trigger),
        builder: (context, child) =>
            DMessageSurface(hovered: _hovered || _sheetOpen, child: child!),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.siteUrl,
    required this.message,
    required this.chained,
    required this.joinsNext,
    required this.endsGroup,
    required this.followsReactions,
    required this.onOpenThread,
    required this.onJumpToMessage,
    required this.showThreadSummary,
    this.messageActions,
    this.messageReaction,
    this.messageReply,
  });

  final String siteUrl;
  final ChatMessage message;
  final bool chained;
  final bool joinsNext;
  final bool endsGroup;
  final bool followsReactions;
  final ValueChanged<ChatThreadPreview>? onOpenThread;
  final ValueChanged<int>? onJumpToMessage;
  final bool showThreadSummary;
  final Widget? messageActions;
  final Widget? messageReaction;
  final Widget? messageReply;

  @override
  Widget build(BuildContext context) =>
      PluginServiceSelector<ChatController, int?>(
        service: chatControllerService,
        select: (chat) => chat.currentUserFor(siteUrl)?.id,
        builder: (context, userId, _) => _conversationMessage(
          context,
          outgoing: userId != null && userId == message.author.id,
        ),
      );

  Widget? _body(
    BuildContext context, {
    TextStyle? textStyle,
    TextStyle? linkStyle,
    bool contentSized = false,
  }) {
    final messageTextStyle = textStyle ?? Theme.of(context).textTheme.bodyLarge;
    final html = message.canonicalReceived
        ? message.cooked
        : message.provisionalCooked;
    if (html != null) {
      if (html.isEmpty) return null;
      return CookedHtml(
        html: html,
        textStyle: messageTextStyle,
        linkStyle: linkStyle,
        siteUrl: siteUrl,
        compactParagraphs: true,
        contentSized: contentSized,
        mentionedUserStatuses: message.mentionedUserStatuses,
      );
    }
    return switch (message) {
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

  Widget _conversationMessage(BuildContext context, {required bool outgoing}) {
    final theme = Theme.of(context);
    const joinedCorner = DRadius.chatBubble / 4;
    final reserveActions = message.isOptimistic && !context.isTouch;
    Widget? pendingAction(
      DIconData icon,
      DButtonSize size,
      String label, {
      DButtonDensity density = DButtonDensity.standard,
    }) => reserveActions
        ? Visibility(
            visible: false,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: DButton.iconOnly(
              icon: DIcon(icon),
              tooltip: label,
              size: size,
              density: density,
              variant: DButtonVariant.transparentBackground,
              onPressed: null,
            ),
          )
        : null;
    final more =
        messageActions ??
        pendingAction(
          DIcons.chevronDown,
          DButtonSize.small,
          'More message actions',
        );
    final react =
        messageReaction ??
        pendingAction(
          DIcons.farFaceSmile,
          DButtonSize.regular,
          'Add reaction',
          density: DButtonDensity.chatMessageAction,
        );
    final reply =
        messageReply ??
        pendingAction(
          DIcons.reply,
          DButtonSize.regular,
          'Reply',
          density: DButtonDensity.chatMessageAction,
        );
    final bubbleAlign = outgoing ? DBubbleAlign.end : DBubbleAlign.start;
    final target = message.threadId == null
        ? ChatChannelTarget(message.channelId)
        : ChatThreadTarget(
            channelId: message.channelId,
            threadId: message.threadId!,
          );
    final hasBody = message.canonicalReceived
        ? message.cooked.isNotEmpty
        : message.provisionalCooked?.isNotEmpty ??
              switch (message.preview) {
                ProjectedPreview(:final document) => document.nodes.isNotEmpty,
                _ => message.optimisticRaw?.isNotEmpty == true,
              };
    final hasSurface =
        hasBody || message.uploads.isNotEmpty || message.replyTo != null;
    final footer = <Widget>[
      if (message.reactions.isNotEmpty)
        _Reactions(siteUrl: siteUrl, message: message),
      if (message.thread case final thread?
          when showThreadSummary && thread.replyCount > 0)
        _ThreadSummaryCard(
          siteUrl: siteUrl,
          channelId: message.channelId,
          thread: thread,
          onOpen: onOpenThread == null ? null : () => onOpenThread!(thread),
          bubbleAlign: bubbleAlign,
        ),
      if (message.edited ||
          message.pinned ||
          message.bookmark != null ||
          message.delivery == ChatMessageDelivery.failed)
        DMessageFooter(
          spacing: DSpacing.sm,
          children: [
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
            if (message.delivery == ChatMessageDelivery.failed)
              DMessageStatus(
                state: DMessageDeliveryState.failed,
                label: message.sendError == null || message.sendError!.isEmpty
                    ? null
                    : 'Failed to send: ${message.sendError}',
              ),
            if (message.delivery == ChatMessageDelivery.failed &&
                message.stagedId != null &&
                message.sendFailure?.failure == WriteFailure.rateLimited)
              PluginServiceSelector<ChatController, bool>(
                service: chatControllerService,
                select: (controller) =>
                    controller.canSendMessageTo(siteUrl, target),
                builder: (context, canSend, _) => DButton(
                  size: DButtonSize.small,
                  variant: DButtonVariant.transparentBackground,
                  label: Text(
                    message.retryWaiting ? 'Retry after cooldown' : 'Retry',
                  ),
                  onPressed: message.retryWaiting || !canSend
                      ? null
                      : () {
                          PluginUiScope.require(
                            context,
                            chatControllerService,
                          ).retryMessage(siteUrl, target, message.stagedId!);
                        },
                ),
              ),
          ],
        ),
    ];

    return Padding(
      key: ValueKey('chat-message-${message.id}'),
      padding: EdgeInsetsDirectional.fromSTEB(
        DSpacing.lg,
        chained ? (followsReactions ? 2 : 4) : 16,
        DSpacing.lg,
        endsGroup ? 8 : 0,
      ),
      child: DMessage(
        align: outgoing ? DMessageAlign.end : DMessageAlign.start,
        footer: footer.isEmpty
            ? null
            : Padding(
                padding: EdgeInsetsDirectional.only(
                  start: outgoing ? 0 : 36,
                  end: outgoing ? 36 : 0,
                  top: 4,
                ),
                child: DMessageContent(
                  flushMetadata: true,
                  spacing: DSpacing.xs,
                  children: footer,
                ),
              ),
        children: [
          DMessageAvatar(
            minimumExtent: 28,
            shiftForFooter: false,
            child: chained
                ? const SizedBox.square(dimension: 28)
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
                      size: 28,
                      fallback: _AvatarFallback(
                        name: message.author.displayName,
                        background: theme.shell.floating,
                      ),
                    ),
                  ),
          ),
          DMessageContent(
            spacing: DSpacing.xs,
            flushMetadata: true,
            children: [
              if (!chained)
                DMessageHeader(
                  followMessageAlignment: true,
                  spacing: DSpacing.xs,
                  children: [
                    UserCardTarget(
                      username: message.author.username,
                      siteUrl: siteUrl,
                      child: Text(
                        outgoing ? 'you' : message.author.displayName,
                      ),
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
                    if (message.createdAt case final at?) ...[
                      const Text('·'),
                      Text(
                        MaterialLocalizations.of(context).formatTimeOfDay(
                          TimeOfDay.fromDateTime(at.toLocal()),
                          alwaysUse24HourFormat:
                              MediaQuery.alwaysUse24HourFormatOf(context),
                        ),
                        key: ValueKey('chat-message-time-${message.id}'),
                      ),
                    ],
                  ],
                ),
              if (hasSurface)
                DBubble(
                  align: bubbleAlign,
                  maximumWidthFactor: context.isTouch ? 1 : .88,
                  variant: outgoing
                      ? DBubbleVariant.accent
                      : DBubbleVariant.neutral,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: DSpacing.controlGap,
                      children: [
                        if (outgoing && reply != null) reply,
                        if (outgoing && react != null) react,
                        Flexible(
                          child: DBubbleContent(
                            key: ValueKey('chat-message-bubble-${message.id}'),
                            borderRadius: BorderRadiusDirectional.only(
                              topStart: Radius.circular(
                                outgoing || !chained
                                    ? DRadius.chatBubble
                                    : joinedCorner,
                              ),
                              topEnd: Radius.circular(
                                outgoing && chained
                                    ? joinedCorner
                                    : DRadius.chatBubble,
                              ),
                              bottomStart: Radius.circular(
                                outgoing || !joinsNext
                                    ? DRadius.chatBubble
                                    : joinedCorner,
                              ),
                              bottomEnd: Radius.circular(
                                outgoing && joinsNext
                                    ? joinedCorner
                                    : DRadius.chatBubble,
                              ),
                            ),
                            trailingAction: more,
                            quote: switch (message.replyTo) {
                              final reply? => _ReplyIndicator(
                                siteUrl: siteUrl,
                                reply: reply,
                                onJump: onJumpToMessage == null
                                    ? null
                                    : () => onJumpToMessage!(reply.id),
                              ),
                              null => null,
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (hasBody)
                                  Builder(
                                    builder: (context) {
                                      final style = DefaultTextStyle.of(context)
                                          .style;
                                      return _MessageBodySelection(
                                        selectionKey:
                                            ChatMessageTile.bodySelectionKey(
                                              message.id,
                                            ),
                                        child: _body(
                                          context,
                                          textStyle: style,
                                          contentSized: true,
                                          linkStyle: DText.linkStyleOf(context)
                                              .copyWith(
                                                color: outgoing
                                                    ? style.color
                                                    : null,
                                                decorationColor: outgoing
                                                    ? style.color
                                                    : null,
                                              ),
                                        )!,
                                      );
                                    },
                                  ),
                                if (message.uploads.isNotEmpty)
                                  ChatUploads(
                                    siteUrl: siteUrl,
                                    uploads: message.uploads,
                                    alignment: outgoing
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (!outgoing && react != null) react,
                        if (!outgoing && reply != null) reply,
                      ],
                    ),
                  ],
                ),
              if (!hasSurface && more != null) more,
            ],
          ),
        ],
      ),
    );
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
  Widget build(BuildContext context) => context.isTouch
      ? widget.child
      : RouteAwareSelectionArea(
          selectionAreaKey: widget.selectionKey,
          focusNode: _focusNode,
          child: widget.child,
        );
}

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
  Widget build(BuildContext context) => DBubbleQuote(
    key: ChatMessageTile.replyIndicatorKey(reply.id),
    semanticLabel:
        'Jump to message from @${reply.username}'
        '${reply.flair == null ? '' : ', ${reply.flair!.label}'}: ${reply.excerpt}',
    onPressed: onJump,
    author: Text(reply.username, maxLines: 1, overflow: TextOverflow.ellipsis),
    child: SiteEmojiText.plain(
      reply.excerpt.isEmpty ? 'Original message' : reply.excerpt,
      siteUrl: siteUrl,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(height: 1.4),
    ),
  );
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
  const _Reactions({required this.siteUrl, required this.message});

  final String siteUrl;
  final ChatMessage message;

  // The enclosing tile's access scope redraws the toggles when the channel
  // changes a permission.
  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final canAdd = chat.canAddReactionToMessage(siteUrl, message);
    bool canToggle(ChatReaction reaction) => reaction.reacted
        ? chat.canRemoveReactionFromMessage(siteUrl, message)
        : canAdd;

    final children = <Widget>[
      for (final reaction in message.reactions)
        ReactionPill(
          key: ValueKey('chat-reaction-pill-${message.id}-${reaction.emoji}'),
          density: DToggleDensity.chatReaction,
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
    ];
    return DMessageFooter(
      key: const ValueKey('chat-reactions'),
      spacing: DSpacing.xs,
      children: children,
    );
  }
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
    required this.channelId,
    required this.thread,
    required this.onOpen,
    this.bubbleAlign,
  });

  final String siteUrl;
  final int channelId;
  final ChatThreadPreview thread;
  final VoidCallback? onOpen;
  final DBubbleAlign? bubbleAlign;

  @override
  Widget build(BuildContext context) {
    final content = DBubbleContent(
      compact: true,
      key: ChatMessageTile.threadPreviewKey(thread.threadId),
      action: DBubbleContentAction.link,
      onPressed: onOpen,
      semanticLabel: _semanticsLabel,
      child: ExcludeSemantics(
        child: _ThreadSummaryContents(siteUrl: siteUrl, thread: thread),
      ),
    );
    final desktop = switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => false,
      _ => true,
    };
    final bubble = DBubble(
      align: bubbleAlign ?? DBubbleAlign.start,
      variant: DBubbleVariant.neutral,
      maximumWidthFactor: .95,
      children: [content],
    );
    if (!desktop || onOpen == null) return bubble;
    return LinkTarget.action(
      action: ({required newTab, panel}) {
        PluginUiScope.require(context, chatShellService).openThread(
          siteUrl: siteUrl,
          channelId: channelId,
          threadId: thread.threadId,
          messageId: thread.lastReplyId,
          mainPanel: panel == ForumPanel.main,
          secondaryPanel: panel == ForumPanel.secondary,
          newTab: newTab,
        );
      },
      child: bubble,
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
    final tokens = DTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < MediaQuery.textScalerOf(context).scale(280);
        return Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DSpacing.sm,
          children: [
            const DIcon(DIcons.chevronRight, size: 12),
            if (!compact && _participantTotal(thread) > 0)
              _ThreadParticipants(siteUrl: siteUrl, thread: thread),
            if (_nonEmpty(thread.lastReplyExcerpt) case final excerpt?
                when !compact)
              Flexible(
                child: SiteEmojiText.plain(
                  excerpt,
                  siteUrl: siteUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.mutedForeground,
                    fontSize: DiscourseTypography.xs,
                  ),
                ),
              ),
            Flexible(
              flex: compact ? 1 : 0,
              child: Text(
                _replyCountLabel(thread.replyCount),
                style: TextStyle(
                  color: tokens.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: DiscourseTypography.xs,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ThreadParticipants extends StatelessWidget {
  const _ThreadParticipants({required this.siteUrl, required this.thread});

  final String siteUrl;
  final ChatThreadPreview thread;

  @override
  Widget build(BuildContext context) {
    final users = _visibleParticipants(thread.participantUsers);
    final hidden = (_participantTotal(thread) - users.length).clamp(0, 1 << 31);
    return DAvatarGroup(
      size: DAvatarSize.sm,
      children: [
        for (final user in users)
          ChatUserAvatar(
            siteUrl: siteUrl,
            userId: user.id,
            url: user.avatarUrl,
            flair: user.flair,
            size: 24,
            fallback: _AvatarFallback(
              name: user.displayName,
              background: Theme.of(context).shell.floating,
            ),
          ),
        if (hidden > 0) DAvatarGroupCount(child: Text('+$hidden')),
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

String _messageDate(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final material = MaterialLocalizations.of(context);
  return "${material.formatFullDate(local)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}";
}
