import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'app_text_scaler.dart';

/// Phone menus lay out their pointer-sized contents before enlarging the
/// whole composition. Reading-text uplift must not enlarge the words twice.
class DMenuContentScale extends StatelessWidget {
  const DMenuContentScale({required this.child, super.key});

  final Widget child;
  static const factor = 17 / 13;

  static bool isActiveOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MenuContentScope>() != null;

  @override
  Widget build(BuildContext context) => _MenuContentScope(
    child: DReferenceTextScale(child: _MenuScale(child: child)),
  );
}

class _MenuContentScope extends InheritedWidget {
  const _MenuContentScope({required super.child});

  @override
  bool updateShouldNotify(_MenuContentScope oldWidget) => false;
}

class _MenuScale extends SingleChildRenderObjectWidget {
  const _MenuScale({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMenuScale();
}

class _RenderMenuScale extends RenderProxyBox {
  static const factor = DMenuContentScale.factor;
  Matrix4 get _transform => Matrix4.diagonal3Values(factor, factor, 1);

  BoxConstraints _unscaled(BoxConstraints constraints) => BoxConstraints(
    minWidth: constraints.minWidth / factor,
    maxWidth: constraints.maxWidth / factor,
    minHeight: constraints.minHeight / factor,
    maxHeight: constraints.maxHeight / factor,
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) => child == null
      ? constraints.smallest
      : constraints.constrain(
          child!.getDryLayout(_unscaled(constraints)) * factor,
        );

  @override
  void performLayout() {
    child?.layout(_unscaled(constraints), parentUsesSize: true);
    size = child == null
        ? constraints.smallest
        : constraints.constrain(child!.size * factor);
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      (child?.getMinIntrinsicWidth(height / factor) ?? 0) * factor;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      (child?.getMaxIntrinsicWidth(height / factor) ?? 0) * factor;

  @override
  double computeMinIntrinsicHeight(double width) =>
      (child?.getMinIntrinsicHeight(width / factor) ?? 0) * factor;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      (child?.getMaxIntrinsicHeight(width / factor) ?? 0) * factor;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    context.pushTransform(needsCompositing, offset, _transform, (
      context,
      offset,
    ) {
      context.paintChild(child!, offset);
    });
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child != null &&
      result.addWithPaintTransform(
        transform: _transform,
        position: position,
        hitTest: (result, local) => child!.hitTest(result, position: local),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_transform);
}
