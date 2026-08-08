import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'json.dart';

/// Which of a site's two palettes its web UI asks a reader to use.
enum SiteAppearanceMode { followSystem, base, alternate }

/// The site palettes available to the native shell.
///
/// [base] is the stylesheet Discourse labels `light-scheme`; it is named for
/// its role rather than its brightness because a theme is allowed to put a
/// dark palette there. [alternate] is the optional `dark-scheme` stylesheet.
@immutable
class SiteAppearance {
  const SiteAppearance({
    this.base,
    this.alternate,
    this.mode = SiteAppearanceMode.followSystem,
  });

  const SiteAppearance.unknown() : this();

  /// Reads a persisted appearance without making a damaged optional palette
  /// damage the site that owns it.
  ///
  /// `light` and `dark` are accepted as aliases for the original field names,
  /// so changing the role terminology does not invalidate an older snapshot.
  factory SiteAppearance.fromJson(Map<String, dynamic> json) => SiteAppearance(
    base: _palette(json['base'] ?? json['light']),
    alternate: _palette(json['alternate'] ?? json['dark']),
    mode: _appearanceMode(json['mode']),
  );

  final ResolvedSitePalette? base;
  final ResolvedSitePalette? alternate;
  final SiteAppearanceMode mode;

  bool get isKnown => base != null || alternate != null;

  Map<String, dynamic> toJson() => {
    'base': base?.toJson(),
    'alternate': alternate?.toJson(),
    'mode': mode.name,
  };

  static ResolvedSitePalette? _palette(Object? value) {
    if (value is! Map) return null;
    try {
      return ResolvedSitePalette.fromJson(Map<String, dynamic>.from(value));
    } catch (_) {
      return null;
    }
  }

  static SiteAppearanceMode _appearanceMode(Object? value) {
    final name = jsonText(value);
    if (name == 'system') return SiteAppearanceMode.followSystem;
    return SiteAppearanceMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => SiteAppearanceMode.followSystem,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SiteAppearance &&
      other.base == base &&
      other.alternate == alternate &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(base, alternate, mode);
}

/// Discourse's color custom properties after their aliases have been resolved.
///
/// These are source colors rather than Material roles. In Discourse naming,
/// `primary` is ordinary text, `secondary` is the page background, and
/// `tertiary` is the interactive accent.
@immutable
class ResolvedSitePalette {
  const ResolvedSitePalette({
    required this.brightness,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.quaternary,
    required this.headerBackground,
    required this.headerPrimary,
    required this.metadataColor,
    required this.contentBorderColor,
    required this.highlight,
    required this.danger,
    required this.success,
    required this.love,
    required this.selected,
    required this.selectedForeground,
    required this.hover,
    required this.primaryVeryLow,
    required this.primaryLow,
    required this.primaryLowMid,
    required this.primaryMedium,
    required this.primaryHigh,
    required this.primaryVeryHigh,
    required this.secondaryVeryHigh,
    required this.tertiaryLow,
    required this.quaternaryLow,
    required this.highlightLow,
    required this.dangerLow,
    required this.mentionBackground,
    required this.codeBlockBackground,
    required this.inlineCodeBackground,
    required this.codeKeyword,
    required this.codeString,
    required this.codeComment,
    required this.codeNumber,
    required this.codeName,
    required this.codeMeta,
  });

