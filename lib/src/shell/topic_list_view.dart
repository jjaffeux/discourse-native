import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../app_shortcuts.dart';
import '../diagnostics/diagnostics_scope.dart';
import '../diagnostics/topic_scroll_capture.dart';
import '../models/discourse_instance.dart';
import '../models/topic.dart';
import '../models/topic_feed.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import '../theme/discourse_typography.dart';
import '../utils/pagination.dart';
import 'avatar_image.dart';
import 'category_icon.dart';
import 'content_reading_lane.dart';
import 'keyboard_navigation.dart';
import 'list_boundary_shortcuts.dart';
import 'open_link.dart';
import 'platform.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'site_emoji_text.dart';
import 'site_url.dart';
import 'skeleton_fill.dart';
import 'topic_list_indicators.dart';
import 'topic_list_layout.dart';
import 'topic_title.dart';

part 'topic_row_content.dart';
part 'conversation_topic_card.dart';

typedef _TopicListIdentity = (String?, String?, String?, String);
typedef _TopicListCursor = ({int topicId, int index, bool keyboard});

class TopicListView extends StatefulWidget {
  const TopicListView({
    super.key,
    required this.feed,
    this.inbox = false,
    this.showHeader = true,
  });

  final TopicFeed feed;
  final bool inbox;
  final bool showHeader;

  @override
  State<TopicListView> createState() => _TopicListViewState();
}

class _TopicListViewState extends State<TopicListView> {
  ScrollController? _scroll;
  ListController? _list;
  _TopicListIdentity? _feedIdentity;
  final ReadingFocusNode _keyboardFocus = ReadingFocusNode(
    debugLabel: 'Topic list cursor',
  );
  ValueNotifier<_TopicListCursor?>? _cursor;
  Object? _keyboardMoveToken;
  Object? _loadMoreToken;
  bool _restored = false;
  int? _readingTopicId;
  int _boundaryJumpRevision = 0;

  ShellController? _controller;
  StreamSubscription<int>? _topicListRevealSubscription;
  TopicScrollCaptureController? _scrollCapture;
  (TopicScrollCaptureController, int, _TopicListIdentity?)? _captureContext;

  bool get _recording => _scrollCapture?.isRecording == true;

