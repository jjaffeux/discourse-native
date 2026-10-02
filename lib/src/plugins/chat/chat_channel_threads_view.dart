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
  ChatShellService? _shell;
  Object? _viewToken;
  bool _viewStartScheduled = false;
  bool _ready = false;
  bool _tickerEnabled = true;

  bool get _viewerActive =>
      _ready && _tickerEnabled && (_shell?.forumActive ?? false);

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController()..addListener(_maybeLoadMore);
  }

  void _handleShellChanged() => _syncViewing();

  void _syncViewing() {
    if (!_viewerActive) {
      if (_viewToken case final token?) {
        _viewToken = null;
        _chat.endViewingChannel(widget.siteUrl, widget.channelId, token);
      }
      return;
    }
    if (_viewToken != null || _viewStartScheduled) return;
    _viewStartScheduled = true;
    // Advancing lastViewedAt updates the channel record consumed by the
    // sibling header, so wait until the current frame has finished building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewStartScheduled = false;
      if (!mounted || !_viewerActive || _viewToken != null) return;
      _viewToken = _chat.beginViewingChannel(widget.siteUrl, widget.channelId);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = PluginUiScope.require(context, chatShellService);
    if (!identical(shell, _shell)) {
      _shell?.removeListener(_handleShellChanged);
      _shell = shell..addListener(_handleShellChanged);
    }
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (!_ready) {
      _chat = PluginUiScope.require(context, chatControllerService);
      _ready = true;
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
    _syncViewing();
  }

  @override
  void dispose() {
    _shell?.removeListener(_handleShellChanged);
    if (_viewToken case final token?) {
      _chat.endViewingChannel(widget.siteUrl, widget.channelId, token);
    }
    _scroll.dispose();
    super.dispose();
  }

  // A failed page is retried only from its Try again row: every scroll
  // update near the end would otherwise resend it as soon as it fails.
  void _maybeLoadMore() {
    if (!_scroll.hasClients ||
        _chat.channelThreadsError(widget.siteUrl, widget.channelId) != null ||
        _scroll.position.extentAfter >
            paginationPrefetchDistance(_scroll.position)) {
      return;
    }
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
      final loadingMore = _chat.channelThreadsLoadingMore(
        widget.siteUrl,
        widget.channelId,
      );
      if (threads.isEmpty &&
          (_chat.channelThreadsLoading(widget.siteUrl, widget.channelId) ||
              loadingMore)) {
        return ContentReadingLane(
          basePadding: const EdgeInsets.symmetric(vertical: 8),
          builder: (context, lane) => ChatBrowseSkeleton(
            page: ChatBrowsePage.threads,
            scrollable: true,
            padding: lane.padding,
          ),
        );
      }
      if (threads.isEmpty && error != null) {
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
          _chat.channelThreadsLoaded(widget.siteUrl, widget.channelId)) {
        return ChatThreadListMessage(
          icon: DIcons.comments,
          message: context.l10n.thereAreNoActiveThreadsInThisChannel,
        );
      }

      final hasFooter =
          loadingMore ||
          error != null ||
          _chat.channelThreadsHaveMore(widget.siteUrl, widget.channelId);
      return ContentReadingLane(
        basePadding: const EdgeInsets.symmetric(vertical: 8),
        builder: (context, lane) => ListView.separated(
          key: PageStorageKey<String>(
            'chat-channel-${widget.channelId}-threads',
          ),
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
                    label: Text(
                      error == null
                          ? context.l10n.loadMore
                          : context.l10n.tryAgain,
                    ),
                    onPressed: () => unawaited(
                      error == null
                          ? _chat.loadChannelThreads(
                              widget.siteUrl,
                              widget.channelId,
                              more: true,
                            )
                          : _chat.retryChannelThreads(
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
    },
  );
}