  /// Reads the current shape while deriving safe values for fields added after
  /// an older persisted snapshot was written.
  factory ResolvedSitePalette.fromJson(Map<String, dynamic> json) {
    final primary = _requiredColor(json, 'primary');
    final secondary = _requiredColor(json, 'secondary');
    final tertiary = _requiredColor(json, 'tertiary');
    final primaryVeryLow = _color(json['primaryVeryLow']) ?? secondary;
    final primaryLow = _color(json['primaryLow']) ?? primaryVeryLow;
    final primaryLowMid = _color(json['primaryLowMid']) ?? primaryLow;
    final primaryMedium = _color(json['primaryMedium']) ?? primaryLowMid;
    final primaryHigh = _color(json['primaryHigh']) ?? primary;
    final primaryVeryHigh = _color(json['primaryVeryHigh']) ?? primaryHigh;
    final highlight = _color(json['highlight']) ?? tertiary;
    final danger = _color(json['danger']) ?? const Color(0xFFC80001);

    return ResolvedSitePalette(
      brightness: switch (jsonText(json['brightness'])) {
        'dark' => Brightness.dark,
        'light' => Brightness.light,
        _ =>
          secondary.computeLuminance() < 0.5
              ? Brightness.dark
              : Brightness.light,
      },
      primary: primary,
      secondary: secondary,
      tertiary: tertiary,
      quaternary: _color(json['quaternary']) ?? tertiary,
      headerBackground: _color(json['headerBackground']) ?? secondary,
      headerPrimary: _color(json['headerPrimary']) ?? primary,
      metadataColor: _color(json['metadataColor']) ?? primaryHigh,
      contentBorderColor: _color(json['contentBorderColor']) ?? primaryLow,
      highlight: highlight,
      danger: danger,
      success: _color(json['success']) ?? const Color(0xFF009900),
      love: _color(json['love']) ?? const Color(0xFFFA6C8D),
      selected: _color(json['selected']) ?? primaryLow,
      selectedForeground: _color(json['selectedForeground']) ?? primary,
      hover: _color(json['hover']) ?? primaryVeryLow,
      primaryVeryLow: primaryVeryLow,
      primaryLow: primaryLow,
      primaryLowMid: primaryLowMid,
      primaryMedium: primaryMedium,
      primaryHigh: primaryHigh,
      primaryVeryHigh: primaryVeryHigh,
      secondaryVeryHigh: _color(json['secondaryVeryHigh']) ?? secondary,
      tertiaryLow: _color(json['tertiaryLow']) ?? tertiary,
      quaternaryLow: _color(json['quaternaryLow']) ?? tertiary,
      highlightLow: _color(json['highlightLow']) ?? highlight,
      dangerLow: _color(json['dangerLow']) ?? danger,
      mentionBackground: _color(json['mentionBackground']) ?? primaryLow,
      codeBlockBackground:
          _color(json['codeBlockBackground']) ?? primaryVeryLow,
      inlineCodeBackground:
          _color(json['inlineCodeBackground']) ?? primaryVeryLow,
      codeKeyword: _color(json['codeKeyword']) ?? tertiary,
      codeString: _color(json['codeString']) ?? primaryHigh,
      codeComment: _color(json['codeComment']) ?? primaryMedium,
      codeNumber: _color(json['codeNumber']) ?? tertiary,
      codeName: _color(json['codeName']) ?? tertiary,
      codeMeta: _color(json['codeMeta']) ?? primaryHigh,
    );
  }

  final Brightness brightness;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color quaternary;
  final Color headerBackground;
  final Color headerPrimary;
  final Color metadataColor;
  final Color contentBorderColor;
  final Color highlight;
  final Color danger;
  final Color success;
  final Color love;
  final Color selected;
  final Color selectedForeground;
  final Color hover;
  final Color primaryVeryLow;
  final Color primaryLow;
  final Color primaryLowMid;
  final Color primaryMedium;
  final Color primaryHigh;
  final Color primaryVeryHigh;
  final Color secondaryVeryHigh;
  final Color tertiaryLow;
  final Color quaternaryLow;
  final Color highlightLow;
  final Color dangerLow;
  final Color mentionBackground;
  final Color codeBlockBackground;
  final Color inlineCodeBackground;
  final Color codeKeyword;
  final Color codeString;
  final Color codeComment;
  final Color codeNumber;
  final Color codeName;
  final Color codeMeta;

