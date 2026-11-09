import 'package:flutter/material.dart';

/// Painter configuration for the draggable thumb; RawScrollbar remains the
/// sole gesture and paint owner. Null color adapts to the container surface.
@immutable
class DScrollThumb {
  const DScrollThumb();

  /// Shared width in logical pixels for UI kit and native app scrollbars.
  static const double defaultThickness = 4;

  /// Clear space between the thumb and its container, in logical pixels.
  static const double containerInset = 2;

  /// A subdued thumb with at least 3:1 contrast against an opaque surface.
  /// Translucent surfaces should be composited over their backdrop by callers.
  static Color colorOn(Color background, {required Color foreground}) {
    double contrast(Color color) {
      final a = color.computeLuminance();
      final b = background.computeLuminance();
      return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
    }

    var target = Color.alphaBlend(foreground, background);
    if (contrast(target) < 3) {
      target = contrast(Colors.black) > contrast(Colors.white)
          ? Colors.black
          : Colors.white;
    }
    for (var step = 55; step < 100; step += 5) {
      final candidate = Color.lerp(background, target, step / 100)!;
      if (contrast(candidate) >= 3) return candidate;
    }
    return target;
  }
}
