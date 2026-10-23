import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Flat post-reaction artwork shared by Native actions and toggles.
abstract final class DPostReactionStyle {
  static const fontSize = 12.5;
  static const iconSize = 14.0;
  static const gap = 5.0;

  static double height(TextScaler scaler) =>
      30 + math.max(0, scaler.scale(fontSize) - fontSize) * 1.5;

  static Color foreground(DTokens tokens, {bool selected = false}) => selected
      ? tokens.foreground
      : Color.lerp(tokens.background, tokens.foreground, .62)!;

  static Color fill(
    DTokens tokens, {
    bool selected = false,
    bool interacting = false,
  }) => selected
      ? tokens.primary.withValues(alpha: .24)
      : interacting
      ? tokens.quietControlSurface().hover
      : tokens.quietControlSurface().background;
}
