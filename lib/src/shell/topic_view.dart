import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../models/post.dart';
import '../models/topic.dart';
import '../plugins/site_plugin.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'cooked_html.dart';
import 'post_actions.dart';
import 'post_footer.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'small_action.dart';
import 'topic_list_view.dart';
import 'user_card.dart';

/// A topic and its posts.
class TopicView extends StatefulWidget {
  const TopicView({super.key});

  /// Start fetching the next batch about a screen before either end.
  static const double _loadPostsThreshold = 900;

  @override
  State<TopicView> createState() => _TopicViewState();
}

class _TopicViewState extends State<TopicView> {
  static const Duration _readInterval = Duration(milliseconds: 500);

  ScrollController? _scroll;
  ListController? _list;
  (String, int)? _topicIdentity;
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
  Timer? _readTimer;
  ({String siteUrl, int topicId, int postNumber, bool caughtUp})? _seen;

  void _syncControllers(
    ShellController controller,
    (String, int) topicIdentity,
  ) {
    if (_topicIdentity == topicIdentity && identical(_controller, controller)) {
      return;
    }

    _creditReaderNow();
    _disposeControllers();
    _controller = controller;
    _topicIdentity = topicIdentity;
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
    _seen = null;
    _scroll = ScrollController();
    _list = ListController();
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
      if (controller.currentContent?.postNumber == null) _restored = true;
      return;
    }
    _restored = true;
    if (index <= 0) return;
    final identity = (snapshot.siteUrl!, snapshot.topicId!);
    _restoring = true;

    void jumpToTarget() {
      if (!_isCurrent(controller, identity)) return;
      final currentIndex = _TopicViewSnapshot.from(controller).initialPostIndex;
      if (currentIndex != null) _jumpTo(currentIndex);
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

  void _jumpTo(int index) {
    final list = _list;
    final scroll = _scroll;
    if (list == null || scroll == null) return;
    if (!list.isAttached || !scroll.hasClients) return;
    // `separated` interleaves a separator after every logical item, and the
    // ListController addresses that expanded child list.
    list.jumpToItem(index: index * 2, scrollController: scroll, alignment: 0);
  }

  bool _isCurrent(ShellController controller, (String, int) topicIdentity) =>
      mounted &&
      _topicIdentity == topicIdentity &&
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
    _creditReaderNow();
    _disposeControllers();
    super.dispose();
  }

  /// Measures the viewport after layout. This also covers short topics that
  /// never produce a scroll notification at all.
  void _scheduleLook() {
    if (_lookScheduled) return;
    _lookScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lookScheduled = false;
      final controller = _controller;
      final identity = _topicIdentity;
      if (controller == null || identity == null) return;
      if (!_isCurrent(controller, identity)) return;
      _noteWhatIsOnScreen(controller, _TopicViewSnapshot.from(controller));
    });
  }

  /// Remembers the farthest real post currently visible, then waits for the
  /// reader to pause. Debouncing the viewport rather than the request avoids a
  /// receipt for every pixel of a fling.
  void _noteWhatIsOnScreen(
    ShellController controller,
    _TopicViewSnapshot snapshot,
  ) {
    if (!_restored || _restoring || _list?.isAttached != true) return;
    final range = _list!.visibleRange;
    if (range == null) return;

    final leading = snapshot.hasEarlier || snapshot.loadingEarlier ? 1 : 0;
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

  double _offsetBeforeChild(ListController list, int childIndex) {
    var offset = 0.0;
    for (var index = 0; index < childIndex; index++) {
      offset += list.extentForIndex(index).$1;
    }
    return offset;
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

    final target = (siteUrl, topicId, snapshot.postIds.length);
    if (_loadMoreToken != null && _loadMoreTarget == target) return;

    final token = Object();
    _loadMoreToken = token;
    _loadMoreTarget = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_loadMoreToken, token)) {
        _loadMoreToken = null;
        _loadMoreTarget = null;
      }
      if (!mounted) return;
      if (!identical(ShellScope.read(context), controller)) return;
      if (_TopicViewSnapshot.from(controller) != snapshot) return;
      unawaited(controller.loadMorePosts());
    });
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
    if (_loadEarlierToken != null || snapshot.loadingEarlier) return;
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
        return const Center(child: CircularProgressIndicator());
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

    // Which posts are on screen, and in what order. The posts themselves are
    // in the store; each tile watches its own, so an edit or a deletion redraws
    // one tile rather than walking the whole stream.
    final postIds = snapshot.postIds;
    final siteUrl = snapshot.siteUrl!;
    final topicIdentity = (siteUrl, snapshot.topicId!);
    _syncControllers(controller, topicIdentity);
    _restoreInitialPost(controller, snapshot);
    _restoreViewportAfterPrepend(controller, snapshot, hasHeader: showHeader);
    _scheduleLook();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) {
          // SuperSliverList publishes its new visible range during layout,
          // after the scroll notification. Looking synchronously here reads
          // the previous viewport and repeatedly credits the old post.
          _scheduleLook();
          // A failed page stays suppressed through the rebuild it causes, so
          // it cannot retry in a tight loop. A fresh scroll deliberately
          // re-arms that same page, including when the pane is too short to
          // ever leave the threshold.
          if (notification is ScrollStartNotification && !_restoring) {
            _allowLoadEarlierRetry(snapshot);
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
        // top, both to fetch and to retry an earlier page.
        physics: const AlwaysScrollableScrollPhysics(),
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
            (showRecommendations ? 1 : 0),
        separatorBuilder: (context, _) =>
            Divider(height: 1, color: theme.shell.divider),
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
            );
          }

          // Building the last post means the end is in view. Scrolling alone
          // is not enough: twenty short posts may not fill the window, leaving
          // nothing to scroll and the rest never fetched.
          if (postIndex == postIds.length - 1 && snapshot.hasMore) {
            _scheduleLoadMore(controller, snapshot);
          }
          final postId = postIds[postIndex];
          return _StoredPost(
            key: ValueKey(postId),
            siteUrl: siteUrl,
            topic: snapshot.topic!,
            postId: postId,
          );
        },
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
    final target = controller.currentContent?.postNumber;
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
          initialPostIndex == other.initialPostIndex &&
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
    initialPostIndex,
    recommendations,
    canAssignLegacyTargets,
  );
}

