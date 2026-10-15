import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Exposes ballistic speed for fetching ahead without polling during scrolling.
class PaginationScrollController extends ScrollController {
  double get velocity =>
      hasClients ? (position as PaginationScrollPosition).velocity : 0;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => PaginationScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class PaginationScrollPosition extends ScrollPositionWithSingleContext {
  PaginationScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  double get velocity => activity?.velocity ?? 0;
}

/// Starts fetching with two screens left to read, including on small windows.
///
/// Fling headroom targets 750ms for the request and layout, capped at six
/// screens. Negative [velocity] moves away from the edge and retains the
/// ordinary reading window.
/// Request deduplication and exhausted/error state remain owned by each feed.
double paginationPrefetchDistance(
  ScrollMetrics metrics, {
  double velocity = 0,
}) {
  final readingDistance = math.max(1600.0, metrics.viewportDimension * 2);
  final flingDistance = velocity.isFinite
      ? (velocity * .75).clamp(0.0, metrics.viewportDimension * 6)
      : 0.0;
  return math.max(readingDistance, flingDistance);
}
