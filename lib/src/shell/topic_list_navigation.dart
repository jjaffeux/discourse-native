import 'dart:async';

import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../theme/app_theme.dart';
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

    return Semantics(
      key: const ValueKey('topic-list-navigation'),
      container: true,
      label: 'Topic lists',
      child: Column(
        children: [
          _TopicListTabStrip(
            height: 48,
            background: theme.shell.content,
            items: [
              _TopicListTabItem(
                controlKey: const ValueKey('topic-list-latest'),
                label: 'Latest',
                selected: mode == TopicListMode.latest,
                onTap: () => unawaited(
                  controller.selectTopicListMode(TopicListMode.latest),
                ),
              ),
              _TopicListTabItem(
                controlKey: const ValueKey('topic-list-new'),
                label: 'New',
                count: state.allCount,
                selected: mode.isNew,
                onTap: () => unawaited(
                  controller.selectTopicListMode(TopicListMode.newActivity),
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
                  selected: mode == TopicListMode.newActivity,
                  onTap: () => unawaited(
                    controller.selectTopicListMode(TopicListMode.newActivity),
                  ),
                ),
                _TopicListTabItem(
                  controlKey: const ValueKey('topic-list-new-topics'),
                  label: 'Topics',
                  count: state.topicCount,
                  selected: mode == TopicListMode.newTopics,
                  onTap: () => unawaited(
                    controller.selectTopicListMode(TopicListMode.newTopics),
                  ),
                ),
                _TopicListTabItem(
                  controlKey: const ValueKey('topic-list-new-replies'),
                  label: 'Replies',
                  count: state.replyCount,
                  selected: mode == TopicListMode.newReplies,
                  onTap: () => unawaited(
                    controller.selectTopicListMode(TopicListMode.newReplies),
                  ),
                ),
              ],
            ),
        ],
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
  });

  final double height;
  final Color background;
  final List<_TopicListTabItem> items;
  final double compactWidth;

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
          if (constraints.maxWidth < compactWidth) {
            return Row(
              children: [for (final item in items) Expanded(child: item)],
            );
          }
          return Row(
            children: [
              for (final item in items) SizedBox(width: 112, child: item),
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
    required this.selected,
    required this.onTap,
    this.count = 0,
  });

  final Key controlKey;
  final String label;
  final int count;
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
            alignment: Alignment.center,
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
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
