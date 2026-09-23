import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  final fixtures =
      (jsonDecode(
                File(
                  'test/fixtures/oneboxes/core_cards.json',
                ).readAsStringSync(),
              )
              as List)
          .cast<Map<String, dynamic>>();
  test('the engine inventory covers every pinned core engine', () {
    final inventory =
        jsonDecode(
              File(
                'tool/markup_contracts/core/onebox_inventory.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final engines = (inventory['engines'] as List).cast<Map<String, dynamic>>();
    final snapshots = Directory('tool/markup_contracts/core/onebox_snapshot')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where(
          (name) =>
              name.startsWith('lib__onebox__engine__') &&
              name.endsWith('_onebox.rb'),
        )
        .toSet();
    expect(
      engines
          .map((engine) => (engine['source'] as String).replaceAll('/', '__'))
          .toSet(),
      snapshots,
    );
    expect(engines.length, 69);
  });
  for (final fixture in fixtures) {
    test('core ${fixture['template']} retains non-extracted content', () {
      final aside = html
          .parseFragment(fixture['html'] as String)
          .querySelector('aside')!;
      final original = aside.outerHtml;
      final parsed = OneboxData.from(aside);
      expect(aside.outerHtml, original);
      // Recombining extracted title and remaining body must preserve all text
      // within the article, even when title and thumbnail share a wrapper.
      final originalText = aside
          .querySelector('article')!
          .text
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final remaining =
          '${parsed.title ?? ''} ${html.parseFragment(parsed.bodyHtml).text}'
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
      for (final word
          in originalText.split(' ').where((word) => word.isNotEmpty)) {
        expect(
          remaining,
          contains(word),
          reason: fixture['template'] as String,
        );
      }
    });
  }
  testWidgets('all core card templates render narrowly with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final fixture in fixtures) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Material(
              child: SingleChildScrollView(
                child: CookedHtml(
                  key: ValueKey(fixture['template']),
                  html: fixture['html'] as String,
                  buildAsync: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byType(OneboxCard),
        findsOneWidget,
        reason: fixture['template'] as String,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: fixture['template'] as String,
      );
    }
  });
}
