import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/shell/forum_settings_controller.dart';

Future<void> main() async {
  final sites = List.generate(12, (i) => 'https://forum-$i.example');
  final palette = {
    'version': 1,
    'name': 'Personal palette',
    'mode': 'light',
    'colors': {
      for (final name in [
        'primary',
        'secondary',
        'tertiary',
        'quaternary',
        'danger',
        'success',
        'love',
      ])
        name: '#123456',
    },
  };
  final document = jsonEncode({
    'version': 1,
    'customThemes': [
      for (var i = 0; i < 120; i++)
        {
          ...palette,
          'id': 'custom-$i',
          'name': 'Saved palette $i',
          'alternate': {...palette, 'mode': 'dark'},
        },
    ],
    'forums': {
      for (var i = 0; i < sites.length; i++)
        sites[i]: {'version': 2, 'source': 'custom', 'custom': 'custom-$i'},
    },
  });
  final times = <int>[];
  final saveTimes = <int>[];
  for (var attempt = 0; attempt < 10; attempt++) {
    final persistence = _SavedPreferences(document);
    final settings = ForumSettingsController(
      store: ForumSettingsStore(persistence: persistence),
    );
    final watch = Stopwatch()..start();
    await settings.restoreSavedForums(sites, initialMode: AppThemeMode.system);
    watch.stop();
    for (var i = 0; i < sites.length; i++) {
      final themes = settings.themesFor(sites[i]);
      if (themes.customTheme?.name != 'Saved palette $i' ||
          themes.customTheme?.alternate == null ||
          themes.customThemes.length != 120) {
        throw StateError('A saved forum palette did not restore');
      }
    }
    final preferences = settings.themesFor(sites.first).useTheme('custom-99');
    final save = Stopwatch()..start();
    await settings.setThemes(sites.first, preferences);
    save.stop();
    final saved = jsonDecode(persistence.document) as Map<String, dynamic>;
    if (saved['forums'] case final Map<String, dynamic> forums
        when (forums[sites.first] as Map)['custom'] == 'custom-99') {
      if (attempt >= 3) saveTimes.add(save.elapsedMicroseconds);
    } else {
      throw StateError('The theme selection was not persisted');
    }
    settings.dispose();
    if (attempt >= 3) times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  saveTimes.sort();
  stdout.writeln(
    jsonEncode({
      'restore_saved_forum_themes': times[3],
      'save_forum_theme_selection': saveTimes[3],
    }),
  );
  exit(0);
}

final class _SavedPreferences implements ScalarPreferencePersistence<String> {
  _SavedPreferences(this.document);

  String document;

  @override
  Future<String?> read(String key) async =>
      key == ForumSettingsStore.themeLibraryKey ? document : null;

  @override
  Future<bool> write(String key, String value) async {
    if (key == ForumSettingsStore.themeLibraryKey) document = value;
    return true;
  }
}
