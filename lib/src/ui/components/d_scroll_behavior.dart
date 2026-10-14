import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Native scrolling with transparent fades wherever a vertical list continues.
/// Horizontal fades are opt-in through [DScrollFadeScope.horizontalExtent].
/// The delegate retains its platform physics, gestures, and scrollbar policy.
class DScrollBehavior extends ScrollBehavior {
  const DScrollBehavior({this.delegate = const MaterialScrollBehavior()});

  final ScrollBehavior delegate;

  @override
  TargetPlatform getPlatform(BuildContext context) =>
      delegate.getPlatform(context);

  @override
  Set<PointerDeviceKind> get dragDevices => delegate.dragDevices;

  @override
  Set<LogicalKeyboardKey> get pointerAxisModifiers =>
      delegate.pointerAxisModifiers;

  @override
  MultitouchDragStrategy getMultitouchDragStrategy(BuildContext context) =>
      delegate.getMultitouchDragStrategy(context);

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      delegate.getScrollPhysics(context);

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) => delegate.getKeyboardDismissBehavior(context);

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => delegate.buildScrollbar(context, child, details);

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final decorated = delegate.buildOverscrollIndicator(
      context,
      child,
      details,
    );
    if (decorated is _ScrollEdgeFade) {
      return decorated;
    }
    final scope = DScrollFadeScope._of(context);
    // A nested list has its own edges; a floating page header belongs only to
    // the first viewport below its scope.
    final parent = Scrollable.maybeOf(context);
    final local =
        parent == null ||
            !identical(DScrollFadeScope._of(parent.context), scope)
        ? scope
        : null;
    final axis = axisDirectionToAxis(details.direction);
    final horizontal = axis == Axis.horizontal;
    final horizontalExtent = local?.horizontalExtent ?? 0;
    if (horizontal && horizontalExtent == 0) return decorated;
    return _ScrollEdgeFade(
      controller: details.controller,
      axis: axis,
      topExtent: horizontal ? horizontalExtent : local?.topExtent ?? 14,
      bottomExtent: horizontal ? horizontalExtent : local?.bottomExtent ?? 20,
      topInset: horizontal ? null : local?.topInset,
      repaint: horizontal ? null : local?.repaint,
      child: decorated,
    );
  }

  @override
  bool shouldNotify(covariant DScrollBehavior oldDelegate) =>
      delegate.runtimeType != oldDelegate.delegate.runtimeType ||
      delegate.shouldNotify(oldDelegate.delegate);
}

/// Edge geometry for the first viewport in this subtree.
/// Nested lists retain their own default fades. Insets are read during paint,
/// so a floating header can move without rebuilding the list on scroll.
class DScrollFadeScope extends InheritedWidget {
  const DScrollFadeScope({
    super.key,
    this.topExtent = 14,
    this.bottomExtent = 20,
    this.horizontalExtent = 0,
    this.topInset,
    this.repaint,
    required super.child,
  }) : assert(topExtent >= 0 && topExtent < double.infinity),
       assert(bottomExtent >= 0 && bottomExtent < double.infinity),
       assert(horizontalExtent >= 0 && horizontalExtent < double.infinity);

  final double topExtent;
  final double bottomExtent;

  /// Fade width at continuing horizontal edges. Zero leaves them unfaded.
  final double horizontalExtent;
  final ValueGetter<double>? topInset;

  /// Repaints changing insets without replacing the scroll position.
  final Listenable? repaint;

  static DScrollFadeScope? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DScrollFadeScope>();

  @override
  bool updateShouldNotify(DScrollFadeScope oldWidget) =>
      topExtent != oldWidget.topExtent ||
      bottomExtent != oldWidget.bottomExtent ||
      horizontalExtent != oldWidget.horizontalExtent ||
      topInset != oldWidget.topInset ||
      repaint != oldWidget.repaint;
}

class _ScrollEdgeFade extends StatefulWidget {
  const _ScrollEdgeFade({
    required this.controller,
    required this.axis,
    required this.topExtent,
    required this.bottomExtent,
    required this.topInset,
    required this.repaint,
    required this.child,
  });

  final ScrollController? controller;
  final Axis axis;
  final double topExtent;
  final double bottomExtent;
  final ValueGetter<double>? topInset;
  final Listenable? repaint;
  final Widget child;

