import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/count_label.dart';
import '../models/category_directory.dart';
import '../models/category_feed.dart';
import '../models/category_sidebar.dart';
import '../models/content_route.dart';
import '../models/json.dart';
import '../models/topic.dart';
import '../theme/d_icons.dart';
import '../utils/pagination.dart';
import 'category_icon.dart';
import 'content_reading_lane.dart';
import 'open_link.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_title.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, required this.siteUrl, required this.feed});

  final String siteUrl;
  final CategoryFeed feed;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  (ShellController, String)? _requestedIdentity;
  final ScrollController _scrollController = ScrollController();
  bool _endCheckScheduled = false;
  CategoryDirectoryScope _scope = CategoryDirectoryScope.all;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _requestFirstPage();
  }

  @override
  void didUpdateWidget(CategoriesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl) {
      _scope = CategoryDirectoryScope.all;
      _requestFirstPage();
    }
  }

  void _requestFirstPage({bool retry = false}) {
    final controller = ShellScope.read(context);
    final identity = (controller, widget.siteUrl);
    if (!retry && _requestedIdentity == identity) return;
    _requestedIdentity = identity;
    unawaited(controller.loadCategories(widget.siteUrl));
  }

  void _retry() {
    final controller = ShellScope.read(context);
    if (widget.feed.pageError) {
      unawaited(controller.loadMoreCategories(widget.siteUrl));
    } else {
      _requestFirstPage(retry: true);
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.extentAfter >=
            paginationPrefetchDistance(notification.metrics)) {
      return false;
    }
    final feed = widget.feed;
    if (feed.hasMore &&
        !feed.loading &&
        !feed.loadingMore &&
        feed.error == null) {
      unawaited(ShellScope.read(context).loadMoreCategories(widget.siteUrl));
    }
    return false;
  }

  void _scheduleVisibleEndCheck() {
    final feed = widget.feed;
    if (_endCheckScheduled ||
        !feed.hasMore ||
        feed.loading ||
        feed.loadingMore ||
        feed.error != null) {
      return;
    }
    _endCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _endCheckScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      final current = widget.feed;
      if (current.hasMore &&
          !current.loading &&
          !current.loadingMore &&
          current.error == null &&
          _scrollController.position.extentAfter <= 0.5) {
        unawaited(ShellScope.read(context).loadMoreCategories(widget.siteUrl));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final feed = widget.feed;
    if (!feed.loaded && feed.categoryIds.isEmpty) {
      return const SizedBox.shrink();
    }
    if (feed.error != null && feed.categoryIds.isEmpty) {
      return _CategoryPageState(
        icon: DIcons.triangleExclamation,
        title: feed.error!,
        actionLabel: context.l10n.tryAgain,
        onAction: _retry,
      );
    }
    if (feed.isEmpty) {
      return _CategoryPageState(
        icon: DIcons.list,
        title: context.l10n.noCategoriesYet,
      );
    }

    final controller = ShellScope.of(context);
    final user = controller.currentUserFor(widget.siteUrl);
    final counts = controller.categoryUnreadTopicCountsFor(widget.siteUrl);
    final scope = user == null && _scope == CategoryDirectoryScope.unread
        ? CategoryDirectoryScope.all
        : _scope;
    final entries = categoryDirectoryEntries(
      rootCategoryIds: feed.categoryIds,
      categories: controller.filterCategoriesFor(widget.siteUrl),
      unreadTopicCounts: counts ?? const {},
      mutedCategoryIds: {
        ...?user?.mutedCategoryIds,
        ...?user?.indirectlyMutedCategoryIds,
      },
    ).where((entry) => entry.matches(scope)).toList();
    _scheduleVisibleEndCheck();

    return ContentReadingLane(
      basePadding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      builder: (context, lane) => NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: lane.padding,
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: DSelect<CategoryDirectoryScope>.controlled(
                          key: ValueKey(('category-scope', widget.siteUrl)),
                          value: scope,
                          semanticLabel: context.l10n.categoryDirectoryScope,
                          entries: [
                            for (final value in CategoryDirectoryScope.values)
                              DSelectOption(
                                value: value,
                                label: _scopeLabel(context, value),
                                enabled:
                                    value != CategoryDirectoryScope.unread ||
                                    user != null,
                                child: Text(_scopeLabel(context, value)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _scope = value);
                            if (_scrollController.hasClients) {
                              _scrollController.jumpTo(0);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: DSeparator()),
                  if (!feed.pageError && feed.error != null)
                    SliverToBoxAdapter(
                      child: _CategoryErrorBanner(
                        message: feed.error!,
                        onRetry: _retry,
                      ),
                    ),
                  SliverList.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) => Column(
                      children: [
                        _CategoryActivityRow(
                          key: ValueKey(
                            'category-row-${entries[index].category.id}',
                          ),
                          siteUrl: widget.siteUrl,
                          entry: entries[index],
                        ),
                        if (index < entries.length - 1) const DSeparator(),
                      ],
                    ),
                  ),
                  if (entries.isEmpty && feed.error == null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: _CategoryPageState(
                          icon: DIcons.list,
                          title:
                              feed.loadingMore ||
                                  feed.hasMore ||
                                  (scope == CategoryDirectoryScope.unread &&
                                      counts == null)
                              ? context.l10n.loading
                              : scope == CategoryDirectoryScope.unread
                              ? context.l10n.noUnreadCategories
                              : context.l10n.noCategoriesWithTopics,
                        ),
                      ),
                    ),
                  if (feed.pageError && feed.error != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _CategoryErrorBanner(
                          message: feed.error!,
                          onRetry: _retry,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _scopeLabel(BuildContext context, CategoryDirectoryScope scope) =>
      switch (scope) {
        CategoryDirectoryScope.all => context.l10n.allCategoriesCategorysidebar,
        CategoryDirectoryScope.unread => context.l10n.unread,
        CategoryDirectoryScope.withTopics => context.l10n.categoriesWithTopics,
      };
}

class _CategoryActivityRow extends StatelessWidget {
  const _CategoryActivityRow({
    super.key,
    required this.siteUrl,
    required this.entry,
  });

  final String siteUrl;
  final CategoryDirectoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    final category = entry.category;
    final tokens = DTokens.of(context);
    final unread = entry.unreadTopicCount > 0;
    final foreground = entry.muted ? tokens.mutedForeground : tokens.foreground;
    final latest = entry.latestTopic;
    final categoriesById = {
      for (final category in controller.filterCategoriesFor(siteUrl))
        category.id: category,
    };
    ContentRoute routeFor(TopicCategory category) =>
        ContentRoute.fromDestination(
          buildCategoryDestination(category, categoriesById: categoriesById),
        );
    final title = DItemTitle(
      child: Row(
        children: [
          Expanded(
            child: Text(
              category.name,
              style: TextStyle(
                color: foreground,
                fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (category.readRestricted) ...[
            const SizedBox(width: 6),
            DIcon(
              DIcons.lock,
              size: 13,
              color: tokens.mutedForeground,
              semanticLabel: context.l10n.privateCategory,
            ),
          ],
          if (entry.muted) ...[
            const SizedBox(width: 6),
            DIcon(
              DIcons.discourseBellSlash,
              size: 13,
              color: tokens.mutedForeground,
              semanticLabel: context.l10n.muted,
            ),
          ],
        ],
      ),
    );
    final activity = DItemDescription(
      maxLines: 1,
      child: latest?.activityAt != null
          ? RelativeTimeText(latest!.activityAt!)
          : Text(
              latest != null && entry.topicCount == 0
                  ? context.l10n.latest
                  : countLabel(entry.topicCount, CountNoun.topic),
            ),
    );
    return LinkTarget.content(
      content: routeFor(category),
      siteUrl: siteUrl,
      child: DItem(
        shape: DItemShape.fullWidth,
        selectionStyle: DItemSelectionStyle.leadingAccent,
        showSelectionIndicator: false,
        link: true,
        semanticLabel: unread
            ? context.l10n.categoryUnreadTopics(entry.unreadTopicCount)
            : null,
        onPressed: () => controller.openCategory(category, siteUrl: siteUrl),
        children: [
          DItemMedia(
            variant: DItemMediaVariant.avatar,
            child: DAvatar(
              size: DAvatarSize.lg,
              border: false,
              decorative: true,
              borderRadius: BorderRadius.circular(DRadius.popover),
              fallback: DAvatarFallback(
                backgroundColor: Color(
                  category.colorValue,
                ).withValues(alpha: .15),
                child: CategoryIcon(
                  category: category,
                  siteUrl: siteUrl,
                  size: 18,
                  showLock: false,
                ),
              ),
            ),
          ),
          DItemContent(
            alignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) =>
                    constraints.maxWidth < 240 ||
                        MediaQuery.textScalerOf(context).scale(14) > 21
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, activity],
                      )
                    : Row(
                        children: [
                          Expanded(child: title),
                          const SizedBox(width: 8),
                          activity,
                        ],
                      ),
              ),
              if (latest != null)
                _LatestTopicLink(
                  siteUrl: siteUrl,
                  topic: latest,
                  unread: unread,
                )
              else if (jsonHtmlText(category.descriptionExcerpt)
                  case final description?)
                DItemDescription(maxLines: 1, child: Text(description)),
              if (entry.subcategories.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final child in entry.subcategories)
                      LinkTarget.content(
                        content: routeFor(child),
                        siteUrl: siteUrl,
                        child: DButton(
                          key: ValueKey('category-subcategory-${child.id}'),
                          variant: DButtonVariant.ghost,
                          size: DButtonSize.small,
                          icon: CategoryIcon(
                            category: child,
                            siteUrl: siteUrl,
                            size: 12,
                          ),
                          label: Text(
                            controller.topicCategoryPathLabel(
                              child,
                              siteUrl: siteUrl,
                            ),
                          ),
                          onPressed: () =>
                              controller.openCategory(child, siteUrl: siteUrl),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LatestTopicLink extends StatelessWidget {
  const _LatestTopicLink({
    required this.siteUrl,
    required this.topic,
    required this.unread,
  });
  final String siteUrl;
  final CategoryFeaturedTopic topic;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final status = topic.pinned
        ? context.l10n.pinned
        : topic.closed
        ? context.l10n.closed
        : topic.archived
        ? context.l10n.archived
        : null;
    final icon = topic.pinned
        ? DIcons.thumbtack
        : topic.closed || topic.archived
        ? DIcons.lock
        : DIcons.farFileLines;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: LinkTarget(
        url: '/t/${topic.slug}/${topic.id}/${topic.firstUnreadPostNumber ?? 1}',
        title: topic.title,
        siteUrl: siteUrl,
        child: DButton(
          key: ValueKey('category-featured-topic-${topic.id}'),
          variant: DButtonVariant.inline,
          size: DButtonSize.small,
          tooltip: status,
          icon: DIcon(icon, size: 13, semanticLabel: status),
          label: TopicTitle(
            topic.title,
            siteUrl: siteUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: unread
                  ? DTokens.of(context).foreground
                  : DTokens.of(context).mutedForeground,
              fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          onPressed: () => ShellScope.read(context).openFeaturedTopic(topic),
        ),
      ),
    );
  }
}

class _CategoryErrorBanner extends StatelessWidget {
  const _CategoryErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DAlert(
      variant: DAlertVariant.destructive,
      icon: const DIcon(DIcons.triangleExclamation),
      description: DAlertDescription(child: Text(message)),
      action: DAlertAction(
        child: DButton(
          label: Text(context.l10n.retry),
          onPressed: onRetry,
          variant: DButtonVariant.link,
        ),
      ),
    ),
  );
}

class _CategoryPageState extends StatelessWidget {
  const _CategoryPageState({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final DIconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: DEmpty(
        children: [
          DEmptyHeader(
            children: [
              DEmptyMedia(variant: DEmptyMediaVariant.icon, child: DIcon(icon)),
              DEmptyTitle(title),
            ],
          ),
          if (actionLabel case final label?)
            DEmptyContent(
              children: [DButton(label: Text(label), onPressed: onAction)],
            ),
        ],
      ),
    ),
  );
}
