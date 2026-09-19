import 'package:flutter/foundation.dart';

import 'forum_font.dart';
import 'forum_theme.dart';
import 'forum_theme_presets.dart';

@immutable
final class ForumThemePreferences {
  ForumThemePreferences({
    this.selectedId,
    this.font = ForumFont.system,
    List<ForumTheme> customThemes = const [],
  }) : customThemes = List.unmodifiable(customThemes);

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
    final id = json['selectedId'];
    return ForumThemePreferences(
      selectedId: [...forumThemePresets, ...customs].any((t) => t.id == id)
          ? id as String
          : null,
      customThemes: customs,
      font: ForumFont.fromName(json['font']),
    );
  }

  static final defaults = ForumThemePreferences();
  final String? selectedId;
  final ForumFont font;
  final List<ForumTheme> customThemes;

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

  ForumThemePreferences remove(String id) => ForumThemePreferences(
    font: font,
    selectedId: selectedId == id ? null : selectedId,
    customThemes: customThemes.where((theme) => theme.id != id).toList(),
  );

  ForumThemePreferences withFont(ForumFont value) => ForumThemePreferences(
    selectedId: selectedId,
    customThemes: customThemes,
    font: value,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'font': font.name,
    'selectedId': selectedId,
    'customThemes': [
      for (final theme in customThemes) {'id': theme.id, ...theme.toJson()},
    ],
  };

  @override
  bool operator ==(Object other) =>
      other is ForumThemePreferences &&
      other.selectedId == selectedId &&
      other.font == font &&
      listEquals(other.customThemes, customThemes);

  @override
  int get hashCode =>
      Object.hash(selectedId, font, Object.hashAll(customThemes));
}
