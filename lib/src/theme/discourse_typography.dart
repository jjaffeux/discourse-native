import 'package:flutter/material.dart';

/// The shared desktop/mobile type system from the local design reference.
/// See docs/design/reference-rules.md for measured roles and native adaptations.
/// Choose a semantic [TextTheme] role in widgets: bodyMedium for interface
/// text, labelLarge for controls, bodyLarge for reading, bodySmall/labelSmall
/// for metadata, titleSmall for row titles, titleMedium for section titles,
/// titleLarge for dialogs, and headlineSmall for page titles.
///
/// Sizes are logical pixels at 100%. Only the root AppTextScaleRegion applies
/// zoom; styles must never multiply their font size by the user's scale.
abstract final class DiscourseTypography {
  static const double micro = 11;
  static const double metadata = 11.5;
  static const double xs = 12;
  static const double preview = 12.5;
  static const double control = 13;
  static const double compact = 13.5;
  static const double sm = 14;
  static const double base = sm;
  static const double rowTitle = 14.5;
  static const double lg = 17;
  static const double xl = 18;
  static const double xxl = 22;
  static const double xxxl = 28;
  static const double xxxxl = 32;

  static const List<double> fontSizes = [
    micro,
    metadata,
    xs,
    preview,
    control,
    compact,
    base,
    rowTitle,
    lg,
    xl,
    xxl,
    xxxl,
    xxxxl,
  ];

  static const double lineHeightCaption = 1.5;
  static const double lineHeightSmall = 1.5;
  static const double lineHeightPreview = 1.45;
  static const double lineHeightRowTitle = 1.35;
  static const double lineHeightBody = 1.65;
  static const double lineHeightProse = lineHeightBody;
  static const double lineHeightContent = 1.6;
  static const double lineHeightLarge = 1.5;
  static const double lineHeightTitle = 1.4;
  static const double lineHeightHeading = 1.25;
  static const double lineHeightDisplaySmall = 1.25;
  static const double lineHeightDisplayLarge = 1.25;
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
        FontWeight.w700,
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
        rowTitle,
        lineHeightRowTitle,
        FontWeight.w600,
      ),
      bodyLarge: style(platform.bodyLarge, base, lineHeightBody),
      bodyMedium: style(platform.bodyMedium, sm, lineHeightSmall),
      bodySmall: style(platform.bodySmall, xs, lineHeightCaption),
      labelLarge: style(
        platform.labelLarge,
        control,
        lineHeightSmall,
        FontWeight.w500,
      ),
      labelMedium: style(platform.labelMedium, preview, lineHeightSmall),
      labelSmall: style(
        platform.labelSmall,
        metadata,
        lineHeightCaption,
        FontWeight.w500,
      ),
    );
  }

  // Compatibility aliases for consumers of discourse_plugin_sdk.dart.
  @Deprecated('Use sm instead.')
  static const double code = sm;
}
