import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_list_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_list_items_test.dart' show pumpEditor, bodies;

Future<ComposerController> slashEditor(
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

Future<void> acceptTodo(WidgetTester tester) async {
  expect(find.text('To-do list'), findsOneWidget);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('slash todo converts an existing bullet', (tester) async {
    final root = await slashEditor(tester, '- Alpha');
    final body = bodies(tester).single;
    await focusBody(tester, body);
    await nativeInsert(tester, ' /todo');
    await acceptTodo(tester);
    expect(root.text.text, '- [ ] Alpha ');
    expect(bodies(tester), hasLength(1));
    expect(bodies(tester).single.focus.hasPrimaryFocus, isTrue);
    expect(bodies(tester).single.text.selection.extentOffset, 6);
  });

  for (final newline in ['\n', '\r\n']) {
    for (final scenario in [
      (
        name: 'bullet with descendants and rich body',
        before:
            '- Alpha **bold**\n  Continued\n\n  Second paragraph\n\n'
            '  ```text\n  [ ] literal\n  ```\n\n'
            '  - [x] Child\n    4. Grandchild\n- Sibling',
        after:
            '- [ ] Alpha | **bold**\n  Continued\n\n  Second paragraph\n\n'
            '  ```text\n  [ ] literal\n  ```\n\n'
            '  - [x] Child\n    4. Grandchild\n- Sibling',
        caret: 5,
      ),
      (
        name: 'ordered item with descendants and paragraphs',
        before:
            '12. Alpha tail\n    Continued\n\n    Second paragraph\n\n'
            '    - [x] Child\n      - Grandchild\n13. Sibling',
        after:
            '- [ ] Alpha | tail\n  Continued\n  \n  Second paragraph\n  \n'
            '  - [x] Child\n    - Grandchild\n13. Sibling',
        caret: 5,
      ),
      (
        name: 'nested bullet under ordered and completed parents',
        before:
            '3. Parent\n   - [x] Middle\n     + Alpha tail\n'
            '       - [ ] Child\n     + Sibling\n4. Outside',
        after:
            '3. Parent\n   - [x] Middle\n     + [ ] Alpha | tail\n'
            '       - [ ] Child\n     + Sibling\n4. Outside',
        caret: 5,
      ),
      (
        name: 'nested ordered item',
        before:
            '- Parent\n  12) Alpha\n      - [x] Child\n'
            '        - Grandchild\n  13) Sibling',
        after:
            '- Parent\n  - [ ] Alpha |\n    - [x] Child\n'
            '      - Grandchild\n  13) Sibling',
        caret: 5,
      ),
      (
        name: 'continuation line converts its owning item',
        before: '12. Alpha\n    Continued tail\n    - Child',
        after: '- [ ] Alpha\n  Continued | tail\n  - Child',
        caret: 'Alpha\nContinued'.length,
      ),
    ]) {
      testWidgets('${scenario.name} preserves caret and undo '
          'with ${newline.length}-character newlines', (tester) async {
        final root = await slashEditor(
          tester,
          scenario.before.replaceAll('\n', newline),
        );
        final body = bodies(
          tester,
        ).singleWhere((body) => body.text.text.startsWith('Alpha'));
        final originalBody = body.text.text;
        final originalBodyCount = bodies(tester).length;
        await focusBody(tester, body, caret: scenario.caret);
        await nativeInsert(tester, ' /todo');
        final queryOffset = root.text.text.indexOf('/todo');
        final beforeConversion = TextEditingValue(
          text: root.text.text.replaceRange(queryOffset, queryOffset + 5, ''),
          selection: TextSelection.collapsed(offset: queryOffset),
        );
        await acceptTodo(tester);

        final expected = scenario.after.replaceAll('\n', newline);
        final converted = TextEditingValue(
          text: expected.replaceFirst('|', ''),
          selection: TextSelection.collapsed(offset: expected.indexOf('|')),
        );
        expect(root.text.text, converted.text);
        expect(root.text.selection, converted.selection);
        expect(bodies(tester), hasLength(originalBodyCount));
        final active = root.activeEditor;
        expect(active, isA<ComposerListBodyController>());
        expect(active.focus.hasPrimaryFocus, isTrue);
        expect(
          active.text.text,
          originalBody.replaceRange(scenario.caret, scenario.caret, ' '),
        );
        expect(active.text.selection.extentOffset, scenario.caret + 1);

        root.history.undo();
        await tester.pumpAndSettle();
        expect(root.text.value, beforeConversion);
        root.history.redo();
        await tester.pumpAndSettle();
        expect(root.text.text, converted.text);
        expect(root.text.selection, converted.selection);

        // Native input must still land at the restored body caret.
        await nativeInsert(tester, 'Z');
        expect(root.text.text, expected.replaceFirst('|', 'Z'));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final marker in ['[ ]', '[]', '[x]', '[X]']) {
    for (final nested in [false, true]) {
      testWidgets('existing $marker todo remains unchanged nested=$nested', (
        tester,
      ) async {
        final source = nested
            ? '- Parent\n  2. $marker Alpha\n     - [x] Child'
            : '- $marker Alpha\n  - [x] Child';
        final root = await slashEditor(tester, source);
        final body = bodies(
          tester,
        ).singleWhere((body) => body.text.text.startsWith('Alpha'));
        final count = bodies(tester).length;
        await focusBody(tester, body, caret: 5);
        await nativeInsert(tester, ' /todo');
        final beforeAcceptance = root.text.value;
        await acceptTodo(tester);
        expect(root.text.text, source.replaceFirst('Alpha', 'Alpha '));
        expect(bodies(tester), hasLength(count));
        expect(body.focus.hasPrimaryFocus, isTrue);
        expect(body.text.selection.extentOffset, 6);
        root.history.undo();
        await tester.pumpAndSettle();
        // An existing task only consumes the query; undo restores that text.
        expect(root.text.value, beforeAcceptance);
        root.history.redo();
        await tester.pumpAndSettle();
        expect(root.text.text, source.replaceFirst('Alpha', 'Alpha '));
        await nativeInsert(tester, 'Z');
        expect(root.text.text, source.replaceFirst('Alpha', 'Alpha Z'));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
