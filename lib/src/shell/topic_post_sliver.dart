import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
// The package does not export its element, which owns the measured extents.
// ignore: implementation_imports
import 'package:super_sliver_list/src/element.dart';
// ignore: implementation_imports
import 'package:super_sliver_list/src/render_object.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// Keeps moved topic rows lazy while their measured extents shift with post IDs.
class TopicPostSliver extends SuperSliverList {
  TopicPostSliver({
    super.key,
    required super.itemBuilder,
    required super.separatorBuilder,
    required super.itemCount,
    required super.findChildIndexCallback,
    required super.listController,
    required super.extentEstimation,
    super.delayPopulatingCacheArea,
    super.layoutKeptAliveChildren,
  }) : super.separated();

  @override
  SliverMultiBoxAdaptorElement createElement() => _TopicPostSliverElement(this);

  @override
  RenderSliverMultiBoxAdaptor createRenderObject(BuildContext context) =>
      _TopicPostRenderSliver(
        childManager: context as _TopicPostSliverElement,
        estimateExtent: extentEstimation!,
        delayPopulatingCacheArea: delayPopulatingCacheArea,
        layoutKeptAliveChildren: layoutKeptAliveChildren,
      );
}

class _TopicPostRenderSliver extends RenderSuperSliverList {
  _TopicPostRenderSliver({
    required super.childManager,
    required super.estimateExtent,
    required super.delayPopulatingCacheArea,
    required super.layoutKeptAliveChildren,
  });

  double? _precedingExtent;

  @override
  void performLayout() {
    final previous = _precedingExtent;
    _precedingExtent = constraints.precedingScrollExtent;
    // Loading the first page reveals the inbox activity summary above this
    // sliver. Correct during layout so an ongoing drag keeps its position too.
    if (previous != null && constraints.scrollOffset > 0) {
      final delta = constraints.precedingScrollExtent - previous;
      if (delta.abs() > precisionErrorTolerance) {
        geometry = SliverGeometry(scrollOffsetCorrection: delta);
        return;
      }
    }
    super.performLayout();
  }
}

class _TopicPostSliverElement extends SuperSliverMultiBoxAdaptorElement {
  _TopicPostSliverElement(super.widget) : super(replaceMovedChildren: false);

  @override
  void performRebuild() {
    super.performRebuild();
    // TopicView shifts the extent table before replacing the delegate. Flutter
    // clears offsets on moved children and copies offsets by their old index;
    // restore them from the shifted table instead. This lets the render sliver
    // start at the existing rows without constructing their vacated slots.
    renderObject.visitChildren((child) {
      final data = child.parentData! as SliverMultiBoxAdaptorParentData;
      if (data.index! < extentManager.numberOfItems) {
        data.layoutOffset = extentManager.offsetForIndex(data.index!);
      }
    });
  }
}
