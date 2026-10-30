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
  const SheetContentGestureRegion({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SheetContentGestureScope>();
    if (scope == null) return child;
    return Listener(
      onPointerDown: enabled ? scope.onPointer : null,
      onPointerPanZoomStart: enabled ? scope.onPointer : null,
      onPointerSignal: enabled ? scope.onSignal : null,
      child: child,
    );
  }
}
