import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/assign/assign_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AssignPreferences create() {
    final preferences = AssignPreferences(
      diagnostics: const PluginDiagnosticsReporter.noop(),
    );
    addTearDown(preferences.dispose);
    return preferences;
  }

  test(
    'loads the legacy visibility key and persists subsequent changes',
    () async {
      SharedPreferences.setMockInitialValues({
        AssignPreferences.storageKey: false,
        'unrelated': 'kept',
      });
      final preferences = create();
      await preferences.load();
      expect(preferences.showAssignments, isFalse);
      await preferences.setShowAssignments(true);
      final reloaded = create();
      await reloaded.load();
      expect(reloaded.showAssignments, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString('unrelated'),
        'kept',
      );
    },
  );

  for (final choice in [true, false]) {
    test(
      'choice $choice made before hydration wins over a delayed stored value',
      () async {
        SharedPreferences.setMockInitialValues({});
        final platform = _DelayedPreferences({
          'flutter.${AssignPreferences.storageKey}': !choice,
        });
        SharedPreferencesStorePlatform.instance = platform;
        final preferences = create();
        final loading = preferences.load();
        await platform.readStarted.future;
        final saving = preferences.setShowAssignments(choice);
        expect(preferences.showAssignments, choice);
        platform.releaseRead.complete();
        await Future.wait([loading, saving]);
        expect(preferences.showAssignments, choice);
        expect(
          (await SharedPreferences.getInstance()).getBool(
            AssignPreferences.storageKey,
          ),
          choice,
        );
      },
    );
  }

  test('rapid choices remain ordered across plugin instances', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = create();
    await Future.wait([
      preferences.setShowAssignments(false),
      preferences.setShowAssignments(true),
      preferences.setShowAssignments(false),
    ]);
    final next = create();
    await next.load();
    expect(next.showAssignments, isFalse);
  });

  test('a late read does not notify a disposed plugin', () async {
    SharedPreferences.setMockInitialValues({});
    final platform = _DelayedPreferences({});
    SharedPreferencesStorePlatform.instance = platform;
    final preferences = AssignPreferences(
      diagnostics: const PluginDiagnosticsReporter.noop(),
    );
    var notifications = 0;
    preferences.addListener(() => notifications++);
    final loading = preferences.load();
    await platform.readStarted.future;
    preferences.dispose();
    platform.releaseRead.complete();
    await loading;
    expect(notifications, 0);
  });
}

final class _DelayedPreferences extends InMemorySharedPreferencesStore {
  _DelayedPreferences(super.data) : super.withData();
  final readStarted = Completer<void>();
  final releaseRead = Completer<void>();
  @override
  Future<Map<String, Object>> getAll() async {
    readStarted.complete();
    await releaseRead.future;
    return super.getAll();
  }
}
