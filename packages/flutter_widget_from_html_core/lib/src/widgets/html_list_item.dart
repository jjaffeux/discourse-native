import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

const _kGapVsMarker = 5.0;

/// A list item widget.
class HtmlListItem extends MultiChildRenderObjectWidget {
  /// Whether the marker takes up space on the leading side of the item.
  final bool markerInside;

  /// The alignment of the item contents.
  final TextAlign? textAlign;

  /// The directionality of the item.
  final TextDirection textDirection;

  /// Creates a list item widget.
  HtmlListItem({
    Widget? child,
    super.key,
    Widget? marker,
    this.markerInside = false,
    this.textAlign,
    required this.textDirection,
  }) : super(
          children: child != null
              ? [
                  child,
                  if (marker != null) marker,
                ]
              : const [],
        );

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ListItemRenderObject(
        markerInside: markerInside,
        textAlign: textAlign,
        textDirection: textDirection,
      );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty('textAlign', textAlign, defaultValue: null));
    properties.add(DiagnosticsProperty('textDirection', textDirection));
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    renderObject as _ListItemRenderObject
      ..markerInside = markerInside
      ..textAlign = textAlign
      ..textDirection = textDirection;
  }
}

class _ListItemData extends ContainerBoxParentData<RenderBox> {}

class _ListItemRenderObject extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ListItemData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ListItemData> {
  _ListItemRenderObject({
    required bool markerInside,
    TextAlign? textAlign,
    required TextDirection textDirection,
  })  : _markerInside = markerInside,
        _textAlign = textAlign,
        _textDirection = textDirection;

  bool _markerInside;
  set markerInside(bool value) {
    if (_markerInside == value) {
      return;
    }
    _markerInside = value;
    markNeedsLayout();
  }

  RenderBox? get _insideMarker =>
      _markerInside && childCount == 2 ? lastChild : null;

  TextAlign? get textAlign => _textAlign;
  TextAlign? _textAlign;
  set textAlign(TextAlign? value) {
    if (_textAlign == value) {
      return;
    }

    _textAlign = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) {
      return;
    }

    _textDirection = value;
    markNeedsLayout();
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final child = firstChild;
    if (child == null) {
      return null;
    }

    final marker = _insideMarker;
    final gutter = marker == null
        ? 0.0
        : marker.getDryLayout(constraints.loosen()).width + _kGapVsMarker;
    return child.getDryBaseline(
        _bodyConstraints(constraints, gutter), baseline);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _compute(firstChild, constraints, ChildLayoutHelper.dryLayoutChild);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      firstChild?.computeMaxIntrinsicHeight(_bodyWidth(width)) ??
      super.computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      (firstChild?.computeMaxIntrinsicWidth(height) ??
          super.computeMaxIntrinsicWidth(height)) +
      _intrinsicGutter(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      firstChild?.computeMinIntrinsicHeight(_bodyWidth(width)) ??
      super.computeMinIntrinsicHeight(width);

  @override
  double computeMinIntrinsicWidth(double height) =>
      (firstChild?.getMinIntrinsicWidth(height) ??
          super.computeMinIntrinsicWidth(height)) +
      _intrinsicGutter(height);

  double _intrinsicGutter(double height) {
    final marker = _insideMarker;
    return marker == null
        ? 0.0
        : marker.getMaxIntrinsicWidth(height) + _kGapVsMarker;
  }

  double _bodyWidth(double width) =>
      (width - _intrinsicGutter(double.infinity)).clamp(0.0, width);

  BoxConstraints _bodyConstraints(BoxConstraints constraints, double gutter) {
    final available = constraints.deflate(EdgeInsets.only(left: gutter));
    return available.maxWidth.isFinite && textAlign != null
        ? available.tighten(width: available.maxWidth)
        : available;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  void performLayout() =>
      size = _compute(firstChild, constraints, ChildLayoutHelper.layoutChild);

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ListItemData) {
      child.parentData = _ListItemData();
    }
  }

  Size _compute(RenderBox? child, BoxConstraints bc, ChildLayouter fn) {
    if (child == null) {
      return bc.smallest;
    }

    final childData = child.parentData! as _ListItemData;
    final marker = childData.nextSibling;
    final markerSize = marker != null ? fn(marker, bc.loosen()) : Size.zero;
    final gutter = _markerInside && marker != null
        ? markerSize.width + _kGapVsMarker
        : 0.0;
    final childSize = fn(child, _bodyConstraints(bc, gutter));
    final height = childSize.height > 0 ? childSize.height : markerSize.height;
    final size = bc.constrain(Size(childSize.width + gutter, height));

    if (identical(fn, ChildLayoutHelper.layoutChild)) {
      final ltr = textDirection == TextDirection.ltr;
      childData.offset = Offset(ltr ? gutter : 0, 0);

      if (marker != null) {
        const baseline = TextBaseline.alphabetic;
        final markerDistance =
            marker.getDistanceToBaseline(baseline, onlyReal: true) ??
                markerSize.height;
        final childDistance =
            child.getDistanceToBaseline(baseline, onlyReal: true) ??
                markerDistance;

        final markerData = marker.parentData! as _ListItemData;
        markerData.offset = Offset(
          ltr
              ? childData.offset.dx - (markerSize.width + _kGapVsMarker)
              : childSize.width + _kGapVsMarker,
          childDistance - markerDistance,
        );
      }
    }

    return size;
  }
}
