import 'dart:async';

import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/global_search_fixtures.dart';
import 'support/shell_test_harness.dart';

void main() {
  for (final phase in ['before frame', 'debounce', 'request']) {
    for (final click in [false, true]) {
      _testChoice(
        'stale user choice cannot replace new text: $phase click=$click',
        (tester) async {
          final api = _UserLookupApi();
          final shell = await _openAuthor(tester, api);
          final field = _key('global-search-filter-value');
          await tester.enterText(field, 'sa');
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pumpAndSettle();
          expect(find.text('Sam'), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.home);

          await tester.enterText(field, 'al');
          if (phase != 'before frame') await tester.pump();
          if (phase == 'request') {
            await tester.pump(const Duration(milliseconds: 200));
            expect(api.terms, contains('al'));
          }
          expect(find.text('Sam'), findsOneWidget);
          if (click) {
            await tester.tap(find.text('Sam'));
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          }
          await tester.pump();

          expect(_value(tester), 'al');
          await tester.tap(_key('global-search-filter-apply'));
          await tester.pump();
          expect(shell.globalSearch.conditions.single.value, ['al']);
          api.release();
          await tester.pump(const Duration(milliseconds: 450));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final click in [false, true]) {
    _testChoice('fresh current-query choices remain usable: click=$click', (
      tester,
    ) async {
      final api = _UserLookupApi();
      final shell = await _openAuthor(tester, api);
      await tester.enterText(_key('global-search-filter-value'), 'al');
      await tester.pump(const Duration(milliseconds: 200));
      expect(api.terms, contains('al'));
      api.release();
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      if (click) {
        await tester.tap(find.text('Alice'));
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      }
      await tester.pump();
      expect(_value(tester), 'alice');
      await tester.tap(_key('global-search-filter-apply'));
      await tester.pump();
      expect(shell.globalSearch.conditions.single.value, ['alice']);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  _testChoice('the typed Use option stays available while lookup is pending', (
    tester,
  ) async {
    final api = _UserLookupApi();
    final shell = await _openAuthor(tester, api);
    await tester.enterText(_key('global-search-filter-value'), 'al');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Use “al”'));
    await tester.pump();
    expect(_value(tester), 'al');
    await tester.tap(_key('global-search-filter-apply'));
    await tester.pump();
    expect(shell.globalSearch.conditions.single.value, ['al']);
    api.release();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Finder _key(String key) => find.byKey(ValueKey(key));

String _value(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: _key('global-search-filter-value'),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

Future<ShellController> _openAuthor(
  WidgetTester tester,
  _UserLookupApi api,
) async {
  addTearDown(api.release);
  await pumpShell(
    tester,
    desktop,
    instances: globalSearchFixtureSites,
    api: api,
    authenticator: FakeAuthenticator()
      ..keys.addAll({
        globalSearchFixtureSite: 'local-fixture',
        globalSearchFixtureOtherSite: 'local-fixture',
      }),
  );
  final shell = ShellScope.read(tester.element(find.byType(ForumSearch)));
  await tester.tap(find.byKey(ForumSearch.inputKey));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(ForumSearch.inputKey), 'design');
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pumpAndSettle();
  await tester.tap(_key('global-search-filter-trigger'));
  await tester.pumpAndSettle();
  await tester.tap(_key('global-search-filter-author'));
  await tester.pumpAndSettle();
  return shell;
}

void _testChoice(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });
}

class _UserLookupApi extends GlobalSearchFixtureApi {
  final terms = <String>[];
  final _held = Completer<Map<String, dynamic>>();
  static const _alice = {
    'users': [
      {'id': 2, 'username': 'alice', 'name': 'Alice'},
    ],
  };

  void release() {
    if (!_held.isCompleted) _held.complete(_alice);
  }

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final uri = Uri.parse(path);
    if (uri.path == '/u/search/users.json') {
      final term = uri.queryParameters['term'] ?? '';
      terms.add(term);
      if (term == 'al') return _held.future;
      return {
        'users': [
          {'id': 1, 'username': 'sam', 'name': 'Sam'},
        ],
      };
    }
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
