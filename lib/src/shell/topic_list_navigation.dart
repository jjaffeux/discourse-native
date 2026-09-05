import 'dart:async';

import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/sidebar_tag.dart';
import '../models/topic.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
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
  const TopicListNavigation({super.key, required this.child, this.trailing});

  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) =>
      ShellSelector<_TopicListNavigationSnapshot>(
        select: (controller) {
          final counts = controller.topicListNewCounts;
          final siteUrl = controller.currentInstance?.url;
          final route = controller.currentContent;
          final showsFilters = route?.isTopicListFilter == true;
          return (
            mode: controller.currentTopicListMode,
            signedIn: controller.currentInstance?.user != null,
            unifiedNew:
                controller.currentInstance?.user?.unifiedNewEnabled == true,
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
          final showsTabs = state.signedIn && state.mode != null;
          final showsFilters =
              state.siteUrl != null && state.route?.isTopicListFilter == true;
          if (!showsTabs && !showsFilters && trailing == null) return child;
          return Column(
            children: [
              _TopicListNavigationControls(
                state: state,
                showsTabs: showsTabs,
                showsFilters: showsFilters,
                trailing: trailing,
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
  });

  final _TopicListNavigationSnapshot state;
  final bool showsTabs;
  final bool showsFilters;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
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
          if (showsTabs || trailing != null)
            ContentReadingLaneBox(
              widthLimit: topicListContentWidth,
              child: Row(
                key: const ValueKey('topic-list-primary-row'),
                children: [
                  Expanded(
                    child: !showsTabs
                        ? const SizedBox.shrink()
                        : _TopicListTabStrip(
                            height: 52,
                            background: theme.shell.content,
                            scrollable: true,
                            items: [
                              _TopicListTabItem(
                                controlKey: const ValueKey('topic-list-latest'),
                                label: 'Recent',
                                textStyle: primaryTextStyle,
                                selected: mode == TopicListMode.latest,
                                onTap: () => unawaited(
                                  controller.selectTopicListMode(
                                    TopicListMode.latest,
                                  ),
                                ),
                              ),
                              _TopicListTabItem(
                                controlKey: const ValueKey('topic-list-new'),
                                label: 'New',
                                count: state.allCount,
                                showCountBadge: true,
                                textStyle: primaryTextStyle,
                                selected: mode.isNew,
                                onTap: () => unawaited(
                                  controller.selectTopicListMode(
                                    TopicListMode.newActivity,
                                  ),
                                ),
                              ),
                              _TopicListTabItem(
                                controlKey: const ValueKey('topic-list-top'),
                                label: 'Top',
                                textStyle: primaryTextStyle,
                                selected: mode.isTop,
                                onTap: () => unawaited(
                                  controller.selectTopicListMode(
                                    mode.isTop
                                        ? mode
                                        : controller.defaultTopTopicListMode,
                                  ),
                                ),
                              ),
                              _TopicListTabItem(
                                controlKey: const ValueKey(
                                  'topic-list-popular',
                                ),
                                label: 'Trending',
                                textStyle: primaryTextStyle,
                                selected: mode == TopicListMode.popular,
                                onTap: () => unawaited(
                                  controller.selectTopicListMode(
                                    TopicListMode.popular,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  if (!showsFilters &&
                      TopicListDensityScope.maybeOf(context) != null)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: _TopicListDensityButton(),
                    ),
                  if (trailing != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        right: topicListHorizontalPadding,
                      ),
                      child: trailing,
                    ),
                ],
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
                    onTap: () => unawaited(
                      controller.selectTopicListMode(TopicListMode.newActivity),
                    ),
                  ),
                  _TopicListTabItem(
                    controlKey: const ValueKey('topic-list-new-topics'),
                    label: 'Topics',
                    count: state.topicCount,
                    textStyle: secondaryTextStyle,
                    selected: mode == TopicListMode.newTopics,
                    onTap: () => unawaited(
                      controller.selectTopicListMode(TopicListMode.newTopics),
                    ),
                  ),
                  _TopicListTabItem(
                    controlKey: const ValueKey('topic-list-new-replies'),
                    label: 'Replies',
                    count: state.replyCount,
                    textStyle: secondaryTextStyle,
                    selected: mode == TopicListMode.newReplies,
                    onTap: () => unawaited(
                      controller.selectTopicListMode(TopicListMode.newReplies),
                    ),
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
                  onSelected: (value) => unawaited(
                    controller.selectTopicListMode(TopicListMode.top(value)),
                  ),
                ),
              ),
          if (showsFilters)
            TopicListFilterBar(
              siteUrl: state.siteUrl!,
              categories: state.categories,
              knownTags: state.tags,
              selectedCategoryId: state.route!.categoryId,
              selectedTagName: state.route!.tagName,
              taggingEnabled: state.taggingEnabled,
              searchTags: (term) => controller.searchFilterTags(
                siteUrl: state.siteUrl!,
                term: term,
              ),
              onCategorySelected: controller.selectTopicListCategory,
              onTagSelected: controller.selectTopicListTag,
              onReset: controller.clearTopicListFilters,
              trailing: TopicListDensityScope.maybeOf(context) == null
                  ? null
                  : const _TopicListDensityButton(),
            ),
        ],
      ),
    );
  }
}

class _TopicListDensityButton extends StatelessWidget {
  const _TopicListDensityButton();

  @override
  Widget build(BuildContext context) {
    final compact = TopicListDensityScope.maybeOf(context)!;
    return Semantics(
      toggled: compact.value,
      child: DButton.iconOnly(
        key: const ValueKey('topic-list-density'),
        icon: const DIcon(DIcons.list, size: 16),
        tooltip: compact.value ? 'Comfortable rows' : 'Compact rows',
        onPressed: () => compact.value = !compact.value,
        variant: DButtonVariant.flat,
        size: DButtonSize.small,
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
    this.scrollable = false,
  });

  final double height;
  final Color background;
  final List<_TopicListTabItem> items;
  final double compactWidth;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(
        horizontal: topicListHorizontalPadding,
      ),
      color: background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (scrollable) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Row(
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
              ),
            );
          }
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
  });

  final Key controlKey;
  final String label;
  final TextStyle? textStyle;
  final int count;
  final bool showCountBadge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayLabel = count > 0 && !showCountBadge
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
            child: showCountBadge && count > 0
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
