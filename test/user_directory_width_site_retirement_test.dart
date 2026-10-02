import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/user_directory_column_width_store.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _other = 'https://team.discourse.org';
String _key(String site) =>
    SharedPreferencesUserDirectoryColumnWidthPersistence.keys.of(site);

void main() {
  testWidgets('queued Native column resize cannot revive a removed forum key', (
    tester,
  ) async {
    final otherWidths = UserDirectoryColumnWidths(const {
      'identity': 260,
    }).encode();
    SharedPreferences.setMockInitialValues({_key(_other): otherWidths});
    final delegate = SharedPreferencesStorePlatform.instance;
    final storage = _HeldWrite(delegate, 'flutter.${_key(_site)}');
    SharedPreferencesStorePlatform.instance = storage;
    addTearDown(() {
      if (!storage.release.isCompleted) storage.release.complete();
      SharedPreferencesStorePlatform.instance = delegate;
      SharedPreferences.setMockInitialValues({});
    });
    final api = FakeDiscourseApi(
      pluginResponses: const {
        'GET /directory-columns.json': {
          'directory_columns': [
            {
              'id': 1,
              'name': 'likes_received',
              'type': 'automatic',
              'position': 1,
            },
          ],
        },
        'GET /directory_items.json?period=weekly&order=likes_received': {
          'directory_items': [
            {
              'id': 1,
              'likes_received': 42,
              'user': {'id': 1, 'username': 'sam', 'name': 'Sam Saffron'},
            },
          ],
          'meta': {'total_rows_directory_items': 1},
        },
      },
    );
    await pumpShell(tester, desktop, api: api);
    await _openDirectory(tester);
    final shell = ShellScope.read(tester.element(primaryMainContent));
    expect(shell.currentContent?.id, 'users');
    final initialWidth = tester.widget<DResizableHandle>(_resize).value;
    storage.hold = true;
    await tester.drag(_resize, const Offset(24, 0));
    await tester.pumpAndSettle();
    await storage.started.future;
    final firstWidth = tester.widget<DResizableHandle>(_resize).value;
    expect(firstWidth, greaterThan(initialWidth));
    await tester.drag(_resize, const Offset(32, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DResizableHandle>(_resize).value,
      greaterThan(firstWidth),
    );
    expect(storage.targetWrites, 1);
    final removal = shell.removeInstance(shell.instanceFor(_site)!);
    await tester.pump();
    expect(await removal, isTrue);
    await tester.pump();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey(_key(_site)), isFalse);
    storage.release.complete();
    await const UserDirectoryColumnWidthStore().read(siteUrl: _site);
    await preferences.reload();
    expect(preferences.containsKey(_key(_site)), isFalse);
    expect(storage.targetWrites, 1);
    expect(preferences.getString(_key(_other)), otherWidths);
    await _openDirectory(tester);
    expect(tester.widget<DResizableHandle>(_resize).value, 260);

    expect(await shell.addInstance(instance('meta.discourse.org')), isTrue);
    shell.selectInstance(
      shell.instances.indexWhere((site) => site.url == _site),
    );
    await tester.pumpAndSettle();
    await _openDirectory(tester);
    expect(tester.widget<DResizableHandle>(_resize).value, initialWidth);
    await tester.drag(_resize, const Offset(40, 0));
    await tester.pumpAndSettle();
    final freshWidth = tester.widget<DResizableHandle>(_resize).value;
    expect(freshWidth, greaterThan(initialWidth));
    expect(
      (await const UserDirectoryColumnWidthStore().read(
        siteUrl: _site,
      ))['identity'],
      freshWidth,
    );
    await preferences.reload();
    expect(
      UserDirectoryColumnWidths.decode(
        preferences.getString(_key(_site)),
      )['identity'],
      freshWidth,
    );
    expect(storage.targetWrites, 2);
    expect(preferences.getString(_key(_other)), otherWidths);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

Future<void> _openDirectory(WidgetTester tester) async {
  if (sidebarDestination('Users').evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('rail-sidebar-toggle')));
    await tester.pumpAndSettle();
  }
  await tester.tap(sidebarDestination('Users'));
  await tester.pumpAndSettle();
  expect(find.byType(UsersPage), findsOneWidget);
}

Finder get _resize => find.byWidgetPredicate(
  (widget) =>
      widget is DResizableHandle &&
      widget.semanticLabel == 'Resize User column',
);

/// The first set has reached storage before acknowledgement is held. A later
/// resize is the only operation that can bring the removed key back.
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