enum _MoreTopicsTab { suggested, related }

/// Core's more-topics footer. Suggested topics are always a core feature;
/// related topics appear when discourse-ai's semantic recommendations are on.
class _MoreTopics extends StatefulWidget {
  const _MoreTopics({super.key, required this.recommendations});

  final TopicRecommendations recommendations;

  @override
  State<_MoreTopics> createState() => _MoreTopicsState();
}

class _MoreTopicsState extends State<_MoreTopics> {
  _MoreTopicsTab _selected = _MoreTopicsTab.suggested;

  _MoreTopicsTab get _effectiveSelection {
    if (_selected == _MoreTopicsTab.suggested &&
        widget.recommendations.suggested.isNotEmpty) {
      return _MoreTopicsTab.suggested;
    }
    if (widget.recommendations.related.isNotEmpty) {
      return _MoreTopicsTab.related;
    }
    return _MoreTopicsTab.suggested;
  }

  @override
  Widget build(BuildContext context) {
    final suggested = widget.recommendations.suggested.isNotEmpty;
    final related = widget.recommendations.related.isNotEmpty;
    final hasTabs = suggested && related;
    final selection = _effectiveSelection;
    final topics = switch (selection) {
      _MoreTopicsTab.suggested => widget.recommendations.suggested,
      _MoreTopicsTab.related => widget.recommendations.related,
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
                  _MoreTopicsTabButton(
                    key: const ValueKey('suggested-topics-tab'),
                    label: 'Suggested',
                    selected: selection == _MoreTopicsTab.suggested,
                    onPressed: () =>
                        setState(() => _selected = _MoreTopicsTab.suggested),
                  ),
                  _MoreTopicsTabButton(
                    key: const ValueKey('related-topics-tab'),
                    label: 'Related',
                    icon: DIcons.discourseSparkles,
                    selected: selection == _MoreTopicsTab.related,
                    onPressed: () =>
                        setState(() => _selected = _MoreTopicsTab.related),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon case final icon?) ...[
                DIcon(icon, size: 13, color: color),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
            ],
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: loading ? const CircularProgressIndicator(strokeWidth: 2) : null,
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
    super.key,
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
                                  fontWeight: FontWeight.w600,
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
                                style: theme.textTheme.labelSmall?.copyWith(
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
                    if (post.createdAt case final createdAt?)
                      Text(
                        relativeTime(createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                CookedHtml(
                  html: post.cooked,
                  textStyle: theme.textTheme.bodyMedium,
                  siteUrl: widget.siteUrl,
                  post: post,
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
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
