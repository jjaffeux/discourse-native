import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_library.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/theme_settings.dart';

const _site = 'https://a.example';
const _otherSite = 'https://b.example/forum';
const _instance = DiscourseInstance(url: _site, title: 'A');
const _otherInstance = DiscourseInstance(url: _otherSite, title: 'B');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final operation in ['import', 'copy']) {
    test('a queued theme $operation cannot restore a removed forum', () async {
      final persistence = _GatedPersistence();
      addTearDown(() {
        if (!persistence.release.isCompleted) persistence.release.complete();
      });
      final store = ForumSettingsStore(persistence: persistence);
      final shell = controller(
        instances: const [_instance, _otherInstance],
        forumSettingsStore: store,
      );
      addTearDown(shell.dispose);
      await shell.load();
      await shell.forumSettings.setThemes(
        _otherSite,
        ForumThemePreferences.preset('dracula'),
      );
      ForumTheme authored(String id) => ForumTheme.fromJson({
        ...forumThemePresets.first.toJson(),
        'name': id,
      }, id: id);
      final firstTheme = authored('custom-first');
      persistence.holdNextLibraryWrite = true;
      final first = shell.forumSettings.importTheme(_site, firstTheme);
      await persistence.started.future;
      final queued = operation == 'import'
          ? shell.forumSettings.importTheme(_site, authored('custom-queued'))
          : shell.forumSettings.useThemesIn(_otherSite, [_site]);
      expect(await shell.removeInstance(shell.instanceFor(_site)!), isTrue);
      await pumpEventQueue();
      persistence.release.complete();
      await Future.wait([first, queued]);
      await store.loadThemes(_otherSite);
      final durable = ForumThemeLibrary.fromJson(
        jsonDecode(persistence.values[ForumSettingsStore.themeLibraryKey]!)
            as Map<String, dynamic>,
      );
      expect(durable.forums, isNot(contains(_site)));
      expect(durable.forSite(_otherSite).presets[Brightness.dark], 'dracula');
      // The already admitted save retains its authored theme in the shared
      // library; a queued operation for the removed site is abandoned.
      expect(durable.themes, [firstTheme]);
      await shell.addInstance(_instance);
      expect(
        shell.forumSettings.themesFor(_site).source,
        ForumThemeSource.forum,
      );
    });
  }

  test(
    'a removed theme save cannot revert its old choice after failure',
    () async {
      final persistence = _GatedPersistence();
      addTearDown(() {
        if (!persistence.release.isCompleted) persistence.release.complete();
      });
      final store = ForumSettingsStore(persistence: persistence);
      final shell = controller(
        instances: const [_instance, _otherInstance],
        forumSettingsStore: store,
      );
      addTearDown(shell.dispose);
      await shell.load();
      await shell.forumSettings.setThemes(
        _site,
        ForumThemePreferences.preset('dracula'),
      );
      persistence.holdNextLibraryWrite = true;
      persistence.failHeldWrite = true;
      final saving = shell.forumSettings
          .setThemes(_site, ForumThemePreferences.preset('wcag'))
          .catchError((Object _) {});
      await persistence.started.future;
      expect(await shell.removeInstance(shell.instanceFor(_site)!), isTrue);
      await pumpEventQueue();
      persistence.release.complete();
      await saving;
      await store.loadThemes(_otherSite);
      await shell.addInstance(_instance);
      expect(
        shell.forumSettings.themesFor(_site).source,
        ForumThemeSource.forum,
      );
    },
  );

  test(
    'a re-added forum can persist a fresh choice after its old save settles',
    () async {
      final persistence = _GatedPersistence();
      addTearDown(() {
        if (!persistence.release.isCompleted) persistence.release.complete();
      });
      final store = ForumSettingsStore(persistence: persistence);
      final shell = controller(
        instances: const [_instance, _otherInstance],
        forumSettingsStore: store,
      );
      addTearDown(shell.dispose);
      await shell.load();
      persistence.holdNextLibraryWrite = true;
      final oldSave = shell.forumSettings.setThemes(
        _site,
        ForumThemePreferences.preset('wcag'),
      );
      await persistence.started.future;
      expect(await shell.removeInstance(shell.instanceFor(_site)!), isTrue);
      await pumpEventQueue();
      final adding = shell.addInstance(_instance);
      await pumpEventQueue();
      // Adding loads settings behind the pending removal in the store queue.
      expect(shell.instanceFor(_site), isNull);
      persistence.release.complete();
      await Future.wait([oldSave, adding]);
      expect(shell.instanceFor(_site), isNotNull);
      expect(
        shell.forumSettings.themesFor(_site).source,
        ForumThemeSource.forum,
      );
      final fresh = ForumThemePreferences.preset('solarized');
      await shell.forumSettings.setThemes(_site, fresh);
      expect(shell.forumSettings.themesFor(_site), fresh);
      expect(await store.loadThemes(_site), fresh);
    },
  );

  for (final remove in [false, true]) {
    testWidgets(
      'queued Appearance choices ${remove ? 'stay forgotten after removal and re-add' : 'persist the latest choice while the forum remains'}',
      (tester) async {
        final persistence = _GatedPersistence();
        addTearDown(() {
          if (!persistence.release.isCompleted) persistence.release.complete();
        });
        final store = ForumSettingsStore(persistence: persistence);
        final shell = controller(
          instances: const [_instance, _otherInstance],
          forumSettingsStore: store,
        );
        addTearDown(shell.dispose);
        await shell.load();
        final authored = ForumTheme.fromJson({
          ...forumThemePresets.first.toJson(),
          'name': 'Shared authored theme',
        }, id: 'custom-shared');
        await shell.forumSettings.setThemes(
          _site,
          shell.forumSettings.themesFor(_site).add(authored),
        );
        await pumpSettings(
          tester,
          shell,
          width: defaultTargetPlatform == TargetPlatform.macOS ? 960 : 390,
          platform: defaultTargetPlatform,
        );

        persistence.holdNextLibraryWrite = true;
        Future<void> choose(String id) async {
          final row = find.byKey(ValueKey(('theme-choice', id)));
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
          await tester.tap(row);
          await tester.pump();
        }

        await choose('wcag');
        await persistence.started.future;
        await choose('solarized');
        expect(
          shell.forumSettings.themesFor(_site).presets[Brightness.light],
          'solarized',
        );
        // Joins the same pending controller write without making another edit.
        final saving = shell.forumSettings.setThemes(
          _site,
          shell.forumSettings.themesFor(_site),
        );
        final otherChoice = shell.forumSettings
            .themesFor(_otherSite)
            .withPreset(Brightness.dark, 'dracula');
        final otherSaving = shell.forumSettings.setThemes(
          _otherSite,
          otherChoice,
        );
        if (remove) {
          expect(await shell.removeInstance(shell.instanceFor(_site)!), isTrue);
          await tester.pump();
          await tester.pump();
          expect(shell.instanceFor(_site), isNull);
        }
        // The real Appearance page leaves with its forum in the app.
        await tester.pumpWidget(const SizedBox.shrink());
        persistence.release.complete();
        await tester.pump();
        await tester.pump();
        await Future.wait([saving, otherSaving]);
        await store.loadThemes(_otherSite);
        final durable = ForumThemeLibrary.fromJson(
          jsonDecode(persistence.values[ForumSettingsStore.themeLibraryKey]!)
              as Map<String, dynamic>,
        );
        if (remove) {
          await shell.addInstance(_instance);
          expect(
            shell.forumSettings.themesFor(_site).source,
            ForumThemeSource.forum,
          );
          expect(durable.forums, isNot(contains(_site)));
        } else {
          expect(durable.forSite(_site).presets[Brightness.light], 'solarized');
        }
        expect(durable.forSite(_otherSite), otherChoice);
        expect(durable.themes, [authored]);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }),
    );
  }
}

class _GatedPersistence implements ScalarPreferencePersistence<String> {
  final values = <String, String>{};
  bool holdNextLibraryWrite = false;
  bool failHeldWrite = false;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<bool> write(String key, String value) async {
    if (key == ForumSettingsStore.themeLibraryKey && holdNextLibraryWrite) {
      holdNextLibraryWrite = false;
      started.complete();
      await release.future;
      if (failHeldWrite) return false;
    }
    values[key] = value;
    return true;
  }
}
