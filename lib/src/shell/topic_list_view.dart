import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../models/discourse_instance.dart';
import '../models/topic.dart';
import '../models/topic_feed.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_activity_indicator.dart';
import 'avatar_image.dart';
import 'content_reading_lane.dart';
import 'inline_action.dart';
import 'list_boundary_shortcuts.dart';
import 'loading_skeleton.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_title.dart';

class TopicListView extends StatefulWidget {
  const TopicListView({super.key, required this.feed});

  final TopicFeed feed;

  @override
  State<TopicListView> createState() => _TopicListViewState();
}

class _TopicListViewState extends State<TopicListView> {
  ScrollController? _scroll;
  ListController? _list;
  (String?, String?, String)? _feedIdentity;
  Object? _loadMoreToken;
  bool _restored = false;
  int _boundaryJumpRevision = 0;

  ShellController? _controller;

  void _syncControllers((String?, String?, String) feedIdentity) {
    if (_feedIdentity == feedIdentity) return;

    _disposeControllers();
    _feedIdentity = feedIdentity;
    _loadMoreToken = null;
    _restored = false;
    _scroll = ScrollController();
    _list = ListController();
  }

  void _restore(
    ShellController controller,
    String destination,
    (String?, String?, String) feedIdentity,
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
    if (scroll == null && list == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scroll?.dispose();
      list?.dispose();
    });
  }

  @override
  void dispose() {
    // Rows are handed to the shell as they change, but the latest may still
    // be waiting out its debounce window. The torn-down list cannot move it
    // any more, so it is written now.
    _controller?.flushAnchorPersist();
    _disposeControllers();
    super.dispose();
  }

  Future<void> _showIncoming(
    ShellController controller,
    String destination,
    (String?, String?, String) feedIdentity,
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
    (String?, String?, String) feedIdentity,
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
    (String?, String?, String) feedIdentity,
  ) =>
      mounted &&
      _feedIdentity == feedIdentity &&
      _currentFeedIdentity(controller) == feedIdentity;

  static (String?, String?, String) _currentFeedIdentity(
    ShellController controller,
  ) {
    final siteUrl = controller.currentInstance?.url;
    final destination = controller.currentFeedId ?? 'latest';
    return (siteUrl, controller.activeTabId, destination);
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
        Expanded(child: _body(controller, destination, feedIdentity)),
      ],
    );
  }

  Widget _body(
    ShellController controller,
    String destination,
    (String?, String?, String) feedIdentity,
  ) {
    final feed = widget.feed;

    if (feed.loading && feed.topicIds.isEmpty) {
      return ContentReadingLaneBox(
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
      return const _Message(icon: DIcons.inbox, text: 'Nothing here yet.');
    }

    _syncControllers(feedIdentity);
    _restore(controller, destination, feedIdentity);

    return Column(
      children: [
        if (feed.loading)
          const LinearProgressIndicator(
            key: ValueKey('topic-feed-refresh-progress'),
            minHeight: 2,
          ),
        if (feed.error case final error? when !feed.pageError)
          _FeedErrorBanner(
            key: const ValueKey('topic-feed-refresh-error'),
            message: error,
            onRetry: () => unawaited(controller.loadFeed(destination)),
          ),
        Expanded(
          child: ContentReadingLane(
            basePadding: const EdgeInsets.symmetric(vertical: 4),
            builder: (context, lane) =>
                NotificationListener<ScrollNotification>(
                  // Fetching on a scroll notification rather than from
                  // itemBuilder keeps the request off the hot path of building
                  // rows. Both paths coalesce through a post-frame callback
                  // because a viewport can emit a scroll notification while
                  // applying new content dimensions during layout.
                  onNotification: (notification) {
                    if (notification.depth != 0) return false;
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
                    return false;
                  },
                  // SuperListView preserves measured heights for variably sized
                  // rows.
                  child: ListBoundaryShortcuts(
                    key: ValueKey(('topic-list-boundary', feedIdentity)),
                    debugLabel: 'topic list',
                    initiallyActive: true,
                    onStart: () => _jumpToBoundary(end: false),
                    onEnd: () => _jumpToBoundary(end: true),
                    child: SuperListView.separated(
                      // Switching destinations swaps the controller, so the
                      // scrollable has to be a new one rather than re-attached
                      // to a different controller.
                      key: ValueKey(feedIdentity),
                      controller: _scroll,
                      listController: _list,
                      padding: lane.padding,
                      itemCount:
                          feed.topicIds.length +
                          (feed.loadingMore || feed.pageError ? 1 : 0),
                      separatorBuilder: (context, _) => Divider(
                        height: 1,
                        color: Theme.of(context).shell.divider,
                      ),
                      itemBuilder: (context, index) {
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
                        return _TopicRow(
                          key: ValueKey(topicId),
                          topicId: topicId,
                        );
                      },
                    ),
                  ),
                ),
          ),
        ),
      ],
    );
  }

  static const double _loadMoreThreshold = 800;
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
    final divider = Theme.of(context).shell.divider;

    return LoadingSkeleton(
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
                    if (index > 0) Divider(height: 1, color: divider),
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
    0 => const _TopicListSkeletonRow(
      titleWidth: 0.72,
      metadataWidth: 0.64,
      posterCount: 3,
    ),
    1 => const _TopicListSkeletonRow(
      titleWidth: 0.88,
      secondTitleWidth: 0.42,
      metadataWidth: 0.52,
      posterCount: 2,
    ),
    2 => const _TopicListSkeletonRow(
      titleWidth: 0.56,
      metadataWidth: 0.72,
      posterCount: 1,
    ),
    3 => const _TopicListSkeletonRow(
      titleWidth: 0.82,
      metadataWidth: 0.48,
      posterCount: 3,
    ),
    _ => const Opacity(
      opacity: 0.72,
      child: _TopicListSkeletonRow(
        titleWidth: 0.66,
        secondTitleWidth: 0.32,
        metadataWidth: 0.58,
        posterCount: 2,
      ),
    ),
  };
}

