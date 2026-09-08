import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

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
    this.radius = 4,
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
  final double radius;

  Color get foreground => colors.onSurface;
  Color get mutedForeground => colors.onSurfaceVariant;
  Color get primary => colors.primary;
  Color get primaryForeground => colors.onPrimary;
  Color get destructive => colors.error;
  Color get destructiveForeground => colors.onError;
  Color get focusRing => colors.primary;

  /// A visible placeholder on both content and muted loading panels.
  Color get skeleton =>
      Color.alphaBlend(foreground.withValues(alpha: 0.16), muted);
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
    double? radius,
  }) => DTokens(
    colors: colors ?? this.colors,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    muted: muted ?? this.muted,
    border: border ?? this.border,
    hover: hover ?? this.hover,
    selected: selected ?? this.selected,
    selectedForeground: selectedForeground ?? this.selectedForeground,
    radius: radius ?? this.radius,
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
      radius: lerpDouble(radius, other.radius, t)!,
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
  static const Duration enter = Duration(milliseconds: 140);
  static const Duration exit = Duration(milliseconds: 100);
  static const Duration change = Duration(milliseconds: 180);
  static const Duration pulse = Duration(milliseconds: 675);

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
