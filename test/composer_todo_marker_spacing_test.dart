import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_list_source.dart';
import 'package:discourse_native/src/shell/composer_todos.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_list_items_test.dart' show bodies, pumpEditor;

Future<ComposerController> spacingEditor(
  WidgetTester tester,
  String source, {
  TargetPlatform platform = TargetPlatform.android,
}) async {
  final root = await pumpEditor(tester, source, platform: platform);
  addTearDown(() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  return root;
}

void main() {
  for (final marker in ['[ ]', '[x]', '[X]', '[]']) {
    for (final prefix in ['', '- ', '+ ', '* ', '1. ']) {
      test('adjacent task text is lossless for $prefix$marker', () {
        final source = '$prefix${marker}Task';
        final todo = composerTodos(source).single;
        expect(todo.markerStart, prefix.length);
        expect(todo.contentStart, prefix.length + marker.length);
        expect(source.substring(todo.contentStart, todo.end), 'Task');
        expect(todo.checked, marker.toLowerCase() == '[x]');
        if (prefix.isNotEmpty) {
          final item = composerListItems(source).single;
          expect(item.isTask, isTrue);
          expect(item.taskMarker, marker);
          expect(item.body.text, 'Task');
          expect(item.body.replace('Task'), source);
          expect(item.body.replace('Edited'), '$prefix${marker}Edited');
          for (var offset = 0; offset <= item.body.text.length; offset++) {
            expect(item.body.sourceOffset(offset), todo.contentStart + offset);
            expect(item.body.localOffset(todo.contentStart + offset), offset);
          }
        }
      });
    }
  }

  for (final newline in ['\n', '\r\n']) {
    test('nested adjacent markers preserve offsets with ${newline.length}', () {
      final source = [
        '- [ ]Parent',
        '  - []Child',
        '    continued',
        '    - [x]Grandchild',
      ].join(newline);
      final todos = composerTodos(source);
      expect(
        todos.map((todo) => source.substring(todo.contentStart, todo.end)),
        ['Parent', 'Child', 'Grandchild'],
      );
      final parent = composerListItems(source).single;
      final child = parent.children.single;
      expect(parent.body.replace(parent.body.text), source);
      expect(child.body.text, 'Child\ncontinued\n- [x]Grandchild');
      expect(
        parent.body.sourceOffset(child.contentStart),
        source.indexOf('Child'),
      );
      expect(
        parent.body.replace(parent.body.text.replaceFirst('Child', 'Edited')),
        source.replaceFirst('Child', 'Edited'),
      );
    });
  }

  // These distinctions come from the bundled checklist cooker: Markdown link
  // rules consume valid links first; punctuation alone does not disqualify a
  // checkbox candidate.
  for (final prefix in ['', '- ']) {
    for (final source in [
      '[x](https://example.test)',
      '[](https://example.test)',
      '[ ]()',
      '[x](https://example.test/a_(b) "Title")',
      '[x](<https://example.test> \'Title\')',
      '[x](<https://example.test/a b>)',
      r'[x](https://example.test/a\)b)',
      '[x](\nhttps://example.test\n)',
      '[x][ref]\n\n[ref]: https://example.test',
      '[x][]\n\n[x]: https://example.test',
      '[x]Done\n\n[x]: https://example.test',
      r'\[x]Escaped',
      r'[x\]Escaped',
      '`[x]Code`',
    ]) {
      test('keeps links and literal syntax intact: $prefix$source', () {
        expect(composerTodos('$prefix$source'), isEmpty);
        if (prefix.isNotEmpty) {
          expect(composerListItems('$prefix$source').first.isTask, isFalse);
        }
      });
    }
    for (final body in [
      '(unfinished',
      '(two words)',
      '(\n\nhttps://example.test)',
      '[missing]',
      '**Bold**',
      '`code`',
      '(javascript:alert(1))',
      '(java&#115;cript:alert(1))',
      r'(javascript\:alert(1))',
      ' (https://example.test)',
      ' [ref]\n\n[ref]: https://example.test',
    ]) {
      test('keeps valid adjacent task content: $prefix[x]$body', () {
        final source = '$prefix[x]$body';
        expect(composerTodos(source), hasLength(1));
        if (prefix.isNotEmpty) {
          expect(composerListItems(source).first.isTask, isTrue);
        }
      });
    }
  }

  test('fenced and indented adjacent markers stay literal', () {
    for (final source in [
      '```md\n- [ ]Task\n[x]Done\n```',
      '    - [ ]Task',
      '    [x]Done',
      '-     [x]Code',
    ]) {
      expect(composerTodos(source), isEmpty, reason: source);
    }
  });

  test('nested full reference links inherit document definitions', () {
    const source = '- [ ]Parent\n  - [x][ref]\n\n[ref]: https://example.test';
    final parent = composerListItems(source).single;
    expect(parent.isTask, isTrue);
    expect(parent.children.single.isTask, isFalse);
    expect(composerTodos(source), hasLength(1));
  });

  for (final source in [
    '```\n[ref]: /target\n```\n\n- [x][ref]',
    '    [ref]: /target\n\n- [x][ref]',
    '- Parent\n  ```\n  [ref]: /target\n  ```\n\n- [x][ref]',
    '- [x][missing]\n\n[x]: /target',
  ]) {
    test('adjacent labels respect reference definition scope: $source', () {
      expect(composerTodos(source).single.checked, isTrue);
    });
  }

  testWidgets('nested adjacent tasks edit and toggle their own source', (
    tester,
  ) async {
    const source = '- [ ]Parent\r\n  - []Child\r\n  - [x]Sibling';
    final root = await spacingEditor(tester, source);
    final child = bodies(tester)[1];
    child.text.text = 'Edited';
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DCheckbox).at(1));
    await tester.pumpAndSettle();
    expect(root.text.text, '- [ ]Parent\r\n  - [x]Edited\r\n  - [x]Sibling');
    expect(tester.takeException(), isNull);
  });

  for (final marker in ['[ ]', '[x]', '[X]', '[]']) {
    testWidgets('bare adjacent $marker renders and toggles', (tester) async {
      final root = await spacingEditor(tester, '${marker}Task');
      expect(find.byType(DCheckbox), findsOneWidget);
      await tester.tap(find.byType(DCheckbox));
      await tester.pumpAndSettle();
      final toggled = marker.toLowerCase() == '[x]' ? '[ ]' : '[x]';
      expect(root.text.text, '${toggled}Task');
      expect(tester.takeException(), isNull);
    });
  }

  test('bare adjacent todo Enter splits and continues the task', () {
    const formatter = ComposerTodoInputFormatter();
    for (final marker in ['[ ]', '[x]', '[X]', '[]']) {
      final source = '${marker}AlphaBeta';
      final caret = marker.length + 5;
      final old = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: caret),
      );
      final next = TextEditingValue(
        text: source.replaceRange(caret, caret, '\n'),
        selection: TextSelection.collapsed(offset: caret + 1),
      );
      final result = formatter.formatEditUpdate(old, next);
      expect(result.text, '${marker}Alpha\n[ ] Beta');
      expect(result.selection.extentOffset, caret + 5);
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    for (final marker in ['[ ]', '[x]', '[X]', '[]']) {
      testWidgets(
        'pasted $marker supports edit toggle and Enter on $platform',
        (tester) async {
          final root = await spacingEditor(tester, '', platform: platform);
          await tester.enterText(find.byType(EditableText), '- ${marker}Task');
          await tester.pumpAndSettle();
          var body = bodies(tester).single;
          expect(body.item.isTask, isTrue);
          expect(body.text.text, 'Task');
          expect(find.byType(DCheckbox), findsOneWidget);

          body.text.value = const TextEditingValue(
            text: 'Edited',
            selection: TextSelection.collapsed(offset: 6),
          );
          await tester.pumpAndSettle();
          expect(root.text.text, '- ${marker}Edited');
          await tester.tap(find.byType(DCheckbox));
          await tester.pumpAndSettle();
          final toggled = marker.toLowerCase() == '[x]' ? '[ ]' : '[x]';
          expect(root.text.text, '- ${toggled}Edited');

          body = bodies(tester).single;
          body.text.selection = const TextSelection.collapsed(offset: 3);
          body.requestFocus();
          await tester.pumpAndSettle();
          if (platform == TargetPlatform.macOS) {
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          } else {
            final before = TextEditingValue.fromJSON(
              tester.testTextInput.editingState!,
            );
            tester.testTextInput.updateEditingValue(
              TextEditingValue(
                text: before.text.replaceRange(
                  before.selection.start,
                  before.selection.end,
                  '\n',
                ),
                selection: TextSelection.collapsed(
                  offset: before.selection.start + 1,
                ),
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(root.text.text, '- ${toggled}Edi\n- [ ] ted');
          expect(bodies(tester).map((body) => body.text.text), ['Edi', 'ted']);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
