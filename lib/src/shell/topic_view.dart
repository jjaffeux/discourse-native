import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../data/topic_recommendations_panel_store.dart';
import '../data/topic_recommendations_tab_store.dart';
import '../foundation/calendar_day.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../plugins/site_plugin.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'cooked_html.dart';
import 'loading_skeleton.dart';
import 'post_actions.dart';
import 'post_footer.dart';
import 'post_text_selection.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'small_action.dart';
import 'topic_list_view.dart';
import 'user_card.dart';

/// A topic and its posts.
class TopicView extends StatefulWidget {
  const TopicView({
    super.key,
    this.showRecommendationsPanel = false,
    this.recommendationsPanelStore = const TopicRecommendationsPanelStore(),
    this.recommendationsTabStore = const TopicRecommendationsTabStore(),
  });

  /// Start fetching the next batch about a screen before either end.
  static const double _loadPostsThreshold = 900;

  /// Whether recommendations are docked beside the posts instead of below
  /// them. Narrow layouts leave this false so the reading column stays usable.
  final bool showRecommendationsPanel;

  final TopicRecommendationsPanelStore recommendationsPanelStore;

  final TopicRecommendationsTabStore recommendationsTabStore;

  @override
  State<TopicView> createState() => _TopicViewState();
}

typedef _TopicDayStart = ({DateTime day, int postIndex});

class _TopicViewState extends State<TopicView> {
  static const Duration _readInterval = Duration(milliseconds: 500);

  ScrollController? _scroll;
  ListController? _list;
  (String, int)? _topicIdentity;
  String? _tabId;
  ShellController? _controller;
  Object? _loadMoreToken;
  (String, int, int)? _loadMoreTarget;
  Object? _loadEarlierToken;
  (String, int, int)? _loadEarlierTarget;
  Object? _anchorRestoreToken;
  List<int> _laidOutPostIds = const [];
  bool _laidOutHasHeader = false;
  bool _restored = false;
  bool _restoring = false;
  bool _lookScheduled = false;
  bool _saveAnchorAfterLook = false;
  int? _savedAnchorPostNumber;
  String? _recommendationsSiteUrl;
  bool _recommendationsPanelCollapsed = false;
  int _recommendationsPanelRestoreGeneration = 0;
  TopicRecommendationsTab _recommendationsTab =
      TopicRecommendationsTab.suggested;
  int _recommendationsTabRestoreGeneration = 0;
  List<_TopicDayStart> _laidOutDayStarts = const [];
  DateTime? _floatingDay;
  double _floatingDayOffset = 0;
  Object? _dayJumpToken;
  Timer? _readTimer;
  ({String siteUrl, int topicId, int postNumber, bool caughtUp})? _seen;

  void _syncControllers(
    ShellController controller,
    (String, int) topicIdentity,
  ) {
    if (_topicIdentity == topicIdentity &&
        _tabId == controller.activeTabId &&
        identical(_controller, controller)) {
      return;
    }

    _creditReaderNow();
    _disposeControllers();
    if (!identical(_controller, controller)) {
      // This viewport stops feeding the outgoing shell's anchors here, so a
      // save still waiting out its debounce window is written rather than
      // left behind on a controller no view drives any more.
      _controller?.flushAnchorPersist();
    }
    _controller = controller;
    _topicIdentity = topicIdentity;
    _tabId = controller.activeTabId;
    _loadMoreToken = null;
    _loadMoreTarget = null;
    _loadEarlierToken = null;
    _loadEarlierTarget = null;
    _anchorRestoreToken = null;
    _laidOutPostIds = const [];
    _laidOutHasHeader = false;
    _restored = false;
    _restoring = false;
    _lookScheduled = false;
    _saveAnchorAfterLook = false;
    _savedAnchorPostNumber = null;
    _laidOutDayStarts = const [];
    _floatingDay = null;
    _floatingDayOffset = 0;
    _dayJumpToken = null;
    _seen = null;
    _scroll = ScrollController();
    _list = ListController()..addListener(_noteExtentsChanged);
    _noteExtentsChanged();
  }

