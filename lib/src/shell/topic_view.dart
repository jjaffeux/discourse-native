import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../data/topic_recommendations_tab_store.dart';
import '../data/topic_sidebar_store.dart';
import '../foundation/calendar_day.dart';
import '../models/content_route.dart';
import '../models/post.dart';
import '../models/post_flag.dart';
import '../models/site_config.dart';
import '../models/topic.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'cooked_html.dart';
import 'inline_action.dart';
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
import 'shell_sheet.dart';
import 'small_action.dart';
import 'stream_day_separator.dart';
import 'time_gap.dart';
import 'title_bar.dart';
import 'topic_actions.dart';
import 'topic_change_owner.dart';
import 'topic_list_view.dart';
import 'topic_move_posts.dart';
import 'topic_progress.dart';
import 'topic_tag_picker.dart';
import 'topic_title.dart';
import 'user_card.dart';
import 'user_menu_button.dart';
import 'user_status.dart';

/// A topic and its posts.
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
  });

  /// Start fetching the next batch about a screen before either end.
  static const double _loadPostsThreshold = 900;

  /// Header, body line, their gap, and the post's outer padding.
  static const double minimumPostHeight = 96;

  /// Whether topic context is docked beside the posts. Narrow layouts leave
  /// this false so the reading column stays usable.
  final bool showSidebar;

  final bool canReturnToSidebar;

  final TopicSidebarStore sidebarStore;

  final TopicRecommendationsTabStore recommendationsTabStore;

  final ContentRoute? route;
  final bool canReply;
  final bool bookmarkBusy;
  final bool isConnected;
  final PluginRegistry registry;

  @override
  State<TopicView> createState() => _TopicViewState();
}

typedef _TopicDayStart = ({DateTime day, int postIndex});
typedef _TopicTimeGap = ({int daysSince, int postIndex});

