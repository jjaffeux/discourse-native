import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_browse_navigation.dart';
import 'chat_browse_skeleton.dart';
import 'chat_chrome_scroll_view.dart';
import 'chat_controller.dart';
import 'chat_message.dart';
import 'chat_plugin.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';
import 'chat_thread.dart';
import 'chat_thread_directory.dart';
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
  late final ChatThreadDirectory _directory;
  VoidCallback? _unregisterRefresher;
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
    _channelId = _chat.inboxFilters.browseFor(widget.siteUrl).threadChannelId;
    _ready = true;
    _directory = ChatThreadDirectory(_chat, widget.siteUrl);
    _unregisterRefresher = PluginUiScope.require(context, chatShellService)
        .registerRouteRefresher(
          widget.siteUrl,
          ChatPlugin.myThreadsRouteId,
          () => _directory.load(reset: true),
        );
    unawaited(_directory.load());
  }

  @override
  void dispose() {
    _unregisterRefresher?.call();
    if (_ready) _directory.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // A failed page is retried only from its Try again row: every scroll
  // update near the end would otherwise resend it as soon as it fails.
  void _maybeLoadMore() {
    if (!_scroll.hasClients ||
        _directory.error(_channelId) != null ||
        _scroll.position.extentAfter >
            paginationPrefetchDistance(_scroll.position)) {
      return;
    }
    unawaited(_directory.load(channelId: _channelId));
  }

  int? _channelId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _directory,
    builder: (context, _) {
      final all = _directory.threads;
      final channels = _directory.channels;
      final threads = [
        for (final thread in all)
          if (_channelId == null || thread.channelId == _channelId) thread,
      ];
      final error = _directory.error(_channelId);
      final hasMore = _directory.hasMore(_channelId);
      final hasFooter = _directory.loading || error != null || hasMore;
      Widget item(BuildContext context, int index) {
        if (index < threads.length) {
          return Column(
            children: [
              const DSeparator(),
              ChatBrowseThreadRow(
                siteUrl: widget.siteUrl,
                thread: threads[index],
              ),
            ],
          );
        }
        if (_directory.loading) {
          return const ChatBrowseSkeleton(
            page: ChatBrowsePage.threads,
            rows: 2,
          );
        }
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) Text(error),
              DButton(
                label: Text(
                  error == null ? context.l10n.loadMore : context.l10n.tryAgain,
                ),
                onPressed: () =>
                    unawaited(_directory.load(channelId: _channelId)),
              ),
            ],
          ),
        );
      }

      return ChatChromeScrollView(
        header: ContentReadingLaneBox(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DSpacing.md,
            children: [
              ChatBrowseNavigation(
                siteUrl: widget.siteUrl,
                page: ChatBrowsePage.threads,
              ),
              ChatBrowseFilter<int>(
                key: const ValueKey('chat-threads-channel-filter'),
                label: _channelId == null
                    ? context.l10n.channel
                    : channels
                              .where((c) => c.id == _channelId)
                              .firstOrNull
                              ?.title ??
                          context.l10n.channel,
                semanticLabel: context.l10n.channel,
                icon: Text(
                  '■',
                  style: TextStyle(
                    color:
                        channels
                            .where((c) => c.id == _channelId)
                            .firstOrNull
                            ?.categoryColor ??
                        DTokens.of(context).mutedForeground,
                  ),
                ),
                emphasized: _channelId != null,
                value: _channelId ?? 0,
                entries: [
                  DSelectOption(
                    value: 0,
                    label: context.l10n.allChannels,
                    child: Text(context.l10n.allChannels),
                  ),
                  for (final channel in channels)
                    DSelectOption(
                      value: channel.id,
                      label: channel.title,
                      child: Text(channel.title),
                    ),
                ],
                onChanged: (id) {
                  setState(() => _channelId = id == 0 ? null : id);
                  _chat.inboxFilters.browseFor(widget.siteUrl).threadChannelId =
                      _channelId;
                },
              ),
            ],
          ),
        ),
        list: (context, lazy) {
          if (_directory.loading && !_directory.loaded) {
            return ContentReadingLane(
              basePadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              builder: (context, lane) => ChatBrowseSkeleton(
                page: ChatBrowsePage.threads,
                scrollable: lazy,
                padding: lane.padding,
              ),
            );
          }
          if (threads.isEmpty && !hasFooter) {
            return ChatThreadListMessage(
              icon: DIcons.comments,
              message: _channelId == null
                  ? context.l10n.noChatThreadsYet
                  : context.l10n.noThreadsInThisChannel,
            );
          }
          final count = threads.length + (hasFooter ? 1 : 0);
          return ContentReadingLane(
            basePadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            builder: (context, lane) => lazy
                ? ListView.builder(
                    key: const PageStorageKey('chat-my-threads'),
                    controller: _scroll,
                    padding: lane.padding,
                    itemCount: count,
                    itemBuilder: item,
                  )
                : Padding(
                    padding: lane.padding,
                    child: Column(
                      children: [
                        for (var index = 0; index < count; index++)
                          item(context, index),
                      ],
                    ),
                  ),
          );
        },
      );
    },
  );
}

