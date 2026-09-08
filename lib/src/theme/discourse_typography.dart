import 'package:flutter/material.dart';

/// The app's unscaled type system, using Tailwind's size and leading pairs.
///
/// https://tailwindcss.com/docs/font-size
/// Choose a semantic [TextTheme] role in widgets: bodyMedium for interface
/// text, labelLarge for controls, bodyLarge for reading, bodySmall/labelSmall
/// for metadata, titleSmall for row titles, titleMedium for section titles,
/// titleLarge for dialogs, and headlineSmall for page titles.
///
/// Sizes are logical pixels at 100%. Only the root AppTextScaleRegion applies
/// zoom; styles must never multiply their font size by the user's scale.
abstract final class DiscourseTypography {
  static const double xs = 12;
  static const double sm = 14;
  static const double base = 16;
  static const double lg = 18;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 30;
  static const double xxxxl = 36;

  static const List<double> fontSizes = [
    xs,
    sm,
    base,
    lg,
    xl,
    xxl,
    xxxl,
    xxxxl,
  ];

  static const double lineHeightCaption = 16 / xs;
  static const double lineHeightSmall = 20 / sm;
  static const double lineHeightBody = 24 / base;
  static const double lineHeightProse = 28 / base;
  static const double lineHeightLarge = 28 / lg;
  static const double lineHeightTitle = 28 / xl;
  static const double lineHeightHeading = 32 / xxl;
  static const double lineHeightDisplaySmall = 36 / xxxl;
  static const double lineHeightDisplayLarge = 40 / xxxxl;
  static const double trackingTight = -0.025;

  /// Authored headings share the scale with the interface (h1 through h6).
  static const List<double> headingSizes = [xxxl, xxl, xl, lg, base, sm];

  static double headingSize(int level) => headingSizes[level.clamp(1, 6) - 1];

  static double headingLineHeight(int level) => switch (level.clamp(1, 6)) {
    1 => lineHeightDisplaySmall,
    2 => lineHeightHeading,
    3 => lineHeightTitle,
    4 => lineHeightLarge,
    5 => lineHeightBody,
    _ => lineHeightSmall,
  };

  static const double codeLineHeight = lineHeightSmall;
  static const double lineHeightMedium = lineHeightHeading;
  static const double lineHeightCooked = lineHeightBody;

  /// Keeps Material defaults, native controls, and custom widgets on the same
  /// roles while retaining the platform font family and palette foregrounds.
  static TextTheme textTheme(TextTheme platform) {
    TextStyle style(
      TextStyle? original,
      double size,
      double height, [
      FontWeight weight = FontWeight.normal,
    ]) => (original ?? const TextStyle()).copyWith(
      fontSize: size,
      height: height,
      fontWeight: weight,
      letterSpacing: 0,
    );

    return TextTheme(
      displayLarge: style(
        platform.displayLarge,
        xxxxl,
        lineHeightDisplayLarge,
        FontWeight.w600,
      ),
      displayMedium: style(
        platform.displayMedium,
        xxxl,
        lineHeightDisplaySmall,
        FontWeight.w600,
      ),
      displaySmall: style(
        platform.displaySmall,
        xxl,
        lineHeightHeading,
        FontWeight.w600,
      ),
      headlineLarge: style(
        platform.headlineLarge,
        xxxxl,
        lineHeightDisplayLarge,
        FontWeight.w600,
      ),
      headlineMedium: style(
        platform.headlineMedium,
        xxxl,
        lineHeightDisplaySmall,
        FontWeight.w600,
      ),
      headlineSmall: style(
        platform.headlineSmall,
        xxl,
        lineHeightHeading,
        FontWeight.w600,
      ),
      titleLarge: style(
        platform.titleLarge,
        xl,
        lineHeightTitle,
        FontWeight.w600,
      ),
      titleMedium: style(
        platform.titleMedium,
        lg,
        lineHeightLarge,
        FontWeight.w600,
      ),
      titleSmall: style(
        platform.titleSmall,
        base,
        lineHeightBody,
        FontWeight.w500,
      ),
      bodyLarge: style(platform.bodyLarge, base, lineHeightBody),
      bodyMedium: style(platform.bodyMedium, sm, lineHeightSmall),
      bodySmall: style(platform.bodySmall, xs, lineHeightCaption),
      labelLarge: style(
        platform.labelLarge,
        sm,
        lineHeightSmall,
        FontWeight.w500,
      ),
      labelMedium: style(platform.labelMedium, sm, lineHeightSmall),
      labelSmall: style(
        platform.labelSmall,
        xs,
        lineHeightCaption,
        FontWeight.w500,
      ),
    );
  }

  // Compatibility aliases for consumers of discourse_plugin_sdk.dart.
  @Deprecated('Use xs or a semantic TextTheme role.')
  static const double fontDown3 = xs;
  @Deprecated('Use xs or a semantic TextTheme role.')
  static const double fontDown2 = xs;
  @Deprecated('Use sm or a semantic TextTheme role.')
  static const double fontDown1 = sm;
  @Deprecated('Use lg or a semantic TextTheme role.')
  static const double fontUp1 = lg;
  @Deprecated('Use xl or a semantic TextTheme role.')
  static const double fontUp2 = xl;
  @Deprecated('Use xxl or a semantic TextTheme role.')
  static const double fontUp3 = xxl;
  @Deprecated('Use xxxl or a semantic TextTheme role.')
  static const double fontUp4 = xxxl;
  @Deprecated('Use xxxl or a semantic TextTheme role.')
  static const double fontUp5 = xxxl;
  @Deprecated('Use xxxxl or a semantic TextTheme role.')
  static const double fontUp6 = xxxxl;
  @Deprecated('Use sm instead.')
  static const double code = sm;
}
