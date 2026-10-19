import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/data/forum_tab_store.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/data/site_preference_keys.dart';
import 'package:discourse_native/src/data/topic_sidebar_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_library.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/shell/forum_settings_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _home = ForumSettingsController.homeSite;
const _first = 'https://first.example';
const _second = 'https://second.example/forum';
const _third = 'https://third.example';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('startup restores the last forum and immediate switching with bounded '
      'theme-library reads including preference cleanup', () async {
    final sites = [for (var i = 0; i < 10; i++) 'https://site-$i.example'];
    SharedPreferences.setMockInitialValues({
      for (var i = 0; i < sites.length; i++)
        SharedPreferencesTopicSidebarPersistence.keys.of(sites[i]): i.isEven,
    });
    final persistence = _modernPersistence(sites);
    final store = ForumSettingsStore(persistence: persistence);
    final tabs = ForumTabStore(persistence: MemoryForumTabPersistence());
    await tabs.save([
      for (var i = 0; i < sites.length; i++)
        ForumWorkspace(
          siteUrl: sites[i],
          accountIdentity: 'anonymous',
          tabs: [
            ForumTab(
              id: 'saved-$i',
              rootDestinationId: 'new-tab',
              contentStack: [ContentRoute.newTab(), ContentRoute.appearance()],
            ),
          ],
          activeTabId: 'saved-$i',
        ),
    ], selectedSiteUrl: sites.last);
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        for (final site in sites) DiscourseInstance(url: site, title: site),
      ]),
      forumTabs: tabs,
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
      appSettingsStore: AppSettingsStore(
        persistence: MemoryAppSettingsPersistence(themeMode: 'dark'),
      ),
      forumSettingsStore: store,
    );
    addTearDown(shell.dispose);

    await shell.load();

    expect(shell.loadStatus, InstanceLoadStatus.ready);
    expect(shell.currentInstance?.url, sites.last);
    expect(shell.activeTabId, 'saved-9');
    expect(shell.currentContent?.isAppearance, isTrue);
    expect(shell.forumSettings.shared.font, ForumFont.jetBrainsMono);
    expect(shell.forumSettings.themeModeFor(_home), AppThemeMode.system);
    expect(persistence.libraryReads, lessThanOrEqualTo(3));
    for (var i = 0; i < sites.length; i++) {
      shell.selectInstance(i);
      expect(shell.currentWorkspace?.siteUrl, sites[i]);
      expect(shell.activeTabId, 'saved-$i');
      expect(shell.currentContent?.isAppearance, isTrue);
      expect(
        shell.forumSettings.themeModeFor(sites[i]),
        i.isEven ? AppThemeMode.dark : AppThemeMode.light,
      );
      expect(
        shell.forumSettings.themesFor(sites[i]).presets[Brightness.dark],
        i.isEven ? 'dracula' : 'wcag',
      );
      expect(shell.topicSidebar.collapsedFor(sites[i]), i.isEven);
    }
    await store.loadThemes(sites.first);
    expect(persistence.libraryReads, 4);
    final reads = Map.of(persistence.reads);
    await shell.forumSettings.restoreSavedForums(
      sites,
      initialMode: AppThemeMode.light,
    );
    expect(persistence.reads, reads);
  });

  test('startup keeps home-first legacy collision order and adopts the '
      'earlier rail forum font', () async {
    final persistence = _Persistence();
    for (final (site, name, font) in [
      (_home, 'Home', 'lato'),
      (_first, 'First', 'openSans'),
      (_second, 'Second', 'jetBrainsMono'),
    ]) {
      persistence.values[ForumSettingsStore.themesKey(site)] = jsonEncode({
        ...ForumThemePreferences().save(_custom(name)).toJson(),
        'font': font,
      });
    }
    final settings = ForumSettingsController(
      store: ForumSettingsStore(persistence: persistence),
    );
    addTearDown(settings.dispose);

    await settings.restoreSavedForums([
      _first,
      _second,
    ], initialMode: AppThemeMode.dark);

    expect(settings.shared.font, ForumFont.openSans);
    expect(settings.themesFor(_home).customId, 'custom-same');
    expect(settings.themesFor(_first).customId, 'custom-same-2');
    expect(settings.themesFor(_second).customId, 'custom-same-3');
    expect(settings.themesFor(_second).customTheme?.name, 'Second');
    expect(settings.themesFor(_first).customThemes.map((theme) => theme.name), [
      'Home',
      'First',
      'Second',
    ]);
    expect(settings.themeModeFor(_home), AppThemeMode.system);
    expect(settings.themeModeFor(_first), AppThemeMode.dark);
    expect(settings.themeModeFor(_second), AppThemeMode.dark);
    expect(persistence.libraryReads, 1);
    expect(persistence.libraryWrites, 1);
  });

  test(
    'a corrupt middle legacy forum leaves later migrations intact',
    () async {
      final persistence = _Persistence()
        ..values[ForumSettingsStore.themesKey(_first)] = jsonEncode(
          ForumThemePreferences().save(_custom('First')).toJson(),
        )
        ..values[ForumSettingsStore.themesKey(_second)] = '{damaged'
        ..values[ForumSettingsStore.themesKey(_third)] = jsonEncode(
          ForumThemePreferences().save(_custom('Third')).toJson(),
        );
      final library = await ForumSettingsStore(
        persistence: persistence,
      ).loadThemeLibrary([_first, _second, _third]);

      expect(library.forSite(_first).customTheme?.name, 'First');
      expect(library.forSite(_third).customTheme?.name, 'Third');
      expect(library.forSite(_third).customId, 'custom-same-2');
      expect(library.forums, isNot(contains(_second)));
      expect(_savedLibrary(persistence).forums.keys, [_first, _third]);
      expect(
        persistence.values[ForumSettingsStore.themesKey(_second)],
        '{damaged',
      );
      expect(persistence.libraryWrites, 1);
    },
  );

  test('a failed batch write retains pending migrations and legacy backups '
      'until a durable retry', () async {
    final persistence = _Persistence()..failLibraryWrites = true;
    for (final (site, name) in [(_first, 'First'), (_second, 'Second')]) {
      persistence.values[ForumSettingsStore.themesKey(site)] = jsonEncode(
        ForumThemePreferences().save(_custom(name)).toJson(),
      );
    }
    final backups = Map.of(persistence.values);
    final store = ForumSettingsStore(persistence: persistence);

    final failed = await store.loadThemeLibrary([_first, _second]);

    expect(failed.forSite(_first).customTheme?.name, 'First');
    expect(failed.forSite(_second).customId, 'custom-same-2');
    expect(persistence.values, backups);
    persistence
      ..failLibraryWrites = false
      ..failLegacyReads = true;
    final retried = await store.loadThemeLibrary([_first, _second]);
    expect(retried.forSite(_second).customTheme?.name, 'Second');
    expect(retried.forSite(_second).customId, 'custom-same-2');
    expect(_savedLibrary(persistence).themes.map((theme) => theme.name), [
      'First',
      'Second',
    ]);
    for (final entry in backups.entries) {
      expect(persistence.values[entry.key], entry.value);
      expect(persistence.reads[entry.key], 1);
    }
    final restored = await ForumSettingsStore(
      persistence: persistence,
    ).loadThemes(_second);
    expect(restored.customId, 'custom-same-2');
    expect(restored.customTheme?.name, 'Second');
  });

  test('a transient library read retries within startup and explicit loads '
      'remain fresh after unreadable storage recovers', () async {
    final persistence = _modernPersistence([_first, _second])
      ..failingLibraryReads = 1;
    final store = ForumSettingsStore(persistence: persistence);
    final settings = ForumSettingsController(store: store);
    addTearDown(settings.dispose);

    await settings.restoreSavedForums([
      _first,
      _second,
    ], initialMode: AppThemeMode.system);

    expect(settings.themesFor(_first).presets[Brightness.dark], 'dracula');
    expect(settings.themesFor(_second).presets[Brightness.dark], 'wcag');
    expect(persistence.libraryReads, 2);
    final valid = _savedLibrary(persistence);
    persistence.values[ForumSettingsStore.themeLibraryKey] = '{damaged';
    final fallback = await store.loadThemeLibrary([_first, _second]);
    expect(fallback.forSite(_second).presets[Brightness.dark], 'wcag');
    expect(persistence.values[ForumSettingsStore.themeLibraryKey], '{damaged');
    expect(persistence.libraryWrites, 0);
    persistence.values[ForumSettingsStore.themeLibraryKey] = jsonEncode(
      valid
          .update(
            _second,
            ForumThemePreferences.preset('solarized'),
            previous: valid.forSite(_second),
          )
          .toJson(),
    );
    expect(
      (await store.loadThemes(_second)).presets[Brightness.dark],
      'solarized',
    );
  });

  test('a live theme choice wins a held startup library read', () async {
    final persistence = _modernPersistence([_first, _second])
      ..holdLibraryRead = true;
    addTearDown(persistence.releaseLibrary);
    final store = ForumSettingsStore(persistence: persistence);
    final settings = ForumSettingsController(store: store);
    addTearDown(settings.dispose);
    final loading = settings.restoreSavedForums([
      _first,
      _second,
    ], initialMode: AppThemeMode.system);
    await persistence.libraryReadStarted.future;
    final chosen = ForumThemePreferences.preset('solarized');
    final saving = settings.setThemes(_second, chosen);
    expect(settings.themesFor(_second), chosen);

    persistence.releaseLibrary();
    await Future.wait([loading, saving]);

    expect(settings.themesFor(_second), chosen);
    expect((await store.loadThemes(_second)), chosen);
    expect(settings.themesFor(_first).presets[Brightness.dark], 'dracula');
  });

  test('removal behind a held startup batch cannot restore its old snapshot '
      'or its durable selection when re-added', () async {
    final persistence = _modernPersistence([_first, _second])
      ..holdLibraryRead = true;
    addTearDown(persistence.releaseLibrary);
    final store = ForumSettingsStore(persistence: persistence);
    final settings = ForumSettingsController(store: store);
    addTearDown(settings.dispose);
    final loading = settings.restoreSavedForums([
      _first,
      _second,
    ], initialMode: AppThemeMode.system);
    await persistence.libraryReadStarted.future;
    settings.forgetSites(
      ForgottenSites.removed(_first, keeping: [_home, _second]),
    );
    final retired = store.loadThemeLibrary([_second]);
    final readding = settings.load(_first);

    persistence.releaseLibrary();
    await Future.wait([loading, readding]);

    expect((await retired).forums, isNot(contains(_first)));
    expect(
      _savedLibrary(persistence).forSite(_first).source,
      ForumThemeSource.forum,
    );
    expect(settings.themesFor(_first).source, ForumThemeSource.forum);
    expect(settings.themesFor(_second).presets[Brightness.dark], 'wcag');
  });

  test(
    'disposing during startup suppresses completion notifications',
    () async {
      final persistence = _modernPersistence([_first, _second])
        ..holdLibraryRead = true;
      addTearDown(persistence.releaseLibrary);
      final settings = ForumSettingsController(
        store: ForumSettingsStore(persistence: persistence),
      );
      var notifications = 0;
      settings.addListener(() => notifications++);
      final loading = settings.restoreSavedForums([
        _first,
        _second,
      ], initialMode: AppThemeMode.system);
      await persistence.libraryReadStarted.future;
      settings.dispose();

      persistence.releaseLibrary();
      await loading;

      expect(notifications, 0);
    },
  );
}

