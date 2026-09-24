import 'package:flutter/foundation.dart';

import 'forum_background.dart';
import 'forum_font.dart';
import 'forum_theme.dart';
import 'forum_theme_presets.dart';
import 'forum_theme_share.dart';

/// Where a forum's colours come from. The forum's own palette and the built-in
/// presets apply as they are; only the user's own themes are ever edited.
enum ForumThemeSource { forum, preset, custom }

@immutable
final class ForumThemePreferences {
  ForumThemePreferences({
    this.source = ForumThemeSource.forum,
    Map<Brightness, String> presets = const {},
    this.customId,
    this.font = ForumFont.system,
    List<ForumTheme> customThemes = const [],
  }) : presets = Map.unmodifiable(presets),
       customThemes = List.unmodifiable(customThemes);

  /// The preset [id] in every mode it has a palette for.
  factory ForumThemePreferences.preset(String id) => ForumThemePreferences(
    source: ForumThemeSource.preset,
    presets: {
      for (final mode in Brightness.values)
        if (forumThemePresetFor(id, mode) != null) mode: id,
    },
  );

  /// Reads the current document, and migrates version 1 documents whose loose
  /// palettes and shared background could hold any edited state.
  factory ForumThemePreferences.fromJson(Map<String, dynamic> json) {
    final customs = _library(json['customThemes']);
    final font = ForumFont.fromName(json['font']);
    return switch (json['version']) {
      2 => _read(json, customs, font),
      1 => _migrate(json, customs, font),
      _ => throw const FormatException('Invalid themes.'),
    };
  }

  static final defaults = ForumThemePreferences();

  final ForumThemeSource source;

  /// The preset chosen for each mode. A mode without one keeps the forum's
  /// own colours, so choosing a preset for dark never repaints light.
  final Map<Brightness, String> presets;

  /// The saved theme chosen last, kept while another source is in use.
  final String? customId;

  /// Applies whatever the colours' source: a font is not part of a theme.
  final ForumFont font;
  final List<ForumTheme> customThemes;

  ForumTheme? get customTheme =>
      customThemes.where((theme) => theme.id == customId).firstOrNull;

  ForumTheme? presetFor(Brightness mode) => switch (presets[mode]) {
    final id? => forumThemePresetFor(id, mode),
    null => null,
  };

  /// The palette shown in [mode], or null where the forum's own applies.
  ForumTheme? themeFor(Brightness mode) {
    switch (source) {
      case ForumThemeSource.forum:
        return null;
      case ForumThemeSource.preset:
        final preset = presetFor(mode);
        return preset
            ?.forBrightness(mode)
            .copyWith(
              background:
                  preset.background ?? const ForumBackground.appearance(),
            );
      case ForumThemeSource.custom:
        return customTheme?.forBrightness(mode);
    }
  }

  ForumThemePreferences withSource(ForumThemeSource value) =>
      ForumThemePreferences(
        source: value,
        presets: presets,
        customId: customId,
        font: font,
        customThemes: customThemes,
      );

  ForumThemePreferences withPreset(Brightness mode, String id) =>
      ForumThemePreferences(
        source: ForumThemeSource.preset,
        presets: {...presets, mode: id},
        customId: customId,
        font: font,
        customThemes: customThemes,
      );

  /// Applies a theme from the library; an id the library lacks changes nothing.
  ForumThemePreferences useTheme(String id) =>
      customThemes.any((theme) => theme.id == id)
      ? ForumThemePreferences(
          source: ForumThemeSource.custom,
          presets: presets,
          customId: id,
          font: font,
          customThemes: customThemes,
        )
      : this;

  /// Stores [theme] in place of the one with its id, or after the others, and
  /// applies it.
  ForumThemePreferences save(ForumTheme theme) => ForumThemePreferences(
    source: ForumThemeSource.custom,
    presets: presets,
    customId: theme.id,
    font: font,
    customThemes: customThemes.any((held) => held.id == theme.id)
        ? [for (final held in customThemes) held.id == theme.id ? theme : held]
        : [...customThemes, theme],
  );

