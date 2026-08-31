import 'package:flutter/material.dart';

const double minimumTextContrastRatio = 4.5;

Color opaqueColorOnCanvas(Color color, Brightness brightness) =>
    Color.alphaBlend(
      color,
      brightness == Brightness.dark ? Colors.black : Colors.white,
    );

Color contrastSafeForeground({
  required Color background,
  required Color backdrop,
  required Iterable<Color?> preferred,
}) {
  assert(backdrop.a == 1.0);
  final paintedBackground = Color.alphaBlend(background, backdrop);

  for (final candidate in preferred) {
    if (candidate == null) continue;
    if (_paintedContrast(candidate, paintedBackground) >=
        minimumTextContrastRatio) {
      return candidate;
    }
  }

  final blackContrast = _paintedContrast(Colors.black, paintedBackground);
  final whiteContrast = _paintedContrast(Colors.white, paintedBackground);
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}

double _paintedContrast(Color foreground, Color paintedBackground) =>
    _opaqueContrast(
      Color.alphaBlend(foreground, paintedBackground),
      paintedBackground,
    );

double _opaqueContrast(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
