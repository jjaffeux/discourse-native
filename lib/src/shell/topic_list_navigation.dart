import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/sidebar_tag.dart';
import '../models/topic.dart';
import '../theme/app_theme.dart';
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
                                            _TopicListTabItem(
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
                                              _TopicListTabItem(
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
                                            _TopicListTabItem(
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
                                            _TopicListTabItem(
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
                  _TopicListTabItem(
                    segmented: stacked,
                    controlKey: const ValueKey('topic-list-new-all'),
                    label: 'All',
                    count: state.allCount,
                    textStyle: secondaryTextStyle,
                    selected: mode == TopicListMode.newActivity,
                    onTap: () =>
                        unawaited(selectMode(TopicListMode.newActivity)),
                  ),
                  _TopicListTabItem(
                    segmented: stacked,
                    controlKey: const ValueKey('topic-list-new-topics'),
                    label: 'Topics',
                    count: state.topicCount,
                    textStyle: secondaryTextStyle,
                    selected: mode == TopicListMode.newTopics,
                    onTap: () => unawaited(selectMode(TopicListMode.newTopics)),
                  ),
                  _TopicListTabItem(
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
                  inbox: stacked,
                  period: period,
                  textStyle: secondaryTextStyle,
                  onSelected: (value) =>
                      unawaited(selectMode(TopicListMode.top(value))),
                ),
              ),
          if (showsFilters && stacked)
            ContentReadingLaneBox(
              widthLimit: topicListContentWidth,
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 12),
                child: filters(),
              ),
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
    this.inbox = false,
  });

  final TopPeriod period;
  final TextStyle? textStyle;
  final ValueChanged<TopPeriod> onSelected;
  final bool inbox;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (inbox) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          topicListHorizontalPadding,
          11,
          topicListHorizontalPadding,
          0,
        ),
        child: Row(
          children: [
            Text(
              'Period',
              style: textStyle?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Semantics(
                button: true,
                label: 'Top period',
                value: period.label,
                child: PopupMenuButton<TopPeriod>(
                  key: const ValueKey('topic-list-top-period'),
                  tooltip: 'Choose top period',
                  position: PopupMenuPosition.under,
                  initialValue: period,
                  onSelected: onSelected,
                  itemBuilder: (_) => [
                    for (final option in TopPeriod.values)
                      PopupMenuItem(
                        key: ValueKey(
                          'topic-list-top-period-${option.queryValue}',
                        ),
                        value: option,
                        child: Text(option.label, style: textStyle),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: theme.shell.content,
                      border: Border.all(color: theme.shell.divider),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DIcon(
                          DIcons.farClock,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            period.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textStyle,
                          ),
                        ),
                        const SizedBox(width: 7),
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
          ],
        ),
      );
    }
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
    this.spacing = 3,
    this.segmented = false,
  });

  final double height;
  final Color background;
  final List<_TopicListTabItem> items;
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
      final segmentHeight =
          (scaler.scale(DiscourseTypography.fontDown1) * 1.2 + 12)
              .ceilToDouble();
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
            key: const ValueKey('topic-list-new-segments'),
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: theme.shell.sidebar,
              border: Border.all(color: theme.shell.divider),
              borderRadius: BorderRadius.circular(7),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(
                    constraints.maxWidth,
                    segmentWidth * items.length + 2 * (items.length - 1),
                  ),
                  height: segmentHeight,
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

class _TopicListTabItem extends StatefulWidget {
  const _TopicListTabItem({
    required this.controlKey,
    required this.label,
    required this.textStyle,
    required this.selected,
    required this.onTap,
    this.count = 0,
    this.showCountBadge = false,
    this.showCount = true,
    this.underline = false,
    this.segmented = false,
  });

  final Key controlKey;
  final String label;
  final TextStyle? textStyle;
  final int count;
  final bool showCountBadge;
  final bool showCount;
  final bool underline;
  final bool segmented;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TopicListTabItem> createState() => _TopicListTabItemState();
}

class _TopicListTabItemState extends State<_TopicListTabItem> {
  final WidgetStatesController _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayLabel =
        widget.showCount &&
            widget.count > 0 &&
            !widget.showCountBadge &&
            !widget.segmented
        ? '${widget.label} (${widget.count})'
        : widget.label;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 120);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.count > 0
          ? '${widget.label}, ${widget.count}'
          : widget.label,
      child: ExcludeSemantics(
        child: InkWell(
          key: widget.controlKey,
          statesController: _states,
          onTap: widget.onTap,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          borderRadius: BorderRadius.circular(
            widget.underline
                ? 0
                : widget.segmented
                ? 4
                : 6,
          ),
          child: ValueListenableBuilder<Set<WidgetState>>(
            valueListenable: _states,
            builder: (context, states, _) {
              final focused = states.contains(WidgetState.focused);
              final emphasized =
                  states.contains(WidgetState.hovered) ||
                  focused ||
                  states.contains(WidgetState.pressed);
              final highlighted =
                  widget.selected || (widget.underline && emphasized);
              final labelWidget = TweenAnimationBuilder<Color?>(
                tween: ColorTween(
                  end: highlighted
                      ? widget.underline || widget.segmented
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                duration: duration,
                curve: Curves.easeOut,
                builder: (context, color, _) => Text(
                  displayLabel,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: widget.textStyle?.copyWith(
                    color: color,
                    fontWeight: widget.selected
                        ? widget.underline || widget.segmented
                              ? FontWeight.w600
                              : FontWeight.w500
                        : FontWeight.w400,
                  ),
                ),
              );
              return AnimatedContainer(
                duration: duration,
                curve: Curves.easeOut,
                alignment: Alignment.center,
                margin: EdgeInsets.symmetric(
                  vertical: widget.underline || widget.segmented ? 0 : 9,
                ),
                padding: widget.underline
                    ? const EdgeInsets.only(top: 3, bottom: 10)
                    : EdgeInsets.symmetric(
                        horizontal: widget.segmented ? 4 : 10,
                      ),
                decoration: BoxDecoration(
                  color: widget.underline
                      ? Colors.transparent
                      : widget.selected && widget.segmented
                      ? theme.shell.content
                      : widget.selected
                      ? theme.shell.selected
                      : emphasized
                      ? theme.shell.hover
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    widget.underline
                        ? 0
                        : widget.segmented
                        ? 4
                        : 6,
                  ),
                  boxShadow: widget.selected && widget.segmented
                      ? const [
                          BoxShadow(
                            color: Color(0x11000000),
                            offset: Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ]
                      : null,
                  border: widget.underline
                      ? Border(
                          bottom: BorderSide(
                            width: 2,
                            color: widget.selected
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                          ),
                        )
                      : null,
                ),
                foregroundDecoration: widget.underline && focused
                    ? BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      )
                    : null,
                child: widget.segmented
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          labelWidget,
                          if (widget.count > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              '${widget.count}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: DiscourseTypography.fontDown2,
                                height: 1.2,
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w400,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ],
                      )
                    : widget.showCount &&
                          widget.showCountBadge &&
                          widget.count > 0
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
                              '${widget.count}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : labelWidget,
              );
            },
          ),
        ),
      ),
    );
  }
}
