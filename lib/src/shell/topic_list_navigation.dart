import 'dart:async';

import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/sidebar_tag.dart';
import '../models/topic.dart';
import '../theme/app_theme.dart';
import 'content_reading_lane.dart';
import 'select.dart';
import 'shell_scope.dart';
import 'topic_list_filter_bar.dart';
import 'topic_list_layout.dart';

typedef _TopicListNavigationSnapshot = ({
  TopicListMode? mode,
  bool signedIn,
  bool unifiedNew,
  int allCount,
  int topicCount,
  int replyCount,
  String? siteUrl,
  ContentRoute? route,
  List<TopicCategory> categories,
  List<SidebarTag> tags,
  bool taggingEnabled,
});

class TopicListNavigation extends StatelessWidget {
  const TopicListNavigation({
    super.key,
    required this.child,
    this.trailing,
    this.stacked = false,
    this.keepTopicOpen = false,
  });

  final Widget child;
  final Widget? trailing;
  final bool stacked;
  final bool keepTopicOpen;

  @override
  Widget build(
    BuildContext context,
  ) => ShellSelector<_TopicListNavigationSnapshot>(
    select: (controller) {
      final counts = controller.topicListNewCounts;
      final siteUrl = controller.currentInstance?.url;
      final route = controller.topicListContent ?? controller.currentContent;
      final showsFilters = route?.isTopicListFilter == true;
      return (
        mode: controller.currentTopicListMode,
        signedIn: controller.currentInstance?.user != null,
        unifiedNew: controller.currentInstance?.user?.unifiedNewEnabled == true,
        allCount: counts.all,
        topicCount: counts.topics,
        replyCount: counts.replies,
        siteUrl: siteUrl,
        route: route,
        categories: showsFilters && siteUrl != null
            ? controller.filterCategoriesFor(siteUrl)
            : const <TopicCategory>[],
        tags: showsFilters && siteUrl != null
            ? controller.topicListFilterTagsFor(siteUrl)
            : const <SidebarTag>[],
        taggingEnabled:
            showsFilters &&
            siteUrl != null &&
            controller.siteConfigFor(siteUrl).taggingEnabled,
      );
    },
    builder: (context, state, _) {
      final showsTabs = state.mode != null;
      final showsFilters =
          state.siteUrl != null && state.route?.isTopicListFilter == true;
      if (!showsTabs && !showsFilters && trailing == null) {
        return child;
      }
      return Column(
        children: [
          _TopicListNavigationControls(
            state: state,
            showsTabs: showsTabs,
            showsFilters: showsFilters,
            trailing: trailing,
            stacked: stacked,
            keepTopicOpen: keepTopicOpen,
          ),
          Expanded(child: child),
        ],
      );
    },
  );
}

class _TopicListNavigationControls extends StatelessWidget {
  const _TopicListNavigationControls({
    required this.state,
    required this.showsTabs,
    required this.showsFilters,
    required this.trailing,
    required this.stacked,
    required this.keepTopicOpen,
  });

