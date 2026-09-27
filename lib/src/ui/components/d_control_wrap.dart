import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../foundation/tokens.dart';

/// Spaces Native controls using their layout bounds. Gaps are not interactive.
/// Nested layouts keep their own spacing, keyboard order and semantics.
/// Set [wrap] to false for one row.
class DControlWrap extends MultiChildRenderObjectWidget {
  const DControlWrap({
    super.key,
    super.children,
    this.spacing = DSpacing.sm,
    this.runSpacing = DSpacing.sm,
    this.wrap = true,
    this.direction = Axis.horizontal,
    this.alignment = WrapAlignment.start,
  }) : assert(spacing >= 0),
       assert(runSpacing >= 0);

  final double spacing;
  final double runSpacing;
  final bool wrap;
  final Axis direction;
  final WrapAlignment alignment;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderDControlWrap(
    wrap,
    spacing: spacing,
    runSpacing: runSpacing,
    textDirection: Directionality.of(context),
    direction: direction,
    alignment: alignment,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderDControlWrap renderObject,
  ) {
    renderObject
      ..spacing = spacing
      ..runSpacing = runSpacing
      ..textDirection = Directionality.of(context)
      ..wrap = wrap
      ..direction = direction
      ..alignment = alignment;
  }
}

/// Fills the remaining space in a non-wrapping [DControlWrap] row or column.
/// The child retains its own interaction bounds.
class DControlExpanded extends ParentDataWidget<DControlWrapParentData> {
  const DControlExpanded({super.key, required super.child});

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as DControlWrapParentData;
    if (data.expanded) return;
    data.expanded = true;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => DControlWrap;
}

class DControlWrapParentData extends WrapParentData {
  bool expanded = false;
}

class _ControlRun {
  final children = <RenderBox>[];
  double main = 0;
  double cross = 0;
}

class RenderDControlWrap extends RenderWrap {
  RenderDControlWrap(
    this._wrap, {
    required super.spacing,
    required super.runSpacing,
    required super.textDirection,
    required super.direction,
    required super.alignment,
  });

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! DControlWrapParentData) {
      child.parentData = DControlWrapParentData();
    }
  }

  bool _wrap;
  set wrap(bool value) {
    if (_wrap == value) return;
    _wrap = value;
    markNeedsLayout();
  }

  final _surfaces = <RenderBox, Rect>{};
  Rect _surfaceOf(RenderBox child) => Offset.zero & child.size;

  bool get _horizontal => direction == Axis.horizontal;
  double _main(Size value) => _horizontal ? value.width : value.height;
  double _cross(Size value) => _horizontal ? value.height : value.width;
  Size _size(double main, double cross) =>
      _horizontal ? Size(main, cross) : Size(cross, main);
  Offset _offset(double main, double cross) =>
      _horizontal ? Offset(main, cross) : Offset(cross, main);

  @override
  void performLayout() {
    _surfaces.clear();
    if (firstChild == null) {
      size = constraints.smallest;
      return;
    }
    final maxMain = _main(constraints.biggest);
    final maxCross = _cross(constraints.biggest);
    BoxConstraints childConstraints({double? main}) => _horizontal
        ? BoxConstraints(
            minWidth: main ?? 0,
            maxWidth: main ?? maxMain,
            maxHeight: maxCross,
          )
        : BoxConstraints(
            maxWidth: maxCross,
            minHeight: main ?? 0,
            maxHeight: main ?? double.infinity,
          );
    final expanded = <RenderBox>[];
    var fixedMain = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if ((child.parentData! as DControlWrapParentData).expanded) {
        assert(
          !_wrap && maxMain.isFinite,
          'DControlExpanded needs a bounded, non-wrapping axis.',
        );
        expanded.add(child);
      } else {
        child.layout(childConstraints(), parentUsesSize: true);
        final surface = _surfaceOf(child);
        _surfaces[child] = surface;
        fixedMain += _main(surface.size);
      }
    }
    if (expanded.isNotEmpty) {
      final extent = math.max(
        0.0,
        (maxMain - fixedMain - spacing * (childCount - 1)) / expanded.length,
      );
      for (final child in expanded) {
        child.layout(childConstraints(main: extent), parentUsesSize: true);
        final surface = _surfaceOf(child);
        // The empty portion of a flexible slot also belongs to that slot.
        _surfaces[child] = _horizontal
            ? Rect.fromLTWH(0, surface.top, extent, surface.height)
            : Rect.fromLTWH(surface.left, 0, surface.width, extent);
      }
    }
    final available = maxMain;
    final runs = <_ControlRun>[];
    var run = _ControlRun();
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final surface = _surfaces[child]!;
      final gap = run.children.isEmpty ? 0.0 : spacing;
      if (_wrap &&
          run.children.isNotEmpty &&
          run.main + gap + _main(surface.size) >
              available + precisionErrorTolerance) {
        runs.add(run);
        run = _ControlRun();
      }
      run.main += (run.children.isEmpty ? 0 : spacing) + _main(surface.size);
      run.cross = math.max(run.cross, _cross(surface.size));
      run.children.add(child);
    }
    runs.add(run);
    final main = runs.fold(0.0, (value, run) => math.max(value, run.main));
    final cross =
        runs.fold(0.0, (value, run) => value + run.cross) +
        runSpacing * (runs.length - 1);
    final fillMain = alignment != WrapAlignment.start && maxMain.isFinite;
    size = constraints.constrain(_size(fillMain ? maxMain : main, cross));
    var crossPosition = 0.0;
    for (final run in runs) {
      final free = math.max(0.0, _main(size) - run.main);
      final count = run.children.length;
      final (leading, extraGap) = switch (alignment) {
        WrapAlignment.start => (0.0, 0.0),
        WrapAlignment.end => (free, 0.0),
        WrapAlignment.center => (free / 2, 0.0),
        WrapAlignment.spaceBetween => (
          0.0,
          count > 1 ? free / (count - 1) : 0.0,
        ),
        WrapAlignment.spaceAround => (free / count / 2, free / count),
        WrapAlignment.spaceEvenly => (free / (count + 1), free / (count + 1)),
      };
      var mainPosition = leading;
      for (final child in run.children) {
        final surface = _surfaces[child]!;
        var position = _offset(
          mainPosition,
          crossPosition + (run.cross - _cross(surface.size)) / 2,
        );
        if (textDirection == TextDirection.rtl) {
          position = Offset(
            size.width - position.dx - surface.width,
            position.dy,
          );
        }
        final offset = position - surface.topLeft;
        (child.parentData! as DControlWrapParentData).offset = offset;
        mainPosition += _main(surface.size) + spacing + extraGap;
      }
      crossPosition += run.cross + runSpacing;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
