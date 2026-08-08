import 'package:flutter/material.dart';

const double minimumTextContrastRatio = 4.5;

/// Resolves [color] against the opaque canvas behind the app.
///
/// Theme colors normally arrive opaque. Theme components are allowed to
/// override them with alpha, though, and luminance is only meaningful after
/// that alpha has been composited onto a real surface.
Color opaqueColorOnCanvas(Color color, Brightness brightness) =>
    Color.alphaBlend(
      color,
      brightness == Brightness.dark ? Colors.black : Colors.white,
    );

/// Picks the first preferred foreground that remains readable after both it
/// and [background] have been painted. Falls back to opaque black or white.
///
/// [backdrop] must already be opaque. Returning the original candidate keeps a
/// site's translucent foreground intact; the comparison uses the color a
/// reader will actually see after Flutter composites it.
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
