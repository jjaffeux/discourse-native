import 'package:flutter/widgets.dart';

/// Coordinates optional control labels with the composer's available width.
class ComposerFooterLayout extends InheritedWidget {
  const ComposerFooterLayout({
    super.key,
    required this.compact,
    required super.child,
  });

  final bool compact;

  static bool isCompactOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ComposerFooterLayout>()
          ?.compact ??
      false;

  @override
  bool updateShouldNotify(ComposerFooterLayout oldWidget) =>
      compact != oldWidget.compact;
}
