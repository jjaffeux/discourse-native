import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_list_source.dart';
import 'package:discourse_native/src/shell/composer_todos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_list_items_test.dart' show pumpEditor, bodies;

void main() {
  const source = '- [ ] Visible\n\n<!--\n- [ ] Hidden\n-->';

  for (final newline in ['\n', '\r\n']) {
    for (final (label, input, expected) in [
      ('audit reproduction', source, ['Visible']),
      (
        'multiline lists and standalone markers',
        '<!--\n- [ ] Hidden\n1. [x] Hidden\n[x] Hidden\n- Bullet\n-->\n- [ ] Visible',
        ['Visible'],
      ),
      (
        'inline opener in prose',
        'Text <!--\n[x] Hidden\n--> text\n\n- [ ] Visible',
        ['Visible'],
      ),
      (
        'inline opener in a task body',
        '- [ ] Before <!--\n  [x] Hidden\n  --> tail\n- [ ] Visible',
        ['Before <!--', 'Visible'],
      ),
      (
        'same line comments',
        '<!-- - [ ] Hidden -->\n- [ ] Visible <!-- hidden -->\n- [x] After',
        ['Visible <!-- hidden -->', 'After'],
      ),
      (
        'multiple comments on one line',
        'Text <!-- first --> <!--\n[x] Hidden\n-->\n- [ ] Visible',
        ['Visible'],
      ),
      (
        'unclosed block comment',
        '- [ ] Visible\n\n<!--\n- [ ] Hidden',
        ['Visible'],
      ),
      (
        'fences inside comments do not hide later standalone tasks',
        '<!--\n```\n- [ ] Hidden\n-->\n[ ] Visible',
        ['Visible'],
      ),
      (
        'comment close inside apparent inline code',
        '<!-- `-->`\n- [ ] Visible\n<!--\n- [ ] Hidden\n-->',
        ['Visible'],
      ),
      (
        'nested comments preserve real children',
        '- [ ] Parent\n  <!--\n  - [ ] Hidden\n  -->\n  - [x] Child\n    <!--\n    - [ ] Hidden too\n    -->\n    - [ ] Grandchild\n- [ ] Visible',
        ['Parent', 'Child', 'Grandchild', 'Visible'],
      ),
    ]) {
      test('$label with ${newline.length}-character newlines', () {
        final text = input.replaceAll('\n', newline);
        expect(
          composerTodos(
            text,
          ).map((todo) => text.substring(todo.contentStart, todo.end)),
          expected,
        );
        void verify(ComposerListItem item) {
          expect(item.body.replace(item.body.text), item.source);
          for (var i = 0; i <= item.body.text.length; i++) {
            expect(item.body.localOffset(item.body.sourceOffset(i)), i);
          }
          for (final child in item.children) {
            verify(child);
          }
        }

        for (final item in composerListItems(text)) {
          verify(item);
        }
      });
    }
  }

  for (final literal in [
    '```html\n<!--\n```',
    '~~~html\n<!--\n~~~',
    '    <!--',
    '\t<!--',
    '`<!--`',
    '``<!-- ` text``',
    '`multiline\ntext <!--\ncode`',
    '-     <!--',
    r'\<!--',
    '- ```html\n  <!--\n  ```',
    '- Parent\n  ```html\n  <!--\n  ```',
    '- Parent\n  - Child\n    ```html\n    <!--\n    ```',
    '- Parent\n\n      <!--',
  ]) {
    test('literal comment opener does not hide following tasks: $literal', () {
      final text = '[x] Standalone\n\n$literal\n\n- [ ] Visible';
      expect(
        composerTodos(
          text,
        ).map((todo) => text.substring(todo.contentStart, todo.end)),
        ['Standalone', 'Visible'],
      );
    });
  }

  for (final text in [
    'Text <!--\n- [ ] Visible\n--> tail',
    'Text <!-- unclosed\n- [ ] Visible',
    'Text <!--\n\n- [ ] Visible\n-->',
    '- [ ] Parent <!--\n  - [ ] Visible\n  --> tail',
  ]) {
    test('interrupted inline comments remain literal: $text', () {
      expect(composerTodos(text).last.contentStart, text.indexOf('Visible'));
    });
  }

  test('a block comment interrupts an unfinished inline code span', () {
    const text = '`multiline\n<!--\ncode`\n\n- [ ] Hidden';
    expect(composerListItems(text), isEmpty);
    expect(composerTodos(text), isEmpty);
  });

  test('dedenting from list code restores comment recognition', () {
    const text = '- ```\n  code\n\n<!--\n- [ ] Hidden\n-->\n- [ ] Visible';
    expect(
      composerTodos(
        text,
      ).map((todo) => text.substring(todo.contentStart, todo.end)),
      ['Visible'],
    );
  });

  test(
    'ordinary lists exclude commented bullets and retain original offsets',
    () {
      const text = '- Before\n\n<!--\n- Hidden\n1. Hidden\n-->\n- After';
      final items = composerListItems(text);
      expect(items.map((item) => item.body.text), ['Before', 'After']);
      expect(items.last.start, text.indexOf('- After'));
      expect(items.last.body.sourceOffset(3), text.indexOf('After') + 3);
    },
  );

  for (final (label, text, count) in [
    ('audit reproduction', source, 1),
    ('standalone markers', '[ ] Visible\n\n<!--\n[x] Hidden\n-->', 1),
    (
      'nested tasks',
      '- [ ] Parent\n  <!--\n  - [ ] Hidden\n  -->\n  - [x] Child',
      2,
    ),
  ]) {
    testWidgets('HTML-commented tasks are not editable checkboxes: $label', (
      tester,
    ) async {
      final root = await pumpEditor(tester, text);
      addTearDown(() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
      expect(find.byType(DCheckbox), findsNWidgets(count));
      expect(root.text.text, text);
      if (label == 'standalone markers') return;
      expect(
        bodies(tester).where((body) => body.item.isTask),
        hasLength(count),
      );
      final task = bodies(tester).last;
      final original = root.text.text;
      task.text.value = task.text.value.copyWith(
        text: '${task.text.text} edited',
        selection: TextSelection.collapsed(offset: task.text.text.length + 7),
      );
      await tester.pumpAndSettle();
      final edited = label == 'audit reproduction'
          ? original.replaceFirst('Visible', 'Visible edited')
          : '$original edited';
      expect(root.text.text, edited);
      bodies(tester).last.toggle();
      await tester.pumpAndSettle();
      expect(
        root.text.text,
        label == 'audit reproduction'
            ? edited.replaceFirst('- [ ] Visible', '- [x] Visible')
            : edited.replaceFirst('- [x] Child', '- [ ] Child'),
      );
      root.history.undo();
      await tester.pumpAndSettle();
      expect(root.text.text, edited);
      expect(tester.takeException(), isNull);
    });
  }
}
