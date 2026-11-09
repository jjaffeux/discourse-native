import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Shared button geometry and disabled opacity.
@immutable
class DiscourseButtonTheme extends ThemeExtension<DiscourseButtonTheme> {
  const DiscourseButtonTheme({
    required this.borderRadius,
    this.disabledOpacity = 0.6,
  });
  final double borderRadius;
  final double disabledOpacity;
  @override
  DiscourseButtonTheme copyWith({
    double? borderRadius,
    double? disabledOpacity,
  }) => DiscourseButtonTheme(
    borderRadius: borderRadius ?? this.borderRadius,
    disabledOpacity: disabledOpacity ?? this.disabledOpacity,
  );
  @override
  DiscourseButtonTheme lerp(covariant DiscourseButtonTheme? other, double t) =>
      other == null
      ? this
      : DiscourseButtonTheme(
          borderRadius: lerpDouble(borderRadius, other.borderRadius, t)!,
          disabledOpacity: lerpDouble(
            disabledOpacity,
            other.disabledOpacity,
            t,
          )!,
        );
}

extension DiscourseButtonThemeAccess on ThemeData {
  DiscourseButtonTheme get discourseButtons =>
      extension<DiscourseButtonTheme>() ??
      const DiscourseButtonTheme(borderRadius: DRadius.control);
}
