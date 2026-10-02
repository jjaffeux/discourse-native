import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Native scrolling with transparent fades wherever a vertical list continues.
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
    if (axisDirectionToAxis(details.direction) != Axis.vertical ||
        decorated is _ScrollEdgeFade) {
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
    return _ScrollEdgeFade(
      controller: details.controller,
      topExtent: local?.topExtent ?? 14,
      bottomExtent: local?.bottomExtent ?? 20,
      topInset: local?.topInset,
      child: decorated,
    );
  }

  @override
  bool shouldNotify(covariant DScrollBehavior oldDelegate) =>
      delegate.runtimeType != oldDelegate.delegate.runtimeType ||
      delegate.shouldNotify(oldDelegate.delegate);
}

/// Edge geometry for the first vertical viewport in this subtree.
/// Nested lists retain their own default fades. Insets are read during paint,
/// so a floating header can move without rebuilding the list on scroll.
class DScrollFadeScope extends InheritedWidget {
  const DScrollFadeScope({
    super.key,
    this.topExtent = 14,
    this.bottomExtent = 20,
    this.topInset,
    required super.child,
  }) : assert(topExtent >= 0 && topExtent < double.infinity),
       assert(bottomExtent >= 0 && bottomExtent < double.infinity);

  final double topExtent;
  final double bottomExtent;
  final ValueGetter<double>? topInset;

  static DScrollFadeScope? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DScrollFadeScope>();

  @override
  bool updateShouldNotify(DScrollFadeScope oldWidget) =>
      topExtent != oldWidget.topExtent ||
      bottomExtent != oldWidget.bottomExtent ||
      topInset != oldWidget.topInset;
}

class _ScrollEdgeFade extends StatefulWidget {
  const _ScrollEdgeFade({
    required this.controller,
    required this.topExtent,
    required this.bottomExtent,
    required this.topInset,
    required this.child,
  });

  final ScrollController? controller;
  final double topExtent;
  final double bottomExtent;
  final ValueGetter<double>? topInset;
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
          topExtent: widget.topExtent,
          bottomExtent: widget.bottomExtent,
          topInset: widget.topInset,
          child: widget.child,
        ),
      );
}

class _ScrollFadeMask extends SingleChildRenderObjectWidget {
  const _ScrollFadeMask({
    super.key,
    required this.controller,
    required this.topExtent,
    required this.bottomExtent,
    required this.topInset,
    required super.child,
  });

  final ScrollController? controller;
  final double topExtent;
  final double bottomExtent;
  final ValueGetter<double>? topInset;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollFadeMask(controller, topExtent, bottomExtent, topInset);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderScrollFadeMask renderObject,
  ) {
    renderObject.update(controller, topExtent, bottomExtent, topInset);
  }
}

class _RenderScrollFadeMask extends RenderProxyBox {
  _RenderScrollFadeMask(
    this._controller,
    this._topExtent,
    this._bottomExtent,
    this._topInset,
  );

  ScrollController? _controller;
  double _topExtent;
  double _bottomExtent;
  ValueGetter<double>? _topInset;

  void update(
    ScrollController? controller,
    double topExtent,
    double bottomExtent,
    ValueGetter<double>? topInset,
  ) {
    if (controller != _controller) {
      if (attached) _controller?.removeListener(markNeedsPaint);
      _controller = controller;
      if (attached) _controller?.addListener(markNeedsPaint);
    }
    _topExtent = topExtent;
    _bottomExtent = bottomExtent;
    _topInset = topInset;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _controller?.removeListener(markNeedsPaint);
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
    if (child == null ||
        size.height == 0 ||
        position == null ||
        !position.hasContentDimensions) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final reversed = position.axisDirection == AxisDirection.up;
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
    final inset = (_topInset?.call() ?? 0).clamp(0.0, size.height);
    final room = size.height - inset;
    final topFade = top ? math.min(_topExtent, room / 2) : 0.0;
    final bottomFade = bottom ? math.min(_bottomExtent, room / 2) : 0.0;
    layer ??= ShaderMaskLayer();
    layer!
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          if (top) ...[Colors.transparent, Colors.transparent],
          Colors.white,
          Colors.white,
          if (bottom) Colors.transparent,
        ],
        stops: [
          if (top) ...[0, inset / size.height],
          top ? (inset + topFade) / size.height : 0,
          bottom ? (size.height - bottomFade) / size.height : 1,
          if (bottom) 1,
        ],
      ).createShader(Offset.zero & size)
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(layer!, super.paint, offset);
  }
}
