import 'package:flutter/foundation.dart';

import 'forum_background.dart';
import 'forum_font.dart';
import 'forum_theme.dart';
import 'forum_theme_presets.dart';
import 'forum_theme_share.dart';

@immutable
final class ForumThemePreferences {
  ForumThemePreferences({
    String? selectedId,
    this.font = ForumFont.system,
    List<ForumTheme> customThemes = const [],
    Map<Brightness, ForumTheme> palettes = const {},
    this.background,
  }) : selectedId = canonicalForumThemeId(selectedId),
       customThemes = List.unmodifiable(customThemes),
       palettes = Map.unmodifiable(palettes);

  factory ForumThemePreferences.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) throw const FormatException('Invalid themes.');
    final customs = <ForumTheme>[];
    final raw = json['customThemes'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map<String, dynamic>) continue;
        final id = entry['id'];
        if (id is! String ||
            !id.startsWith('custom-') ||
            customs.any((theme) => theme.id == id)) {
          continue;
        }
        try {
          customs.add(ForumTheme.fromJson(entry, id: id));
        } on FormatException {
          // One damaged custom theme must not hide the rest of the library.
        }
      }
    }
    final rawId = json['selectedId'];
    final id = canonicalForumThemeId(rawId is String ? rawId : null);
    final palettes = <Brightness, ForumTheme>{};
    if (json['palettes'] case final Map<String, dynamic> rawPalettes) {
      for (final mode in Brightness.values) {
        final raw = rawPalettes[mode.name];
        if (raw is! Map<String, dynamic> || raw['id'] is! String) continue;
        try {
          final theme = ForumTheme.fromJson(raw, id: raw['id'] as String);
          if (theme.brightness == mode) palettes[mode] = theme;
        } on FormatException {
          // Keep the other mode and saved library if one palette is damaged.
        }
      }
    }
    ForumBackground? background;
    try {
      if (json['background'] != null) {
        background = ForumBackground.fromJson(json['background']);
      }
    } on FormatException {
      // Invalid effects do not discard the user's colors.
    }
    return ForumThemePreferences(
      selectedId: [...forumThemePresets, ...customs].any((t) => t.id == id)
          ? id
          : null,
      customThemes: customs,
      font: ForumFont.fromName(json['font']),
      palettes: palettes,
      background: background,
    );
  }

  static final defaults = ForumThemePreferences();
  final String? selectedId;
  final ForumFont font;
  final List<ForumTheme> customThemes;
  final Map<Brightness, ForumTheme> palettes;
  final ForumBackground? background;

  ForumTheme? themeFor(Brightness mode) {
    final theme = palettes[mode] ?? selectedTheme?.forBrightness(mode);
    return background == null ? theme : theme?.copyWith(background: background);
  }

  /// A preset replaces only this mode's colors. Effects belong to the window
  /// and remain unchanged across mode switches.
  ForumThemePreferences withPalette(ForumTheme theme) => ForumThemePreferences(
    selectedId: selectedId,
    font: font,
    customThemes: customThemes,
    palettes: {...palettes, theme.brightness: theme},
    background: background,
  );

  ForumThemePreferences withBackground(ForumBackground value) =>
      ForumThemePreferences(
        selectedId: selectedId,
        font: font,
        customThemes: customThemes,
        palettes: palettes,
        background: value,
      );

  ForumTheme? get selectedTheme => [
    ...forumThemePresets,
    ...customThemes,
  ].where((theme) => theme.id == selectedId).firstOrNull;

  ForumThemePreferences select(String? id) => ForumThemePreferences(
    selectedId: id,
    customThemes: customThemes,
    font: font,
  );

  ForumThemePreferences save(ForumTheme theme) => ForumThemePreferences(
    font: font,
    selectedId: theme.id,
    customThemes: [
      for (final held in customThemes)
        if (held.id != theme.id) held,
      theme,
    ],
  );

  /// Reuses an identical theme already in the library, including the sender's
  /// original saved theme when they use their own shared card.
  ForumThemePreferences importTheme(ForumTheme theme) {
    final existing = customThemes
        .where((held) => ForumThemeShare.matches(held, theme))
        .firstOrNull;
    return existing == null ? save(theme) : select(existing.id);
  }

  ForumThemePreferences remove(String id) => ForumThemePreferences(
    font: font,
    palettes: palettes,
    background: background,
    selectedId: selectedId == id ? null : selectedId,
    customThemes: customThemes.where((theme) => theme.id != id).toList(),
  );

  ForumThemePreferences withFont(ForumFont value) => ForumThemePreferences(
    selectedId: selectedId,
    customThemes: customThemes,
    font: value,
    palettes: palettes,
    background: background,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'font': font.name,
    'selectedId': selectedId,
    if (background != null) 'background': background!.toJson(),
    if (palettes.isNotEmpty)
      'palettes': {
        for (final entry in palettes.entries)
          entry.key.name: {'id': entry.value.id, ...entry.value.toJson()},
      },
    'customThemes': [
      for (final theme in customThemes) {'id': theme.id, ...theme.toJson()},
    ],
  };

  @override
  bool operator ==(Object other) =>
      other is ForumThemePreferences &&
      other.selectedId == selectedId &&
      other.font == font &&
      other.background == background &&
      mapEquals(other.palettes, palettes) &&
      listEquals(other.customThemes, customThemes);

  @override
  int get hashCode => Object.hash(
    selectedId,
    font,
    Object.hashAll(customThemes),
    background,
    palettes[Brightness.light],
    palettes[Brightness.dark],
  );
}
