import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../foundation/sheet_page_band.dart';

/// Places a part shared by a header's layouts under a stable [String] name.
///
/// A `fontSize` says the part's text changes size between layouts, and is the
/// size it is set at in this one: the part scales by the ratio of the two,
/// keeping its proportions. Any other part only moves.
typedef DHeaderMorphPart =
    Widget Function(String id, Widget child, {double? fontSize});

/// Moves shared header parts between full and compact layouts in place.
/// The builder keeps control ownership and callbacks while the kit owns motion.
class DHeaderMorph extends StatefulWidget {
  const DHeaderMorph({super.key, required this.compact, required this.builder});
  static Widget scrollFade({
    required ValueListenable<double>? scroll,
    required double Function() extent,
    required ValueNotifier<double> titleOpacity,
    required Widget child,
  }) => _ScrollFadeScope(
    scroll: scroll,
    extent: extent,
    titleOpacity: titleOpacity,
    child: child,
  );

  final bool compact;
  final Widget Function(
    BuildContext context,
    bool compact,
    DHeaderMorphPart part,
  )
  builder;
  @override
  State<DHeaderMorph> createState() => _DHeaderMorphState();
}

class _DHeaderMorphState extends State<DHeaderMorph> {
  final _parts = <String, GlobalKey<_MorphPartState>>{};
  final _root = GlobalKey();

  @override
  void didUpdateWidget(DHeaderMorph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.compact == widget.compact ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    for (final part in _parts.values) {
      part.currentState?.holdPlace();
    }
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: _root,
    child: widget.builder(
      context,
      widget.compact,
      (id, child, {fontSize}) => _MorphPart(
        key: _parts.putIfAbsent(id, () => GlobalKey<_MorphPartState>()),
        fontSize: fontSize,
        child: _ReaderFadePart(id: id, root: _root, child: child),
      ),
    ),
  );
}

class _MorphPart extends StatefulWidget {
  const _MorphPart({super.key, required this.fontSize, required this.child});
  final double? fontSize;
  final Widget child;
  @override
  State<_MorphPart> createState() => _MorphPartState();
}

class _MorphPartState extends State<_MorphPart>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  final _box = GlobalKey();
  final _transform = GlobalKey();
  ({Offset start, double? fontSize})? _held;

  /// Remembers where the part is drawn, in the middle of a move included,
  /// for the layout about to replace this one to start from.
  void holdPlace() {
    final box = _box.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _held = (
      start: box.localToGlobal(
        _startEdge(box.size, Directionality.of(context)),
      ),
      fontSize: widget.fontSize,
    );
  }

  @override
  void didUpdateWidget(_MorphPart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final held = _held;
    if (held == null) return;
    _held = null;
    final then = held.fontSize;
    final now = widget.fontSize;
    final render =
        _transform.currentContext?.findRenderObject() as _RenderMorphTransform?;
    render?.moveFrom(
      held.start,
      grow: then != null && now != null ? then / now : 1,
    );
    _motion.forward(from: 0);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _MorphTransform(
    key: _transform,
    motion: _motion,
    child: RepaintBoundary(key: _box, child: widget.child),
  );
}

Offset _startEdge(Size size, TextDirection direction) =>
    direction == TextDirection.rtl ? Offset(size.width, 0) : Offset.zero;

class _MorphTransform extends SingleChildRenderObjectWidget {
  const _MorphTransform({
    super.key,
    required this.motion,
    required super.child,
  });
  final Animation<double> motion;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMorphTransform(motion, Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMorphTransform renderObject,
  ) => renderObject.textDirection = Directionality.of(context);
}

// The new place is only known once the new layout is done, and a post-frame
// measurement would first show a frame of the part already at its end. Paint
// is the first moment both are known, so the distance is read there.
class _RenderMorphTransform extends RenderProxyBox {
  _RenderMorphTransform(this._motion, this.textDirection);

