/// Discourse's 16px modular type scale, resolved from
/// `font-variables.scss`.
///
/// App-owned text chooses one of these sizes. Relative sizes inside authored
/// content can derive from the surrounding style, and the app-wide text zoom
/// is applied separately at the root `MediaQuery` boundary.
abstract final class DiscourseTypography {
  static const double fontDown3 = 10.5584;
  static const double fontDown2 = 12.1264;
  static const double fontDown1 = 13.9296;
  static const double base = 16;
  static const double fontUp1 = 18.3792;
  static const double fontUp2 = 21.112;
  static const double fontUp3 = 24.2512;
  static const double fontUp4 = 28.0176;
  static const double fontUp5 = 32;
  static const double fontUp6 = 36.736;

  static const List<double> fontSizes = [
    fontDown3,
    fontDown2,
    fontDown1,
    base,
    fontUp1,
    fontUp2,
    fontUp3,
    fontUp4,
    fontUp5,
    fontUp6,
  ];

  /// Heading sizes ordered from `<h1>` through `<h6>`.
  static const List<double> headingSizes = [
    fontUp3,
    fontUp2,
    fontUp1,
    base,
    fontDown1,
    fontDown2,
  ];

  /// Returns the modular size for a heading [level], clamped to 1–6.
  static double headingSize(int level) => headingSizes[level.clamp(1, 6) - 1];

  @Deprecated('Use fontDown1 instead.')
  static const double code = fontDown1;

  static const double codeLineHeight = 17 / 13;

  static const double lineHeightMedium = 1.2;
  static const double lineHeightLarge = 1.4;
  static const double lineHeightCooked = 1.5;
}