  final _TopicListNavigationSnapshot state;
  final bool showsTabs;
  final bool showsFilters;
  final Widget? trailing;
  final bool stacked;
  final bool keepTopicOpen;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    Future<void> selectMode(TopicListMode mode) =>
        controller.selectTopicListMode(mode, keepTopicOpen: keepTopicOpen);
    Widget filters() => TopicListFilterBar(
      inline: !stacked,
      wrap: stacked,
      siteUrl: state.siteUrl!,
      categories: state.categories,
      knownTags: state.tags,
      selectedCategoryId: state.route!.categoryId,
      selectedTagName: state.route!.tagName,
      selectedTagNames: stacked ? state.route!.tagNames : null,
      onTagsSelected: stacked
          ? (values) => controller.selectTopicListTags(
              values,
              keepTopicOpen: keepTopicOpen,
            )
          : null,
      taggingEnabled: state.taggingEnabled,
      searchTags: (term) =>
          controller.searchFilterTags(siteUrl: state.siteUrl!, term: term),
      onCategorySelected: (value) => controller.selectTopicListCategory(
        value,
        keepTopicOpen: keepTopicOpen,
      ),
      onTagSelected: (value) =>
          controller.selectTopicListTag(value, keepTopicOpen: keepTopicOpen),
    );
    final mode = state.mode ?? TopicListMode.latest;
    final theme = Theme.of(context);
    final primaryTextStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w400,
    );
    final secondaryTextStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w400,
    );

    return Semantics(
      key: const ValueKey('topic-list-navigation'),
      container: true,
      label: 'Topic lists',
      child: Column(
        children: [
          if (showsTabs || showsFilters || trailing != null)
            ContentReadingLaneBox(
              widthLimit: topicListContentWidth,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final mediaQuery = MediaQuery.of(context);
                  final toolbarWidth = ContentReadingLane.breakpointWidthOf(
                    context,
                    constraints.maxWidth,
                  );
                  return Material(
                    color: theme.shell.content,
                    child: SizedBox(
                      key: const ValueKey('topic-list-primary-row'),
                      height: 52,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: topicListHorizontalPadding,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (showsTabs)
                                      _TopicListTabStrip(
                                        height: 52,
                                        background: theme.shell.content,
                                        inline: true,
                                        items: [
                                          _TopicListTabItem(
                                            controlKey: const ValueKey(
                                              'topic-list-latest',
                                            ),
                                            label: 'Recent',
                                            textStyle: primaryTextStyle,
                                            selected:
                                                mode == TopicListMode.latest,
                                            onTap: () => unawaited(
                                              selectMode(TopicListMode.latest),
                                            ),
                                          ),
                                          if (state.signedIn)
                                            _TopicListTabItem(
                                              controlKey: const ValueKey(
                                                'topic-list-new',
                                              ),
                                              label: 'New',
                                              count: state.allCount,
                                              showCount:
                                                  !stacked ||
                                                  constraints.maxWidth >= 500,
                                              showCountBadge: true,
                                              textStyle: primaryTextStyle,
                                              selected: mode.isNew,
                                              onTap: () => unawaited(
                                                selectMode(
                                                  TopicListMode.newActivity,
                                                ),
                                              ),
                                            ),
                                          _TopicListTabItem(
                                            controlKey: const ValueKey(
                                              'topic-list-top',
                                            ),
                                            label: 'Top',
                                            textStyle: primaryTextStyle,
                                            selected: mode.isTop,
                                            onTap: () => unawaited(
                                              selectMode(
                                                mode.isTop
                                                    ? mode
                                                    : controller
                                                          .defaultTopTopicListMode,
                                              ),
                                            ),
                                          ),
                                          _TopicListTabItem(
                                            controlKey: const ValueKey(
                                              'topic-list-popular',
                                            ),
                                            label: 'Trending',
                                            textStyle: primaryTextStyle,
                                            selected:
                                                mode == TopicListMode.popular,
                                            onTap: () => unawaited(
                                              selectMode(TopicListMode.popular),
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (showsTabs && showsFilters && !stacked)
                                      const SizedBox(width: 8),
                                    if (showsFilters && !stacked) filters(),
                                  ],
                                ),
                              ),
                            ),
                            if (trailing != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: MediaQuery(
                                  data: mediaQuery.copyWith(
                                    size: Size(
                                      toolbarWidth,
                                      mediaQuery.size.height,
                                    ),
                                  ),
                                  child: trailing!,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (showsTabs && mode.isNew && state.unifiedNew)
            ContentReadingLaneBox(
              widthLimit: topicListContentWidth,
              child: _TopicListTabStrip(
                height: 44,
                background: theme.shell.sidebar,
                compactWidth: 480,
                items: [
                  _TopicListTabItem(
                    controlKey: const ValueKey('topic-list-new-all'),
                    label: 'All',
                    count: state.allCount,
                    textStyle: secondaryTextStyle,
                    selected: mode == TopicListMode.newActivity,
                    onTap: () =>
                        unawaited(selectMode(TopicListMode.newActivity)),
                  ),
                  _TopicListTabItem(
                    controlKey: const ValueKey('topic-list-new-topics'),
                    label: 'Topics',
                    count: state.topicCount,
                    textStyle: secondaryTextStyle,
                    selected: mode == TopicListMode.newTopics,
                    onTap: () => unawaited(selectMode(TopicListMode.newTopics)),
                  ),
                  _TopicListTabItem(
                    controlKey: const ValueKey('topic-list-new-replies'),
                    label: 'Replies',
                    count: state.replyCount,
                    textStyle: secondaryTextStyle,
                    selected: mode == TopicListMode.newReplies,
                    onTap: () =>
                        unawaited(selectMode(TopicListMode.newReplies)),
                  ),
                ],
              ),
            ),
          if (showsTabs)
            if (mode.topPeriod case final period?)
              ContentReadingLaneBox(
                widthLimit: topicListContentWidth,
                child: _TopPeriodChooser(
                  period: period,
                  textStyle: secondaryTextStyle,
                  onSelected: (value) =>
                      unawaited(selectMode(TopicListMode.top(value))),
                ),
              ),
          if (showsFilters && stacked)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: filters(),
            ),
        ],
      ),
    );
  }
}

class _TopPeriodChooser extends StatelessWidget {
  const _TopPeriodChooser({
    required this.period,
    required this.textStyle,
    required this.onSelected,
  });

  final TopPeriod period;
  final TextStyle? textStyle;
  final ValueChanged<TopPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(
        horizontal: topicListHorizontalPadding,
      ),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: theme.shell.sidebar,
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: Semantics(
        button: true,
        label: 'Top period',
        value: period.label,
        child: DropdownButtonHideUnderline(
          child: DSelect<TopPeriod>(
            key: const ValueKey('topic-list-top-period'),
            value: period,
            items: [
              for (final option in TopPeriod.values)
                DropdownMenuItem(
                  key: ValueKey('topic-list-top-period-${option.queryValue}'),
                  value: option,
                  child: Text(option.label, style: textStyle),
                ),
            ],
            onChanged: (value) {
              if (value != null) onSelected(value);
            },
          ),
        ),
      ),
    );
  }
}