  /// Adds [theme] to the library without applying it.
  ForumThemePreferences add(ForumTheme theme) => ForumThemePreferences(
    source: source,
    presets: presets,
    customId: customId,
    font: font,
    customThemes: [...customThemes, theme],
  );

  /// Removing the theme in use falls back to the forum's own colours.
  ForumThemePreferences remove(String id) {
    final chosen = customId == id;
    return ForumThemePreferences(
      source: chosen && source == ForumThemeSource.custom
          ? ForumThemeSource.forum
          : source,
      presets: presets,
      customId: chosen ? null : customId,
      font: font,
      customThemes: customThemes.where((theme) => theme.id != id).toList(),
    );
  }

  ForumThemePreferences withFont(ForumFont value) => ForumThemePreferences(
    source: source,
    presets: presets,
    customId: customId,
    font: value,
    customThemes: customThemes,
  );

  /// Reuses an identical theme already in the library, including the sender's
  /// original saved theme when they use their own shared card.
  ForumThemePreferences importTheme(ForumTheme theme) {
    final existing = customThemes
        .where((held) => ForumThemeShare.matches(held, theme))
        .firstOrNull;
    return existing == null ? save(theme) : useTheme(existing.id);
  }

  Map<String, dynamic> toJson() => {
    'version': 2,
    'source': source.name,
    if (presets.isNotEmpty)
      'presets': {
        for (final entry in presets.entries) entry.key.name: entry.value,
      },
    if (customId != null) 'custom': customId,
    'font': font.name,
    'customThemes': [
      for (final theme in customThemes) {'id': theme.id, ...theme.toJson()},
    ],
  };

  static List<ForumTheme> _library(Object? raw) {
    final customs = <ForumTheme>[];
    if (raw is! List) return customs;
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
    return customs;
  }

  static ForumThemePreferences _read(
    Map<String, dynamic> json,
    List<ForumTheme> customs,
    ForumFont font,
  ) {
    final presets = <Brightness, String>{};
    if (json['presets'] case final Map<String, dynamic> raw) {
      for (final mode in Brightness.values) {
        final id = canonicalForumThemeId(switch (raw[mode.name]) {
          final String id => id,
          _ => null,
        });
        if (id != null && forumThemePresetFor(id, mode) != null) {
          presets[mode] = id;
        }
      }
    }
    final chosen = json['custom'];
    final customId = chosen is String && customs.any((t) => t.id == chosen)
        ? chosen
        : null;
    final source =
        ForumThemeSource.values
            .where((value) => value.name == json['source'])
            .firstOrNull ??
        ForumThemeSource.forum;
    return ForumThemePreferences(
      // A theme deleted elsewhere leaves nothing to show but the forum's own.
      source: source == ForumThemeSource.custom && customId == null
          ? ForumThemeSource.forum
          : source,
      presets: presets,
      customId: customId,
      font: font,
      customThemes: customs,
    );
  }

