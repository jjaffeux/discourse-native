import 'package:flutter/widgets.dart';

/// Geometry shared by DTooltip and the Material tooltip theme.
abstract final class DTooltipMetrics {
  /// How long the pointer must remain over a trigger before showing its hint.
  static const hoverDelay = Duration(milliseconds: 250);

  static const constraints = BoxConstraints(maxWidth: 320);
  static const padding = EdgeInsets.symmetric(horizontal: 12, vertical: 6);
  static const margin = EdgeInsets.all(5);
  static const double verticalOffset = 4;
}