  void _restoreInitialPost(
    ShellController controller,
    _TopicViewSnapshot snapshot,
  ) {
    if (_restored) return;

    final index = snapshot.initialPostIndex;
    if (index == null) {
      // A numbered route may briefly be drawing cached posts that do not
      // include its target. Leave restoration armed for the around-post
      // response. An unnumbered topic genuinely belongs at the beginning.
      final topicId = snapshot.topicId;
      if (topicId == null ||
          controller.topicScrollPostNumber(topicId) == null) {
        _restored = true;
      }
      return;
    }
    _restored = true;
    if (index <= 0 &&
        controller.topicScrollPostOffset(snapshot.topicId!) == 0) {
      return;
    }
    final identity = (snapshot.siteUrl!, snapshot.topicId!);
    _restoring = true;

    void jumpToTarget() {
      if (!_isCurrent(controller, identity)) return;
      final current = _TopicViewSnapshot.from(controller);
      final currentIndex = current.initialPostIndex;
      if (currentIndex != null) {
        final postIndex = currentIndex - (current.hasEarlier ? 1 : 0);
        final target = controller.topicScrollPostNumber(snapshot.topicId!);
        final post = postIndex >= 0 && postIndex < current.postIds.length
            ? controller.store.read<Post>(
                snapshot.siteUrl!,
                current.postIds[postIndex],
              )
            : null;
        _jumpTo(
          currentIndex,
          // A deleted anchor falls forward to the next post. Its old pixel
          // offset belongs to the deleted post and must not be applied there.
          viewportOffset: post?.postNumber == target
              ? controller.topicScrollPostOffset(snapshot.topicId!)
              : 0,
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jumpToTarget();
      // The first jump uses estimates for posts that have not been laid out.
      // Repeat once their real heights are known so the requested post lands
      // at the top rather than merely somewhere near it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isCurrent(controller, identity)) return;
        jumpToTarget();
        _restoring = false;
        _scheduleLook();
        _scheduleLoadEarlier(controller, _TopicViewSnapshot.from(controller));
      });
    });
  }

  void _jumpTo(int index, {double viewportOffset = 0}) {
    final list = _list;
    final scroll = _scroll;
    if (list == null || scroll == null) return;
    if (!list.isAttached || !scroll.hasClients) return;
    // `separated` interleaves a separator after every logical item, and the
    // ListController addresses that expanded child list.
    list.jumpToItem(index: index * 2, scrollController: scroll, alignment: 0);
    if (viewportOffset == 0 || !scroll.hasClients) return;
    final position = scroll.position;
    scroll.jumpTo(
      (position.pixels - viewportOffset)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
    );
  }

  bool _isCurrent(ShellController controller, (String, int) topicIdentity) =>
      mounted &&
      _topicIdentity == topicIdentity &&
      _tabId == controller.activeTabId &&
      controller.currentInstance?.url == topicIdentity.$1 &&
      controller.currentTopic?.id == topicIdentity.$2;

  void _disposeControllers() {
    final scroll = _scroll;
    final list = _list;
    if (scroll == null && list == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scroll?.dispose();
      list?.dispose();
    });
  }

  @override
  void dispose() {
    _recommendationsPanelRestoreGeneration++;
    _recommendationsTabRestoreGeneration++;
    _dayJumpToken = null;
    _creditReaderNow();
    // Nothing can move this topic's anchor once its viewport is gone, so a
    // save still waiting out its debounce window is written now.
    _controller?.flushAnchorPersist();
    _disposeControllers();
    super.dispose();
  }

  void _syncRecommendationsSite(String siteUrl) {
    if (_recommendationsSiteUrl == siteUrl) return;
    _recommendationsSiteUrl = siteUrl;
    _recommendationsPanelCollapsed = false;
    _recommendationsTab = TopicRecommendationsTab.suggested;
    unawaited(_restoreRecommendationsPanel(siteUrl));
    unawaited(_restoreRecommendationsTab(siteUrl));
  }

  Future<void> _restoreRecommendationsPanel(String siteUrl) async {
    final generation = ++_recommendationsPanelRestoreGeneration;
    final collapsed = await widget.recommendationsPanelStore.read(
      siteUrl: siteUrl,
    );
    if (!mounted ||
        generation != _recommendationsPanelRestoreGeneration ||
        _recommendationsSiteUrl != siteUrl) {
      return;
    }
    if (collapsed != _recommendationsPanelCollapsed) {
      setState(() => _recommendationsPanelCollapsed = collapsed);
    }
  }

  Future<void> _restoreRecommendationsTab(String siteUrl) async {
    final generation = ++_recommendationsTabRestoreGeneration;
    final tab = await widget.recommendationsTabStore.read(siteUrl: siteUrl);
    if (!mounted ||
        generation != _recommendationsTabRestoreGeneration ||
        _recommendationsSiteUrl != siteUrl) {
      return;
    }
    if (tab != _recommendationsTab) {
      setState(() => _recommendationsTab = tab);
    }
  }

  void _setRecommendationsPanelCollapsed(bool collapsed) {
    final siteUrl = _recommendationsSiteUrl;
    if (siteUrl == null || collapsed == _recommendationsPanelCollapsed) return;
    _recommendationsPanelRestoreGeneration++;
    setState(() => _recommendationsPanelCollapsed = collapsed);
    unawaited(
      widget.recommendationsPanelStore.write(
        siteUrl: siteUrl,
        collapsed: collapsed,
      ),
    );
  }

  void _setRecommendationsTab(TopicRecommendationsTab tab) {
    final siteUrl = _recommendationsSiteUrl;
    if (siteUrl == null || tab == _recommendationsTab) return;
    _recommendationsTabRestoreGeneration++;
    setState(() => _recommendationsTab = tab);
    unawaited(widget.recommendationsTabStore.write(siteUrl: siteUrl, tab: tab));
  }

  /// Measures the viewport after layout. This also covers short topics that
  /// never produce a scroll notification at all.
  void _scheduleLook({bool saveAnchor = false}) {
    _saveAnchorAfterLook = _saveAnchorAfterLook || saveAnchor;
    if (_lookScheduled) return;
    _lookScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lookScheduled = false;
      final saveAnchor = _saveAnchorAfterLook;
      _saveAnchorAfterLook = false;
      final controller = _controller;
      final identity = _topicIdentity;
      if (controller == null || identity == null) return;
      if (!_isCurrent(controller, identity)) return;
      final snapshot = _TopicViewSnapshot.from(controller);
      _syncFloatingDay(snapshot);
      _noteWhatIsOnScreen(controller, snapshot, saveAnchor: saveAnchor);
    });
  }

  /// Pins the last date boundary that has passed the top of the viewport.
  ///
  /// Core chat gives every date marker a sticky span that lasts until the next
  /// marker. Topic rows must keep their post-based indices for paging and
  /// restoration, so the equivalent here is one overlay driven by those same
  /// two boundaries. As the next date approaches it pushes the old one out.
  void _syncFloatingDay(_TopicViewSnapshot snapshot) {
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

    var candidateIndex = -1;
    for (var index = 0; index < _laidOutDayStarts.length; index++) {
      if (_laidOutDayStarts[index].postIndex > firstVisiblePostIndex) break;
      candidateIndex = index;
    }
    if (candidateIndex < 0) {
      _setFloatingDay(null, 0);
      return;
    }

    double topOf(_TopicDayStart start) {
      final childIndex = (start.postIndex + leading) * 2;
      return _offsetBeforeChild(list, childIndex) - scroll.position.pixels;
    }

    // The first visible post can itself begin a day while its marker is still
    // below the viewport edge. Until it crosses, the preceding day remains the
    // sticky one.
    if (topOf(_laidOutDayStarts[candidateIndex]) >= 0) candidateIndex--;
    if (candidateIndex < 0) {
      _setFloatingDay(null, 0);
      return;
    }

    final current = _laidOutDayStarts[candidateIndex];
    final nextIndex = candidateIndex + 1;
    var offset = 0.0;
    if (nextIndex < _laidOutDayStarts.length) {
      final nextTop = topOf(_laidOutDayStarts[nextIndex]);
      if (nextTop < _TopicDaySeparator.height) {
        offset = nextTop - _TopicDaySeparator.height;
      }
    }
    _setFloatingDay(current.day, offset);
  }

  void _setFloatingDay(DateTime? day, double offset) {
    if (_floatingDay == day && (_floatingDayOffset - offset).abs() < 0.1) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _floatingDay = day;
      _floatingDayOffset = offset;
    });
  }

  List<_TopicDayStart> _dayStarts(
    ShellController controller,
    String siteUrl,
    List<int> postIds,
  ) {
    // Rebuilding this on every build costs a store read per loaded post, and
    // the floating-day push animation rebuilds per frame. Snapshots allocate
    // a fresh id list each time, so value equality is the usable key; the
    // int comparison is far cheaper than the reads it saves. Created-at never
    // changes for a held post, so same ids means same day starts.
    if (_dayStartsSite == siteUrl && listEquals(_dayStartsFor, postIds)) {
      return _dayStartsCache;
    }
    final starts = <_TopicDayStart>[];
    DateTime? previousDay;
    for (var index = 0; index < postIds.length; index++) {
      final post = controller.store.read<Post>(siteUrl, postIds[index]);
      final day = calendarDay(post?.createdAt);
      if (day != null && day != previousDay) {
        starts.add((day: day, postIndex: index));
      }
      previousDay = day;
    }
    _dayStartsCache = starts;
    _dayStartsFor = postIds;
    _dayStartsSite = siteUrl;
    return starts;
  }

  List<_TopicDayStart> _dayStartsCache = const [];
  List<int>? _dayStartsFor;
  String? _dayStartsSite;

  /// Loads enough of an around-post window to know where [day] really began,
  /// then places that day's first post at the top. This is the topic analogue
  /// of chat's `fetchMessagesByDate(startOfDay)` click.
  Future<void> _jumpToDayStart(DateTime day) async {
    final controller = _controller;
    final identity = _topicIdentity;
    if (controller == null || identity == null) return;

    final token = Object();
    _dayJumpToken = token;
    _anchorRestoreToken = null;
    _restoring = true;

    bool isCurrent() =>
        identical(_dayJumpToken, token) && _isCurrent(controller, identity);

    while (isCurrent()) {
      final snapshot = _TopicViewSnapshot.from(controller);
      if (!snapshot.hasEarlier || snapshot.postIds.isEmpty) break;
      final first = controller.store.read<Post>(
        snapshot.siteUrl!,
        snapshot.postIds.first,
      );
      if (calendarDay(first?.createdAt) != day) break;

      final before = List<int>.of(snapshot.postIds);
      await controller.loadEarlierPosts();
      if (!isCurrent()) return;
      if (listEquals(before, _TopicViewSnapshot.from(controller).postIds)) {
        // A refused page should still land on the earliest copy in hand rather
        // than retrying forever from one click.
        break;
      }
    }
    if (!isCurrent()) return;

    void finish() {
      if (!isCurrent()) return;
      _dayJumpToken = null;
      _restoring = false;
      _scheduleLook(saveAnchor: true);
      _scheduleLoadEarlier(controller, _TopicViewSnapshot.from(controller));
    }

    void jump() {
      if (!isCurrent()) return;
      final snapshot = _TopicViewSnapshot.from(controller);
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

  /// Remembers the farthest real post currently visible, then waits for the
  /// reader to pause. Debouncing the viewport rather than the request avoids a
  /// receipt for every pixel of a fling.
  void _noteWhatIsOnScreen(
    ShellController controller,
    _TopicViewSnapshot snapshot, {
    bool saveAnchor = false,
  }) {
    if (!_restored || _restoring || _list?.isAttached != true) return;
    final range = _list!.visibleRange;
    if (range == null) return;

    final leading = snapshot.hasEarlier || snapshot.loadingEarlier ? 1 : 0;
    for (var childIndex = range.$1; childIndex <= range.$2; childIndex++) {
      if (childIndex.isOdd) continue;
      final itemIndex = childIndex ~/ 2;
      final postIndex = itemIndex - leading;
      if (postIndex < 0 || postIndex >= snapshot.postIds.length) continue;
      final post = controller.store.read<Post>(
        snapshot.siteUrl!,
        snapshot.postIds[postIndex],
      );
      if (post != null &&
          (saveAnchor || _savedAnchorPostNumber != post.postNumber)) {
        controller.saveTopicScrollPost(
          snapshot.topicId!,
          post.postNumber,
          viewportOffset:
              _offsetBeforeChild(_list!, childIndex) - _scroll!.position.pixels,
        );
        _savedAnchorPostNumber = post.postNumber;
      }
      break;
    }
    for (var childIndex = range.$2; childIndex >= range.$1; childIndex--) {
      // Even children are list items; odd children are separators.
      if (childIndex.isOdd) continue;
      final itemIndex = childIndex ~/ 2;
      final postIndex = itemIndex - leading;
      if (postIndex < 0 || postIndex >= snapshot.postIds.length) continue;
      final post = controller.store.read<Post>(
        snapshot.siteUrl!,
        snapshot.postIds[postIndex],
      );
      if (post == null) continue;

      final seen = (
        siteUrl: snapshot.siteUrl!,
        topicId: snapshot.topicId!,
        postNumber: post.postNumber,
        caughtUp: !snapshot.hasMore && postIndex == snapshot.postIds.length - 1,
      );
      if (seen == _seen) return;
      _seen = seen;
      _readTimer?.cancel();
      _readTimer = Timer(_readInterval, _creditReaderNow);
      return;
    }
  }

  void _creditReaderNow() {
    _readTimer?.cancel();
    _readTimer = null;

    final seen = _seen;
    final controller = _controller;
    if (seen == null || controller == null) return;

    // A delayed timer must not credit reading after the app has gone into the
    // background. Null is a test or a launch with no lifecycle event yet, and
    // both mean the view is in front.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;

    void send() => unawaited(
      controller.markTopicRead(
        seen.siteUrl,
        seen.topicId,
        seen.postNumber,
        caughtUp: seen.caughtUp,
      ),
    );

    // dispose runs while Flutter has the element tree locked. The optimistic
    // Store write notifies topic rows, so hand it to the next microtask when a
    // frame is in progress rather than marking one of those rows dirty during
    // unmount.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      send();
    } else {
      unawaited(Future<void>.microtask(send));
    }
  }

  /// Cumulative extent before each child, grown on demand.
  ///
  /// [_offsetBeforeChild] backs every per-frame viewport measurement, and a
  /// fresh walk per call grows with how deep the reader is in the topic. The
  /// list controller notifies exactly when a measure changes during layout,
  /// which is when these sums can go stale — a steady scroll over measured
  /// rows reuses them.
  final List<double> _extentsBefore = [0];

  void _noteExtentsChanged() => _extentsBefore.length = 1;

  double _offsetBeforeChild(ListController list, int childIndex) {
    while (_extentsBefore.length <= childIndex) {
      final index = _extentsBefore.length - 1;
      _extentsBefore.add(_extentsBefore[index] + list.extentForIndex(index).$1);
    }
    return _extentsBefore[childIndex];
  }

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
      return (
        postId: postIds[postIndex],
        viewportOffset:
            _offsetBeforeChild(list, childIndex) - scroll.position.pixels,
      );
    }
    return null;
  }

  /// Keeps a visible post at the same viewport offset while earlier posts are
  /// inserted ahead of it. The second correction runs after the target post
  /// has been laid out with its real height rather than an estimate.
  void _restoreViewportAfterPrepend(
    ShellController controller,
    _TopicViewSnapshot snapshot, {
    required bool hasHeader,
  }) {
    final previousPostIds = _laidOutPostIds;
    final previousHasHeader = _laidOutHasHeader;
    _laidOutPostIds = List.of(snapshot.postIds);
    _laidOutHasHeader = hasHeader;
    // The numbered-route restoration owns the viewport until both of its
    // jumps finish. If a refresh expands a cached window in between them, its
    // final target jump must win over prepend anchoring.
    if (previousPostIds.isEmpty || _restoring) return;

    final previousFirstIndex = snapshot.postIds.indexOf(previousPostIds.first);
    final prepended = previousFirstIndex > 0;
    final headerChanged =
        previousHasHeader != hasHeader &&
        listEquals(previousPostIds, snapshot.postIds);
    if (!prepended && !headerChanged) return;

    final anchor = _captureViewportAnchor(
      previousPostIds,
      hasHeader: previousHasHeader,
    );
    if (anchor == null) return;

    final identity = (snapshot.siteUrl!, snapshot.topicId!);
    final token = Object();
    _anchorRestoreToken = token;
    _restoring = true;

    void restore() {
      if (!identical(_anchorRestoreToken, token)) return;
      if (!_isCurrent(controller, identity)) return;
      final list = _list;
      final scroll = _scroll;
      if (list == null || scroll == null) return;
      if (!list.isAttached || !scroll.hasClients) return;

      final current = _TopicViewSnapshot.from(controller);
      final postIndex = current.postIds.indexOf(anchor.postId);
      if (postIndex < 0) return;
      final leading = current.hasEarlier || current.loadingEarlier ? 1 : 0;
      final childIndex = (postIndex + leading) * 2;
      if (childIndex >= list.numberOfItems) return;
      final target =
          _offsetBeforeChild(list, childIndex) - anchor.viewportOffset;
      final position = scroll.position;
      scroll.jumpTo(
        target
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      restore();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        restore();
        if (!identical(_anchorRestoreToken, token)) return;
        _anchorRestoreToken = null;
        if (!_isCurrent(controller, identity)) return;
        _restoring = false;
        _scheduleLook();
        _scheduleLoadEarlier(controller, _TopicViewSnapshot.from(controller));
      });
    });
  }

  @override
  Widget build(BuildContext context) => ShellSelector<_TopicViewSnapshot>(
    select: _TopicViewSnapshot.from,
    builder: _build,
  );

  void _scheduleLoadMore(
    ShellController controller,
    _TopicViewSnapshot snapshot,
  ) {
    final siteUrl = snapshot.siteUrl;
    final topicId = snapshot.topicId;
    if (siteUrl == null ||
        topicId == null ||
        !snapshot.hasMore ||
        snapshot.loadingMore) {
      return;
    }

    // The target survives the request, so a failed page — which leaves the
    // post count unchanged — cannot be re-requested by the rebuild it causes.
    // A landed page changes the count and with it the target.
    final target = (siteUrl, topicId, snapshot.postIds.length);
    if (_loadMoreTarget == target) return;

    final token = Object();
    _loadMoreToken = token;
    _loadMoreTarget = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!identical(_loadMoreToken, token)) return;
      _loadMoreToken = null;
      if (!mounted ||
          !identical(ShellScope.read(context), controller) ||
          _TopicViewSnapshot.from(controller) != snapshot) {
        if (_loadMoreTarget == target) _loadMoreTarget = null;
        return;
      }
      unawaited(controller.loadMorePosts());
    });
  }

  void _allowLoadMoreRetry(_TopicViewSnapshot snapshot) {
    if (_loadMoreToken != null || !snapshot.hasMore || snapshot.loadingMore) {
      return;
    }
    final siteUrl = snapshot.siteUrl;
    final topicId = snapshot.topicId;
    if (siteUrl == null || topicId == null) return;
    final target = (siteUrl, topicId, snapshot.postIds.length);
    if (_loadMoreTarget == target) _loadMoreTarget = null;
  }

  void _scheduleLoadEarlier(
    ShellController controller,
    _TopicViewSnapshot snapshot,
  ) {
    final siteUrl = snapshot.siteUrl;
    final topicId = snapshot.topicId;
    final scroll = _scroll;
    if (siteUrl == null ||
        topicId == null ||
        snapshot.postIds.isEmpty ||
        !snapshot.hasEarlier ||
        snapshot.loadingEarlier ||
        _restoring ||
        scroll == null ||
        !scroll.hasClients ||
        scroll.position.extentBefore >= TopicView._loadPostsThreshold) {
      return;
    }

    final target = (siteUrl, topicId, snapshot.postIds.first);
    if (_loadEarlierTarget == target) return;

    final token = Object();
    _loadEarlierToken = token;
    _loadEarlierTarget = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!identical(_loadEarlierToken, token)) return;
      _loadEarlierToken = null;
      if (!mounted ||
          _restoring ||
          !identical(ShellScope.read(context), controller) ||
          _TopicViewSnapshot.from(controller) != snapshot) {
        if (_loadEarlierTarget == target) _loadEarlierTarget = null;
        return;
      }
      unawaited(controller.loadEarlierPosts());
    });
  }

  void _allowLoadEarlierRetry(_TopicViewSnapshot snapshot) {
    if (_loadEarlierToken != null ||
        !snapshot.hasEarlier ||
        snapshot.loadingEarlier) {
      return;
    }
    final siteUrl = snapshot.siteUrl;
    final topicId = snapshot.topicId;
    if (siteUrl == null || topicId == null || snapshot.postIds.isEmpty) return;
    final target = (siteUrl, topicId, snapshot.postIds.first);
    if (_loadEarlierTarget == target) _loadEarlierTarget = null;
  }

  Widget _build(
    BuildContext context,
    _TopicViewSnapshot snapshot,
    Widget? child,
  ) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);

    if (snapshot.topicId == null) {
      if (snapshot.loading) {
        return const _TopicLoadingSkeleton(
          key: ValueKey('topic-loading-skeleton'),
        );
      }
      return Center(
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
      );
    }

    // The footer is a spinner, so it may only appear while actually loading —
    // otherwise it spins forever at the bottom of a topic with more to fetch.
    final showFooter = snapshot.loadingMore;
    final showHeader = snapshot.hasEarlier || snapshot.loadingEarlier;
    final showRecommendations =
        !snapshot.hasMore && snapshot.recommendations?.isNotEmpty == true;
    final showRecommendationsPanel =
        widget.showRecommendationsPanel && showRecommendations;

    // Which posts are on screen, and in what order. The posts themselves are
    // in the store; each tile watches its own, so an edit or a deletion redraws
    // one tile rather than walking the whole stream.
    final postIds = snapshot.postIds;
    final siteUrl = snapshot.siteUrl!;
    _syncRecommendationsSite(siteUrl);
    final topicIdentity = (siteUrl, snapshot.topicId!);
    _syncControllers(controller, topicIdentity);
    final dayStarts = _dayStarts(controller, siteUrl, postIds);
    _laidOutDayStarts = dayStarts;
    final dayByPostIndex = {
      for (final start in dayStarts) start.postIndex: start.day,
    };
    _restoreInitialPost(controller, snapshot);
    _restoreViewportAfterPrepend(controller, snapshot, hasHeader: showHeader);
    _scheduleLook();

    final postStream = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) {
          // SuperSliverList publishes its new visible range during layout,
          // after the scroll notification. Looking synchronously here reads
          // the previous viewport and repeatedly credits the old post.
          _scheduleLook(saveAnchor: notification is ScrollEndNotification);
          // A failed page in either direction stays suppressed through the
          // rebuild it causes, so it cannot retry in a tight loop. A fresh
          // scroll deliberately re-arms that same page, including when the
          // pane is too short to ever leave the threshold.
          if (notification is ScrollStartNotification && !_restoring) {
            _allowLoadEarlierRetry(snapshot);
            _allowLoadMoreRetry(snapshot);
          }
          if (notification.metrics.extentBefore <
              TopicView._loadPostsThreshold) {
            _scheduleLoadEarlier(controller, snapshot);
          } else if (!snapshot.loadingEarlier) {
            _allowLoadEarlierRetry(snapshot);
          }
          if (notification.metrics.extentAfter <
              TopicView._loadPostsThreshold) {
            _scheduleLoadMore(controller, snapshot);
          } else if (!snapshot.loadingMore) {
            _allowLoadMoreRetry(snapshot);
          }
        }
        return false;
      },
      // A plain ListView estimates how tall the unbuilt posts are by averaging
      // the ones currently laid out. Post heights swing from a one-line small
      // action to a screenful of quotes and images, so that average — and with
      // it maxScrollExtent — lurches as you scroll, and the scrollbar thumb
      // jumps. SuperListView remembers each post's real height once measured,
      // so the estimate only ever tightens.
      //
      // Its extentPrecalculationPolicy would make the scrollbar exact rather
      // than merely stable, but precalculating builds every post — including
      // the last, whose builder asks for the next page. That would walk the
      // whole topic on open.
      child: SuperListView.separated(
        key: ValueKey((siteUrl, snapshot.topicId)),
        controller: _scroll,
        listController: _list,
        // A short around-post window still needs to accept a pull toward the
        // top, both to fetch and to retry an earlier page. Once post one is in
        // hand, stop forcing top-edge overscroll: there is no earlier request
        // left for that gesture to make.
        physics: snapshot.hasEarlier
            ? const AlwaysScrollableScrollPhysics()
            : null,
        // Keep existing post elements attached to their ids when a page is
        // inserted before them; separated lists address the expanded index.
        findChildIndexCallback: (key) {
          if (key is! ValueKey<int>) return null;
          final postIndex = postIds.indexOf(key.value);
          if (postIndex < 0) return null;
          return (postIndex + (showHeader ? 1 : 0)) * 2;
        },
        // Lazy, like the topic list: a 500-post topic builds only what shows.
        itemCount:
            postIds.length +
            (showHeader ? 1 : 0) +
            (showFooter ? 1 : 0) +
            (showRecommendations && !showRecommendationsPanel ? 1 : 0),
        separatorBuilder: (context, index) {
          final nextPostIndex = index + 1 - (showHeader ? 1 : 0);
          if (dayByPostIndex.containsKey(nextPostIndex)) {
            // The calendar marker is the boundary; a second rule immediately
            // above it would make the separation look doubled.
            return const SizedBox.shrink();
          }
          return Divider(height: 1, color: theme.shell.divider);
        },
        itemBuilder: (context, index) {
          if (showHeader && index == 0) {
            _scheduleLoadEarlier(controller, snapshot);
            return _EarlierPostsRow(loading: snapshot.loadingEarlier);
          }

          final postIndex = index - (showHeader ? 1 : 0);
          if (postIndex >= postIds.length) {
            final trailingIndex = postIndex - postIds.length;
            if (showFooter && trailingIndex == 0) {
              return const _LoadingPostsRow();
            }
            return _MoreTopics(
              key: ValueKey((siteUrl, snapshot.topicId, 'more-topics')),
              recommendations: snapshot.recommendations!,
              selected: _recommendationsTab,
              onSelected: _setRecommendationsTab,
            );
          }

          // Building the last post means the end is in view. Scrolling alone
          // is not enough: twenty short posts may not fill the window, leaving
          // nothing to scroll and the rest never fetched.
          if (postIndex == postIds.length - 1 && snapshot.hasMore) {
            _scheduleLoadMore(controller, snapshot);
          }
          final postId = postIds[postIndex];
          final day = dayByPostIndex[postIndex];
          return _TopicPostItem(
            key: ValueKey(postId),
            day: day,
            hideDay: day != null && day == _floatingDay,
            onDayTap: day == null ? null : () => _jumpToDayStart(day),
            child: _StoredPost(
              siteUrl: siteUrl,
              topic: snapshot.topic!,
              postId: postId,
            ),
          );
        },
      ),
    );

    final floatingDay = _floatingDay;
    return Row(
      children: [
        Expanded(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(child: postStream),
              if (floatingDay != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: _floatingDayOffset,
                  child: _TopicDaySeparator(
                    key: ValueKey(('topic-floating-day', floatingDay)),
                    day: floatingDay,
                    floating: true,
                    onTap: () => _jumpToDayStart(floatingDay),
                  ),
                ),
            ],
          ),
        ),
        if (showRecommendationsPanel)
          _TopicRecommendationsPanel(
            collapsed: _recommendationsPanelCollapsed,
            recommendations: snapshot.recommendations!,
            selected: _recommendationsTab,
            onSelected: _setRecommendationsTab,
            onCollapsedChanged: _setRecommendationsPanelCollapsed,
          ),
      ],
    );
  }
}

