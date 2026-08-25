import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/d_icons.dart';
import '../plugin_scope.dart';
import '../plugin_services.dart';
import 'chat_controller.dart';
import 'chat_my_threads_view.dart';

/// The active thread index for one Chat channel.
///
/// Discourse serves this independently from the message stream and reorders
/// it as tracking and reply events arrive. [ChatController] owns that live
/// projection; this widget owns only the visible page and its scroll trigger.
class ChatChannelThreadsView extends StatefulWidget {
  const ChatChannelThreadsView({
    super.key,
    required this.siteUrl,
    required this.channelId,
  });

  final String siteUrl;
  final int channelId;

  @override
  State<ChatChannelThreadsView> createState() => _ChatChannelThreadsViewState();
}

class _ChatChannelThreadsViewState extends State<ChatChannelThreadsView> {
  late final ChatController _chat;
  late final ScrollController _scroll;
  Object? _viewToken;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController()..addListener(_maybeLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_ready) return;
      _viewToken = _chat.beginViewingChannel(widget.siteUrl, widget.channelId);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _chat = PluginScope.require(context, chatControllerService);
    _ready = true;
    unawaited(_chat.loadChannelThreads(widget.siteUrl, widget.channelId));
  }

  @override
  void dispose() {
    if (_viewToken case final token?) {
      _chat.endViewingChannel(widget.siteUrl, widget.channelId, token);
    }
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients || _scroll.position.extentAfter > 600) return;
    unawaited(
      _chat.loadChannelThreads(widget.siteUrl, widget.channelId, more: true),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _chat,
    builder: (context, _) {
      final threads = _chat.channelThreads(widget.siteUrl, widget.channelId);
      final error = _chat.channelThreadsError(widget.siteUrl, widget.channelId);
      if (_chat.channelThreadsLoading(widget.siteUrl, widget.channelId)) {
        return const Center(child: CircularProgressIndicator.adaptive());
      }
      if (threads.isEmpty && error != null) {
        return ChatThreadListMessage(
          icon: DIcons.triangleExclamation,
          message: error,
          action: 'Try again',
          onAction: () => unawaited(
            _chat.loadChannelThreads(
              widget.siteUrl,
              widget.channelId,
              force: true,
            ),
          ),
        );
      }
      if (threads.isEmpty &&
          _chat.channelThreadsLoaded(widget.siteUrl, widget.channelId)) {
        return const ChatThreadListMessage(
          icon: DIcons.comments,
          message: 'There are no active threads in this channel.',
        );
      }

      final hasFooter =
          _chat.channelThreadsLoadingMore(widget.siteUrl, widget.channelId) ||
          error != null ||
          _chat.channelThreadsHaveMore(widget.siteUrl, widget.channelId);
      return RefreshIndicator.adaptive(
        onRefresh: () => _chat.loadChannelThreads(
          widget.siteUrl,
          widget.channelId,
          force: true,
        ),
        child: ListView.separated(
          key: PageStorageKey<String>(
            'chat-channel-${widget.channelId}-threads',
          ),
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
                showChannel: false,
                keyPrefix: 'chat-channel-thread',
              );
            }
            if (_chat.channelThreadsLoadingMore(
              widget.siteUrl,
              widget.channelId,
            )) {
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
                      _chat.loadChannelThreads(
                        widget.siteUrl,
                        widget.channelId,
                        more: true,
                      ),
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
