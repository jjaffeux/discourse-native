import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

Color topicListTitleColor(ThemeData theme, {required bool visited}) => visited
    ? Color.lerp(theme.discourse.whisper, theme.colorScheme.onSurface, 0.25)!
    : theme.colorScheme.onSurface;

class TopicUnreadBadge extends StatelessWidget {
  const TopicUnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = '$count unread ${count == 1 ? 'post' : 'posts'}';
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class TopicStateDot extends StatelessWidget {
  const TopicStateDot({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    child: Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
      ),
    ),
  );
}
