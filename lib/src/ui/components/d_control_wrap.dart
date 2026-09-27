import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../foundation/control_artwork.dart';
import '../foundation/tokens.dart';

/// Spaces Native control artwork while retaining its full touch targets.
///
/// Targets may overlap in the gaps. A painted control takes priority there;
/// otherwise the nearest control receives the hit. Nested layouts keep their
/// own spacing, keyboard order and semantics. Set [wrap] to false for one row.
class DControlWrap extends MultiChildRenderObjectWidget {
  const DControlWrap({
    super.key,
    super.children,
    this.spacing = DSpacing.sm,
    this.runSpacing = DSpacing.sm,
    this.wrap = true,
  }) : assert(spacing >= 0),
       assert(runSpacing >= 0);

  final double spacing;
  final double runSpacing;
  final bool wrap;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderDControlWrap(
    wrap,
    spacing: spacing,
    runSpacing: runSpacing,
    textDirection: Directionality.of(context),
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
      ..wrap = wrap;
  }
}

class _ControlRun {
  final children = <RenderBox>[];
  double width = 0;
  double height = 0;
}

class RenderDControlWrap extends RenderWrap {
  RenderDControlWrap(
    this._wrap, {
    required super.spacing,
    required super.runSpacing,
    required super.textDirection,
  });

  bool _wrap;
  set wrap(bool value) {
    if (_wrap == value) return;
    _wrap = value;
    markNeedsLayout();
  }

  final _surfaces = <RenderBox, Rect>{};
  Rect _artworkBounds = Rect.zero;

  Rect _surfaceOf(RenderBox child) {
    Rect? bounds;
    void visit(RenderObject node) {
      final Rect? surface = switch (node) {
        RenderDControlWrap() => node._artworkBounds,
        RenderDControlArtwork() => node.layoutBounds,
        _ => null,
      };
      if (surface != null) {
        final rect = MatrixUtils.transformRect(
          node.getTransformTo(child),
          surface,
        );
        bounds = bounds?.expandToInclude(rect) ?? rect;
      } else {
        node.visitChildren(visit);
      }
    }

    visit(child);
    return bounds ?? Offset.zero & child.size;
  }

  @override
  void performLayout() {
    // Use normal Wrap measurement: controls containing LayoutBuilder cannot
    // be measured intrinsically. Only their placement changes below.
    super.performLayout();
    _surfaces.clear();
    if (firstChild == null) {
      _artworkBounds = Rect.zero;
      return;
    }
    var leftInset = 0.0;
    var rightInset = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final surface = _surfaceOf(child);
      _surfaces[child] = surface;
      leftInset = math.max(leftInset, surface.left);
      rightInset = math.max(rightInset, child.size.width - surface.right);
    }
    final available = math.max(
      0.0,
      constraints.maxWidth - leftInset - rightInset,
    );
    final runs = <_ControlRun>[];
    var run = _ControlRun();
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final surface = _surfaces[child]!;
      final gap = run.children.isEmpty ? 0.0 : spacing;
      if (_wrap &&
          run.children.isNotEmpty &&
          run.width + gap + surface.width >
              available + precisionErrorTolerance) {
        runs.add(run);
        run = _ControlRun();
      }
      run.width += (run.children.isEmpty ? 0 : spacing) + surface.width;
      run.height = math.max(run.height, surface.height);
      run.children.add(child);
    }
    runs.add(run);
    var topInset = 0.0;
    var bottomInset = 0.0;
    for (final child in runs.first.children) {
      final surface = _surfaces[child]!;
      topInset = math.max(
        topInset,
        surface.top - (runs.first.height - surface.height) / 2,
      );
    }
    for (final child in runs.last.children) {
      final surface = _surfaces[child]!;
      bottomInset = math.max(
        bottomInset,
        child.size.height -
            surface.bottom -
            (runs.last.height - surface.height) / 2,
      );
    }
    final width = runs.fold(0.0, (width, run) => math.max(width, run.width));
    final height =
        runs.fold(0.0, (height, run) => height + run.height) +
        runSpacing * (runs.length - 1);
    size = constraints.constrain(
      Size(width + leftInset + rightInset, height + topInset + bottomInset),
    );
    Rect? artwork;
    var y = topInset;
    for (final run in runs) {
      var x = 0.0;
      for (final child in run.children) {
        final surface = _surfaces[child]!;
        final position = Offset(
          textDirection == TextDirection.rtl
              ? size.width - rightInset - x - surface.width
              : leftInset + x,
          y + (run.height - surface.height) / 2,
        );
        (child.parentData! as WrapParentData).offset =
            position - surface.topLeft;
        final placed = position & surface.size;
        artwork = artwork?.expandToInclude(placed) ?? placed;
        x += surface.width + spacing;
      }
      y += run.height + runSpacing;
    }
    _artworkBounds = artwork!;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final candidates = <(RenderBox, double)>[];
    for (var child = lastChild; child != null; child = childBefore(child)) {
      final offset = (child.parentData! as WrapParentData).offset;
      if (!(offset & child.size).contains(position)) continue;
      final surface = _surfaces[child]!.shift(offset);
      final dx = position.dx - position.dx.clamp(surface.left, surface.right);
      final dy = position.dy - position.dy.clamp(surface.top, surface.bottom);
      candidates.add((child, dx * dx + dy * dy));
    }
    candidates.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (child, _) in candidates) {
      final offset = (child.parentData! as WrapParentData).offset;
      if (result.addWithPaintOffset(
        offset: offset,
        position: position,
        hitTest: (result, position) =>
            child.hitTest(result, position: position),
      )) {
        return true;
      }
    }
    return false;
  }
}
