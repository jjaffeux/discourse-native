import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'forum_background.dart';
import 'site_appearance.dart';

/// A portable color palette; the forum still owns typography and geometry.
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
  });

  factory ForumTheme.fromJson(Map<String, dynamic> json, {required String id}) {
    final name = json['name'];
    final mode = json['mode'];
    final colors = json['colors'];
    if (json['version'] != 1 ||
        name is! String ||
        name.trim().isEmpty ||
        name.trim().length > 48 ||
        (mode != 'light' && mode != 'dark') ||
        colors is! Map) {
      throw const FormatException('Invalid theme.');
    }
    Color color(String key) {
      final value = colors[key];
      final parsed = value is String ? parseHex(value) : null;
      if (parsed == null) throw FormatException('Invalid $key color.');
      return parsed;
    }

    for (final key in ['windowGradient', 'darkerSidebars']) {
      if (json.containsKey(key) && json[key] is! bool) {
        throw FormatException('Invalid $key option.');
      }
    }

    final rawAlternate = json['alternate'];
    ForumTheme? alternate;
    if (rawAlternate != null) {
      if (rawAlternate is! Map<String, dynamic> ||
          rawAlternate.containsKey('alternate')) {
        throw const FormatException('Invalid alternate palette.');
      }
      alternate = ForumTheme.fromJson(rawAlternate, id: id);
      if (alternate.brightness.name == mode) {
        throw const FormatException('Duplicate palette mode.');
      }
    }
    return ForumTheme(
      background: json['background'] == null
          ? null
          : ForumBackground.fromJson(json['background']),
      windowGradient: json['windowGradient'] == true,
      darkerSidebars: json['darkerSidebars'] == true,
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

  /// A standalone palette for the requested mode, suitable for editing.
  ForumTheme forBrightness(Brightness target) {
    final source = alternate?.brightness == target ? alternate! : this;
    return ForumTheme(
      id: id,
      name: name,
      background: background,
      windowGradient: windowGradient,
      darkerSidebars: darkerSidebars,
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
    final foreground = target == brightness ? primary : secondary;
    final background = target == brightness ? secondary : primary;
    Color mix(Color color, double amount) =>
        Color.lerp(background, color, amount)!;
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
      'metadataColor': mix(foreground, .70).toARGB32(),
      'contentBorderColor': mix(foreground, .12).toARGB32(),
      'highlight': quaternary.toARGB32(),
      'danger': danger.toARGB32(),
      'success': success.toARGB32(),
      'love': love.toARGB32(),
      'selected': mix(tertiary, .20).toARGB32(),
      'selectedForeground': foreground.toARGB32(),
      'hover': mix(foreground, .08).toARGB32(),
      'primaryVeryLow': mix(foreground, .03).toARGB32(),
      'primaryLow': mix(foreground, .12).toARGB32(),
      'primaryLowMid': mix(foreground, .22).toARGB32(),
      'primaryMedium': mix(foreground, .50).toARGB32(),
      'primaryHigh': mix(foreground, .70).toARGB32(),
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
      'codeMeta': mix(foreground, .70).toARGB32(),
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
      other.darkerSidebars == darkerSidebars;

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
  );
}
