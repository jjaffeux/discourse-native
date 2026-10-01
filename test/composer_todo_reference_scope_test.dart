import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_list_source.dart';
import 'package:discourse_native/src/shell/composer_todos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import 'composer_list_items_test.dart' show pumpEditor, bodies;

void main() {
  final cooking = OfflineCookingService();
  tearDownAll(cooking.dispose);

  Future<void> expectChecked(String source, int checked) async {
    final result = await cooking.cook(
      CookingRequest(
        raw: source,
        configuration: CookingConfiguration(
          modules: [
            CookingModule(
              id: 'checklist',
              owner: 'cooking',
              version: '1',
              enabledSetting: 'checklist_enabled',
            ),
          ],
        ),
        snapshot: CookingSnapshot(
          siteId: 'test-site',
          accountId: 'test-account',
          pluginContext: {
            'cooking': {
              'settings': {'checklist_enabled': true},
            },
          },
        ),
      ),
    );
    expect(result.failure, isNull);
    final cooked = html.parseFragment(result.html);
    expect(
      cooked.querySelectorAll('.chcklst-box.checked'),
      hasLength(checked),
      reason: result.html,
    );
    final todos = composerTodos(source);
    expect(todos.where((todo) => todo.checked), hasLength(checked));
    expect(todos, hasLength(cooked.querySelectorAll('.chcklst-box').length));
  }

  for (final marker in ['x', 'X']) {
    final reference = '[$marker]: https://example.com';
    final done = '- [$marker] Done';
    final codeCases = {
      'root backtick fence': '```\n$reference\n```\n\n$done',
      'root tilde fence': '~~~md\n$reference\n~~~\n\n$done',
      'indented root fence': '   ```\n$reference\n   ```\n\n$done',
      'long fence with shorter interior run':
          '````\n```\n$reference\n````\n\n$done',
      'mismatched interior run': '~~~\n```\n$reference\n~~~\n\n$done',
      'nested fence': '- [ ] Parent\n  ```\n  $reference\n  ```\n$done',
      'deeply nested fence':
          '- [ ] Parent\n  - [ ] Child\n    ~~~\n    $reference\n    ~~~\n$done',
      'ordered list fence': '1. Parent\n   ```\n   $reference\n   ```\n\n$done',
      'fence on the list opening line': '- ```\n  $reference\n  ```\n\n$done',
      'unclosed nested fence ends with the item':
          '- Parent\n  ```\n  $reference\n\n$done',
      'root indented code': '    $reference\n\n$done',
      'root tab-indented code': '\t$reference\n\n$done',
      'nested indented code': '- Parent\n\n      $reference\n\n$done',
      'nested indented code with literal fences':
          '- Parent\n\n      ```\n      $reference\n      ```\n\n$done',
    };
    for (final entry in codeCases.entries) {
      test('reference-like ${entry.key} leaves [$marker] checked', () async {
        expect(composerTaskReferences(entry.value), isEmpty);
        await expectChecked(entry.value, 1);
      });
    }

    final linkCases = {
      'definition before the list': '$reference\n\n$done',
      'definition after another label': '[other]: /path\n$reference\n\n$done',
      'definition after the list': '$done\n\n$reference',
      'definition also applies to nested tasks':
          '- [ ] Parent\n  $done\n\n$reference',
      'definition inside a list applies to siblings':
          '- Parent\n\n  $reference\n\n$done',
      'deep definition applies document-wide':
          '- Parent\n  - Child\n\n    $reference\n\n$done',
      'definition on the list opening line': '- $reference\n\n$done',
      'definition after a fence': '```\n$reference\n```\n$reference\n\n$done',
      'definition with a title':
          '$done\n\n[$marker]: <https://example.com> "Link"',
      'case-insensitive label':
          '$done\n\n[${marker == 'x' ? 'X' : 'x'}]: /path',
    };
    for (final entry in linkCases.entries) {
      test('real ${entry.key} keeps [$marker] a link', () async {
        expect(composerTaskReferences(entry.value), {'[x]'});
        await expectChecked(entry.value, 0);
      });
    }
  }

  test(
    'CRLF fences preserve checked markers in standalone and list tasks',
    () async {
      const source =
          '```\r\n[x]: https://example.com\r\n```\r\n\r\n'
          '[x] Standalone\r\n\r\n- [X] Done';
      expect(composerTaskReferences(source), isEmpty);
      await expectChecked(source, 2);
    },
  );

  test(
    'reference-like code preserves every checklist marker variant',
    () async {
      const source =
          '```\n[ ]: https://example.com\n[]: https://example.com\n```\n\n'
          '- [ ] Open\n- [] Empty\n- [x] Done\n- [X] Permanent';
      expect(composerTaskReferences(source), isEmpty);
      await expectChecked(source, 2);
    },
  );

  test('task text does not introduce a document-wide definition', () {
    const source = '- [ ] [x]: https://example.com\n  - [x] Child\n- [X] Done';
    expect(composerTaskReferences(source), isEmpty);
    expect(composerTodos(source).where((todo) => todo.checked), hasLength(2));
  });

  for (final source in [
    '```\n[x]: https://example.com\n```\n\n- [x] Done',
    '- [ ] Parent\n  ```\n  [x]: https://example.com\n  ```\n- [X] Done',
    '- [ ] Parent\n\n      [x]: https://example.com\n\n- [x] Done',
  ]) {
    testWidgets('editor retains, toggles and undoes checked task: $source', (
      tester,
    ) async {
      final root = await pumpEditor(tester, source);
      addTearDown(() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
      final done = bodies(tester).last;
      expect(done.item.checked, isTrue);
      expect(done.text.text, 'Done');
      expect(
        tester
            .widgetList<DCheckbox>(find.byType(DCheckbox))
            .where((box) => box.value == true),
        hasLength(1),
      );
      done.toggle();
      await tester.pumpAndSettle();
      expect(
        root.text.text,
        source.replaceFirst(RegExp(r'\[[xX]\] Done'), '[ ] Done'),
      );
      root.history.undo();
      await tester.pumpAndSettle();
      expect(root.text.text, source);
      expect(bodies(tester).last.item.checked, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('editor propagates a real nested definition document-wide', (
    tester,
  ) async {
    const source =
        '- Parent\n\n  [x]: https://example.com\n\n- [X] Link\n- [ ] Open';
    final root = await pumpEditor(tester, source);
    addTearDown(() async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    expect(find.byType(DCheckbox), findsOneWidget);
    expect(bodies(tester).where((body) => body.item.checked), isEmpty);
    expect(bodies(tester)[1].text.text, '[X] Link');
    expect(root.text.text, source);
    expect(tester.takeException(), isNull);
  });
}