class ChatBrowseThreadRow extends StatelessWidget {
  const ChatBrowseThreadRow({
    super.key,
    required this.siteUrl,
    required this.thread,
  });
  final String siteUrl;
  final ChatThread thread;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _buildRow);

  Widget _buildRow(BuildContext context, BoxConstraints constraints) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final channel = chat.channel(siteUrl, thread.channelId);
    final preview = thread.preview;
    final original = thread.originalMessage;
    final author =
        preview?.lastReplyUser ?? (preview == null ? original?.author : null);
    final title =
        _text(thread.title) ??
        _text(original?.excerpt) ??
        _text(original?.message) ??
        context.l10n.thread;
    final excerpt =
        _text(preview?.lastReplyExcerpt) ??
        (preview == null
            ? _text(original?.excerpt) ?? _text(original?.message)
            : null) ??
        context.l10n.noRepliesYetChatmythreadsview;
    final unread =
        thread.tracking.unreadCount > 0 ||
        thread.tracking.mentionCount > 0 ||
        thread.tracking.watchedThreadsUnreadCount > 0;
    return DItem(
      key: ValueKey('chat-my-thread-${thread.id}'),
      shape: DItemShape.fullWidth,
      padding: constraints.maxWidth < 600
          ? const EdgeInsets.symmetric(vertical: DSpacing.md)
          : null,
      semanticLabel: context.l10n.openThread(
        (channel == null).toString(),
        (unread).toString(),
        (title).toString(),
        (_replyCountLabel(thread.replyCount)).toString(),
        ((!(channel == null)) ? (channel.title) : '').toString(),
      ),
      onPressed: () => unawaited(_open(context, chat)),
      children: [
        DItemContent(
          spacing: DSpacing.xs,
          children: [
            Row(
              spacing: DSpacing.xs,
              children: [
                const Text('#'),
                Expanded(
                  child: Text(
                    channel?.title ?? context.l10n.chat,
                    style: TextStyle(
                      color: DTokens.of(context).mutedForeground,
                    ),
                  ),
                ),
                if (unread)
                  DNotificationDot(
                    key: ValueKey('chat-my-thread-unread-${thread.id}'),
                    color: _threadIndicatorColor(context, thread),
                    semanticLabel: context.l10n.unread,
                  ),
              ],
            ),
            DItemTitle(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Row(
              spacing: DSpacing.controlGap,
              children: [
                ChatUserAvatar(
                  siteUrl: siteUrl,
                  userId: author?.id ?? 0,
                  url: author?.avatarUrl ?? preview?.lastReplyAvatarUrl,
                  size: 18,
                  fallback: DAvatarFallback(
                    child: Text(
                      (author?.displayName ?? preview?.lastReplyUsername ?? '?')
                          .characters
                          .first
                          .toUpperCase(),
                    ),
                  ),
                ),
                Expanded(
                  child: DItemDescription(
                    child: Text(
                      excerpt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Text(
                  _replyCountLabel(thread.replyCount),
                  key: ValueKey('chat-my-thread-replies-${thread.id}'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: DTokens.of(context).mutedForeground,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
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
      if (context.mounted) {
        DToast.show(
          context,
          appL10n.couldNotOpenThisChatThread,
          type: DToastType.error,
        );
      }
    }
  }
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
        context.l10n.thread;
    final latestName =
        _text(preview?.lastReplyUser?.displayName) ??
        _text(preview?.lastReplyUsername);
    final latestExcerpt = _text(preview?.lastReplyExcerpt);
    Widget latestText(String? latestTime) {
      final latest = [
        if (latestName != null) '$latestName:',
        ?latestExcerpt,
        if (latestTime != null) '· $latestTime',
      ].join(' ');
      return Text(
        latest.isEmpty ? _replyCountLabel(thread.replyCount) : latest,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final semantics = StringBuffer(
      context.l10n.openThreadChatmythreadsview((title).toString()),
    );
    if (channel != null) {
      semantics.write(
        context.l10n.messageInChatmythreadsview((channel.title).toString()),
      );
    }
    if (unread) semantics.write(context.l10n.unreadChatmythreadsview);
    semantics.write(', ${_replyCountLabel(thread.replyCount)}.');
    if (preview case final value?) {
      final participants = _participantTotal(value);
      if (participants > 0) {
        semantics.write(context.l10n.messageChatmessagetile(participants));
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
                channelTitle: channel?.title ?? context.l10n.chat,
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
                        channel?.title ?? context.l10n.chat,
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
                      child: switch (preview?.lastReplyAt) {
                        final at? => RelativeTimeBuilder(
                          when: at,
                          builder: (context, time) => latestText(time),
                        ),
                        null => latestText(null),
                      },
                    ),
                  ],
                ),
                trailing: unread
                    ? DNotificationDot(
                        color: _threadIndicatorColor(context, thread),
                        semanticLabel: context.l10n.unread,
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
        appL10n.couldNotOpenThisChatThread,
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
                            semanticLabel: context.l10n.unread,
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
      at: latestAt,
      excerpt:
          latestExcerpt ??
          (thread.replyCount == 0
              ? context.l10n.noRepliesYetChatmythreadsview
              : context.l10n.latestReplyChatmythreadsview),
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
    required this.at,
    required this.excerpt,
    required this.compact,
  });

  final String siteUrl;
  final int? userId;
  final UserStatus? status;
  final String? name;
  final DateTime? at;
  final String excerpt;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (name != null || at != null || status != null)
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
              if (at case final value?) ...[
                if (name != null || status != null) const SizedBox(width: 6),
                RelativeTimeText(
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
        if (name != null || at != null || status != null)
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

String _replyCountLabel(int count) => countLabel(count, CountNoun.reply);

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
