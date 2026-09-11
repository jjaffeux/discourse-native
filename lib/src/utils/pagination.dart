import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Starts fetching with two screens left to read, including on small windows.
/// Request deduplication and exhausted/error state remain owned by each feed.
double paginationPrefetchDistance(ScrollMetrics metrics) =>
    math.max(1600, metrics.viewportDimension * 2);
