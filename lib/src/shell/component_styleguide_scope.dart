import 'package:flutter/widgets.dart';

typedef ComponentStyleguideOpener = Future<void> Function(BuildContext context);

/// Hands the desktop rail the styleguide from the composition root, which is
/// the only layer allowed to know the styleguide's plugin examples.
class ComponentStyleguideScope extends InheritedWidget {
  const ComponentStyleguideScope({
    super.key,
    required this.open,
    required super.child,
  });

  final ComponentStyleguideOpener? open;

  static ComponentStyleguideOpener? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ComponentStyleguideScope>()
      ?.open;

  @override
  bool updateShouldNotify(ComponentStyleguideScope oldWidget) =>
      open != oldWidget.open;
}
