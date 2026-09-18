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
    Color? hoverBorder,
  }) : hoverBorder = hoverBorder ?? border;

  final Color background;
  final Color hover;
  final Color foreground;
  final Color border;
  final Color hoverBorder;

  static DControlSurface lerp(DControlSurface a, DControlSurface b, double t) =>
      DControlSurface(
        background: Color.lerp(a.background, b.background, t)!,
        hover: Color.lerp(a.hover, b.hover, t)!,
        foreground: Color.lerp(a.foreground, b.foreground, t)!,
        border: Color.lerp(a.border, b.border, t)!,
        hoverBorder: Color.lerp(a.hoverBorder, b.hoverBorder, t)!,
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

  /// Linear's neutral raised controls and solid actions, using the host palette.
  factory DControlTheme.linear(
    ColorScheme colors,
    Color background, {
    required double radius,
  }) {
    final dark = colors.brightness == Brightness.dark;
    Color mix(Color color, double amount) =>
        Color.lerp(background, color, amount)!;
    final edge = dark ? Colors.white : Colors.black;
    final border = edge.withValues(alpha: dark ? .167 : .14);
    double contrast(Color foreground, Color background) {
      final first = foreground.computeLuminance() + .05;
      final second = background.computeLuminance() + .05;
      return first > second ? first / second : second / first;
    }

    var primaryHover = Color.lerp(
      colors.primary,
      dark ? Colors.white : Colors.black,
      .08,
    )!;
    // A custom forum accent can be near the text contrast threshold. Move
    // away from the label instead when Linear's lighter hover would cross it.
    if (contrast(colors.onPrimary, primaryHover) < 4.5) {
      primaryHover = Color.lerp(
        colors.primary,
        colors.onPrimary.computeLuminance() > .5 ? Colors.black : Colors.white,
        .08,
      )!;
    }
    return DControlTheme(
      radius: radius,
      outline: DControlSurface(
        background: dark ? mix(colors.onSurface, .045) : background,
        hover: mix(colors.onSurface, dark ? .085 : .035),
        foreground: colors.onSurface,
        border: border,
        hoverBorder: edge.withValues(alpha: dark ? .278 : .22),
      ),
      primary: DControlSurface(
        background: colors.primary,
        hover: primaryHover,
        foreground: colors.onPrimary,
      ),
      accent: DControlSurface(
        background: mix(colors.primary, dark ? .16 : .08),
        hover: mix(colors.primary, dark ? .24 : .14),
        foreground: colors.onSurface,
        border: border,
        hoverBorder: edge.withValues(alpha: dark ? .278 : .22),
      ),
    );
  }

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
