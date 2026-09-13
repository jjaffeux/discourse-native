import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

Color topicListTitleColor(ThemeData theme, {required bool visited}) =>
    visited ? theme.discourse.whisper : theme.colorScheme.onSurface;

class TopicUnreadBadge extends StatelessWidget {
  const TopicUnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = '$count unread ${count == 1 ? 'post' : 'posts'}';
    final colors = Theme.of(context).discourse;
    return DTooltip(
      message: label,
      excludeFromSemantics: true,
      child: DBadge(
        semanticLabel: label,
        backgroundColor: colors.notificationIndicator,
        foregroundColor: colors.notificationForeground,
        child: Text('$count'),
      ),
    );
  }
}

class TopicStateDot extends StatelessWidget {
  const TopicStateDot({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DTooltip(
    message: label,
    excludeFromSemantics: true,
    child: DNotificationDot(
      semanticLabel: label,
      color: Theme.of(context).discourse.notificationIndicator,
    ),
  );
}
