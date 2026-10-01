import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_list_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_list_items_test.dart' show pumpEditor, bodies;

Future<ComposerController> _pumpEditor(
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

Future<void> _focusBody(
  WidgetTester tester,
  ComposerListBodyController body,
) async {
  body.text.selection = TextSelection.collapsed(offset: body.text.text.length);
  body.requestFocus();
  await tester.pumpAndSettle();
}

// Read the native value so empty-field sentinels follow the software keyboard
// path instead of replacing the document through its controller.
Future<void> _nativeInsert(WidgetTester tester, String insertion) async {
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

Future<void> _enter(WidgetTester tester, TargetPlatform platform) async {
  if (platform == TargetPlatform.macOS) {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  } else {
    await _nativeInsert(tester, '\n');
  }
}

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    for (final newline in ['\n', '\r\n']) {
      for (final checked in [false, true]) {
        for (final depth in [0, 1, 3]) {
          testWidgets(
            'exiting trailing empty task keeps following typing outside list '
            '($platform, newline ${newline.length}, checked $checked, depth $depth)',
            (tester) async {
              final marker = checked ? '- [x] ' : '- [ ] ';
              final lines = [
                for (var i = 0; i < depth; i++) '${'  ' * i}- [ ] Parent$i',
                '${'  ' * depth}${marker}First',
              ];
              final prefix = '${lines.join(newline)}$newline';
              final source = '$prefix${'  ' * depth}$marker';
              final root = await _pumpEditor(
                tester,
                source,
                platform: platform,
              );
              await _focusBody(tester, bodies(tester).last);
              final history = [source];

              // Each nested Enter outdents once without adding a blank line.
              for (var remaining = depth - 1; remaining >= 0; remaining--) {
                await _enter(tester, platform);
                expect(root.text.text, '$prefix${'  ' * remaining}$marker');
                expect(bodies(tester).last.focus.hasPrimaryFocus, isTrue);
                history.add(root.text.text);
              }

              await _enter(tester, platform);
              expect(root.text.text, '$prefix$newline');
              expect(root.focus.hasPrimaryFocus, isTrue);
              expect(
                root.text.selection,
                TextSelection.collapsed(offset: root.text.text.length),
              );
              history.add(root.text.text);
              await _nativeInsert(tester, 'Paragraph');
              expect(root.text.text, '$prefix${newline}Paragraph');
              expect(bodies(tester).last.text.text, 'First');
              expect(root.focus.hasPrimaryFocus, isTrue);

              // Typing, the final exit, and every outdent are separate edits.
              for (final before in history.reversed) {
                expect(root.history.undo(), isTrue);
                await tester.pumpAndSettle();
                expect(root.text.text, before);
              }
              for (final after in [
                ...history.skip(1),
                '$prefix${newline}Paragraph',
              ]) {
                expect(root.history.redo(), isTrue);
                await tester.pumpAndSettle();
                expect(root.text.text, after);
              }
              expect(tester.takeException(), isNull);
            },
            variant: TargetPlatformVariant.only(platform),
          );
        }
      }
    }
  }

  for (final newline in ['\n', '\r\n']) {
    for (final checked in [false, true]) {
      for (final lead in [
        '',
        'Introduction$newline$newline',
        '- [x] First$newline$newline',
        '- [x] First$newline$newline$newline',
      ]) {
        testWidgets(
          'empty task exit preserves existing separation '
          '(newline ${newline.length}, checked $checked, lead ${lead.length})',
          (tester) async {
            final source = '$lead- [${checked ? 'x' : ' '}] ';
            final root = await _pumpEditor(tester, source);
            await _focusBody(tester, bodies(tester).last);
            await _nativeInsert(tester, '\n');
            expect(root.text.text, lead);
            expect(root.focus.hasPrimaryFocus, isTrue);
            await _nativeInsert(tester, 'Paragraph');
            expect(root.text.text, '${lead}Paragraph');
            expect(root.history.undo(), isTrue);
            await tester.pumpAndSettle();
            expect(root.text.text, lead);
            expect(root.history.undo(), isTrue);
            await tester.pumpAndSettle();
            expect(root.text.text, source);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
