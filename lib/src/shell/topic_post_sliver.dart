import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
// The package does not export its element, which owns the measured extents.
// ignore: implementation_imports
import 'package:super_sliver_list/src/element.dart';
// ignore: implementation_imports
import 'package:super_sliver_list/src/render_object.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../models/post.dart';
import '../utils/pagination.dart';
import 'topic_viewport_coordinator.dart';

part 'topic_reader_geometry.dart';

/// Positions the reader before paint, including while its anchor changes size.
class TopicPostScrollController extends PaginationScrollController {
  TopicPostScrollController(
    this._initialOffset, {
    required this.anchorOffset,
    this.topInset,
  });

  double? Function()? _initialOffset;
  final double? Function() anchorOffset;
  final ValueGetter<double>? topInset;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _TopicPostScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    targetOffset: () => _initialOffset?.call() ?? anchorOffset(),
    onPositioned: () => _initialOffset = null,
    topInset: topInset,
  );
}

class _TopicPostScrollPosition extends PaginationScrollPosition {
  _TopicPostScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.targetOffset,
    required this.onPositioned,
    required this.topInset,
  });

  final double? Function() targetOffset;
  final VoidCallback onPositioned;
  final ValueGetter<double>? topInset;

  @override
  Future<void> ensureVisible(
    RenderObject object, {
    double alignment = 0,
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
    ScrollPositionAlignmentPolicy alignmentPolicy =
        ScrollPositionAlignmentPolicy.explicit,
    RenderObject? targetRenderObject,
  }) async {
    final inset = topInset?.call() ?? 0;
    if (inset == 0 ||
        axisDirection != AxisDirection.down ||
        alignmentPolicy == ScrollPositionAlignmentPolicy.keepVisibleAtEnd) {
      return super.ensureVisible(
        object,
        alignment: alignment,
        duration: duration,
        curve: curve,
        alignmentPolicy: alignmentPolicy,
        targetRenderObject: targetRenderObject,
      );
    }
    final viewport = RenderAbstractViewport.maybeOf(object);
    if (viewport == null) return;
    final rect = targetRenderObject != null && targetRenderObject != object
        ? MatrixUtils.transformRect(
            targetRenderObject.getTransformTo(object),
            object.paintBounds.intersect(targetRenderObject.paintBounds),
          )
        : null;
    final align = alignmentPolicy == ScrollPositionAlignmentPolicy.explicit
        ? alignment
        : 0.0;
    // Align within the readable area below the overlay. This also protects
    // focused controls revealed by Flutter, rather than topic navigation.
    var target =
        (viewport
                    .getOffsetToReveal(object, align, rect: rect, axis: axis)
                    .offset -
                inset * (1 - align))
            .clamp(minScrollExtent, maxScrollExtent);
    if (alignmentPolicy == ScrollPositionAlignmentPolicy.keepVisibleAtStart &&
        target > pixels) {
      target = pixels;
    }
    if (target == pixels) return;
    if (duration == Duration.zero) {
      jumpTo(target);
    } else {
      await animateTo(target, duration: duration, curve: curve);
    }
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (!super.applyContentDimensions(minScrollExtent, maxScrollExtent)) {
      return false;
    }
    final offset = targetOffset();
    if (offset == null) return true;
    final target = offset.clamp(minScrollExtent, maxScrollExtent);
    if ((target - pixels).abs() > precisionErrorTolerance) {
      // Repeat layout with the target visible. Its measured height and the
      // surrounding estimates can change, so resolve again before accepting it.
      correctPixels(target);
      return false;
    }
    onPositioned();
    return true;
  }
}

/// Keeps moved topic rows lazy while their measured extents shift with post IDs.
class TopicPostSliver extends SuperSliverList {
  TopicPostSliver({
    required TopicReaderGeometry geometry,
    required super.itemBuilder,
    required super.separatorBuilder,
    required super.itemCount,
    super.delayPopulatingCacheArea,
    super.layoutKeptAliveChildren,
  }) : super.separated(
         key: geometry.sliverKey,
         listController: geometry._list,
         findChildIndexCallback: geometry.findChildIndexCallback,
         extentEstimation: TopicReaderGeometry.estimateChildExtent,
       );

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
  bool _resizing = false;

  @override
  double? childScrollOffset(RenderObject child) {
    final offset = super.childScrollOffset(child);
    final data = child.parentData! as SliverMultiBoxAdaptorParentData;
    if (offset == null && _resizing && data.keptAlive) {
      // A width change can move the previously visible row into keep-alive
      // storage while SuperSliverList still uses it as its resize anchor.
      // Its layout offset was cleared; the retained extent table owns its
      // current position, including the rows measured during this pass.
      final manager = (childManager as _TopicPostSliverElement).extentManager;
      final index = data.index;
      if (index != null && index < manager.numberOfItems) {
        return manager.offsetForIndex(index);
      }
    }
    return offset;
  }