  Map<String, dynamic> toJson() => {
    'brightness': brightness.name,
    'primary': primary.toARGB32(),
    'secondary': secondary.toARGB32(),
    'tertiary': tertiary.toARGB32(),
    'quaternary': quaternary.toARGB32(),
    'headerBackground': headerBackground.toARGB32(),
    'headerPrimary': headerPrimary.toARGB32(),
    'metadataColor': metadataColor.toARGB32(),
    'contentBorderColor': contentBorderColor.toARGB32(),
    'highlight': highlight.toARGB32(),
    'danger': danger.toARGB32(),
    'success': success.toARGB32(),
    'love': love.toARGB32(),
    'selected': selected.toARGB32(),
    'selectedForeground': selectedForeground.toARGB32(),
    'hover': hover.toARGB32(),
    'primaryVeryLow': primaryVeryLow.toARGB32(),
    'primaryLow': primaryLow.toARGB32(),
    'primaryLowMid': primaryLowMid.toARGB32(),
    'primaryMedium': primaryMedium.toARGB32(),
    'primaryHigh': primaryHigh.toARGB32(),
    'primaryVeryHigh': primaryVeryHigh.toARGB32(),
    'secondaryVeryHigh': secondaryVeryHigh.toARGB32(),
    'tertiaryLow': tertiaryLow.toARGB32(),
    'quaternaryLow': quaternaryLow.toARGB32(),
    'highlightLow': highlightLow.toARGB32(),
    'dangerLow': dangerLow.toARGB32(),
    'mentionBackground': mentionBackground.toARGB32(),
    'codeBlockBackground': codeBlockBackground.toARGB32(),
    'inlineCodeBackground': inlineCodeBackground.toARGB32(),
    'codeKeyword': codeKeyword.toARGB32(),
    'codeString': codeString.toARGB32(),
    'codeComment': codeComment.toARGB32(),
    'codeNumber': codeNumber.toARGB32(),
    'codeName': codeName.toARGB32(),
    'codeMeta': codeMeta.toARGB32(),
  };

  @override
  bool operator ==(Object other) =>
      other is ResolvedSitePalette &&
      other.brightness == brightness &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.tertiary == tertiary &&
      other.quaternary == quaternary &&
      other.headerBackground == headerBackground &&
      other.headerPrimary == headerPrimary &&
      other.metadataColor == metadataColor &&
      other.contentBorderColor == contentBorderColor &&
      other.highlight == highlight &&
      other.danger == danger &&
      other.success == success &&
      other.love == love &&
      other.selected == selected &&
      other.selectedForeground == selectedForeground &&
      other.hover == hover &&
      other.primaryVeryLow == primaryVeryLow &&
      other.primaryLow == primaryLow &&
      other.primaryLowMid == primaryLowMid &&
      other.primaryMedium == primaryMedium &&
      other.primaryHigh == primaryHigh &&
      other.primaryVeryHigh == primaryVeryHigh &&
      other.secondaryVeryHigh == secondaryVeryHigh &&
      other.tertiaryLow == tertiaryLow &&
      other.quaternaryLow == quaternaryLow &&
      other.highlightLow == highlightLow &&
      other.dangerLow == dangerLow &&
      other.mentionBackground == mentionBackground &&
      other.codeBlockBackground == codeBlockBackground &&
      other.inlineCodeBackground == inlineCodeBackground &&
      other.codeKeyword == codeKeyword &&
      other.codeString == codeString &&
      other.codeComment == codeComment &&
      other.codeNumber == codeNumber &&
      other.codeName == codeName &&
      other.codeMeta == codeMeta;

  @override
  int get hashCode => Object.hashAll([
    brightness,
    primary,
    secondary,
    tertiary,
    quaternary,
    headerBackground,
    headerPrimary,
    metadataColor,
    contentBorderColor,
    highlight,
    danger,
    success,
    love,
    selected,
    selectedForeground,
    hover,
    primaryVeryLow,
    primaryLow,
    primaryLowMid,
    primaryMedium,
    primaryHigh,
    primaryVeryHigh,
    secondaryVeryHigh,
    tertiaryLow,
    quaternaryLow,
    highlightLow,
    dangerLow,
    mentionBackground,
    codeBlockBackground,
    inlineCodeBackground,
    codeKeyword,
    codeString,
    codeComment,
    codeNumber,
    codeName,
    codeMeta,
  ]);
}

Color _requiredColor(Map<String, dynamic> json, String name) =>
    _color(json[name]) ??
    (throw FormatException('Missing palette color $name'));

Color? _color(Object? value) {
  final integer = jsonIntOrNull(value);
  if (integer != null) return Color(integer & 0xFFFFFFFF);
  if (value is! String) return null;
  final text = value.trim().replaceFirst('#', '');
  final parsed = int.tryParse(text, radix: 16);
  if (parsed == null) return null;
  return switch (text.length) {
    6 => Color(0xFF000000 | parsed),
    8 => Color(parsed),
    _ => null,
  };
}