  /// Version 1 applied a selected theme, a palette per mode and one shared
  /// background, all editable in place. Untouched forum colours, presets and
  /// saved themes map onto their sources; anything else was the user's own
  /// work and becomes a saved theme, so nothing they see changes.
  static ForumThemePreferences _migrate(
    Map<String, dynamic> json,
    List<ForumTheme> customs,
    ForumFont font,
  ) {
    final rawId = json['selectedId'];
    final selectedId = canonicalForumThemeId(rawId is String ? rawId : null);
    final selected = [
      ...forumThemePresets,
      ...customs,
    ].where((theme) => theme.id == selectedId).firstOrNull;
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
    final enabled = switch (json['useCustomTheme']) {
      final bool value => value,
      _ =>
        selected != null ||
            palettes.isNotEmpty ||
            background != null ||
            font != ForumFont.system,
    };
    ForumThemePreferences keep({
      ForumThemeSource source = ForumThemeSource.forum,
      Map<Brightness, String> presets = const {},
      String? customId,
      List<ForumTheme>? library,
    }) => ForumThemePreferences(
      source: source,
      presets: presets,
      customId: customId,
      font: font,
      customThemes: library ?? customs,
    );
    if (!enabled) return keep();

    ForumTheme? shown(Brightness mode) =>
        palettes[mode] ?? selected?.forBrightness(mode);
    final presets = <Brightness, String>{};
    ForumTheme? owned;
    var edited = false;
    for (final mode in Brightness.values) {
      final palette = shown(mode);
      if (palette == null) continue;
      // Changing one mode seeded the other with a copy of the forum's colours.
      // Colour edits to that copy cannot be told apart from the forum palette,
      // which is not stored with them; its surface options can.
      if (palette.id == 'forum') {
        if (palette.darkerSidebars || palette.windowGradient) edited = true;
        continue;
      }
      final preset = forumThemePresets
          .where((theme) => theme.id == palette.id)
          .firstOrNull;
      if (preset != null && _sameColors(preset.forBrightness(mode), palette)) {
        // A preset without a palette for this mode used to be inverted into
        // it. That mode keeps the forum's colours instead.
        if (forumThemePresetFor(preset.id, mode) != null) {
          presets[mode] = preset.id;
        }
        continue;
      }
      final theme = customs.where((held) => held.id == palette.id).firstOrNull;
      if (theme != null &&
          (owned == null || owned.id == theme.id) &&
          _sameColors(theme.forBrightness(mode), palette)) {
        owned = theme;
        continue;
      }
      edited = true;
    }
    final plain =
        background == null || background == const ForumBackground.appearance();
    if (!edited && owned != null && presets.isEmpty) {
      final authored = {
        for (final mode in Brightness.values)
          owned.forBrightness(mode).background,
      };
      if (plain || authored.contains(background)) {
        return keep(source: ForumThemeSource.custom, customId: owned.id);
      }
    }
    if (!edited && owned == null && plain) {
      return presets.isEmpty
          ? keep()
          : keep(source: ForumThemeSource.preset, presets: presets);
    }
    final light =
        shown(Brightness.light) ??
        shown(Brightness.dark)?.forBrightness(Brightness.light);
    if (light == null) return keep();
    final dark = shown(Brightness.dark) ?? light.forBrightness(Brightness.dark);
    var copy = 1;
    String name() => copy == 1 ? 'My theme' : 'My theme $copy';
    String id() => copy == 1 ? 'custom-migrated' : 'custom-migrated-$copy';
    while (customs.any((theme) => theme.name == name() || theme.id == id())) {
      copy++;
    }
    Map<String, dynamic> part(ForumTheme palette, Brightness mode) {
      final surface = background ?? palette.background;
      return {
        ...palette.forBrightness(mode).toJson(),
        'name': name(),
        if (surface != null) 'background': surface.toJson(),
      };
    }

    final theme = ForumTheme.fromJson({
      ...part(light, Brightness.light),
      'alternate': part(dark, Brightness.dark),
    }, id: id());
    return keep(
      source: ForumThemeSource.custom,
      customId: theme.id,
      library: [...customs, theme],
    );
  }

  static bool _sameColors(ForumTheme a, ForumTheme b) =>
      a.primary == b.primary &&
      a.secondary == b.secondary &&
      a.tertiary == b.tertiary &&
      a.quaternary == b.quaternary &&
      a.danger == b.danger &&
      a.success == b.success &&
      a.love == b.love &&
      a.darkerSidebars == b.darkerSidebars &&
      a.windowGradient == b.windowGradient;

  @override
  bool operator ==(Object other) =>
      other is ForumThemePreferences &&
      other.source == source &&
      mapEquals(other.presets, presets) &&
      other.customId == customId &&
      other.font == font &&
      listEquals(other.customThemes, customThemes);

  @override
  int get hashCode => Object.hash(
    source,
    presets[Brightness.light],
    presets[Brightness.dark],
    customId,
    font,
    Object.hashAll(customThemes),
  );
}