  @override
  void didUpdateWidget(TopicListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    final identity = _feedIdentity;
    final list = _list;
    final scroll = _scroll;
    if (controller == null ||
        identity == null ||
        !_isCurrent(controller, identity) ||
        !controller.currentFeedIsUnread ||
        list?.isAttached != true ||
        scroll?.hasClients != true) {
      return;
    }
    final previous = oldWidget.feed.topicIds;
    final next = widget.feed.topicIds;
    final remaining = next.toSet();
    if (next.isEmpty || !previous.any((id) => !remaining.contains(id))) return;
    final range = list!.visibleRange;
    if (range == null) return;
    final visible = [
      for (
        var i = range.$1 ~/ 2;
        i <= range.$2 ~/ 2 && i < previous.length;
        i++
      )
        if (remaining.contains(previous[i])) previous[i],
    ];
    final selected = controller.readingTopicId;
    final anchor = visible.contains(selected) ? selected : visible.firstOrNull;
    if (anchor == null) return;
    final anchorBox = _renderedRow(previous.indexOf(anchor));
    if (anchorBox == null) return;
    final top = anchorBox.localToGlobal(Offset.zero).dy;
    final readingTopicId = controller.readingTopicId;
    void restore({bool correct = true}) {
      if (!_isCurrent(controller, identity) ||
          !identical(widget.feed.topicIds, next) ||
          controller.readingTopicId != readingTopicId ||
          !identical(_list, list) ||
          !list.isAttached ||
          !scroll!.hasClients) {
        return;
      }
      final box = _renderedRow(next.indexOf(anchor));
      if (box == null) {
        list.jumpToItem(
          index: next.indexOf(anchor) * 2,
          scrollController: scroll,
          alignment: 0,
        );
      } else {
        final target = scroll.offset + box.localToGlobal(Offset.zero).dy - top;
        if (!target.isFinite) return;
        scroll.jumpTo(
          target.clamp(
            scroll.position.minScrollExtent,
            scroll.position.maxScrollExtent,
          ),
        );
      }
      if (correct) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => restore(correct: false),
        );
        WidgetsBinding.instance.scheduleFrame();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => restore());
  }

  RenderBox? _renderedRow(int topicIndex) {
    RenderBox? result;
    void visit(RenderObject object) {
      if (result != null) return;
      if (object is RenderSliverMultiBoxAdaptor) {
        var child = object.firstChild;
        while (child != null) {
          if (object.indexOf(child) == topicIndex * 2 && child.hasSize) {
            result = child;
            return;
          }
          child = object.childAfter(child);
        }
        return;
      }
      object.visitChildren(visit);
    }

    final root = context.findRenderObject();
    if (root != null) visit(root);
    return result;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollCapture = DiagnosticsScope.maybeRead(context)?.topicScrollCapture;
  }

  void _recordScrollEvent(String name, Map<String, Object?> data) {
    final capture = _scrollCapture;
    if (capture == null || !capture.isRecording) return;
    final identity = (capture, capture.captureId, _feedIdentity);
    if (_captureContext != identity) {
      _captureContext = identity;
      capture.recordTopicEvent('topicList.capture.context', {
        'topicCount': widget.feed.topicIds.length,
        'inbox': widget.inbox,
        'mode': 'card',
        if (_scroll?.hasClients == true)
          'viewportExtent': _scroll!.position.viewportDimension,
        'devicePixelRatio': View.of(context).devicePixelRatio,
      });
    }
    capture.recordTopicEvent(name, data);
  }

  void _revealCursor() {
    if (_cursor?.value == null) return;
    final controller = _controller!;
    final identity = _feedIdentity!;
    final cursor = _cursor!.value!;
    final topicId = controller.readingTopicId;
    void reveal({bool correct = true}) {
      if (!_isCurrent(controller, identity) ||
          controller.readingTopicId != topicId ||
          _cursor?.value != cursor ||
          !TickerMode.valuesOf(context).enabled) {
        return;
      }
      final index = widget.feed.topicIds.indexOf(cursor.topicId);
      if (index < 0) return;
      _jumpTo(index * 2);
      if (correct) {
        // Inbox rows have different heights. Correct once they are measured.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => reveal(correct: false),
        );
        WidgetsBinding.instance.scheduleFrame();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => reveal());
    WidgetsBinding.instance.scheduleFrame();
  }

  void _revealTopic(int topicId) {
    final controller = _controller;
    final identity = _feedIdentity;
    if (!widget.inbox ||
        controller == null ||
        identity == null ||
        controller.readingTopicId != topicId ||
        !_isCurrent(controller, identity)) {
      return;
    }
    _rememberTopic(topicId);
    _revealCursor();
  }

  void _syncControllers(_TopicListIdentity feedIdentity) {
    if (_feedIdentity == feedIdentity) return;

    _disposeControllers();
    _feedIdentity = feedIdentity;
    _loadMoreToken = null;
    _restored = false;
    _readingTopicId = null;
    _scroll = ScrollController();
    _list = ListController();
    _keyboardMoveToken = null;
    final saved = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: ('topic-list-keyboard', feedIdentity));
    _cursor = ValueNotifier(saved is _TopicListCursor ? saved : null);
  }

  void _restore(
    ShellController controller,
    String destination,
    _TopicListIdentity feedIdentity,
  ) {
    if (_restored) return;
    _restored = true;

    final row = controller.feedScrollRow(destination, tabId: feedIdentity.$3);
    if (row <= 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrent(controller, feedIdentity)) return;
      _jumpTo(row);
      // The first jump was measured against estimated heights for rows that
      // had never been built. Now that the real ones are laid out, land on the
      // same row again.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isCurrent(controller, feedIdentity)) return;
        _jumpTo(row);
      });
    });
  }

  void _jumpTo(int row) {
    final list = _list;
    final scroll = _scroll;
    if (list == null || scroll == null) return;
    if (!list.isAttached || !scroll.hasClients) return;

    // The remembered row may belong to pages that have not been loaded yet,
    // or to a loading/error footer that is no longer present. Bound it by
    // both the extent table and the real topic rows in this frame.
    final renderedItemCount = list.numberOfItems;
    if (renderedItemCount == 0 || widget.feed.topicIds.isEmpty) return;
    // The separated list gives the controller interleaved topic/separator
    // indices, so topic N is extent index N * 2.
    final lastTopicIndex = (widget.feed.topicIds.length - 1) * 2;
    final lastRenderedTopicIndex = lastTopicIndex < renderedItemCount
        ? lastTopicIndex
        : renderedItemCount - 1;
    final target = row.clamp(0, lastRenderedTopicIndex);

    list.jumpToItem(index: target, scrollController: scroll, alignment: 0);
  }

  void _jumpToBoundary({required bool end}) {
    final revision = ++_boundaryJumpRevision;
    final list = _list;
    final scroll = _scroll;
    if (list == null || scroll == null || !scroll.hasClients) return;

    if (!end || !list.isAttached || list.numberOfItems == 0) {
      scroll.jumpTo(
        end ? scroll.position.maxScrollExtent : scroll.position.minScrollExtent,
      );
      return;
    }

    // SuperListView estimates unbuilt variable-height rows. Address the
    // terminal row first so it is measured, then correct to maxScrollExtent
    // after layout so trailing list padding is included too.
    final target = list.numberOfItems - 1;
    bool isCurrent() {
      if (!mounted || !identical(_list, list) || !identical(_scroll, scroll)) {
        return false;
      }
      return revision == _boundaryJumpRevision &&
          list.isAttached &&
          scroll.hasClients;
    }

    void correctToEnd({bool repeat = true}) {
      if (!isCurrent()) return;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      if (!repeat) return;

      WidgetsBinding.instance.addPostFrameCallback(
        (_) => correctToEnd(repeat: false),
      );
      WidgetsBinding.instance.scheduleFrame();
    }

    list.jumpToItem(index: target, scrollController: scroll, alignment: 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => correctToEnd());
    WidgetsBinding.instance.scheduleFrame();
  }

  void _disposeControllers() {
    // The outgoing controllers are still attached to the scrollable being
    // replaced this frame; disposing them before that detach happens would
    // leave the scrollable holding a dead position.
    final scroll = _scroll;
    final list = _list;
    final cursor = _cursor;
    if (scroll == null && list == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scroll?.dispose();
      list?.dispose();
      cursor?.dispose();
    });
  }

  @override
  void dispose() {
    unawaited(_topicListRevealSubscription?.cancel());
    // Rows are handed to the shell as they change, but the latest may still
    // be waiting out its debounce window. The torn-down list cannot move it
    // any more, so it is written now.
    _controller?.flushAnchorPersist();
    _disposeControllers();
    _keyboardFocus.dispose();
    super.dispose();
  }

  Future<void> _showIncoming(
    ShellController controller,
    String destination,
    _TopicListIdentity feedIdentity,
  ) async {
    await controller.showIncoming(destination);
    if (!_isCurrent(controller, feedIdentity)) return;

    // The rows only exist after the frame that draws them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrent(controller, feedIdentity)) return;
      final scroll = _scroll;
      if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
    });
  }

  void _scheduleLoadMore(
    ShellController controller,
    String destination,
    _TopicListIdentity feedIdentity,
    TopicFeed feed,
  ) {
    if (!feed.hasMore ||
        feed.loading ||
        feed.loadingMore ||
        feed.error != null ||
        _loadMoreToken != null) {
      return;
    }

    final token = Object();
    _loadMoreToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_loadMoreToken, token)) _loadMoreToken = null;
      if (!_isCurrent(controller, feedIdentity)) return;
      if (!identical(widget.feed, feed)) return;
      unawaited(controller.loadMoreFeed(destination));
    });
  }

  bool _isCurrent(
    ShellController controller,
    _TopicListIdentity feedIdentity,
  ) =>
      mounted &&
      _feedIdentity == feedIdentity &&
      controller.readTab(
            feedIdentity.$3,
            () => _currentFeedIdentity(controller),
          ) ==
          feedIdentity;

  static _TopicListIdentity _currentFeedIdentity(ShellController controller) {
    final siteUrl = controller.currentInstance?.url;
    final destination = controller.currentFeedId ?? 'latest';
    return (
      siteUrl,
      controller.currentAccountIdentity,
      controller.topicListTab?.id,
      destination,
    );
  }

  // A page can land in the controller a frame before this list rebuilds with
  // it. Read the list's own tab, not whichever tab is active.
  List<int> _latestTopicIds() {
    final controller = _controller;
    final identity = _feedIdentity;
    if (controller == null || identity == null) return widget.feed.topicIds;
    return controller
            .readTab(identity.$3, () => controller.currentFeed)
            ?.topicIds ??
        widget.feed.topicIds;
  }

  void _rememberTopic(int topicId, {bool? keyboard}) {
    final ids = _latestTopicIds();
    final index = ids.indexOf(topicId);
    if (index < 0) return;
    // Mouse navigation remembers the position without leaving a keyboard
    // highlight behind after the reader closes.
    final previous = _cursor!.value;
    final cursor = (
      topicId: topicId,
      index: index,
      keyboard:
          keyboard ?? (previous?.topicId == topicId && previous!.keyboard),
    );
    _cursor!.value = cursor;
    PageStorage.maybeOf(context)?.writeState(
      context,
      cursor,
      identifier: ('topic-list-keyboard', _feedIdentity),
    );
  }

  bool _moveSelection(int direction) {
    if (widget.feed.topicIds.isEmpty) return false;
    if (_keyboardMoveToken != null) return true;
    unawaited(_moveSelectionTo(direction));
    return true;
  }

  Future<void> _moveSelectionTo(int direction) async {
    final controller = _controller!;
    final identity = _feedIdentity!;
    final token = Object();
    _keyboardMoveToken = token;
    final route = controller.currentContent;
    bool isCurrent() =>
        _isCurrent(controller, identity) &&
        identical(_keyboardMoveToken, token) &&
        controller.currentContent == route &&
        navigationShortcutsAllowed(context);
    try {
      final ids = widget.feed.topicIds;
      final cursor = _cursor!.value;
      final anchor = cursor?.topicId ?? controller.readingTopicId;
      final index = anchor == null ? -1 : ids.indexOf(anchor);
      var target = index >= 0
          ? index + direction
          : cursor != null
          ? cursor.index + (direction < 0 ? -1 : 0)
          : (_list?.visibleRange?.$1 ?? 0) ~/ 2;
      if (target >= ids.length && widget.feed.hasMore) {
        await controller.loadMoreFeed(identity.$4);
        if (!isCurrent()) return;
      }
      final currentIds = _latestTopicIds();
      if (!isCurrent() || currentIds.isEmpty) return;
      target = target.clamp(0, currentIds.length - 1);
      _rememberTopic(currentIds[target], keyboard: true);
      _keyboardFocus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isCurrent()) return;
        _jumpTo(target * 2);
      });
      WidgetsBinding.instance.scheduleFrame();
    } finally {
      // Keep the token through the reveal callback, but accept the next key
      // after that frame. Context changes invalidate both callbacks.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (identical(_keyboardMoveToken, token)) _keyboardMoveToken = null;
      });
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  void _openRow(Topic topic, {bool keyboard = false}) {
    _keyboardMoveToken = null;
    _rememberTopic(topic.id, keyboard: keyboard);
    if (keyboard) FocusManager.instance.primaryFocus?.unfocus();
    final controller = _controller!;
    if (keyboard && controller.readingTopicId == topic.id) return;
    handleTabOpenResult(
      context,
      widget.inbox
          ? controller.openTopicFromList(topic, revealInList: keyboard)
          : controller.openTopic(topic),
    );
  }

  bool _openSelection() {
    final id = _cursor?.value?.topicId;
    final controller = _controller!;
    final siteUrl = controller.currentInstance?.url;
    if (id == null || siteUrl == null || !widget.feed.topicIds.contains(id)) {
      return false;
    }
    final topic = controller.store.read<Topic>(siteUrl, id);
    if (topic == null) return false;
    _openRow(topic, keyboard: true);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ShellSelector<_TopicListSnapshot>(
      select: _topicListSnapshot,
      builder: (context, state, _) => _build(context, state),
    );
  }

  Widget _build(BuildContext context, _TopicListSnapshot state) {
    final controller = ShellScope.read(context);
    if (!identical(_controller, controller)) {
      // A replaced shell keeps its own pending anchor window; this list no
      // longer feeds it, so the window is written rather than left behind.
      _controller?.flushAnchorPersist();
      unawaited(_topicListRevealSubscription?.cancel());
      _topicListRevealSubscription = controller.topicListRevealRequests.listen(
        _revealTopic,
      );
    }
    _controller = controller;
    final destination = state.destination;
    final feedIdentity = state.feedIdentity;

    return Column(
      children: [
        if (widget.showHeader) const TopicListHeader(),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _body(controller, destination, feedIdentity),
              if (state.incoming > 0 && !widget.feed.loadingIncoming)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _IncomingBanner(
                    count: state.incoming,
                    destination: destination,
                    onTap: () =>
                        _showIncoming(controller, destination, feedIdentity),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body(
    ShellController controller,
    String destination,
    _TopicListIdentity feedIdentity,
  ) {
    final feed = widget.feed;
    _syncControllers(feedIdentity);

    if (feed.loading && feed.topicIds.isEmpty) {
      return ContentReadingLaneBox(
        widthLimit: topicListContentWidth,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _TopicListLoadingSkeleton(
          key: const ValueKey('topic-list-loading-skeleton'),
          destination: destination,
        ),
      );
    }
    if (feed.error case final error? when feed.topicIds.isEmpty) {
      return _Message(
        icon: DIcons.triangleExclamation,
        text: error,
        actionLabel: 'Retry',
        onAction: () => unawaited(
          feed.pageError
              ? controller.loadMoreFeed(destination)
              : controller.loadFeed(destination),
        ),
      );
    }
    if (feed.isEmpty && feed.hasMore) {
      _scheduleLoadMore(controller, destination, feedIdentity, feed);
      // A filtered page can be empty while later pages still contain replies.
      return _TopicListLoadingSkeleton(destination: destination);
    }
    if (feed.isEmpty) {
      return _Message(
        icon: DIcons.inbox,
        text: controller.topicListContent?.topicListSearch.isNotEmpty == true
            ? 'No topics found. Try another search or change the filters.'
            : controller.currentFeedIsUnread
            ? "You're all caught up."
            : 'Nothing here yet.',
      );
    }

    _restore(controller, destination, feedIdentity);
    if (_recording) {
      _recordScrollEvent('topicList.view.built', {
        'topicCount': feed.topicIds.length,
      });
    }
    final readingTopicId = widget.inbox ? controller.readingTopicId : null;
    final hiddenCategoryId = controller.topicListContent?.categoryId;
    if (_readingTopicId != readingTopicId) {
      _readingTopicId = readingTopicId;
      if (readingTopicId == null) {
        if (context.isTouch) _revealCursor();
      } else if (feed.topicIds.contains(readingTopicId)) {
        _rememberTopic(readingTopicId);
      }
    }

    return Column(
      children: [
        if (feed.error case final error? when !feed.pageError)
          _FeedErrorBanner(
            key: const ValueKey('topic-feed-refresh-error'),
            message: error,
            onRetry: () => unawaited(controller.loadFeed(destination)),
          ),
        Expanded(
          child: ContentReadingLane(
            widthLimit: topicListContentWidth,
            basePadding: EdgeInsets.zero,
            builder: (context, lane) => NotificationListener<ScrollNotification>(
              // Fetching on a scroll notification rather than from
              // itemBuilder keeps the request off the hot path of building
              // rows. Both paths coalesce through a post-frame callback
              // because a viewport can emit a scroll notification while
              // applying new content dimensions during layout.
              onNotification: (notification) {
                if (notification.depth != 0) return false;
                final stopwatch = _recording ? (Stopwatch()..start()) : null;
                // Opening a topic tears this list down, so the position has
                // to be handed to the controller as it changes rather than
                // on dispose.
                if (_isCurrent(controller, feedIdentity) &&
                    _list?.isAttached == true) {
                  if (_list!.visibleRange case final range?) {
                    controller.saveFeedScrollRow(
                      destination,
                      range.$1,
                      tabId: feedIdentity.$3,
                    );
                  }
                }
                if (notification.metrics.extentAfter <
                    paginationPrefetchDistance(notification.metrics)) {
                  _scheduleLoadMore(
                    controller,
                    destination,
                    feedIdentity,
                    feed,
                  );
                }
                if (stopwatch != null) {
                  stopwatch.stop();
                  _recordScrollEvent('topicList.scroll.notification', {
                    'type': notification.runtimeType.toString(),
                    'pixels': notification.metrics.pixels,
                    'maxScrollExtent': notification.metrics.maxScrollExtent,
                    'viewportExtent': notification.metrics.viewportDimension,
                    'durationUs': stopwatch.elapsedMicroseconds,
                    if (_list?.isAttached == true)
                      if (_list!.visibleRange case final range?)
                        'visibleRange': [range.$1, range.$2],
                  });
                }
                return false;
              },
              // SuperListView preserves measured heights for variably sized
              // rows.
              child: ReadingShortcuts(
                commands: {
                  ReadingCommand.nextTopic: () => _moveSelection(1),
                  ReadingCommand.previousTopic: () => _moveSelection(-1),
                  ReadingCommand.nextPost: () =>
                      controller.currentContent?.isTopic != true &&
                      _moveSelection(1),
                  ReadingCommand.previousPost: () =>
                      controller.currentContent?.isTopic != true &&
                      _moveSelection(-1),
                  ReadingCommand.openTopic: _openSelection,
                },
                child: ListBoundaryShortcuts(
                  key: ValueKey(('topic-list-boundary', feedIdentity)),
                  debugLabel: 'topic list',
                  initiallyActive: controller.currentContent?.isTopic != true,
                  scrollController: _scroll!,
                  focusNode: _keyboardFocus,
                  onStart: () => _jumpToBoundary(end: false),
                  onEnd: () => _jumpToBoundary(end: true),
                  child: SuperListView.separated(
                    // Switching destinations swaps the controller, so the
                    // scrollable has to be a new one rather than re-attached
                    // to a different controller.
                    key: ValueKey(feedIdentity),
                    physics: const AlwaysScrollableScrollPhysics(),
                    controller: _scroll,
                    listController: _list,
                    // During a fast fling, build the visible rows first. The
                    // sliver fills its cache once scrolling slows down.
                    delayPopulatingCacheArea: true,
                    extentEstimation: _estimateExtent,
                    padding: lane.padding,
                    itemCount:
                        feed.topicIds.length +
                        (feed.loadingMore || feed.pageError ? 1 : 0),
                    findChildIndexCallback: (key) {
                      if (key is! ValueKey<int>) return null;
                      final index = feed.topicIds.indexOf(key.value);
                      // The separated delegate addresses topics and gaps.
                      return index < 0 ? null : index * 2;
                    },
                    separatorBuilder: (context, index) => lane.width >= 600
                        ? const DSeparator()
                        : ValueListenableBuilder<_TopicListCursor?>(
                            valueListenable: _cursor!,
                            builder: (context, cursor, _) {
                              final current = feed.topicIds[index];
                              final next = index + 1 < feed.topicIds.length
                                  ? feed.topicIds[index + 1]
                                  : null;
                              final keyboardId =
                                  cursor != null &&
                                      (cursor.keyboard ||
                                          readingTopicId == cursor.topicId)
                                  ? cursor.topicId
                                  : null;
                              final selectedId = widget.inbox
                                  ? readingTopicId
                                  : null;
                              return TopicListSeparator(
                                besideSelection:
                                    current == keyboardId ||
                                    next != null && next == keyboardId ||
                                    current == selectedId ||
                                    next != null && next == selectedId,
                              );
                            },
                          ),
                    itemBuilder: (context, index) {
                      if (_recording) {
                        _recordScrollEvent('topicList.row.built', {
                          'index': index,
                        });
                      }
                      if (index >= feed.topicIds.length) {
                        if (feed.loadingMore) {
                          return const _LoadingMoreRow();
                        }
                        return _LoadMoreErrorRow(
                          message: feed.error!,
                          onRetry: () =>
                              unawaited(controller.loadMoreFeed(destination)),
                        );
                      }

                      if (index == feed.topicIds.length - 1 && feed.hasMore) {
                        _scheduleLoadMore(
                          controller,
                          destination,
                          feedIdentity,
                          feed,
                        );
                      }

                      final topicId = feed.topicIds[index];
                      return ValueListenableBuilder<_TopicListCursor?>(
                        key: ValueKey(topicId),
                        valueListenable: _cursor!,
                        builder: (context, cursor, child) =>
                            KeyboardSelection.scope(
                              key: ValueKey('topic-list-keyboard-$topicId'),
                              selected:
                                  cursor?.topicId == topicId &&
                                  (cursor!.keyboard ||
                                      readingTopicId == topicId),
                              child: child!,
                            ),
                        child: _TopicRow(
                          topicId: topicId,
                          compact: lane.width < 600,
                          inbox: widget.inbox,
                          onOpen: _openRow,
                          hiddenCategoryId: hiddenCategoryId,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Separators occupy half of the sliver indices. Estimating them at the
  // library's default 100px forces large corrections as they are measured.
  double _estimateExtent(int? index, double crossAxisExtent) {
    if (index == null) return 0;
    return index.isOdd ? 1 : TopicListRow.minimumHeight;
  }
}

class TopicListHeader extends StatelessWidget {
  const TopicListHeader({super.key, this.filtersBuilder});
  final Widget Function(bool showColumns)? filtersBuilder;

  @override
  Widget build(BuildContext context) => filtersBuilder == null
      ? const SizedBox.shrink()
      : ContentReadingLaneBox(
          widthLimit: topicListContentWidth,
          padding: const EdgeInsets.all(16),
          child: filtersBuilder!(false),
        );
}

class _TopicListLoadingSkeleton extends StatelessWidget {
  const _TopicListLoadingSkeleton({super.key, required this.destination});

  static const _patternLength = 5;

  final String destination;

  String get _semanticsLabel {
    if (destination == 'messages' ||
        destination.startsWith('messages-group-')) {
      return 'Loading messages';
    }
    return destination == 'filter'
        ? 'Loading filtered topics'
        : 'Loading topics';
  }

  @override
  Widget build(BuildContext context) {
    return DSkeletonRegion(
      expand: true,
      semanticsLabel: _semanticsLabel,
      color: skeletonFill(context),
      child: ForumTabLayoutBuilder(
        builder: (context, constraints) {
          final visibleRowCount = constraints.hasBoundedHeight
              ? (constraints.maxHeight / TopicListRow.minimumHeight).ceil()
              : _patternLength;
          final rowCount = visibleRowCount < 1 ? 1 : visibleRowCount;

          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: double.infinity,
              child: Column(
                key: const ValueKey('topic-list-loading-skeleton-content'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < rowCount; index++) ...[
                    if (index > 0) const SizedBox(height: 1),
                    _rowAt(index),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _rowAt(int index) => switch (index % _patternLength) {
    0 => const _TopicListSkeletonRow(titleWidth: 0.72, metadataWidth: 0.64),
    1 => const _TopicListSkeletonRow(titleWidth: 0.88, metadataWidth: 0.52),
    2 => const _TopicListSkeletonRow(titleWidth: 0.56, metadataWidth: 0.72),
    3 => const _TopicListSkeletonRow(titleWidth: 0.82, metadataWidth: 0.48),
    _ => const Opacity(
      opacity: 0.72,
      child: _TopicListSkeletonRow(titleWidth: 0.66, metadataWidth: 0.58),
    ),
  };
}

class _TopicListSkeletonRow extends StatelessWidget {
  const _TopicListSkeletonRow({
    required this.titleWidth,
    required this.metadataWidth,
  });

  final double titleWidth;
  final double metadataWidth;

  @override
  Widget build(BuildContext context) {
    return DItem(
      shape: DItemShape.fullWidth,
      children: [
        DItemContent(
          spacing: 8,
          children: [
            _SkeletonLine(widthFactor: titleWidth, height: 14),
            const _SkeletonLine(widthFactor: .94, height: 12),
            _SkeletonLine(widthFactor: metadataWidth, height: 12),
            const DSkeleton(width: 160, height: 20),
          ],
        ),
      ],
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor, required this.height});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: FractionallySizedBox(
      widthFactor: widthFactor,
      child: DSkeleton(height: height),
    ),
  );
}

class _IncomingBanner extends StatelessWidget {
  const _IncomingBanner({
    required this.count,
    required this.destination,
    required this.onTap,
  });

  final int count;
  final String destination;
  final VoidCallback onTap;

  String get _label {
    final noun = destination == 'latest' ? 'new or updated topic' : 'new topic';
    return 'See $count $noun${count == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final label = Text(
      _label,
      softWrap: true,
      maxLines: 4,
      textAlign: TextAlign.center,
    );

    return ContentReadingLaneBox(
      widthLimit: topicListContentWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Align(
          alignment: Alignment.center,
          child: Semantics(
            liveRegion: true,
            child: DButton(
              key: const ValueKey('incoming-topics-button'),
              variant: DButtonVariant.primary,
              size: DButtonSize.small,
              icon: const DIcon(DIcons.arrowUp),
              label: label,
              onPressed: onTap,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingMoreRow extends StatelessWidget {
  const _LoadingMoreRow();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _LoadMoreErrorRow extends StatelessWidget {
  const _LoadMoreErrorRow({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('topic-feed-load-more-error'),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
    child: _FeedErrorBanner(message: message, onRetry: onRetry),
  );
}

class _FeedErrorBanner extends StatelessWidget {
  const _FeedErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => DAlert(
    variant: DAlertVariant.destructive,
    icon: const Icon(Icons.error_outline),
    description: DAlertDescription(child: Text(message)),
    action: DAlertAction(
      child: DButton(
        key: const ValueKey('topic-feed-error-retry'),
        label: const Text('Retry'),
        onPressed: onRetry,
        variant: DButtonVariant.link,
      ),
    ),
  );
}

class _TopicRow extends StatefulWidget {
  const _TopicRow({
    required this.topicId,
    required this.compact,
    required this.hiddenCategoryId,
    required this.onOpen,
    this.inbox = false,
  });

  final int topicId;
  final bool compact;
  final int? hiddenCategoryId;
  final bool inbox;
  final ValueChanged<Topic> onOpen;

  @override
  State<_TopicRow> createState() => _TopicRowState();
}

class _TopicRowState extends State<_TopicRow> {
  Widget? _content;

  @override
  void didUpdateWidget(_TopicRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topicId != widget.topicId ||
        oldWidget.compact != widget.compact ||
        oldWidget.hiddenCategoryId != widget.hiddenCategoryId ||
        oldWidget.onOpen != widget.onOpen ||
        oldWidget.inbox != widget.inbox) {
      _content = null;
    }
  }

  // Pagination rebuilds the sliver delegate. Keep the mounted row's selectors
  // and content stable; topic, category, selection and inherited dependencies
  // still update independently. The cache dies when the row leaves the sliver.
  @override
  Widget build(BuildContext context) => _content ??= _buildContent();

  Widget _buildContent() {
    return ShellSelector<({String? siteUrl, bool selected, bool reading})>(
      select: (controller) => (
        siteUrl: controller.currentInstance?.url,
        reading: widget.inbox && controller.currentContent?.isTopic == true,
        selected: widget.inbox && controller.readingTopicId == widget.topicId,
      ),
      builder: (context, state, _) {
        final siteUrl = state.siteUrl;
        if (siteUrl == null) return const SizedBox.shrink();
        final controller = ShellScope.read(context);

        return ValueListenableBuilder<Topic?>(
          valueListenable: controller.topicRef(siteUrl, widget.topicId),
          builder: (context, topic, _) => topic == null
              // The id is in a list, so the topic was stored with it. A gap
              // here means the site was just disconnected and this list is
              // one frame from being torn down.
              ? const SizedBox.shrink()
              : ShellSelector<
                  ({TopicCategory? category, TopicCategory? parent})
                >(
                  select: (controller) => _topicCategoryPresentation(
                    controller,
                    topic.categoryId,
                    siteUrl,
                    hiddenCategoryId: widget.hiddenCategoryId,
                  ),
                  builder: (context, categoryPresentation, _) => _TopicRowBody(
                    topic: topic,
                    compact: widget.compact,
                    category: categoryPresentation.category,
                    parentCategory: categoryPresentation.parent,
                    showCategoryBreadcrumb: true,
                    siteUrl: siteUrl,
                    selected: state.selected,
                    inbox: state.reading,
                    onTap: () => widget.onOpen(topic),
                  ),
                ),
        );
      },
    );
  }
}

/// Topic rows share inset rules on narrow panes and flush rules on desktop.
class TopicListSeparator extends StatelessWidget {
  const TopicListSeparator({super.key, this.besideSelection = false});

  final bool besideSelection;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 600) return const DSeparator();
      if (besideSelection) return const SizedBox.shrink();
      return DSeparator(
        indent: 16,
        endIndent: 16,
        color: DTokens.of(context).footerBorder,
      );
    },
  );
}

class TopicListRow extends StatelessWidget {
  const TopicListRow({
    super.key,
    required this.topic,
    this.forum,
    this.siteUrl,
    this.onTap,
    this.titleStyle,
    this.showViews = false,
    this.onSort,
    this.order,
    this.ascending = false,
    this.showCategoryBreadcrumb = true,
    this.itemVariant = DItemVariant.outline,
    this.contentPadding,
    this.outerPadding,
  }) : assert(forum == null || siteUrl == null);

  static const double minimumHeight = 110;

  final Topic topic;
  final bool showViews;
  final ValueChanged<String>? onSort;
  final String? order;
  final bool ascending;
  final DiscourseInstance? forum;

  final String? siteUrl;
  final VoidCallback? onTap;

  final TextStyle? titleStyle;
  final bool showCategoryBreadcrumb;
  final DItemVariant itemVariant;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsetsGeometry? outerPadding;

  @override
  Widget build(BuildContext context) => _build(context);

  Widget _build(BuildContext context) {
    final owningForum = forum;
    if (owningForum != null) {
      return _buildRow(context, owningForum.url, owningForum);
    }
    if (siteUrl case final siteUrl?) {
      return _buildRow(context, siteUrl, null);
    }
    return ShellSelector<String?>(
      select: (controller) => controller.currentInstance?.url,
      builder: (context, siteUrl, _) {
        if (siteUrl == null) return const SizedBox.shrink();
        return _buildRow(context, siteUrl, null);
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    String siteUrl,
    DiscourseInstance? owningForum,
  ) {
    final controller = ShellScope.maybeRead(context);
    if (controller == null) {
      assert(onTap != null, 'TopicListRow needs an onTap outside ShellScope.');
      return _TopicRowBody(
        topic: topic,
        category: null,
        parentCategory: null,
        showCategoryBreadcrumb: false,
        siteUrl: siteUrl,
        forum: owningForum,
        onTap: onTap ?? () {},
        titleStyle: titleStyle,
        showViews: showViews,
        onSort: onSort,
        order: order,
        ascending: ascending,
        itemVariant: itemVariant,
        contentPadding: contentPadding,
        outerPadding: outerPadding,
      );
    }
    return ShellSelector<({TopicCategory? category, TopicCategory? parent})>(
      select: (controller) =>
          _topicCategoryPresentation(controller, topic.categoryId, siteUrl),
      builder: (context, categoryPresentation, _) => _TopicRowBody(
        topic: topic,
        category: categoryPresentation.category,
        parentCategory: categoryPresentation.parent,
        showCategoryBreadcrumb: showCategoryBreadcrumb,
        siteUrl: siteUrl,
        forum: owningForum,
        onTap:
            onTap ??
            () => handleTabOpenResult(context, controller.openTopic(topic)),
        titleStyle: titleStyle,
        showViews: showViews,
        onSort: onSort,
        order: order,
        ascending: ascending,
        itemVariant: itemVariant,
        contentPadding: contentPadding,
        outerPadding: outerPadding,
      ),
    );
  }
}

({TopicCategory? category, TopicCategory? parent}) _topicCategoryPresentation(
  ShellController controller,
  int? categoryId,
  String siteUrl, {
  int? hiddenCategoryId,
}) {
  final category = controller.categoryFor(categoryId, siteUrl: siteUrl);
  if (category?.id == hiddenCategoryId) {
    return (category: null, parent: null);
  }
  return (
    category: category,
    parent: category?.parentCategoryId == hiddenCategoryId
        ? null
        : controller.categoryFor(category?.parentCategoryId, siteUrl: siteUrl),
  );
}

typedef _TopicListSnapshot = ({
  _TopicListIdentity feedIdentity,
  String destination,
  int incoming,
  int? topicId,
});

_TopicListSnapshot _topicListSnapshot(ShellController controller) {
  // Not `destinationId`: a category or tag list opened from a hashtag is a
  // feed of its own, sitting over whichever sidebar entry is still selected.
  final destination = controller.currentFeedId ?? 'latest';
  return (
    feedIdentity: _TopicListViewState._currentFeedIdentity(controller),
    destination: destination,
    incoming: controller.incomingCount(destination),
    topicId: controller.readingTopicId,
  );
}

class _TopicRowBody extends StatelessWidget {
  const _TopicRowBody({
    required this.topic,
    required this.category,
    required this.parentCategory,
    required this.showCategoryBreadcrumb,
    required this.siteUrl,
    required this.onTap,
    this.compact,
    this.forum,
    this.titleStyle,
    this.selected = false,
    this.inbox = false,
    this.itemVariant = DItemVariant.outline,
    this.contentPadding,
    this.outerPadding,
    this.showViews = false,
    this.onSort,
    this.order,
    this.ascending = false,
  });

  final bool showViews;
  // Lists already know the row width. Standalone rows measure it themselves.
  final bool? compact;
  final ValueChanged<String>? onSort;
  final String? order;
  final bool ascending;
  final Topic topic;
  final TopicCategory? category;
  final TopicCategory? parentCategory;
  final bool showCategoryBreadcrumb;
  final String siteUrl;
  final VoidCallback onTap;
  final DiscourseInstance? forum;
  final TextStyle? titleStyle;
  final bool selected;
  final bool inbox;
  final DItemVariant itemVariant;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsetsGeometry? outerPadding;

  @override
  StatelessElement createElement() => _TopicRowBodyElement(this);

  @override
  Widget build(BuildContext context) => _TopicRowLayout(
    topicId: topic.id,
    capture: DiagnosticsScope.maybeRead(context)?.topicScrollCapture,
    child: _buildBody(context),
  );

  Widget _buildBody(BuildContext context) => _ConversationTopicCard(row: this);
}

class _CategoryBreadcrumb extends StatelessWidget {
  const _CategoryBreadcrumb({
    required this.parent,
    required this.category,
    required this.siteUrl,
    required this.onOpen,
    this.compact = false,
  });

  final bool compact;
  final TopicCategory? parent;
  final TopicCategory category;
  final String siteUrl;
  final ValueChanged<TopicCategory> onOpen;

  @override
  Widget build(BuildContext context) {
    final parent = this.parent;
    return DBreadcrumb(
      semanticLabel: 'Category path',
      child: DBreadcrumbList(
        spacing: 1.5,
        children: [
          if (parent != null) ...[
            DBreadcrumbItem(
              child: LinkTarget(
                url: resolveSiteRootPath(siteUrl, '/c/${parent.id}'),
                title: parent.name,
                siteUrl: siteUrl,
                child: _CategoryBadge(
                  key: ValueKey(('topic-row-parent-category', parent.id)),
                  category: parent,
                  compact: compact,
                  siteUrl: siteUrl,
                  label: parent.name,
                  semanticLabel: 'Parent category: ${parent.name}',
                  onTap: () => onOpen(parent),
                ),
              ),
            ),
          ],
          DBreadcrumbItem(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 1.5,
              children: [
                if (parent != null)
                  DBreadcrumbSeparator(
                    key: ValueKey((
                      'topic-row-category-chevron',
                      parent.id,
                      category.id,
                    )),
                  ),
                Flexible(
                  child: LinkTarget(
                    url: resolveSiteRootPath(siteUrl, '/c/${category.id}'),
                    title: category.name,
                    siteUrl: siteUrl,
                    child: _CategoryBadge(
                      key: ValueKey(('topic-row-category', category.id)),
                      category: category,
                      compact: compact,
                      siteUrl: siteUrl,
                      label: category.name,
                      semanticLabel: 'Category: ${category.name}',
                      onTap: () => onOpen(category),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({
    super.key,
    required this.category,
    required this.siteUrl,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.compact = false,
  });
  final bool compact;
  final TopicCategory category;
  final String siteUrl;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DTooltip(
    message: label,
    // [semanticLabel] already names the category.
    excludeFromSemantics: true,
    child: DBreadcrumbLink(
      compact: compact,
      onPressed: onTap,
      semanticLabel: semanticLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CategoryIcon(
            key: ValueKey(('topic-row-category-swatch', category.id)),
            category: category,
            siteUrl: siteUrl,
            size: 13,
            squareSize: 9,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TopicTag extends StatelessWidget {
  const _TopicTag({
    required this.tag,
    required this.onTap,
    required this.onMiddleClick,
    this.compact = false,
  });
  final bool compact;
  final TopicTag tag;
  final VoidCallback onTap;
  final Future<void> Function() onMiddleClick;

  @override
  Widget build(BuildContext context) => GestureDetector(
    excludeFromSemantics: true,
    onTertiaryTapUp: (_) => onMiddleClick(),
    child: DBadge.link(
      variant: DBadgeVariant.outline,
      size: compact ? DBadgeSize.tag : DBadgeSize.compact,
      backgroundColor: compact ? DTokens.of(context).footerBorder : null,
      foregroundColor: compact
          ? Color.lerp(
              DTokens.of(context).background,
              DTokens.of(context).foreground,
              .62,
            )
          : DTokens.of(context).mutedForeground,
      semanticLabel: 'Tag: ${tag.name}',
      onPressed: onTap,
      child: Text(tag.name),
    ),
  );
}

class _TopicTagOverflow extends StatelessWidget {
  const _TopicTagOverflow({required this.tags});
  final List<TopicTag> tags;
  int get count => tags.length;

  @override
  Widget build(BuildContext context) => DTooltip(
    message: tags.map((tag) => '#${tag.name}').join(', '),
    child: DBadge(
      key: const ValueKey('topic-row-tag-overflow'),
      variant: DBadgeVariant.outline,
      semanticLabel: '$count more ${count == 1 ? 'tag' : 'tags'}',
      child: Text('+$count'),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final DIconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ForumTabLayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: DEmpty(
            children: [
              DEmptyHeader(
                children: [
                  DEmptyMedia(
                    variant: DEmptyMediaVariant.icon,
                    child: DIcon(icon),
                  ),
                  DEmptyTitle(text),
                ],
              ),
              if (actionLabel case final label?)
                DEmptyContent(
                  children: [
                    DButton(
                      key: const ValueKey('topic-feed-initial-retry'),
                      label: Text(label),
                      onPressed: onAction,
                      variant: DButtonVariant.link,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

// Measure synchronous subtree construction, including descendants, rather than
// just allocating the widget returned by _TopicRowBody.build.
class _TopicRowBodyElement extends StatelessElement {
  _TopicRowBodyElement(_TopicRowBody super.widget);

  @override
  void performRebuild() {
    final capture = getInheritedWidgetOfExactType<DiagnosticsScope>()
        ?.controller
        .topicScrollCapture;
    if (capture == null || !capture.isRecording) {
      super.performRebuild();
      return;
    }
    final timer = Stopwatch()..start();
    try {
      super.performRebuild();
    } finally {
      timer.stop();
      capture.recordTopicEvent('topicList.row.build', {
        'topicId': (widget as _TopicRowBody).topic.id,
        'durationUs': timer.elapsedMicroseconds,
      });
    }
  }
}

class _TopicRowLayout extends SingleChildRenderObjectWidget {
  const _TopicRowLayout({
    required this.topicId,
    required this.capture,
    required super.child,
  });

  final int topicId;
  final TopicScrollCaptureController? capture;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTopicRowLayout(topicId, capture);

  @override
  void updateRenderObject(BuildContext context, _RenderTopicRowLayout object) {
    object
      ..topicId = topicId
      ..capture = capture;
  }
}

class _RenderTopicRowLayout extends RenderProxyBox {
  _RenderTopicRowLayout(this.topicId, this.capture);

  int topicId;
  TopicScrollCaptureController? capture;

  @override
  void performLayout() {
    final recorder = capture;
    if (recorder == null || !recorder.isRecording) {
      super.performLayout();
      return;
    }
    final timer = Stopwatch()..start();
    try {
      super.performLayout();
    } finally {
      timer.stop();
      recorder.recordTopicEvent('topicList.row.layout', {
        'topicId': topicId,
        'durationUs': timer.elapsedMicroseconds,
      });
    }
  }
}
