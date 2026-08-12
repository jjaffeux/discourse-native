import 'dart:async';

import 'package:flutter/material.dart';

import '../../shell/cooked_html.dart';
import '../../shell/relative_time.dart';
import '../../shell/shell_scope.dart';
import '../../shell/site_emoji_image.dart';
import '../../shell/user_card.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
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
  });

  final String siteUrl;
  final int messageId;

  /// Whether this row belongs to the run above it, and so draws no avatar, no
  /// name and no time. Decided by `buildChatStream` over the whole list, since
  /// it is a fact about two messages rather than about one.
  final bool chained;

  /// Width of the avatar plus its gutter, so a chained row's body lines up with
  /// the one above it.
  static const double gutter = 42;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatMessage?>(
      valueListenable: ShellScope.read(
        context,
      ).chat.messageRef(siteUrl, messageId),
      builder: (context, message, _) {
        // Gone for good, in the frame before the stream that named it is
        // rewritten without it.
        if (message == null) return const SizedBox.shrink();
        return _Tile(siteUrl: siteUrl, message: message, chained: chained);
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.siteUrl,
    required this.message,
    required this.chained,
  });

  final String siteUrl;
  final ChatMessage message;
  final bool chained;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messageTextStyle = theme.textTheme.bodyLarge?.copyWith(height: 1.4);

    return Padding(
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
                        when thread.replyCount > 0)
                      _ThreadRow(thread: thread),
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
          _Tag(label: 'bot', color: theme.colorScheme.tertiary),
        ],
        if (message.createdAt case final at?) ...[
          const SizedBox(width: 4),
          Text(
            relativeTime(at),
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (message.edited) ...[
          const SizedBox(width: 4),
          Text(
            '(edited)',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
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

  void _toggle(BuildContext context, ChatReaction reaction) {
    final controller = ShellScope.read(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    unawaited(
      controller.chat
          .toggleMessageReaction(siteUrl, message.id, reaction.emoji)
          .then((error) {
            if (error == null || messenger == null || !messenger.mounted) {
              return;
            }
            if (!identical(
              ShellScope.maybeRead(messenger.context),
              controller,
            )) {
              return;
            }
            messenger.showSnackBar(SnackBar(content: Text(error)));
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('chat-reactions'),
      // Core gives the list 0.25em above it and every chip a 1px vertical
      // margin. Keeping both parts preserves the space below the text and the
      // breathing room after the final chip.
      padding: const EdgeInsets.only(top: 5, bottom: 1),
      child: Wrap(
        spacing: 3,
        runSpacing: 2,
        children: [
          for (final reaction in message.reactions)
            _ChatReactionChip(
              siteUrl: siteUrl,
              reaction: reaction,
              onTap: () => _toggle(context, reaction),
            ),
        ],
      ),
    );
  }
}

class _ChatReactionChip extends StatelessWidget {
  const _ChatReactionChip({
    required this.siteUrl,
    required this.reaction,
    required this.onTap,
  });

  final String siteUrl;
  final ChatReaction reaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = reaction.count == 1
        ? '1 ${reaction.emoji} reaction'
        : '${reaction.count} ${reaction.emoji} reactions';

    return Semantics(
      button: true,
      selected: reaction.reacted,
      label: label,
      onTapHint: reaction.reacted
          ? 'remove your reaction'
          : 'add this reaction',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: ExcludeSemantics(
                child: Container(
                  key: ValueKey('chat-reaction-${reaction.emoji}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7.25,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: reaction.reacted
                        ? Color.alphaBlend(
                            theme.colorScheme.primary.withValues(alpha: 0.08),
                            theme.colorScheme.surface,
                          )
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: reaction.reacted
                          ? theme.colorScheme.primary.withValues(alpha: 0.5)
                          : theme.colorScheme.outline,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SiteEmojiImage(
                        siteUrl: siteUrl,
                        name: reaction.emoji,
                        size: 15,
                        alt: ':${reaction.emoji}:',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${reaction.count}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: reaction.reacted
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// That a message started a thread, and what has happened in it.
///
/// A footnote rather than a button: the replies live behind their own route and
/// there is no screen for them yet, so nothing here should look like a way in.
class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread});

  final ChatThreadPreview thread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = thread.replyCount;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          DIcon(
            DIcons.comments,
            size: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            count == 1 ? '1 reply' : '$count replies',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (thread.lastReplyUsername case final username?) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                thread.lastReplyExcerpt == null
                    ? 'last by $username'
                    : '$username: ${thread.lastReplyExcerpt}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (thread.lastReplyAt case final at?) ...[
            const SizedBox(width: 8),
            Text(
              relativeTime(at),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The same shape `TopicView` gives a post's staff tag.
class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
