import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'json.dart';

const double defaultDiscourseBorderRadius = 4;
const AvatarBorderRadius defaultDiscourseAvatarBorderRadius =
    AvatarBorderRadius.percent(50);

@immutable
class AvatarBorderRadius {
  const AvatarBorderRadius.pixels(this.value) : isPercent = false;

  const AvatarBorderRadius.percent(this.value) : isPercent = true;

  final double value;
  final bool isPercent;

  double resolve(double diameter) {
    if (!diameter.isFinite || diameter <= 0 || !value.isFinite || value < 0) {
      return 0;
    }
    final radius = isPercent ? diameter * value / 100 : value;
    return radius.clamp(0, diameter / 2).toDouble();
  }

  Map<String, dynamic> toJson() => {
    'value': value,
    'unit': isPercent ? 'percent' : 'pixels',
  };

  @override
  bool operator ==(Object other) =>
      other is AvatarBorderRadius &&
      other.value == value &&
      other.isPercent == isPercent;

  @override
  int get hashCode => Object.hash(value, isPercent);
}

enum SiteAppearanceMode { followSystem, base, alternate }

@immutable
class SiteAppearance {
  const SiteAppearance({
    this.base,
    this.alternate,
    this.mode = SiteAppearanceMode.followSystem,
  });

  const SiteAppearance.unknown() : this();

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

@immutable
class ResolvedSitePalette {
  const ResolvedSitePalette({
    this.borderRadius = defaultDiscourseBorderRadius,
    this.avatarBorderRadius = defaultDiscourseAvatarBorderRadius,
    required this.brightness,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.accentSubtle,
    this.notificationIndicator,
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
    this._currentUserMentionBackground,
    required this.codeBlockBackground,
    required this.inlineCodeBackground,
    required this.codeKeyword,
    required this.codeString,
    required this.codeComment,
    required this.codeNumber,
    required this.codeName,
    required this.codeMeta,
  });

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
      borderRadius:
          _nonNegativeDouble(json['borderRadius']) ??
          defaultDiscourseBorderRadius,
      avatarBorderRadius:
          _avatarBorderRadius(json['avatarBorderRadius']) ??
          defaultDiscourseAvatarBorderRadius,
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
      accentSubtle: _color(json['accentSubtle']) ?? tertiary,
      notificationIndicator: _color(json['notificationIndicator']),
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
      currentUserMentionBackground: _color(
        json['currentUserMentionBackground'],
      ),
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

  final double borderRadius;
  final AvatarBorderRadius avatarBorderRadius;
  final Brightness brightness;
  final Color primary;
  final Color secondary;
  final Color tertiary;

  final Color accentSubtle;

  /// Core's `--tertiary-med-or-tertiary`; absent in older saved palettes.
  final Color? notificationIndicator;

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
  final Color? _currentUserMentionBackground;

  // Palettes retained across hot reload can predate the own-mention color.
  Color get currentUserMentionBackground =>
      _currentUserMentionBackground ?? tertiaryLow;

  final Color codeBlockBackground;
  final Color inlineCodeBackground;
  final Color codeKeyword;
  final Color codeString;
  final Color codeComment;
  final Color codeNumber;
  final Color codeName;
  final Color codeMeta;

  Map<String, dynamic> toJson() => {
    'borderRadius': borderRadius,
    'avatarBorderRadius': avatarBorderRadius.toJson(),
    'brightness': brightness.name,
    'primary': primary.toARGB32(),
    'secondary': secondary.toARGB32(),
    'tertiary': tertiary.toARGB32(),
    'accentSubtle': accentSubtle.toARGB32(),
    'notificationIndicator': ?notificationIndicator?.toARGB32(),
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
    'currentUserMentionBackground': currentUserMentionBackground.toARGB32(),
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
      other.borderRadius == borderRadius &&
      other.avatarBorderRadius == avatarBorderRadius &&
      other.brightness == brightness &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.tertiary == tertiary &&
      other.accentSubtle == accentSubtle &&
      other.notificationIndicator == notificationIndicator &&
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
      other.currentUserMentionBackground == currentUserMentionBackground &&
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
    borderRadius,
    avatarBorderRadius,
    brightness,
    primary,
    secondary,
    tertiary,
    accentSubtle,
    notificationIndicator,
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
    currentUserMentionBackground,
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

AvatarBorderRadius? _avatarBorderRadius(Object? value) {
  if (value is! Map) return null;
  final amount = _nonNegativeDouble(value['value']);
  if (amount == null) return null;
  return switch (jsonText(value['unit'])) {
    'percent' => AvatarBorderRadius.percent(amount),
    'pixels' => AvatarBorderRadius.pixels(amount),
    _ => null,
  };
}

double? _nonNegativeDouble(Object? value) {
  if (value is! num) return null;
  final result = value.toDouble();
  return result.isFinite && result >= 0 ? result : null;
}

Color _requiredColor(Map<String, dynamic> json, String name) =>
    _color(json[name]) ??
    (throw FormatException('Missing palette color $name'));

// A persisted Color is 32 bits. Ten decimal digits hold every unsigned value,
// and one extra code unit permits a sign. Hex colors are shorter even with '#'.
const int _maximumPersistedColorTextCodeUnits = 11;

Color? _color(Object? value) {
  String? text;
  if (value is String) {
    if (value.length > _maximumPersistedColorTextCodeUnits) return null;
    text = value.trim().replaceFirst('#', '');
  }
  // Hex must win over decimal for the six/eight-digit shapes: '222222' is the
  // persisted hex color 0xFF222222, never the decimal integer 222222, and no
  // color with visible alpha writes exactly six or eight decimal digits.
  if (text != null && (text.length == 6 || text.length == 8)) {
    final parsed = int.tryParse(text, radix: 16);
    if (parsed != null && parsed >= 0) {
      return text.length == 6 ? Color(0xFF000000 | parsed) : Color(parsed);
    }
  }
  final integer = jsonIntOrNull(value);
  return integer == null ? null : Color(integer & 0xFFFFFFFF);
}
