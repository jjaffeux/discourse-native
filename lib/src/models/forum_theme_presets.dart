import 'dart:ui';

import 'forum_theme.dart';

// Raw palettes from the September 2026 HTML reference at localhost:5183.
const forumThemePresets = <ForumTheme>[
  ForumTheme(
    alternate: ForumTheme(
      id: 'neutral',
      name: 'Dark',
      brightness: Brightness.dark,
      primary: Color(0xFFDDDDDD),
      secondary: Color(0xFF222222),
      tertiary: Color(0xFF099DD7),
      quaternary: Color(0xFFC14924),
      danger: Color(0xFFE45735),
      success: Color(0xFF1CA551),
      love: Color(0xFFFA6C8D),
    ),
    id: 'neutral',
    name: 'Neutral',
    brightness: Brightness.light,
    primary: Color(0xFF000000),
    secondary: Color(0xFFFFFFFF),
    tertiary: Color(0xFF51839B),
    quaternary: Color(0xFFB85E48),
    danger: Color(0xFFB85E48),
    success: Color(0xFF518751),
    love: Color(0xFFFA6C8D),
  ),
  ForumTheme(
    id: 'grey-amber',
    name: 'Grey Amber',
    brightness: Brightness.dark,
    primary: Color(0xFFD9D9D9),
    secondary: Color(0xFF3D4147),
    tertiary: Color(0xFFFDD459),
    quaternary: Color(0xFFFDD459),
    danger: Color(0xFFE45735),
    success: Color(0xFFFDD459),
    love: Color(0xFFFDD459),
  ),
  ForumTheme(
    id: 'shades-of-blue',
    name: 'Shades of Blue',
    brightness: Brightness.light,
    primary: Color(0xFF203243),
    secondary: Color(0xFFEEF4F7),
    tertiary: Color(0xFF416376),
    quaternary: Color(0xFF5E99B9),
    danger: Color(0xFFBF3C3C),
    success: Color(0xFF70DB82),
    love: Color(0xFFFC94CB),
  ),
  ForumTheme(
    id: 'latte',
    name: 'Latte',
    brightness: Brightness.dark,
    primary: Color(0xFFF2E5D7),
    secondary: Color(0xFF262322),
    tertiary: Color(0xFFF7F2ED),
    quaternary: Color(0xFFD7C9AA),
    danger: Color(0xFFDB9584),
    success: Color(0xFF78BE78),
    love: Color(0xFF8F6201),
  ),
  ForumTheme(
    id: 'summer',
    name: 'Summer',
    brightness: Brightness.light,
    primary: Color(0xFF874342),
    secondary: Color(0xFFFFFFF4),
    tertiary: Color(0xFFFE9896),
    quaternary: Color(0xFFFCC9D0),
    danger: Color(0xFFCFEBDC),
    success: Color(0xFFFCB4B5),
    love: Color(0xFFF3C07F),
  ),
  ForumTheme(
    id: 'dark-rose',
    name: 'Dark Rose',
    brightness: Brightness.dark,
    primary: Color(0xFFCA9CB2),
    secondary: Color(0xFF3A2A37),
    tertiary: Color(0xFFFDD459),
    quaternary: Color(0xFF7E566A),
    danger: Color(0xFF6C3E63),
    success: Color(0xFFD9B2BB),
    love: Color(0xFFD9B2BB),
  ),
  ForumTheme(
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
    name: 'Dracula',
    brightness: Brightness.dark,
    primary: Color(0xFFF2F2F2),
    secondary: Color(0xFF2D303E),
    tertiary: Color(0xFFBD93F9),
    quaternary: Color(0xFF8BE9FD),
    danger: Color(0xFFFF5555),
    success: Color(0xFF50FA7B),
    love: Color(0xFFFF79C6),
  ),
  ForumTheme(
    alternate: ForumTheme(
      id: 'solarized',
      name: 'Solarized',
      brightness: Brightness.dark,
      primary: Color(0xFFFCF6E1),
      secondary: Color(0xFF002B36),
      tertiary: Color(0xFF1A97D5),
      quaternary: Color(0xFFE45735),
      danger: Color(0xFFE45735),
      success: Color(0xFF009900),
      love: Color(0xFFFA6C8D),
    ),
    id: 'solarized',
    name: 'Solarized',
    brightness: Brightness.light,
    primary: Color(0xFF002B36),
    secondary: Color(0xFFFCF6E1),
    tertiary: Color(0xFF0088CC),
    quaternary: Color(0xFFE45735),
    danger: Color(0xFFE45735),
    success: Color(0xFF009900),
    love: Color(0xFFFA6C8D),
  ),
  ForumTheme(
    id: 'clover-dark',
    name: 'Clover',
    brightness: Brightness.dark,
    primary: Color(0xFFFFFFFF),
    secondary: Color(0xFF1A1A1A),
    tertiary: Color(0xFF39845B),
    quaternary: Color(0xFF39845B),
    danger: Color(0xFF39845B),
    success: Color(0xFF39845B),
    love: Color(0xFFFA6C8D),
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
const blankForumTheme = ForumTheme(
  alternate: ForumTheme(
    id: 'blank',
    name: 'Blank',
    brightness: Brightness.dark,
    primary: Color(0xFFE6E6E6),
    secondary: Color(0xFF1E1E1E),
    tertiary: Color(0xFF9A9A9A),
    quaternary: Color(0xFF7A7A7A),
    danger: Color(0xFFB3B3B3),
    success: Color(0xFF8C8C8C),
    love: Color(0xFFA6A6A6),
  ),
  id: 'blank',
  name: 'Blank',
  brightness: Brightness.light,
  primary: Color(0xFF1E1E1E),
  secondary: Color(0xFFFFFFFF),
  tertiary: Color(0xFF6B6B6B),
  quaternary: Color(0xFF8C8C8C),
  danger: Color(0xFF595959),
  success: Color(0xFF737373),
  love: Color(0xFF808080),
);

/// Preserve selections saved before light and dark variants shared one entry.
String? canonicalForumThemeId(String? id) => switch (id) {
  'dark' => 'neutral',
  'wcag-dark' => 'wcag',
  'solarized-light' || 'solarized-dark' => 'solarized',
  _ => id,
};
