import 'dart:ui';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import 'forum_background.dart';
import 'site_appearance.dart';

/// A portable color palette and how far it tints toward its accent; the forum
/// still owns geometry, and the app owns the font and the other window
/// effects.
@immutable
final class ForumTheme {
  const ForumTheme({
    required this.id,
    required this.name,
    required this.brightness,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.quaternary,
    required this.danger,
    required this.success,
    required this.love,
    this.alternate,
    this.background,
    this.windowGradient = false,
    this.darkerSidebars = false,
    this.tint = 0,
  }) : assert(tint >= 0 && tint <= 1);

  factory ForumTheme.fromJson(Map<String, dynamic> json, {required String id}) {
    final name = json['name'];
    final mode = json['mode'];
    final colors = json['colors'];
    if (json['version'] != 1 ||
        name is! String ||
        name.trim().isEmpty ||
        name.trim().characters.length > 48 ||
        (mode != 'light' && mode != 'dark') ||
        colors is! Map) {
      throw FormatException(appL10n.invalidTheme);
    }
    Color color(String key) {
      final value = colors[key];
      final parsed = value is String ? parseHex(value) : null;
      if (parsed == null) {
        throw FormatException(appL10n.invalidColor((key).toString()));
      }
      return parsed;
    }

    for (final key in ['windowGradient', 'darkerSidebars']) {
      if (json.containsKey(key) && json[key] is! bool) {
        throw FormatException(appL10n.invalidOption((key).toString()));
      }
    }

    final tint = json['tint'] ?? 0;
    if (tint is! num || !tint.isFinite || tint < 0 || tint > 1) {
      throw FormatException(appL10n.invalidTint);
    }

    final rawAlternate = json['alternate'];
    ForumTheme? alternate;
    if (rawAlternate != null) {
      if (rawAlternate is! Map<String, dynamic> ||
          rawAlternate.containsKey('alternate')) {
        throw FormatException(appL10n.invalidAlternatePalette);
      }
      alternate = ForumTheme.fromJson(rawAlternate, id: id);
      if (alternate.brightness.name == mode) {
        throw FormatException(appL10n.duplicatePaletteMode);
      }
    }
    return ForumTheme(
      background: json['background'] == null
          ? null
          : ForumBackground.fromJson(json['background']),
      windowGradient: json['windowGradient'] == true,
      darkerSidebars: json['darkerSidebars'] == true,
      tint: tint.toDouble(),
      alternate: alternate,
      id: id,
      name: name.trim(),
      brightness: mode == 'dark' ? Brightness.dark : Brightness.light,
      primary: color('primary'),
      secondary: color('secondary'),
      tertiary: color('tertiary'),
      quaternary: color('quaternary'),
      danger: color('danger'),
      success: color('success'),
      love: color('love'),
    );
  }

  final String id;
  final String name;
  final Brightness brightness;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color quaternary;
  final Color danger;
  final Color success;
  final Color love;
  final ForumTheme? alternate;
  final ForumBackground? background;
  final bool windowGradient;
  final bool darkerSidebars;

  /// How far surfaces and text lean toward the accent, from none to
  /// [ForumBackground.maxTint] and [ForumBackground.maxTextTint].
  final double tint;

  factory ForumTheme.fromPalette(ResolvedSitePalette palette) => ForumTheme(
    id: 'forum',
    name: appL10n.forumDefault,
    brightness: palette.brightness,
    primary: palette.primary,
    secondary: palette.secondary,
    tertiary: palette.tertiary,
    quaternary: palette.quaternary,
    danger: palette.danger,
    success: palette.success,
    love: palette.love,
    background: palette.background,
  );

  ForumTheme copyWith({
    bool? darkerSidebars,
    double? tint,
    String? id,
    String? name,
    Color? primary,
    Color? secondary,
    Color? tertiary,
    Color? quaternary,
    Color? danger,
    Color? success,
    Color? love,
    ForumBackground? background,
  }) => ForumTheme(
    id: id ?? this.id,
    name: name ?? this.name,
    brightness: brightness,
    primary: primary ?? this.primary,
    secondary: secondary ?? this.secondary,
    tertiary: tertiary ?? this.tertiary,
    quaternary: quaternary ?? this.quaternary,
    danger: danger ?? this.danger,
    success: success ?? this.success,
    love: love ?? this.love,
    alternate: alternate,
    background: background ?? this.background,
    windowGradient: windowGradient,
    darkerSidebars: darkerSidebars ?? this.darkerSidebars,
    tint: tint ?? this.tint,
  );

  static String hex(Color color) =>
      '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// The color a `#RRGGBB` string names, or null when [value] is not one.
  /// The inverse of [hex], and the only reader of that form.
  static Color? parseHex(String value) => _hexPattern.hasMatch(value)
      ? Color(0xff000000 | int.parse(value.substring(1), radix: 16))
      : null;

  static final RegExp _hexPattern = RegExp(r'^#[a-fA-F0-9]{6}$');

  Map<String, dynamic> toJson() => {
    if (alternate != null) 'alternate': alternate!.toJson(),
    'version': 1,
    if (background != null) 'background': background!.toJson(),
    'windowGradient': windowGradient,
    'darkerSidebars': darkerSidebars,
    if (tint > 0) 'tint': tint,
    'name': name,
    'mode': brightness.name,
    'colors': {
      'primary': hex(primary),
      'secondary': hex(secondary),
      'tertiary': hex(tertiary),
      'quaternary': hex(quaternary),
      'danger': hex(danger),
      'success': hex(success),
      'love': hex(love),
    },
  };

