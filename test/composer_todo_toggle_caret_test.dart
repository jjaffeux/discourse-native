import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_list_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_list_items_test.dart' show pumpEditor, bodies;

Future<ComposerController> _pumpEditor(
  WidgetTester tester,
  String source,
) async {
  final root = await pumpEditor(tester, source);
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
  TextSelection selection,
) async {
  body.text.selection = selection;
  body.requestFocus();
  await tester.pumpAndSettle();
}

void main() {
  for (final depth in [0, 1, 3]) {
    for (final checkbox in [false, true]) {
      for (final caret in [0, 2, 5]) {
        testWidgets('shorthand toggle retains caret $caret at depth $depth via '
            '${checkbox ? 'checkbox' : 'controller'} and undo/redo', (
          tester,
        ) async {
          final source = [
            for (var i = 0; i < depth; i++) '${'  ' * i}- [ ] Parent$i',
            '${'  ' * depth}- [] Alpha',
          ].join('\n');
          final root = await _pumpEditor(tester, source);
          final selection = TextSelection.collapsed(offset: caret);
          await _focusBody(tester, bodies(tester).last, selection);
          final before = root.value;

          if (checkbox) {
            await tester.tap(find.byType(DCheckbox).last);
          } else {
            bodies(tester).last.toggle();
          }
          await tester.pumpAndSettle();
          expect(root.text.text, source.replaceFirst('[]', '[x]'));
          expect(
            root.value.selection,
            before.selection.copyWith(
              baseOffset: before.selection.baseOffset + 1,
              extentOffset: before.selection.extentOffset + 1,
            ),
          );
          expect(bodies(tester).last.text.selection, selection);
          if (!checkbox) {
            expect(bodies(tester).last.focus.hasPrimaryFocus, isTrue);
          }

          root.requestFocus();
          await tester.pumpAndSettle();
          expect(bodies(tester).last.text.selection, selection);
          expect(bodies(tester).last.focus.hasPrimaryFocus, isTrue);
          final after = root.value;

          expect(root.history.undo(), isTrue);
          await tester.pumpAndSettle();
          expect(root.value, before);
          root.requestFocus();
          await tester.pumpAndSettle();
          expect(bodies(tester).last.text.selection, selection);

          expect(root.history.redo(), isTrue);
          await tester.pumpAndSettle();
          expect(root.value, after);
          root.requestFocus();
          await tester.pumpAndSettle();
          expect(bodies(tester).last.text.selection, selection);
          expect(bodies(tester).last.focus.hasPrimaryFocus, isTrue);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('shorthand toggle retains backward selection at depth $depth', (
      tester,
    ) async {
      final source = [
        for (var i = 0; i < depth; i++) '${'  ' * i}- [ ] Parent$i',
        '${'  ' * depth}- [] Alpha',
      ].join('\n');
      final root = await _pumpEditor(tester, source);
      const selection = TextSelection(
        baseOffset: 5,
        extentOffset: 1,
        affinity: TextAffinity.upstream,
        isDirectional: true,
      );
      await _focusBody(tester, bodies(tester).last, selection);
      final before = root.value;
      bodies(tester).last.toggle();
      await tester.pumpAndSettle();
      expect(bodies(tester).last.text.selection, selection);
      expect(bodies(tester).last.focus.hasPrimaryFocus, isTrue);
      expect(
        root.value.selection,
        before.selection.copyWith(
          baseOffset: before.selection.baseOffset + 1,
          extentOffset: before.selection.extentOffset + 1,
        ),
      );
      final after = root.value;
      expect(root.history.undo(), isTrue);
      await tester.pumpAndSettle();
      expect(root.value, before);
      expect(bodies(tester).last.text.selection, selection);
      expect(bodies(tester).last.focus.hasPrimaryFocus, isTrue);
      expect(root.history.redo(), isTrue);
      await tester.pumpAndSettle();
      expect(root.value, after);
      expect(bodies(tester).last.text.selection, selection);
      expect(bodies(tester).last.focus.hasPrimaryFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final prefix in ['[]', '- []', '- [ ] Parent\n  - []']) {
    for (final position in ['before', 'after', 'across']) {
      testWidgets('toggle $prefix preserves a document selection $position', (
        tester,
      ) async {
        final source = 'Before\n\n$prefix Alpha\n\nAfter';
        final root = await _pumpEditor(tester, source);
        final selection = TextSelection(
          baseOffset: position == 'before' ? 4 : source.length,
          extentOffset: position == 'after' ? source.length - 3 : 1,
          affinity: TextAffinity.upstream,
          isDirectional: true,
        );
        root.text.selection = selection;
        root.requestFocus();
        await tester.pumpAndSettle();
        final before = root.value;
        final focus = FocusManager.instance.primaryFocus;
        // Invoke the actual Native checkbox callback without moving focus.
        tester.widget<DCheckbox>(find.byType(DCheckbox).last).onChanged!(true);
        await tester.pumpAndSettle();
        expect(root.text.text, source.replaceFirst('[]', '[x]'));
        expect(
          root.value.selection,
          selection.copyWith(
            baseOffset: selection.baseOffset + (position == 'before' ? 0 : 1),
            extentOffset:
                selection.extentOffset + (position == 'after' ? 1 : 0),
          ),
        );
        expect(FocusManager.instance.primaryFocus, same(focus));
        final after = root.value;
        expect(root.history.undo(), isTrue);
        await tester.pumpAndSettle();
        expect(root.value, before);
        expect(root.history.redo(), isTrue);
        await tester.pumpAndSettle();
        expect(root.value, after);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final nested in [false, true]) {
    for (final activeIndex in [0, 1]) {
      for (final selected in [false, true]) {
        testWidgets(
          'toggle retains ${selected ? 'selection' : 'caret'} in sibling '
          '$activeIndex nested=$nested',
          (tester) async {
            final source = nested
                ? '- [ ] Parent\n  - [] First\n  - [] Second'
                : '- [] First\n- [] Second';
            final root = await _pumpEditor(tester, source);
            final selection = TextSelection(
              baseOffset: 4,
              extentOffset: selected ? 1 : 4,
              isDirectional: selected,
            );
            final active = bodies(tester)[activeIndex + (nested ? 1 : 0)];
            await _focusBody(tester, active, selection);
            final before = root.value;
            final toggledIndex = 1 - activeIndex + (nested ? 1 : 0);
            bodies(tester)[toggledIndex].toggle();
            await tester.pumpAndSettle();
            final expected = before.selection.copyWith(
              baseOffset:
                  before.selection.baseOffset + (activeIndex == 1 ? 1 : 0),
              extentOffset:
                  before.selection.extentOffset + (activeIndex == 1 ? 1 : 0),
            );
            expect(root.value.selection, expected);
            expect(active.text.selection, selection);
            expect(active.focus.hasPrimaryFocus, isTrue);
            expect(root.history.undo(), isTrue);
            await tester.pumpAndSettle();
            expect(root.value, before);
            expect(active.text.selection, selection);
            expect(active.focus.hasPrimaryFocus, isTrue);
            expect(root.history.redo(), isTrue);
            await tester.pumpAndSettle();
            expect(root.value.selection, expected);
            expect(active.text.selection, selection);
            expect(active.focus.hasPrimaryFocus, isTrue);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('bare shorthand retains caret through focus and undo/redo', (
    tester,
  ) async {
    final root = await _pumpEditor(tester, '[] Alpha');
    root.requestFocus();
    await tester.pumpAndSettle();
    final before = root.value;
    await tester.tap(find.byType(DCheckbox));
    await tester.pumpAndSettle();
    expect(root.value.text, '[x] Alpha');
    expect(root.value.selection.extentOffset, 9);
    root.requestFocus();
    await tester.pumpAndSettle();
    expect(root.focus.hasPrimaryFocus, isTrue);
    expect(root.value.selection.extentOffset, 9);
    final after = root.value;
    expect(root.history.undo(), isTrue);
    await tester.pumpAndSettle();
    expect(root.value, before);
    expect(root.history.redo(), isTrue);
    await tester.pumpAndSettle();
    expect(root.value, after);
    expect(root.focus.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
