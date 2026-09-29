import 'dart:convert';
import 'dart:ui';

import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/data/site_preference_keys.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/shell/forum_settings_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

const siteA = 'https://example.com/a';
const siteB = 'https://example.com/b';

void main() {
  test('version 1 keeps the saved reading font and defaults interface', () {
    final migrated = SharedAppearance.fromJson({
      'version': 1,
      'font': 'lato',
      'effects': const ForumBackground.appearance().toJson(),
    });
    expect(migrated.readingFont, ForumFont.lato);
    expect(migrated.interfaceFont, ForumFont.system);
    final chosen = migrated.copyWith(interfaceFont: ForumFont.openSans);
    expect(SharedAppearance.fromJson(chosen.toJson()), chosen);
    expect(chosen.readingFont, ForumFont.lato);
    expect(chosen.copyWith(font: ForumFont.system).readingFamily, 'Open Sans');
  });

  test(
    'interface and reading fonts apply to their own roles in both modes',
    () {
      for (final mode in Brightness.values) {
        for (final theme in [
          AppTheme.forBrightness(
            mode,
            fontFamily: 'Open Sans',
            readingFontFamily: 'Lato',
          ),
          AppTheme.fromPalette(
            forumThemePresets.first.resolve(mode),
            fontFamily: 'Open Sans',
            readingFontFamily: 'Lato',
          ),
        ]) {
          expect(theme.textTheme.bodyMedium!.fontFamily, 'Open Sans');
          expect(theme.textTheme.labelLarge!.fontFamily, 'Open Sans');
          expect(theme.textTheme.bodyLarge!.fontFamily, 'Lato');
          expect(theme.textTheme.bodyLarge!.fontFamilyFallback, [
            'packages/discourse_native/Lato',
          ]);
        }
      }
    },
  );

  test(
    'legacy libraries migrate once with collisions and per-mode effects intact',
    () async {
      final persistence = _Persistence();
      final first = _custom('First', .2);
      final second = _custom('Second', .25);
      persistence.values[ForumSettingsStore.themesKey(siteA)] = jsonEncode(
        ForumThemePreferences().save(first).toJson(),
      );
      persistence.values[ForumSettingsStore.themesKey(siteB)] = jsonEncode(
        ForumThemePreferences().save(second).toJson(),
      );
      final store = ForumSettingsStore(persistence: persistence);
      final settings = ForumSettingsController(store: store);
      addTearDown(settings.dispose);
      await settings.loadShared([siteA, siteB]);
      final a = settings.themesFor(siteA);
      final b = settings.themesFor(siteB);
      expect(a.customThemes.map((theme) => theme.name), ['First', 'Second']);
      expect(b.customThemes, a.customThemes);
      expect(a.customId, isNot(b.customId));
      expect(a.customTheme!.name, 'First');
      expect(b.customTheme!.name, 'Second');
      for (final mode in Brightness.values) {
        expect(
          a.themeFor(mode)!.background,
          first.forBrightness(mode).background,
        );
        expect(
          b.themeFor(mode)!.background,
          second.forBrightness(mode).background,
        );
      }
      // A third forum can use either without changing the existing selections.
      const third = 'https://third.example';
      await settings.load(third);
      await settings.setThemes(
        third,
        settings.themesFor(third).useTheme(b.customId!),
      );
      expect(settings.themesFor(siteA).customTheme!.name, 'First');
      expect(settings.themesFor(third).customTheme!.name, 'Second');
      final restored = ForumSettingsStore(persistence: persistence);
      expect((await restored.loadThemes(siteA)).customThemes, a.customThemes);
      expect((await restored.loadThemes(siteB)).customId, b.customId);
      expect((await restored.loadThemes(third)).customTheme!.name, 'Second');
      expect(
        persistence.values[ForumSettingsStore.themesKey(siteB)],
        isNotNull,
      );
    },
  );

  test(
    'migration can be retried after a failed write without losing legacy themes',
    () async {
      final persistence = _Persistence()..failWrites = true;
      final theme = _custom('Saved', .3);
      persistence.values[ForumSettingsStore.themesKey(siteA)] = jsonEncode(
        ForumThemePreferences().save(theme).toJson(),
      );
      final store = ForumSettingsStore(persistence: persistence);
      expect((await store.loadThemes(siteA)).customTheme, theme);
      persistence.failWrites = false;
      expect((await store.loadThemes(siteA)).customTheme, theme);
      expect(
        (await ForumSettingsStore(
          persistence: persistence,
        ).loadThemes(siteB)).customThemes,
        [theme],
      );
    },
  );

  test(
    'failed migrations retain every forum library until storage recovers',
    () async {
      final persistence = _Persistence()..failWrites = true;
      for (final (site, name) in [(siteA, 'A'), (siteB, 'B')]) {
        persistence.values[ForumSettingsStore.themesKey(site)] = jsonEncode(
          ForumThemePreferences().save(_custom(name, .2)).toJson(),
        );
      }
      final store = ForumSettingsStore(persistence: persistence);
      final settings = ForumSettingsController(store: store);
      addTearDown(settings.dispose);
      await settings.loadShared([siteA, siteB]);
      expect(settings.themesFor(siteA).customTheme!.name, 'A');
      expect(settings.themesFor(siteB).customTheme!.name, 'B');
      persistence.failWrites = false;
      await store.loadThemes(siteA);
      final restored = ForumSettingsStore(persistence: persistence);
      expect(
        (await restored.loadThemes(
          siteB,
        )).customThemes.map((theme) => theme.name),
        ['A', 'B'],
      );
    },
  );

  test(
    'shared editing, importing, and removal preserve independent forum selections',
    () async {
      final store = ForumSettingsStore.memory();
      final settings = ForumSettingsController(store: store);
      addTearDown(settings.dispose);
      final first = _custom('First', .2);
      await settings.setThemes(siteA, settings.themesFor(siteA).save(first));
      await settings.setThemes(
        siteB,
        settings.themesFor(siteB).withPreset(Brightness.dark, 'dracula'),
      );
      expect(settings.themesFor(siteB).customThemes, [first]);
      final edited = first.copyWith(name: 'Edited');
      await settings.setThemes(siteB, settings.themesFor(siteB).save(edited));
      expect(settings.themesFor(siteA).customTheme!.name, 'Edited');
      final colliding = _custom('Imported', .15);
      await settings.importTheme(siteB, colliding);
      final importedId = settings.themesFor(siteB).customId;
      expect(importedId, isNot(first.id));
      expect(settings.themesFor(siteA).customTheme!.name, 'Edited');
      await settings.setThemes(
        siteB,
        settings.themesFor(siteB).remove(first.id),
      );
      expect(settings.themesFor(siteA).source, ForumThemeSource.forum);
      expect(settings.themesFor(siteB).customId, importedId);
      expect((await store.loadThemes(siteA)).customThemes, hasLength(1));
    },
  );

  test('simultaneous forums retain both newly saved themes', () async {
    final store = ForumSettingsStore.memory();
    final settings = ForumSettingsController(store: store);
    addTearDown(settings.dispose);
    final a = _custom('A', .1);
    final b = _custom('B', .2).copyWith(id: 'custom-b');
    await Future.wait([
      settings.setThemes(siteA, settings.themesFor(siteA).save(a)),
      settings.setThemes(siteB, settings.themesFor(siteB).save(b)),
    ]);
    expect(settings.themesFor(siteA).customThemes.map((theme) => theme.name), [
      'A',
      'B',
    ]);
    expect((await store.loadThemes(siteB)).customThemes, hasLength(2));
  });

  test(
    'disconnect forgets forum selection while keeping shared themes',
    () async {
      final store = ForumSettingsStore.memory();
      await store.writeThemes(
        siteA,
        ForumThemePreferences().save(_custom('Saved', .2)),
      );
      await store.forgetThemes(ForgottenSites.removed(siteA, keeping: [siteB]));
      final reconnected = await store.loadThemes(siteA);
      expect(reconnected.source, ForumThemeSource.forum);
      expect(reconnected.customThemes.single.name, 'Saved');
    },
  );
}

ForumTheme _custom(String name, double transparency) => ForumTheme.fromJson({
  ...forumThemePresets.first
      .copyWith(
        name: name,
        background: ForumBackground.appearance(transparency: transparency),
      )
      .toJson(),
  'alternate': forumThemePresets.first
      .forBrightness(Brightness.dark)
      .copyWith(
        name: name,
        background: ForumBackground.appearance(transparency: transparency / 2),
      )
      .toJson(),
}, id: 'custom-same-id');

class _Persistence implements ScalarPreferencePersistence<String> {
  final values = <String, String>{};
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<bool> write(String key, String value) async {
    if (failWrites) return false;
    values[key] = value;
    return true;
  }
}