  @override
  State<_ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<_ScrollEdgeFade> {
  final _maskKey = GlobalKey();

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) {
            _maskKey.currentContext?.findRenderObject()?.markNeedsPaint();
          }
          return false;
        },
        child: _ScrollFadeMask(
          key: _maskKey,
          controller: widget.controller,
          axis: widget.axis,
          topExtent: widget.topExtent,
          bottomExtent: widget.bottomExtent,
          topInset: widget.topInset,
          repaint: widget.repaint,
          child: widget.child,
        ),
      );
}

class _ScrollFadeMask extends SingleChildRenderObjectWidget {
  const _ScrollFadeMask({
    super.key,
    required this.controller,
    required this.axis,
    required this.topExtent,
    required this.bottomExtent,
    required this.topInset,
    required this.repaint,
    required super.child,
  });

  final ScrollController? controller;
  final Axis axis;
  final double topExtent;
  final double bottomExtent;
  final ValueGetter<double>? topInset;
  final Listenable? repaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollFadeMask(
        controller,
        axis,
        topExtent,
        bottomExtent,
        topInset,
        repaint,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderScrollFadeMask renderObject,
  ) {
    renderObject.update(
      controller,
      axis,
      topExtent,
      bottomExtent,
      topInset,
      repaint,
    );
  }
}

class _RenderScrollFadeMask extends RenderProxyBox {
  _RenderScrollFadeMask(
    this._controller,
    this._axis,
    this._topExtent,
    this._bottomExtent,
    this._topInset,
    this._repaint,
  );

  ScrollController? _controller;
  Axis _axis;
  double _topExtent;
  double _bottomExtent;
  ValueGetter<double>? _topInset;
  Listenable? _repaint;

  void update(
    ScrollController? controller,
    Axis axis,
    double topExtent,
    double bottomExtent,
    ValueGetter<double>? topInset,
    Listenable? repaint,
  ) {
    if (controller != _controller) {
      if (attached) _controller?.removeListener(markNeedsPaint);
      _controller = controller;
      if (attached) _controller?.addListener(markNeedsPaint);
    }
    if (repaint != _repaint) {
      if (attached) _repaint?.removeListener(markNeedsPaint);
      _repaint = repaint;
      if (attached) _repaint?.addListener(markNeedsPaint);
    }
    _topExtent = topExtent;
    _axis = axis;
    _bottomExtent = bottomExtent;
    _topInset = topInset;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller?.addListener(markNeedsPaint);
    _repaint?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _controller?.removeListener(markNeedsPaint);
    _repaint?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  ShaderMaskLayer? get layer => super.layer as ShaderMaskLayer?;

  @override
  void paint(PaintingContext context, Offset offset) {
    final positions = _controller?.positions;
    final position = positions?.length == 1 ? positions!.single : null;
    final horizontal = _axis == Axis.horizontal;
    final extent = horizontal ? size.width : size.height;
    if (child == null ||
        extent == 0 ||
        position == null ||
        !position.hasContentDimensions) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final reversed =
        position.axisDirection == AxisDirection.up ||
        position.axisDirection == AxisDirection.left;
    // Match the mockup's 2px tolerance, including elastic overscroll.
    final before = position.pixels - position.minScrollExtent > 2;
    final after = position.maxScrollExtent - position.pixels > 2;
    final top = (reversed ? after : before) && _topExtent > 0;
    final bottom = (reversed ? before : after) && _bottomExtent > 0;
    if (!top && !bottom) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final inset = (_topInset?.call() ?? 0).clamp(0.0, extent);
    final room = extent - inset;
    final topFade = top ? math.min(_topExtent, room / 2) : 0.0;
    final bottomFade = bottom ? math.min(_bottomExtent, room / 2) : 0.0;
    layer ??= ShaderMaskLayer();
    layer!
      ..shader = LinearGradient(
        begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
        end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
        colors: [
          if (top) ...[Colors.transparent, Colors.transparent],
          Colors.white,
          Colors.white,
          if (bottom) Colors.transparent,
        ],
        stops: [
          if (top) ...[0, inset / extent],
          top ? (inset + topFade) / extent : 0,
          bottom ? (extent - bottomFade) / extent : 1,
          if (bottom) 1,
        ],
      ).createShader(Offset.zero & size)
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(layer!, super.paint, offset);
  }
}
