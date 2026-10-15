import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/discourse_instance.dart';
import '../models/topic.dart';
import '../models/user_activity.dart';
import '../models/user_activity_feed.dart';
import '../theme/d_icons.dart';
import '../utils/pagination.dart';
import 'account_activity_loader.dart';
import 'account_activity_paging_skeleton.dart';
import 'category_icon.dart';
import 'content_reading_lane.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'skeleton_fill.dart';
import 'topic_title.dart';

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
      return DPageSurface.headed(
        title: Text(context.l10n.activity),
        child: _ActivityState(
          icon: DIcons.list,
          title: context.l10n.connectThisAccountToSeeItsActivity,
        ),
      );
    }

    final feed = controller.accountActivity.userActivityFor(siteUrl);
    final body = _body(feed);
    return body is _ActivityList
        ? body
        : DPageSurface.headed(title: Text(context.l10n.activity), child: body);
  }

  Widget _body(UserActivityFeed feed) {
    if (feed.error case final error? when feed.items.isEmpty) {
      return _ActivityState(
        icon: DIcons.triangleExclamation,
        title: error,
        actionLabel: appL10n.tryAgain,
        onAction: _refresh,
      );
    }
    if (!feed.loaded && feed.items.isEmpty) {
      return const _ActivityLoadingSkeleton();
    }
    if (feed.isEmpty) {
      return _ActivityState(
        icon: DIcons.list,
        title: appL10n.noActivityYet,
        body: appL10n.topicsYouCreateAndRepliesYouPostWillAppearHereLikes,
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

enum _ActivityKind { all, topics, replies }

class _ActivityList extends StatefulWidget {
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

  @override
  State<_ActivityList> createState() => _ActivityListState();
}

class _ActivityListState extends State<_ActivityList> {
  _ActivityKind _kind = _ActivityKind.all;
  UserActivityFeed get feed => widget.feed;
  String get siteUrl => widget.siteUrl;
  Future<void> Function() get onLoadMore => widget.onLoadMore;
  Future<void> Function() get onRefresh => widget.onRefresh;
  ValueChanged<UserActivityItem> get onOpen => widget.onOpen;

  @override
  void didUpdateWidget(_ActivityList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl) _kind = _ActivityKind.all;
  }

  // A failed page is retried only from its Retry row: every scroll
  // notification near the end would otherwise resend it as soon as it fails.
  bool _nearEnd(ScrollNotification notification) {
    if (notification.depth != 0 ||
        !feed.hasMore ||
        feed.loading ||
        feed.error != null) {
      return false;
    }
    return notification.metrics.extentAfter <
        paginationPrefetchDistance(notification.metrics);
  }

  @override
  Widget build(BuildContext context) {
    final items = feed.items
        .where(
          (item) => switch (_kind) {
            _ActivityKind.all => true,
            _ActivityKind.topics => item.isTopic,
            _ActivityKind.replies => item.isReply,
          },
        )
        .toList();
    final hasFooter = feed.loading || feed.error != null || feed.hasMore;
    final content = DPageSurface.headed(
      title: Text(context.l10n.activity),
      controls: ContentReadingLaneBox(
        child: Padding(
          padding: EdgeInsets.zero,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: DSelect<_ActivityKind>.controlled(
              size: DControlSize.filter,
              key: const ValueKey('activity-kind-filter'),
              value: _kind,
              semanticLabel: context.l10n.activity,
              onChanged: (value) {
                if (value != null) setState(() => _kind = value);
              },
              entries: [
                for (final (value, label) in [
                  (_ActivityKind.all, context.l10n.allActivity),
                  (_ActivityKind.topics, context.l10n.topics),
                  (_ActivityKind.replies, context.l10n.replies),
                ])
                  DSelectOption(value: value, label: label, child: Text(label)),
              ],
            ),
          ),
        ),
      ),
      bodyBuilder: (context, header) => ContentReadingLane(
        basePadding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        builder: (context, lane) => NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (_nearEnd(notification)) unawaited(onLoadMore());
            return false;
          },
          child: DPageScrollInsets(
            builder: (context, insets) => ListView.separated(
              key: const PageStorageKey('user-activity-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: lane.padding.add(insets),
              itemCount:
                  items.length + (hasFooter ? 1 : 0) + (items.isEmpty ? 1 : 0),
              separatorBuilder: (context, index) => index < items.length - 1
                  ? const Center(
                      child: SizedBox(
                        width: double.infinity,
                        child: DSeparator(space: 1),
                      ),
                    )
                  : const SizedBox.shrink(),
              itemBuilder: (context, index) {
                if (items.isEmpty && index == 0) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(context.l10n.noActivityYet),
                  );
                }
                if (index < items.length) {
                  final item = items[index];
                  return Center(
                    child: SizedBox(
                      width: double.infinity,
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
                    onRetry: () => unawaited(
                      feed.retryFromStart ? onRefresh() : onLoadMore(),
                    ),
                  );
                }
                return feed.loading
                    ? AccountActivityPagingSkeleton(
                        semanticsLabel: context.l10n.loadingMoreActivity,
                      )
                    : Align(
                        child: DButton(
                          label: Text(context.l10n.loadMore),
                          onPressed: () => unawaited(onLoadMore()),
                        ),
                      );
              },
            ),
          ),
        ),
      ),
    );
    return DScrollChromePagination(
      hasMore: feed.hasMore,
      loading: feed.loading,
      child: content,
    );
  }
}

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

  // The age is part of the row's semantic label as well as its text, so the
  // whole row follows it.
  @override
  Widget build(BuildContext context) => switch (item.createdAt) {
    final at? => RelativeTimeBuilder(when: at, builder: _row),
    null => _row(context, null),
  };

  Widget _row(BuildContext context, String? when) {
    final theme = Theme.of(context);
    final category = this.category;
    final semanticLabel = [
      item.title,
      item.isTopic
          ? context.l10n.topicCreatedBy((item.username).toString())
          : context.l10n.replyBy((item.username).toString()),
      if (item.postNumber > 1)
        context.l10n.postUseractivity((item.postNumber).toString()),
      if (category != null) category.name,
      ?when,
      if (item.deleted) context.l10n.deleted,
      if (item.hidden) context.l10n.hidden,
      if (item.plainExcerpt.isNotEmpty) item.plainExcerpt,
    ].join(', ');

    return DItem(
      key: ValueKey('user-activity-row-${item.identity}'),
      shape: DItemShape.fullWidth,
      semanticLabel: semanticLabel,
      onPressed: onTap,
      header: DItemHeader(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DSpacing.xs,
          children: [
            DIcon(item.isTopic ? DIcons.layerGroup : DIcons.reply, size: 12),
            Text(
              item.isTopic
                  ? context.l10n.activityStartedTopic
                  : context.l10n.activityReplied,
            ),
          ],
        ),
      ),
      children: [
        DItemContent(
          children: [
            DItemTitle(
              maxLines: 2,
              child: TopicTitle(item.title, siteUrl: siteUrl),
            ),
            if (item.excerpt.isNotEmpty)
              DItemDescription(
                child: Text(
                  item.plainExcerpt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Wrap(
              spacing: DSpacing.sm,
              runSpacing: DSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (item.closed || item.archived)
                  const DIcon(DIcons.lock, size: 12),
                if (category != null)
                  _ActivityCategory(siteUrl: siteUrl, category: category),
                if (when != null)
                  Text(when, style: theme.textTheme.labelMedium),
                if (item.deleted || item.hidden)
                  Text(
                    item.deleted ? context.l10n.deleted : context.l10n.hidden,
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _ActivityCategory extends StatelessWidget {
  const _ActivityCategory({required this.siteUrl, required this.category});

  final String siteUrl;
  final TopicCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CategoryIcon(
          category: category,
          siteUrl: siteUrl,
          size: 13,
          squareSize: 9,
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
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: DAlert(
          variant: DAlertVariant.destructive,
          icon: const Icon(Icons.error_outline),
          description: DAlertDescription(child: Text(message)),
          action: DAlertAction(
            child: DButton(
              label: Text(context.l10n.retry),
              onPressed: onRetry,
              variant: DButtonVariant.link,
            ),
          ),
        ),
      ),
    ),
  );
}

class _ActivityLoadingSkeleton extends StatelessWidget {
  const _ActivityLoadingSkeleton();

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    expand: true,
    semanticsLabel: context.l10n.loadingActivity,
    color: skeletonFill(context),
    child: ContentReadingLane(
      basePadding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      builder: (context, lane) => ListView.separated(
        padding: lane.padding,
        itemCount: 6,
        separatorBuilder: (context, index) => const DSeparator(space: 1),
        itemBuilder: (context, index) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: double.infinity,
              minHeight: 112,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DSkeleton.circle(diameter: 44),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FractionallySizedBox(
                          widthFactor: index.isEven ? 0.52 : 0.68,
                          child: const DSkeleton(height: 12),
                        ),
                        const SizedBox(height: 9),
                        const DSkeleton(width: 110, height: 8),
                        const SizedBox(height: 18),
                        const FractionallySizedBox(
                          widthFactor: 0.88,
                          child: DSkeleton(height: 10),
                        ),
                        const SizedBox(height: 8),
                        const FractionallySizedBox(
                          widthFactor: 0.61,
                          child: DSkeleton(height: 10),
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
  });

  final DIconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Center(
              child: DEmpty(
                children: [
                  DEmptyHeader(
                    children: [
                      DEmptyMedia(
                        variant: DEmptyMediaVariant.icon,
                        child: DIcon(icon),
                      ),
                      DEmptyTitle(title),
                      if (body case final body?) DEmptyDescription(body),
                    ],
                  ),
                  if (actionLabel case final label?)
                    DEmptyContent(
                      children: [
                        DButton(
                          label: Text(label),
                          onPressed: onAction == null
                              ? null
                              : () => unawaited(onAction!()),
                          variant: DButtonVariant.primary,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
