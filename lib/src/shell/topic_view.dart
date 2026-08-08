import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../models/post.dart';
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
import 'user_card.dart';

/// A topic and its posts.
class TopicView extends StatefulWidget {
  const TopicView({super.key});

  /// Start fetching the next batch about a screen before the end.
  static const double _loadMoreThreshold = 900;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrent(controller, identity)) return;
      _jumpTo(index);
      // The first jump uses estimates for posts that have not been laid out.
      // Repeat once their real heights are known so the requested post lands
      // at the top rather than merely somewhere near it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isCurrent(controller, identity)) return;
        _jumpTo(index);
        _restoring = false;
        _scheduleLook();
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

    // Which posts are on screen, and in what order. The posts themselves are
    // in the store; each tile watches its own, so an edit or a deletion redraws
    // one tile rather than walking the whole stream.
    final postIds = snapshot.postIds;
    final siteUrl = snapshot.siteUrl!;
    final topicIdentity = (siteUrl, snapshot.topicId!);
    _syncControllers(controller, topicIdentity);
    _restoreInitialPost(controller, snapshot);
    _scheduleLook();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) {
          // SuperSliverList publishes its new visible range during layout,
          // after the scroll notification. Looking synchronously here reads
          // the previous viewport and repeatedly credits the old post.
          _scheduleLook();
          if (notification.metrics.extentAfter < TopicView._loadMoreThreshold) {
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
        // Lazy, like the topic list: a 500-post topic builds only what shows.
        itemCount: postIds.length + (showHeader ? 1 : 0) + (showFooter ? 1 : 0),
        separatorBuilder: (context, _) =>
            Divider(height: 1, color: theme.shell.divider),
        itemBuilder: (context, index) {
          if (showHeader && index == 0) {
            return _EarlierPostsRow(
              loading: snapshot.loadingEarlier,
              onPressed: controller.loadEarlierPosts,
            );
          }

          final postIndex = index - (showHeader ? 1 : 0);
          if (postIndex >= postIds.length) {
            return const _LoadingPostsRow();
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
    required this.siteUrl,
    required this.postIds,
    required this.loading,
    required this.loadingMore,
    required this.loadingEarlier,
    required this.hasMore,
    required this.hasEarlier,
    required this.initialPostIndex,
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
      siteUrl: siteUrl,
      postIds: postIds,
      loading: controller.currentTopicLoading,
      loadingMore: controller.loadingMorePosts,
      loadingEarlier: controller.loadingEarlierPosts,
      hasMore: controller.currentTopicHasMore,
      hasEarlier: hasEarlier,
      initialPostIndex: initialPostIndex,
    );
  }

  final int? topicId;
  final String? siteUrl;
  final List<int> postIds;
  final bool loading;
  final bool loadingMore;
  final bool loadingEarlier;
  final bool hasMore;
  final bool hasEarlier;
  final int? initialPostIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TopicViewSnapshot &&
          topicId == other.topicId &&
          siteUrl == other.siteUrl &&
          listEquals(postIds, other.postIds) &&
          loading == other.loading &&
          loadingMore == other.loadingMore &&
          loadingEarlier == other.loadingEarlier &&
          hasMore == other.hasMore &&
          hasEarlier == other.hasEarlier &&
          initialPostIndex == other.initialPostIndex;

  @override
  int get hashCode => Object.hash(
    topicId,
    siteUrl,
    Object.hashAll(postIds),
    loading,
    loadingMore,
    loadingEarlier,
    hasMore,
    hasEarlier,
    initialPostIndex,
  );
}

class _EarlierPostsRow extends StatelessWidget {
  const _EarlierPostsRow({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Center(
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              onPressed: onPressed,
              child: const Text('Load earlier posts'),
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
  const _StoredPost({super.key, required this.siteUrl, required this.postId});

  final String siteUrl;
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
            : _PostTile(siteUrl: siteUrl, post: post);
      },
    );
  }
}

class _PostTile extends StatefulWidget {
  const _PostTile({required this.siteUrl, required this.post});

  final String siteUrl;
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
