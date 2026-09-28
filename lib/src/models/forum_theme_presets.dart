import 'dart:ui';

import 'package:discourse_native/l10n/strings.dart';

import 'forum_theme.dart';

// Raw palettes from the September 2026 HTML reference at localhost:5183.
List<ForumTheme> get forumThemePresets => <ForumTheme>[
  ForumTheme(
    alternate: ForumTheme(
      id: 'neutral',
      name: appL10n.dark,
      brightness: Brightness.dark,
      primary: const Color(0xFFDDDDDD),
      secondary: const Color(0xFF222222),
      tertiary: const Color(0xFF099DD7),
      quaternary: const Color(0xFFC14924),
      danger: const Color(0xFFE45735),
      success: const Color(0xFF1CA551),
      love: const Color(0xFFFA6C8D),
    ),
    id: 'neutral',
    name: appL10n.neutral,
    brightness: Brightness.light,
    primary: const Color(0xFF000000),
    secondary: const Color(0xFFFFFFFF),
    tertiary: const Color(0xFF51839B),
    quaternary: const Color(0xFFB85E48),
    danger: const Color(0xFFB85E48),
    success: const Color(0xFF518751),
    love: const Color(0xFFFA6C8D),
  ),
  ForumTheme(
    id: 'grey-amber',
    name: appL10n.greyAmber,
    brightness: Brightness.dark,
    primary: const Color(0xFFD9D9D9),
    secondary: const Color(0xFF3D4147),
    tertiary: const Color(0xFFFDD459),
    quaternary: const Color(0xFFFDD459),
    danger: const Color(0xFFE45735),
    success: const Color(0xFFFDD459),
    love: const Color(0xFFFDD459),
  ),
  ForumTheme(
    id: 'shades-of-blue',
    name: appL10n.shadesOfBlue,
    brightness: Brightness.light,
    primary: const Color(0xFF203243),
    secondary: const Color(0xFFEEF4F7),
    tertiary: const Color(0xFF416376),
    quaternary: const Color(0xFF5E99B9),
    danger: const Color(0xFFBF3C3C),
    success: const Color(0xFF70DB82),
    love: const Color(0xFFFC94CB),
  ),
  ForumTheme(
    id: 'latte',
    name: appL10n.latte,
    brightness: Brightness.dark,
    primary: const Color(0xFFF2E5D7),
    secondary: const Color(0xFF262322),
    tertiary: const Color(0xFFF7F2ED),
    quaternary: const Color(0xFFD7C9AA),
    danger: const Color(0xFFDB9584),
    success: const Color(0xFF78BE78),
    love: const Color(0xFF8F6201),
  ),
  ForumTheme(
    id: 'summer',
    name: appL10n.summer,
    brightness: Brightness.light,
    primary: const Color(0xFF874342),
    secondary: const Color(0xFFFFFFF4),
    tertiary: const Color(0xFFFE9896),
    quaternary: const Color(0xFFFCC9D0),
    danger: const Color(0xFFCFEBDC),
    success: const Color(0xFFFCB4B5),
    love: const Color(0xFFF3C07F),
  ),
  ForumTheme(
    id: 'dark-rose',
    name: appL10n.darkRose,
    brightness: Brightness.dark,
    primary: const Color(0xFFCA9CB2),
    secondary: const Color(0xFF3A2A37),
    tertiary: const Color(0xFFFDD459),
    quaternary: const Color(0xFF7E566A),
    danger: const Color(0xFF6C3E63),
    success: const Color(0xFFD9B2BB),
    love: const Color(0xFFD9B2BB),
  ),
  const ForumTheme(
    alternate: ForumTheme(
      id: 'wcag',
      name: 'WCAG',
      brightness: Brightness.dark,
      primary: Color(0xFFFFFFFF),
      secondary: Color(0xFF0C0C0C),
      tertiary: Color(0xFF759AFF),
      quaternary: Color(0xFF759AFF),
      danger: Color(0xFFFF697A),
      success: Color(0xFF70B880),
      love: Color(0xFF9D256B),
    ),
    id: 'wcag',
    name: 'WCAG',
    brightness: Brightness.light,
    primary: Color(0xFF000000),
    secondary: Color(0xFFFFFFFF),
    tertiary: Color(0xFF0033CC),
    quaternary: Color(0xFF3369FF),
    danger: Color(0xFFBB1122),
    success: Color(0xFF3D854D),
    love: Color(0xFF9D256B),
  ),
  ForumTheme(
    id: 'dracula',
    name: appL10n.dracula,
    brightness: Brightness.dark,
    primary: const Color(0xFFF2F2F2),
    secondary: const Color(0xFF2D303E),
    tertiary: const Color(0xFFBD93F9),
    quaternary: const Color(0xFF8BE9FD),
    danger: const Color(0xFFFF5555),
    success: const Color(0xFF50FA7B),
    love: const Color(0xFFFF79C6),
  ),
  ForumTheme(
    alternate: ForumTheme(
      id: 'solarized',
      name: appL10n.solarized,
      brightness: Brightness.dark,
      primary: const Color(0xFFFCF6E1),
      secondary: const Color(0xFF002B36),
      tertiary: const Color(0xFF1A97D5),
      quaternary: const Color(0xFFE45735),
      danger: const Color(0xFFE45735),
      success: const Color(0xFF009900),
      love: const Color(0xFFFA6C8D),
    ),
    id: 'solarized',
    name: appL10n.solarized,
    brightness: Brightness.light,
    primary: const Color(0xFF002B36),
    secondary: const Color(0xFFFCF6E1),
    tertiary: const Color(0xFF0088CC),
    quaternary: const Color(0xFFE45735),
    danger: const Color(0xFFE45735),
    success: const Color(0xFF009900),
    love: const Color(0xFFFA6C8D),
  ),
  ForumTheme(
    id: 'clover-dark',
    name: appL10n.clover,
    brightness: Brightness.dark,
    primary: const Color(0xFFFFFFFF),
    secondary: const Color(0xFF1A1A1A),
    tertiary: const Color(0xFF39845B),
    quaternary: const Color(0xFF39845B),
    danger: const Color(0xFF39845B),
    success: const Color(0xFF39845B),
    love: const Color(0xFFFA6C8D),
  ),
];

