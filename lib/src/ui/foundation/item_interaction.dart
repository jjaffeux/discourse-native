import 'package:flutter/widgets.dart';

/// Interaction inherited by passive Native artwork inside an Item.
/// Item retains the focus node, gesture recognizer, and state lifecycle.
class DItemInteraction extends InheritedWidget {
  const DItemInteraction({
    super.key,
    required this.hovered,
    required this.focused,
    required this.pressed,
    required super.child,
  });

  final bool hovered;
  final bool focused;
  final bool pressed;
  bool get emphasized => hovered || focused || pressed;

  static DItemInteraction of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DItemInteraction>() ??
      const DItemInteraction(
        hovered: false,
        focused: false,
        pressed: false,
        child: SizedBox.shrink(),
      );

  @override
  bool updateShouldNotify(DItemInteraction oldWidget) =>
      hovered != oldWidget.hovered ||
      focused != oldWidget.focused ||
      pressed != oldWidget.pressed;
}
