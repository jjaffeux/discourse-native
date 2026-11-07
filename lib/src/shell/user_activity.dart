import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:super_sliver_list/super_sliver_list.dart';

import '../models/discourse_instance.dart';
import '../models/topic.dart';
import '../models/user_activity.dart';
import '../models/user_activity_feed.dart';
import '../theme/d_icons.dart';
import '../theme/discourse_typography.dart';
import '../utils/pagination.dart';
import 'account_activity_loader.dart';
import 'account_activity_paging_skeleton.dart';
import 'account_feed_viewport.dart';
import 'content_reading_lane.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'skeleton_fill.dart';
import 'topic_list_view.dart';
import 'topic_title.dart';

class UserActivityView extends StatelessWidget {
  const UserActivityView({
    super.key,
    required this.siteUrl,
    this.username,
    this.title,
    this.embedded = false,
    this.onOpen,
  });

  final String siteUrl;
  final String? username;
  final String? title;
  final bool embedded;
  final ValueChanged<UserActivityItem>? onOpen;

  @override
  Widget build(BuildContext context) => AccountActivityLoader.userActivity(
    siteUrl: siteUrl,
    username: username,
    builder: (context, controller) => ListenableBuilder(
      listenable: controller.accountActivity.userActivityListenable,
      builder: (context, _) => _UserActivityBody(
        controller: controller,
        siteUrl: siteUrl,
        username: username,
        title: title,
        embedded: embedded,
        onOpen: onOpen,
      ),
    ),
  );
}

class _UserActivityBody extends StatelessWidget {
  const _UserActivityBody({
    required this.controller,
    required this.siteUrl,
    required this.username,
    required this.title,
    required this.embedded,
    required this.onOpen,
  });

  final ShellController controller;
  final String siteUrl;
  final String? username;
  final String? title;
  final bool embedded;
  final ValueChanged<UserActivityItem>? onOpen;
  String get pageTitle => title ?? appL10n.activity;

  DiscourseInstance? get _instance => controller.instances
      .where((instance) => instance.url == siteUrl)
      .firstOrNull;

  Future<void> _refresh() async {
    final instance = _instance;
    if (instance != null) {
      await controller.accountActivity.loadUserActivity(
        instance,
        username: username,
        refresh: true,
      );
    }
  }

  Future<void> _loadMore() async {
    final instance = _instance;
    if (instance != null) {
      await controller.accountActivity.loadUserActivity(
        instance,
        username: username,
        loadMore: true,
      );
    }
  }

  Future<void> _loadPrevious() async {
    final instance = _instance;
    if (instance != null) {
      await controller.accountActivity.loadUserActivity(
        instance,
        username: username,
        loadPrevious: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final instance = _instance;
    if (instance?.isConnected != true) {
      if (embedded) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Text(context.l10n.connectThisAccountToSeeItsActivity),
        );
      }
      return DPageSurface.headed(
        title: Text(pageTitle),
        child: _ActivityState(
          icon: DIcons.list,
          title: context.l10n.connectThisAccountToSeeItsActivity,
        ),
      );
    }

    final feed = controller.accountActivity.userActivityFor(
      siteUrl,
      username: username,
    );
    final body = _body(feed);
    return body is _ActivityList
        ? body
        : DPageSurface.headed(title: Text(pageTitle), child: body);
  }

  Widget _body(UserActivityFeed feed) {
    if (embedded) return _list(feed);
    if (feed.error case final error?
        when feed.items.isEmpty && !feed.hasPrevious) {
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
        body: appL10n.activityHistoryDescription,
      );
    }

    return _list(feed);
  }

  Widget _list(UserActivityFeed feed) => _ActivityList(
    key: ValueKey((
      siteUrl,
      username,
      controller.lifecycle.capture(siteUrl).session,
    )),
    siteUrl: siteUrl,
    title: pageTitle,
    embedded: embedded,
    username: username,
    session: controller.lifecycle.capture(siteUrl).session,
    feed: feed,
    onRefresh: _refresh,
    onLoadMore: _loadMore,
    onLoadPrevious: _loadPrevious,
    onOpen: onOpen ?? controller.openUserActivityItem,
  );
}

enum _ActivityKind { all, topics, replies, likes }

class _ActivityList extends StatefulWidget {
  const _ActivityList({
    super.key,
    required this.siteUrl,
    required this.title,
    required this.username,
    required this.embedded,
    required this.session,
    required this.feed,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onLoadPrevious,
    required this.onOpen,
  });