class _TopicListTabStrip extends StatelessWidget {
  const _TopicListTabStrip({
    required this.height,
    required this.background,
    required this.items,
    this.compactWidth = 400,
    this.inline = false,
  });

  final double height;
  final Color background;
  final List<_TopicListTabItem> items;
  final double compactWidth;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    if (inline) {
      return SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0) const SizedBox(width: 3),
              IntrinsicWidth(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 48),
                  child: items[index],
                ),
              ),
            ],
          ],
        ),
      );
    }
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(
        horizontal: topicListHorizontalPadding,
      ),
      color: background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < compactWidth) {
            return Row(
              children: [for (final item in items) Expanded(child: item)],
            );
          }
          return Row(
            children: [
              for (final item in items)
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 112),
                  child: item,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TopicListTabItem extends StatelessWidget {
  const _TopicListTabItem({
    required this.controlKey,
    required this.label,
    required this.textStyle,
    required this.selected,
    required this.onTap,
    this.count = 0,
    this.showCountBadge = false,
    this.showCount = true,
  });

  final Key controlKey;
  final String label;
  final TextStyle? textStyle;
  final int count;
  final bool showCountBadge;
  final bool showCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayLabel = showCount && count > 0 && !showCountBadge
        ? '$label ($count)'
        : label;
    final labelWidget = Text(
      displayLabel,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      style: textStyle?.copyWith(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
        fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: count > 0 ? '$label, $count' : label,
      child: ExcludeSemantics(
        child: InkWell(
          key: controlKey,
          onTap: onTap,
          hoverColor: theme.shell.hover,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            alignment: Alignment.center,
            margin: const EdgeInsets.symmetric(vertical: 9),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? theme.shell.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: showCount && showCountBadge && count > 0
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      labelWidget,
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.shell.hover,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$count',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  )
                : labelWidget,
          ),
        ),
      ),
    );
  }
}