class _TopicListSkeletonRow extends StatelessWidget {
  const _TopicListSkeletonRow({
    required this.titleWidth,
    this.secondTitleWidth,
    required this.metadataWidth,
    required this.posterCount,
  });

  final double titleWidth;
  final double? secondTitleWidth;
  final double metadataWidth;
  final int posterCount;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonLine(widthFactor: titleWidth, height: 11),
                if (secondTitleWidth case final secondTitleWidth?) ...[
                  const SizedBox(height: 7),
                  _SkeletonLine(widthFactor: secondTitleWidth, height: 11),
                ],
                const SizedBox(height: 8),
                _SkeletonLine(widthFactor: metadataWidth, height: 8),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _TopicListSkeletonPosters(count: posterCount),
        ],
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: TopicListRow.minimumHeight),
      child: row,
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
      child: LoadingSkeletonBlock(height: height),
    ),
  );
}

class _TopicListSkeletonPosters extends StatelessWidget {
  const _TopicListSkeletonPosters({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24.0 + (count - 1) * 16,
      height: 24,
      child: Stack(
        children: [
          for (var index = 0; index < count; index++)
            Positioned(
              left: index * 16,
              child: const LoadingSkeletonBlock.circle(diameter: 24),
            ),
        ],
      ),
    );
  }
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
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onPrimaryContainer;