  @override
  void performLayout() {
    final previous = _precedingExtent;
    _precedingExtent = constraints.precedingScrollExtent;
    // Preserve the row anchor if an opening sliver changes its extent,
    // including while a drag is still in progress.
    if (previous != null && constraints.scrollOffset > 0) {
      final delta = constraints.precedingScrollExtent - previous;
      if (delta.abs() > precisionErrorTolerance) {
        geometry = SliverGeometry(scrollOffsetCorrection: delta);
        return;
      }
    }
    if (_didRebuild) {
      _didRebuild = false;
      _discardOffscreenPrefixBeforeGap();
    }
    _resizing =
        previousConstraints != null &&
        previousConstraints!.crossAxisExtent != constraints.crossAxisExtent;
    try {
      final correction = _layoutLeadingCache();
      if (correction.abs() > precisionErrorTolerance) {
        geometry = SliverGeometry(scrollOffsetCorrection: correction);
        return;
      }
      super.performLayout();
    } finally {
      _resizing = false;
    }
  }

  double _layoutLeadingCache() {
    if (_resizing ||
        previousConstraints == null ||
        hasChildScrollOffsetEstimation ||
        constraints.scrollOffset <= 0 ||
        constraints.remainingPaintExtent <= 0) {
      return 0;
    }
    final leading =
        constraints.scrollOffset +
        (constraints.overlap > 0 ? constraints.overlap : 0);
    final trailing =
        constraints.scrollOffset + constraints.remainingPaintExtent;
    RenderBox? anchor;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final offset = childScrollOffset(child);
      if (offset == null || !child.hasSize) continue;
      if (offset >= trailing) break;
      if (offset + paintExtentOf(child) > leading) {
        anchor = child;
        break;
      }
    }
    if (anchor == null || anchor == firstChild) return 0;

    // Measure the cached prefix before normal layout can collect a visible
    // child's state using the newly expanded prefix's uncorrected offsets.
    final manager = (childManager as _TopicPostSliverElement).extentManager;
    if (indexOf(anchor) >= manager.numberOfItems) return 0;
    final childConstraints = constraints.asBoxConstraints();
    var correction = 0.0;
    var beforeAnchor = true;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as SliverMultiBoxAdaptorParentData;
      if (data.layoutOffset case final offset? when correction != 0) {
        data.layoutOffset = offset + correction;
      }
      if (child == anchor) beforeAnchor = false;
      if (!beforeAnchor) continue;
      final index = indexOf(child);
      final previousExtent = manager.getExtent(index);
      child.layout(childConstraints, parentUsesSize: true);
      final extent = paintExtentOf(child);
      if (extent != previousExtent) {
        manager.setExtent(index, extent);
        correction += extent - previousExtent;
      }
    }
    return correction;
  }

  bool _didRebuild = false;

  void _discardOffscreenPrefixBeforeGap() {
    // The earlier-page header stays at index zero while old replies move.
    // The package fills gaps between attached children before discarding
    // offscreen ones, so remove that prefix before it can build the new page.
    final cacheStart = constraints.scrollOffset + constraints.cacheOrigin;
    var prefixLength = 0;
    int? previousIndex;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final index = indexOf(child);
      if (previousIndex != null && index != previousIndex + 1) {
        collectGarbage(prefixLength, 0);
        return;
      }
      final offset = childScrollOffset(child);
      if (offset == null ||
          !child.hasSize ||
          offset + paintExtentOf(child) >= cacheStart) {
        return;
      }
      prefixLength++;
      previousIndex = index;
    }
  }
}

class _TopicPostSliverElement extends SuperSliverMultiBoxAdaptorElement {
  _TopicPostSliverElement(super.widget) : super(replaceMovedChildren: false);

  @override
  void performRebuild() {
    super.performRebuild();
    // The adapter shifts the extent table before replacing the delegate. Flutter
    // clears offsets on moved children and copies offsets by their old index;
    // restore them from the shifted table instead. This lets the render sliver
    // start at the existing rows without constructing their vacated slots.
    final renderObject = this.renderObject as _TopicPostRenderSliver;
    renderObject._didRebuild = true;
    renderObject.visitChildren((child) {
      final data = child.parentData! as SliverMultiBoxAdaptorParentData;
      if (data.index! < extentManager.numberOfItems) {
        data.layoutOffset = extentManager.offsetForIndex(data.index!);
      }
    });
  }
}