  final String siteUrl;
  final String title;
  final String? username;
  final bool embedded;
  final Object session;
  final UserActivityFeed feed;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onLoadPrevious;
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
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.session != widget.session ||
        oldWidget.username != widget.username) {
      _kind = _ActivityKind.all;
    }
    _keepEmbeddedAnchor(oldWidget);
  }

  final _embeddedKeys = <String, GlobalKey>{};
  void _keepEmbeddedAnchor(_ActivityList oldWidget) {
    if (!widget.embedded ||
        oldWidget.feed.items == feed.items ||
        _outerScroll == null) {
      return;
    }
    final retained = {for (final item in feed.items) item.identity};
    GlobalKey? anchor;
    double? top;
    for (final item in oldWidget.feed.items) {
      if (!retained.contains(item.identity)) continue;
      final key = _embeddedKeys[item.identity];
      final box = key?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y + box.size.height > 0 && y < MediaQuery.sizeOf(context).height) {
        anchor = key;
        top = y;
        break;
      }
    }
    _embeddedKeys.removeWhere((id, _) => !retained.contains(id));
    if (anchor == null || top == null) return;
    final position = _outerScroll!;
    final savedTop = top;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _outerScroll != position) return;
      final box = anchor?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !position.hasContentDimensions) {
        return;
      }
      final delta = box.localToGlobal(Offset.zero).dy - savedTop;
      if (delta.abs() > .5) {
        position.jumpTo(
          (position.pixels + delta).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
    });
  }

  ScrollPosition? _outerScroll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = widget.embedded
        ? Scrollable.maybeOf(context)?.position
        : null;
    if (position == _outerScroll) return;
    _outerScroll?.removeListener(_outerMoved);
    _outerScroll = position;
    position?.addListener(_outerMoved);
  }

  void _outerMoved() {
    final position = _outerScroll;
    if (position == null ||
        !position.hasContentDimensions ||
        feed.loading ||
        feed.error != null) {
      return;
    }
    if (feed.hasPrevious &&
        position.extentBefore < paginationPrefetchDistance(position)) {
      unawaited(widget.onLoadPrevious());
    } else if (position.pixels > 0 &&
        feed.hasMore &&
        position.extentAfter < paginationPrefetchDistance(position)) {
      unawaited(onLoadMore());
    }
  }

  @override
  void dispose() {
    _outerScroll?.removeListener(_outerMoved);
    super.dispose();
  }

  Widget _embedded(List<UserActivityItem> items) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DTabs<_ActivityKind>.controlled(
          value: _kind,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _kind = value);
            if (feed.hasPrevious) unawaited(onRefresh());
          },
          children: [
            DTabList<_ActivityKind>(
              variant: DTabListVariant.line,
              children: [
                for (final (kind, label) in [
                  (_ActivityKind.all, appL10n.all),
                  (_ActivityKind.topics, appL10n.topics),
                  (_ActivityKind.replies, appL10n.replies),
                  (_ActivityKind.likes, appL10n.likes),
                ])
                  DTabTrigger<_ActivityKind>(value: kind, child: Text(label)),
              ],
            ),
          ],
        ),
      ),
      if (feed.hasPrevious)
        Center(
          child: DButton(
            label: Text(appL10n.previous),
            loading: feed.loadingPrevious,
            onPressed: feed.loading
                ? null
                : () => unawaited(widget.onLoadPrevious()),
          ),
        ),
      for (final (index, item) in items.indexed) ...[
        if (index > 0) const DSeparator(indent: 16, endIndent: 16),
        KeyedSubtree(
          key: _embeddedKeys.putIfAbsent(item.identity, GlobalKey.new),
          child: UserActivityRow(
            siteUrl: siteUrl,
            item: item,
            category: feed.categoryFor(item.categoryId),
            onTap: () => onOpen(item),
          ),
        ),
      ],
      if (!feed.loaded || feed.loading)
        AccountActivityPagingSkeleton(semanticsLabel: appL10n.loadingActivity),
      if (feed.error case final error?)
        _LoadMoreError(
          message: error,
          onRetry: () => unawaited(
            feed.retryFromStart
                ? onRefresh()
                : feed.retryPrevious
                ? widget.onLoadPrevious()
                : onLoadMore(),
          ),
        ),
      if (feed.loaded && !feed.loading && feed.error == null && items.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(appL10n.noActivityYet),
        ),
      if (feed.hasMore && !feed.loading && feed.error == null)
        Center(
          child: DButton(
            label: Text(appL10n.loadMore),
            onPressed: () => unawaited(onLoadMore()),
          ),
        ),
    ],
  );

  // A failed page is retried only from its Retry row: every scroll
  // notification near the end would otherwise resend it as soon as it fails.
  bool _nearEnd(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification is! ScrollUpdateNotification ||
        (notification.scrollDelta ?? 0) <= 0 ||
        !feed.hasMore ||
        feed.loading ||
        feed.error != null) {
      return false;
    }
    return notification.metrics.extentAfter <
        (feed.retainedPageCount == 1
            ? 0.5
            : paginationPrefetchDistance(notification.metrics));
  }

  @override
  Widget build(BuildContext context) {
    final items = feed.items
        .where(
          (item) => switch (_kind) {
            _ActivityKind.all => true,
            _ActivityKind.topics => item.isTopic,
            _ActivityKind.replies => item.isReply,
            _ActivityKind.likes => item.isLike,
          },
        )
        .toList();
    final hasFooter = feed.loading || feed.error != null || feed.hasMore;
    if (widget.embedded) return _embedded(items);
    final content = DPageSurface.headed(
      title: Text(widget.title),
      controls: DReferenceTextScale(
        child: ContentReadingLaneBox(
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
                  if (value == null) return;
                  setState(() => _kind = value);
                  if (feed.hasPrevious) unawaited(onRefresh());
                },
                entries: [
                  for (final (value, label) in [
                    (_ActivityKind.all, context.l10n.allActivity),
                    (_ActivityKind.topics, context.l10n.topics),
                    (_ActivityKind.replies, context.l10n.replies),
                    (_ActivityKind.likes, context.l10n.likes),
                  ])
                    DSelectOption(
                      value: value,
                      label: label,
                      child: Text(label),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      bodyBuilder: (context, header) => ContentReadingLane(
        basePadding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        builder: (context, lane) => AccountFeedViewport(
          identity: (siteUrl, widget.session, widget.username, _kind),
          rows: [for (final item in items) item.identity],
          revealEnd: feed.window.lastPageWasPrevious,
          builder: (context, viewport) =>
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (viewport.restoring) return false;
                  if (notification.depth == 0 &&
                      (notification is UserScrollNotification &&
                              notification.direction ==
                                  ScrollDirection.forward ||
                          notification is ScrollUpdateNotification &&
                              (notification.scrollDelta ?? 0) < 0) &&
                      notification.metrics.extentBefore <
                          (feed.retainedPageCount == 1
                              ? 0.5
                              : paginationPrefetchDistance(
                                  notification.metrics,
                                )) &&
                      feed.hasPrevious &&
                      !feed.loading &&
                      feed.error == null) {
                    unawaited(widget.onLoadPrevious());
                  } else if (_nearEnd(notification)) {
                    unawaited(onLoadMore());
                  }
                  return false;
                },
                child: DPageScrollInsets(
                  builder: (context, insets) => CustomScrollView(
                    key: PageStorageKey((
                      'user-activity-list',
                      siteUrl,
                      widget.username,
                      _kind,
                    )),
                    controller: viewport.scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: lane.padding.add(insets),
                        sliver: SliverMainAxisGroup(
                          slivers: [
                            if (feed.hasPrevious)
                              SliverToBoxAdapter(
                                child: Center(
                                  child: DButton(
                                    label: Text(context.l10n.previous),
                                    loading: feed.loadingPrevious,
                                    onPressed: feed.loading
                                        ? null
                                        : () => unawaited(
                                            widget.onLoadPrevious(),
                                          ),
                                  ),
                                ),
                              ),
                            SuperSliverList.builder(
                              listController: viewport.listController,
                              findChildIndexCallback: viewport.indexForKey,
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item = items[index];
                                return viewport.row(
                                  item.identity,
                                  Column(
                                    children: [
                                      UserActivityRow(
                                        siteUrl: siteUrl,
                                        item: item,
                                        category: feed.categoryFor(
                                          item.categoryId,
                                        ),
                                        onTap: () => onOpen(item),
                                      ),
                                      if (index < items.length - 1)
                                        const DSeparator(space: 1),
                                    ],
                                  ),
                                );
                              },
                            ),
                            if (items.isEmpty && !feed.hasPrevious)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(context.l10n.noActivityYet),
                                ),
                              ),
                            if (hasFooter)
                              SliverToBoxAdapter(
                                child: feed.error != null
                                    ? _LoadMoreError(
                                        message: feed.error!,
                                        onRetry: () => unawaited(
                                          feed.retryFromStart
                                              ? onRefresh()
                                              : feed.retryPrevious
                                              ? widget.onLoadPrevious()
                                              : onLoadMore(),
                                        ),
                                      )
                                    : feed.loading
                                    ? AccountActivityPagingSkeleton(
                                        semanticsLabel:
                                            context.l10n.loadingMoreActivity,
                                      )
                                    : Center(
                                        child: DButton(
                                          label: Text(context.l10n.loadMore),
                                          onPressed: () =>
                                              unawaited(onLoadMore()),
                                        ),
                                      ),
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
    final category = this.category;
    final semanticLabel = [
      item.title,
      item.isLike
          ? context.l10n.activityLikedPost(item.username)
          : item.isTopic
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

    final tokens = DTokens.of(context);
    final kicker = item.isLike
        ? context.l10n.activityLikedPost(item.username)
        : item.isTopic
        ? context.l10n.activityStartedTopic
        : context.l10n.activityReplied;
    return DItem(
      key: ValueKey('user-activity-row-${item.identity}'),
      size: DItemSize.artwork,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: DItemShape.fullWidth,
      semanticLabel: semanticLabel,
      onPressed: onTap,
      closed: item.closed,
      children: [
        DItemContent(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DefaultTextStyle.merge(
                  style: TextStyle(
                    fontSize: DiscourseTypography.metadata,
                    color: tokens.mutedForeground,
                    height: 1.4,
                  ),
                  child: Row(
                    spacing: 6,
                    children: [
                      DIcon(
                        item.isLike
                            ? DIcons.heart
                            : item.isTopic
                            ? DIcons.layerGroup
                            : DIcons.reply,
                        size: 10,
                        color: tokens.mutedForeground,
                      ),
                      Flexible(child: Text(kicker)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                DItemTitle(
                  maxLines: 2,
                  child: TopicTitle(
                    item.title,
                    siteUrl: siteUrl,
                    style: TextStyle(
                      fontWeight: FontWeight.w400,
                      fontSize: DiscourseTypography.rowTitle,
                      height: 1.35,
                      color: tokens.titleRead,
                    ),
                  ),
                ),
                if (item.excerpt.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  DItemDescription(
                    child: Text(
                      item.plainExcerpt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DiscourseTypography.preview,
                        height: 1.45,
                        color: tokens.mutedForeground,
                      ),
                    ),
                  ),
                ],
                _ActivityTopicMetadata(
                  siteUrl: siteUrl,
                  item: item,
                  category: category,
                  when: when,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Cache misses deliberately remain misses: this strip never loads a topic.
class _ActivityTopicMetadata extends StatelessWidget {
  const _ActivityTopicMetadata({
    required this.siteUrl,
    required this.item,
    required this.category,
    required this.when,
  });
  final String siteUrl;
  final UserActivityItem item;
  final TopicCategory? category;
  final String? when;

  @override
  Widget build(BuildContext context) {
    if (ShellScope.maybeRead(context) == null) return _fallback(context);
    return ShellSelector<({ShellController controller, Object session})>(
      select: (controller) => (
        controller: controller,
        session: controller.lifecycle.capture(siteUrl).session,
      ),
      builder: (context, owner, _) => ListenableBuilder(
        listenable: owner.controller.topicRef(siteUrl, item.topicId),
        builder: (context, _) {
          final topic = owner.controller.store.read<Topic>(
            siteUrl,
            item.topicId,
          );
          if (topic == null) return _fallback(context);
          return Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TopicListMetadata(
                  topic: topic,
                  siteUrl: siteUrl,
                  timeLabel: when ?? '',
                  category: category,
                ),
                if (item.closed ||
                    item.archived ||
                    item.deleted ||
                    item.hidden) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: DSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (item.closed || item.archived)
                        const DIcon(DIcons.lock, size: 12),
                      if (item.deleted || item.hidden)
                        Text(
                          item.deleted
                              ? context.l10n.deleted
                              : context.l10n.hidden,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    if (category == null &&
        when == null &&
        !item.closed &&
        !item.archived &&
        !item.deleted &&
        !item.hidden) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: DSpacing.sm,
              runSpacing: DSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (item.closed || item.archived)
                  const DIcon(DIcons.lock, size: 12),
                if (category != null)
                  _ActivityCategory(siteUrl: siteUrl, category: category!),
                if (item.deleted || item.hidden)
                  Text(
                    item.deleted ? context.l10n.deleted : context.l10n.hidden,
                  ),
              ],
            ),
          ),
          if (when != null)
            Text(when!, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
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