  /// The palettes and their tints alone. The other window effects belong to
  /// the app and apply to every forum alike; themes saved before that carried
  /// effects of their own.
  ForumTheme get colours => background == null && alternate?.background == null
      ? this
      : ForumTheme.fromJson({
          ...toJson()..remove('background'),
          if (alternate case final alternate?)
            'alternate': alternate.toJson()..remove('background'),
        }, id: id);

  /// A standalone palette for the requested mode, suitable for editing.
  ForumTheme forBrightness(Brightness target) {
    final source = alternate?.brightness == target ? alternate! : this;
    return ForumTheme(
      id: id,
      name: source.name,
      background: source.background,
      windowGradient: source.windowGradient,
      darkerSidebars: source.darkerSidebars,
      tint: source.tint,
      brightness: target,
      primary: source.brightness == target ? source.primary : source.secondary,
      secondary: source.brightness == target
          ? source.secondary
          : source.primary,
      tertiary: source.tertiary,
      quaternary: source.quaternary,
      danger: source.danger,
      success: source.success,
      love: source.love,
    );
  }

  /// Uses authored mode variants when available; otherwise swaps text/background.
  ResolvedSitePalette resolve(
    Brightness target, {
    ResolvedSitePalette? forumPalette,
  }) {
    if (alternate?.brightness == target) {
      return forBrightness(target).resolve(target, forumPalette: forumPalette);
    }
    final originalForeground = target == brightness ? primary : secondary;
    final originalBackground = target == brightness ? secondary : primary;
    // Tint the shared base before deriving panel and control surfaces. Applying
    // it only to the window canvas leaves opaque Native surfaces unchanged.
    final effects = this.background;
    Color lean(Color color, double reach) =>
        Color.lerp(color, tertiary, (tint * reach * 100).round() / 100)!;
    final background = lean(originalBackground, ForumBackground.maxTint);
    final foreground = lean(originalForeground, ForumBackground.maxTextTint);
    Color mix(Color color, double amount) =>
        Color.lerp(background, color, amount)!;
    final selected = mix(tertiary, .20);
    final metadata = mix(foreground, effects == null ? .70 : .50);
    return ResolvedSitePalette.fromJson({
      'brightness': target.name,
      if (this.background != null) 'background': this.background!.toJson(),
      'windowGradient': windowGradient,
      'darkerSidebars': darkerSidebars,
      'borderRadius':
          forumPalette?.borderRadius ?? defaultDiscourseBorderRadius,
      'avatarBorderRadius':
          (forumPalette?.avatarBorderRadius ??
                  defaultDiscourseAvatarBorderRadius)
              .toJson(),
      'primary': foreground.toARGB32(),
      'secondary': background.toARGB32(),
      'tertiary': tertiary.toARGB32(),
      'quaternary': quaternary.toARGB32(),
      'accentSubtle': tertiary.toARGB32(),
      'notificationIndicator': tertiary.toARGB32(),
      'headerBackground': mix(foreground, .05).toARGB32(),
      'headerPrimary': foreground.toARGB32(),
      'metadataColor': metadata.toARGB32(),
      'contentBorderColor': mix(foreground, .12).toARGB32(),
      'highlight': quaternary.toARGB32(),
      'danger': danger.toARGB32(),
      'success': success.toARGB32(),
      'love': love.toARGB32(),
      'selected': selected.toARGB32(),
      'selectedForeground': foreground.toARGB32(),
      'hover': mix(foreground, .08).toARGB32(),
      'primaryVeryLow': mix(foreground, .03).toARGB32(),
      'primaryLow': mix(foreground, .12).toARGB32(),
      'primaryLowMid': mix(foreground, .22).toARGB32(),
      'primaryMedium': mix(foreground, .50).toARGB32(),
      'primaryHigh': metadata.toARGB32(),
      'primaryVeryHigh': mix(foreground, .90).toARGB32(),
      'secondaryVeryHigh': mix(foreground, .10).toARGB32(),
      'tertiaryLow': mix(tertiary, .18).toARGB32(),
      'quaternaryLow': mix(quaternary, .18).toARGB32(),
      'highlightLow': mix(quaternary, .18).toARGB32(),
      'dangerLow': mix(danger, .18).toARGB32(),
      'mentionBackground': mix(quaternary, .15).toARGB32(),
      'currentUserMentionBackground': mix(tertiary, .18).toARGB32(),
      'codeBlockBackground': mix(foreground, .05).toARGB32(),
      'inlineCodeBackground': mix(foreground, .08).toARGB32(),
      'codeKeyword': tertiary.toARGB32(),
      'codeString': success.toARGB32(),
      'codeComment': mix(foreground, .62).toARGB32(),
      'codeNumber': quaternary.toARGB32(),
      'codeName': tertiary.toARGB32(),
      'codeMeta': metadata.toARGB32(),
    });
  }

  @override
  bool operator ==(Object other) =>
      other is ForumTheme &&
      other.id == id &&
      other.name == name &&
      other.brightness == brightness &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.tertiary == tertiary &&
      other.quaternary == quaternary &&
      other.danger == danger &&
      other.success == success &&
      other.love == love &&
      other.alternate == alternate &&
      other.background == background &&
      other.windowGradient == windowGradient &&
      other.darkerSidebars == darkerSidebars &&
      other.tint == tint;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    brightness,
    primary,
    secondary,
    tertiary,
    quaternary,
    danger,
    success,
    love,
    alternate,
    background,
    windowGradient,
    darkerSidebars,
    tint,
  );
}
