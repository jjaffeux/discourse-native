import 'dart:async';

import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/shell/forum_settings_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  const siteA = 'https://a.example';
  const siteB = 'https://b.example/forum';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'forum settings uses a content page and returns through navigation',
    () async {
      final shell = ShellController(
        instanceStore: FakeInstanceStore(const [
          DiscourseInstance(url: siteA, title: 'A'),
          DiscourseInstance(url: siteB, title: 'B'),
        ]),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      final previous = shell.currentContent;
      shell.openForumSettings(siteA);
      expect(shell.currentContent!.isAppearance, isTrue);
      expect(shell.canCreateTopicHere, isFalse);
      shell.openForumSettings(siteA);
      shell.handleBack(canReturnToSidebar: true);
      expect(shell.currentContent, previous);
      shell.openForumSettings(siteB);
      expect(shell.currentInstance!.url, siteB);
      expect(shell.currentContent!.isAppearance, isTrue);
    },
  );

  test(
    'theme choices persist per forum, including subfolder identities',
    () async {
      final settings = ForumSettingsController(store: ForumSettingsStore());
      addTearDown(settings.dispose);
      await settings.setThemeMode(siteA, AppThemeMode.dark);
      await settings.setThemeMode(siteB, AppThemeMode.light);
      final restored = ForumSettingsController(store: ForumSettingsStore());
      addTearDown(restored.dispose);
      await restored.load('$siteA/');
      await restored.load(siteB);
      await restored.load('https://b.example');
      expect(restored.themeModeFor(siteA), AppThemeMode.dark);
      expect(restored.themeModeFor('$siteB/'), AppThemeMode.light);
      expect(restored.themeModeFor('https://b.example'), AppThemeMode.system);
    },
  );

  test(
    'migrates existing forums once and starts new forums with System',
    () async {
      final forums = ForumSettingsStore();
      final instances = FakeInstanceStore([
        const DiscourseInstance(url: siteA, title: 'A'),
        const DiscourseInstance(url: siteB, title: 'B'),
      ]);
      ShellController shell() => ShellController(
        instanceStore: instances,
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
        appSettingsStore: AppSettingsStore(
          persistence: MemoryAppSettingsPersistence(themeMode: 'dark'),
        ),
        forumSettingsStore: forums,
      );
      final first = shell();
      await first.load();
      expect(first.forumSettings.themeModeFor(siteA), AppThemeMode.dark);
      expect(first.forumSettings.themeModeFor(siteB), AppThemeMode.dark);
      await first.forumSettings.setThemeMode(siteA, AppThemeMode.system);
      await first.addInstance(
        const DiscourseInstance(url: 'https://new.example', title: 'New'),
      );
      expect(
        first.forumSettings.themeModeFor('https://new.example'),
        AppThemeMode.system,
      );
      first.dispose();

      final second = shell();
      addTearDown(second.dispose);
      await second.load();
      expect(second.forumSettings.themeModeFor(siteA), AppThemeMode.system);
      expect(second.forumSettings.themeModeFor(siteB), AppThemeMode.dark);
      expect(
        second.forumSettings.themeModeFor('https://new.example'),
        AppThemeMode.system,
      );
    },
  );

  test(
    'a late migration read cannot replace a newer explicit choice',
    () async {
      final persistence = _ControlledPersistence()
        ..readGate = Completer<void>();
      final settings = ForumSettingsController(
        store: ForumSettingsStore(persistence: persistence),
      );
      addTearDown(settings.dispose);
      final loading = settings.load(siteA, initialMode: AppThemeMode.dark);
      await persistence.readStarted.future;
      final saving = settings.setThemeMode(siteA, AppThemeMode.light);
      expect(settings.themeModeFor(siteA), AppThemeMode.light);
      persistence.readGate!.complete();
      await Future.wait([loading, saving]);
      expect(settings.themeModeFor(siteA), AppThemeMode.light);
      expect(
        persistence.values[ForumSettingsStore.themeModeKey(siteA)],
        'light',
      );
    },
  );

  test(
    'rapid changes persist in order and leave other forums untouched',
    () async {
      final persistence = _ControlledPersistence()
        ..writeGate = Completer<void>();
      final settings = ForumSettingsController(
        store: ForumSettingsStore(persistence: persistence),
      );
      addTearDown(settings.dispose);
      final dark = settings.setThemeMode(siteA, AppThemeMode.dark);
      await persistence.writeStarted.future;
      final light = settings.setThemeMode(siteA, AppThemeMode.light);
      final system = settings.setThemeMode(siteA, AppThemeMode.system);
      await settings.setThemeMode(siteA, AppThemeMode.system);
      await settings.setThemeMode(siteB, AppThemeMode.dark);
      persistence.writeGate!.complete();
      await Future.wait([dark, light, system]);
      expect(
        persistence.writes
            .where(
              (entry) => entry.$1 == ForumSettingsStore.themeModeKey(siteA),
            )
            .map((entry) => entry.$2),
        ['dark', 'light', 'system'],
      );
      expect(settings.themeModeFor(siteB), AppThemeMode.dark);
      expect(
        persistence.values[ForumSettingsStore.themeModeKey(siteA)],
        'system',
      );
    },
  );

  test('failed writes retain the session choice through hydration', () async {
    final persistence = _ControlledPersistence()..acceptWrites = false;
    final settings = ForumSettingsController(
      store: ForumSettingsStore(persistence: persistence),
    );
    addTearDown(settings.dispose);
    await settings.setThemeMode(siteA, AppThemeMode.dark);
    await settings.load(siteA);
    expect(settings.themeModeFor(siteA), AppThemeMode.dark);
  });

  test(
    'unknown values follow the system and failed reads do not overwrite',
    () async {
      final persistence = _ControlledPersistence();
      final key = ForumSettingsStore.themeModeKey(siteA);
      persistence.values[key] = 'unknown';
      final store = ForumSettingsStore(persistence: persistence);
      expect(await store.loadThemeMode(siteA), AppThemeMode.system);
      persistence.failReads = true;
      expect(await store.loadThemeMode(siteA), AppThemeMode.system);
      expect(persistence.writes, isEmpty);
    },
  );
}

class _ControlledPersistence implements ScalarPreferencePersistence<String> {
  final values = <String, String>{};
  final writes = <(String, String)>[];
  Completer<void>? readGate;
  Completer<void>? writeGate;
  final readStarted = Completer<void>();
  final writeStarted = Completer<void>();
  bool acceptWrites = true;
  bool failReads = false;

  @override
  Future<String?> read(String key) async {
    if (!readStarted.isCompleted) readStarted.complete();
    await readGate?.future;
    if (failReads) throw StateError('Read failed');
    return values[key];
  }

  @override
  Future<bool> write(String key, String value) async {
    writes.add((key, value));
    if (!writeStarted.isCompleted) {
      writeStarted.complete();
      await writeGate?.future;
    }
    if (acceptWrites) values[key] = value;
    return acceptWrites;
  }
}
