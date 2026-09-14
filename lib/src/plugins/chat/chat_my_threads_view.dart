import 'dart:async';

import 'package:flutter/material.dart';

import '../../../discourse_ui.dart';
import '../../models/user_status.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../shell/content_reading_lane.dart';
import '../../shell/relative_time.dart';
import '../../shell/user_status.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icons.dart';
import '../../utils/pagination.dart';
import 'chat_controller.dart';
import 'chat_message.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';
import 'chat_thread.dart';
import 'chat_user_avatar.dart';

class ChatMyThreadsView extends StatefulWidget {
  const ChatMyThreadsView({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<ChatMyThreadsView> createState() => _ChatMyThreadsViewState();
}

class _ChatMyThreadsViewState extends State<ChatMyThreadsView> {
  late final ChatController _chat;
  late final ScrollController _scroll;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController()..addListener(_maybeLoadMore);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _chat = PluginUiScope.require(context, chatControllerService);
    _ready = true;
    unawaited(_chat.loadMyThreads(widget.siteUrl));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients ||
        _scroll.position.extentAfter >
            paginationPrefetchDistance(_scroll.position)) {
      return;
    }
    unawaited(_chat.loadMyThreads(widget.siteUrl, more: true));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _chat,
    builder: (context, _) {
      final threads = _chat.myThreads(widget.siteUrl);
      final error = _chat.myThreadsError(widget.siteUrl);
      if (_chat.myThreadsLoading(widget.siteUrl)) {
        return const Center(child: DSpinner(size: DSpacing.xl));
      }
      if (threads.isEmpty && error != null) {
        return ChatThreadListMessage(
          icon: DIcons.triangleExclamation,
          message: error,
          action: 'Try again',
          onAction: () =>
              unawaited(_chat.loadMyThreads(widget.siteUrl, force: true)),
        );
      }
      if (threads.isEmpty && _chat.myThreadsLoaded(widget.siteUrl)) {
        return const ChatThreadListMessage(
          icon: DIcons.comments,
          message: 'You do not have any chat threads yet.',
        );
      }

      final hasFooter =
          _chat.myThreadsLoadingMore(widget.siteUrl) ||
          error != null ||
          _chat.myThreadsHaveMore(widget.siteUrl);
      return ContentReadingLane(
        basePadding: const EdgeInsets.symmetric(vertical: 8),
        builder: (context, lane) => RefreshIndicator.adaptive(
          onRefresh: () => _chat.loadMyThreads(widget.siteUrl, force: true),
          child: ListView.separated(
            key: const PageStorageKey('chat-my-threads'),
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: lane.padding,
            itemCount: threads.length + (hasFooter ? 1 : 0),
            separatorBuilder: (_, _) => const DSeparator(space: 1),
            itemBuilder: (context, index) {
              if (index < threads.length) {
                return ChatThreadListRow(
                  siteUrl: widget.siteUrl,
                  thread: threads[index],
                  nestedPreview: true,
                );
              }
              if (_chat.myThreadsLoadingMore(widget.siteUrl)) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: DSpinner(size: DSpacing.xl)),
                );
              }
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (error case final message?) ...[
                      Text(message, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                    ],
                    DButton(
                      label: Text(error == null ? 'Load more' : 'Try again'),
                      onPressed: () => unawaited(
                        _chat.loadMyThreads(widget.siteUrl, more: true),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

class ChatThreadListRow extends StatelessWidget {
  const ChatThreadListRow({
    super.key,
    required this.siteUrl,
    required this.thread,
    this.showChannel = true,
    this.nestedPreview = false,
    this.keyPrefix = 'chat-my-thread',
  });

  final String siteUrl;
  final ChatThread thread;
  final bool showChannel;
  final bool nestedPreview;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final channel = chat.channel(siteUrl, thread.channelId);
    final original = thread.originalMessage;
    final author = original?.author;
    final preview = thread.preview;
    final unread =
        thread.tracking.unreadCount > 0 ||
        thread.tracking.mentionCount > 0 ||
        thread.tracking.watchedThreadsUnreadCount > 0;
    final title =
        _text(thread.title) ??
        _text(original?.excerpt) ??
        _text(original?.message) ??
        'Thread';
    final latestName =
        _text(preview?.lastReplyUser?.displayName) ??
        _text(preview?.lastReplyUsername);
    final latestExcerpt = _text(preview?.lastReplyExcerpt);
    final latestTime = switch (preview?.lastReplyAt) {
      final DateTime at => relativeTime(at),
      _ => null,
    };
    final latest = [
      if (latestName != null) '$latestName:',
      ?latestExcerpt,
      if (latestTime != null) '· $latestTime',
    ].join(' ');
    final semantics = StringBuffer('Open thread $title');
    if (channel != null) semantics.write(' in ${channel.title}');
    if (unread) semantics.write(', unread');
    semantics.write(', ${_replyCountLabel(thread.replyCount)}.');
    if (preview case final value?) {
      final participants = _participantTotal(value);
      if (participants > 0) {
        semantics.write(
          ' $participants ${participants == 1 ? 'participant' : 'participants'}.',
        );
      }
    }

    return Semantics(
      button: true,
      label: semantics.toString(),
      child: Material(
        type: MaterialType.transparency,
        child: nestedPreview
            ? _NestedThreadListRow(
                rowKey: ValueKey<String>('$keyPrefix-${thread.id}'),
                siteUrl: siteUrl,
                thread: thread,
                channelTitle: channel?.title ?? 'Chat',
                title: title,
                unread: unread,
                showChannel: showChannel,
                keyPrefix: keyPrefix,
                onTap: () => unawaited(_open(context, chat)),
              )
            : ListTile(
                key: ValueKey<String>('$keyPrefix-${thread.id}'),
                onTap: () => unawaited(_open(context, chat)),
                leading: ChatUserAvatar(
                  siteUrl: siteUrl,
                  userId: author?.id ?? 0,
                  url: author?.avatarUrl,
                  flair: author?.flair,
                  size: 40,
                  fallback: _AvatarFallback(name: author?.displayName),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showChannel)
                      Text(
                        channel?.title ?? 'Chat',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: unread
                          ? const TextStyle(fontWeight: FontWeight.w700)
                          : null,
                    ),
                  ],
                ),
                subtitle: Row(
                  children: [
                    UserStatusMessage(
                      siteUrl: siteUrl,
                      userId: preview?.lastReplyUser?.id,
                      status: preview?.lastReplyUser?.status,
                      size: 14,
                    ),
                    if (preview?.lastReplyUser?.status != null)
                      const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        latest.isEmpty
                            ? _replyCountLabel(thread.replyCount)
                            : latest,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                trailing: unread
                    ? DNotificationDot(
                        color: _threadIndicatorColor(context, thread),
                        semanticLabel: 'Unread',
                        key: ValueKey<String>('$keyPrefix-unread-${thread.id}'),
                      )
                    : null,
              ),
      ),
    );
  }

  Future<void> _open(BuildContext context, ChatController chat) async {
    try {
      final channel = await chat.ensureChannel(siteUrl, thread.channelId);
      if (!context.mounted) return;
      if (channel == null) throw StateError('Channel unavailable');
      PluginUiScope.require(context, chatShellService).openThread(
        siteUrl: siteUrl,
        channelId: channel.id,
        threadId: thread.id,
      );
    } catch (_) {
      if (!context.mounted) return;
      DToast.show(
        context,
        'Could not open this chat thread.',
        type: DToastType.error,
      );
    }
  }
}

class _NestedThreadListRow extends StatefulWidget {
  const _NestedThreadListRow({
    required this.rowKey,
    required this.siteUrl,
    required this.thread,
    required this.channelTitle,
    required this.title,
    required this.unread,
    required this.showChannel,
    required this.keyPrefix,
    required this.onTap,
  });

  final Key rowKey;
  final String siteUrl;
  final ChatThread thread;
  final String channelTitle;
  final String title;
  final bool unread;
  final bool showChannel;
  final String keyPrefix;
  final VoidCallback onTap;

  static const double _compactBreakpoint = 560;

  @override
  State<_NestedThreadListRow> createState() => _NestedThreadListRowState();
}

class _NestedThreadListRowState extends State<_NestedThreadListRow> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  void _updateHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _updateFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
  }

  void _updatePressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rowKey = widget.rowKey;
    final siteUrl = widget.siteUrl;
    final thread = widget.thread;
    final channelTitle = widget.channelTitle;
    final title = widget.title;
    final unread = widget.unread;
    final showChannel = widget.showChannel;
    final keyPrefix = widget.keyPrefix;
    return InkWell(
      key: rowKey,
      excludeFromSemantics: true,
      mouseCursor: SystemMouseCursors.click,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      onHover: _updateHovered,
      onFocusChange: _updateFocused,
      onHighlightChanged: _updatePressed,
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 22),
        child: ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = ContentReadingLane.breakpointWidthOf(
                context,
                constraints.maxWidth,
              );
              final compact = width < _NestedThreadListRow._compactBreakpoint;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showChannel) ...[
                    Row(
                      children: [
                        DIcon(
                          DIcons.comment,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            channelTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: compact ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: DNotificationDot(
                            color: _threadIndicatorColor(context, thread),
                            semanticLabel: 'Unread',
                            key: ValueKey<String>(
                              '$keyPrefix-unread-${thread.id}',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 13),
                  _LatestReplyCard(
                    key: ValueKey<String>('$keyPrefix-preview-${thread.id}'),
                    siteUrl: siteUrl,
                    thread: thread,
                    compact: compact,
                    keyPrefix: keyPrefix,
                    emphasized: _hovered || _focused || _pressed,
                    focused: _focused,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LatestReplyCard extends StatelessWidget {
  const _LatestReplyCard({
    super.key,
    required this.siteUrl,
    required this.thread,
    required this.compact,
    required this.keyPrefix,
    required this.emphasized,
    required this.focused,
  });

  final String siteUrl;
  final ChatThread thread;
  final bool compact;
  final String keyPrefix;
  final bool emphasized;
  final bool focused;

  static const double _avatarSize = 40;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final original = thread.originalMessage;
    final originalAuthor = original?.author;
    final preview = thread.preview;
    final replyUser = preview?.lastReplyUser;
    final fallbackAuthor = preview == null ? originalAuthor : null;
    final displayedUser = replyUser ?? fallbackAuthor;
    final latestName =
        _text(replyUser?.displayName) ??
        _text(preview?.lastReplyUsername) ??
        _text(fallbackAuthor?.displayName);
    final latestExcerpt =
        _text(preview?.lastReplyExcerpt) ??
        (preview == null
            ? _text(original?.excerpt) ?? _text(original?.message)
            : null);
    final latestAt =
        preview?.lastReplyAt ?? (preview == null ? original?.createdAt : null);
    final latestTime = latestAt == null ? null : relativeTime(latestAt);
    final latestAvatarUrl =
        replyUser?.avatarUrl ??
        preview?.lastReplyAvatarUrl ??
        fallbackAuthor?.avatarUrl;
    final latestStatus = replyUser?.status ?? fallbackAuthor?.status;
    final baseCardColor = theme.colorScheme.surfaceContainerHighest;
    final cardColor = emphasized
        ? Color.alphaBlend(
            theme.colorScheme.onSurface.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.055 : 0.035,
            ),
            baseCardColor,
          )
        : baseCardColor;
    final borderColor = focused
        ? theme.colorScheme.primary.withValues(alpha: 0.7)
        : emphasized
        ? theme.colorScheme.onSurface.withValues(alpha: 0.1)
        : Colors.transparent;
    final avatar = ChatUserAvatar(
      siteUrl: siteUrl,
      userId: displayedUser?.id ?? 0,
      url: latestAvatarUrl,
      flair: displayedUser?.flair,
      size: _avatarSize,
      fallback: _AvatarFallback(name: latestName),
    );
    final copy = _LatestReplyCopy(
      siteUrl: siteUrl,
      userId: displayedUser?.id,
      status: latestStatus,
      name: latestName,
      time: latestTime,
      excerpt:
          latestExcerpt ??
          (thread.replyCount == 0 ? 'No replies yet' : 'Latest reply'),
      compact: compact,
    );
    final activity = _ThreadActivity(
      siteUrl: siteUrl,
      thread: thread,
      keyPrefix: keyPrefix,
      background: cardColor,
    );

    return AnimatedContainer(
      key: ValueKey<String>('$keyPrefix-preview-surface-${thread.id}'),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      avatar,
                      const SizedBox(width: 11),
                      Expanded(child: copy),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(left: _avatarSize + 11),
                    child: activity,
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  avatar,
                  const SizedBox(width: 11),
                  Expanded(child: copy),
                  const SizedBox(width: 16),
                  activity,
                ],
              ),
      ),
    );
  }
}

class _LatestReplyCopy extends StatelessWidget {
  const _LatestReplyCopy({
    required this.siteUrl,
    required this.userId,
    required this.status,
    required this.name,
    required this.time,
    required this.excerpt,
    required this.compact,
  });

  final String siteUrl;
  final int? userId;
  final UserStatus? status;
  final String? name;
  final String? time;
  final String excerpt;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (name != null || time != null || status != null)
          Row(
            children: [
              if (name case final value?)
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              UserStatusMessage(
                siteUrl: siteUrl,
                userId: userId,
                status: status,
                size: 14,
                leadingGap: name == null ? 0 : 4,
              ),
              if (time case final value?) ...[
                if (name != null || status != null) const SizedBox(width: 6),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        if (name != null || time != null || status != null)
          const SizedBox(height: 3),
        Text(
          excerpt,
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _ThreadActivity extends StatelessWidget {
  const _ThreadActivity({
    required this.siteUrl,
    required this.thread,
    required this.keyPrefix,
    required this.background,
  });

  final String siteUrl;
  final ChatThread thread;
  final String keyPrefix;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = thread.preview;
    final participants = preview == null ? 0 : _participantTotal(preview);
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          _replyCountLabel(thread.replyCount),
          key: ValueKey<String>('$keyPrefix-replies-${thread.id}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        if (preview != null && participants > 0)
          _ThreadParticipants(
            key: ValueKey<String>('$keyPrefix-participants-${thread.id}'),
            siteUrl: siteUrl,
            preview: preview,
            background: background,
          ),
      ],
    );
  }
}

class _ThreadParticipants extends StatelessWidget {
  const _ThreadParticipants({
    super.key,
    required this.siteUrl,
    required this.preview,
    required this.background,
  });

  final String siteUrl;
  final ChatThreadPreview preview;
  final Color background;

  static const double _avatarSize = 24;
  static const double _avatarStep = 16;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final users = _visibleParticipants(preview.participantUsers);
    final hidden = (_participantTotal(preview) - users.length).clamp(
      0,
      1 << 31,
    );
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
              clipBehavior: Clip.none,
              children: [
                for (final (index, user) in users.indexed)
                  Positioned(
                    left: index * _avatarStep,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: background,
                        shape: BoxShape.circle,
                        border: Border.all(color: background),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(1),
                        child: ChatUserAvatar(
                          siteUrl: siteUrl,
                          userId: user.id,
                          url: user.avatarUrl,
                          flair: user.flair,
                          size: _avatarSize - 4,
                          fallback: _AvatarFallback(name: user.displayName),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (hidden > 0) ...[
          if (users.isNotEmpty) const SizedBox(width: 5),
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
  const _AvatarFallback({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Center(
      child: Text(switch (_text(name)) {
        final value? => value.characters.first.toUpperCase(),
        _ => '?',
      }),
    ),
  );
}

class ChatThreadListMessage extends StatelessWidget {
  const ChatThreadListMessage({
    super.key,
    required this.icon,
    required this.message,
    this.action,
    this.onAction,
  });

  final DIconData icon;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: DEmpty(
        children: [
          DEmptyHeader(
            children: [
              DEmptyMedia(variant: DEmptyMediaVariant.icon, child: DIcon(icon)),
              DEmptyTitle(message),
            ],
          ),
          if (action case final label?)
            DEmptyContent(
              children: [DButton(label: Text(label), onPressed: onAction)],
            ),
        ],
      ),
    ),
  );
}

String _replyCountLabel(int count) => count == 1 ? '1 reply' : '$count replies';

int _participantTotal(ChatThreadPreview preview) {
  final serialized = preview.participantUsers.length;
  final reported = preview.participantCount ?? serialized;
  return reported < serialized ? serialized : reported;
}

List<ChatMessageAuthor> _visibleParticipants(
  List<ChatMessageAuthor> participants,
) => participants.length <= 3
    ? participants
    : [participants[0], participants[1], participants.last];

String? _text(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Color _threadIndicatorColor(BuildContext context, ChatThread thread) {
  final colors = Theme.of(context).discourse;
  final tracking = thread.tracking;
  return tracking.mentionCount + tracking.watchedThreadsUnreadCount > 0
      ? colors.success
      : colors.notificationIndicator;
}
