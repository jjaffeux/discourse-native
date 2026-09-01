import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../app_shortcuts.dart';
import '../data/topic_recommendations_tab_store.dart';
import '../data/topic_sidebar_store.dart';
import '../diagnostics/diagnostics_scope.dart';
import '../diagnostics/topic_scroll_capture.dart';
import '../foundation/calendar_day.dart';
import '../models/content_route.dart';
import '../models/post.dart';
import '../models/post_flag.dart';
import '../models/topic.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import '../theme/d_tooltip.dart';
import 'avatar_image.dart';
import 'content_reading_lane.dart';
import 'cooked_html.dart';
import 'inline_action.dart';
import 'list_boundary_shortcuts.dart';
import 'loading_skeleton.dart';
import 'open_link.dart';
import 'post_actions.dart';
import 'post_footer.dart';
import 'post_revision_history.dart';
import 'post_text_selection.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'site_emoji_text.dart';
import 'small_action.dart';
import 'stream_day_separator.dart';
import 'time_gap.dart';
import 'title_bar.dart';
import 'topic_actions.dart';
import 'topic_category_picker.dart';
import 'topic_change_owner.dart';
import 'topic_list_view.dart';
import 'topic_move_posts.dart';
import 'topic_progress.dart';
import 'topic_tag_picker.dart';
import 'topic_taxonomy_fields.dart';
import 'topic_title.dart';
import 'topic_viewport_coordinator.dart';
import 'user_card.dart';
import 'user_menu_button.dart';
import 'user_status.dart';

class TopicView extends StatefulWidget {
  const TopicView({
    super.key,
    this.showSidebar = false,
    this.canReturnToSidebar = false,
    this.sidebarStore = const TopicSidebarStore(),
    this.recommendationsTabStore = const TopicRecommendationsTabStore(),
    this.route,
    this.canReply = false,
    this.bookmarkBusy = false,
    this.isConnected = false,
    this.registry = PluginRegistry.empty,
    this.now,
  });

  static const double _loadPostsThreshold = 900;

  static const double minimumPostHeight = 96;

  static double _estimateChildExtent(int? index, double _) =>
      index == null ? 0 : (index.isOdd ? 1 : 199);

  final bool showSidebar;

  final bool canReturnToSidebar;

  final TopicSidebarStore sidebarStore;

  final TopicRecommendationsTabStore recommendationsTabStore;

  final ContentRoute? route;
  final bool canReply;
  final bool bookmarkBusy;
  final bool isConnected;
  final PluginRegistry registry;
  final DateTime Function()? now;

  @override
  State<TopicView> createState() => _TopicViewState();
}

typedef _TopicDayStart = ({DateTime day, int postIndex});
typedef _TopicTimeGap = ({int daysSince, int postIndex});
typedef _RetainedTopicPostExtent = ({
  double width,
  double height,
  Post post,
  TopicDetail topic,
  bool summary,
  bool summaryLoading,
  int readTimeWordCount,
});

@visibleForTesting
RevealedOffset? getOffsetToRevealIfLaidOut(
  RenderAbstractViewport viewport,
  RenderObject target,
  double alignment,
) {
  var child = target;
  while (child.parent != viewport) {
    final parent = child.parent;
    if (parent == null) return null;
    if (parent is RenderSliver && parent.childScrollOffset(child) == null) {
      return null;
    }
    child = parent;
  }
  return viewport.getOffsetToReveal(target, alignment);
}

/// Returns the web-style horizontal eyeline used to choose the current post.
///
/// The eyeline stays near the top while reading, then travels toward the
/// post-stream boundary over the final viewport of scroll. When trailing
/// topic content is laid out, its height narrows that transition in the same
/// way as Discourse web's document-bottom calculation.
@visibleForTesting
double topicContextEyeline({
  required double viewportExtent,
  required double scrollOffset,
  required double maxScrollExtent,
  required double? postStreamBottom,
  required bool hasMore,
}) {
  if (!viewportExtent.isFinite || viewportExtent <= 0) return 0;

  final maximumEyeline = math.max(0.0, viewportExtent - 0.5);
  final topBoundary = math.min(1.0, maximumEyeline);
  final bottomBoundary = (postStreamBottom ?? viewportExtent)
      .clamp(topBoundary, maximumEyeline)
      .toDouble();
  if (hasMore) return topBoundary;

  final maximumScroll = math.max(0.0, maxScrollExtent);
  final remainingScroll = (maximumScroll - scrollOffset)
      .clamp(0.0, maximumScroll)
      .toDouble();
  var scrollableArea = math.min(viewportExtent, maximumScroll);

  if (postStreamBottom != null) {
    final documentExtent = maximumScroll + viewportExtent;
    final distanceToBottom = math.max(
      0.0,
      documentExtent - (scrollOffset + postStreamBottom),
    );
    // Native topic views do not always have the page footer that gives web a
    // non-zero trailing region. In that case retain the intended one-viewport
    // transition rather than pinning the eyeline to the stream bottom.
    if (distanceToBottom > 0.5) {
      scrollableArea = math.min(scrollableArea, distanceToBottom);
    }
  }

  final progress = scrollableArea > 0
      ? 1 - (remainingScroll / scrollableArea).clamp(0.0, 1.0)
      : 1.0;
  return topBoundary + progress * (bottomBoundary - topBoundary);
}

final class TopicPostIndexProjection {
  TopicPostIndexProjection(List<int> postIds) : _source = postIds {
    for (var index = 0; index < postIds.length; index++) {
      final postId = postIds[index];
      // Topic streams should contain unique ids. Preserve List.indexOf's
      // first-match behavior if a malformed payload repeats one anyway.
      if (!_indexByPostId.containsKey(postId)) {
        _indexByPostId[postId] = index;
      }
    }
  }

  final List<int> _source;
  final Map<int, int> _indexByPostId = {};

  bool represents(List<int> postIds) => identical(_source, postIds);

  int? operator [](int postId) => _indexByPostId[postId];
}

class _TopicViewState extends State<TopicView> with WidgetsBindingObserver {
  final Object _visibleTopicContextOwner = Object();
  late final TopicViewportCoordinator _viewport;
  int? _chatContextCurrentPostId;
  int _boundaryJumpRevision = 0;
  String? _recommendationsSiteUrl;
  bool _sidebarCollapsed = false;
  bool _sidebarOverlayOpen = false;
  int _sidebarRestoreGeneration = 0;
  TopicRecommendationSourceId _recommendationsSourceId =
      coreSuggestedTopicRecommendationSourceId;
  int _recommendationsTabRestoreGeneration = 0;
  List<_TopicDayStart> _laidOutDayStarts = const [];
  Object? _dayJumpToken;
  bool _tickerEnabled = true;
  TopicPostIndexProjection? _postIndexProjection;
  final Map<int, BuildContext> _postContexts = {};
  final Map<int, _RetainedTopicPostExtent> _retainedPostExtents = {};
  double _laidOutPostWidth = 0;
  int _extentGeneration = 0;
  TopicScrollCaptureController? _scrollCapture;
  TopicScrollCaptureController? _reportedScrollCaptureController;
  int? _reportedScrollCaptureId;
  late Size _viewportLogicalSize;
  late double _devicePixelRatio;

  ScrollController? get _scroll => _viewport.scrollController;
  ListController? get _list => _viewport.listController;
  ShellController? get _controller => _viewport.owner as ShellController?;
  (String, int, int)? get _topicIdentity => switch (_viewport.identity) {
    final identity? => (
      identity.siteUrl,
      identity.topicId,
      identity.navigationRevision,
    ),
    null => null,
  };
  bool get _restored => _viewport.restored;
  bool get _restoring => _viewport.restoring;
  bool get _userDragging => _viewport.userDragging;
  bool get _applyingAnchorRestore => _viewport.applyingAnchorRestore;
  int? get _savedAnchorPostNumber => _viewport.savedAnchorPostNumber;
  TopicViewportListenable get _viewportState => _viewport;
  DateTime? get _floatingDay => _viewportState.floatingDay;
  double get _floatingDayOffset => _viewportState.floatingDayOffset;
  int? get _progressPosition => _viewportState.progressPosition;
  TopicViewportSnapshot? get _laidOutSnapshot => _viewport.laidOutSnapshot;
  int? get _anchorRestorePostId => _viewport.anchorRestorePostId;
  double get _anchorRestoreViewportOffset =>
      _viewport.anchorRestoreViewportOffset;

  TopicPostIndexProjection _postIndexes(List<int> postIds) {
    final held = _postIndexProjection;
    if (held != null && held.represents(postIds)) return held;
    return _postIndexProjection = TopicPostIndexProjection(postIds);
  }

  bool get _isScrollCaptureRecording => _scrollCapture?.isRecording == true;

  void _recordTopicScrollEvent(String name, Map<String, Object?> data) {
    final capture = _scrollCapture;
    if (capture == null || !capture.isRecording) return;
    if (!identical(_reportedScrollCaptureController, capture) ||
        _reportedScrollCaptureId != capture.captureId) {
      _reportedScrollCaptureController = capture;
      _reportedScrollCaptureId = capture.captureId;
      final snapshot = _laidOutSnapshot;
      capture.recordTopicEvent('topic.capture.context', {
        'topicId': _topicIdentity?.$2 ?? snapshot?.topicId,
        'navigationRevision': _topicIdentity?.$3,
        'viewportLogicalSize': {
          'width': _viewportLogicalSize.width,
          'height': _viewportLogicalSize.height,
        },
        'devicePixelRatio': _devicePixelRatio,
        'list': {
          'widget': 'SuperListView.separated',
          'sliver': 'SuperSliverList',
          'listController': 'ListController',
          'scrollController': 'ScrollController',
          'physics': 'SuperRangeMaintainingScrollPhysics',
          'postExtentEstimate': 199,
          'separatorExtentEstimate': 1,
        },
        if (snapshot != null) 'topicWindow': _topicWindowData(snapshot),
      });
    }
    capture.recordTopicEvent(name, data);
  }

  Map<String, Object?> _topicWindowData(TopicViewportSnapshot snapshot) => {
    'topicId': snapshot.topicId,
    'navigationRevision': snapshot.navigationRevision,
    'loadedPostCount': snapshot.postIds.length,
    'streamPostCount': snapshot.streamIds.length,
    'loading': snapshot.loading,
    'loadingEarlier': snapshot.loadingEarlier,
    'loadingMore': snapshot.loadingMore,
    'hasEarlier': snapshot.hasEarlier,
    'hasMore': snapshot.hasMore,
    'restored': _restored,
    'restoring': _restoring,
    'userDragging': _userDragging,
    'applyingAnchorRestore': _applyingAnchorRestore,
    'extentGeneration': _extentGeneration,
  };

  Map<String, Object?> _scrollMetricsData(ScrollMetrics metrics) {
    try {
      return {
        'type': metrics.runtimeType.toString(),
        'axis': metrics.axis.name,
        'axisDirection': metrics.axisDirection.name,
        'pixels': metrics.pixels,
        'minScrollExtent': metrics.minScrollExtent,
        'maxScrollExtent': metrics.maxScrollExtent,
        'viewportDimension': metrics.viewportDimension,
        'extentBefore': metrics.extentBefore,
        'extentInside': metrics.extentInside,
        'extentAfter': metrics.extentAfter,
        'atEdge': metrics.atEdge,
        'outOfRange': metrics.outOfRange,
        'hasContentDimensions': metrics.hasContentDimensions,
        'devicePixelRatio': metrics.devicePixelRatio,
        if (metrics is ScrollPosition) ...{
          'isScrolling': metrics.isScrollingNotifier.value,
          'userScrollDirection': metrics.userScrollDirection.name,
        },
      };
    } on Object catch (error) {
      return {'unavailable': error.runtimeType.toString()};
    }
  }

  Map<String, Object?> _sliverLayoutData() {
    final list = _list;
    final scroll = _scroll;
    final data = <String, Object?>{
      'listAttached': list?.isAttached ?? false,
      'scrollAttached': scroll?.hasClients ?? false,
      'attachedPostCount': _postContexts.length,
    };
    if (list != null && list.isAttached) {
      try {
        final range = list.visibleRange;
        final unobstructed = list.unobstructedVisibleRange;
        final visibleChildExtents = <Map<String, Object?>>[];
        if (range != null) {
          for (
            var childIndex = range.$1;
            childIndex <= range.$2;
            childIndex++
          ) {
            final extent = list.extentForIndex(childIndex);
            visibleChildExtents.add({
              'index': childIndex,
              'extent': extent.$1,
              'estimated': extent.$2,
            });
          }
        }
        data.addAll({
          'visibleRange': range == null ? null : [range.$1, range.$2],
          'unobstructedVisibleRange': unobstructed == null
              ? null
              : [unobstructed.$1, unobstructed.$2],
          'numberOfItems': list.numberOfItems,
          'estimatedItemCount': list.numberOfItemsWithEstimatedExtent,
          'totalExtent': list.totalExtent,
          'isLocked': list.isLocked,
          if (range != null) 'visibleChildExtents': visibleChildExtents,
        });
      } on Object catch (error) {
        data['sliverReadError'] = error.runtimeType.toString();
      }
    }
    if (scroll != null && scroll.hasClients) {
      data['scrollMetrics'] = _scrollMetricsData(scroll.position);
    }
    return data;
  }