ForumTheme _custom(String name) => ForumTheme.fromJson({
  ...forumThemePresets.first.toJson(),
  'name': name,
}, id: 'custom-same');

_Persistence _modernPersistence(List<String> sites) => _Persistence()
  ..values.addAll({
    ForumSettingsStore.appearanceKey: jsonEncode(
      const SharedAppearance(font: ForumFont.jetBrainsMono).toJson(),
    ),
    ForumSettingsStore.themeLibraryKey: jsonEncode(
      ForumThemeLibrary(
        forums: {
          _home: ForumThemePreferences.defaults,
          for (var i = 0; i < sites.length; i++)
            sites[i]: ForumThemePreferences.preset(
              i.isEven ? 'dracula' : 'wcag',
            ),
        },
      ).toJson(),
    ),
    for (var i = 0; i < sites.length; i++)
      ForumSettingsStore.themeModeKey(sites[i]): i.isEven ? 'dark' : 'light',
  });

ForumThemeLibrary _savedLibrary(_Persistence persistence) =>
    ForumThemeLibrary.fromJson(
      jsonDecode(persistence.values[ForumSettingsStore.themeLibraryKey]!)
          as Map<String, dynamic>,
    );

final class _Persistence implements ScalarPreferencePersistence<String> {
  final values = <String, String>{};
  final reads = <String, int>{};
  int libraryWrites = 0;
  int failingLibraryReads = 0;
  bool failLibraryWrites = false;
  bool failLegacyReads = false;
  bool holdLibraryRead = false;
  final libraryReadStarted = Completer<void>();
  final _libraryRelease = Completer<void>();

  int get libraryReads => reads[ForumSettingsStore.themeLibraryKey] ?? 0;

  void releaseLibrary() {
    if (!_libraryRelease.isCompleted) _libraryRelease.complete();
  }

  @override
  Future<String?> read(String key) async {
    reads.update(key, (count) => count + 1, ifAbsent: () => 1);
    if (key == ForumSettingsStore.themeLibraryKey && failingLibraryReads > 0) {
      failingLibraryReads--;
      throw StateError('Library storage temporarily unavailable.');
    }
    if (failLegacyReads &&
        key.startsWith('${ForumSettingsStore.themesKeys.prefix}.')) {
      throw StateError('Legacy storage unavailable.');
    }
    final value = values[key];
    if (key == ForumSettingsStore.themeLibraryKey && holdLibraryRead) {
      holdLibraryRead = false;
      libraryReadStarted.complete();
      await _libraryRelease.future;
    }
    return value;
  }

  @override
  Future<bool> write(String key, String value) async {
    if (key == ForumSettingsStore.themeLibraryKey) {
      libraryWrites++;
      if (failLibraryWrites) return false;
    }
    values[key] = value;
    return true;
  }
}
