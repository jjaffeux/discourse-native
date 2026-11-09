import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/count_label.dart';
import '../foundation/icons/d_icons.dart';
import '../models/category_directory.dart';
import '../models/category_feed.dart';
import '../models/category_sidebar.dart';
import '../models/content_route.dart';
import '../models/json.dart';
import '../models/topic.dart';
import '../theme/discourse_typography.dart';
import '../utils/pagination.dart';
import 'category_icon.dart';
import 'directory_skeleton.dart';
import 'forum_tab_scope.dart';
import 'open_link.dart';
import 'relative_time.dart';
import 'search_words.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_category_path_selector.dart';

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
  int? _parentCategoryId;

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
      _parentCategoryId = null;
      _requestFirstPage();
    }
  }

  void _requestFirstPage({bool retry = false}) {
    final controller = ShellScope.identityOf(context);
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

  static bool _admitsNextPage(CategoryFeed feed) => ScrollPagingGate(
    hasMore: feed.hasMore,
    busy: feed.loading || feed.loadingMore,
    lastPageFailed: feed.error != null,
  ).admits;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.extentAfter >=
            paginationPrefetchDistance(notification.metrics)) {
      return false;
    }
    if (_admitsNextPage(widget.feed)) {
      unawaited(ShellScope.read(context).loadMoreCategories(widget.siteUrl));
    }
    return false;
  }

  void _scheduleVisibleEndCheck() {
    if (_endCheckScheduled || !_admitsNextPage(widget.feed)) return;
    _endCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _endCheckScheduled = false;
      _loadMoreIfEndVisible();
    });
  }

  void _loadMoreIfEndVisible() {
    if (!mounted || !_scrollController.hasClients) return;
    if (_admitsNextPage(widget.feed) &&
        _scrollController.position.extentAfter <= 0.5) {
      unawaited(ShellScope.read(context).loadMoreCategories(widget.siteUrl));
    }
  }

  // A taller viewport reveals the end without rebuilding this page.
  bool _onScrollMetrics(ScrollMetricsNotification notification) {
    if (notification.depth == 0) _loadMoreIfEndVisible();
    return false;
  }

  void _resetScroll() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) => ShellSelector<Object?>(
    select: (controller) => (
      controller.currentUserFor(widget.siteUrl),
      controller.filterCategoriesFor(widget.siteUrl),
      controller.siteConfigFor(widget.siteUrl).maxCategoryNesting,
      // Counts decide which rows exist only in the Unread scope. Every other
      // scope lists the same rows, and each card follows its own badge.
      _scope == CategoryDirectoryScope.unread
          ? controller.categoryUnreadTopicCountsFor(widget.siteUrl)
          : null,
    ),
    builder: (context, _, _) => _buildPage(context),
  );

  Widget _buildPage(BuildContext context) {
    final feed = widget.feed;
    final controller = ShellScope.read(context);
    final user = controller.currentUserFor(widget.siteUrl);
    final counts = controller.categoryUnreadTopicCountsFor(widget.siteUrl);
    final scope = user == null && _scope == CategoryDirectoryScope.unread
        ? CategoryDirectoryScope.all
        : _scope;
    final categories = controller.filterCategoriesFor(widget.siteUrl);
    final muted = {
      ...?user?.mutedCategoryIds,
      ...?user?.indirectlyMutedCategoryIds,
    };
    final directory = CategoryDirectory(
      rootCategoryIds: feed.categoryIds,
      categories: categories,
    );
    final parentId = directory.containsCategory(_parentCategoryId)
        ? _parentCategoryId
        : null;
    final words = SearchWords.of(context);
    final queryWords = searchWords(
      words,
    ).map((word) => word.toLowerCase()).toList();
    final searching = queryWords.isNotEmpty;
    final entries = directory.entries(
      parentCategoryId: parentId,
      searching: searching,
      scope: scope,
      matchesCategory: searching
          ? (category) => _matchesCategorySearch(category, queryWords)
          : null,
      unreadTopicCounts: counts ?? const {},
      mutedCategoryIds: muted,
    );
    _scheduleVisibleEndCheck();

    final loadingFilteredResults =
        feed.loadingMore ||
        feed.hasMore ||
        (scope == CategoryDirectoryScope.unread && counts == null);
    final loading =
        (feed.categoryIds.isEmpty && (!feed.loaded || feed.loading)) ||
        (entries.isEmpty &&
            !feed.isEmpty &&
            feed.error == null &&
            loadingFilteredResults);
    return DScrollChromePagination(
      hasMore: feed.hasMore,
      loading: feed.loadingMore,
      child: DPageSurface.headed(
        title: Text(context.l10n.categories),
        controls: DReferenceTextScale(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wrap =
                  constraints.maxWidth < 600 &&
                  MediaQuery.textScalerOf(context).scale(14) > 21;
              final path = TopicCategoryPathSelector(
                keyPrefix: 'categories',
                siteUrl: widget.siteUrl,
                categories: directory.accessibleCategories.toList(),
                selectedCategoryId: parentId,
                maxCategoryNesting: controller
                    .siteConfigFor(widget.siteUrl)
                    .maxCategoryNesting,
                onSelected: (category) {
                  setState(() => _parentCategoryId = category?.id);
                  _resetScroll();
                },
              );
              return DControlWrap(
                spacing: 8,
                runSpacing: 8,
                wrap: wrap,
                children: [
                  if (words.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 128),
                      child: DButton(
                        key: const ValueKey('categories-search-words'),
                        variant: DButtonVariant.quietSelected,
                        size: DButtonSize.filter,
                        icon: const DIcon(DIcons.magnifyingGlass, size: 11),
                        label: Text(
                          '“$words”',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const DIcon(DIcons.xmark, size: 10),
                        tooltip: context.l10n.clearSearch,
                        semanticLabel: '${context.l10n.clearSearch}: $words',
                        onPressed: () {
                          controller.search.setPageWords(
                            widget.siteUrl,
                            ForumTabScope.idOf(context) ??
                                controller.activeTabId,
                            'all-categories',
                            '',
                          );
                          _resetScroll();
                        },
                      ),
                    ),
                  DSelect<CategoryDirectoryScope>.controlled(
                    size: DControlSize.filter,
                    width: 128,
                    key: ValueKey(('category-scope', widget.siteUrl)),
                    value: scope,
                    semanticLabel: context.l10n.categoryDirectoryScope,
                    triggerBuilder: (context, state, _) => DButton(
                      size: DButtonSize.filter,
                      variant: DButtonVariant.quiet,
                      label: Text(
                        _scopeLabel(context, scope),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      semanticLabel: context.l10n.categoryDirectoryScope,
                      focusNode: state.focusNode,
                      hasPopup: true,
                      expanded: state.open,
                      onPressed: state.toggle,
                    ),
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
                      _resetScroll();
                    },
                  ),
                  if (wrap) path else DControlExpanded(child: path),
                ],
              );
            },
          ),
        ),
        bodyBuilder: (context, header) => DPageReadingLane(
          builder: (context, lane) =>
              NotificationListener<ScrollMetricsNotification>(
                onNotification: _onScrollMetrics,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: header.spacer),
                      SliverPadding(
                        padding: lane.padding.add(
                          EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16 + DScrollChrome.bottomInsetOf(context),
                          ),
                        ),
                        sliver: SliverMainAxisGroup(
                          slivers: [
                            if (loading)
                              SliverLayoutBuilder(
                                builder: (context, constraints) =>
                                    SliverToBoxAdapter(
                                      child: SizedBox(
                                        height:
                                            (constraints.viewportMainAxisExtent -
                                                    constraints
                                                        .precedingScrollExtent -
                                                    lane.padding.bottom -
                                                    16 -
                                                    DScrollChrome.bottomInsetOf(
                                                      context,
                                                    ))
                                                .clamp(0, double.infinity),
                                        child: const DirectorySkeleton(
                                          kind:
                                              DirectorySkeletonKind.categories,
                                        ),
                                      ),
                                    ),
                              )
                            else if (feed.error != null &&
                                feed.categoryIds.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: _CategoryPageState(
                                  icon: DIcons.triangleExclamation,
                                  title: feed.error!,
                                  actionLabel: context.l10n.tryAgain,
                                  onAction: _retry,
                                ),
                              )
                            else if (feed.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: _CategoryPageState(
                                  icon: DIcons.list,
                                  title: context.l10n.noCategoriesYet,
                                ),
                              )
                            else ...[
                              if (!feed.pageError && feed.error != null)
                                SliverToBoxAdapter(
                                  child: _CategoryErrorBanner(
                                    message: feed.error!,
                                    onRetry: _retry,
                                  ),
                                ),
                              _CategoryGrid(
                                siteUrl: widget.siteUrl,
                                entries: entries,
                                categoriesById: directory.categoriesById,
                              ),
                              if (entries.isEmpty && feed.error == null)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 24,
                                    ),
                                    child: DText(
                                      scope == CategoryDirectoryScope.unread
                                          ? context.l10n.noUnreadCategories
                                          : scope ==
                                                CategoryDirectoryScope
                                                    .withTopics
                                          ? context.l10n.noCategoriesWithTopics
                                          : context.l10n.nothingHereYet,
                                      style: TextStyle(
                                        fontSize: DiscourseTypography.compact,
                                        color: DTokens.of(
                                          context,
                                        ).mutedForeground,
                                      ),
                                    ),
                                  ),
                                ),
                              if (feed.pageError && feed.error != null)
                                SliverToBoxAdapter(
                                  child: _CategoryErrorBanner(
                                    message: feed.error!,
                                    onRetry: _retry,
                                  ),
                                ),
                            ],
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

  String _scopeLabel(BuildContext context, CategoryDirectoryScope scope) =>
      switch (scope) {
        CategoryDirectoryScope.all => context.l10n.allCategoriesCategorysidebar,
        CategoryDirectoryScope.unread => context.l10n.unread,
        CategoryDirectoryScope.withTopics => context.l10n.categoriesWithTopics,
      };
}