  static const _ease = Cubic(.2, .8, .2, 1);

  final Animation<double> _motion;
  TextDirection textDirection;
  Offset? _start;
  Offset _from = Offset.zero;
  double _grow = 1;

  void moveFrom(Offset start, {required double grow}) {
    _start = start;
    _grow = grow;
    markNeedsPaint();
  }

  Matrix4 get _matrix {
    final remaining = 1 - _ease.transform(_motion.value);
    final anchor = _startEdge(size, textDirection);
    final scale = 1 + (_grow - 1) * remaining;
    return Matrix4.identity()
      ..translateByDouble(
        _from.dx * remaining + anchor.dx,
        _from.dy * remaining + anchor.dy,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-anchor.dx, -anchor.dy, 0, 1);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _motion.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _motion.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_start case final start?) {
      _start = null;
      _from = start - localToGlobal(_startEdge(size, textDirection));
    }
    if (child == null) return;
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _matrix,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }

  // Targets travel with the same visible artwork.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      hitTestChildren(result, position: position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintTransform(
        transform: _matrix,
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_matrix);
}

class _ScrollFadeScope extends InheritedWidget {
  const _ScrollFadeScope({
    required this.scroll,
    required this.extent,
    required this.titleOpacity,
    required super.child,
  });
  final ValueListenable<double>? scroll;
  final double Function() extent;
  final ValueNotifier<double> titleOpacity;
  @override
  bool updateShouldNotify(_ScrollFadeScope oldWidget) =>
      scroll != oldWidget.scroll || extent != oldWidget.extent;
}

class _ReaderFadePart extends StatefulWidget {
  const _ReaderFadePart({
    required this.id,
    required this.root,
    required this.child,
  });
  final String id;
  final GlobalKey root;
  final Widget child;
  @override
  State<_ReaderFadePart> createState() => _ReaderFadePartState();
}

class _ReaderFadePartState extends State<_ReaderFadePart> {
  final _box = GlobalKey();
  _ScrollFadeScope? _scope;
  ValueListenable<double>? _edge;
  double _opacity = 1;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope?.scroll?.removeListener(_measure);
    _edge?.removeListener(_measure);
    _scope = context.dependOnInheritedWidgetOfExactType<_ScrollFadeScope>();
    _edge = DSheetPageBand.edgeOf(context);
    if (_scope?.scroll?.value == double.infinity) _opacity = 0;
    _scope?.scroll?.addListener(_measure);
    _edge?.addListener(_measure);
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _measure();
    });
  }

  void _measure() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _schedule();
      return;
    }
    final scope = _scope;
    final box = _box.currentContext?.findRenderObject() as RenderBox?;
    final root = widget.root.currentContext?.findRenderObject() as RenderBox?;
    if (scope?.scroll == null ||
        box == null ||
        root == null ||
        !box.hasSize ||
        !root.hasSize) {
      return;
    }
    final bottom = box
        .localToGlobal(Offset(0, box.size.height), ancestor: root)
        .dy;
    final clearance = math.max(1.0, scope!.extent() - bottom);
    final gap = clearance - scope.scroll!.value - (_edge?.value ?? 0);
    final opacity = (gap / math.min(40, clearance)).clamp(0.0, 1.0);
    if (widget.id == 'title') scope.titleOpacity.value = opacity;
    if (_opacity != opacity) setState(() => _opacity = opacity);
  }

  @override
  void dispose() {
    _scope?.scroll?.removeListener(_measure);
    _edge?.removeListener(_measure);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_scope?.scroll == null) return widget.child;
    _schedule();
    return SizedBox(
      key: _box,
      child: IgnorePointer(
        ignoring: _opacity < .5,
        child: ExcludeSemantics(
          excluding: _opacity < .5,
          child: ExcludeFocus(
            excluding: _opacity < .5,
            child: Opacity(opacity: _opacity, child: widget.child),
          ),
        ),
      ),
    );
  }
}