/// Whether [theme] carries a palette authored for [mode].
bool forumThemeHasMode(ForumTheme theme, Brightness mode) =>
    theme.brightness == mode || theme.alternate?.brightness == mode;

/// The presets authored for [mode], in reference order.
Iterable<ForumTheme> forumThemePresetsFor(Brightness mode) =>
    forumThemePresets.where((theme) => forumThemeHasMode(theme, mode));

/// The preset named [id] when it has a palette authored for [mode].
ForumTheme? forumThemePresetFor(String id, Brightness mode) =>
    forumThemePresetsFor(mode).where((theme) => theme.id == id).firstOrNull;

/// Plain greys to build a theme from scratch, every colour left to choose.
ForumTheme get blankForumTheme => ForumTheme(
  alternate: ForumTheme(
    id: 'blank',
    name: appL10n.blank,
    brightness: Brightness.dark,
    primary: const Color(0xFFE6E6E6),
    secondary: const Color(0xFF1E1E1E),
    tertiary: const Color(0xFF9A9A9A),
    quaternary: const Color(0xFF7A7A7A),
    danger: const Color(0xFFB3B3B3),
    success: const Color(0xFF8C8C8C),
    love: const Color(0xFFA6A6A6),
  ),
  id: 'blank',
  name: appL10n.blank,
  brightness: Brightness.light,
  primary: const Color(0xFF1E1E1E),
  secondary: const Color(0xFFFFFFFF),
  tertiary: const Color(0xFF6B6B6B),
  quaternary: const Color(0xFF8C8C8C),
  danger: const Color(0xFF595959),
  success: const Color(0xFF737373),
  love: const Color(0xFF808080),
);

/// Preserve selections saved before light and dark variants shared one entry.
String? canonicalForumThemeId(String? id) => switch (id) {
  'dark' => 'neutral',
  'wcag-dark' => 'wcag',
  'solarized-light' || 'solarized-dark' => 'solarized',
  _ => id,
};
