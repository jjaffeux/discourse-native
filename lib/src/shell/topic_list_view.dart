import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../app_shortcuts.dart';
import '../diagnostics/diagnostics_scope.dart';
import '../diagnostics/topic_scroll_capture.dart';
import '../models/discourse_instance.dart';
import '../models/topic.dart';
import '../models/topic_feed.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'category_icon.dart';
import 'content_reading_lane.dart';
import 'keyboard_navigation.dart';
import 'list_boundary_shortcuts.dart';
import 'open_link.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_list_indicators.dart';
import 'topic_list_layout.dart';
import 'topic_title.dart';

typedef _TopicListIdentity = (String?, String?, String?, String);
typedef _TopicListCursor = ({int topicId, int index});

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
    final topicId = controller.currentContent?.topicId;
    void reveal({bool correct = true}) {
      if (!_isCurrent(controller, identity) ||
          controller.currentContent?.topicId != topicId ||
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
        controller.currentContent?.topicId != topicId ||
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

    final row = controller.feedScrollRow(destination);
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
      _currentFeedIdentity(controller) == feedIdentity;

  static _TopicListIdentity _currentFeedIdentity(ShellController controller) {
    final siteUrl = controller.currentInstance?.url;
    final destination = controller.currentFeedId ?? 'latest';
    return (
      siteUrl,
      controller.currentAccountIdentity,
      controller.activeTabId,
      destination,
    );
  }

  void _rememberTopic(int topicId) {
    final ids = _controller?.currentFeed?.topicIds ?? widget.feed.topicIds;
    final index = ids.indexOf(topicId);
    if (index < 0) return;
    final cursor = (topicId: topicId, index: index);
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
      final anchor = cursor?.topicId ?? controller.currentContent?.topicId;
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
      final currentIds =
          controller.currentFeed?.topicIds ?? widget.feed.topicIds;
      if (!isCurrent() || currentIds.isEmpty) return;
      target = target.clamp(0, currentIds.length - 1);
      _rememberTopic(currentIds[target]);
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
    _rememberTopic(topic.id);
    if (keyboard) FocusManager.instance.primaryFocus?.unfocus();
    final controller = _controller!;
    if (keyboard && controller.currentContent?.topicId == topic.id) return;
    if (widget.inbox) {
      controller.openTopicFromList(topic, revealInList: keyboard);
    } else {
      controller.openTopic(topic);
    }
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
        if (state.incoming > 0)
          _IncomingBanner(
            count: state.incoming,
            destination: destination,
            loading: widget.feed.loadingIncoming,
            onTap: () => _showIncoming(controller, destination, feedIdentity),
          ),
        if (widget.showHeader) const TopicListHeader(),
        Expanded(child: _body(controller, destination, feedIdentity)),
      ],
    );
  }

  Widget _body(
    ShellController controller,
    String destination,
    _TopicListIdentity feedIdentity,
  ) {
    final feed = widget.feed;

    if (feed.loading && feed.topicIds.isEmpty) {
      return ContentReadingLaneBox(
        widthLimit: topicListContentWidth,
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
        onAction: () => unawaited(controller.loadFeed(destination)),
      );
    }
    if (feed.isEmpty) {
      return _Message(
        icon: DIcons.inbox,
        text: controller.topicListContent?.topicListSearch.isNotEmpty == true
            ? 'No topics found. Try another search or change the filters.'
            : 'Nothing here yet.',
      );
    }

    _syncControllers(feedIdentity);
    _restore(controller, destination, feedIdentity);
    if (_recording) {
      _recordScrollEvent('topicList.view.built', {
        'topicCount': feed.topicIds.length,
      });
    }
    final readingTopicId = widget.inbox
        ? controller.currentContent?.topicId
        : null;
    if (_readingTopicId != readingTopicId) {
      _readingTopicId = readingTopicId;
      if (readingTopicId == null) {
        _revealCursor();
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
            basePadding: const EdgeInsets.symmetric(vertical: 8),
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
                    controller.saveFeedScrollRow(destination, range.$1);
                  }
                }
                if (notification.metrics.extentAfter < _loadMoreThreshold) {
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
                    separatorBuilder: (context, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (_recording) {
                        _recordScrollEvent('topicList.row.built', {
                          'index': index,
                        });
                      }
                      if (index >= feed.topicIds.length) {
                        if (feed.loadingMore) return const _LoadingMoreRow();
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
                              selected: cursor?.topicId == topicId,
                              child: child!,
                            ),
                        child: _TopicRow(
                          topicId: topicId,
                          inbox: widget.inbox,
                          onOpen: _openRow,
                          hiddenCategoryId:
                              controller.topicListContent?.categoryId,
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

  static const double _loadMoreThreshold = 800;

  // Separators occupy half of the sliver indices. Estimating them at the
  // library's default 100px forces large corrections as they are measured.
  static double _estimateExtent(int? index, double crossAxisExtent) {
    if (index == null) return 0;
    return index.isOdd ? 8 : TopicListRow.minimumHeight;
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
      child: LayoutBuilder(
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
                    if (index > 0) const SizedBox(height: 8),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DItem(
        variant: DItemVariant.outline,
        children: [
          DItemContent(
            spacing: 12,
            children: [
              _SkeletonLine(widthFactor: titleWidth, height: 14),
              _SkeletonLine(widthFactor: metadataWidth, height: 12),
              const DSkeleton(width: 100, height: 20),
            ],
          ),
        ],
      ),
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
    required this.loading,
    required this.onTap,
  });

  final int count;
  final String destination;
  final bool loading;
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
              icon: const DIcon(DIcons.arrowUp, size: 16),
              label: label,
              loading: loading,
              loadingLabel: label,
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
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 20),
    child: Center(child: SizedBox(width: 20, height: 20, child: DSpinner())),
  );
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

class _TopicRow extends StatelessWidget {
  const _TopicRow({
    required this.topicId,
    required this.hiddenCategoryId,
    required this.onOpen,
    this.inbox = false,
  });

  final int topicId;
  final int? hiddenCategoryId;
  final bool inbox;
  final ValueChanged<Topic> onOpen;

  @override
  Widget build(BuildContext context) {
    return ShellSelector<({String? siteUrl, bool selected, bool reading})>(
      select: (controller) => (
        siteUrl: controller.currentInstance?.url,
        reading: inbox && controller.currentContent?.isTopic == true,
        selected: inbox && controller.currentContent?.topicId == topicId,
      ),
      builder: (context, state, _) {
        final siteUrl = state.siteUrl;
        if (siteUrl == null) return const SizedBox.shrink();
        final controller = ShellScope.read(context);

        return ValueListenableBuilder<Topic?>(
          valueListenable: controller.topicRef(siteUrl, topicId),
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
                    hiddenCategoryId: hiddenCategoryId,
                  ),
                  builder: (context, categoryPresentation, _) => _TopicRowBody(
                    topic: topic,
                    category: categoryPresentation.category,
                    parentCategory: categoryPresentation.parent,
                    showCategoryBreadcrumb: true,
                    siteUrl: siteUrl,
                    selected: state.selected,
                    inbox: state.reading,
                    onTap: () => onOpen(topic),
                  ),
                ),
        );
      },
    );
  }
}

