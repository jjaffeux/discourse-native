import 'dart:async';

import 'package:flutter/material.dart';

import '../models/category_feed.dart';
import '../models/topic.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'site_emoji_image.dart';
import 'topic_title.dart';

/// The native version of Discourse's `categories_boxes_with_topics` page.
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
    if (oldWidget.siteUrl != widget.siteUrl) _requestFirstPage();
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
    if (notification.depth != 0 || notification.metrics.extentAfter >= 600) {
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
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (feed.error != null && feed.categoryIds.isEmpty) {
      return _CategoryPageState(
        icon: DIcons.triangleExclamation,
        title: feed.error!,
        actionLabel: 'Try again',
        onAction: _retry,
      );
    }
    if (feed.isEmpty) {
      return const _CategoryPageState(
        icon: DIcons.list,
        title: 'No categories yet',
      );
    }

    _scheduleVisibleEndCheck();

    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 16.0;
        const gap = 12.0;
        final availableWidth = constraints.maxWidth - horizontalPadding * 2;
        final columns = _columnsFor(availableWidth);
        final cardWidth = (availableWidth - gap * (columns - 1)) / columns;

        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (feed.loading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (!feed.pageError && feed.error != null)
                  _CategoryErrorBanner(message: feed.error!, onRetry: _retry),
                _CategoryGrid(
                  siteUrl: widget.siteUrl,
                  categoryIds: feed.categoryIds,
                  columns: columns,
                  cardWidth: cardWidth,
                  gap: gap,
                ),
                if (feed.loadingMore)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ),
                if (feed.pageError && feed.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _CategoryErrorBanner(
                      message: feed.error!,
                      onRetry: _retry,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static int _columnsFor(double width) {
    if (width >= 960) return 3;
    if (width >= 620) return 2;
    return 1;
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.siteUrl,
    required this.categoryIds,
    required this.columns,
    required this.cardWidth,
    required this.gap,
  });

  final String siteUrl;
  final List<int> categoryIds;
  final int columns;
  final double cardWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final rows = <List<int>>[];
    for (var start = 0; start < categoryIds.length; start += columns) {
      rows.add(categoryIds.skip(start).take(columns).toList(growable: false));
    }

    return Column(
      children: [
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
          if (rowIndex > 0) SizedBox(height: gap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (column > 0) SizedBox(width: gap),
                  SizedBox(
                    width: cardWidth,
                    child: column < rows[rowIndex].length
                        ? _CategoryCardSlot(
                            key: ValueKey(
                              'category-card-${rows[rowIndex][column]}',
                            ),
                            siteUrl: siteUrl,
                            categoryId: rows[rowIndex][column],
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryCardSlot extends StatelessWidget {
  const _CategoryCardSlot({
    super.key,
    required this.siteUrl,
    required this.categoryId,
  });

  final String siteUrl;
  final int categoryId;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    return ValueListenableBuilder<TopicCategory?>(
      valueListenable: controller.categoryRef(siteUrl, categoryId),
      builder: (context, category, _) => category == null
          ? const SizedBox.shrink()
          : _CategoryCard(
              siteUrl: siteUrl,
              category: category,
              onTap: () => controller.openCategory(category),
            ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.siteUrl,
    required this.category,
    required this.onTap,
  });

  final String siteUrl;
  final TopicCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = category.isMuted
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;

    return Material(
      color: theme.shell.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: BorderSide(color: theme.shell.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: ColoredBox(
                color: Color(category.colorValue),
                child: const SizedBox(width: 5),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 118),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Wrap(
                        spacing: 7,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _CategoryArt(category: category, siteUrl: siteUrl),
                          Text(
                            category.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (category.readRestricted)
                            DIcon(
                              DIcons.lock,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                        ],
                      ),
                    ),
                    if (!category.isMuted &&
                        category.featuredTopics.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final topic in category.featuredTopics)
                        _FeaturedTopicRow(siteUrl: siteUrl, topic: topic),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryArt extends StatelessWidget {
  const _CategoryArt({required this.category, required this.siteUrl});

  final TopicCategory category;
  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    final emoji = category.emoji;
    if (category.styleType == 'emoji' && emoji != null) {
      return SiteEmojiImage(
        siteUrl: siteUrl,
        name: emoji,
        size: 15,
        alt: ':$emoji:',
        style: Theme.of(context).textTheme.labelSmall,
      );
    }
    if (category.styleType == 'icon') {
      return DIcon(
        DIcons.byName[category.icon] ?? DIcons.folder,
        size: 15,
        color: color,
      );
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _FeaturedTopicRow extends StatelessWidget {
  const _FeaturedTopicRow({required this.siteUrl, required this.topic});

  final String siteUrl;
  final CategoryFeaturedTopic topic;

  DIconData get _icon {
    if (topic.pinned) return DIcons.thumbtack;
    if (topic.closed || topic.archived) return DIcons.lock;
    return DIcons.farFileLines;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        key: ValueKey('category-featured-topic-${topic.id}'),
        onTap: () => ShellScope.read(context).openFeaturedTopic(topic),
        borderRadius: BorderRadius.circular(5),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: DIcon(
                  _icon,
                  size: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: TopicTitle(
                  topic.title,
                  siteUrl: siteUrl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
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

class _CategoryErrorBanner extends StatelessWidget {
  const _CategoryErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          DIcon(
            DIcons.triangleExclamation,
            size: 17,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DIcon(icon, size: 42, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (actionLabel case final label?) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onAction, child: Text(label)),
            ],
          ],
        ),
      ),
    );
  }
}