  void _recordScrollNotification(ScrollNotification notification) {
    final data = <String, Object?>{
      'notification': notification.runtimeType.toString(),
      'depth': notification.depth,
      'metrics': _scrollMetricsData(notification.metrics),
      if (notification is ScrollStartNotification)
        'drag': notification.dragDetails != null,
      if (notification is ScrollUpdateNotification) ...{
        'scrollDelta': notification.scrollDelta,
        'drag': notification.dragDetails != null,
      },
      if (notification is OverscrollNotification) ...{
        'overscroll': notification.overscroll,
        'velocity': notification.velocity,
        'drag': notification.dragDetails != null,
      },
      if (notification is ScrollEndNotification)
        'drag': notification.dragDetails != null,
      if (notification is UserScrollNotification)
        'direction': notification.direction.name,
    };
    _recordTopicScrollEvent('scroll.notification', data);
  }

  void _recordViewportInspection(TopicViewportSnapshot snapshot) {
    final list = _list;
    final visiblePosts = <Map<String, Object?>>[];
    if (list != null && list.isAttached) {
      final range = list.visibleRange;
      if (range != null) {
        final leading = snapshot.hasEarlier || snapshot.loadingEarlier ? 1 : 0;
        for (var childIndex = range.$1; childIndex <= range.$2; childIndex++) {
          if (childIndex.isOdd) continue;
          final postIndex = childIndex ~/ 2 - leading;
          if (postIndex < 0 || postIndex >= snapshot.postIds.length) continue;
          final postId = snapshot.postIds[postIndex];
          final post = _controller?.store.read<Post>(snapshot.siteUrl!, postId);
          final bounds = _postViewportBounds(postId);
          visiblePosts.add({
            'childIndex': childIndex,
            'postIndex': postIndex,
            'postId': postId,
            'postNumber': post?.postNumber,
            if (bounds != null) ...{
              'top': bounds.top,
              'bottom': bounds.bottom,
              'height': bounds.bottom - bounds.top,
            },
          });
        }
      }
    }
    _recordTopicScrollEvent('viewport.inspected', {
      'topicWindow': _topicWindowData(snapshot),
      'sliverLayout': _sliverLayoutData(),
      'visiblePosts': visiblePosts,
      'savedAnchorPostNumber': _savedAnchorPostNumber,
      'progressPosition': _progressPosition,
      'anchorRestorePostId': _anchorRestorePostId,
      'anchorRestoreViewportOffset': _anchorRestoreViewportOffset,
    });
  }

  @override
  void initState() {
    super.initState();
    _viewport = TopicViewportCoordinator(
      postFrame: (callback) =>
          WidgetsBinding.instance.addPostFrameCallback((_) => callback()),
      geometry: TopicViewportGeometryCallbacks(
        captureAnchor: _captureViewportAnchor,
        postViewportOffset: _postViewportOffset,
        canCorrectAnchor: () =>
            _list?.isAttached == true && _scroll?.hasClients == true,
        scrollPosition: () {
          final position = _scroll!.position;
          return (
            pixels: position.pixels,
            minScrollExtent: position.minScrollExtent,
            maxScrollExtent: position.maxScrollExtent,
          );
        },
        jumpToPost: (itemIndex, viewportOffset) =>
            _jumpTo(itemIndex, viewportOffset: viewportOffset),
        jumpToPixels: (pixels) => _scroll!.jumpTo(pixels),
      ),
      inspectViewport: _inspectViewport,
      listLayoutChanged: _onListLayoutChanged,
      diagnosticsEnabled: () => _isScrollCaptureRecording,
      recordDiagnostic: _recordTopicScrollEvent,
      layoutDiagnostics: _sliverLayoutData,
      pagingThreshold: TopicView._loadPostsThreshold,
    );
    if (WidgetsBinding.instance.lifecycleState case final lifecycle?) {
      _viewport.handleAppLifecycleState(lifecycle);
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewportLogicalSize = MediaQuery.sizeOf(context);
    _devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (_tickerEnabled == tickerEnabled) return;
    _tickerEnabled = tickerEnabled;
    _viewport.setTickerEnabled(tickerEnabled);
  }

  @override
  void didUpdateWidget(covariant TopicView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showSidebar != widget.showSidebar) {
      _sidebarOverlayOpen = false;
    }
  }

  void _syncViewport(
    ShellController controller,
    TopicViewportSnapshot snapshot,
  ) {
    final previousIdentity = _topicIdentity;
    final previousController = _controller;
    final previousTabId = _viewport.binding?.tabId;
    final changed = _viewport.bind(
      TopicViewportBinding.fromShell(controller, snapshot),
    );
    if (!changed) return;

    previousController?.clearVisibleTopicContext(_visibleTopicContextOwner);
    controller.updateVisibleTopicContext(
      owner: _visibleTopicContextOwner,
      siteUrl: snapshot.siteUrl!,
      topicId: snapshot.topicId!,
      postIds: const [],
    );

    if (_isScrollCaptureRecording) {
      _recordTopicScrollEvent('topic.controllers.sync', {
        'previousTopicId': previousIdentity?.$2,
        'previousNavigationRevision': previousIdentity?.$3,
        'topicId': snapshot.topicId,
        'navigationRevision': snapshot.navigationRevision,
        'controllerChanged': !identical(previousController, controller),
        'tabChanged': previousTabId != controller.activeTabId,
      });
    }
    _laidOutDayStarts = const [];
    _dayJumpToken = null;
    _postIndexProjection = null;
    _chatContextCurrentPostId = null;
    _postContexts.clear();
    _retainedPostExtents.clear();
    _laidOutPostWidth = 0;
    _extentGeneration = 0;
    _sidebarOverlayOpen = false;
  }

  void _jumpTo(int index, {double viewportOffset = 0}) {
    final list = _list;
    final scroll = _scroll;
    if (list == null || scroll == null) {
      if (_isScrollCaptureRecording) {
        _recordTopicScrollEvent('scroll.jump.skipped', {
          'reason': 'controllers-unavailable',
          'itemIndex': index,
          'viewportOffset': viewportOffset,
        });
      }
      return;
    }
    if (!list.isAttached || !scroll.hasClients) {
      if (_isScrollCaptureRecording) {
        _recordTopicScrollEvent('scroll.jump.skipped', {
          'reason': 'controllers-detached',
          'itemIndex': index,
          'viewportOffset': viewportOffset,
          'sliverLayout': _sliverLayoutData(),
        });
      }
      return;
    }
    if (_isScrollCaptureRecording) {
      _recordTopicScrollEvent('scroll.jump.requested', {
        'itemIndex': index,
        'expandedChildIndex': index * 2,
        'viewportOffset': viewportOffset,
        'before': _sliverLayoutData(),
      });
    }
    // `separated` interleaves a separator after every logical item, and the
    // ListController addresses that expanded child list.
    list.jumpToItem(index: index * 2, scrollController: scroll, alignment: 0);
    if (viewportOffset == 0 || !scroll.hasClients) {
      if (_isScrollCaptureRecording) {
        _recordTopicScrollEvent('scroll.jump.completed', {
          'itemIndex': index,
          'after': _sliverLayoutData(),
        });
      }
      return;
    }
    final position = scroll.position;
    scroll.jumpTo(
      (position.pixels - viewportOffset)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
    );
    if (_isScrollCaptureRecording) {
      _recordTopicScrollEvent('scroll.jump.completed', {
        'itemIndex': index,
        'after': _sliverLayoutData(),
      });
    }
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

    // Reveal and measure the terminal post before including trailing padding.
    list.jumpToItem(index: target, scrollController: scroll, alignment: 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => correctToEnd());
    WidgetsBinding.instance.scheduleFrame();
  }

