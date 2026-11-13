import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_browse_navigation.dart';
import 'chat_browse_skeleton.dart';
import 'chat_controller.dart';
import 'chat_my_threads_view.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';
import 'chat_stream_target.dart';
import 'chat_view_lifetime.dart';

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
  late ChatController _chat;
  ChatViewLifetime? _viewing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chat = PluginUiScope.require(context, chatControllerService);
    final shell = PluginUiScope.require(context, chatShellService);
    if (_viewing == null || !identical(chat, _chat)) {
      _viewing?.dispose();
      _chat = chat;
      _viewing = ChatViewLifetime(
        chat: chat,
        siteUrl: widget.siteUrl,
        target: ChatChannelTarget(widget.channelId),
      );
      // Live events never add a thread to a held list, so each visit
      // revalidates it behind the rows already shown.
      unawaited(
        _chat.loadChannelThreads(
          widget.siteUrl,
          widget.channelId,
          revalidate: true,
        ),
      );
    }
    _viewing!.bind(shell, tickerEnabled: TickerMode.valuesOf(context).enabled);
  }

  @override
  void dispose() {
    _viewing?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DPullToRefresh(
    key: ValueKey((widget.siteUrl, widget.channelId)),
    onRefresh: () =>
        _chat.loadChannelThreads(widget.siteUrl, widget.channelId, force: true),
    child: AnimatedBuilder(
      animation: _chat,
      builder: (context, _) {
        final threads = _chat.channelThreads(widget.siteUrl, widget.channelId);
        final error = _chat.channelThreadsError(
          widget.siteUrl,
          widget.channelId,
        );
        final loadingMore = _chat.channelThreadsLoadingMore(
          widget.siteUrl,
          widget.channelId,
        );
        final loading = _chat.channelThreadsLoading(
          widget.siteUrl,
          widget.channelId,
        );
        final hasMore = _chat.channelThreadsHaveMore(
          widget.siteUrl,
          widget.channelId,
        );
        if (threads.isEmpty && (loading || loadingMore)) {
          return ContentReadingLane(
            basePadding: const EdgeInsets.symmetric(vertical: 8),
            builder: (context, lane) => ChatBrowseSkeleton(
              page: ChatBrowsePage.threads,
              scrollable: true,
              padding: lane.padding,
            ),
          );
        }
        if (threads.isEmpty && error != null && !hasMore) {
          return ChatThreadListMessage(
            icon: DIcons.triangleExclamation,
            message: error,
            action: context.l10n.tryAgain,
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
            !hasMore &&
            _chat.channelThreadsLoaded(widget.siteUrl, widget.channelId)) {
          return ChatThreadListMessage(
            icon: DIcons.comments,
            message: context.l10n.thereAreNoActiveThreadsInThisChannel,
          );
        }

        final hasFooter = loadingMore || error != null || hasMore;
        final content = ContentReadingLane(
          basePadding: const EdgeInsets.symmetric(vertical: 8),
          builder: (context, lane) => ListView.separated(
            key: PageStorageKey<String>(
              'chat-channel-${widget.channelId}-threads',
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: lane.padding,
            itemCount: threads.length + (hasFooter ? 1 : 0),
            separatorBuilder: (_, _) => const DSeparator(space: 1),
            itemBuilder: (context, index) {
              if (index < threads.length) {
                return ChatThreadListRow(
                  siteUrl: widget.siteUrl,
                  thread: threads[index],
                  showChannel: false,
                  keyPrefix: 'chat-channel-thread',
                );
              }
              if (loadingMore) {
                return const ChatBrowseSkeleton(
                  page: ChatBrowsePage.threads,
                  rows: 2,
                );
              }
              if (error == null) {
                return ScrollPageTrigger(
                  enabled: hasMore && !loading,
                  onLoad: () => unawaited(
                    _chat.loadChannelThreads(
                      widget.siteUrl,
                      widget.channelId,
                      more: true,
                    ),
                  ),
                  child: const SizedBox.shrink(),
                );
              }
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    DButton(
                      label: Text(context.l10n.tryAgain),
                      onPressed: () => unawaited(
                        _chat.retryChannelThreads(
                          widget.siteUrl,
                          widget.channelId,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
        return DScrollChromePagination(
          hasMore: _chat.channelThreadsHaveMore(
            widget.siteUrl,
            widget.channelId,
          ),
          loading: loadingMore,
          child: content,
        );
      },
    ),
  );
}