class TopicListRow extends StatelessWidget {
  const TopicListRow({
    super.key,
    required this.topic,
    this.forum,
    this.siteUrl,
    this.onTap,
    this.titleStyle,
    this.showCategoryBreadcrumb = true,
    this.itemVariant = DItemVariant.outline,
  }) : assert(forum == null || siteUrl == null);

  static const double minimumHeight = 110;
  static const double compactMinimumHeight = 50;

  final Topic topic;
  final DiscourseInstance? forum;

  final String? siteUrl;
  final VoidCallback? onTap;

  final TextStyle? titleStyle;
  final bool showCategoryBreadcrumb;
  final DItemVariant itemVariant;

  @override
  Widget build(BuildContext context) {
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
        itemVariant: itemVariant,
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
        onTap: onTap ?? () => controller.openTopic(topic),
        titleStyle: titleStyle,
        itemVariant: itemVariant,
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
    topicId: controller.currentContent?.topicId,
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
    this.forum,
    this.titleStyle,
    this.selected = false,
    this.inbox = false,
    this.itemVariant = DItemVariant.outline,
  });

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveTitleStyle = titleStyle ?? theme.textTheme.titleSmall;
    final titleLineHeight =
        MediaQuery.textScalerOf(
          context,
        ).scale(effectiveTitleStyle?.fontSize ?? 14) *
        (effectiveTitleStyle?.height ?? 1.5);
    Widget statusIcon(DIconData icon, String label) => SizedBox(
      height: titleLineHeight,
      child: Center(child: DIcon(icon, size: 14, semanticLabel: label)),
    );
    final pluginMetadata =
        (PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty)
            .topicListMetadata(context, siteUrl, topic);

    final muted = theme.colorScheme.onSurfaceVariant;
    final titleColor = topicListTitleColor(theme, visited: topic.visited);
    final keyboardSelected = KeyboardSelection.isSelectedOf(context);
    final controller = ShellScope.maybeRead(context);
    const maximumVisibleTags = 2;
    final visibleTags = topic.tags.take(maximumVisibleTags).toList();
    final age = topic.bumpedAt == null ? null : relativeTime(topic.bumpedAt!);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: topicListHorizontalPadding,
      ),
      child: LinkTarget(
        url: '/t/${topic.slug}/${topic.id}/${topic.lastUnreadPostNumber ?? 1}',
        title: topic.title,
        siteUrl: siteUrl,
        child: Semantics(
          key: inbox ? ValueKey('inbox-row-${topic.id}') : null,
          container: true,
          selected: selected || keyboardSelected,
          child: DItem(
            key: ValueKey('topic-card-${topic.id}'),
            selected: selected,
            variant: keyboardSelected
                ? DItemVariant.muted
                : itemVariant,
            onPressed: onTap,
            link: true,
            footer: pluginMetadata.isEmpty
                ? null
                : DItemFooter(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: pluginMetadata,
                    ),
                  ),
            children: [
              DItemContent(
                alignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DItemTitle(
                          maxLines: 2,
                          child: Row(
                            spacing: 6,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (topic.closed)
                                statusIcon(DIcons.lock, 'Closed'),
                              if (topic.pinned)
                                statusIcon(DIcons.thumbtack, 'Pinned'),
                              if (topic.bookmarked)
                                statusIcon(DIcons.bookmark, 'Bookmarked'),
                              Flexible(
                                child: TopicTitle(
                                  topic.title,
                                  siteUrl: siteUrl,
                                  overflow:
                                      MediaQuery.textScalerOf(
                                            context,
                                          ).scale(14) >
                                          21
                                      ? TextOverflow.clip
                                      : TextOverflow.ellipsis,
                                  maxLines:
                                      MediaQuery.textScalerOf(
                                            context,
                                          ).scale(14) >
                                          21
                                      ? null
                                      : 2,
                                  trailing: [
                                    for (final marker in <Widget>[
                                      if (topic.showNewTopicDot)
                                        const TopicStateDot(
                                          key: ValueKey('new-topic-dot'),
                                          label: 'New topic',
                                        )
                                      else if (topic.showNewRepliesDot)
                                        const TopicStateDot(
                                          key: ValueKey('new-replies-dot'),
                                          label: 'Topic has new replies',
                                        ),
                                      if (topic.showUnreadCount)
                                        TopicUnreadBadge(
                                          key: ValueKey(
                                            'inbox-row-unread-${topic.id}',
                                          ),
                                          count: topic.unreadCount,
                                        ),
                                    ])
                                      Padding(
                                        padding:
                                            const EdgeInsetsDirectional.only(
                                              start: 6,
                                            ),
                                        child: marker,
                                      ),
                                  ],

                                  style: effectiveTitleStyle?.copyWith(
                                    color: titleColor,
                                    fontWeight: topic.visited
                                        ? FontWeight.w400
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (age != null) ...[
                        const SizedBox(width: 12),
                        Text(
                          age,
                          key: ValueKey('inbox-row-time-${topic.id}'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (topic.excerpt case final excerpt?
                      when excerpt.trim().isNotEmpty)
                    DItemDescription(child: Text(excerpt)),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final taxonomy = Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (forum case final forum?)
                            Text(
                              forum.title,
                              style: theme.textTheme.labelMedium,
                            ),
                          if (showCategoryBreadcrumb && category != null)
                            _CategoryBreadcrumb(
                              parent: parentCategory,
                              category: category!,
                              siteUrl: siteUrl,
                              onOpen: (category) => controller?.openCategory(
                                category,
                                siteUrl: siteUrl,
                              ),
                            ),
                          for (final tag in visibleTags)
                            _TopicTag(
                              tag: tag,
                              onTap: () => controller?.openTopicTag(
                                tag,
                                siteUrl: siteUrl,
                                privateMessage: topic.privateMessage,
                              ),
                              onMiddleClick: () async {
                                await controller?.openTopicTag(
                                  tag,
                                  siteUrl: siteUrl,
                                  privateMessage: topic.privateMessage,
                                  newTab: true,
                                );
                              },
                            ),
                          if (topic.tags.length > maximumVisibleTags)
                            _TopicTagOverflow(
                              tags: topic.tags
                                  .skip(maximumVisibleTags)
                                  .toList(),
                            ),
                        ],
                      );
                      final activity = Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (topic.lastPosterUsername
                              case final username?) ...[
                            DAvatar(
                              dimension: 20,
                              decorative: true,
                              child: AvatarImage(
                                url: topic.lastPosterAvatarUrl,
                                size: 20,
                                fallback: const DAvatarFallback(
                                  child: DIcon(DIcons.user, size: 12),
                                ),
                              ),
                            ),
                            Text(
                              'Last post by $username',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: muted,
                              ),
                            ),
                            Text('·', style: TextStyle(color: muted)),
                          ],
                          Text(
                            '${topic.replyCount} ${topic.replyCount == 1 ? 'reply' : 'replies'}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: muted,
                            ),
                          ),
                        ],
                      );
                      if (constraints.maxWidth /
                              MediaQuery.textScalerOf(context).scale(1) <
                          620) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            taxonomy,
                            const SizedBox(height: 8),
                            activity,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: taxonomy),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: activity,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryBreadcrumb extends StatelessWidget {
  const _CategoryBreadcrumb({
    required this.parent,
    required this.category,
    required this.siteUrl,
    required this.onOpen,
  });

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
                url: '/c/${parent.id}',
                title: parent.name,
                siteUrl: siteUrl,
                child: _CategoryBadge(
                  key: ValueKey(('topic-row-parent-category', parent.id)),
                  category: parent,
                  siteUrl: siteUrl,
                  label: parent.name,
                  semanticLabel: 'Parent category: ${parent.name}',
                  onTap: () => onOpen(parent),
                ),
              ),
            ),
            DBreadcrumbSeparator(
              key: ValueKey((
                'topic-row-category-chevron',
                parent.id,
                category.id,
              )),
            ),
          ],
          DBreadcrumbItem(
            child: LinkTarget(
              url: '/c/${category.id}',
              title: category.name,
              siteUrl: siteUrl,
              child: _CategoryBadge(
                key: ValueKey(('topic-row-category', category.id)),
                category: category,
                siteUrl: siteUrl,
                label: category.name,
                semanticLabel: 'Category: ${category.name}',
                onTap: () => onOpen(category),
              ),
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
  });
  final TopicCategory category;
  final String siteUrl;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DBreadcrumbLink(
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
        Flexible(child: Text(label)),
      ],
    ),
  );
}

class _TopicTag extends StatelessWidget {
  const _TopicTag({
    required this.tag,
    required this.onTap,
    required this.onMiddleClick,
  });
  final TopicTag tag;
  final VoidCallback onTap;
  final Future<void> Function() onMiddleClick;

  @override
  Widget build(BuildContext context) => GestureDetector(
    excludeFromSemantics: true,
    onTertiaryTapUp: (_) => onMiddleClick(),
    child: DBadge.link(
      variant: DBadgeVariant.outline,
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
    message: tags.map((tag) => '# ${tag.name}').join(', '),
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
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: DEmpty(
        children: [
          DEmptyHeader(
            children: [
              DEmptyMedia(variant: DEmptyMediaVariant.icon, child: DIcon(icon)),
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
  );
}
