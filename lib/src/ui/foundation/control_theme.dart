import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// A control surface whose emphasis is independent of the forum's link color.
@immutable
class DControlSurface {
  const DControlSurface({
    required this.background,
    required this.hover,
    required this.foreground,
    this.border = Colors.transparent,
  });

  final Color background;
  final Color hover;
  final Color foreground;
  final Color border;

  static DControlSurface lerp(DControlSurface a, DControlSurface b, double t) =>
      DControlSurface(
        background: Color.lerp(a.background, b.background, t)!,
        hover: Color.lerp(a.hover, b.hover, t)!,
        foreground: Color.lerp(a.foreground, b.foreground, t)!,
        border: Color.lerp(a.border, b.border, t)!,
      );
}

/// Optional host styling shared by buttons, triggers and editable controls.
///
/// The palette supplies colors, while the kit retains sizing, interaction,
/// disabled and invalid states. Focus continues to use the separate focus token.
@immutable
class DControlTheme {
  const DControlTheme({
    required this.outline,
    required this.primary,
    required this.accent,
    required this.radius,
  });

  final DControlSurface outline;
  final DControlSurface primary;
  final DControlSurface accent;
  final double radius;

  static DControlTheme lerp(DControlTheme a, DControlTheme b, double t) =>
      DControlTheme(
        outline: DControlSurface.lerp(a.outline, b.outline, t),
        primary: DControlSurface.lerp(a.primary, b.primary, t),
        accent: DControlSurface.lerp(a.accent, b.accent, t),
        radius: lerpDouble(a.radius, b.radius, t)!,
      );
}
