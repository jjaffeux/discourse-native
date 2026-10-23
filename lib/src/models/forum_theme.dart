import 'dart:math' as math;
import 'dart:ui';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import '../foundation/palette_contrast.dart';
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
    // The other half is read back under the theme's id.
    alternate: id == null ? alternate : alternate?.copyWith(id: id),
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

  /// A standalone palette for the requested mode, suitable for editing: the
  /// authored half for it, or else the other half made from this one, the
  /// same hues the other way round.
  ForumTheme forBrightness(Brightness target) {
    final source = alternate?.brightness == target ? alternate! : this;
    final authored = source.brightness == target;
    final base = authored
        ? (ground: source.secondary, text: source.primary)
        : counterpartBase(
            background: source.secondary,
            text: source.primary,
            target: target,
          );
    Color own(Color color) =>
        authored ? color : readableIn(color, base.ground, target);
    return ForumTheme(
      id: id,
      name: source.name,
      background: source.background,
      windowGradient: source.windowGradient,
      darkerSidebars: source.darkerSidebars,
      tint: source.tint,
      brightness: target,
      primary: base.text,
      secondary: base.ground,
      tertiary: own(source.tertiary),
      quaternary: own(source.quaternary),
      danger: own(source.danger),
      success: own(source.success),
      love: own(source.love),
    );
  }

  /// Each derived colour takes as much of the palette as it would by
  /// default, and more or less only where that falls short of WCAG AA for
  /// what is set on it. The palette's own colours are never changed, only
  /// how far they are mixed.
  ResolvedSitePalette resolve(
    Brightness target, {
    ResolvedSitePalette? forumPalette,
  }) {
    if (target != brightness || alternate != null) {
      return forBrightness(target).resolve(target, forumPalette: forumPalette);
    }
    // Tint the shared base before deriving panel and control surfaces. Applying
    // it only to the window canvas leaves opaque Native surfaces unchanged.
    // Each leans toward the accent only as far as the text still reads.
    final effects = this.background;
    Color lean(Color color, double reach) =>
        Color.lerp(color, tertiary, (tint * reach * 100).round() / 100)!;
    final tintedGround = lean(secondary, ForumBackground.maxTint);
    final background =
        contrastRatio(primary, tintedGround) >= textContrast + contrastMargin
        ? tintedGround
        : secondary;
    final tintedText = lean(primary, ForumBackground.maxTextTint);
    final foreground = contrastRatio(tintedText, background) >= textContrast
        ? tintedText
        : primary;
    Color mix(Color color, double amount) =>
        Color.lerp(background, color, amount)!;
    // A surface text is set on, as much of [color] as it takes by default
    // and less where the text would no longer read on it.
    Color under(Color color, double most) {
      var share = most;
      while (share > 0 &&
          contrastRatio(foreground, mix(color, share)) <
              textContrast + contrastMargin) {
        share = math.max(0, share - .005);
      }
      return mix(color, share);
    }

    final panel = mix(foreground, .03);
    final header = mix(foreground, .05);
    final hover = under(foreground, .08);
    final floating = under(foreground, .10);
    final raised = under(foreground, .12);
    final selected = under(tertiary, .20);
    final codeBlock = mix(foreground, .05);
    final inlineCode = under(foreground, .08);
    final surfaces = [
      background,
      panel,
      header,
      hover,
      floating,
      raised,
      selected,
      codeBlock,
      inlineCode,
    ];
    // A level of text: as much of the text as it takes by default, more
    // where that does not reach [need] on every surface.
    Color level(double need, double from) => mix(
      foreground,
      shareFor(foreground, background, surfaces, need + contrastMargin, from),
    );
    // A colour as text: moved toward the text only as far as it takes to
    // read on every surface.
    Color ink(Color color) => mixInto(
      color,
      foreground,
      shareFor(foreground, color, surfaces, textContrast + contrastMargin, 0),
    );
    final metadata = level(textContrast, effects == null ? .70 : .50);
    final accent = ink(tertiary);
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
      'tertiary': accent.toARGB32(),
      'quaternary': quaternary.toARGB32(),
      'accentSubtle': accent.toARGB32(),
      'notificationIndicator': accent.toARGB32(),
      'headerBackground': header.toARGB32(),
      'headerPrimary': foreground.toARGB32(),
      'metadataColor': metadata.toARGB32(),
      'contentBorderColor': mix(foreground, .12).toARGB32(),
      'highlight': quaternary.toARGB32(),
      'danger': danger.toARGB32(),
      'success': success.toARGB32(),
      'love': love.toARGB32(),
      'selected': selected.toARGB32(),
      'selectedForeground': foreground.toARGB32(),
      'hover': hover.toARGB32(),
      'primaryVeryLow': panel.toARGB32(),
      'primaryLow': raised.toARGB32(),
      'primaryLowMid': mix(foreground, .22).toARGB32(),
      'primaryMedium': level(textContrast, .50).toARGB32(),
      'primaryHigh': metadata.toARGB32(),
      'primaryVeryHigh': level(bodyContrast, .90).toARGB32(),
      'secondaryVeryHigh': floating.toARGB32(),
      'tertiaryLow': under(tertiary, .18).toARGB32(),
      'quaternaryLow': under(quaternary, .18).toARGB32(),
      'highlightLow': under(quaternary, .18).toARGB32(),
      'dangerLow': under(danger, .18).toARGB32(),
      'mentionBackground': under(quaternary, .15).toARGB32(),
      'currentUserMentionBackground': under(tertiary, .18).toARGB32(),
      'codeBlockBackground': codeBlock.toARGB32(),
      'inlineCodeBackground': inlineCode.toARGB32(),
      'codeKeyword': accent.toARGB32(),
      'codeString': ink(success).toARGB32(),
      'codeComment': level(textContrast, .62).toARGB32(),
      'codeNumber': ink(quaternary).toARGB32(),
      'codeName': accent.toARGB32(),
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
