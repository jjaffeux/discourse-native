import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_list_editor.dart';
import 'package:discourse_native/src/shell/composer_todos.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_list_items_test.dart' show pumpEditor, bodies;

Future<ComposerController> selectionEditor(
  WidgetTester tester,
  String source,
  TargetPlatform platform,
) async {
  final root = await pumpEditor(tester, source, platform: platform);
  addTearDown(() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  return root;
}

Future<void> focusSelection(
  WidgetTester tester,
  ComposerListBodyController body,
  TextSelection selection,
) async {
  body.text.selection = selection;
  body.requestFocus();
  await tester.pumpAndSettle();
}

TextEditingValue replaceSelection(TextEditingValue before, String insertion) =>
    TextEditingValue(
      text: before.text.replaceRange(
        before.selection.start,
        before.selection.end,
        insertion,
      ),
      selection: TextSelection.collapsed(
        offset: before.selection.start + insertion.length,
      ),
    );

Future<void> nativeReturn(WidgetTester tester) async {
  final before = TextEditingValue.fromJSON(tester.testTextInput.editingState!);
  tester.testTextInput.updateEditingValue(replaceSelection(before, '\n'));
  await tester.pumpAndSettle();
}

void main() {
  for (final reversed in [false, true]) {
    for (final prefix in ['- [ ] ', '- [x] ', '[X] ']) {
      test('formatter replaces selected text with Return: $prefix '
          'reversed=$reversed', () {
        final start = prefix.length + 5;
        final end = prefix.length + 11;
        final before = TextEditingValue(
          text: '${prefix}AlphaMiddleOmega',
          selection: TextSelection(
            baseOffset: reversed ? end : start,
            extentOffset: reversed ? start : end,
          ),
        );
        final nextPrefix = prefix.replaceFirst(RegExp(r'\[[ xX]?\]'), '[ ]');
        expect(
          const ComposerTodoInputFormatter().formatEditUpdate(
            before,
            replaceSelection(before, '\n'),
          ),
          TextEditingValue(
            text: '${prefix}Alpha\n${nextPrefix}Omega',
            selection: TextSelection.collapsed(
              offset: prefix.length + 6 + nextPrefix.length,
            ),
          ),
        );
      });
    }
  }

  test('formatter exits a task after replacing its whole body with Return', () {
    const before = TextEditingValue(
      text: '- [x] Alpha',
      selection: TextSelection(baseOffset: 6, extentOffset: 11),
    );
    expect(
      const ComposerTodoInputFormatter().formatEditUpdate(
        before,
        replaceSelection(before, '\n'),
      ),
      const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      ),
    );
  });

  test('formatter preserves nested indentation and CRLF with a selection', () {
    const source = '- [ ] Parent\r\n  - [X] AlphaMiddleOmega';
    final start = source.indexOf('Middle');
    final before = TextEditingValue(
      text: source,
      selection: TextSelection(baseOffset: start + 6, extentOffset: start),
    );
    const expected = '- [ ] Parent\r\n  - [X] Alpha\r\n  - [ ] Omega';
    expect(
      const ComposerTodoInputFormatter().formatEditUpdate(
        before,
        replaceSelection(before, '\r\n'),
      ),
      TextEditingValue(
        text: expected,
        selection: TextSelection.collapsed(offset: expected.indexOf('Omega')),
      ),
    );
  });

  test(
    'formatter leaves other selected replacements and composition intact',
    () {
      const before = TextEditingValue(
        text: '- [x] AlphaMiddleOmega',
        selection: TextSelection(baseOffset: 11, extentOffset: 17),
      );
      const formatter = ComposerTodoInputFormatter();
      for (final insertion in ['', 'New', '\nPasted']) {
        final after = replaceSelection(before, insertion);
        expect(formatter.formatEditUpdate(before, after), after);
      }
      final composing = before.copyWith(
        composing: const TextRange(start: 11, end: 17),
      );
      final after = replaceSelection(before, '\n');
      expect(formatter.formatEditUpdate(composing, after), after);
      final afterComposing = after.copyWith(
        composing: const TextRange(start: 11, end: 12),
      );
      expect(
        formatter.formatEditUpdate(before, afterComposing),
        afterComposing,
      );
    },
  );

  testWidgets('formatter Shift Return keeps selected text in the task body', (
    tester,
  ) async {
    const before = TextEditingValue(
      text: '- [x] AlphaMiddleOmega',
      selection: TextSelection(baseOffset: 17, extentOffset: 11),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final after = const ComposerTodoInputFormatter().formatEditUpdate(
      before,
      replaceSelection(before, '\n'),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(
      after,
      const TextEditingValue(
        text: '- [x] Alpha\n  Omega',
        selection: TextSelection.collapsed(offset: 14),
      ),
    );
  });

  for (final newline in ['\n', '\r\n']) {
    testWidgets('selected Return spans a nested continuation '
        'newline=${newline.length}', (tester) async {
      final source =
          '- [ ] Parent$newline  - [x] AlphaMiddle$newline    TailOmega';
      final root = await selectionEditor(
        tester,
        source,
        TargetPlatform.android,
      );
      await focusSelection(
        tester,
        bodies(tester).last,
        const TextSelection(baseOffset: 16, extentOffset: 5),
      );
      await nativeReturn(tester);
      expect(
        root.text.text,
        '- [ ] Parent$newline  - [x] Alpha$newline  - [ ] Omega',
      );
      expect(root.activeEditor.text.text, 'Omega');
      expect(
        root.activeEditor.text.selection,
        const TextSelection.collapsed(offset: 0),
      );
      root.history.undo();
      await tester.pumpAndSettle();
      expect(root.text.text, source);
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    for (final depth in [0, 1, 3]) {
      for (final wholeBody in [false, true]) {
        for (final reversed in [false, true]) {
          testWidgets('selected Return on $platform depth=$depth '
              'wholeBody=$wholeBody reversed=$reversed', (tester) async {
            final ancestors = [
              for (var i = 0; i < depth; i++) '${'  ' * i}- [ ] Parent$i',
            ];
            final indent = '  ' * depth;
            final source = [
              ...ancestors,
              '$indent- [x] AlphaMiddleOmega',
            ].join('\n');
            final root = await selectionEditor(tester, source, platform);
            final start = wholeBody ? 0 : 5;
            final end = wholeBody ? 16 : 11;
            final selection = TextSelection(
              baseOffset: reversed ? end : start,
              extentOffset: reversed ? start : end,
            );
            await focusSelection(tester, bodies(tester).last, selection);
            if (platform == TargetPlatform.macOS) {
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
              await tester.pumpAndSettle();
            } else {
              await nativeReturn(tester);
            }
            final expected = wholeBody
                ? depth == 0
                      ? ''
                      : [...ancestors, '${'  ' * (depth - 1)}- [x] '].join('\n')
                : [
                    ...ancestors,
                    '$indent- [x] Alpha',
                    '$indent- [ ] Omega',
                  ].join('\n');
            expect(root.text.text, expected);
            expect(root.activeEditor.text.text, wholeBody ? '' : 'Omega');
            expect(
              root.activeEditor.text.selection,
              const TextSelection.collapsed(offset: 0),
            );
            expect(root.activeEditor.focus.hasPrimaryFocus, isTrue);
            if (!wholeBody) {
              expect(bodies(tester).last.item.checked, isFalse);
              expect(bodies(tester)[depth].item.checked, isTrue);
            }
            root.history.undo();
            await tester.pumpAndSettle();
            expect(
              root.text.text,
              source,
              reason: 'One undo restores the edit',
            );
            root.history.redo();
            await tester.pumpAndSettle();
            expect(root.text.text, expected);
            expect(tester.takeException(), isNull);
          }, variant: TargetPlatformVariant.only(platform));
        }
      }
    }
  }

  for (final nested in [false, true]) {
    testWidgets('Shift Return replaces selected text with a continuation '
        'nested=$nested', (tester) async {
      final prefix = nested ? '- [ ] Parent\n  ' : '';
      final indent = nested ? '  ' : '';
      final source = '$prefix- [x] AlphaMiddleOmega';
      final root = await selectionEditor(tester, source, TargetPlatform.macOS);
      await focusSelection(
        tester,
        bodies(tester).last,
        const TextSelection(baseOffset: 11, extentOffset: 5),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(root.text.text, '$prefix- [x] Alpha\n$indent  Omega');
      expect(root.activeEditor.text.text, 'Alpha\nOmega');
      expect(
        root.activeEditor.text.selection,
        const TextSelection.collapsed(offset: 6),
      );
      root.history.undo();
      await tester.pumpAndSettle();
      expect(root.text.text, source);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
}