  bool _isCurrent(
    ShellController controller,
    (String, int, int) topicIdentity,
  ) =>
      mounted &&
      _viewport.isCurrentOwner(controller, (
        siteUrl: topicIdentity.$1,
        topicId: topicIdentity.$2,
        navigationRevision: topicIdentity.$3,
      ));

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.clearVisibleTopicContext(_visibleTopicContextOwner);
    _sidebarRestoreGeneration++;
    _recommendationsTabRestoreGeneration++;
    _dayJumpToken = null;
    if (_isScrollCaptureRecording) {
      _recordTopicScrollEvent('topic.controllers.disposeScheduled', {
        'sliverLayout': _sliverLayoutData(),
      });
    }
    _viewport.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _viewport.handleAppLifecycleState(state);
  }

  void _syncRecommendationsSite(String siteUrl) {
    if (_recommendationsSiteUrl == siteUrl) return;
    _recommendationsSiteUrl = siteUrl;
    _sidebarCollapsed = false;
    _recommendationsSourceId = coreSuggestedTopicRecommendationSourceId;
    final sourceMigrations =
        PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty;
    unawaited(_restoreSidebar(siteUrl));
    unawaited(_restoreRecommendationsTab(siteUrl, sourceMigrations));
  }

  Future<void> _restoreSidebar(String siteUrl) async {
    final generation = ++_sidebarRestoreGeneration;
    final collapsed = await widget.sidebarStore.read(siteUrl: siteUrl);
    if (!mounted ||
        generation != _sidebarRestoreGeneration ||
        _recommendationsSiteUrl != siteUrl) {
      return;
    }
    if (collapsed != _sidebarCollapsed) {
      setState(() => _sidebarCollapsed = collapsed);
    }
  }

  Future<void> _restoreRecommendationsTab(
    String siteUrl,
    TopicRecommendationSourceMigrationRegistry sourceMigrations,
  ) async {
    final generation = ++_recommendationsTabRestoreGeneration;
    final sourceId = await widget.recommendationsTabStore.read(
      siteUrl: siteUrl,
      sourceMigrations: sourceMigrations,
    );
    if (!mounted ||
        generation != _recommendationsTabRestoreGeneration ||
        _recommendationsSiteUrl != siteUrl) {
      return;
    }
    if (sourceId != _recommendationsSourceId) {
      setState(() => _recommendationsSourceId = sourceId);
    }
  }

  void _setSidebarCollapsed(bool collapsed) {
    final siteUrl = _recommendationsSiteUrl;
    if (siteUrl == null || collapsed == _sidebarCollapsed) return;
    _sidebarRestoreGeneration++;
    setState(() {
      _sidebarCollapsed = collapsed;
      _sidebarOverlayOpen = false;
    });
    unawaited(
      widget.sidebarStore.write(siteUrl: siteUrl, collapsed: collapsed),
    );
  }

  void _setSidebarOverlayOpen(bool open) {
    if (open == _sidebarOverlayOpen) return;
    setState(() => _sidebarOverlayOpen = open);
  }

  void _toggleSidebar({required bool canPinSidebar}) {
    if (canPinSidebar) {
      _setSidebarCollapsed(!_sidebarCollapsed);
    } else {
      _setSidebarOverlayOpen(!_sidebarOverlayOpen);
    }
  }

  double _sidebarOverlayWidth(BuildContext context) => MediaQuery.sizeOf(
    context,
  ).width.clamp(0.0, _TopicSidebarPanel.dockedWidth).toDouble();

  void _setRecommendationsSource(TopicRecommendationSourceId sourceId) {
    final siteUrl = _recommendationsSiteUrl;
    if (siteUrl == null || sourceId == _recommendationsSourceId) return;
    _recommendationsTabRestoreGeneration++;
    setState(() => _recommendationsSourceId = sourceId);
    unawaited(
      widget.recommendationsTabStore.write(
        siteUrl: siteUrl,
        sourceId: sourceId,
      ),
    );
  }

  void _scheduleLook({bool saveAnchor = false}) {
    _viewport.scheduleLook(saveAnchor: saveAnchor);
  }

  void _inspectViewport(
    TopicViewportSnapshot snapshot, {
    required bool saveAnchor,
  }) {
    final controller = _controller;
    if (controller == null) return;
    _syncFloatingDay(snapshot);
    _noteWhatIsOnScreen(controller, snapshot, saveAnchor: saveAnchor);
    if (_isScrollCaptureRecording) _recordViewportInspection(snapshot);
  }

  void _syncFloatingDay(TopicViewportSnapshot snapshot) {
    final list = _list;
    final scroll = _scroll;
    if (list == null || scroll == null) return;
    if (!list.isAttached || !scroll.hasClients) return;
    final range = list.visibleRange;
    if (range == null || _laidOutDayStarts.isEmpty) {
      _setFloatingDay(null, 0);
      return;
    }

    final leading = snapshot.hasEarlier || snapshot.loadingEarlier ? 1 : 0;
    int? firstVisiblePostIndex;
    for (var childIndex = range.$1; childIndex <= range.$2; childIndex++) {
      if (childIndex.isOdd) continue;
      final postIndex = childIndex ~/ 2 - leading;
      if (postIndex < 0 || postIndex >= snapshot.postIds.length) continue;
      firstVisiblePostIndex = postIndex;
      break;
    }
    if (firstVisiblePostIndex == null) {
      _setFloatingDay(null, 0);
      return;
    }

    var low = 0;
    var high = _laidOutDayStarts.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (_laidOutDayStarts[middle].postIndex <= firstVisiblePostIndex) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    var candidateIndex = low - 1;
    if (candidateIndex < 0) {
      _setFloatingDay(null, 0);
      return;
    }

    double? topOf(_TopicDayStart start) =>
        _postViewportOffset(snapshot.postIds[start.postIndex]);

    // The first visible post can itself begin a day while its marker is still
    // below the viewport edge. Until it crosses, the preceding day remains the
    // sticky one.
    final candidateTop = topOf(_laidOutDayStarts[candidateIndex]);
    if (candidateTop != null && candidateTop >= 0) candidateIndex--;
    if (candidateIndex < 0) {
      _setFloatingDay(null, 0);
      return;
    }

    final current = _laidOutDayStarts[candidateIndex];
    final nextIndex = candidateIndex + 1;
    var offset = 0.0;
    if (nextIndex < _laidOutDayStarts.length) {
      final nextTop = topOf(_laidOutDayStarts[nextIndex]);
      if (nextTop != null && nextTop < StreamDaySeparator.height) {
        offset = nextTop - StreamDaySeparator.height;
      }
    }
    _setFloatingDay(current.day, offset);
  }

  void _setFloatingDay(DateTime? day, double offset) {
    _viewport.updateFloatingDay(day, offset);
  }

  List<_TopicDayStart> _dayStarts(
    ShellController controller,
    String siteUrl,
    List<int> postIds,
    DateTime today,
  ) {
    // Rebuilding this on every build costs a store read per loaded post, and
    // the floating-day push animation rebuilds per frame. Snapshots allocate
    // a fresh id list each time, so value equality is the usable key; the
    // int comparison is far cheaper than the reads it saves. Created-at never
    // changes for a held post, so the same ids on the same reader day mean the
    // same day starts.
    if (_dayStartsSite == siteUrl &&
        _dayStartsToday == today &&
        listEquals(_dayStartsFor, postIds)) {
      return _dayStartsCache;
    }
    final starts = <_TopicDayStart>[];
    DateTime? previousDay;
    for (var index = 0; index < postIds.length; index++) {
      final post = controller.store.read<Post>(siteUrl, postIds[index]);
      final day = calendarDay(post?.createdAt);
      final isTodaysOpeningPost = post?.postNumber == 1 && day == today;
      if (day != null && day != previousDay && !isTodaysOpeningPost) {
        starts.add((day: day, postIndex: index));
      }
      previousDay = day;
    }
    _dayStartsCache = starts;
    _dayStartsFor = postIds;
    _dayStartsSite = siteUrl;
    _dayStartsToday = today;
    return starts;
  }

  List<_TopicDayStart> _dayStartsCache = const [];
  List<int>? _dayStartsFor;
  String? _dayStartsSite;
  DateTime? _dayStartsToday;

  List<_TopicTimeGap> _timeGaps(
    ShellController controller,
    String siteUrl,
    List<int> postIds,
    int showAfterDays,
  ) {
    if (_timeGapsSite == siteUrl &&
        _timeGapsShowAfterDays == showAfterDays &&
        listEquals(_timeGapsFor, postIds)) {
      return _timeGapsCache;
    }

    final gaps = <_TopicTimeGap>[];
    Post? previous;
    for (var index = 0; index < postIds.length; index++) {
      final post = controller.store.read<Post>(siteUrl, postIds[index]);
      final daysSince = timeGapDaysBetween(
        previous?.createdAt,
        post?.createdAt,
      );
      if (daysSince != null && daysSince > showAfterDays) {
        gaps.add((daysSince: daysSince, postIndex: index));
      }
      previous = post;
    }
    _timeGapsCache = gaps;
    _timeGapsFor = postIds;
    _timeGapsSite = siteUrl;
    _timeGapsShowAfterDays = showAfterDays;
    return gaps;
  }

  List<_TopicTimeGap> _timeGapsCache = const [];
  List<int>? _timeGapsFor;
  String? _timeGapsSite;
  int? _timeGapsShowAfterDays;

  Future<void> _jumpToDayStart(DateTime day) async {
    final controller = _controller;
    final identity = _topicIdentity;
    if (controller == null || identity == null) return;

    final token = Object();
    _dayJumpToken = token;
    _viewport.beginRestoration();

    bool isCurrent() =>
        identical(_dayJumpToken, token) && _isCurrent(controller, identity);

    while (isCurrent()) {
      final snapshot = TopicViewportSnapshot.from(controller);
      if (!snapshot.hasEarlier || snapshot.postIds.isEmpty) break;
      final first = controller.store.read<Post>(
        snapshot.siteUrl!,
        snapshot.postIds.first,
      );
      if (calendarDay(first?.createdAt) != day) break;

      final before = List<int>.of(snapshot.postIds);
      await controller.loadEarlierPosts();
      if (!isCurrent()) return;
      if (listEquals(before, TopicViewportSnapshot.from(controller).postIds)) {
        // A refused page should still land on the earliest copy in hand rather
        // than retrying forever from one click.
        break;
      }
    }
    if (!isCurrent()) return;

    void finish() {
      if (!isCurrent()) return;
      _dayJumpToken = null;
      _viewport.finishRestoration(saveAnchor: true);
      _viewport.scheduleLoadEarlier(TopicViewportSnapshot.from(controller));
    }

    void jump() {
      if (!isCurrent()) return;
      final snapshot = TopicViewportSnapshot.from(controller);
      final postIndex = snapshot.postIds.indexWhere((id) {
        final post = controller.store.read<Post>(snapshot.siteUrl!, id);
        return calendarDay(post?.createdAt) == day;
      });
      if (postIndex < 0) return;
      final leading = snapshot.hasEarlier || snapshot.loadingEarlier ? 1 : 0;
      _jumpTo(postIndex + leading);
    }

    // A preceding page changes the list in the same event turn. Let it lay
    // out before addressing its rows, then repeat once measured just like the
    // reader's normal post restoration.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isCurrent()) return;
      jump();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isCurrent()) return;
        jump();
        finish();
      });
    });
  }

  void _noteWhatIsOnScreen(
    ShellController controller,
    TopicViewportSnapshot snapshot, {
    bool saveAnchor = false,
  }) {
    if (!_restored || _restoring || _list?.isAttached != true) return;
    final range = _list!.visibleRange;
    if (range == null) return;

    final leading = snapshot.hasEarlier || snapshot.loadingEarlier ? 1 : 0;
    TopicViewportSeenPost? leadingPost;
    for (var childIndex = range.$1; childIndex <= range.$2; childIndex++) {
      if (childIndex.isOdd) continue;
      final itemIndex = childIndex ~/ 2;
      final postIndex = itemIndex - leading;
      if (postIndex < 0 || postIndex >= snapshot.postIds.length) continue;
      final post = controller.store.read<Post>(
        snapshot.siteUrl!,
        snapshot.postIds[postIndex],
      );
      if (post != null) {
        leadingPost = (
          postId: post.id,
          postNumber: post.postNumber,
          caughtUp: false,
        );
      }
      break;
    }

    // Progress follows the farthest intersecting post so the control remains
    // responsive while reading inside a post taller than the viewport.
    TopicViewportSeenPost? visiblePost;
    for (var childIndex = range.$2; childIndex >= range.$1; childIndex--) {
      if (childIndex.isOdd) continue;
      final itemIndex = childIndex ~/ 2;
      final postIndex = itemIndex - leading;
      if (postIndex < 0 || postIndex >= snapshot.postIds.length) continue;
      final post = controller.store.read<Post>(
        snapshot.siteUrl!,
        snapshot.postIds[postIndex],
      );
      if (post == null) continue;
      visiblePost = (
        postId: post.id,
        postNumber: post.postNumber,
        caughtUp: !snapshot.hasMore && postIndex == snapshot.postIds.length - 1,
      );
      break;
    }

    final scrollPosition = _scroll!.position;
    final contextEyeline = topicContextEyeline(
      viewportExtent: scrollPosition.viewportDimension,
      scrollOffset: scrollPosition.pixels,
      maxScrollExtent: scrollPosition.maxScrollExtent,
      postStreamBottom: snapshot.hasMore || snapshot.postIds.isEmpty
          ? null
          : _postViewportBounds(snapshot.postIds.last)?.bottom,
      hasMore: snapshot.hasMore,
    );
    TopicViewportSeenPost? contextPost;
    for (var childIndex = range.$1; childIndex <= range.$2; childIndex++) {
      if (childIndex.isOdd) continue;
      final itemIndex = childIndex ~/ 2;
      final postIndex = itemIndex - leading;
      if (postIndex < 0 || postIndex >= snapshot.postIds.length) continue;
      final post = controller.store.read<Post>(
        snapshot.siteUrl!,
        snapshot.postIds[postIndex],
      );
      if (post == null) continue;
      final bounds = _postViewportBounds(post.id);
      if (bounds == null ||
          contextEyeline < bounds.top - 0.5 ||
          contextEyeline > bounds.bottom + 0.5) {
        continue;
      }
      contextPost = (
        postId: post.id,
        postNumber: post.postNumber,
        caughtUp: false,
      );
      break;
    }

    // Separators can briefly cross the eyeline. Like web, retain the prior
    // current post until another post itself contains the line.
    final previousContextPostId = _chatContextCurrentPostId;
    if (contextPost == null &&
        previousContextPostId != null &&
        snapshot.postIds.contains(previousContextPostId)) {
      final previous = controller.store.read<Post>(
        snapshot.siteUrl!,
        previousContextPostId,
      );
      if (previous != null) {
        contextPost = (
          postId: previous.id,
          postNumber: previous.postNumber,
          caughtUp: false,
        );
      }
    }
    contextPost ??= leadingPost;
    _chatContextCurrentPostId = contextPost?.postId;

    controller.updateVisibleTopicContext(
      owner: _visibleTopicContextOwner,
      siteUrl: snapshot.siteUrl!,
      topicId: snapshot.topicId!,
      postIds: contextPost == null
          ? const []
          : _chatContextPostIds(controller, snapshot, contextPost.postId),
    );

    // A one-pixel glimpse of a very tall post is not evidence that it was
    // read. Advance receipts only through a post whose trailing edge reached
    // the viewport; a post taller than the screen qualifies when its end is
    // eventually reached.
    final viewportExtent = _scroll?.position.viewportDimension;
    if (viewportExtent == null) return;
    TopicViewportSeenPost? readablePost;
    for (var childIndex = range.$2; childIndex >= range.$1; childIndex--) {
      if (childIndex.isOdd) continue;
      final itemIndex = childIndex ~/ 2;
      final postIndex = itemIndex - leading;
      if (postIndex < 0 || postIndex >= snapshot.postIds.length) continue;
      final post = controller.store.read<Post>(
        snapshot.siteUrl!,
        snapshot.postIds[postIndex],
      );
      if (post == null) continue;
      final bounds = _postViewportBounds(post.id);
      if (bounds == null || bounds.bottom > viewportExtent + 0.5) continue;
      readablePost = (
        postId: post.id,
        postNumber: post.postNumber,
        caughtUp: !snapshot.hasMore && postIndex == snapshot.postIds.length - 1,
      );
      break;
    }

    final previousProgress = _progressPosition;
    final previousSavedAnchor = _savedAnchorPostNumber;
    _viewport.recordObservation(
      snapshot: snapshot,
      saveAnchor: saveAnchor,
      leading: leadingPost,
      visible: visiblePost,
      readable: readablePost,
    );
    if (_isScrollCaptureRecording && previousProgress != _progressPosition) {
      _recordTopicScrollEvent('topic.progress.changed', {
        'previous': previousProgress,
        'current': _progressPosition,
      });
    }
    if (_isScrollCaptureRecording &&
        previousSavedAnchor != _savedAnchorPostNumber &&
        leadingPost != null) {
      _recordTopicScrollEvent('viewport.anchor.saved', {
        'postId': leadingPost.postId,
        'postNumber': leadingPost.postNumber,
        'viewportOffset': _postViewportOffset(leadingPost.postId),
        'saveAfterScrollEnd': saveAnchor,
      });
    }
  }

  /// Matches web chat context: the current intersecting post and the nearest
  /// non-hidden, non-deleted post on either side of it.
  List<int> _chatContextPostIds(
    ShellController controller,
    TopicViewportSnapshot snapshot,
    int currentPostId,
  ) {
    final currentIndex = snapshot.postIds.indexOf(currentPostId);
    if (currentIndex < 0) return const [];

    int? eligibleNeighbor(int from, int step) {
      for (
        var index = from;
        index >= 0 && index < snapshot.postIds.length;
        index += step
      ) {
        final post = controller.store.read<Post>(
          snapshot.siteUrl!,
          snapshot.postIds[index],
        );
        if (post != null && !post.hidden && !post.isDeleted) return post.id;
      }
      return null;
    }

    return [
      ?eligibleNeighbor(currentIndex - 1, -1),
      currentPostId,
      ?eligibleNeighbor(currentIndex + 1, 1),
    ];
  }

  void _onListLayoutChanged() {
    if (_isScrollCaptureRecording) {
      // This can notify more than once inside one layout. Keep the marker
      // cheap; _scheduleLook coalesces the full geometry read after the frame.
      _recordTopicScrollEvent('sliver.layout.changed', {
        'listAttached': _list?.isAttached ?? false,
        'scrollAttached': _scroll?.hasClients ?? false,
      });
    }
  }

  void _invalidateRetainedExtents() {
    final list = _list;
    if (list == null || !list.isAttached) return;
    if (!list.isLocked) {
      if (_isScrollCaptureRecording) {
        _recordTopicScrollEvent('sliver.extents.invalidated', {
          'deferred': false,
          'before': _sliverLayoutData(),
        });
      }
      list.invalidateAllExtents();
      return;
    }
    if (_isScrollCaptureRecording) {
      _recordTopicScrollEvent('sliver.extentInvalidation.deferred', {
        'before': _sliverLayoutData(),
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = _list;
      if (current == null || !current.isAttached || current.isLocked) return;
      if (_isScrollCaptureRecording) {
        _recordTopicScrollEvent('sliver.extents.invalidated', {
          'deferred': true,
          'before': _sliverLayoutData(),
        });
      }
      current.invalidateAllExtents();
    });
  }

  void _registerPostContext(int postId, BuildContext context) {
    _postContexts[postId] = context;
    if (_isScrollCaptureRecording) {
      _recordTopicScrollEvent('sliver.post.attached', {
        'postId': postId,
        'attachedPostCount': _postContexts.length,
      });
    }
  }

  void _unregisterPostContext(int postId, BuildContext context) {
    if (identical(_postContexts[postId], context)) {
      _rememberPostExtent(postId);
      _postContexts.remove(postId);
      if (_isScrollCaptureRecording) {
        _recordTopicScrollEvent('sliver.post.detached', {
          'postId': postId,
          'attachedPostCount': _postContexts.length,
        });
      }
    }
  }

  void _rememberPostExtent(int postId) {
    final snapshot = _laidOutSnapshot;
    final controller = _controller;
    final list = _list;
    if (snapshot == null ||
        controller == null ||
        list == null ||
        !list.isAttached) {
      return;
    }
    final postIndex = snapshot.postIds.indexOf(postId);
    if (postIndex < 0) return;
    final leading = snapshot.hasEarlier || snapshot.loadingEarlier ? 1 : 0;
    final childIndex = (postIndex + leading) * 2;
    if (childIndex >= list.numberOfItems) return;
    final extent = list.extentForIndex(childIndex);
    if (extent.$2) return;
    final post = controller.store.read<Post>(snapshot.siteUrl!, postId);
    final topic = snapshot.topic;
    if (post == null ||
        topic == null ||
        !CookedHtml.buildsAsynchronously(post.cooked)) {
      return;
    }
    final width = _laidOutPostWidth;
    final height = extent.$1;
    final retained = (
      width: width,
      height: height,
      post: post,
      topic: topic,
      summary: snapshot.summary,
      summaryLoading: snapshot.summaryLoading,
      readTimeWordCount: snapshot.readTimeWordCount,
    );
    final previous = _retainedPostExtents[postId];
    // Do not let the asynchronous loading frame replace a settled extent for
    // the same post. A changed post or topic gets a fresh measurement instead.
    if (previous != null &&
        identical(previous.post, post) &&
        identical(previous.topic, topic) &&
        previous.summary == snapshot.summary &&
        previous.summaryLoading == snapshot.summaryLoading &&
        previous.readTimeWordCount == snapshot.readTimeWordCount &&
        (previous.width - width).abs() < 0.5 &&
        previous.height > height) {
      return;
    }
    _retainedPostExtents[postId] = retained;
  }

  double? _retainedPostMinimumHeight({
    required int postId,
    required Post? post,
    required TopicDetail topic,
    required double width,
    required bool summary,
    required bool summaryLoading,
    required int readTimeWordCount,
  }) {
    final retained = _retainedPostExtents[postId];
    if (retained == null ||
        post == null ||
        !identical(retained.post, post) ||
        !identical(retained.topic, topic) ||
        retained.summary != summary ||
        retained.summaryLoading != summaryLoading ||
        retained.readTimeWordCount != readTimeWordCount ||
        (retained.width - width).abs() >= 0.5) {
      return null;
    }
    return retained.height;
  }

  ({double top, double bottom})? _postViewportBounds(int postId) {
    final context = _postContexts[postId];
    final scroll = _scroll;
    if (context == null || scroll == null || !scroll.hasClients) return null;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) return null;
    final revealed = getOffsetToRevealIfLaidOut(viewport, renderObject, 0);
    if (revealed == null) return null;
    final top = revealed.offset - scroll.position.pixels;
    return (top: top, bottom: top + renderObject.size.height);
  }

  double? _postViewportOffset(int postId) => _postViewportBounds(postId)?.top;

  ({int postId, double viewportOffset})? _captureViewportAnchor(
    List<int> postIds, {
    required bool hasHeader,
  }) {
    final list = _list;
    final scroll = _scroll;
    if (list == null || scroll == null) return null;
    if (!list.isAttached || !scroll.hasClients) return null;
    final range = list.visibleRange;
    if (range == null) return null;

    final leading = hasHeader ? 1 : 0;
    for (var childIndex = range.$1; childIndex <= range.$2; childIndex++) {
      if (childIndex.isOdd) continue;
      final postIndex = childIndex ~/ 2 - leading;
      if (postIndex < 0 || postIndex >= postIds.length) continue;
      final viewportOffset = _postViewportOffset(postIds[postIndex]);
      if (viewportOffset == null) continue;
      return (postId: postIds[postIndex], viewportOffset: viewportOffset);
    }
    return null;
  }

  void _applyWindowChange(TopicViewportWindowChange change) {
    if (_isScrollCaptureRecording &&
        change.previousPostIds.isNotEmpty &&
        change.changed) {
      _recordTopicScrollEvent('topic.window.changed', {
        'previousPostCount': change.previousPostIds.length,
        'currentPostCount': change.currentPostIds.length,
        'previousFirstPostId': change.previousPostIds.firstOrNull,
        'previousLastPostId': change.previousPostIds.lastOrNull,
        'currentFirstPostId': change.currentPostIds.firstOrNull,
        'currentLastPostId': change.currentPostIds.lastOrNull,
        'previousFirstIndex': change.currentPostIds.indexOf(
          change.previousPostIds.first,
        ),
        'prepended': change.prepended,
        'appendOnly': change.appendOnly,
        'headerChanged': change.previousHasHeader != change.hasHeader,
      });
    }
    switch (change.extentAction) {
      case TopicViewportExtentAction.none:
        return;
      case TopicViewportExtentAction.invalidate:
        _invalidateRetainedExtents();
        return;
      case TopicViewportExtentAction.replace:
        _extentGeneration++;
        if (_isScrollCaptureRecording) {
          _recordTopicScrollEvent('sliver.extentManager.replaced', {
            'extentGeneration': _extentGeneration,
            'reason': 'topic-window-replaced',
          });
        }
    }
  }

  @override
  Widget build(BuildContext context) => ShellSelector<TopicViewportSnapshot>(
    select: TopicViewportSnapshot.from,
    builder: (context, snapshot, child) => ListenableBuilder(
      listenable: _viewportState,
      builder: (context, child) => _build(context, snapshot, child),
    ),
  );

  Widget _build(
    BuildContext context,
    TopicViewportSnapshot snapshot,
    Widget? child,
  ) => LayoutBuilder(
    builder: (context, constraints) =>
        _buildForViewport(context, snapshot, constraints.maxWidth),
  );

  Widget _buildForViewport(
    BuildContext context,
    TopicViewportSnapshot snapshot,
    double viewportWidth,
  ) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);
    _scrollCapture = DiagnosticsScope.maybeRead(context)?.topicScrollCapture;
    if (snapshot.siteUrl case final siteUrl?) {
      _syncRecommendationsSite(siteUrl);
    }
    final canPinSidebar =
        widget.showSidebar &&
        viewportWidth >= _TopicSidebarPanel.minimumPinnedViewportWidth;
    final showPinnedSidebar = canPinSidebar && !_sidebarCollapsed;
    final showOverlaySidebar = !canPinSidebar && _sidebarOverlayOpen;
    final pinnedSidebarInset = showPinnedSidebar
        ? _TopicSidebarPanel.dockedWidth
        : 0.0;
    final readingLane = ContentReadingLane.geometryFor(
      context,
      availableWidth: viewportWidth,
      basePadding: EdgeInsets.only(right: pinnedSidebarInset),
    );
    _laidOutPostWidth = readingLane.width;

    if (snapshot.topicId == null) {
      if (snapshot.loading) {
        const topicSkeleton = _TopicLoadingSkeleton(
          key: ValueKey('topic-loading-skeleton'),
        );
        return Column(
          children: [
            _TopicViewHeader(
              title: widget.route?.title ?? 'Topic',
              siteUrl: snapshot.siteUrl,
              route: widget.route,
              canReturnToSidebar: widget.canReturnToSidebar,
              sidebarVisible: showPinnedSidebar || showOverlaySidebar,
              onToggleSidebar: showOverlaySidebar
                  ? null
                  : () => _toggleSidebar(canPinSidebar: canPinSidebar),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: readingLane.padding,
                      child: topicSkeleton,
                    ),
                  ),
                  if (showPinnedSidebar)
                    Positioned(
                      top: 0,
                      right: 0,
                      bottom: 0,
                      child: _TopicSidebarPanel(
                        siteUrl: snapshot.siteUrl,
                        topic: null,
                        recommendations: null,
                        loading: true,
                        selected: _recommendationsSourceId,
                        onSelected: _setRecommendationsSource,
                        route: widget.route,
                        canReply: false,
                        registry: widget.registry,
                      ),
                    ),
                  if (showOverlaySidebar)
                    Positioned(
                      top: 0,
                      right: 0,
                      bottom: 0,
                      child: _TopicSidebarPanel(
                        width: _sidebarOverlayWidth(context),
                        siteUrl: snapshot.siteUrl,
                        topic: null,
                        recommendations: null,
                        loading: true,
                        selected: _recommendationsSourceId,
                        onSelected: _setRecommendationsSource,
                        onCollapsed: () => _setSidebarOverlayOpen(false),
                        route: widget.route,
                        canReply: false,
                        registry: widget.registry,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      }
      return Column(
        children: [
          _TopicViewHeader(
            title: widget.route?.title ?? 'Topic',
            siteUrl: snapshot.siteUrl,
            route: widget.route,
            canReturnToSidebar: widget.canReturnToSidebar,
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DIcon(
                      DIcons.triangleExclamation,
                      size: 40,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Couldn't load this topic.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final showFooter = snapshot.loadingMore;
    final showHeader = snapshot.hasEarlier || snapshot.loadingEarlier;
    final hasRecommendations = snapshot.recommendations?.isNotEmpty == true;
    final showRecommendations = !snapshot.hasMore && hasRecommendations;
    // A null payload is unresolved rather than empty: Discourse only sends
    // the recommendation fields with the final post window. Reserve the
    // eventual panel while that window is still outstanding so its arrival
    // fills the fixed sidebar without shifting the reading content.
    final recommendationsPending =
        snapshot.recommendations == null &&
        (snapshot.hasMore || snapshot.loadingMore);
    final postIds = snapshot.postIds;
    final postIndexes = _postIndexes(postIds);
    final siteUrl = snapshot.siteUrl!;
    _syncViewport(controller, snapshot);
    _viewport.updateLaidOutSnapshot(snapshot);
    final dayStarts = _dayStarts(
      controller,
      siteUrl,
      postIds,
      calendarDay(widget.now?.call() ?? DateTime.now())!,
    );
    _laidOutDayStarts = dayStarts;
    final dayByPostIndex = {
      for (final start in dayStarts) start.postIndex: start.day,
    };
    final timeGapByPostIndex = {
      for (final gap in _timeGaps(
        controller,
        siteUrl,
        postIds,
        snapshot.showTimeGapDays,
      ))
        gap.postIndex: gap.daysSince,
    };
    _viewport.restoreInitialPost(snapshot);
    _applyWindowChange(_viewport.updateWindow(snapshot, hasHeader: showHeader));
    if (_isScrollCaptureRecording) {
      _recordTopicScrollEvent('topic.view.built', {
        'viewportWidth': viewportWidth,
        'pinnedSidebarInset': pinnedSidebarInset,
        'showHeader': showHeader,
        'showFooter': showFooter,
        'showRecommendations': showRecommendations,
        'itemCount':
            postIds.length +
            (showHeader ? 1 : 0) +
            (showFooter ? 1 : 0) +
            (showRecommendations && (!widget.showSidebar || !canPinSidebar)
                ? 1
                : 0),
        'topicWindow': _topicWindowData(snapshot),
      });
    }
    _scheduleLook();

    final postStreamContent = NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) {
          if (_isScrollCaptureRecording) {
            _recordTopicScrollEvent('scroll.metricsChanged', {
              'depth': notification.depth,
              'metrics': _scrollMetricsData(notification.metrics),
            });
          }
          _scheduleLook();
        }
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) {
            if (_isScrollCaptureRecording) {
              _recordScrollNotification(notification);
            }
            _viewport.handleScroll(notification, snapshot);
          }
          return false;
        },
        // SuperListView retains measured post heights without eagerly building
        // media-heavy offscreen posts, keeping scrollbar estimates stable.
        child: SuperListView.separated(
          key: ValueKey((
            siteUrl,
            snapshot.topicId,
            snapshot.navigationRevision,
            _extentGeneration,
          )),
          controller: _scroll,
          listController: _list,
          // The post viewport itself stays full width so it owns the only
          // vertical scrollbar. The pinned sidebar floats above its right
          // edge; this inner inset keeps post content from sitting beneath it.
          padding: readingLane.padding,
          // A short around-post window still needs to accept a pull toward the
          // top, both to fetch and to retry an earlier page. Once post one is in
          // hand, stop forcing top-edge overscroll: there is no earlier request
          // left for that gesture to make.
          physics: SuperRangeMaintainingScrollPhysics(
            parent: snapshot.hasEarlier || snapshot.hasMore
                ? const AlwaysScrollableScrollPhysics()
                : null,
          ),
          extentEstimation: TopicView._estimateChildExtent,
          // Keep existing post elements attached to their ids when a page is
          // inserted before them; separated lists address the expanded index.
          findChildIndexCallback: (key) {
            if (key is! ValueKey<int>) return null;
            final postIndex = postIndexes[key.value];
            if (postIndex == null) return null;
            final childIndex = (postIndex + (showHeader ? 1 : 0)) * 2;
            if (_isScrollCaptureRecording) {
              _recordTopicScrollEvent('sliver.childIndex.resolved', {
                'postId': key.value,
                'postIndex': postIndex,
                'childIndex': childIndex,
                'showHeader': showHeader,
              });
            }
            return childIndex;
          },
          itemCount:
              postIds.length +
              (showHeader ? 1 : 0) +
              (showFooter ? 1 : 0) +
              (showRecommendations && (!widget.showSidebar || !canPinSidebar)
                  ? 1
                  : 0),
          separatorBuilder: (context, index) {
            final nextPostIndex = index + 1 - (showHeader ? 1 : 0);
            if (_isScrollCaptureRecording) {
              _recordTopicScrollEvent('sliver.separator.built', {
                'separatorIndex': index,
                'nextPostIndex': nextPostIndex,
                'isDayBoundary': dayByPostIndex.containsKey(nextPostIndex),
              });
            }
            if (dayByPostIndex.containsKey(nextPostIndex)) {
              return const SizedBox.shrink();
            }
            return Divider(height: 1, color: theme.shell.divider);
          },
          itemBuilder: (context, index) {
            if (showHeader && index == 0) {
              if (_isScrollCaptureRecording) {
                _recordTopicScrollEvent('sliver.child.built', {
                  'itemIndex': index,
                  'kind': 'earlier-posts',
                  'loading': snapshot.loadingEarlier,
                });
              }
              return _EarlierPostsRow(loading: snapshot.loadingEarlier);
            }

            final postIndex = index - (showHeader ? 1 : 0);
            if (postIndex >= postIds.length) {
              final trailingIndex = postIndex - postIds.length;
              if (showFooter && trailingIndex == 0) {
                if (_isScrollCaptureRecording) {
                  _recordTopicScrollEvent('sliver.child.built', {
                    'itemIndex': index,
                    'kind': 'loading-more',
                  });
                }
                return const _LoadingPostsRow();
              }
              if (_isScrollCaptureRecording) {
                _recordTopicScrollEvent('sliver.child.built', {
                  'itemIndex': index,
                  'kind': 'recommendations',
                });
              }
              return _MoreTopics(
                key: ValueKey((siteUrl, snapshot.topicId, 'more-topics')),
                siteUrl: siteUrl,
                recommendations: snapshot.recommendations!,
                selected: _recommendationsSourceId,
                onSelected: _setRecommendationsSource,
              );
            }

            final postId = postIds[postIndex];
            final day = dayByPostIndex[postIndex];
            final post = controller.store.read<Post>(siteUrl, postId);
            if (_isScrollCaptureRecording) {
              _recordTopicScrollEvent('sliver.child.built', {
                'itemIndex': index,
                'postIndex': postIndex,
                'postId': postId,
                'postNumber': post?.postNumber,
                'wasAttached': _postContexts.containsKey(postId),
                'hasDayBoundary': day != null,
                'hasTimeGap': timeGapByPostIndex.containsKey(postIndex),
              });
            }
            return _TopicPostItem(
              key: ValueKey(postId),
              postId: postId,
              retainedMinimumHeight: _retainedPostMinimumHeight(
                postId: postId,
                post: post,
                topic: snapshot.topic!,
                width: readingLane.width,
                summary: snapshot.summary,
                summaryLoading: snapshot.summaryLoading,
                readTimeWordCount: snapshot.readTimeWordCount,
              ),
              day: day,
              timeGapDays: timeGapByPostIndex[postIndex],
              hideDay: day != null && day == _floatingDay,
              onDayTap: day == null ? null : () => _jumpToDayStart(day),
              gapBefore: snapshot.topic!.gapsBefore[postId] ?? const [],
              gapAfter: snapshot.topic!.gapsAfter[postId] ?? const [],
              expandGapBefore: () =>
                  controller.expandPostGap(anchorPostId: postId, before: true),
              expandGapAfter: () =>
                  controller.expandPostGap(anchorPostId: postId, before: false),
              onAttach: _registerPostContext,
              onDetach: _unregisterPostContext,
              child: _StoredPost(
                siteUrl: siteUrl,
                topic: snapshot.topic!,
                postId: postId,
                summary: snapshot.summary,
                summaryLoading: snapshot.summaryLoading,
                readTimeWordCount: snapshot.readTimeWordCount,
              ),
            );
          },
        ),
      ),
    );
    final postStream = ScrollbarTheme(
      data: const ScrollbarThemeData(thickness: WidgetStatePropertyAll(4)),
      child: ListBoundaryShortcuts(
        key: ValueKey(('topic-post-boundary', siteUrl, snapshot.topicId)),
        debugLabel: 'topic post stream',
        initiallyActive: true,
        onStart: () => _jumpToBoundary(end: false),
        onEnd: () => _jumpToBoundary(end: true),
        child: postStreamContent,
      ),
    );

    final floatingDay = _floatingDay;
    return Column(
      children: [
        _TopicViewHeader(
          title: snapshot.topic!.title,
          siteUrl: siteUrl,
          route: widget.route,
          topic: snapshot.topic!,
          isConnected: widget.isConnected,
          bookmarkBusy: widget.bookmarkBusy,
          canReturnToSidebar: widget.canReturnToSidebar,
          sidebarVisible: showPinnedSidebar || showOverlaySidebar,
          onToggleSidebar: showOverlaySidebar
              ? null
              : () => _toggleSidebar(canPinSidebar: canPinSidebar),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(right: pinnedSidebarInset),
                      child: _TopicPostSelectionToolbar(
                        siteUrl: siteUrl,
                        topic: snapshot.topic!,
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          Positioned.fill(child: postStream),
                          if (floatingDay != null)
                            Positioned(
                              left: readingLane.padding.left,
                              right: readingLane.padding.right,
                              top: _floatingDayOffset,
                              child: StreamDaySeparator(
                                key: ValueKey((
                                  'topic-floating-day',
                                  floatingDay,
                                )),
                                day: floatingDay,
                                floating: true,
                                onTap: () => _jumpToDayStart(floatingDay),
                              ),
                            ),
                          if (_progressPosition case final position?
                              when snapshot.streamIds.length > 1)
                            Positioned(
                              right: readingLane.padding.right + 16,
                              bottom: 16,
                              child: TopicProgressButton(
                                position: position,
                                total: snapshot.streamIds.length,
                                onPressed: () => unawaited(
                                  showTopicProgress(
                                    context: context,
                                    controller: controller,
                                    position: position,
                                    total: snapshot.streamIds.length,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (showPinnedSidebar)
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: _TopicSidebarPanel(
                    siteUrl: siteUrl,
                    topic: snapshot.topic!,
                    recommendations: snapshot.recommendations,
                    loading: recommendationsPending || snapshot.loadingMore,
                    selected: _recommendationsSourceId,
                    onSelected: _setRecommendationsSource,
                    route: widget.route,
                    canReply: widget.canReply,
                    registry: widget.registry,
                  ),
                ),
              if (showOverlaySidebar)
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: _TopicSidebarPanel(
                    width: _sidebarOverlayWidth(context),
                    siteUrl: siteUrl,
                    topic: snapshot.topic!,
                    recommendations: snapshot.recommendations,
                    loading: recommendationsPending || snapshot.loadingMore,
                    selected: _recommendationsSourceId,
                    onSelected: _setRecommendationsSource,
                    onCollapsed: () => _setSidebarOverlayOpen(false),
                    route: widget.route,
                    canReply: widget.canReply,
                    registry: widget.registry,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopicPostSelectionToolbar extends StatelessWidget {
  const _TopicPostSelectionToolbar({
    required this.siteUrl,
    required this.topic,
  });

  final String siteUrl;
  final TopicDetail topic;

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
    bool destructive = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            DButton(
              label: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            DButton(
              key: ValueKey('topic-selected-${action.toLowerCase()}-confirm'),
              label: Text(action),
              onPressed: () => Navigator.of(context).pop(true),
              variant: destructive
                  ? DButtonVariant.danger
                  : DButtonVariant.primary,
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _delete(
    BuildContext context,
    ShellController controller,
    int count,
  ) async {
    final confirmed = await _confirm(
      context,
      title: 'Delete selected posts?',
      message: 'Delete $count selected ${count == 1 ? 'post' : 'posts'}?',
      action: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final error = await controller.deleteSelectedTopicPosts(siteUrl, topic.id);
    if (error != null && context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _merge(
    BuildContext context,
    ShellController controller,
    int count,
  ) async {
    final confirmed = await _confirm(
      context,
      title: 'Merge selected posts?',
      message: 'Merge $count posts by the same author into one post?',
      action: 'Merge',
    );
    if (!confirmed || !context.mounted) return;
    final error = await controller.mergeSelectedTopicPosts(siteUrl, topic.id);
    if (error != null && context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShellSelector<
      ({bool enabled, bool busy, List<Post> selected, int loaded})
    >(
      select: (controller) => (
        enabled: controller.topicPostSelectionEnabled(siteUrl, topic.id),
        busy: controller.topicPostSelectionWriteInFlight(siteUrl, topic.id),
        selected: controller.selectedTopicPosts(siteUrl, topic.id),
        loaded: topic.stream
            .where((id) => controller.store.read<Post>(siteUrl, id) != null)
            .length,
      ),
      builder: (context, state, _) {
        if (!state.enabled) return const SizedBox.shrink();
        final controller = ShellScope.read(context);
        final selected = state.selected;
        final canDelete =
            selected.isNotEmpty && selected.every((post) => post.canDelete);
        final canMerge =
            selected.length > 1 &&
            canDelete &&
            selected.map((post) => post.username).toSet().length == 1;
        final canChangeOwner = controller.canChangeSelectedTopicPostOwner(
          siteUrl,
          topic.id,
        );
        final count = selected.length;
        final theme = Theme.of(context);
        return Material(
          key: const ValueKey('topic-selected-posts-toolbar'),
          color: theme.colorScheme.surfaceContainer,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.shell.divider)),
            ),
            child: SizedBox(
              height: 52,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    if (state.busy) ...[
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      '$count ${count == 1 ? 'post' : 'posts'} selected',
                      key: const ValueKey('topic-selected-posts-count'),
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      key: const ValueKey('topic-selected-posts-all'),
                      onPressed: state.busy || state.loaded == 0
                          ? null
                          : () => controller.selectAllLoadedTopicPosts(
                              siteUrl,
                              topic.id,
                            ),
                      child: const Text('Select all loaded'),
                    ),
                    TextButton(
                      key: const ValueKey('topic-selected-posts-clear'),
                      onPressed: state.busy || selected.isEmpty
                          ? null
                          : () => controller.clearSelectedTopicPosts(
                              siteUrl,
                              topic.id,
                            ),
                      child: const Text('Clear'),
                    ),
                    TextButton.icon(
                      key: const ValueKey('topic-selected-posts-move'),
                      onPressed:
                          state.busy || selected.isEmpty || !topic.canMovePosts
                          ? null
                          : () => unawaited(
                              showTopicMovePosts(
                                context: context,
                                controller: controller,
                                siteUrl: siteUrl,
                                topic: topic,
                                selectedPosts: selected,
                              ),
                            ),
                      icon: const DIcon(DIcons.rightFromBracket, size: 15),
                      label: const Text('Move'),
                    ),
                    TextButton.icon(
                      key: const ValueKey('topic-selected-posts-change-owner'),
                      onPressed: state.busy || !canChangeOwner
                          ? null
                          : () => unawaited(
                              showTopicChangeOwner(
                                context: context,
                                controller: controller,
                                siteUrl: siteUrl,
                                topicId: topic.id,
                                selectedPosts: selected,
                              ),
                            ),
                      icon: const DIcon(DIcons.user, size: 15),
                      label: const Text('Change owner'),
                    ),
                    TextButton.icon(
                      key: const ValueKey('topic-selected-posts-merge'),
                      onPressed: state.busy || !canMerge
                          ? null
                          : () => unawaited(
                              _merge(context, controller, selected.length),
                            ),
                      icon: const DIcon(DIcons.layerGroup, size: 15),
                      label: const Text('Merge'),
                    ),
                    TextButton.icon(
                      key: const ValueKey('topic-selected-posts-delete'),
                      onPressed: state.busy || !canDelete
                          ? null
                          : () => unawaited(
                              _delete(context, controller, selected.length),
                            ),
                      icon: const DIcon(DIcons.trashCan, size: 15),
                      label: const Text('Delete'),
                    ),
                    TextButton(
                      key: const ValueKey('topic-selected-posts-cancel'),
                      onPressed: state.busy
                          ? null
                          : () => controller.setTopicPostSelectionEnabled(
                              siteUrl,
                              topic.id,
                              false,
                            ),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopicLoadingSkeleton extends StatelessWidget {
  const _TopicLoadingSkeleton({super.key});

  static const _patternHeight = 404.0;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).shell.divider;

    return LoadingSkeleton(
      semanticsLabel: 'Loading topic',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final patternCount = constraints.hasBoundedHeight
              ? (constraints.maxHeight / _patternHeight).ceil()
              : 1;

          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: double.infinity,
              child: Column(
                key: const ValueKey('topic-loading-skeleton-content'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < patternCount; index++) ...[
                    const _TopicPostSkeleton(
                      nameWidthFactor: 0.3,
                      lineWidths: [0.92, 0.72, 0.48],
                    ),
                    Divider(height: 1, color: divider),
                    const _TopicPostSkeleton(
                      nameWidthFactor: 0.22,
                      lineWidths: [0.72, 0.92, 0.3],
                    ),
                    Divider(height: 1, color: divider),
                    const Opacity(
                      opacity: 0.72,
                      child: _TopicPostSkeleton(
                        nameWidthFactor: 0.3,
                        lineWidths: [0.92, 0.48],
                        showFooter: false,
                      ),
                    ),
                    Divider(height: 1, color: divider),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopicPostSkeleton extends StatelessWidget {
  const _TopicPostSkeleton({
    required this.nameWidthFactor,
    required this.lineWidths,
    this.showFooter = true,
  });

  final double nameWidthFactor;
  final List<double> lineWidths;
  final bool showFooter;

  @override
  Widget build(BuildContext context) {
    final post = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LoadingSkeletonBlock.circle(diameter: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: nameWidthFactor,
                    child: const LoadingSkeletonBlock(height: 10),
                  ),
                ),
              ),
              const LoadingSkeletonBlock(width: 36, height: 7),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 13, bottom: 12),
            child: Column(
              children: [
                for (var index = 0; index < lineWidths.length; index++) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FractionallySizedBox(
                      widthFactor: lineWidths[index],
                      child: const LoadingSkeletonBlock(height: 9),
                    ),
                  ),
                  if (index < lineWidths.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          if (showFooter)
            const Row(
              children: [
                LoadingSkeletonBlock.circle(diameter: 14),
                SizedBox(width: 12),
                LoadingSkeletonBlock.circle(diameter: 14),
                SizedBox(width: 12),
                LoadingSkeletonBlock(width: 42, height: 7),
              ],
            ),
        ],
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: TopicView.minimumPostHeight),
      child: post,
    );
  }
}

class _TopicViewHeader extends StatelessWidget {
  const _TopicViewHeader({
    required this.title,
    required this.siteUrl,
    required this.canReturnToSidebar,
    this.route,
    this.topic,
    this.isConnected = false,
    this.bookmarkBusy = false,
    this.sidebarVisible = false,
    this.onToggleSidebar,
  });

  final String title;
  final String? siteUrl;
  final bool canReturnToSidebar;
  final ContentRoute? route;
  final TopicDetail? topic;
  final bool isConnected;
  final bool bookmarkBusy;
  final bool sidebarVisible;
  final VoidCallback? onToggleSidebar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final topic = this.topic;
    final siteUrl = this.siteUrl;
    final topicFlags = topic == null || siteUrl == null
        ? const <PostFlagType>[]
        : controller.availableTopicFlagTypes(siteUrl, topic);
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        key: const ValueKey('topic-content-header'),
        height: shellHeaderHeight,
        padding: const EdgeInsets.only(left: 8, right: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.shell.divider)),
        ),
        child: Row(
          children: [
            DButton.iconOnly(
              onPressed: () =>
                  controller.handleBack(canReturnToSidebar: canReturnToSidebar),
              icon: const DIcon(DIcons.arrowLeft, size: 20),
              tooltip: 'Back',
              variant: DButtonVariant.flat,
              size: DButtonSize.small,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: topic?.canEdit == true && siteUrl != null
                        ? InlineTopicTitleEditor(
                            key: const ValueKey('topic-header-title'),
                            title: title,
                            siteUrl: siteUrl,
                            style: titleStyle,
                            onSave: (title) => controller.saveTopicTitle(
                              siteUrl: siteUrl,
                              topicId: topic!.id,
                              title: title,
                            ),
                          )
                        : Tooltip(
                            message: title,
                            child: siteUrl == null
                                ? Text(
                                    title,
                                    key: const ValueKey('topic-header-title'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: titleStyle,
                                  )
                                : TopicTitle(
                                    title,
                                    key: const ValueKey('topic-header-title'),
                                    siteUrl: siteUrl,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: titleStyle,
                                  ),
                          ),
                  ),
                  if (topic != null && siteUrl != null) ...[
                    const SizedBox(width: 4),
                    TopicStatusButton(
                      siteUrl: siteUrl,
                      topic: topic,
                      topicFlags: topicFlags,
                    ),
                  ],
                ],
              ),
            ),
            if (topic != null && siteUrl != null) ...[
              const SizedBox(width: 8),
              TopicShareButton(siteUrl: siteUrl, topic: topic, route: route),
            ],
            if (topic != null &&
                siteUrl != null &&
                controller.currentInstance?.user != null) ...[
              const SizedBox(width: 8),
              TopicBookmarkButton(
                siteUrl: siteUrl,
                topic: topic,
                busy: bookmarkBusy,
              ),
            ],
            if (topic != null && siteUrl != null && isConnected) ...[
              SizedBox(width: controller.currentInstance?.user != null ? 4 : 8),
              TopicNotificationLevelButton(siteUrl: siteUrl, topic: topic),
            ],
            if (onToggleSidebar case final onPressed?) ...[
              const SizedBox(width: 4),
              _TopicSidebarToggle(
                showSidebar: !sidebarVisible,
                onPressed: onPressed,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopicSidebarPanel extends StatelessWidget {
  const _TopicSidebarPanel({
    required this.siteUrl,
    required this.topic,
    required this.recommendations,
    required this.loading,
    required this.selected,
    required this.onSelected,
    this.onCollapsed,
    required this.route,
    required this.canReply,
    required this.registry,
    this.width = dockedWidth,
  }) : assert(recommendations == null || siteUrl != null);

  static const double dockedWidth = 344;
  static const double minimumPostWidth = 640;
  static const double minimumPinnedViewportWidth =
      dockedWidth + minimumPostWidth;

  final String? siteUrl;
  final TopicDetail? topic;
  final TopicRecommendations? recommendations;
  final bool loading;
  final TopicRecommendationSourceId selected;
  final ValueChanged<TopicRecommendationSourceId> onSelected;
  final VoidCallback? onCollapsed;
  final ContentRoute? route;
  final bool canReply;
  final PluginRegistry registry;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const ValueKey('topic-sidebar-panel'),
      width: width,
      child: Padding(
        key: const ValueKey('topic-sidebar-surface'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('topic-sidebar-scroll-view'),
                primary: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopicSidebarActions(
                      siteUrl: siteUrl,
                      topic: topic,
                      canReply: canReply,
                      registry: registry,
                      onCollapsed: onCollapsed,
                    ),
                    if (topic case final topic? when siteUrl != null) ...[
                      const SizedBox(height: 12),
                      _TopicPropertiesCard(
                        siteUrl: siteUrl!,
                        topic: topic,
                        route: route,
                        registry: registry,
                      ),
                    ],
                    if (recommendations?.isNotEmpty == true || loading) ...[
                      const SizedBox(height: 12),
                      _TopicSidebarCard(
                        key: const ValueKey('topic-more-topics-card'),
                        child: switch (recommendations) {
                          final recommendations? => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  13,
                                  14,
                                  8,
                                ),
                                child: Text(
                                  'More topics',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              _MoreTopics(
                                key: const ValueKey(
                                  'topic-sidebar-more-topics-list',
                                ),
                                siteUrl: siteUrl!,
                                recommendations: recommendations,
                                selected: selected,
                                onSelected: onSelected,
                                topPadding: 0,
                              ),
                            ],
                          ),
                          null => const _MoreTopicsLoadingSkeleton(),
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicSidebarActions extends StatelessWidget {
  const _TopicSidebarActions({
    required this.siteUrl,
    required this.topic,
    required this.canReply,
    required this.registry,
    this.onCollapsed,
  });

  final String? siteUrl;
  final TopicDetail? topic;
  final bool canReply;
  final PluginRegistry registry;
  final VoidCallback? onCollapsed;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    final topic = this.topic;
    final siteUrl = this.siteUrl;
    final theme = Theme.of(context);
    final secondaryActions = topic == null || siteUrl == null
        ? const <Widget>[]
        : <Widget>[
            if (ShellTitleBar.columnsCarryUserMenu) ...[
              ...registry.shellHeaderActions(
                context,
                surface: PluginHeaderSurface.content,
                compact: MediaQuery.sizeOf(context).width < 768,
                ringColor: theme.shell.panel,
              ),
              UserMenuButton(ringColor: theme.shell.panel),
            ],
          ];
    Widget replyButton() => SizedBox(
      height: DButton.iconOnlyDimensionFor(DButtonSize.small),
      child: DButton(
        key: const ValueKey('topic-reply-button'),
        onPressed: controller.openReply,
        icon: const DIcon(DIcons.reply, size: 18),
        label: const Text('Reply'),
        tooltip: 'Reply to this topic',
        shortcut: const DShortcut(topicReplyShortcut),
        variant: DButtonVariant.primary,
        size: DButtonSize.small,
        alignment: Alignment.centerLeft,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ((topic != null && canReply) || onCollapsed != null)
          Row(
            children: [
              if (topic != null && canReply)
                Expanded(child: replyButton())
              else
                const Spacer(),
              if (onCollapsed case final onPressed?) ...[
                const SizedBox(width: 4),
                _TopicSidebarToggle(showSidebar: false, onPressed: onPressed),
              ],
            ],
          ),
        if (secondaryActions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: secondaryActions),
        ],
      ],
    );
  }
}

class _TopicSidebarToggle extends StatelessWidget {
  const _TopicSidebarToggle({
    required this.showSidebar,
    required this.onPressed,
  });

  final bool showSidebar;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DButton.iconOnly(
    key: const ValueKey('topic-sidebar-toggle'),
    onPressed: onPressed,
    icon: const _TopicSidebarIcon(),
    tooltip: showSidebar ? 'Show topic sidebar' : 'Hide topic sidebar',
    variant: DButtonVariant.flat,
    size: DButtonSize.small,
  );
}

class _TopicSidebarIcon extends StatelessWidget {
  const _TopicSidebarIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? const Color(0xFF000000);
    return SizedBox(
      width: 20,
      height: 18,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            bottom: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1),
              ),
              child: const SizedBox(width: 4),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicPropertiesCard extends StatelessWidget {
  const _TopicPropertiesCard({
    required this.siteUrl,
    required this.topic,
    required this.route,
    required this.registry,
  });

  final String siteUrl;
  final TopicDetail topic;
  final ContentRoute? route;
  final PluginRegistry registry;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    final category = controller.categoryFor(topic.categoryId, siteUrl: siteUrl);
    final propertiesRebuildOn = registry.topicPropertiesRebuildOn(
      context,
      siteUrl,
      topic,
    );

    Widget properties() {
      final pluginSections = registry.topicProperties(context, siteUrl, topic);
      final inlineSections = pluginSections
          .where(
            (section) => section.layout == TopicPropertySectionLayout.inline,
          )
          .toList(growable: false);
      final standaloneSections = pluginSections
          .where(
            (section) =>
                section.layout == TopicPropertySectionLayout.standalone,
          )
          .toList(growable: false);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopicSidebarCard(
            key: const ValueKey('topic-properties-card'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                children: [
                  TopicCategoryMenuAnchor(
                    siteUrl: siteUrl,
                    topicId: topic.id,
                    categoryId: topic.categoryId,
                    enabled: topic.canEdit,
                    builder: (context, openMenu, saving) => TopicPropertyRow(
                      key: const ValueKey('topic-sidebar-category-property'),
                      label: 'Category',
                      child: TopicCategoryValue(
                        valueKey: const ValueKey('topic-sidebar-category'),
                        label: category == null
                            ? route?.subtitle ?? 'Uncategorized'
                            : controller.topicCategoryPathLabel(
                                category,
                                siteUrl: siteUrl,
                              ),
                        color: category == null
                            ? route?.color
                            : Color(category.colorValue),
                        colorKey: const ValueKey(
                          'topic-sidebar-category-color',
                        ),
                        actionKey: const ValueKey(
                          'topic-sidebar-category-action',
                        ),
                        editActionKey: const ValueKey(
                          'topic-sidebar-category-edit-action',
                        ),
                        editIconKey: const ValueKey(
                          'topic-sidebar-category-edit-indicator',
                        ),
                        saving: saving,
                        onNavigate: category == null
                            ? null
                            : () => controller.openCategory(
                                category,
                                siteUrl: siteUrl,
                              ),
                        onEdit: openMenu,
                      ),
                    ),
                  ),
                  TopicTagMenuAnchor(
                    siteUrl: siteUrl,
                    topicId: topic.id,
                    categoryId: topic.categoryId,
                    tags: topic.tags,
                    enabled: topic.canEditTags,
                    builder: (context, openMenu, saving) => TopicPropertyRow(
                      key: const ValueKey('topic-sidebar-tags-property'),
                      label: 'Tags',
                      child: TopicTagsValue(
                        tags: topic.tags,
                        saving: saving,
                        onTagNavigate: (tag) => controller.openTopicTag(
                          tag,
                          siteUrl: siteUrl,
                          privateMessage: topic.privateMessage,
                        ),
                        onEdit: openMenu,
                        tagKey: (tag) =>
                            ValueKey(('topic-sidebar-tag', tag.name)),
                        addKey: const ValueKey('topic-sidebar-add-tag'),
                        addIconKey: const ValueKey(
                          'topic-sidebar-tags-edit-indicator',
                        ),
                      ),
                    ),
                  ),
                  for (final section in inlineSections)
                    TopicPropertyRow(
                      label: section.label,
                      child: section.values.isEmpty
                          ? const _EmptyTopicProperty('None')
                          : Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: section.values,
                            ),
                    ),
                ],
              ),
            ),
          ),
          for (final section in standaloneSections) ...[
            const SizedBox(height: 12),
            _TopicStandalonePropertyCard(section: section),
          ],
        ],
      );
    }

    return propertiesRebuildOn == null
        ? properties()
        : ListenableBuilder(
            listenable: propertiesRebuildOn,
            builder: (context, _) => properties(),
          );
  }
}

class _TopicStandalonePropertyCard extends StatelessWidget {
  const _TopicStandalonePropertyCard({required this.section});

  final TopicPropertySection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _TopicSidebarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 8),
            child: Text(
              section.label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: section.values.isEmpty
                ? const _EmptyTopicProperty('None')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (
                        var index = 0;
                        index < section.values.length;
                        index++
                      ) ...[
                        if (index > 0) const SizedBox(height: 6),
                        section.values[index],
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _TopicSidebarCard extends StatelessWidget {
  const _TopicSidebarCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border.all(color: theme.shell.divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(11), child: child),
    );
  }
}

class _EmptyTopicProperty extends StatelessWidget {
  const _EmptyTopicProperty(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _MoreTopicsLoadingSkeleton extends StatelessWidget {
  const _MoreTopicsLoadingSkeleton();

  static const double _headingHeight = 48;
  static const int _rowCount = 4;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).shell.divider;

    return LoadingSkeleton(
      key: const ValueKey('topic-recommendations-loading-skeleton'),
      semanticsLabel: 'Loading more topics',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            height: _headingHeight,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: LoadingSkeletonBlock(width: 72, height: 10),
              ),
            ),
          ),
          for (var index = 0; index < _rowCount; index++) ...[
            if (index > 0) Divider(height: 1, color: divider),
            _MoreTopicsSkeletonRow(index: index),
          ],
        ],
      ),
    );
  }
}

class _MoreTopicsSkeletonRow extends StatelessWidget {
  const _MoreTopicsSkeletonRow({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final (titleWidth, metadataWidth) = switch (index % 4) {
      0 => (0.78, 0.54),
      1 => (0.62, 0.42),
      2 => (0.88, 0.64),
      _ => (0.7, 0.48),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: TopicListRow.minimumHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FractionallySizedBox(
              widthFactor: titleWidth,
              child: const LoadingSkeletonBlock(height: 11),
            ),
            const SizedBox(height: 8),
            FractionallySizedBox(
              widthFactor: metadataWidth,
              child: const LoadingSkeletonBlock(height: 8),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreTopics extends StatelessWidget {
  const _MoreTopics({
    super.key,
    required this.siteUrl,
    required this.recommendations,
    required this.selected,
    required this.onSelected,
    this.topPadding = 20,
  });

  final String siteUrl;
  final TopicRecommendations recommendations;
  final TopicRecommendationSourceId selected;
  final ValueChanged<TopicRecommendationSourceId> onSelected;
  final double topPadding;

  TopicRecommendationSource _effectiveSelection(
    List<TopicRecommendationSource> available,
  ) {
    for (final source in available) {
      if (source.id == selected) return source;
    }
    return available.first;
  }

  @override
  Widget build(BuildContext context) {
    final available = [
      for (final source in recommendations.sources)
        if (source.topics.isNotEmpty) source,
    ];
    if (available.isEmpty) return const SizedBox.shrink();
    final selection = _effectiveSelection(available);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (available.length > 1)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.shell.divider)),
              ),
              child: Row(
                children: [
                  for (final source in available)
                    Expanded(
                      child: _MoreTopicsTabButton(
                        key: ValueKey(
                          'topic-recommendations-tab-${source.id.value}',
                        ),
                        label: source.label,
                        icon: source.definition.icon,
                        selected: selection.id == source.id,
                        onPressed: () => onSelected(source.id),
                      ),
                    ),
                ],
              ),
            ),
          for (var index = 0; index < selection.topics.length; index++) ...[
            TopicListRow(
              topic: selection.topics[index],
              siteUrl: siteUrl,
              titleStyle: theme.textTheme.titleSmall,
            ),
            if (index < selection.topics.length - 1)
              Divider(height: 1, color: theme.shell.divider),
          ],
        ],
      ),
    );
  }
}

class _MoreTopicsTabButton extends StatelessWidget {
  const _MoreTopicsTabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final DIconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon case final icon?) ...[
                DIcon(icon, size: 13, color: color),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicPostItem extends StatefulWidget {
  const _TopicPostItem({
    super.key,
    required this.postId,
    required this.retainedMinimumHeight,
    required this.day,
    required this.timeGapDays,
    required this.hideDay,
    required this.onDayTap,
    required this.gapBefore,
    required this.gapAfter,
    required this.expandGapBefore,
    required this.expandGapAfter,
    required this.onAttach,
    required this.onDetach,
    required this.child,
  });

  final int postId;
  final double? retainedMinimumHeight;
  final DateTime? day;
  final int? timeGapDays;
  final bool hideDay;
  final VoidCallback? onDayTap;
  final List<int> gapBefore;
  final List<int> gapAfter;
  final Future<void> Function() expandGapBefore;
  final Future<void> Function() expandGapAfter;
  final void Function(int postId, BuildContext context) onAttach;
  final void Function(int postId, BuildContext context) onDetach;
  final Widget child;

  @override
  State<_TopicPostItem> createState() => _TopicPostItemState();
}

class _TopicPostItemState extends State<_TopicPostItem> {
  double? _retainedMinimumHeight;
  bool _releaseScheduled = false;

  @override
  void initState() {
    super.initState();
    _retainedMinimumHeight = widget.retainedMinimumHeight;
    widget.onAttach(widget.postId, context);
  }

  @override
  void didUpdateWidget(_TopicPostItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId == widget.postId) {
      if (oldWidget.retainedMinimumHeight != widget.retainedMinimumHeight) {
        _retainedMinimumHeight = widget.retainedMinimumHeight;
        _releaseScheduled = false;
      }
      return;
    }
    oldWidget.onDetach(oldWidget.postId, context);
    _retainedMinimumHeight = widget.retainedMinimumHeight;
    _releaseScheduled = false;
    widget.onAttach(widget.postId, context);
  }

  @override
  void dispose() {
    widget.onDetach(widget.postId, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.gapBefore.isNotEmpty)
          _PostGap(
            key: const ValueKey('post-gap-before'),
            count: widget.gapBefore.length,
            onExpand: widget.expandGapBefore,
          ),
        if (day != null)
          IgnorePointer(
            ignoring: widget.hideDay,
            child: Opacity(
              opacity: widget.hideDay ? 0 : 1,
              child: StreamDaySeparator(
                key: ValueKey(('topic-day', day)),
                day: day,
                onTap: widget.onDayTap!,
              ),
            ),
          ),
        if (widget.timeGapDays case final daysSince?)
          TimeGapNotice(
            key: ValueKey(('topic-time-gap', widget.postId)),
            daysSince: daysSince,
          ),
        widget.child,
        if (widget.gapAfter.isNotEmpty)
          _PostGap(
            key: const ValueKey('post-gap-after'),
            count: widget.gapAfter.length,
            onExpand: widget.expandGapAfter,
          ),
      ],
    );
    final retainedMinimumHeight = _retainedMinimumHeight;
    return _RetainedMinimumHeight(
      minimumHeight: retainedMinimumHeight ?? 0,
      onNaturalHeightRestored: retainedMinimumHeight == null
          ? null
          : _releaseRetainedMinimumHeight,
      child: child,
    );
  }

  void _releaseRetainedMinimumHeight() {
    if (_releaseScheduled) return;
    _releaseScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _retainedMinimumHeight = null;
        _releaseScheduled = false;
      });
    });
  }
}

class _PostGap extends StatefulWidget {
  const _PostGap({super.key, required this.count, required this.onExpand});

  final int count;
  final Future<void> Function() onExpand;

  @override
  State<_PostGap> createState() => _PostGapState();
}

class _PostGapState extends State<_PostGap> {
  bool _loading = false;

  String get _label => widget.count == 1
      ? 'View 1 hidden reply'
      : 'View ${widget.count} hidden replies';

  Future<void> _expand() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onExpand();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _loading ? 'Loading…' : _label;
    final left = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 58.0;

    return Semantics(
      button: true,
      label: label,
      onTap: _loading ? null : _expand,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: _loading ? null : _expand,
            child: Padding(
              padding: EdgeInsets.fromLTRB(left, 8, 16, 12),
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EarlierPostsRow extends StatelessWidget {
  const _EarlierPostsRow({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) => loading
      ? const _TopicPaginationSkeleton(
          key: ValueKey('topic-loading-earlier-skeleton'),
          semanticsLabel: 'Loading earlier posts',
          nameWidthFactor: 0.22,
          lineWidthFactor: 0.72,
        )
      : const SizedBox(height: 68);
}

class _StoredPost extends StatelessWidget {
  const _StoredPost({
    required this.siteUrl,
    required this.topic,
    required this.postId,
    required this.summary,
    required this.summaryLoading,
    required this.readTimeWordCount,
  });

  final String siteUrl;
  final TopicDetail topic;
  final int postId;
  final bool summary;
  final bool summaryLoading;
  final int readTimeWordCount;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Post?>(
      valueListenable: ShellScope.read(context).postRef(siteUrl, postId),
      builder: (context, post, _) {
        // Gone for good — deleted outright rather than soft-deleted — in the
        // frame before the stream that named it is rewritten without it.
        if (post == null) return const SizedBox.shrink();
        final registry =
            PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty;
        if (post.isSmallAction || registry.isSmallAction(post)) {
          return SmallActionTile(post: post, siteUrl: siteUrl);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PostTile(siteUrl: siteUrl, topic: topic, post: post),
            if (post.postNumber == 1)
              _TopicMap(
                siteUrl: siteUrl,
                topic: topic,
                summary: summary,
                summaryLoading: summaryLoading,
                readTimeWordCount: readTimeWordCount,
              ),
          ],
        );
      },
    );
  }
}

class _PostTile extends StatefulWidget {
  const _PostTile({
    required this.siteUrl,
    required this.topic,
    required this.post,
  });

  final String siteUrl;
  final TopicDetail topic;
  final Post post;

  @override
  State<_PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<_PostTile> {
  bool _linksExpanded = false;

  @override
  Widget build(BuildContext context) =>
      ShellSelector<({bool enabled, bool selected, bool busy})>(
        select: (controller) => (
          enabled: controller.topicPostSelectionEnabled(
            widget.siteUrl,
            widget.topic.id,
          ),
          selected: controller
              .selectedTopicPostIds(widget.siteUrl, widget.topic.id)
              .contains(widget.post.id),
          busy: controller.topicPostSelectionWriteInFlight(
            widget.siteUrl,
            widget.topic.id,
          ),
        ),
        builder: (context, selection, _) => _build(context, selection),
      );

  Widget _build(
    BuildContext context,
    ({bool enabled, bool selected, bool busy}) selection,
  ) {
    final theme = Theme.of(context);
    final post = widget.post;

    final tile = ColoredBox(
      color: post.isDeleted
          ? theme.colorScheme.error.withValues(alpha: 0.07)
          : Colors.transparent,
      child: PostActions(
        siteUrl: widget.siteUrl,
        post: post,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (selection.enabled) ...[
                    Checkbox(
                      key: ValueKey('topic-post-select-${post.id}'),
                      value: selection.selected,
                      onChanged: selection.busy
                          ? null
                          : (_) => ShellScope.read(context)
                                .toggleTopicPostSelected(
                                  widget.siteUrl,
                                  widget.topic.id,
                                  post.id,
                                ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  UserCardTarget(
                    username: post.username,
                    siteUrl: widget.siteUrl,
                    child: ClipOval(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: AvatarImage(
                          url: post.avatarUrl,
                          size: 32,
                          fallback: ColoredBox(
                            color: theme.shell.floating,
                            child: Center(
                              child: Text(
                                post.username.isEmpty
                                    ? '?'
                                    : post.username.characters.first
                                          .toUpperCase(),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: UserCardTarget(
                            username: post.username,
                            siteUrl: widget.siteUrl,
                            child: Text(
                              post.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        UserStatusMessage(
                          siteUrl: widget.siteUrl,
                          userId: post.userId,
                          status: post.userStatus,
                          size: 15,
                          leadingGap: 6,
                        ),
                        if (post.isStaff) ...[
                          const SizedBox(width: 6),
                          _Tag(
                            label: 'staff',
                            color: theme.colorScheme.primary,
                          ),
                        ] else if (post.userTitle case final title?) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                        if (post.isDeleted) ...[
                          const SizedBox(width: 6),
                          _Tag(
                            label: 'deleted',
                            color: theme.colorScheme.error,
                          ),
                        ],
                        if (post.wiki) ...[
                          const SizedBox(width: 6),
                          _Tag(label: 'wiki', color: theme.colorScheme.primary),
                        ],
                        if (post.locked) ...[
                          const SizedBox(width: 6),
                          _Tag(
                            label: 'locked',
                            color: theme.colorScheme.secondary,
                          ),
                        ],
                        if (post.hidden) ...[
                          const SizedBox(width: 6),
                          _Tag(label: 'hidden', color: theme.colorScheme.error),
                        ],
                        if (post.isModeratorAction) ...[
                          const SizedBox(width: 6),
                          _Tag(
                            label: 'moderator',
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (post.isWhisper) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'This post is a private whisper',
                      child: DIcon(
                        DIcons.farEyeSlash,
                        size: 14,
                        color: theme.discourse.whisper,
                      ),
                    ),
                    if (post.createdAt != null) const SizedBox(width: 8),
                  ],
                  if (post.editCount > 0) ...[
                    PostRevisionIndicator(post: post),
                    if (post.createdAt != null) const SizedBox(width: 4),
                  ],
                  if (post.createdAt case final createdAt?)
                    Text(
                      relativeTime(createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              if (post.notice case final notice?) ...[
                const SizedBox(height: 10),
                _PostNoticeBanner(
                  siteUrl: widget.siteUrl,
                  post: post,
                  notice: notice,
                ),
              ],
              const SizedBox(height: 10),
              PostTextSelection(
                post: post,
                topicId: widget.topic.id,
                child: CookedHtml(
                  html: post.cooked,
                  textStyle: post.isWhisper
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: theme.discourse.whisper,
                          fontStyle: FontStyle.italic,
                          height: DiscourseTypography.lineHeightCooked,
                        )
                      : theme.textTheme.bodyMedium?.copyWith(
                          height: DiscourseTypography.lineHeightCooked,
                        ),
                  siteUrl: widget.siteUrl,
                  post: post,
                  containingTopic: PluginContainingTopic(
                    id: widget.topic.id,
                    slug:
                        ShellScope.read(context).currentContent?.slug ??
                        'topic',
                    archived: widget.topic.archived,
                  ),
                  mentionedUserStatuses: post.mentionedUserStatuses,
                ),
              ),
              ...(PluginScope.maybeOf(context)?.registry ??
                      PluginRegistry.empty)
                  .postDecorations(context, widget.siteUrl, widget.topic, post),
              PostFooter(siteUrl: widget.siteUrl, post: post),
              if (post.inboundLinks.isNotEmpty)
                _PostInboundLinks(
                  siteUrl: widget.siteUrl,
                  links: post.inboundLinks,
                  expanded: _linksExpanded,
                  onExpand: () => setState(() => _linksExpanded = true),
                ),
            ],
          ),
        ),
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: TopicView.minimumPostHeight),
      child: tile,
    );
  }
}

class _PostNoticeBanner extends StatelessWidget {
  const _PostNoticeBanner({
    required this.siteUrl,
    required this.post,
    required this.notice,
  });

  final String siteUrl;
  final Post post;
  final PostNotice notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cooked = notice.cooked;
    final label = switch (notice.type) {
      'new_user' => 'This is this user’s first post.',
      'returning_user' => 'This user is returning after a long absence.',
      _ => notice.raw ?? 'Staff notice',
    };
    return Container(
      key: ValueKey('post-notice-${post.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DIcon(
            DIcons.user,
            size: 16,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: cooked == null || cooked.isEmpty
                ? Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  )
                : CookedHtml(
                    html: cooked,
                    siteUrl: siteUrl,
                    post: post,
                    textStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PostInboundLinks extends StatelessWidget {
  const _PostInboundLinks({
    required this.siteUrl,
    required this.links,
    required this.expanded,
    required this.onExpand,
  });

  static const int _collapsedLimit = 5;

  final String siteUrl;
  final List<PostInboundLink> links;
  final bool expanded;
  final VoidCallback onExpand;

  List<PostInboundLink> get _uniqueLinks {
    final titles = <String>{};
    return [
      for (final link in links)
        if (titles.add(link.title)) link,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unique = _uniqueLinks;
    final displayed = expanded ? unique : unique.take(_collapsedLimit).toList();
    final remaining = unique.length - displayed.length;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: theme.shell.divider),
          const SizedBox(height: 10),
          for (final link in displayed)
            InlineAction.link(
              semanticLabel: link.title,
              excludeChildSemantics: true,
              borderRadius: BorderRadius.circular(4),
              onTap: () => unawaited(
                openLink(
                  context,
                  link.url,
                  title: link.title,
                  siteUrl: siteUrl,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    DIcon(
                      DIcons.link,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SiteEmojiText.plain(
                        link.title,
                        siteUrl: siteUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (remaining > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onExpand,
                child: Text(
                  '$remaining more ${remaining == 1 ? 'link' : 'links'}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopicMap extends StatelessWidget {
  const _TopicMap({
    required this.siteUrl,
    required this.topic,
    required this.summary,
    required this.summaryLoading,
    required this.readTimeWordCount,
  });

  static const int _minimumPostsForMapDetails = 3;
  static const int _minimumLikes = 5;
  static const int _minimumParticipantCount = 5;
  static const int _maximumVisibleParticipants = 5;
  static const int _minimumReadMinutes = 3;

  final String siteUrl;
  final TopicDetail topic;
  final bool summary;
  final bool summaryLoading;
  final int readTimeWordCount;

  int? get _readTimeMinutes {
    final wordMinutes = topic.wordCount / readTimeWordCount;
    final postMinutes = topic.postsCount * 4 / 60;
    final minutes = (wordMinutes > postMinutes ? wordMinutes : postMinutes)
        .ceil();
    return minutes > _minimumReadMinutes ? minutes : null;
  }

  bool get _showLikes =>
      topic.likeCount > _minimumLikes &&
      topic.postsCount > _minimumPostsForMapDetails;

  bool get _showUsers => topic.participantCount > _minimumParticipantCount;

  Future<void> _toggleSummary(BuildContext context) async {
    final error = await ShellScope.read(context).toggleTopicSummary();
    if (!context.mounted || error == null) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(error)));
  }

  List<Widget> _stats(BuildContext context) => [
    _TopicMapStat(
      key: const ValueKey('topic-map-views'),
      value: topic.views < 1 ? 1 : topic.views,
      label: topic.views <= 1 ? 'view' : 'views',
      tooltip: 'Topic views',
    ),
    if (topic.isNestedView)
      _TopicMapStat(
        key: const ValueKey('topic-map-replies'),
        value: topic.replyCount,
        label: topic.replyCount == 1 ? 'reply' : 'replies',
        tooltip: 'Replies',
      ),
    if (_showLikes)
      _TopicMapStat(
        key: const ValueKey('topic-map-likes'),
        value: topic.likeCount,
        label: topic.likeCount == 1 ? 'like' : 'likes',
        tooltip: 'Likes in this topic',
      ),
    if (topic.links.isNotEmpty)
      _TopicMapStat(
        key: const ValueKey('topic-map-links'),
        value: topic.links.length,
        label: topic.links.length == 1 ? 'link' : 'links',
        tooltip: 'Links in this topic',
        menuChildren: [
          for (final link in topic.links)
            MenuItemButton(
              leadingIcon: const DIcon(DIcons.link, size: 14),
              onPressed: () => unawaited(
                openLink(
                  context,
                  link.url,
                  title: link.title,
                  siteUrl: siteUrl,
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  link.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    if (_showUsers)
      _TopicMapStat(
        key: const ValueKey('topic-map-users'),
        value: topic.participantCount,
        label: topic.participantCount == 1 ? 'user' : 'users',
        tooltip: 'Participants',
        menuChildren: [
          for (final participant in topic.participants)
            MenuItemButton(
              leadingIcon: _TopicParticipantAvatar(
                participant: participant,
                siteUrl: siteUrl,
                size: 24,
                interactive: false,
              ),
              onPressed: () => unawaited(
                showUserCard(
                  context: context,
                  username: participant.username,
                  siteUrl: siteUrl,
                ),
              ),
              child: Text(participant.displayName),
            ),
        ],
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readTime = _readTimeMinutes;
    final pluginActions =
        (PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty)
            .topicMapActions(context, siteUrl, topic);

    return Container(
      key: const ValueKey('topic-map'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.shell.divider)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showAvatars =
              constraints.maxWidth >= 520 &&
              topic.postsCount >= _minimumPostsForMapDetails &&
              topic.participants.length >= 2;
          final details = Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ..._stats(context),
              if (showAvatars)
                for (final participant in topic.participants.take(
                  _maximumVisibleParticipants,
                ))
                  _TopicParticipantAvatar(
                    participant: participant,
                    siteUrl: siteUrl,
                  ),
            ],
          );
          final actions = Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (readTime != null) _TopicReadTime(minutes: readTime),
              if (topic.hasSummary && !pluginActions.replacesSummary)
                DButton(
                  key: const ValueKey('topic-summary-button'),
                  label: Text(summary ? 'Show all' : 'Summarize'),
                  onPressed: () => unawaited(_toggleSummary(context)),
                  icon: DIcon(
                    summary ? DIcons.list : DIcons.layerGroup,
                    size: 14,
                  ),
                  loading: summaryLoading,
                ),
              ...pluginActions.actions,
            ],
          );

          if (constraints.maxWidth < 560) {
            return Wrap(
              spacing: 16,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [details, actions],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              if (actions.children.isNotEmpty) ...[
                const SizedBox(width: 16),
                actions,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TopicMapStat extends StatelessWidget {
  const _TopicMapStat({
    super.key,
    required this.value,
    required this.label,
    required this.tooltip,
    this.menuChildren = const [],
  });

  final int value;
  final String label;
  final String tooltip;
  final List<Widget> menuChildren;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              height: 1.1,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.1,
            ),
          ),
        ],
      ),
    );

    if (menuChildren.isEmpty) {
      return Tooltip(message: tooltip, child: content);
    }
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(theme.shell.floating),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        maximumSize: const WidgetStatePropertyAll(Size(380, 440)),
      ),
      menuChildren: menuChildren,
      builder: (context, menu, child) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: menu.open,
          child: child,
        ),
      ),
      child: content,
    );
  }
}

class _TopicParticipantAvatar extends StatelessWidget {
  const _TopicParticipantAvatar({
    required this.participant,
    required this.siteUrl,
    this.size = 32,
    this.interactive = true,
  });

  final TopicParticipant participant;
  final String siteUrl;
  final double size;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatar = Tooltip(
      message: '@${participant.username}',
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: AvatarImage(
            url: participant.avatarUrl,
            size: size,
            fallback: ColoredBox(
              color: theme.shell.floating,
              child: Center(
                child: Text(
                  participant.username.characters.first.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return interactive
        ? UserCardTarget(
            username: participant.username,
            siteUrl: siteUrl,
            child: avatar,
          )
        : avatar;
  }
}

class _TopicReadTime extends StatelessWidget {
  const _TopicReadTime({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('$minutes min', style: theme.textTheme.bodyMedium),
        Text(
          'read',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _RetainedMinimumHeight extends SingleChildRenderObjectWidget {
  const _RetainedMinimumHeight({
    required this.minimumHeight,
    required this.onNaturalHeightRestored,
    required super.child,
  });

  final double minimumHeight;
  final VoidCallback? onNaturalHeightRestored;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRetainedMinimumHeight(
        minimumHeight: minimumHeight,
        onNaturalHeightRestored: onNaturalHeightRestored,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRetainedMinimumHeight renderObject,
  ) {
    renderObject
      ..minimumHeight = minimumHeight
      ..onNaturalHeightRestored = onNaturalHeightRestored;
  }
}

class _RenderRetainedMinimumHeight extends RenderProxyBox {
  _RenderRetainedMinimumHeight({
    required this._minimumHeight,
    required this._onNaturalHeightRestored,
  });

  double _minimumHeight;
  VoidCallback? _onNaturalHeightRestored;

  set minimumHeight(double value) {
    if (value == _minimumHeight) return;
    _minimumHeight = value;
    markNeedsLayout();
  }

  set onNaturalHeightRestored(VoidCallback? value) {
    _onNaturalHeightRestored = value;
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size(0, _minimumHeight));
      return;
    }
    child.layout(constraints.copyWith(minHeight: 0), parentUsesSize: true);
    final childSize = child.size;
    size = constraints.constrain(
      Size(childSize.width, math.max(childSize.height, _minimumHeight)),
    );
    if (_onNaturalHeightRestored case final callback?
        when childSize.height >= _minimumHeight - 0.5) {
      callback();
    }
  }
}

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

class _LoadingPostsRow extends StatelessWidget {
  const _LoadingPostsRow();

  @override
  Widget build(BuildContext context) => const _TopicPaginationSkeleton(
    key: ValueKey('topic-loading-more-skeleton'),
    semanticsLabel: 'Loading more posts',
    nameWidthFactor: 0.3,
    lineWidthFactor: 0.92,
  );
}

class _TopicPaginationSkeleton extends StatelessWidget {
  const _TopicPaginationSkeleton({
    super.key,
    required this.semanticsLabel,
    required this.nameWidthFactor,
    required this.lineWidthFactor,
  });

  final String semanticsLabel;
  final double nameWidthFactor;
  final double lineWidthFactor;

  @override
  Widget build(BuildContext context) => LoadingSkeleton(
    semanticsLabel: semanticsLabel,
    child: _TopicPostSkeleton(
      nameWidthFactor: nameWidthFactor,
      lineWidths: [lineWidthFactor],
      showFooter: false,
    ),
  );
}
