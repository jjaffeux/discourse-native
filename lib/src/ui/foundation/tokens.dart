import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'control_theme.dart';

/// Semantic component tokens. The host maps its palette at the theme boundary.
@immutable
class DTokens extends ThemeExtension<DTokens> {
  const DTokens({
    required this.colors,
    required this.background,
    required this.surface,
    required this.muted,
    required this.border,
    required this.hover,
    required this.selected,
    required this.selectedForeground,
    this.successColor,
    this.radius = 4,
    this.controls,
  });

  factory DTokens.fromTheme(ThemeData theme) {
    final colors = theme.colorScheme;
    return DTokens(
      colors: colors,
      background: colors.surface,
      surface: colors.surfaceContainerLow,
      muted: colors.surfaceContainer,
      border: colors.outlineVariant,
      hover: colors.surfaceContainerHigh,
      selected: colors.secondaryContainer,
      selectedForeground: colors.onSecondaryContainer,
      successColor: colors.tertiary,
    );
  }

  static DTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<DTokens>() ?? DTokens.fromTheme(theme);
  }

  final ColorScheme colors;
  final Color background;
  final Color surface;
  final Color muted;
  final Color border;
  final Color hover;
  final Color selected;
  final Color selectedForeground;

  /// Optional positive-state override supplied by the host palette.
  final Color? successColor;
  final double radius;

  final DControlTheme? controls;

  double get controlRadius => controls?.radius ?? radius;

  Color get foreground => colors.onSurface;
  Color get mutedForeground => colors.onSurfaceVariant;
  Color get primary => colors.primary;
  Color get primaryForeground => colors.onPrimary;
  Color get destructive => colors.error;
  Color get destructiveForeground => colors.onError;
  Color get focusRing => colors.primary;

  /// Positive state color supplied by the host palette.
  ///
  /// Ordinary Material themes fall back to their tertiary color.
  Color get success => successColor ?? colors.tertiary;

  BorderRadius get borderRadius => BorderRadius.circular(radius);

  @override
  DTokens copyWith({
    ColorScheme? colors,
    Color? background,
    Color? surface,
    Color? muted,
    Color? border,
    Color? hover,
    Color? selected,
    Color? selectedForeground,
    Color? successColor,
    double? radius,
    DControlTheme? controls,
  }) => DTokens(
    colors: colors ?? this.colors,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    muted: muted ?? this.muted,
    border: border ?? this.border,
    hover: hover ?? this.hover,
    selected: selected ?? this.selected,
    selectedForeground: selectedForeground ?? this.selectedForeground,
    successColor: successColor ?? success,
    radius: radius ?? this.radius,
    controls: controls ?? this.controls,
  );

  @override
  DTokens lerp(ThemeExtension<DTokens>? other, double t) {
    if (other is! DTokens) return this;
    return DTokens(
      colors: ColorScheme.lerp(colors, other.colors, t),
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      selectedForeground: Color.lerp(
        selectedForeground,
        other.selectedForeground,
        t,
      )!,
      successColor: Color.lerp(success, other.success, t)!,
      radius: lerpDouble(radius, other.radius, t)!,
      controls: controls == null && other.controls == null
          ? null
          : DControlTheme.lerp(
              controls ?? _referenceControls,
              other.controls ?? other._referenceControls,
              t,
            ),
    );
  }

  DControlTheme get _referenceControls {
    final dark = colors.brightness == Brightness.dark;
    final action = DControlSurface(
      background: primary,
      hover: primary.withValues(alpha: primary.a * .8),
      foreground: primaryForeground,
    );
    return DControlTheme(
      outline: DControlSurface(
        background: dark
            ? colors.outlineVariant.withValues(
                alpha: colors.outlineVariant.a * .3,
              )
            : background,
        hover: dark
            ? colors.outlineVariant.withValues(
                alpha: colors.outlineVariant.a * .5,
              )
            : muted,
        foreground: foreground,
        border: dark ? colors.outlineVariant : border,
      ),
      primary: action,
      accent: action,
      radius: radius,
    );
  }
}

/// Logical pixels; text continues to use the host's semantic TextTheme roles.
abstract final class DSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double touchTarget = 48;
}

abstract final class DMotion {
  static const Duration open = Duration(milliseconds: 100);
  static const Duration close = Duration(milliseconds: 100);
  static const Duration spin = Duration(seconds: 1);
  static const Duration enter = Duration(milliseconds: 140);
  static const Duration exit = Duration(milliseconds: 100);
  static const Duration change = Duration(milliseconds: 180);

  /// One leg of shadcn's two-second, full-opacity → half-opacity → full pulse.
  static const Duration pulse = Duration(seconds: 1);

  static Duration duration(BuildContext context, Duration preferred) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : preferred;

  static AnimationStyle overlay(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: enter,
          reverseDuration: exit,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
}
