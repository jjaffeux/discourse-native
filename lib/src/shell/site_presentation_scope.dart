import 'package:flutter/widgets.dart';

import 'site_presentation_controller.dart';

/// Hands a forum's emoji answers to the widgets that draw them, so a leaf
/// emoji neither compiles the shell nor wakes on its notifications.
class SitePresentationScope extends InheritedWidget {
  const SitePresentationScope({
    super.key,
    required this.presentation,
    required super.child,
  });

  final SitePresentationController presentation;

  static SitePresentationController of(BuildContext context) {
    final presentation = maybeOf(context);
    assert(presentation != null, 'No ShellScope found above this widget');
    return presentation!;
  }

  static SitePresentationController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SitePresentationScope>()
      ?.presentation;

  @override
  bool updateShouldNotify(SitePresentationScope oldWidget) =>
      !identical(presentation, oldWidget.presentation);
}
