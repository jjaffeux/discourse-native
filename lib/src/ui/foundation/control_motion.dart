import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class DControlMotionScope extends InheritedWidget {
  const DControlMotionScope({super.key, required super.child});

  @override
  bool updateShouldNotify(DControlMotionScope oldWidget) => false;
}

class DControlMotion extends StatelessWidget {
  const DControlMotion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DControlMotionScope>() == null
      ? child
      : _ControlMotion(child: child);
}

class _ControlMotion extends SingleChildRenderObjectWidget {
  const _ControlMotion({required super.child});

  @override
  RenderDControlMotion createRenderObject(BuildContext context) =>
      RenderDControlMotion();
}

class RenderDControlMotion extends RenderProxyBox {
  Rect layoutBounds = Rect.zero;
  ({RenderBox ancestor, Rect from, double progress})? _placement;

  // Descendant paint transforms may read sizes, so resolve them after layout.
  Offset get _offset {
    final placement = _placement;
    if (placement == null) return Offset.zero;
    final current = MatrixUtils.transformRect(
      getTransformTo(placement.ancestor),
      layoutBounds,
    );
    return (placement.from.topLeft - current.topLeft) *
        (1 - placement.progress);
  }

  Rect get paintedBounds => layoutBounds.shift(_offset);
  double _opacity = 1;

  @override
  void performLayout() {
    super.performLayout();
    layoutBounds = Offset.zero & size;
  }

  void place(
    ({RenderBox ancestor, Rect from, double progress})? placement,
    double opacity,
  ) {
    if (_placement == placement && _opacity == opacity) return;
    _placement = placement;
    if (_opacity != opacity) {
      _opacity = opacity;
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  bool get alwaysNeedsCompositing =>
      _opacity < 1 || super.alwaysNeedsCompositing;

  @override
  void paint(PaintingContext context, Offset offset) {
    offset += _offset;
    if (_opacity == 1) {
      super.paint(context, offset);
    } else {
      context.pushOpacity(offset, (_opacity * 255).round(), super.paint);
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      _opacity >= .5 &&
      result.addWithPaintOffset(
        offset: _offset,
        position: position,
        hitTest: (result, position) =>
            super.hitTest(result, position: position),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset = _offset;
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..isMergingSemanticsOfDescendants = true;
  }
}

class DControlMotionSurface extends StatelessWidget {
  const DControlMotionSurface({
    super.key,
    required this.decoration,
    required this.child,
  });

  final Decoration decoration;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DControlMotionScope>() == null
      ? DecoratedBox(decoration: decoration, child: child)
      : _ControlMotionSurface(decoration: decoration, child: child);
}

class _ControlMotionSurface extends SingleChildRenderObjectWidget {
  const _ControlMotionSurface({required this.decoration, required super.child});

  final Decoration decoration;

  @override
  RenderDControlMotionSurface createRenderObject(BuildContext context) =>
      RenderDControlMotionSurface(decoration);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderDControlMotionSurface renderObject,
  ) => renderObject.decoration = decoration;
}

class RenderDControlMotionSurface extends RenderProxyBox {
  RenderDControlMotionSurface(this._decoration);

  Decoration _decoration;
  BoxPainter? _painter;
  Size? _paintSize;
  Size layoutSize = Size.zero;

  set decoration(Decoration value) {
    if (_decoration == value) return;
    _decoration = value;
    _painter?.dispose();
    _painter = null;
    markNeedsPaint();
  }

  set paintSize(Size? value) {
    if (_paintSize == value) return;
    _paintSize = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    super.performLayout();
    layoutSize = size;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _painter ??= _decoration.createBoxPainter(markNeedsPaint);
    _painter!.paint(
      context.canvas,
      offset,
      ImageConfiguration(size: _paintSize ?? size),
    );
    super.paint(context, offset);
  }

  @override
  void dispose() {
    _painter?.dispose();
    super.dispose();
  }
}
