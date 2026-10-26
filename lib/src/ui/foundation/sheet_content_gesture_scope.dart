import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class SheetContentGestureScope extends InheritedWidget {
  const SheetContentGestureScope({
    super.key,
    required this.onPointer,
    required this.onSignal,
    required super.child,
  });

  final ValueChanged<PointerEvent> onPointer;
  final ValueChanged<PointerSignalEvent> onSignal;

  @override
  bool updateShouldNotify(SheetContentGestureScope oldWidget) =>
      onPointer != oldWidget.onPointer || onSignal != oldWidget.onSignal;
}

class SheetContentGestureRegion extends StatelessWidget {
  const SheetContentGestureRegion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SheetContentGestureScope>();
    if (scope == null) return child;
    return Listener(
      onPointerDown: scope.onPointer,
      onPointerPanZoomStart: scope.onPointer,
      onPointerSignal: scope.onSignal,
      child: child,
    );
  }
}
