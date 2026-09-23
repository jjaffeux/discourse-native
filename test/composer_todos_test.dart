import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_blocks.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_todos.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue valueAt(String source) {
  final caret = source.indexOf('|');
  return TextEditingValue(
    text: source.replaceFirst('|', ''),
    selection: TextSelection.collapsed(offset: caret),
  );
}

void main() {
  test('recognizes upstream states and keeps code and links literal', () {
    const source =
        '[ ] Open\n[x] Done\n[X] Permanent\n[] Empty\n- [ ] Bullet\n'
        '    [ ] Code\n`[x] inline`\n\\[ ] Escaped\n[x](https://example.com)\n'
        '```\n[ ] Fenced\n```';
    final todos = composerTodos(source);
    expect(todos.map((todo) => todo.checked), [
      false,
      true,
      true,
      false,
      false,
    ]);
    expect(todos.map((todo) => source.substring(todo.contentStart, todo.end)), [
      'Open',
      'Done',
      'Permanent',
      'Empty',
      'Bullet',
    ]);
    expect(composerTodos('[x] Reference\n\n[x]: https://example.com'), isEmpty);
  });

  test(
    'insertion preserves current text and does not duplicate an existing item',
    () {
      for (final (before, after) in [
        ('|', '- [ ] |'),
        ('Before\n\nDo this|', 'Before\n\n- [ ] Do this|'),
        ('## Heading|', '- [ ] Heading|'),
        ('- Bullet|', '- [ ] Bullet|'),
        ('[x] Done|', '[x] Done|'),
      ]) {
        expect(insertComposerTodo(valueAt(before)), valueAt(after));
      }
    },
  );

  test(
    'marker shortcuts leave code, escapes, references, paste and IME intact',
    () {
      const formatter = ComposerTodoInputFormatter();
      for (final before in [
        '    [x|',
        '```\n[x|',
        '\\[x|',
        'Text [x|',
        '[x|\n\n[x]: https://example.com',
      ]) {
        final old = valueAt(before);
        final caret = old.selection.extentOffset;
        final next = TextEditingValue(
          text: old.text.replaceRange(caret, caret, ']'),
          selection: TextSelection.collapsed(offset: caret + 1),
        );
        expect(formatter.formatEditUpdate(old, next), next);
      }
      final paste = valueAt('[x](https://example.com)|');
      expect(formatter.formatEditUpdate(valueAt('|'), paste), paste);
      final composing = valueAt(
        '[x]|',
      ).copyWith(composing: const TextRange(start: 0, end: 3));
      expect(formatter.formatEditUpdate(valueAt('[x|'), composing), composing);
    },
  );

  test(
    'Return continues items, splits text, and exits empty items on the same line',
    () {
      const formatter = ComposerTodoInputFormatter();
      for (final (before, after) in [
        ('[ ] First|', '[ ] First\n[ ] |'),
        ('[x] First|', '[x] First\n[ ] |'),
        ('[ ] First| part', '[ ] First\n[ ] | part'),
        ('- [x] First|', '- [x] First\n- [ ] |'),
        ('[ ] First\n[ ] |', '[ ] First\n|'),
        ('[x] |', '|'),
        ('- [x] First\n- [ ] |', '- [x] First\n|'),
        ('[ ] First\n[ ]  \t|', '[ ] First\n|'),
        ('[ ] First\n[ ] |\nAfter', '[ ] First\n|\nAfter'),
      ]) {
        final old = valueAt(before);
        final caret = old.selection.end;
        expect(
          formatter.formatEditUpdate(
            old,
            TextEditingValue(
              text: old.text.replaceRange(caret, caret, '\n'),
              selection: TextSelection.collapsed(offset: caret + 1),
            ),
          ),
          valueAt(after),
          reason: before,
        );
      }
    },
  );

  test(
    'Backspace removes the whole prefix while paste and IME stay intact',
    () {
      const formatter = ComposerTodoInputFormatter();
      final old = valueAt('[ ] |Keep this');
      expect(
        formatter.formatEditUpdate(old, valueAt('[ ]|Keep this')),
        valueAt('|Keep this'),
      );
      final paste = valueAt('[ ] First\nSecond|');
      expect(formatter.formatEditUpdate(valueAt('[ ] |'), paste), paste);
      final composing = valueAt(
        '[ ] 文|',
      ).copyWith(composing: const TextRange(start: 4, end: 5));
      expect(formatter.formatEditUpdate(old, composing), composing);
    },
  );

  test('deleting any part of a rendered todo removes its whole prefix', () {
    const formatter = ComposerTodoInputFormatter();
    for (final prefix in ['[ ] ', '[x] ', '[X] ', '[] ', '- [ ] ', '  [ ] ']) {
      for (final lead in ['', 'Before\n']) {
        final source = '$lead${prefix}Keep\n[ ] Next';
        for (
          var offset = lead.length;
          offset < lead.length + prefix.length;
          offset++
        ) {
          for (final backwards in [false, true]) {
            final old = TextEditingValue(
              text: source,
              selection: TextSelection.collapsed(
                offset: offset + (backwards ? 1 : 0),
              ),
            );
            final next = TextEditingValue(
              text: source.replaceRange(offset, offset + 1, ''),
              selection: TextSelection.collapsed(offset: offset),
            );
            expect(
              formatter.formatEditUpdate(old, next),
              valueAt('$lead|Keep\n[ ] Next'),
              reason: '$prefix at $offset, backwards: $backwards',
            );
          }
        }
      }
    }
  });

  test(
    'an empty checked item remains a movable to-do, not unclosed BBCode',
    () {
      final blocks = ComposerBlockIndex.parse('[x] \n\nAfter');
      expect(blocks.blocks.first.kind, ComposerBlockKind.todo);
      expect(blocks.blocks.first.movable, isTrue);
    },
  );

  Future<ComposerController> pump(
    WidgetTester tester, {
    bool dark = false,
    double scale = 1,
  }) async {
    final composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://example.com',
        topicId: 1,
        slug: 'test',
        topicTitle: 'Test',
      ),
    );
    addTearDown(composer.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
          platform: TargetPlatform.macOS,
        ),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Center(
              child: SizedBox(
                width: 360,
                height: 320,
                child: ComposerEditor(
                  composer: composer,
                  hintText: 'Reply',
                  textStyle: const TextStyle(fontSize: 16),
                  hintStyle: null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return composer;
  }

  testWidgets('todo artwork aligns with text and uses the standard label gap', (
    tester,
  ) async {
    final composer = await pump(tester);
    await tester.enterText(
      find.byType(EditableText),
      'Paragraph\n[ ] Open\n[x] Done',
    );
    await tester.pumpAndSettle();
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final textStart = editable
        .localToGlobal(
          editable.getLocalRectForCaret(const TextPosition(offset: 0)).topLeft,
        )
        .dx;
    final artwork = find.descendant(
      of: find.byType(DCheckbox),
      matching: find.byType(AnimatedContainer),
    );
    expect(artwork, findsNWidgets(2));
    for (final marker in artwork.evaluate()) {
      expect(
        tester.getTopLeft(find.byWidget(marker.widget)).dx,
        closeTo(textStart, 0.1),
      );
    }
    final firstArtwork = tester.getRect(artwork.first);
    final contentStart = editable.localToGlobal(
      editable
          .getBoxesForSelection(
            const TextSelection(baseOffset: 14, extentOffset: 15),
          )
          .first
          .toRect()
          .topLeft,
    );
    expect(contentStart.dx - firstArtwork.right, closeTo(8, 0.1));
    await tester.tap(find.byType(DCheckbox).first);
    await tester.pump();
    expect(composer.text.text, 'Paragraph\n[x] Open\n[x] Done');
  });

  testWidgets('typing after clicking a todo returns keyboard focus to text', (
    tester,
  ) async {
    final composer = await pump(tester);
    await tester.enterText(find.byType(EditableText), '[ ] First\n[ ] Second');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DCheckbox).first);
    await tester.pumpAndSettle();
    expect(composer.text.text, '[x] First\n[ ] Second');

    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    await tester.tapAt(
      editable.localToGlobal(
        editable
            .getLocalRectForCaret(
              TextPosition(offset: composer.text.text.length),
            )
            .center,
      ),
    );
    await tester.pumpAndSettle();
    expect(composer.focus.hasPrimaryFocus, isTrue);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.space), isFalse);
    expect(composer.text.text, '[x] First\n[ ] Second');
    tester.testTextInput.updateEditingValue(valueAt('[x] First\n[ ] Second |'));
    await tester.pump();
    expect(composer.text.value, valueAt('[x] First\n[ ] Second |'));
  });

  for (final query in ['todo', 'checklist', 'checkbox', 'task']) {
    testWidgets('/$query inserts an editable unchecked item', (tester) async {
      final composer = await pump(tester);
      await tester.enterText(find.byType(EditableText), '/$query');
      await tester.pumpAndSettle();
      expect(find.text('To-do list'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(composer.text.text, '- [ ] ');
      expect(composer.text.selection.extentOffset, 6);
      expect(composer.activeEditor.focus.hasPrimaryFocus, isTrue);
      expect(find.byType(DCheckbox), findsOneWidget);
      expect(find.text('To-do'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final marker in ['[]', '[ ]', '[x]']) {
    testWidgets('typing $marker creates an item without a trailing space', (
      tester,
    ) async {
      final composer = await pump(tester);
      await tester.showKeyboard(find.byType(EditableText));

      Future<void> type(String text) async {
        for (final character in text.split('')) {
          final value = composer.activeEditor.text.value;
          final caret = value.selection.extentOffset;
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: value.text.replaceRange(caret, caret, character),
              selection: TextSelection.collapsed(offset: caret + 1),
            ),
          );
          await tester.pumpAndSettle();
        }
      }

      final canonical = marker == '[]' ? '[ ]' : marker;
      for (final prefix in ['', 'Before\n']) {
        composer.text.value = TextEditingValue(
          text: prefix,
          selection: TextSelection.collapsed(offset: prefix.length),
        );
        composer.requestFocus();
        await tester.pumpAndSettle();
        await type(marker);
        expect(composer.text.value, valueAt('$prefix- $canonical |'));
        expect(find.text('To-do'), findsOneWidget);
        expect(
          tester.widget<DCheckbox>(find.byType(DCheckbox)).value,
          marker == '[x]',
        );
        await type('Buy milk');
        expect(composer.text.value, valueAt('$prefix- $canonical Buy milk|'));
        expect(find.byType(DCheckbox), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          composer.text.value,
          valueAt('$prefix- $canonical Buy milk\n- [ ] |'),
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  for (final dark in [false, true]) {
    testWidgets('toggles source, preserves caret, and supports undo ($dark)', (
      tester,
    ) async {
      final composer = await pump(tester, dark: dark);
      await tester.enterText(
        find.byType(EditableText),
        '[ ] Buy milk\n[x] Send mail',
      );
      await tester.pumpAndSettle();
      composer.history.flush();
      final selection = composer.text.selection;
      await tester.tap(find.byType(DCheckbox).first);
      await tester.pumpAndSettle();
      expect(composer.text.text, '[x] Buy milk\n[x] Send mail');
      expect(composer.text.selection, selection);
      expect(
        tester.widget<DCheckbox>(find.byType(DCheckbox).first).value,
        isTrue,
      );
      final context = tester.element(find.byType(ComposerEditor));
      final span = composer.text.buildTextSpan(
        context: context,
        style: const TextStyle(fontSize: 16),
        withComposing: true,
      );
      expect(
        span.toPlainText(includeSemanticsLabels: false).length,
        composer.text.text.length,
      );
      final body = span.children!.whereType<TextSpan>().firstWhere(
        (s) => s.text?.contains('Buy milk') ?? false,
      );
      expect(body.style!.decoration, TextDecoration.lineThrough);
      composer.history.undo();
      await tester.pumpAndSettle();
      expect(composer.text.text, '[ ] Buy milk\n[x] Send mail');
      composer.history.redo();
      await tester.pumpAndSettle();
      expect(composer.text.text, '[x] Buy milk\n[x] Send mail');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('submission locks checkbox changes, including a stale callback', (
    tester,
  ) async {
    final composer = await pump(tester);
    await tester.enterText(find.byType(EditableText), '[ ] First');
    await tester.pumpAndSettle();
    final onChanged = tester
        .widget<DCheckbox>(find.byType(DCheckbox))
        .onChanged!;
    composer.beginSubmit();
    onChanged(true);
    await tester.pumpAndSettle();
    expect(composer.text.text, '[ ] First');
  });

  testWidgets('double Return exits without adding an extra blank line', (
    tester,
  ) async {
    final composer = await pump(tester);
    await tester.enterText(find.byType(EditableText), '[x] First');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(composer.text.value, valueAt('[x] First\n[ ] |'));
    expect(find.byType(DCheckbox), findsNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(composer.text.value, valueAt('[x] First\n|'));
    expect(find.byType(DCheckbox), findsOneWidget);
    tester.testTextInput.updateEditingValue(valueAt('[x] First\nAfter|'));
    await tester.pumpAndSettle();
    expect(composer.text.value, valueAt('[x] First\nAfter|'));
    expect(find.byType(DCheckbox), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Backspace at the item start removes its checklist prefix', (
    tester,
  ) async {
    final composer = await pump(tester);
    await tester.enterText(find.byType(EditableText), '[ ] Keep');
    composer.text.selection = const TextSelection.collapsed(offset: 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(composer.text.text, 'Keep');
  });

  testWidgets(
    'Delete before the checkbox removes the todo and preserves text',
    (tester) async {
      final composer = await pump(tester);
      await tester.enterText(find.byType(EditableText), '[ ] Keep\n[x] Next');
      composer.text.selection = const TextSelection.collapsed(offset: 3);
      composer.history.flush();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(composer.text.value, valueAt('|Keep\n[x] Next'));
      expect(find.byType(DCheckbox), findsOneWidget);
      composer.history.undo();
      await tester.pumpAndSettle();
      expect(composer.text.text, '[ ] Keep\n[x] Next');
      expect(find.byType(DCheckbox), findsNWidgets(2));
    },
  );

  testWidgets(
    'keyboard checkbox toggles undo individually and arrows skip source',
    (tester) async {
      final composer = await pump(tester);
      await tester.enterText(
        find.byType(EditableText),
        '[ ] First\n[ ] Second',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DCheckbox).first);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(composer.text.text, '[ ] First\n[ ] Second');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(composer.text.text, '[x] First\n[ ] Second');
      composer.history.undo();
      await tester.pumpAndSettle();
      expect(composer.text.text, '[ ] First\n[ ] Second');
      composer.focus.requestFocus();
      composer.text.selection = const TextSelection.collapsed(offset: 14);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(composer.text.selection.extentOffset, 9);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(composer.text.selection.extentOffset, 14);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      expect(composer.text.selection.extentOffset, 14);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(composer.text.text, '[ ] First\n[ ] \nSecond');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow scaled editor and cooked rows retain checked state', (
    tester,
  ) async {
    await pump(tester, dark: true, scale: 2);
    await tester.enterText(
      find.byType(EditableText),
      '[ ] A longer task that wraps onto another line\n[x] Done\n[ ] ',
    );
    await tester.pumpAndSettle();
    expect(find.byType(DCheckbox), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: SizedBox(
            width: 320,
            child: CookedHtml(
              html:
                  '<p>Introduction<br><span class="chcklst-box fa fa-square-o"></span> Open<br>'
                  '<span class="chcklst-box checked fa fa-square-check-o"></span> <strong>Done</strong></p>',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<DCheckbox>(find.byType(DCheckbox))
          .map((box) => box.value),
      [false, true],
    );
    expect(tester.takeException(), isNull);
  });
}
