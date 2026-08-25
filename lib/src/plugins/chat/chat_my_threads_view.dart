import 'dart:async';

import 'package:flutter/material.dart';

import '../../shell/relative_time.dart';
import '../../shell/shell_scope.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../plugin_scope.dart';
import '../plugin_services.dart';
import 'chat_controller.dart';
import 'chat_thread.dart';
import 'chat_user_avatar.dart';

/// The account-level thread list behind Discourse Chat's "My Threads" route.
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
    _chat = PluginScope.require(context, chatControllerService);
    _ready = true;
    unawaited(_chat.loadMyThreads(widget.siteUrl));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients || _scroll.position.extentAfter > 600) return;
    unawaited(_chat.loadMyThreads(widget.siteUrl, more: true));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _chat,
    builder: (context, _) {
      final threads = _chat.myThreads(widget.siteUrl);
      final error = _chat.myThreadsError(widget.siteUrl);
      if (_chat.myThreadsLoading(widget.siteUrl)) {
        return const Center(child: CircularProgressIndicator.adaptive());
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
      return RefreshIndicator.adaptive(
        onRefresh: () => _chat.loadMyThreads(widget.siteUrl, force: true),
        child: ListView.separated(
          key: const PageStorageKey('chat-my-threads'),
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: threads.length + (hasFooter ? 1 : 0),
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index < threads.length) {
              return ChatThreadListRow(
                siteUrl: widget.siteUrl,
                thread: threads[index],
              );
            }
            if (_chat.myThreadsLoadingMore(widget.siteUrl)) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator.adaptive()),
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
                  OutlinedButton(
                    onPressed: () => unawaited(
                      _chat.loadMyThreads(widget.siteUrl, more: true),
                    ),
                    child: Text(error == null ? 'Load more' : 'Try again'),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

/// One thread-list result shared by the account and channel routes.
class ChatThreadListRow extends StatelessWidget {
  const ChatThreadListRow({
    super.key,
    required this.siteUrl,
    required this.thread,
    this.showChannel = true,
    this.keyPrefix = 'chat-my-thread',
  });

  final String siteUrl;
  final ChatThread thread;
  final bool showChannel;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final chat = PluginScope.require(context, chatControllerService);
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
    semantics.write(', ${thread.replyCount} replies.');

    return Semantics(
      button: true,
      label: semantics.toString(),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: ValueKey<String>('$keyPrefix-${thread.id}'),
          onTap: () => unawaited(_open(context, chat)),
          leading: ChatUserAvatar(
            siteUrl: siteUrl,
            userId: author?.id ?? 0,
            url: author?.avatarUrl,
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
          subtitle: latest.isEmpty
              ? Text('${thread.replyCount} replies')
              : Text(latest, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: unread
              ? Semantics(
                  label: 'Unread',
                  child: Container(
                    key: ValueKey<String>('$keyPrefix-unread-${thread.id}'),
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
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
      ShellScope.read(context).openChatThread(
        siteUrl: siteUrl,
        channelId: channel.id,
        threadId: thread.id,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not open this chat thread.')),
      );
    }
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
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DIcon(icon, size: 28),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (action case final label?) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(label)),
          ],
        ],
      ),
    ),
  );
}

String? _text(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
