import 'package:flutter/foundation.dart';

import 'forum_theme.dart';
import 'forum_theme_preferences.dart';
import 'forum_theme_share.dart';

/// One atomic document holds the library and independent forum selections.
/// Legacy forum documents are retained as migration backups.
@immutable
final class ForumThemeLibrary {
  ForumThemeLibrary({
    List<ForumTheme> themes = const [],
    Map<String, ForumThemePreferences> forums = const {},
  }) : themes = List.unmodifiable(themes),
       forums = Map.unmodifiable(forums);

  factory ForumThemeLibrary.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 || json['forums'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid theme library');
    }
    final themes = ForumThemePreferences.fromJson({
      'version': 2,
      'customThemes': json['customThemes'],
    }).customThemes;
    final forums = <String, ForumThemePreferences>{};
    for (final entry in (json['forums'] as Map<String, dynamic>).entries) {
      if (entry.value is! Map<String, dynamic>) continue;
      forums[entry.key] = ForumThemePreferences.fromJson({
        ...entry.value as Map<String, dynamic>,
        'customThemes': [
          for (final theme in themes) {'id': theme.id, ...theme.toJson()},
        ],
      });
    }
    return ForumThemeLibrary(themes: themes, forums: forums);
  }

  final List<ForumTheme> themes;
  final Map<String, ForumThemePreferences> forums;

  ForumThemePreferences forSite(String site) =>
      (forums[site] ?? ForumThemePreferences.defaults).withLibrary(themes);

  /// Imports each legacy identity once, remapping collisions in its selection.
  ForumThemeLibrary migrate(String site, ForumThemePreferences legacy) {
    if (forums.containsKey(site)) return this;
    final library = [...themes];
    var chosen = legacy.customId;
    for (final theme in legacy.customThemes) {
      final existing = library.where((held) => held.id == theme.id).firstOrNull;
      var id = theme.id;
      if (existing != null && !ForumThemeShare.matches(existing, theme)) {
        var suffix = 2;
        while (library.any((held) => held.id == id)) {
          id = '${theme.id}-${suffix++}';
        }
      }
      if (!library.any((held) => held.id == id)) {
        library.add(ForumTheme.fromJson(theme.toJson(), id: id));
      }
      if (legacy.customId == theme.id) chosen = id;
    }
    return ForumThemeLibrary(
      themes: library,
      forums: {
        ...forums,
        site: ForumThemePreferences(
          source: legacy.source,
          presets: legacy.presets,
          customId: chosen,
          customThemes: library,
        ),
      },
    );
  }

  ForumThemeLibrary update(
    String site,
    ForumThemePreferences value, {
    required ForumThemePreferences previous,
  }) => ForumThemeLibrary(
    themes: applyEdits(themes, previous, value),
    forums: {...forums, site: value},
  );

  /// Applies only the caller's edits, retaining themes another load discovered.
  static List<ForumTheme> applyEdits(
    List<ForumTheme> library,
    ForumThemePreferences previous,
    ForumThemePreferences value,
  ) {
    final before = {for (final theme in previous.customThemes) theme.id: theme};
    final after = {for (final theme in value.customThemes) theme.id: theme};
    final removed = before.keys.toSet().difference(after.keys.toSet());
    final changed = {
      for (final entry in after.entries)
        if (before[entry.key] != entry.value) entry.key: entry.value,
    };
    return [
      for (final theme in library)
        if (!removed.contains(theme.id)) changed.remove(theme.id) ?? theme,
      ...changed.values,
    ];
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'customThemes': [
      for (final theme in themes) {'id': theme.id, ...theme.toJson()},
    ],
    'forums': {
      for (final entry in forums.entries)
        entry.key: {...entry.value.toJson()}..remove('customThemes'),
    },
  };
}
