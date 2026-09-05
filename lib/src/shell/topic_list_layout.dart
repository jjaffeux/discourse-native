import 'package:flutter/widgets.dart';

const double topicListContentWidth = 1120;
const double topicListHorizontalPadding = 20;

/// Shares row density across discovery views without notifying the shell.
class TopicListDensityScope extends InheritedNotifier<ValueNotifier<bool>> {
  const TopicListDensityScope({
    super.key,
    required ValueNotifier<bool> compact,
    required super.child,
  }) : super(notifier: compact);

  static ValueNotifier<bool>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TopicListDensityScope>()
      ?.notifier;

  static bool isCompact(BuildContext context) =>
      maybeOf(context)?.value ?? false;
}
