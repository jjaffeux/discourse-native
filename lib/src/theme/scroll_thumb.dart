import 'package:flutter/material.dart';

/// Painter configuration for the draggable thumb; RawScrollbar remains the
/// sole gesture and paint owner. A scrollbar is only its thumb: no track and
/// no corner fill, in the palette's ink, thin and round.
@immutable
class DScrollThumb {
  const DScrollThumb();

  /// Shared width in logical pixels for UI kit and native app scrollbars.
  static const double defaultThickness = 4;

  /// Clear space between the thumb and its container, in logical pixels: a
  /// 10 wide gutter around a 4 wide thumb.
  static const double containerInset = 3;

  /// The thumb at rest, the ink at 24%.
  static Color color(Color ink) => ink.withValues(alpha: ink.a * .24);

  /// The thumb under the pointer or dragged, the ink at 36%.
  static Color activeColor(Color ink) => ink.withValues(alpha: ink.a * .36);
}
