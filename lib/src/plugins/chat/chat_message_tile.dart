import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../data/emoji_picker_store.dart';
import '../../shell/cooked_html.dart';
import '../../shell/emoji_picker.dart';
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
    this.onOpenThread,
    this.onReplyInThread,
    this.showThreadSummary = true,
  });

  final String siteUrl;
  final int messageId;

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

  /// Opens or creates this message's thread from the adaptive action surface.
  final ValueChanged<ChatMessage>? onReplyInThread;

  /// Whether to draw the thread summary embedded on an original message.
  ///
  /// Thread views set this false because their responses include the original
  /// message, where another link into the thread would be recursive.
  final bool showThreadSummary;

  /// Width of the avatar plus its gutter, so a chained row's body lines up with
  /// the one above it.
  static const double gutter = 42;

  /// A speaker header plus one body line and the row's vertical padding.
  static const double minimumUnchainedHeight = 58;

  /// One body line and the tighter padding used inside a speaker run.
  static const double minimumChainedHeight = 28;

  static Key threadPreviewKey(int threadId) =>
      ValueKey<String>('chat-thread-preview-$threadId');

  static Key actionsKey(int messageId) =>
      ValueKey<String>('chat-message-actions-$messageId');

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
          showThreadSummary: showThreadSummary,
        );
        final canReplyInThread =
            onReplyInThread != null &&
            !message.isDeleted &&
            !message.isOptimistic &&
            (message.threadId == null || message.thread != null);
        return canReplyInThread
            ? _ChatMessageActions(
                focusKey: actionsKey(message.id),
                onReply: () => onReplyInThread!(message),
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
    required this.onReply,
    required this.child,
  });

  final Key focusKey;
  final VoidCallback onReply;
  final Widget child;

  @override
  State<_ChatMessageActions> createState() => _ChatMessageActionsState();
}

class _ChatMessageActionsState extends State<_ChatMessageActions> {
  bool _hovered = false;

  void _reply() {
    widget.onReply();
  }

  Future<void> _showActions() => showShellSheet<void>(
    context: context,
    title: 'Message actions',
    padding: EdgeInsets.zero,
    builder: (sheetContext) => ListTile(
      minTileHeight: 52,
      leading: const DIcon(DIcons.reply, size: 18),
      title: const Text('Reply in thread'),
      onTap: () {
        Navigator.of(sheetContext).pop();
        _reply();
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
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
            customSemanticsActions: {
              const CustomSemanticsAction(label: 'Reply in thread'): _reply,
            },
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onLongPress: () => unawaited(_showActions()),
                onSecondaryTap: () => unawaited(_showActions()),
                child: Stack(
                  children: [
                    widget.child,
                    if (_hovered)
                      Positioned(
                        top: 4,
                        right: 12,
                        child: Material(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(8),
                          elevation: 2,
                          child: IconButton(
                            constraints: const BoxConstraints.tightFor(
                              width: 44,
                              height: 44,
                            ),
                            tooltip: 'Reply in thread',
                            onPressed: _reply,
                            icon: const DIcon(DIcons.reply, size: 16),
                          ),
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
    required this.showThreadSummary,
  });

  final String siteUrl;
  final ChatMessage message;
  final bool chained;
  final ValueChanged<ChatThreadPreview>? onOpenThread;
  final bool showThreadSummary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messageTextStyle = theme.textTheme.bodyLarge?.copyWith(height: 1.4);

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
            _ReplyIndicator(siteUrl: siteUrl, reply: reply),
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
                    if (message.canonicalReceived && message.cooked.isNotEmpty)
                      CookedHtml(
                        html: message.cooked,
                        textStyle: messageTextStyle,
                        siteUrl: siteUrl,
                        compactParagraphs: true,
                      ),
                    if (message.preview case ProjectedPreview(
                      :final document,
                    ) when !message.canonicalReceived)
                      ChatPreviewBody(
                        document: document,
                        textStyle: messageTextStyle,
                      ),
                    if (message.optimisticRaw case final raw?
                        when !message.canonicalReceived &&
                            message.preview is! ProjectedPreview)
                      Text(raw, style: messageTextStyle),
                    if (message.uploads.isNotEmpty)
                      ChatUploads(siteUrl: siteUrl, uploads: message.uploads),
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
        if (message.edited) ...[
          const SizedBox(width: 4),
          Text(
            '(edited)',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.discourse.whisper,
            ),
          ),
        ],
      ],
    );
  }
}

/// What this message is answering, one line above it.
class _ReplyIndicator extends StatelessWidget {
  const _ReplyIndicator({required this.siteUrl, required this.reply});

  final String siteUrl;
  final ChatReplyTo reply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: ChatMessageTile.gutter, bottom: 2),
      child: Row(
        children: [
          DIcon(
            DIcons.reply,
            size: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          ChatUserAvatar(
            siteUrl: siteUrl,
            userId: reply.userId,
            url: reply.avatarUrl,
            size: 16,
            fallback: ColoredBox(color: theme.shell.floating),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              reply.excerpt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
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

  Future<void> _pickReaction(BuildContext context) async {
    final controller = ShellScope.read(context);
    final chat = PluginScope.require(context, chatControllerService);
    if (!chat.canAddReactionToMessage(siteUrl, message)) return;
    final lease = controller.lifecycle.capture(siteUrl);
    final messenger = ScaffoldMessenger.maybeOf(context);

    final picked = await showEmojiPicker(
      context: context,
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
