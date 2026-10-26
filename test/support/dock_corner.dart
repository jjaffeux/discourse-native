import 'dart:math' as math;

/// Where the phone bar's circle, and what follows it, settle into a screen
/// corner: on the corner's diagonal for something [extent] across, never
/// deeper than the [foot], and the bar's 6 on a square screen. Stated here
/// from the mockup so that a test never asks the dock geometry for its own
/// expectation.
double dockCornerAt(double extent, double foot) => math.max(
  6,
  math.min(foot, 55 - (55 - 6 - extent / 2) * 0.7071 - extent / 2),
);
