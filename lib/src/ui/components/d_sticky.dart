import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'd_page_surface.dart';

/// Refreshes sticky children after a sliver's layout and scroll corrections.
///
/// Wrap the list containing [DSticky] slots. If several slivers can change
/// their positions, wrap their [SliverMainAxisGroup] instead. This keeps cached
/// avatar layers current when preceding content changes size without scrolling.
class DStickySliver extends SingleChildRenderObjectWidget {
  const DStickySliver({super.key, required Widget sliver})
    : super(child: sliver);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderStickySliver();
}

class _RenderStickySliver extends RenderProxySliver {
  final _stickies = <_RenderSticky>{};

  @override
  void performLayout() {
    super.performLayout();
    for (final sticky in _stickies) {
      sticky._scrollChanged();
    }
  }
}

/// Keeps a child near the top of its viewport within a bounded vertical slot.
///
/// The parent supplies a finite width and height, usually with a positioned
/// gutter beside scrolling content. The child starts at the slot's top and
/// stops at its bottom. [topOffset] is relative to the enclosing viewport, so
/// headers outside that viewport need no extra compensation. Floating Native
/// page headers are accounted for automatically as they hide and reveal.
///
/// Wrap the enclosing sliver in [DStickySliver] so layout changes elsewhere in
/// the list also update the position, including retained and recycled rows.
///
/// Scrolling changes paint and semantics without rebuilding or laying out the
/// child. The slot owns no styling or interaction; compose Native controls
/// inside it. Outside a scrollable, the child stays at the slot's top.
class DSticky extends SingleChildRenderObjectWidget {
  const DSticky({super.key, this.topOffset = 0, required super.child})
    : assert(topOffset >= 0);

  /// The minimum distance from the viewport's top while the child is pinned.
  final double topOffset;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSticky(
    Scrollable.maybeOf(context, axis: Axis.vertical)?.position,
    topOffset,
    DPageSurface.headerGeometryOf(context, insideViewport: true),
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderSticky)
      ..position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position
      ..topOffset = topOffset
      ..pageHeader = DPageSurface.headerGeometryOf(
        context,
        insideViewport: true,
      );
  }
}

class _RenderSticky extends RenderShiftedBox {
  _RenderSticky(this._position, this._topOffset, this._pageHeader)
    : super(null);

  ScrollPosition? _position;
  double _topOffset;
  DPageHeaderGeometry? _pageHeader;
  _RenderStickySliver? _sliver;

  set position(ScrollPosition? value) {
    if (identical(_position, value)) return;
    if (attached) _position?.removeListener(_scrollChanged);
    _position = value;
    if (attached) _position?.addListener(_scrollChanged);
    _scrollChanged();
  }

  set topOffset(double value) {
    if (_topOffset == value) return;
    _topOffset = value;
    _scrollChanged();
  }

  set pageHeader(DPageHeaderGeometry? value) {
    if (identical(_pageHeader, value)) return;
    if (attached) _pageHeader?.removeListener(_scrollChanged);
    _pageHeader = value;
    if (attached) _pageHeader?.addListener(_scrollChanged);
    _scrollChanged();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  Rect get paintBounds {
    final child = this.child;
    if (child == null || !hasSize || !child.hasSize) return Rect.zero;
    _updateOffset();
    // Cache the avatar's artwork, not an empty layer as tall as the post.
    return child.paintBounds.shift((child.parentData! as BoxParentData).offset);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _position?.addListener(_scrollChanged);
    _pageHeader?.addListener(_scrollChanged);
    for (var ancestor = parent; ancestor != null; ancestor = ancestor.parent) {
      if (ancestor is _RenderStickySliver) {
        _sliver = ancestor;
        ancestor._stickies.add(this);
        break;
      }
    }
  }

  @override
  void detach() {
    _position?.removeListener(_scrollChanged);
    _pageHeader?.removeListener(_scrollChanged);
    _sliver?._stickies.remove(this);
    _sliver = null;
    super.detach();
  }

  void _scrollChanged() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(
      constraints.hasBoundedWidth && constraints.hasBoundedHeight,
      'DSticky needs a bounded slot, such as a positioned gutter in a Stack.',
    );
    return constraints.biggest;
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
    child?.layout(constraints.loosen(), parentUsesSize: true);
  }

  void _updateOffset() {
    final child = this.child;
    if (child == null || !hasSize || !child.hasSize) return;
    final viewport = RenderAbstractViewport.maybeOf(this);
    // Kept-alive lazy rows can have no sliver offset until they return to the
    // viewport. Their old cached layers must not query that missing geometry.
    for (
      RenderObject? row = this;
      row != null && row != viewport;
      row = row.parent
    ) {
      final data = row.parentData;
      if (data is SliverMultiBoxAdaptorParentData &&
          (data.keptAlive || data.layoutOffset == null)) {
        return;
      }
    }
    final top = _position == null || viewport == null
        ? 0.0
        : localToGlobal(Offset.zero, ancestor: viewport).dy;
    final offset = _position == null || viewport == null
        ? 0.0
        : (_topOffset + (_pageHeader?.visibleExtent ?? 0) - top).clamp(
            0.0,
            size.height - child.size.height,
          );
    (child.parentData! as BoxParentData).offset = Offset(0, offset);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _updateOffset();
    super.paint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    _updateOffset();
    return super.hitTestChildren(result, position: position);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    _updateOffset();
    super.applyPaintTransform(child, transform);
  }
}