/// A faithful outline of the post stream while its first page is in flight.
///
/// The post pattern repeats until it covers the viewport. Any remainder, or
/// the whole pattern on an exceptionally short pane, is clipped so loading
/// never introduces a second scroll position or changes the real stream's
/// eventual anchor.
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
    return Padding(
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
  }
}

@immutable
class _TopicViewSnapshot {
  const _TopicViewSnapshot({
    required this.topicId,
    required this.topic,
    required this.siteUrl,
    required this.postIds,
    required this.loading,
    required this.loadingMore,
    required this.loadingEarlier,
    required this.hasMore,
    required this.hasEarlier,
    required this.initialPostIndex,
    required this.recommendations,
    required this.canAssignLegacyTargets,
  });

  factory _TopicViewSnapshot.from(ShellController controller) {
    final postIds = controller.currentPostIds;
    final siteUrl = controller.currentInstance?.url;
    final topicId = controller.currentContent?.topicId;
    final target = topicId == null
        ? null
        : controller.topicScrollPostNumber(topicId);
    final hasEarlier = controller.currentTopicHasEarlier;
    int? initialPostIndex;
    if (siteUrl != null && target != null) {
      for (var index = 0; index < postIds.length; index++) {
        final post = controller.store.read<Post>(siteUrl, postIds[index]);
        // If the named post has since been deleted, reveal the next visible
        // one rather than dropping the reader at the start of the window.
        if (post != null && post.postNumber >= target) {
          initialPostIndex = index + (hasEarlier ? 1 : 0);
          break;
        }
      }
    }

    return _TopicViewSnapshot(
      topicId: controller.currentTopic?.id,
      topic: controller.currentTopic,
      siteUrl: siteUrl,
      postIds: postIds,
      loading: controller.currentTopicLoading,
      loadingMore: controller.loadingMorePosts,
      loadingEarlier: controller.loadingEarlierPosts,
      hasMore: controller.currentTopicHasMore,
      hasEarlier: hasEarlier,
      initialPostIndex: initialPostIndex,
      recommendations: controller.currentTopic?.recommendations,
      canAssignLegacyTargets:
          siteUrl != null && controller.canAssignForTarget(siteUrl, null),
    );
  }

