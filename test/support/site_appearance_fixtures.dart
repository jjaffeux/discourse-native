import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:flutter/material.dart';

ResolvedSitePalette sitePalette({
  Color accent = const Color(0xFF3366CC),
  Color background = const Color(0xFFFFFFFF),
  Color foreground = const Color(0xFF202020),
  Brightness brightness = Brightness.light,
}) => ResolvedSitePalette(
  brightness: brightness,
  primary: foreground,
  secondary: background,
  tertiary: accent,
  quaternary: const Color(0xFFEE7722),
  headerBackground: const Color(0xFF102040),
  headerPrimary: const Color(0xFFF8F8F8),
  highlight: const Color(0xFFFFCC33),
  danger: const Color(0xFFCC2233),
  success: const Color(0xFF228844),
  love: const Color(0xFFEE4477),
  selected: const Color(0xFFDDE7FF),
  hover: const Color(0xFFF1F4FA),
  primaryVeryLow: const Color(0xFFF4F5F7),
  primaryLow: const Color(0xFFE2E5E9),
  primaryLowMid: const Color(0xFFB1B7C0),
  primaryMedium: const Color(0xFF7A828D),
  primaryHigh: const Color(0xFF4D545D),
  primaryVeryHigh: const Color(0xFF30353B),
  secondaryVeryHigh: const Color(0xFFF7F7F7),
  metadataColor: const Color(0xFF68717D),
  contentBorderColor: const Color(0xFFD6DAE0),
  tertiaryLow: const Color(0xFFDCE6FF),
  quaternaryLow: const Color(0xFFFFE4D1),
  highlightLow: const Color(0xFFFFF2BF),
  dangerLow: const Color(0xFFFFDDE1),
  selectedForeground: const Color(0xFF202020),
  mentionBackground: const Color(0xFFFFEDB8),
  codeBlockBackground: const Color(0xFF18202A),
  inlineCodeBackground: const Color(0xFFE9EDF2),
  codeKeyword: const Color(0xFF9B59B6),
  codeString: const Color(0xFF258A42),
  codeComment: const Color(0xFF77808C),
  codeNumber: const Color(0xFFB24835),
  codeName: const Color(0xFF2468A2),
  codeMeta: const Color(0xFF8B5A2B),
);

SiteAppearance siteAppearance({
  Color accent = const Color(0xFF3366CC),
  SiteAppearanceMode mode = SiteAppearanceMode.followSystem,
  Color? alternateAccent,
}) => SiteAppearance(
  base: sitePalette(accent: accent),
  alternate: alternateAccent == null
      ? null
      : sitePalette(
          accent: alternateAccent,
          background: const Color(0xFF181A1F),
          foreground: const Color(0xFFE8E9EB),
          brightness: Brightness.dark,
        ),
  mode: mode,
);
