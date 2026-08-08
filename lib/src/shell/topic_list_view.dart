import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../models/topic.dart';
import '../models/topic_feed.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
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

  /// Fetches the topics the banner is counting, then goes up to them.
  ///
  /// The web puts its banner inside the list, so tapping it can only happen
  /// from the top. This one is pinned above the list and is reachable from
  /// anywhere in it, which makes the jump part of the action rather than a
  /// separate thing the reader has to do.
  Future<void> _showIncoming(
    ShellController controller,
    String destination,
  ) async {
    await controller.showIncoming(destination);
    if (!mounted || _destination != destination) return;

    // The rows only exist after the frame that draws them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _destination != destination) return;
      final scroll = _scroll;
      if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.of(context);
    // Not `destinationId`: a category or tag list opened from a hashtag is a
    // feed of its own, sitting over whichever sidebar entry is still selected.
    final destination = controller.currentFeedId ?? 'latest';
    final incoming = controller.incomingCount(destination);

    return Column(
      children: [
        // Above the list rather than scrolling with it, so it is still there
        // when the topics it is announcing are twenty rows up.
        if (incoming > 0)
          _IncomingBanner(
            count: incoming,
            destination: destination,
            loading: widget.feed.loadingIncoming,
            onTap: () => _showIncoming(controller, destination),
          ),
        Expanded(child: _body(controller, destination)),
      ],
    );
  }

  Widget _body(ShellController controller, String destination) {
    final feed = widget.feed;

    if (feed.loading && feed.topicIds.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (feed.error case final error?) {
      return _Message(icon: DIcons.triangleExclamation, text: error);
    }
    if (feed.isEmpty) {
      return const _Message(icon: DIcons.inbox, text: 'Nothing here yet.');
    }

    _syncControllers(destination);
    _restore(controller, destination);

    return RefreshIndicator(
      onRefresh: () => controller.loadFeed(destination, force: true),
      child: NotificationListener<ScrollNotification>(
        // Fetching on a scroll notification rather than from itemBuilder keeps
        // the request off the hot path of building rows. It does not keep it
        // out of the frame — a viewport applying new content dimensions starts
        // a scroll from inside its own layout, and this runs there too. What
        // makes that safe is ShellController deferring the notification it
        // raises, not anything here.
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
          itemCount: feed.topicIds.length + (feed.loadingMore ? 1 : 0),
          separatorBuilder: (context, _) =>
              Divider(height: 1, color: Theme.of(context).shell.divider),
          itemBuilder: (context, index) {
            if (index >= feed.topicIds.length) return const _LoadingMoreRow();

            // The end is in view; fetch before the user gets there.
            if (index == feed.topicIds.length - 1 && feed.hasMore) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => controller.loadMoreFeed(destination),
              );
            }

            return _TopicRow(topicId: feed.topicIds[index]);
          },
        ),
      ),
    );
  }

  /// How close to the end triggers the next page. Roughly a screenful, so the
  /// rows are usually there before the user reaches them.
  static const double _loadMoreThreshold = 800;
}

/// "See 3 new topics" — the strip the site's live updates put at the top of a
/// list, and the only thing in the shell that appears without being asked for.
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

  /// Core's `topic_count_latest` and `topic_count_new`, which differ for a
  /// reason worth keeping: only the latest list counts topics that were merely
  /// bumped, and a bump is an update rather than something new.
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
        // Tapping again mid-fetch would ask for the same ids a second time.
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
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
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
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

/// One row, drawing the topic the store holds under [topicId].
///
/// The list only ever knew which topics were in it and in what order; the topic
/// itself comes from the store, watched rather than passed in. So reading a
/// topic — which clears its unread state wherever that topic appears — redraws
/// this row alone, without the list it is in being rebuilt or even told.
class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.topicId});

  final int topicId;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.of(context);
    final siteUrl = controller.currentInstance?.url;
    if (siteUrl == null) return const SizedBox.shrink();

    return ValueListenableBuilder<Topic?>(
      valueListenable: controller.topicRef(siteUrl, topicId),
      builder: (context, topic, _) => topic == null
          // The id is in a list, so the topic was stored with it. A gap here
          // means the site was just disconnected and this list is one frame
          // from being torn down.
          ? const SizedBox.shrink()
          : _TopicRowBody(
              topic: topic,
              category: controller.categoryFor(topic.categoryId),
              onTap: () => controller.openTopic(topic),
            ),
    );
  }
}

class _TopicRowBody extends StatelessWidget {
  const _TopicRowBody({
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
                          child: DIcon(
                            DIcons.thumbtack,
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
                      _Stat(icon: DIcons.reply, value: topic.replyCount),
                      const SizedBox(width: 10),
                      _Stat(icon: DIcons.farEye, value: topic.views),
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

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final DIconData icon;
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
            DIcon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
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
