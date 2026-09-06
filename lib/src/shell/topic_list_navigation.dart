import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/content_route.dart';
import '../models/sidebar_tag.dart';
import '../models/topic.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_picker.dart';
import 'content_reading_lane.dart';
import 'list_navigation_tab.dart';
import 'shell_scope.dart';
import 'topic_list_filter_bar.dart';
import 'topic_list_layout.dart';
import 'topic_list_view.dart';

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
    Widget filters({bool showColumns = false}) => TopicListFilterBar(
      inline: !stacked || showColumns,
      wrap: stacked && !showColumns,
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
      fontSize: stacked ? DiscourseTypography.fontDown1 : null,
      height: stacked ? 1.2 : null,
    );
    final secondaryTextStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w400,
      fontSize: stacked ? DiscourseTypography.fontDown1 : null,
      height: stacked ? 1.2 : null,
    );
    final primaryHeight = stacked
        ? (MediaQuery.textScalerOf(
                        context,
                      ).scale(DiscourseTypography.fontDown1) *
                      1.2 +
                  16)
              .ceilToDouble()
        : 52.0;

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
                      height: primaryHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: topicListHorizontalPadding,
                        ),
                        child: DecoratedBox(
                          key: const ValueKey('topic-list-feed-tabs'),
                          decoration: BoxDecoration(
                            border: stacked
                                ? Border(
                                    bottom: BorderSide(
                                      color: theme.shell.divider,
                                    ),
                                  )
                                : null,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (showsFilters && !stacked) filters(),
                                      if (showsTabs && showsFilters && !stacked)
                                        const SizedBox(width: 8),
                                      if (showsTabs)
                                        _TopicListTabStrip(
                                          height: primaryHeight,
                                          background: theme.shell.content,
                                          inline: true,
                                          spacing: stacked ? 17 : 3,
                                          items: [
                                            ListNavigationTab(
                                              underline: stacked,
                                              controlKey: const ValueKey(
                                                'topic-list-latest',
                                              ),
                                              label: 'Recent',
                                              textStyle: primaryTextStyle,
                                              selected:
                                                  mode == TopicListMode.latest,
                                              onTap: () => unawaited(
                                                selectMode(
                                                  TopicListMode.latest,
                                                ),
                                              ),
                                            ),
                                            if (state.signedIn)
                                              ListNavigationTab(
                                                underline: stacked,
                                                controlKey: const ValueKey(
                                                  'topic-list-new',
                                                ),
                                                label: 'New',
                                                count: state.allCount,
                                                showCount: !stacked,
                                                showCountBadge: true,
                                                textStyle: primaryTextStyle,
                                                selected: mode.isNew,
                                                onTap: () => unawaited(
                                                  selectMode(
                                                    TopicListMode.newActivity,
                                                  ),
                                                ),
                                              ),
                                            ListNavigationTab(
                                              underline: stacked,
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
                                            ListNavigationTab(
                                              underline: stacked,
                                              controlKey: const ValueKey(
                                                'topic-list-popular',
                                              ),
                                              label: 'Trending',
                                              textStyle: primaryTextStyle,
                                              selected:
                                                  mode == TopicListMode.popular,
                                              onTap: () => unawaited(
                                                selectMode(
                                                  TopicListMode.popular,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
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
                segmented: stacked,
                items: [
                  ListNavigationTab(
                    segmented: stacked,
                    controlKey: const ValueKey('topic-list-new-all'),
                    label: 'All',
                    count: state.allCount,
                    textStyle: secondaryTextStyle,
                    selected: mode == TopicListMode.newActivity,
                    onTap: () =>
                        unawaited(selectMode(TopicListMode.newActivity)),
                  ),
                  ListNavigationTab(
                    segmented: stacked,
                    controlKey: const ValueKey('topic-list-new-topics'),
                    label: 'Topics',
                    count: state.topicCount,
                    textStyle: secondaryTextStyle,
                    selected: mode == TopicListMode.newTopics,
                    onTap: () => unawaited(selectMode(TopicListMode.newTopics)),
                  ),
                  ListNavigationTab(
                    segmented: stacked,
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
          if (stacked)
            TopicListHeader(
              filtersBuilder: showsFilters
                  ? (showColumns) => filters(showColumns: showColumns)
                  : null,
            ),
        ],
      ),
    );
  }
}

class _TopPeriodChooser extends StatefulWidget {
  const _TopPeriodChooser({
    required this.period,
    required this.textStyle,
    required this.onSelected,
  });

  final TopPeriod period;
  final TextStyle? textStyle;
  final ValueChanged<TopPeriod> onSelected;

  @override
  State<_TopPeriodChooser> createState() => _TopPeriodChooserState();
}

class _TopPeriodChooserState extends State<_TopPeriodChooser> {
  final GlobalKey _anchorKey = GlobalKey();
  bool _showing = false;

  Future<void> _show() async {
    final anchorContext = _anchorKey.currentContext;
    if (_showing || anchorContext == null) return;
    _showing = true;
    try {
      final selected = await showAnchoredPicker<TopPeriod>(
        context: context,
        anchorContext: anchorContext,
        title: 'Top topics',
        barrierLabel: 'Dismiss time range picker',
        popoverKey: const ValueKey('topic-list-top-period-popover'),
        popoverHeight: null,
        popoverPadding: const EdgeInsets.symmetric(vertical: 6),
        builder: (pickerContext) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                FocusScope.of(pickerContext).nextFocus(),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                FocusScope.of(pickerContext).previousFocus(),
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(pickerContext).pop(),
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in TopPeriod.values)
                AnchoredPickerOption(
                  key: ValueKey('topic-list-top-period-${option.queryValue}'),
                  title: Text(option.label),
                  selected: option == widget.period,
                  autofocus: option == widget.period,
                  trailing: option == widget.period
                      ? DIcon(
                          DIcons.check,
                          size: 14,
                          color: Theme.of(pickerContext).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(pickerContext).pop(option),
                ),
            ],
          ),
        ),
      );
      if (mounted && selected != null && selected != widget.period) {
        widget.onSelected(selected);
      }
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _TopicListSubnavigationSurface(
      surfaceKey: const ValueKey('topic-list-top-period-segment'),
      child: Semantics(
        container: true,
        button: true,
        label: 'Top period',
        value: widget.period.label,
        onTap: _show,
        child: ExcludeSemantics(
          child: SizedBox(
            key: _anchorKey,
            child: TextButton(
              key: const ValueKey('topic-list-top-period'),
              onPressed: _show,
              style:
                  TextButton.styleFrom(
                    backgroundColor: theme.shell.content,
                    foregroundColor: theme.colorScheme.onSurface,
                    minimumSize: Size(
                      0,
                      _TopicListSubnavigationSurface.segmentHeight(context),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.standard,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ).copyWith(
                    side: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.focused)
                          ? BorderSide(
                              color: theme.colorScheme.primary,
                              width: 1.5,
                            )
                          : BorderSide.none,
                    ),
                  ),
              child: Row(
                children: [
                  DIcon(
                    DIcons.farClock,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.period.label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: widget.textStyle?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DIcon(
                    DIcons.chevronDown,
                    size: 10,
                    color: theme.colorScheme.onSurfaceVariant,
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

class _TopicListSubnavigationSurface extends StatelessWidget {
  const _TopicListSubnavigationSurface({
    required this.surfaceKey,
    required this.child,
  });

  final Key surfaceKey;
  final Widget child;

  static double segmentHeight(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(DiscourseTypography.fontDown1) *
                  1.2 +
              12)
          .ceilToDouble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        topicListHorizontalPadding,
        11,
        topicListHorizontalPadding,
        0,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          key: surfaceKey,
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: theme.shell.sidebar,
            border: Border.all(color: theme.shell.divider),
            borderRadius: BorderRadius.circular(7),
          ),
          child: child,
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
    this.spacing = 3,
    this.segmented = false,
  });

  final double height;
  final Color background;
  final List<ListNavigationTab> items;
  final double compactWidth;
  final bool inline;
  final double spacing;
  final bool segmented;

  @override
  Widget build(BuildContext context) {
    if (segmented) {
      final theme = Theme.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      final countStyle = theme.textTheme.labelSmall!.copyWith(
        fontSize: DiscourseTypography.fontDown2,
        height: 1.2,
      );
      // Keep full labels and tracking counts readable when text is enlarged.
      // The control scrolls only when three equal segments cannot fit.
      var segmentWidth = 0.0;
      for (final item in items) {
        final painter = TextPainter(
          text: TextSpan(
            children: [
              TextSpan(
                text: item.label,
                style: item.textStyle?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (item.count > 0)
                TextSpan(text: ' ${item.count}', style: countStyle),
            ],
          ),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        segmentWidth = math.max(
          segmentWidth,
          painter.width.ceilToDouble() + 14,
        );
        painter.dispose();
      }
      return _TopicListSubnavigationSurface(
        surfaceKey: const ValueKey('topic-list-new-segments'),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(
                constraints.maxWidth,
                segmentWidth * items.length + 2 * (items.length - 1),
              ),
              height: _TopicListSubnavigationSurface.segmentHeight(context),
              child: Row(
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    if (index > 0) const SizedBox(width: 2),
                    Expanded(child: items[index]),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (inline) {
      return SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0) SizedBox(width: spacing),
              IntrinsicWidth(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: items[index].underline ? 0 : 48,
                  ),
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
