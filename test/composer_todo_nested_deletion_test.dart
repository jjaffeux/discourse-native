import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_list_editor.dart';
import 'package:discourse_native/src/shell/composer_list_source.dart';
import 'package:discourse_native/src/shell/composer_todos.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_list_items_test.dart' show pumpEditor, bodies;

Future<ComposerController> nestedEditor(
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

Future<void> focusBody(
  WidgetTester tester,
  ComposerListBodyController body, {
  int? caret,
  TextSelection? selection,
}) async {
  body.text.selection =
      selection ??
      TextSelection.collapsed(offset: caret ?? body.text.text.length);
  body.requestFocus();
  await tester.pumpAndSettle();
}

// Use the native editing value so empty-field boundary sentinels are handled
// in exactly the same way as software-keyboard text input.
Future<void> nativeInsert(WidgetTester tester, String insertion) async {
  final before = TextEditingValue.fromJSON(tester.testTextInput.editingState!);
  final selection = before.selection;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: before.text.replaceRange(selection.start, selection.end, insertion),
      selection: TextSelection.collapsed(
        offset: selection.start + insertion.length,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final newline in ['\n', '\r\n']) {
    for (final blankIndent in ['', '  ', '   ']) {
      test(
        'deleting an extra blank line preserves child indentation '
        'with newline ${newline.length} and indent ${blankIndent.length}',
        () {
          final source =
              '- [ ] Parent$newline$blankIndent$newline'
              '  - [x] Child$newline    - [ ] Grandchild';
          final item = composerListItems(source).single;
          expect(
            item.body.replace('Parent\n- [x] Child\n  - [ ] Grandchild'),
            '- [ ] Parent$newline  - [x] Child$newline    - [ ] Grandchild',
          );
        },
      );
    }
  }

  for (final newline in ['\n', '\r\n']) {
    test('compact list spacing does not consume the child separator '
        'with newline ${newline.length}', () {
      final source = 'Parent$newline$newline- [x] Child';
      final text = MarkdownEditingController(enableBlockSeparators: true)
        ..compactListSpacing = true
        ..value = TextEditingValue(
          text: source,
          selection: const TextSelection.collapsed(offset: 6),
        );
      addTearDown(text.dispose);
      text.value = TextEditingValue(
        text: source.replaceRange(6, 6 + newline.length, ''),
        selection: const TextSelection.collapsed(offset: 6),
      );
      expect(text.text, 'Parent$newline- [x] Child');
    });
  }

  testWidgets('deletion of first parent body line retains its child task', (
    tester,
  ) async {
    final root = await nestedEditor(tester, '- [ ] Parent\n  - [x] Child');
    await focusBody(
      tester,
      bodies(tester).first,
      selection: const TextSelection(baseOffset: 0, extentOffset: 7),
    );
    await nativeInsert(tester, '');
    expect(root.text.text, '- [ ] \n  - [x] Child');
    expect(composerTodos(root.text.text), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  for (final action in ['delete', 'software delete']) {
    testWidgets('$action cannot flatten a child into parent prose', (
      tester,
    ) async {
      final root = await nestedEditor(tester, '- [ ] Parent\n  - [x] Child');
      await focusBody(tester, bodies(tester).first, caret: 6);
      if (action == 'delete') {
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pumpAndSettle();
      } else {
        final before = TextEditingValue.fromJSON(
          tester.testTextInput.editingState!,
        );
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: before.text.replaceRange(6, 7, ''),
            selection: const TextSelection.collapsed(offset: 6),
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(root.text.text, '- [ ] Parent\n  - [x] Child');
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    for (final newline in ['\n', '\r\n']) {
      for (final selected in [false, true]) {
        for (final hardware in [false, true]) {
          testWidgets(
            'nested boundary preserves descendants, neighbors and undo '
            'on $platform, newline ${newline.length}, '
            'selected $selected, hardware $hardware',
            (tester) async {
              final source = [
                '- [ ] Before',
                '- [ ] Parent',
                '  - [x] Child',
                '    - [ ] Grandchild',
                '  - [ ] Other child',
                '- [x] After',
              ].join(newline);
              final root = await nestedEditor(
                tester,
                source,
                platform: platform,
              );
              final parent = bodies(
                tester,
              ).firstWhere((body) => body.text.text.startsWith('Parent'));
              await focusBody(
                tester,
                parent,
                caret: 6,
                // Also exercise a backwards selection.
                selection: selected
                    ? const TextSelection(baseOffset: 7, extentOffset: 0)
                    : null,
              );
              if (hardware) {
                await tester.sendKeyEvent(LogicalKeyboardKey.delete);
              } else {
                final before = TextEditingValue.fromJSON(
                  tester.testTextInput.editingState!,
                );
                tester.testTextInput.updateEditingValue(
                  TextEditingValue(
                    text: before.text.replaceRange(selected ? 0 : 6, 7, ''),
                    selection: TextSelection.collapsed(
                      offset: selected ? 0 : 6,
                    ),
                  ),
                );
              }
              await tester.pumpAndSettle();
              final expected = selected
                  ? source.replaceFirst('Parent', '')
                  : source;
              expect(root.text.text, expected);
              expect(bodies(tester), hasLength(6));
              final items = composerListItems(root.text.text);
              expect(items, hasLength(3));
              expect(items[1].children, hasLength(2));
              expect(items[1].children.first.checked, isTrue);
              expect(
                items[1].children.first.children.single.body.text,
                'Grandchild',
              );
              expect(
                parent.text.selection,
                TextSelection.collapsed(offset: selected ? 0 : 6),
              );
              expect(root.history.canUndo, selected);

              if (selected) {
                expect(root.history.undo(), isTrue);
                await tester.pumpAndSettle();
                expect(root.text.text, source);
                expect(root.history.redo(), isTrue);
                await tester.pumpAndSettle();
                expect(root.text.text, expected);
              }

              // The preserved descendant must still have its own editable body.
              final child = bodies(
                tester,
              ).firstWhere((body) => body.text.text.startsWith('Child'));
              await focusBody(tester, child, caret: 5);
              await nativeInsert(tester, '!');
              expect(root.text.text, expected.replaceFirst('Child', 'Child!'));
              expect(root.history.undo(), isTrue);
              await tester.pumpAndSettle();
              expect(root.text.text, expected);
              expect(bodies(tester), hasLength(6));
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }

  testWidgets('Backspace selection preserves the boundary at deeper nesting', (
    tester,
  ) async {
    const source = '- [ ] Outer\n  - [ ] Parent\n    - [x] Child';
    final root = await nestedEditor(
      tester,
      source,
      platform: TargetPlatform.macOS,
    );
    final parent = bodies(tester)[1];
    await focusBody(
      tester,
      parent,
      selection: const TextSelection(baseOffset: 0, extentOffset: 7),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(root.text.text, source.replaceFirst('Parent', ''));
    expect(bodies(tester), hasLength(3));
    expect(root.history.undo(), isTrue);
    await tester.pumpAndSettle();
    expect(root.text.text, source);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary parent prose and extra newlines remain deletable', (
    tester,
  ) async {
    final root = await nestedEditor(tester, '- [ ] Parent\n\n  - [x] Child');
    var parent = bodies(tester).first;
    await focusBody(tester, parent, caret: 6);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(root.text.text, '- [ ] Parent\n  - [x] Child');
    parent = bodies(tester).first;
    await focusBody(tester, parent, caret: 5);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(root.text.text, '- [ ] Paren\n  - [x] Child');
    expect(bodies(tester), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting the entire child still removes the child atomically', (
    tester,
  ) async {
    final root = await nestedEditor(tester, '- [ ] Parent\n  - [x] Child');
    final parent = bodies(tester).first;
    await focusBody(
      tester,
      parent,
      selection: TextSelection(
        baseOffset: 6,
        extentOffset: parent.text.text.length,
      ),
    );
    await nativeInsert(tester, '');
    expect(root.text.text, '- [ ] Parent');
    expect(bodies(tester), hasLength(1));
    expect(root.history.undo(), isTrue);
    await tester.pumpAndSettle();
    expect(root.text.text, '- [ ] Parent\n  - [x] Child');
    expect(bodies(tester), hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
