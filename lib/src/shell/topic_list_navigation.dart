import 'dart:async';

import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../theme/app_theme.dart';
import 'select.dart';
import 'shell_scope.dart';

typedef _TopicListNavigationSnapshot = ({
  TopicListMode? mode,
  bool signedIn,
  bool unifiedNew,
  int allCount,
  int topicCount,
  int replyCount,
});

class TopicListNavigation extends StatelessWidget {
  const TopicListNavigation({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ShellSelector<_TopicListNavigationSnapshot>(
        select: (controller) => (
          mode: controller.currentTopicListMode,
          signedIn: controller.currentInstance?.user != null,
          unifiedNew:
              controller.currentInstance?.user?.unifiedNewEnabled == true,
          allCount: controller.newActivityCount,
          topicCount: controller.newTopicCount,
          replyCount: controller.newReplyCount,
        ),
        builder: (context, state, _) {
          if (!state.signedIn || state.mode == null) return child;
          return Column(
            children: [
              _TopicListNavigationControls(state: state),
              Expanded(child: child),
            ],
          );
        },
      );
}

class _TopicListNavigationControls extends StatelessWidget {
  const _TopicListNavigationControls({required this.state});

  final _TopicListNavigationSnapshot state;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    final mode = state.mode!;
    final theme = Theme.of(context);
    final primaryTextStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final secondaryTextStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w400,
    );

    return Semantics(
      key: const ValueKey('topic-list-navigation'),
      container: true,
      label: 'Topic lists',
      child: Column(
        children: [
          _TopicListTabStrip(
            height: 48,
            background: theme.shell.content,
            scrollable: true,
            fillWidth: true,
            items: [
              _TopicListTabItem(
                controlKey: const ValueKey('topic-list-latest'),
                label: 'Recent',
                textStyle: primaryTextStyle,
                alignment: Alignment.centerLeft,
                selected: mode == TopicListMode.latest,
                onTap: () => unawaited(
                  controller.selectTopicListMode(TopicListMode.latest),
                ),
              ),
              _TopicListTabItem(
                controlKey: const ValueKey('topic-list-new'),
                label: 'New',
                count: state.allCount,
                textStyle: primaryTextStyle,
                alignment: Alignment.centerLeft,
                selected: mode.isNew,
                onTap: () => unawaited(
                  controller.selectTopicListMode(TopicListMode.newActivity),
                ),
              ),
              _TopicListTabItem(
                controlKey: const ValueKey('topic-list-unread'),
                label: 'Unread',
                count: state.replyCount,
                textStyle: primaryTextStyle,
                alignment: Alignment.centerLeft,
                selected: mode == TopicListMode.unread,
                onTap: () => unawaited(
                  controller.selectTopicListMode(TopicListMode.unread),
                ),
              ),
              _TopicListTabItem(
                controlKey: const ValueKey('topic-list-top'),
                label: 'Top',
                textStyle: primaryTextStyle,
                alignment: Alignment.centerLeft,
                selected: mode.isTop,
                onTap: () => unawaited(
                  controller.selectTopicListMode(
                    mode.isTop ? mode : controller.defaultTopTopicListMode,
                  ),
                ),
              ),
              _TopicListTabItem(
                controlKey: const ValueKey('topic-list-popular'),
                label: 'Popular',
                textStyle: primaryTextStyle,
                alignment: Alignment.centerLeft,
                selected: mode == TopicListMode.popular,
                onTap: () => unawaited(
                  controller.selectTopicListMode(TopicListMode.popular),
                ),
              ),
            ],
          ),
          if (mode.isNew && state.unifiedNew)
            _TopicListTabStrip(
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
          if (mode.topPeriod case final period?)
            _TopPeriodChooser(
              period: period,
              textStyle: secondaryTextStyle,
              onSelected: (value) => unawaited(
                controller.selectTopicListMode(TopicListMode.top(value)),
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
  });

  final TopPeriod period;
  final TextStyle? textStyle;
  final ValueChanged<TopPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
    this.fillWidth = false,
  });

  final double height;
  final Color background;
  final List<_TopicListTabItem> items;
  final double compactWidth;
  final bool scrollable;
  final bool fillWidth;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).shell.divider;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: divider)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (scrollable) {
            if (fillWidth && constraints.maxWidth >= 520) {
              return Row(
                children: [for (final item in items) Expanded(child: item)],
              );
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Row(
                  children: [
                    for (final item in items)
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 76),
                        child: item,
                      ),
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
    this.alignment = Alignment.center,
  });

  final Key controlKey;
  final String label;
  final TextStyle? textStyle;
  final int count;
  final AlignmentGeometry alignment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayLabel = count > 0 ? '$label ($count)' : label;
    return Semantics(
      button: true,
      selected: selected,
      label: count > 0 ? '$label, $count' : label,
      child: ExcludeSemantics(
        child: InkWell(
          key: controlKey,
          onTap: onTap,
          hoverColor: theme.shell.hover,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            alignment: alignment,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Text(
              displayLabel,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: textStyle?.copyWith(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