  final int? topicId;
  final TopicDetail? topic;
  final String? siteUrl;
  final List<int> postIds;
  final bool loading;
  final bool loadingMore;
  final bool loadingEarlier;
  final bool hasMore;
  final bool hasEarlier;
  final int? initialPostIndex;
  final TopicRecommendations? recommendations;
  final bool canAssignLegacyTargets;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TopicViewSnapshot &&
          topicId == other.topicId &&
          identical(topic, other.topic) &&
          siteUrl == other.siteUrl &&
          listEquals(postIds, other.postIds) &&
          loading == other.loading &&
          loadingMore == other.loadingMore &&
          loadingEarlier == other.loadingEarlier &&
          hasMore == other.hasMore &&
          hasEarlier == other.hasEarlier &&
          recommendations == other.recommendations &&
          canAssignLegacyTargets == other.canAssignLegacyTargets;

  @override
  int get hashCode => Object.hash(
    topicId,
    identityHashCode(topic),
    siteUrl,
    Object.hashAll(postIds),
    loading,
    loadingMore,
    loadingEarlier,
    hasMore,
    hasEarlier,
    recommendations,
    canAssignLegacyTargets,
  );
}

class _TopicRecommendationsPanel extends StatelessWidget {
  const _TopicRecommendationsPanel({
    required this.collapsed,
    required this.recommendations,
    required this.selected,
    required this.onSelected,
    required this.onCollapsedChanged,
  });