bool _matchesCategorySearch(TopicCategory category, List<String> queryWords) {
  final name = category.name.toLowerCase();
  final description = (jsonHtmlText(category.descriptionExcerpt) ?? '')
      .toLowerCase();
  return queryWords.every(
    (word) => name.contains(word) || description.contains(word),
  );
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.siteUrl,
    required this.entries,
    required this.categoriesById,
  });
  final String siteUrl;
  final List<CategoryDirectoryEntry> entries;
  final Map<int, TopicCategory> categoriesById;

  @override
  Widget build(BuildContext context) => ForumTabSelector<ContentRoute?>(
    select: (_, tab) => tab.activeTab?.listBefore(CorePage.categories),
    builder: (context, list, _) {
      final currentId = list?.categoryId;
      return DPlaceCardGrid(
        itemCount: entries.length,
        itemBuilder: (context, index) => _CategoryCard(
          key: ValueKey('category-row-${entries[index].category.id}'),
          siteUrl: siteUrl,
          entry: entries[index],
          categoriesById: categoriesById,
          selected: entries[index].category.id == currentId,
        ),
      );
    },
  );
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    super.key,
    required this.siteUrl,
    required this.entry,
    required this.categoriesById,
    required this.selected,
  });
  final String siteUrl;
  final CategoryDirectoryEntry entry;
  final Map<int, TopicCategory> categoriesById;
  final bool selected;

  @override
  Widget build(BuildContext context) => ShellSelector<int>(
    select: (controller) => entry.unreadTopicCountIn(
      controller.categoryUnreadTopicCountsFor(siteUrl) ?? const {},
    ),
    builder: (context, unreadTopicCount, _) =>
        _buildCard(context, unreadTopicCount),
  );

  Widget _buildCard(BuildContext context, int unreadTopicCount) {
    final controller = ShellScope.read(context);
    final category = entry.category;
    final tokens = DTokens.of(context);
    final unread = unreadTopicCount > 0;
    final latest = entry.latestTopic?.activityAt;
    final description = jsonHtmlText(category.descriptionExcerpt);
    final route = ContentRoute.fromDestination(
      buildCategoryDestination(category, categoriesById: categoriesById),
    );
    return LinkTarget.content(
      content: route,
      siteUrl: siteUrl,
      child: DPlaceCard(
        onPressed: () => controller.openCategory(category, siteUrl: siteUrl),
        strong: unread,
        muted: entry.muted,
        selected: selected,
        unreadCount: unread ? unreadTopicCount.toString() : null,
        semanticLabel: unread
            ? context.l10n.categoryUnreadTopics(unreadTopicCount)
            : null,
        leading: DPlaceCardMark(
          color: Color(category.colorValue),
          child: CategoryIcon(
            category: category,
            siteUrl: siteUrl,
            size: 13,
            showLock: false,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: SearchText(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
        description: description != null && description.isNotEmpty
            ? SearchText(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        footer: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                countLabel(entry.topicCount, CountNoun.topic),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (latest != null) ...[
              const Text(' · '),
              RelativeTimeText(latest),
            ],
          ],
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