    // Its own Material: the ink has to splash on the banner rather than on the
    // content surface underneath it, which is a different colour.
    return Material(
      color: theme.colorScheme.primaryContainer,
      child: InkWell(
        onTap: loading ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.shell.divider)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: AdaptiveActivityIndicator(
                    color: foreground,
                    cupertinoRadius: 7,
                    materialStrokeWidth: 2,
                  ),
                )
              else
                DIcon(DIcons.arrowUp, size: 14, color: foreground),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                  ),
                ),
              ),
            ],
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
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator.adaptive(strokeWidth: 2),
      ),
    ),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        color: theme.colorScheme.errorContainer,
        child: Row(
          children: [
            DIcon(
              DIcons.triangleExclamation,
              size: 17,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(message)),
            DButton(
              key: const ValueKey('topic-feed-error-retry'),
              label: const Text('Retry'),
              onPressed: onRetry,
              variant: DButtonVariant.link,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({super.key, required this.topicId});

  final int topicId;

  @override
  Widget build(BuildContext context) {
    return ShellSelector<String?>(
      select: (controller) => controller.currentInstance?.url,
      builder: (context, siteUrl, _) {
        if (siteUrl == null) return const SizedBox.shrink();
        final controller = ShellScope.read(context);

        return ValueListenableBuilder<Topic?>(
          valueListenable: controller.topicRef(siteUrl, topicId),
          builder: (context, topic, _) => topic == null
              // The id is in a list, so the topic was stored with it. A gap
              // here means the site was just disconnected and this list is
              // one frame from being torn down.
              ? const SizedBox.shrink()
              : ShellSelector<TopicCategory?>(
                  select: (controller) => controller.categoryFor(
                    topic.categoryId,
                    siteUrl: siteUrl,
                  ),
                  builder: (context, category, _) => _TopicRowBody(
                    topic: topic,
                    category: category,
                    siteUrl: siteUrl,
                    onTap: () => controller.openTopic(topic),
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
  }) : assert(forum == null || siteUrl == null);

  static const double minimumHeight = 68;

  final Topic topic;
  final DiscourseInstance? forum;

  final String? siteUrl;
  final VoidCallback? onTap;

  final TextStyle? titleStyle;

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
    final controller = ShellScope.read(context);
    return ShellSelector<TopicCategory?>(
      select: (controller) =>
          controller.categoryFor(topic.categoryId, siteUrl: siteUrl),
      builder: (context, category, _) => _TopicRowBody(
        topic: topic,
        category: category,
        siteUrl: siteUrl,
        forum: owningForum,
        onTap: onTap ?? () => controller.openTopic(topic),
        titleStyle: titleStyle,
      ),
    );
  }
}

typedef _TopicListSnapshot = ({
  (String?, String?, String) feedIdentity,
  String destination,
  int incoming,
});

_TopicListSnapshot _topicListSnapshot(ShellController controller) {
  // Not `destinationId`: a category or tag list opened from a hashtag is a
  // feed of its own, sitting over whichever sidebar entry is still selected.
  final destination = controller.currentFeedId ?? 'latest';
  return (
    feedIdentity: _TopicListViewState._currentFeedIdentity(controller),
    destination: destination,
    incoming: controller.incomingCount(destination),
  );
}

class _TopicRowBody extends StatelessWidget {
  const _TopicRowBody({
    required this.topic,
    required this.category,
    required this.siteUrl,
    required this.onTap,
    this.forum,
    this.titleStyle,
  });

  final Topic topic;
  final TopicCategory? category;
  final String siteUrl;
  final VoidCallback onTap;
  final DiscourseInstance? forum;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);
    final effectiveTitleStyle = titleStyle ?? theme.textTheme.titleMedium;

    final row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (forum case final forum?) ...[
              Padding(
                padding: const EdgeInsets.only(right: 12, top: 1),
                child: Semantics(
                  label: forum.title,
                  image: true,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: AvatarImage(
                      url: forum.iconUrl,
                      size: 28,
                      fit: BoxFit.contain,
                      fallback: ColoredBox(
                        color: forum.accentColor.withValues(alpha: 0.16),
                        child: SizedBox.square(
                          dimension: 28,
                          child: Center(
                            child: Text(
                              forum.monogram,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w800,
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (topic.closed)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: DIcon(
                            DIcons.lock,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                            semanticLabel: 'Closed topic',
                          ),
                        ),
                      if (topic.pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: DIcon(
                            DIcons.thumbtack,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (topic.bookmarked)
                        Semantics(
                          label: 'Bookmarked',
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: DIcon(
                              DIcons.bookmark,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      Flexible(
                        child: TopicTitle(
                          topic.title,
                          siteUrl: siteUrl,
                          trailing: [
                            if (topic.showUnreadCount) ...[
                              const SizedBox(width: 8),
                              _UnreadPill(count: topic.unreadCount),
                            ],
                            if (topic.showNewTopicDot) ...[
                              const SizedBox(width: 8),
                              const _TopicStateDot(
                                key: ValueKey('new-topic-dot'),
                                label: 'New topic',
                              ),
                            ],
                            if (topic.showNewRepliesDot) ...[
                              const SizedBox(width: 8),
                              const _TopicStateDot(
                                key: ValueKey('new-replies-dot'),
                                label: 'Topic has new replies',
                              ),
                            ],
                          ],
                          style: effectiveTitleStyle?.copyWith(
                            // Core dims only rows whose last visible post has
                            // been read. Tracking level controls the badge, not
                            // the title treatment.
                            color: topic.visited
                                ? theme.discourse.whisper
                                : theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    runSpacing: 0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (forum case final forum?)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(
                            forum.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (category case final category?)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: _CategoryBadge(
                            category: category,
                            onTap: () => controller.openCategory(
                              category,
                              siteUrl: siteUrl,
                            ),
                          ),
                        ),
                      for (var index = 0; index < topic.tags.length; index++)
                        _TopicTag(
                          tag: topic.tags[index],
                          onTap: () => controller.openTopicTag(
                            topic.tags[index],
                            siteUrl: siteUrl,
                            privateMessage: topic.privateMessage,
                          ),
                          hasComma: index < topic.tags.length - 1,
                          trailingSpacing: index < topic.tags.length - 1
                              ? 3
                              : 10,
                        ),
                      for (final metadata
                          in (PluginScope.maybeOf(context)?.registry ??
                                  PluginRegistry.empty)
                              .topicListMetadata(context, siteUrl, topic))
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: metadata,
                        ),
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _Stat(
                          icon: DIcons.reply,
                          value: topic.replyCount,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          right: topic.bumpedAt == null ? 0 : 10,
                        ),
                        child: _Stat(icon: DIcons.farEye, value: topic.views),
                      ),
                      if (topic.bumpedAt case final bumpedAt?)
                        Text(
                          relativeTime(bumpedAt),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _Posters(avatars: topic.posterAvatars),
          ],
        ),
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: TopicListRow.minimumHeight),
      child: row,
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category, required this.onTap});

  final TopicCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InlineAction.link(
      onTap: onTap,
      semanticLabel: 'Category: ${category.name}',
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 32, minHeight: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: Color(category.colorValue),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 5),
            // Same 200px cap as a tag, and flexible on top of it: a category
            // name long enough to fill the metadata row must ellipsize, not
            // overflow.
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  category.name,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicTag extends StatelessWidget {
  const _TopicTag({
    required this.tag,
    required this.onTap,
    required this.hasComma,
    required this.trailingSpacing,
  });

  final TopicTag tag;
  final VoidCallback onTap;
  final bool hasComma;
  final double trailingSpacing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: EdgeInsets.only(right: trailingSpacing),
      child: InlineAction.link(
        onTap: onTap,
        semanticLabel: 'Tag: ${tag.name}',
        excludeChildSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 32, minHeight: 24),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                '${tag.name}${hasComma ? ',' : ''}',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value});

  final DIconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DIcon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          _short(value),
          style: theme.textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }

  static String _short(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}m';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return '$value';
  }
}

class _Posters extends StatelessWidget {
  const _Posters({required this.avatars});

  final List<String> avatars;

  @override
  Widget build(BuildContext context) {
    final shown = avatars.take(3).toList();
    if (shown.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: 24.0 + (shown.length - 1) * 16,
      height: 24,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 16,
              child: ClipOval(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: AvatarImage(
                    url: shown[i],
                    size: 24,
                    fallback: ColoredBox(
                      color: Theme.of(context).shell.floating,
                      child: DIcon(
                        DIcons.user,
                        size: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TopicStateDot extends StatelessWidget {
  const _TopicStateDot({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    child: Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DIcon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel case final label?) ...[
              const SizedBox(height: 8),
              DButton(
                key: const ValueKey('topic-feed-initial-retry'),
                label: Text(label),
                onPressed: onAction,
                variant: DButtonVariant.link,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
