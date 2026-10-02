import 'dart:async';

import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'support/shell_test_harness.dart';
import 'support/theme_settings.dart';

const _site = 'https://a.example';
const _other = 'https://b.example';
const _instance = DiscourseInstance(url: _site, title: 'A');
const _otherInstance = DiscourseInstance(url: _other, title: 'B');

void main() {
  testWidgets('queued Native mode choice cannot revive a removed forum key', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      ForumSettingsStore.themeModeKey(_other): 'light',
    });
    final delegate = SharedPreferencesStorePlatform.instance;
    final storage = _HeldWrite(
      delegate,
      'flutter.${ForumSettingsStore.themeModeKey(_site)}',
    );
    SharedPreferencesStorePlatform.instance = storage;
    addTearDown(() {
      if (!storage.release.isCompleted) storage.release.complete();
      SharedPreferencesStorePlatform.instance = delegate;
      SharedPreferences.setMockInitialValues({});
    });
    await pumpShell(
      tester,
      desktop,
      instances: const [_instance, _otherInstance],
    );
    final shell = ShellScope.read(tester.element(primaryMainContent));
    shell.openForumSettings(_site);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Themes'));
    await tester.pumpAndSettle();
    final seededWrites = storage.targetWrites;
    storage.hold = true;
    await _chooseMode(tester, 'Dark');
    await storage.started.future;
    await _chooseMode(tester, 'Light');
    expect(shell.forumSettings.themeModeFor(_site), AppThemeMode.light);
    expect(storage.targetWrites, seededWrites + 1);
    final removal = shell.removeInstance(shell.instanceFor(_site)!);
    await tester.pump();
    expect(await removal, isTrue);
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    final key = ForumSettingsStore.themeModeKey(_site);
    expect(preferences.containsKey(key), isFalse);
    storage.release.complete();
    await tester.pumpAndSettle();
    await preferences.reload();
    expect(preferences.containsKey(key), isFalse);
    expect(storage.targetWrites, seededWrites + 1);
    expect(
      preferences.getString(ForumSettingsStore.themeModeKey(_other)),
      'light',
    );
    expect(shell.forumSettings.themeModeFor(_other), AppThemeMode.light);

    expect(await shell.addInstance(_instance), isTrue);
    expect(shell.forumSettings.themeModeFor(_site), AppThemeMode.system);
    shell.openForumSettings(_site);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Themes'));
    await tester.pumpAndSettle();
    await _chooseMode(tester, 'Dark');
    await preferences.reload();
    expect(preferences.getString(key), 'dark');
    expect(shell.forumSettings.themeModeFor(_site), AppThemeMode.dark);
    expect(
      preferences.getString(ForumSettingsStore.themeModeKey(_other)),
      'light',
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  test('initial hydration cannot seed a mode after public removal', () async {
    SharedPreferences.setMockInitialValues({
      ForumSettingsStore.themeModeKey(_other): 'light',
    });
    final persistence = _HeldRead();
    final store = ForumSettingsStore(persistence: persistence);
    final shell = controller(
      instances: const [_instance, _otherInstance],
      forumSettingsStore: store,
    );
    addTearDown(shell.dispose);
    addTearDown(() {
      if (!persistence.release.isCompleted) persistence.release.complete();
      SharedPreferences.setMockInitialValues({});
    });
    final loading = shell.load();
    await persistence.started.future;
    expect(await shell.removeInstance(shell.instanceFor(_site)!), isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.containsKey(ForumSettingsStore.themeModeKey(_site)),
      isFalse,
    );
    persistence.release.complete();
    await loading;
    await preferences.reload();
    expect(
      preferences.containsKey(ForumSettingsStore.themeModeKey(_site)),
      isFalse,
    );
    expect(
      preferences.getString(ForumSettingsStore.themeModeKey(_other)),
      'light',
    );
    expect(await shell.addInstance(_instance), isTrue);
    expect(shell.forumSettings.themeModeFor(_site), AppThemeMode.system);
    await shell.forumSettings.setThemeMode(_site, AppThemeMode.dark);
    await preferences.reload();
    expect(
      preferences.getString(ForumSettingsStore.themeModeKey(_site)),
      'dark',
    );
  });
}

Future<void> _chooseMode(WidgetTester tester, String label) async {
  final choice = find.descendant(
    of: find.byKey(const ValueKey('appearance-mode')),
    matching: find.text(label),
  );
  await tester.ensureVisible(choice);
  await tester.tap(choice);
  await tester.pumpAndSettle();
}

/// Hold only the acknowledgement of a set that has already reached storage.
final class _HeldWrite extends SharedPreferencesStorePlatform {
  _HeldWrite(this.delegate, this.target);
  final SharedPreferencesStorePlatform delegate;
  final String target;
  final started = Completer<void>();
  final release = Completer<void>();
  bool hold = false;
  int targetWrites = 0;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final saved = await delegate.setValue(type, key, value);
    if (key == target) {
      targetWrites++;
      if (hold && !started.isCompleted) {
        started.complete();
        await release.future;
      }
    }
    return saved;
  }

  @override
  Future<bool> remove(String key) => delegate.remove(key);
  @override
  Future<bool> clear() => delegate.clear();
  @override
  Future<Map<String, Object>> getAll() => delegate.getAll();
  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) => delegate.getAllWithParameters(parameters);
}

final class _HeldRead implements ScalarPreferencePersistence<String> {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<String?> read(String key) async {
    final value = (await SharedPreferences.getInstance()).getString(key);
    if (key == ForumSettingsStore.themeModeKey(_site) && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    return value;
  }

  @override
  Future<bool> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}
