import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../models/topic.dart';
import '../models/topic_feed.dart';
import '../theme/app_theme.dart';
import 'avatar_image.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

/// The first real screen: a list of topics from the site.
class TopicListView extends StatefulWidget {
  const TopicListView({super.key, required this.feed});

  final TopicFeed feed;

  @override
  State<TopicListView> createState() => _TopicListViewState();
}

class _TopicListViewState extends State<TopicListView> {
  ScrollController? _scroll;
  ListController? _list;
  String? _destination;
  bool _restored = false;

  /// Rebuilds the scroll controllers when the list underneath them changes, so
  /// each destination starts at its own remembered row rather than inheriting
  /// the previous one's.
  void _syncControllers(String destination) {
    if (_destination == destination) return;

    _disposeControllers();
    _destination = destination;
    _restored = false;
    _scroll = ScrollController();
    _list = ListController();
  }

  /// Puts the row the user left at the top of the viewport, once there is a
  /// laid-out list to jump within.
  void _restore(ShellController controller, String destination) {
    if (_restored) return;
    _restored = true;

    final row = controller.feedScrollRow(destination);
    if (row <= 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _destination != destination) return;
      _jumpTo(row);
      // The first jump was measured against estimated heights for rows that
      // had never been built. Now that the real ones are laid out, land on the
      // same row again.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _destination != destination) return;
        _jumpTo(row);
      });
    });
  }

  void _jumpTo(int row) {
    final list = _list;
    final scroll = _scroll;
    if (list == null || scroll == null) return;
    if (!list.isAttached || !scroll.hasClients) return;

    list.jumpToItem(index: row, scrollController: scroll, alignment: 0);
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
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = widget.feed;

    if (feed.loading && feed.topics.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (feed.error case final error?) {
      return _Message(icon: Icons.cloud_off, text: error);
    }
    if (feed.isEmpty) {
      return const _Message(
        icon: Icons.inbox_outlined,
        text: 'Nothing here yet.',
      );
    }

    final controller = ShellScope.of(context);
    final destination = controller.destinationId ?? 'latest';
    _syncControllers(destination);
    _restore(controller, destination);

    return RefreshIndicator(
      onRefresh: () => controller.loadFeed(destination, force: true),
      child: NotificationListener<ScrollNotification>(
        // Fetching on a scroll notification rather than from itemBuilder keeps
        // the request out of the build phase.
        onNotification: (notification) {
          // Opening a topic tears this list down, so the position has to be
          // handed to the controller as it changes rather than on dispose.
          if (notification.depth == 0 && _list?.isAttached == true) {
            if (_list!.visibleRange case final range?) {
              controller.saveFeedScrollRow(destination, range.$1);
            }
          }
          if (notification.metrics.extentAfter < _loadMoreThreshold) {
            controller.loadMoreFeed(destination);
          }
          return false;
        },
        // Titles wrap to one line or two, so a plain ListView's average-based
        // guess at the unbuilt rows drifts as you scroll and the scrollbar
        // thumb slides with it. SuperListView remembers each row's measured
        // height instead. See TopicView, where the same problem is severe.
        child: SuperListView.separated(
          // Switching destinations swaps the controller, so the scrollable has
          // to be a new one rather than re-attached to a different controller.
          key: ValueKey(destination),
          controller: _scroll,
          listController: _list,
          padding: const EdgeInsets.symmetric(vertical: 4),
          // Still builds lazily through a SliverChildBuilderDelegate, so only
          // rows near the viewport exist — a list of thousands costs the same
          // as a list of thirty.
          // Spinner only while fetching; see TopicView for why.
          itemCount: feed.topics.length + (feed.loadingMore ? 1 : 0),
          separatorBuilder: (context, _) =>
              Divider(height: 1, color: Theme.of(context).shell.divider),
          itemBuilder: (context, index) {
            if (index >= feed.topics.length) return const _LoadingMoreRow();

            // The end is in view; fetch before the user gets there.
            if (index == feed.topics.length - 1 && feed.hasMore) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => controller.loadMoreFeed(destination),
              );
            }

            final topic = feed.topics[index];
            return _TopicRow(
              topic: topic,
              category: controller.categoryFor(topic.categoryId),
              onTap: () => controller.openTopic(topic),
            );
          },
        ),
      ),
    );
  }

  /// How close to the end triggers the next page. Roughly a screenful, so the
  /// rows are usually there before the user reaches them.
  static const double _loadMoreThreshold = 800;
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
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({
    required this.topic,
    required this.category,
    required this.onTap,
  });

  final Topic topic;
  final TopicCategory? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (topic.pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.push_pin,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          topic.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            // Unread topics read heavier, the way the web does.
                            fontWeight: topic.hasUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (category case final category?) ...[
                        _CategoryBadge(category: category),
                        const SizedBox(width: 10),
                      ],
                      _Stat(
                        icon: Icons.mode_comment_outlined,
                        value: topic.replyCount,
                      ),
                      const SizedBox(width: 10),
                      _Stat(
                        icon: Icons.visibility_outlined,
                        value: topic.views,
                      ),
                      if (topic.bumpedAt case final bumpedAt?) ...[
                        const SizedBox(width: 10),
                        Text(
                          relativeTime(bumpedAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _Posters(avatars: topic.posterAvatars),
            if (topic.hasUnread) ...[
              const SizedBox(width: 8),
              _UnreadPill(count: topic.unreadPosts + topic.newPosts),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final TopicCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
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
        Text(
          category.name,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value});

  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          _short(value),
          style: theme.textTheme.labelSmall?.copyWith(color: color),
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

/// Up to three poster avatars, as the web list shows.
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
                      child: Icon(
                        Icons.person,
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

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