  static const double _width = 320;
  static const double _collapsedWidth = 48;

  final bool collapsed;
  final TopicRecommendations recommendations;
  final TopicRecommendationsTab selected;
  final ValueChanged<TopicRecommendationsTab> onSelected;
  final ValueChanged<bool> onCollapsedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('topic-recommendations-panel'),
      width: collapsed ? _collapsedWidth : _width,
      decoration: BoxDecoration(
        color: theme.shell.panel,
        border: Border(left: BorderSide(color: theme.shell.divider)),
      ),
      child: collapsed
          ? Align(
              alignment: Alignment.topCenter,
              child: IconButton(
                onPressed: () => onCollapsedChanged(false),
                icon: const DIcon(DIcons.chevronLeft, size: 18),
                tooltip: 'Show more topics',
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'More topics',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => onCollapsedChanged(true),
                        icon: const DIcon(DIcons.chevronRight, size: 18),
                        tooltip: 'Collapse more topics',
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: theme.shell.divider),
                Expanded(
                  child: SingleChildScrollView(
                    child: _MoreTopics(
                      key: const ValueKey('topic-recommendations-panel-list'),
                      recommendations: recommendations,
                      selected: selected,
                      onSelected: onSelected,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Core's more-topics footer. Suggested topics are always a core feature;
/// related topics appear when discourse-ai's semantic recommendations are on.
///
/// The reader's tab choice is remembered per forum, so it is owned by the
/// topic view rather than by this widget, which a new topic rebuilds.
class _MoreTopics extends StatelessWidget {
  const _MoreTopics({
    super.key,
    required this.recommendations,
    required this.selected,
    required this.onSelected,
  });

  final TopicRecommendations recommendations;
  final TopicRecommendationsTab selected;
  final ValueChanged<TopicRecommendationsTab> onSelected;

  /// The remembered choice only holds while that list has topics; a forum
  /// without discourse-ai, or a topic with no semantic matches, falls back to
  /// whichever list is there rather than showing an empty tab.
  TopicRecommendationsTab get _effectiveSelection {
    if (selected == TopicRecommendationsTab.suggested &&
        recommendations.suggested.isNotEmpty) {
      return TopicRecommendationsTab.suggested;
    }
    if (recommendations.related.isNotEmpty) {
      return TopicRecommendationsTab.related;
    }
    return TopicRecommendationsTab.suggested;
  }

  @override
  Widget build(BuildContext context) {
    final suggested = recommendations.suggested.isNotEmpty;
    final related = recommendations.related.isNotEmpty;
    final hasTabs = suggested && related;
    final selection = _effectiveSelection;
    final topics = switch (selection) {
      TopicRecommendationsTab.suggested => recommendations.suggested,
      TopicRecommendationsTab.related => recommendations.related,
    };
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasTabs)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.shell.divider)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _MoreTopicsTabButton(
                      key: const ValueKey('suggested-topics-tab'),
                      label: 'Suggested',
                      selected: selection == TopicRecommendationsTab.suggested,
                      onPressed: () =>
                          onSelected(TopicRecommendationsTab.suggested),
                    ),
                  ),
                  Expanded(
                    child: _MoreTopicsTabButton(
                      key: const ValueKey('related-topics-tab'),
                      label: 'Related',
                      icon: DIcons.discourseSparkles,
                      selected: selection == TopicRecommendationsTab.related,
                      onPressed: () =>
                          onSelected(TopicRecommendationsTab.related),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  if (related) ...[
                    DIcon(
                      DIcons.discourseSparkles,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    related ? 'Related' : 'Suggested',
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          for (var index = 0; index < topics.length; index++) ...[
            TopicListRow(topic: topics[index]),
            if (index < topics.length - 1)
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

/// A post together with the calendar boundary immediately above it.
///
/// Keeping both in one logical list item is important: all topic paging,
/// viewport receipts, and restoration address posts, not decorative rows.
class _TopicPostItem extends StatelessWidget {
  const _TopicPostItem({
    super.key,
    required this.day,
    required this.hideDay,
    required this.onDayTap,
    required this.child,
  });

  final DateTime? day;
  final bool hideDay;
  final VoidCallback? onDayTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final day = this.day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (day != null)
          IgnorePointer(
            ignoring: hideDay,
            child: Opacity(
              opacity: hideDay ? 0 : 1,
              child: _TopicDaySeparator(
                key: ValueKey(('topic-day', day)),
                day: day,
                onTap: onDayTap!,
              ),
            ),
          ),
        child,
      ],
    );
  }
}

/// The date line in the stream and the bordered pill it becomes once pinned.
class _TopicDaySeparator extends StatelessWidget {
  const _TopicDaySeparator({
    super.key,
    required this.day,
    required this.onTap,
    this.floating = false,
  });

  static const double height = 44;

  final DateTime day;
  final VoidCallback onTap;
  final bool floating;

  String get _label => dayLabel(day, now: DateTime.now());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _label;
    // Core's pinned date uses primary-50 against a primary-200 border. The
    // matching Material roles preserve that contrast for each site palette.
    final background = floating
        ? theme.colorScheme.surfaceContainerLow
        : theme.shell.content;

    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!floating)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 1, color: theme.shell.divider),
            ),
          Semantics(
            button: true,
            label: 'Go to start of $label',
            onTap: onTap,
            excludeSemantics: true,
            child: Tooltip(
              message: 'Go to start of $label',
              excludeFromSemantics: true,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: onTap,
                  child: SizedBox(
                    height: height,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: background,
                          border: Border.all(
                            color: floating
                                ? theme.colorScheme.surfaceContainerHigh
                                : Colors.transparent,
                          ),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: floating
                              ? const [
                                  BoxShadow(
                                    color: Color(0x1F000000),
                                    blurRadius: 3,
                                    offset: Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EarlierPostsRow extends StatelessWidget {
  const _EarlierPostsRow({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: loading
            ? const CircularProgressIndicator.adaptive(strokeWidth: 2)
            : null,
      ),
    ),
  );
}

/// Draws whichever post the store holds under [postId].
///
/// The indirection is the point: rewriting a post, deleting it, or fetching its
/// markdown for the composer all write one record, and only the tile watching
/// that record is rebuilt.
class _StoredPost extends StatelessWidget {
  const _StoredPost({
    required this.siteUrl,
    required this.topic,
    required this.postId,
  });

  final String siteUrl;
  final TopicDetail topic;
  final int postId;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Post?>(
      valueListenable: ShellScope.read(context).postRef(siteUrl, postId),
      builder: (context, post, _) {
        // Gone for good — deleted outright rather than soft-deleted — in the
        // frame before the stream that named it is rewritten without it.
        if (post == null) return const SizedBox.shrink();
        return post.isSmallAction
            ? SmallActionTile(post: post, siteUrl: siteUrl)
            : _PostTile(siteUrl: siteUrl, topic: topic, post: post);
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
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = widget.post;

    // Transparent rather than [ShellColors.content] when idle, so the tile
    // takes whichever surface the column it is in happens to paint.
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: ColoredBox(
        color: switch ((post.isDeleted, _hovered)) {
          (true, final hovered) => theme.colorScheme.error.withValues(
            alpha: hovered ? 0.12 : 0.07,
          ),
          (false, true) => theme.shell.hover,
          (false, false) => Colors.transparent,
        },
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
                          // Only the people who can undo a deletion are shown
                          // one at all, so saying so is worth the room.
                          if (post.isDeleted) ...[
                            const SizedBox(width: 6),
                            _Tag(
                              label: 'deleted',
                              color: theme.colorScheme.error,
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
                    if (post.createdAt case final createdAt?)
                      Text(
                        relativeTime(createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
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
                  ),
                ),
                ...pluginRegistry.postDecorations(
                  context,
                  widget.siteUrl,
                  widget.topic,
                  post,
                ),
                PostFooter(siteUrl: widget.siteUrl, post: post),
              ],
            ),
          ),
        ),
      ),
    );
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
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator.adaptive(strokeWidth: 2),
      ),
    ),
  );
}
