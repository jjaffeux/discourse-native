import 'package:flutter/material.dart';

import '../models/site_appearance.dart';
import '../theme/app_theme.dart';

enum StyleguideTheme {
  current('Current app'),
  light('Light'),
  dark('Dark'),
  forest('Forest site'),
  plum('Plum site');

  const StyleguideTheme(this.label);
  final String label;

  ThemeData resolve(ThemeData current) => switch (this) {
    StyleguideTheme.current => current,
    StyleguideTheme.light => AppTheme.light,
    StyleguideTheme.dark => AppTheme.dark,
    StyleguideTheme.forest => _siteTheme(false),
    StyleguideTheme.plum => _siteTheme(true),
  };
}

// Samples use the same palette adapter as a real site, with no server or store.
ThemeData _siteTheme(bool dark) => AppTheme.fromPalette(
  ResolvedSitePalette.fromJson({
    'brightness': dark ? 'dark' : 'light',
    'primary': dark ? 0xFFF3EAF5 : 0xFF192F25,
    'secondary': dark ? 0xFF211725 : 0xFFF8FCF9,
    'tertiary': dark ? 0xFFDCA6F0 : 0xFF216E4B,
    'headerBackground': dark ? 0xFF170F1B : 0xFFE1EFE6,
    'headerPrimary': dark ? 0xFFF3EAF5 : 0xFF192F25,
    'primaryVeryLow': dark ? 0xFF2B2030 : 0xFFEEF6F0,
    'primaryLow': dark ? 0xFF49354F : 0xFFCBDDD0,
    'primaryMedium': dark ? 0xFFB297B8 : 0xFF627C6D,
    'primaryHigh': dark ? 0xFFD3BBD9 : 0xFF3C5C49,
    'secondaryVeryHigh': dark ? 0xFF302336 : 0xFFFFFFFF,
    'selected': dark ? 0xFF593264 : 0xFFD2EADB,
    'selectedForeground': dark ? 0xFFFFFFFF : 0xFF143F2A,
    'hover': dark ? 0xFF3E2C45 : 0xFFE1EFE6,
    'danger': dark ? 0xFFFF9B9E : 0xFFAD2532,
    'success': dark ? 0xFF8ACCAA : 0xFF216E4B,
    'borderRadius': dark ? 12.0 : 6.0,
  }),
);