/// The inverse of one immutable post stream, used to retain keyed list rows.
///
/// A page inserted before the viewport makes the sliver resolve every retained
/// child's key again. Looking each id up in the post list would walk an
/// increasingly long tail once per retained child; projecting the stream once
/// keeps the reconciliation itself constant-time per child.
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
  static const Duration _readInterval = Duration(milliseconds: 500);

  ScrollController? _scroll;
  ListController? _list;
  (String, int, int)? _topicIdentity;
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
  bool _userDragging = false;
  bool _applyingAnchorRestore = false;
  bool _lookScheduled = false;
  bool _saveAnchorAfterLook = false;
  int? _savedAnchorPostNumber;
  String? _recommendationsSiteUrl;
  bool _sidebarCollapsed = false;
  bool _sidebarOverlayOpen = false;
  int _sidebarRestoreGeneration = 0;
  TopicRecommendationSourceId _recommendationsSourceId =
      coreSuggestedTopicRecommendationSourceId;
  int _recommendationsTabRestoreGeneration = 0;
  List<_TopicDayStart> _laidOutDayStarts = const [];
  DateTime? _floatingDay;
  double _floatingDayOffset = 0;
  Object? _dayJumpToken;
  Timer? _readTimer;
  ({String siteUrl, int topicId, int postNumber, bool caughtUp})? _seen;
  int? _progressPosition;
  TopicPostIndexProjection? _postIndexProjection;

  TopicPostIndexProjection _postIndexes(List<int> postIds) {
    final held = _postIndexProjection;
    if (held != null && held.represents(postIds)) return held;
    return _postIndexProjection = TopicPostIndexProjection(postIds);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant TopicView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showSidebar != widget.showSidebar) {
      _sidebarOverlayOpen = false;
    }
  }

  void _syncControllers(
    ShellController controller,
    (String, int, int) topicIdentity,
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
    _userDragging = false;
    _applyingAnchorRestore = false;
    _lookScheduled = false;
    _saveAnchorAfterLook = false;
    _savedAnchorPostNumber = null;
    _laidOutDayStarts = const [];
    _floatingDay = null;
    _floatingDayOffset = 0;
    _dayJumpToken = null;
    _seen = null;
    _progressPosition = null;
    _sidebarOverlayOpen = false;
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
    final identity = (
      snapshot.siteUrl!,
      snapshot.topicId!,
      snapshot.navigationRevision,
    );
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

  bool _isCurrent(
    ShellController controller,
    (String, int, int) topicIdentity,
  ) =>
      mounted &&
      _topicIdentity == topicIdentity &&
      _tabId == controller.activeTabId &&
      controller.currentInstance?.url == topicIdentity.$1 &&
      controller.currentTopic?.id == topicIdentity.$2 &&
      controller.topicNavigationRevision == topicIdentity.$3;

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
    WidgetsBinding.instance.removeObserver(this);
    _sidebarRestoreGeneration++;
    _recommendationsTabRestoreGeneration++;
    _dayJumpToken = null;
    _creditReaderNow();
    // Nothing can move this topic's anchor once its viewport is gone, so a
    // save still waiting out its debounce window is written now.
    _controller?.flushAnchorPersist();
    _disposeControllers();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;

    // The post was measured while the app was still in front. Flush that
    // observation at the first foreground-exit signal, before the platform can
    // suspend the request. This is especially easy to hit from a video-only
    // post: opening the video externally backgrounds the app inside the normal
    // viewport debounce window.
    _creditReaderNow(leavingForeground: true);
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
    setState(() => _sidebarCollapsed = collapsed);
    unawaited(
      widget.sidebarStore.write(siteUrl: siteUrl, collapsed: collapsed),
    );
  }

  void _setSidebarOverlayOpen(bool open) {
    if (open == _sidebarOverlayOpen) return;
    setState(() => _sidebarOverlayOpen = open);
  }

  void _toggleSidebar() {
    if (widget.showSidebar) {
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
      if (nextTop < StreamDaySeparator.height) {
        offset = nextTop - StreamDaySeparator.height;
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

      final streamIndex = snapshot.streamIds.indexOf(post.id);
      if (streamIndex >= 0) _setProgressPosition(streamIndex + 1);

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

  void _setProgressPosition(int position) {
    if (_progressPosition == position || !mounted) return;
    setState(() => _progressPosition = position);
  }

  void _creditReaderNow({bool leavingForeground = false}) {
    _readTimer?.cancel();
    _readTimer = null;

    final seen = _seen;
    final controller = _controller;
    if (seen == null || controller == null) return;

    // A delayed timer must not credit reading after the app has gone into the
    // background. Null is a test or a launch with no lifecycle event yet, and
    // both mean the view is in front.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!leavingForeground &&
        lifecycle != null &&
        lifecycle != AppLifecycleState.resumed) {
      return;
    }

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

    final identity = (
      snapshot.siteUrl!,
      snapshot.topicId!,
      snapshot.navigationRevision,
    );
    final token = Object();
    _anchorRestoreToken = token;
    _restoring = true;

    void restore() {
      if (!identical(_anchorRestoreToken, token)) return;
      if (!_isCurrent(controller, identity)) return;
      // ScrollPosition.jumpTo ends the current drag. Once the reader has put
      // a finger back on the list, preserving that live gesture matters more
      // than applying the second, estimate-settling correction.
      if (_userDragging) {
        _anchorRestoreToken = null;
        _restoring = false;
        return;
      }
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
      _applyingAnchorRestore = true;
      try {
        scroll.jumpTo(
          target
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble(),
        );
      } finally {
        _applyingAnchorRestore = false;
      }
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
        !scroll.hasClients) {
      return;
    }

    final position = scroll.position;
    if (!position.hasContentDimensions) {
      // The leading row can be built after the controller attaches but before
      // its first layout supplies scroll extents. Reading extentBefore in that
      // gap trips ScrollPosition's null assertion. Retry after this layout so
      // a short around-post window still fetches its preceding page.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(_scroll, scroll)) return;
        _scheduleLoadEarlier(controller, snapshot);
      });
      return;
    }
    if (position.extentBefore >= TopicView._loadPostsThreshold) return;

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
    if (snapshot.siteUrl case final siteUrl?) {
      _syncRecommendationsSite(siteUrl);
    }

    if (snapshot.topicId == null) {
      if (snapshot.loading) {
        const topicSkeleton = _TopicLoadingSkeleton(
          key: ValueKey('topic-loading-skeleton'),
        );
        final showDockedSidebar = widget.showSidebar && !_sidebarCollapsed;
        final showOverlaySidebar = !widget.showSidebar && _sidebarOverlayOpen;
        return Stack(
          children: [
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _TopicViewHeader(
                          title: widget.route?.title ?? 'Topic',
                          siteUrl: snapshot.siteUrl,
                          canReturnToSidebar: widget.canReturnToSidebar,
                          sidebarVisible:
                              showDockedSidebar || showOverlaySidebar,
                          onToggleSidebar: showOverlaySidebar
                              ? null
                              : _toggleSidebar,
                        ),
                        const Expanded(child: topicSkeleton),
                      ],
                    ),
                  ),
                  if (showDockedSidebar)
                    _TopicSidebarPanel(
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
                ],
              ),
            ),
            if (showOverlaySidebar)
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                child: Material(
                  elevation: 8,
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
              ),
          ],
        );
      }
      return Column(
        children: [
          _TopicViewHeader(
            title: widget.route?.title ?? 'Topic',
            siteUrl: snapshot.siteUrl,
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

    // The footer is a loading skeleton, so it may only appear while actually
    // loading — otherwise it pulses forever below a topic with more to fetch.
    final showFooter = snapshot.loadingMore;
    final showHeader = snapshot.hasEarlier || snapshot.loadingEarlier;
    final hasRecommendations = snapshot.recommendations?.isNotEmpty == true;
    final showRecommendations = !snapshot.hasMore && hasRecommendations;
    // A null payload is unresolved rather than empty: Discourse only sends
    // the recommendation fields with the final post window. Reserve the
    // eventual panel while that window is still outstanding so its arrival
    // cannot resize the post column.
    final recommendationsPending =
        snapshot.recommendations == null &&
        (snapshot.hasMore || snapshot.loadingMore);
    final showDockedSidebar = widget.showSidebar && !_sidebarCollapsed;
    final showOverlaySidebar = !widget.showSidebar && _sidebarOverlayOpen;

    // Which posts are on screen, and in what order. The posts themselves are
    // in the store; each tile watches its own, so an edit or a deletion redraws
    // one tile rather than walking the whole stream.
    final postIds = snapshot.postIds;
    final postIndexes = _postIndexes(postIds);
    final siteUrl = snapshot.siteUrl!;
    final topicIdentity = (
      siteUrl,
      snapshot.topicId!,
      snapshot.navigationRevision,
    );
    _syncControllers(controller, topicIdentity);
    final dayStarts = _dayStarts(controller, siteUrl, postIds);
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
    _restoreInitialPost(controller, snapshot);
    _restoreViewportAfterPrepend(controller, snapshot, hasHeader: showHeader);
    _scheduleLook();

    final postStream = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _userDragging = true;
          } else if (notification is ScrollEndNotification) {
            _userDragging = false;
          }
          // Wheel, trackpad, touch, and an unrelated programmatic scroll all
          // supersede a queued prepend correction. The correction's own
          // ScrollUpdateNotification is ignored while jumpTo is on the stack.
          if (notification is ScrollUpdateNotification &&
              !_applyingAnchorRestore &&
              _anchorRestoreToken != null) {
            _anchorRestoreToken = null;
            _restoring = false;
          }
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
          final postIndex = postIndexes[key.value];
          if (postIndex == null) return null;
          return (postIndex + (showHeader ? 1 : 0)) * 2;
        },
        // Lazy, like the topic list: a 500-post topic builds only what shows.
        itemCount:
            postIds.length +
            (showHeader ? 1 : 0) +
            (showFooter ? 1 : 0) +
            (showRecommendations && !widget.showSidebar ? 1 : 0),
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
              siteUrl: siteUrl,
              recommendations: snapshot.recommendations!,
              selected: _recommendationsSourceId,
              onSelected: _setRecommendationsSource,
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
            postId: postId,
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
    );

    final floatingDay = _floatingDay;
    return Stack(
      children: [
        Positioned.fill(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _TopicViewHeader(
                      title: snapshot.topic!.title,
                      siteUrl: siteUrl,
                      topic: snapshot.topic!,
                      isConnected: widget.isConnected,
                      bookmarkBusy: widget.bookmarkBusy,
                      canReturnToSidebar: widget.canReturnToSidebar,
                      sidebarVisible: showDockedSidebar || showOverlaySidebar,
                      onToggleSidebar: showOverlaySidebar
                          ? null
                          : _toggleSidebar,
                    ),
                    _TopicPostSelectionToolbar(
                      siteUrl: siteUrl,
                      topic: snapshot.topic!,
                    ),
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
                              right: 16,
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
              if (showDockedSidebar)
                _TopicSidebarPanel(
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
            ],
          ),
        ),
        if (showOverlaySidebar)
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            child: Material(
              elevation: 8,
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
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: ValueKey('topic-selected-${action.toLowerCase()}-confirm'),
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    )
                  : null,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
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

@immutable
class _TopicViewSnapshot {
  const _TopicViewSnapshot({
    required this.topicId,
    required this.topic,
    required this.siteUrl,
    required this.postIds,
    required this.streamIds,
    required this.loading,
    required this.loadingMore,
    required this.loadingEarlier,
    required this.hasMore,
    required this.hasEarlier,
    required this.initialPostIndex,
    required this.recommendations,
    required this.summary,
    required this.summaryLoading,
    required this.readTimeWordCount,
    required this.showTimeGapDays,
    required this.navigationRevision,
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
      streamIds: controller.currentTopicStreamIds,
      loading: controller.currentTopicLoading,
      loadingMore: controller.loadingMorePosts,
      loadingEarlier: controller.loadingEarlierPosts,
      hasMore: controller.currentTopicHasMore,
      hasEarlier: hasEarlier,
      initialPostIndex: initialPostIndex,
      recommendations: controller.currentTopic?.recommendations,
      summary: controller.currentTopicSummary,
      summaryLoading: controller.currentTopicSummaryLoading,
      readTimeWordCount: controller.currentSiteConfig.readTimeWordCount,
      showTimeGapDays: siteUrl == null
          ? SiteConfig.defaultShowTimeGapDays
          : controller.siteConfigFor(siteUrl).showTimeGapDays,
      navigationRevision: controller.topicNavigationRevision,
    );
  }

  final int? topicId;
  final TopicDetail? topic;
  final String? siteUrl;
  final List<int> postIds;
  final List<int> streamIds;
  final bool loading;
  final bool loadingMore;
  final bool loadingEarlier;
  final bool hasMore;
  final bool hasEarlier;
  final int? initialPostIndex;
  final TopicRecommendations? recommendations;
  final bool summary;
  final bool summaryLoading;
  final int readTimeWordCount;
  final int showTimeGapDays;
  final int navigationRevision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TopicViewSnapshot &&
          topicId == other.topicId &&
          identical(topic, other.topic) &&
          siteUrl == other.siteUrl &&
          listEquals(postIds, other.postIds) &&
          listEquals(streamIds, other.streamIds) &&
          loading == other.loading &&
          loadingMore == other.loadingMore &&
          loadingEarlier == other.loadingEarlier &&
          hasMore == other.hasMore &&
          hasEarlier == other.hasEarlier &&
          recommendations == other.recommendations &&
          summary == other.summary &&
          summaryLoading == other.summaryLoading &&
          readTimeWordCount == other.readTimeWordCount &&
          showTimeGapDays == other.showTimeGapDays &&
          navigationRevision == other.navigationRevision;

  @override
  int get hashCode => Object.hash(
    topicId,
    identityHashCode(topic),
    siteUrl,
    Object.hashAll(postIds),
    Object.hashAll(streamIds),
    loading,
    loadingMore,
    loadingEarlier,
    hasMore,
    hasEarlier,
    recommendations,
    summary,
    summaryLoading,
    readTimeWordCount,
    showTimeGapDays,
    navigationRevision,
  );
}

class _TopicViewHeader extends StatelessWidget {
  const _TopicViewHeader({
    required this.title,
    required this.siteUrl,
    required this.canReturnToSidebar,
    this.topic,
    this.isConnected = false,
    this.bookmarkBusy = false,
    this.sidebarVisible = false,
    this.onToggleSidebar,
  });

  final String title;
  final String? siteUrl;
  final bool canReturnToSidebar;
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
    return Container(
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
                    siteUrl: siteUrl!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
          ),
          if (topic case final topic?
              when siteUrl != null &&
                  controller.currentInstance?.user != null) ...[
            const SizedBox(width: 8),
            TopicBookmarkButton(
              siteUrl: siteUrl!,
              topic: topic,
              busy: bookmarkBusy,
            ),
          ],
          if (topic case final topic? when siteUrl != null && isConnected) ...[
            SizedBox(
              width: controller.currentInstance?.user != null ? 4 : 8,
            ),
            TopicNotificationLevelButton(siteUrl: siteUrl!, topic: topic),
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
    return Container(
      key: const ValueKey('topic-sidebar-panel'),
      width: width,
      decoration: BoxDecoration(
        color: theme.shell.panel,
        border: Border(left: BorderSide(color: theme.shell.divider)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopicSidebarActions(
              siteUrl: siteUrl,
              topic: topic,
              route: route,
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
                        padding: const EdgeInsets.fromLTRB(14, 13, 14, 8),
                        child: Text(
                          'More topics',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _MoreTopics(
                        key: const ValueKey('topic-sidebar-more-topics-list'),
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
    );
  }
}

class _TopicSidebarActions extends StatelessWidget {
  const _TopicSidebarActions({
    required this.siteUrl,
    required this.topic,
    required this.route,
    required this.canReply,
    required this.registry,
    this.onCollapsed,
  });

  final String? siteUrl;
  final TopicDetail? topic;
  final ContentRoute? route;
  final bool canReply;
  final PluginRegistry registry;
  final VoidCallback? onCollapsed;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    final topic = this.topic;
    final siteUrl = this.siteUrl;
    final topicFlags = topic == null || siteUrl == null
        ? const <PostFlagType>[]
        : controller.availableTopicFlagTypes(siteUrl, topic);
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
        variant: DButtonVariant.primary,
        size: DButtonSize.small,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ((topic != null && (canReply || siteUrl != null)) ||
            onCollapsed != null)
          Row(
            children: [
              if (topic != null && canReply)
                Expanded(child: replyButton())
              else
                const Spacer(),
              if (topic != null && siteUrl != null) ...[
                const SizedBox(width: 4),
                TopicStatusButton(
                  siteUrl: siteUrl,
                  topic: topic,
                  route: route,
                  topicFlags: topicFlags,
                ),
              ],
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
      return _TopicSidebarCard(
        key: const ValueKey('topic-properties-card'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            children: [
              _TopicPropertyRow(
                key: const ValueKey('topic-sidebar-category-property'),
                label: 'Category',
                child: _TopicSidebarCategory(
                  label: category?.name ?? route?.subtitle ?? 'Uncategorized',
                  color: category == null
                      ? route?.color
                      : Color(category.colorValue),
                  onTap: topic.canEdit
                      ? () => unawaited(
                          _showTopicCategoryEditor(
                            context: context,
                            controller: controller,
                            siteUrl: siteUrl,
                            topic: topic,
                          ),
                        )
                      : null,
                ),
              ),
              TopicTagMenuAnchor(
                siteUrl: siteUrl,
                topicId: topic.id,
                categoryId: topic.categoryId,
                tags: topic.tags,
                enabled: topic.canEditTags,
                builder: (context, openMenu, saving) => _TopicPropertyRow(
                  key: const ValueKey('topic-sidebar-tags-property'),
                  label: 'Tags',
                  child: topic.tags.isEmpty
                      ? topic.canEditTags
                            ? _EditableEmptyTopicTags(
                                saving: saving,
                                onTap: openMenu,
                              )
                            : const _EmptyTopicProperty('No tags')
                      : Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final tag in topic.tags)
                              _TopicSidebarTag(tag: tag, onTap: openMenu),
                            if (saving)
                              const _TopicTagsSavingIndicator()
                            else if (topic.canEditTags)
                              _TopicTagsAddButton(onTap: openMenu),
                          ],
                        ),
                ),
              ),
              for (final section in pluginSections)
                _TopicPropertyRow(
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

class _TopicPropertyRow extends StatelessWidget {
  const _TopicPropertyRow({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 94,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _TopicSidebarCategory extends StatelessWidget {
  const _TopicSidebarCategory({
    required this.label,
    required this.color,
    this.onTap,
  });

  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = Row(
      key: const ValueKey('topic-sidebar-category'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const ValueKey('topic-sidebar-category-color'),
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color ?? theme.colorScheme.outline,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
    if (onTap == null) return category;
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: 'Edit topic category',
        child: InlineAction(
          key: const ValueKey('topic-sidebar-category-action'),
          onTap: onTap!,
          borderRadius: BorderRadius.circular(5),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: category,
          ),
        ),
      ),
    );
  }
}

Future<void> _showTopicCategoryEditor({
  required BuildContext context,
  required ShellController controller,
  required String siteUrl,
  required TopicDetail topic,
}) async {
  unawaited(controller.loadCategories(siteUrl));
  await showShellSheet<void>(
    context: context,
    title: 'Edit topic category',
    dialogOnDesktop: true,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    builder: (sheetContext) => _TopicCategoryEditor(
      controller: controller,
      siteUrl: siteUrl,
      topicId: topic.id,
      initialCategoryId: topic.categoryId,
      onSaved: () => Navigator.of(sheetContext).pop(),
    ),
  );
}

class _TopicCategoryEditor extends StatefulWidget {
  const _TopicCategoryEditor({
    required this.controller,
    required this.siteUrl,
    required this.topicId,
    required this.initialCategoryId,
    required this.onSaved,
  });

  final ShellController controller;
  final String siteUrl;
  final int topicId;
  final int? initialCategoryId;
  final VoidCallback onSaved;

  @override
  State<_TopicCategoryEditor> createState() => _TopicCategoryEditorState();
}

class _TopicCategoryEditorState extends State<_TopicCategoryEditor> {
  int? _categoryId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initialCategoryId;
  }

  Future<void> _save() async {
    final categoryId = _categoryId;
    if (_saving || categoryId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.controller.saveTopicCategory(
      siteUrl: widget.siteUrl,
      topicId: widget.topicId,
      categoryId: categoryId,
    );
    if (!mounted) return;
    if (error == null) {
      widget.onSaved();
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) =>
      ShellSelector<
        ({List<TopicCategory> categories, bool loaded, String? loadError})
      >(
        select: (controller) {
          final feed = controller.categoryFeedFor(widget.siteUrl);
          return (
            categories: controller.topicComposerCategories(widget.siteUrl),
            loaded: feed.loaded,
            loadError: feed.error,
          );
        },
        builder: (context, state, _) {
          final categories = _editableTopicCategories(state.categories);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!state.loaded && categories.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              else if (categories.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    state.loadError ?? 'No categories are available.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                RadioGroup<int>(
                  groupValue: _categoryId,
                  onChanged: _saving
                      ? (_) {}
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _categoryId = value;
                            _error = null;
                          });
                        },
                  child: Column(
                    children: [
                      for (final category in categories)
                        RadioListTile<int>(
                          key: ValueKey('topic-category-option-${category.id}'),
                          value: category.id,
                          contentPadding: EdgeInsets.only(
                            left: category.parentCategoryId == null ? 4 : 28,
                            right: 4,
                          ),
                          title: Row(
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: Color(category.colorValue),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(child: Text(category.name)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              if (_error case final error?) ...[
                const SizedBox(height: 8),
                Text(
                  error,
                  key: const ValueKey('topic-category-editor-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('topic-category-editor-save'),
                    onPressed:
                        !_saving &&
                            _categoryId != null &&
                            _categoryId != widget.initialCategoryId
                        ? () => unawaited(_save())
                        : null,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          );
        },
      );
}

List<TopicCategory> _editableTopicCategories(
  Iterable<TopicCategory> categories,
) {
  final permitted = categories.where((category) => category.canCreateTopic);
  final permittedIds = permitted.map((category) => category.id).toSet();
  final ordered = <TopicCategory>[];
  final visited = <int>{};

  void appendChildren(int? parentId) {
    final children =
        permitted
            .where(
              (category) => parentId == null
                  ? category.parentCategoryId == null ||
                        !permittedIds.contains(category.parentCategoryId)
                  : category.parentCategoryId == parentId,
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    for (final child in children) {
      if (!visited.add(child.id)) continue;
      ordered.add(child);
      appendChildren(child.id);
    }
  }

  appendChildren(null);
  return ordered;
}

class _TopicSidebarTag extends StatelessWidget {
  const _TopicSidebarTag({required this.tag, this.onTap});

  final TopicTag tag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = StadiumBorder(
      side: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    final pill = Material(
      key: ValueKey(('topic-sidebar-tag', tag.name)),
      color: theme.colorScheme.surfaceContainerHigh,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        mouseCursor: onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        customBorder: shape,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              tag.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
    return onTap == null
        ? pill
        : Tooltip(message: 'Edit topic tags', child: pill);
  }
}

class _EditableEmptyTopicTags extends StatelessWidget {
  const _EditableEmptyTopicTags({required this.saving, required this.onTap});

  final bool saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    const shape = StadiumBorder();
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Tooltip(
          message: saving ? 'Saving topic tags' : 'Add tag',
          child: Material(
            color: theme.colorScheme.surfaceContainerHigh,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('topic-sidebar-add-tag'),
              onTap: onTap,
              mouseCursor: onTap == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              customBorder: shape,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (saving)
                      const SizedBox.square(
                        dimension: 11,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    else
                      DIcon(DIcons.tag, size: 11, color: color),
                    const SizedBox(width: 4),
                    Text(
                      saving ? 'Saving…' : 'Add tag',
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicTagsAddButton extends StatelessWidget {
  const _TopicTagsAddButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Add tag',
    child: Material(
      type: MaterialType.transparency,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('topic-sidebar-add-tag'),
        onTap: onTap,
        mouseCursor: onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: DIcon(
            DIcons.plus,
            key: const ValueKey('topic-sidebar-tags-edit-indicator'),
            size: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ),
  );
}

class _TopicTagsSavingIndicator extends StatelessWidget {
  const _TopicTagsSavingIndicator();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 13,
    child: CircularProgressIndicator(strokeWidth: 1.5),
  );
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

/// A topic-list-shaped placeholder for the payload attached to the final post
/// window. The enclosing panel owns the stable width; this owns only the
/// loading affordance, so a failed page can stop pulsing without resizing the
/// post column.
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

/// Core's more-topics footer, populated by core and installed source
/// contributions.
///
/// The reader's source choice is remembered per forum, so it is owned by the
/// topic view rather than by this widget, which a new topic rebuilds.
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

  /// A remembered choice only holds while that source has topics. A missing
  /// plugin or an empty contribution falls back to the first populated source
  /// in registry order rather than showing an empty tab.
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
    final hasTabs = available.length > 1;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: 16),
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
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  if (selection.definition.icon case final icon?) ...[
                    DIcon(
                      icon,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(selection.label, style: theme.textTheme.titleSmall),
                ],
              ),
            ),
          for (var index = 0; index < selection.topics.length; index++) ...[
            TopicListRow(topic: selection.topics[index], siteUrl: siteUrl),
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

/// A post together with the calendar boundary immediately above it.
///
/// Keeping both in one logical list item is important: all topic paging,
/// viewport receipts, and restoration address posts, not decorative rows.
class _TopicPostItem extends StatelessWidget {
  const _TopicPostItem({
    super.key,
    required this.postId,
    required this.day,
    required this.timeGapDays,
    required this.hideDay,
    required this.onDayTap,
    required this.gapBefore,
    required this.gapAfter,
    required this.expandGapBefore,
    required this.expandGapAfter,
    required this.child,
  });

  final int postId;
  final DateTime? day;
  final int? timeGapDays;
  final bool hideDay;
  final VoidCallback? onDayTap;
  final List<int> gapBefore;
  final List<int> gapAfter;
  final Future<void> Function() expandGapBefore;
  final Future<void> Function() expandGapAfter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final day = this.day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (gapBefore.isNotEmpty)
          _PostGap(
            key: const ValueKey('post-gap-before'),
            count: gapBefore.length,
            onExpand: expandGapBefore,
          ),
        if (day != null)
          IgnorePointer(
            ignoring: hideDay,
            child: Opacity(
              opacity: hideDay ? 0 : 1,
              child: StreamDaySeparator(
                key: ValueKey(('topic-day', day)),
                day: day,
                onTap: onDayTap!,
              ),
            ),
          ),
        if (timeGapDays case final daysSince?)
          TimeGapNotice(
            key: ValueKey(('topic-time-gap', postId)),
            daysSince: daysSince,
          ),
        child,
        if (gapAfter.isNotEmpty)
          _PostGap(
            key: const ValueKey('post-gap-after'),
            count: gapAfter.length,
            onExpand: expandGapAfter,
          ),
      ],
    );
  }
}

/// Core's explicit affordance for posts omitted from the ordinary stream.
///
/// The server supplies both the ids and their placement. A gap is therefore
/// not an authorization guess: if it is here, the reader may ask to reveal it.
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

    // Transparent rather than [ShellColors.content] for ordinary posts, so the
    // tile takes whichever surface the column it is in happens to paint.
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
                        // Only the people who can undo a deletion are shown
                        // one at all, so saying so is worth the room.
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

/// The internal topics which link back to this post.
///
/// Core shows five until explicitly expanded and collapses duplicate titles,
/// since two posts in the same source topic otherwise produce identical rows.
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
                      child: Text(
                        link.title,
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

/// Core's compact topic map beneath the opening post.
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
              if (topic.hasSummary)
                OutlinedButton.icon(
                  key: const ValueKey('topic-summary-button'),
                  onPressed: summaryLoading
                      ? null
                      : () => unawaited(_toggleSummary(context)),
                  icon: summaryLoading
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        )
                      : DIcon(
                          summary ? DIcons.list : DIcons.layerGroup,
                          size: 14,
                        ),
                  label: Text(summary ? 'Show all' : 'Summarize'),
                ),
              ...pluginActions,
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

/// A compact continuation of the post stream while an adjacent page loads.
///
/// The single-line, footerless shape is exactly the minimum real-post height.
/// A short final page can therefore replace it without shrinking the list and
/// forcing a bottom-anchored reader back into posts they already passed.
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
