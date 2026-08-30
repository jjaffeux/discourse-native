import 'dart:async';

import 'package:flutter/material.dart';

import '../models/discourse_instance.dart';
import '../models/topic.dart';
import '../models/user_activity.dart';
import '../models/user_activity_feed.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'account_activity_loader.dart';
import 'avatar_image.dart';
import 'cooked_html.dart';
import 'loading_skeleton.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'topic_title.dart';

/// The connected user's default Activity page: topics and replies in one
/// reverse-chronological stream, matching `userActivity.index` on the web.
class UserActivityView extends StatelessWidget {
  const UserActivityView({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  Widget build(BuildContext context) => AccountActivityLoader.userActivity(
    siteUrl: siteUrl,
    builder: (context, controller) => ListenableBuilder(
      listenable: controller.accountActivity.userActivityListenable,
      builder: (context, _) =>
          _UserActivityBody(controller: controller, siteUrl: siteUrl),
    ),
  );
}

class _UserActivityBody extends StatelessWidget {
  const _UserActivityBody({required this.controller, required this.siteUrl});

  final ShellController controller;
  final String siteUrl;

  DiscourseInstance? get _instance => controller.instances
      .where((instance) => instance.url == siteUrl)
      .firstOrNull;

  Future<void> _refresh() async {
    final instance = _instance;
    if (instance != null) {
      await controller.accountActivity.loadUserActivity(
        instance,
        refresh: true,
      );
    }
  }

  Future<void> _loadMore() async {
    final instance = _instance;
    if (instance != null) {
      await controller.accountActivity.loadUserActivity(
        instance,
        loadMore: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final instance = _instance;
    if (instance?.isConnected != true) {
      return const _ActivityState(
        icon: DIcons.list,
        title: 'Connect this account to see its activity',
      );
    }

    final feed = controller.accountActivity.userActivityFor(siteUrl);
    if (feed.error case final error? when feed.items.isEmpty) {
      return _ActivityState(
        icon: DIcons.triangleExclamation,
        title: error,
        actionLabel: 'Try again',
        onAction: _refresh,
        onRefresh: _refresh,
      );
    }
    if (!feed.loaded && feed.items.isEmpty) {
      return const _ActivityLoadingSkeleton();
    }
    if (feed.isEmpty) {
      return _ActivityState(
        icon: DIcons.list,
        title: 'No activity yet',
        body:
            'Topics you create and replies you post will appear here. '
            'Likes, bookmarks, reads, and drafts have their own lists.',
        onRefresh: _refresh,
      );
    }

    return _ActivityList(
      siteUrl: siteUrl,
      feed: feed,
      onRefresh: _refresh,
      onLoadMore: _loadMore,
      onOpen: controller.openUserActivityItem,
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({
    required this.siteUrl,
    required this.feed,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onOpen,
  });

  final String siteUrl;
  final UserActivityFeed feed;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final ValueChanged<UserActivityItem> onOpen;

  bool _nearEnd(ScrollNotification notification) {
    if (notification.depth != 0 || !feed.hasMore || feed.loading) return false;
    return notification.metrics.extentAfter <
        notification.metrics.viewportDimension;
  }

  @override
  Widget build(BuildContext context) {
    final hasFooter = feed.loading || feed.error != null;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (_nearEnd(notification)) unawaited(onLoadMore());
          return false;
        },
        child: ListView.separated(
          key: const PageStorageKey('user-activity-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: feed.items.length + (hasFooter ? 1 : 0),
          separatorBuilder: (context, index) => index < feed.items.length - 1
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: const Divider(height: 1),
                  ),
                )
              : const SizedBox.shrink(),
          itemBuilder: (context, index) {
            if (index < feed.items.length) {
              final item = feed.items[index];
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: UserActivityRow(
                    siteUrl: siteUrl,
                    item: item,
                    category: feed.categoryFor(item.categoryId),
                    onTap: () => onOpen(item),
                  ),
                ),
              );
            }
            if (feed.error case final error?) {
              return _LoadMoreError(
                message: error,
                onRetry: () =>
                    unawaited(feed.retryFromStart ? onRefresh() : onLoadMore()),
              );
            }
            return Semantics(
              liveRegion: true,
              label: 'Loading more activity',
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One native counterpart of core's `PostListItem` in a user stream.
class UserActivityRow extends StatelessWidget {
  const UserActivityRow({
    super.key,
    required this.siteUrl,
    required this.item,
    required this.onTap,
    this.category,
  });

  final String siteUrl;
  final UserActivityItem item;
  final TopicCategory? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = item.createdAt == null ? null : relativeTime(item.createdAt!);
    final category = this.category;
    final semanticLabel = [
      item.title,
      item.isTopic
          ? 'Topic created by ${item.username}'
          : 'Reply by ${item.username}',
      if (item.postNumber > 1) 'Post ${item.postNumber}',
      if (category != null) category.name,
      ?when,
      if (item.deleted) 'Deleted',
      if (item.hidden) 'Hidden',
      if (item.plainExcerpt.isNotEmpty) item.plainExcerpt,
    ].join(', ');

    return Semantics(
      key: ValueKey('user-activity-row-${item.identity}'),
      button: true,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('user-activity-row-target-${item.identity}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipOval(
                  child: AvatarImage(
                    url: item.avatarUrl,
                    size: 44,
                    fallback: CircleAvatar(
                      radius: 22,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      child: Text(
                        item.username.isEmpty
                            ? '?'
                            : item.username.characters.first.toUpperCase(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Opacity(
                    opacity: item.deleted || item.hidden ? 0.68 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (item.closed || item.archived) ...[
                              DIcon(
                                DIcons.lock,
                                size: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: TopicTitle(
                                item.title,
                                siteUrl: siteUrl,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (category != null ||
                            when != null ||
                            item.deleted ||
                            item.hidden) ...[
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (category != null)
                                _ActivityCategory(category: category),
                              if (when != null)
                                Text(
                                  when,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              if (item.deleted || item.hidden)
                                Text(
                                  item.deleted ? 'Deleted' : 'Hidden',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ],
                        if (item.excerpt.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          CookedHtml(
                            html: item.excerpt,
                            siteUrl: siteUrl,
                            textStyle: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.discourse.primaryHigh,
                            ),
                            compactParagraphs: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityCategory extends StatelessWidget {
  const _ActivityCategory({required this.category});

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
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LoadMoreError extends StatelessWidget {
  const _LoadMoreError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Container(
            margin: const EdgeInsets.only(top: 12),
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
                  label: const Text('Retry'),
                  onPressed: onRetry,
                  variant: DButtonVariant.link,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityLoadingSkeleton extends StatelessWidget {
  const _ActivityLoadingSkeleton();

  @override
  Widget build(BuildContext context) => LoadingSkeleton(
    semanticsLabel: 'Loading activity',
    child: ListView.separated(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      itemCount: 6,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 976, minHeight: 112),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LoadingSkeletonBlock.circle(diameter: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: index.isEven ? 0.52 : 0.68,
                        child: const LoadingSkeletonBlock(height: 12),
                      ),
                      const SizedBox(height: 9),
                      const LoadingSkeletonBlock(width: 110, height: 8),
                      const SizedBox(height: 18),
                      const FractionallySizedBox(
                        widthFactor: 0.88,
                        child: LoadingSkeletonBlock(height: 10),
                      ),
                      const SizedBox(height: 8),
                      const FractionallySizedBox(
                        widthFactor: 0.61,
                        child: LoadingSkeletonBlock(height: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ActivityState extends StatelessWidget {
  const _ActivityState({
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.onRefresh,
  });

  final DIconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Semantics(
      container: true,
      liveRegion: true,
      label: [title, ?body].join('. '),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DIcon(icon, size: 48, color: theme.colorScheme.primary),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                if (body case final body?) ...[
                  const SizedBox(height: 6),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (actionLabel case final label?) ...[
                  const SizedBox(height: 18),
                  DButton(
                    label: Text(label),
                    onPressed: onAction == null
                        ? null
                        : () => unawaited(onAction!()),
                    variant: DButtonVariant.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final onRefresh = this.onRefresh;
    if (onRefresh == null) return content;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [SizedBox(height: constraints.maxHeight, child: content)],
        ),
      ),
    );
  }
}
