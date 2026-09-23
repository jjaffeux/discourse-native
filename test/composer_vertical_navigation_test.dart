import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_list_items_test.dart' show pumpEditor, bodies, editable;

const desktopPlatforms = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.linux,
  TargetPlatform.windows,
});

Offset caretPosition(WidgetTester tester, ComposerController composer) {
  final render = tester
      .state<EditableTextState>(editable(composer))
      .renderEditable;
  return render.localToGlobal(
    render.getLocalRectForCaret(composer.text.selection.extent).center,
  );
}

Future<void> focusAt(
  WidgetTester tester,
  ComposerController composer,
  int offset,
) async {
  composer.text.selection = TextSelection.collapsed(offset: offset);
  composer.requestFocus();
  await tester.pumpAndSettle();
}

Future<void> arrow(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('native macOS selectors cross the tasks created by Return', (
    tester,
  ) async {
    final root = await pumpEditor(
      tester,
      '- [ ] FirstSecond\r\n  Continued',
      platform: TargetPlatform.macOS,
    );
    await focusAt(tester, bodies(tester).single, 5);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final items = bodies(tester);
    expect(items, hasLength(2));
    expect(items.last.focus.hasPrimaryFocus, isTrue);
    tester
        .state<EditableTextState>(editable(items.last))
        .performSelector('moveUp:');
    await tester.pumpAndSettle();
    expect(items.first.focus.hasPrimaryFocus, isTrue);
    expect(items.first.text.selection.extentOffset, 0);
    await focusAt(tester, items.first, 3);
    tester
        .state<EditableTextState>(editable(items.first))
        .performSelector('moveDown:');
    await tester.pumpAndSettle();
    expect(items.last.focus.hasPrimaryFocus, isTrue);
    expect(items.last.text.selection.extentOffset, 3);
    expect(root.text.text, '- [ ] First\r\n- [ ] Second\r\n  Continued');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('arrows enter explicit empty paragraphs surrounding tasks', (
    tester,
  ) async {
    const source = '\n- [ ] First text\n\n\n- [ ] Final text\n\n';
    final root = await pumpEditor(
      tester,
      source,
      platform: defaultTargetPlatform,
    );
    final items = bodies(tester);
    await focusAt(tester, items.first, 4);
    await arrow(tester, LogicalKeyboardKey.arrowUp);
    expect(root.focus.hasPrimaryFocus, isTrue);
    expect(root.text.selection.extentOffset, 0);
    await arrow(tester, LogicalKeyboardKey.arrowDown);
    expect(items.first.focus.hasPrimaryFocus, isTrue);
    expect(items.first.text.selection.extentOffset, 4);
    await arrow(tester, LogicalKeyboardKey.arrowDown);
    expect(root.focus.hasPrimaryFocus, isTrue);
    expect(root.text.selection.extentOffset, source.indexOf('\n\n\n') + 2);
    await arrow(tester, LogicalKeyboardKey.arrowDown);
    expect(items.last.focus.hasPrimaryFocus, isTrue);
    expect(items.last.text.selection.extentOffset, 4);
    await arrow(tester, LogicalKeyboardKey.arrowDown);
    expect(root.focus.hasPrimaryFocus, isTrue);
    expect(root.text.selection.extentOffset, source.length);
    await arrow(tester, LogicalKeyboardKey.arrowUp);
    expect(items.last.focus.hasPrimaryFocus, isTrue);
    expect(items.last.text.selection.extentOffset, 4);
    expect(root.text.text, source);
  }, variant: desktopPlatforms);

  testWidgets(
    'arrows cross task, list and paragraph boundaries at the same column',
    (tester) async {
      const source =
          'Before text\n\n- [ ] First text\n- Other text\n1. Third text\n\nAfter text';
      final root = await pumpEditor(
        tester,
        source,
        platform: defaultTargetPlatform,
      );
      final items = bodies(tester);
      await focusAt(tester, items.first, 4);
      final x = caretPosition(tester, items.first).dx;
      for (final (key, target) in [
        (LogicalKeyboardKey.arrowDown, items[1]),
        (LogicalKeyboardKey.arrowDown, items.last),
        (LogicalKeyboardKey.arrowDown, root),
        (LogicalKeyboardKey.arrowUp, items.last),
        (LogicalKeyboardKey.arrowUp, items[1]),
        (LogicalKeyboardKey.arrowUp, items.first),
        (LogicalKeyboardKey.arrowUp, root),
        (LogicalKeyboardKey.arrowDown, items.first),
      ]) {
        await arrow(tester, key);
        expect(target.focus.hasPrimaryFocus, isTrue);
        expect(caretPosition(tester, target).dx, closeTo(x, 9));
      }
      expect(root.text.text, source);
    },
    variant: desktopPlatforms,
  );

  testWidgets(
    'held arrows preserve the desired column across short and empty tasks',
    (tester) async {
      const source =
          '- [ ] Long first text\n- [ ] \n- [ ] x\n- [ ] Long final text';
      final root = await pumpEditor(
        tester,
        source,
        platform: defaultTargetPlatform,
      );
      final items = bodies(tester);
      await focusAt(tester, items.first, 8);
      final x = caretPosition(tester, items.first).dx;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(items[1].focus.hasPrimaryFocus, isTrue);
      expect(items[1].text.selection.extentOffset, 0);
      for (final target in items.skip(2)) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(target.focus.hasPrimaryFocus, isTrue);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      expect(caretPosition(tester, items.last).dx, closeTo(x, 1));
      for (final target in items.reversed.skip(1)) {
        await arrow(tester, LogicalKeyboardKey.arrowUp);
        expect(target.focus.hasPrimaryFocus, isTrue);
      }
      expect(items.first.text.selection.extentOffset, 8);
      expect(root.text.text, source);
      expect(tester.takeException(), isNull);
    },
    variant: desktopPlatforms,
  );

  testWidgets(
    'arrows move through wrapped lines before crossing to an adjacent task',
    (tester) async {
      const source =
          '- [ ] A long task that wraps across several visual lines in this narrow editor\n- [ ] Following task';
      final root = await pumpEditor(
        tester,
        source,
        platform: defaultTargetPlatform,
      );
      final items = bodies(tester);
      await focusAt(tester, items.first, 3);
      final start = caretPosition(tester, items.first);
      await arrow(tester, LogicalKeyboardKey.arrowDown);
      expect(items.first.focus.hasPrimaryFocus, isTrue);
      expect(caretPosition(tester, items.first).dy, greaterThan(start.dy));
      expect(caretPosition(tester, items.first).dx, closeTo(start.dx, 1));
      final render = tester
          .state<EditableTextState>(editable(items.first))
          .renderEditable;
      final lastLine = render.getLineAtOffset(
        TextPosition(offset: items.first.text.text.length),
      );
      await focusAt(tester, items.first, lastLine.start + 3);
      final last = caretPosition(tester, items.first);
      await arrow(tester, LogicalKeyboardKey.arrowDown);
      expect(items.last.focus.hasPrimaryFocus, isTrue);
      expect(caretPosition(tester, items.last).dx, closeTo(last.dx, 1));
      await arrow(tester, LogicalKeyboardKey.arrowUp);
      expect(items.first.focus.hasPrimaryFocus, isTrue);
      expect(caretPosition(tester, items.first).dx, closeTo(last.dx, 1));
      expect(caretPosition(tester, items.first).dy, closeTo(last.dy, 1));
      expect(root.text.text, source);
    },
    variant: desktopPlatforms,
  );

  testWidgets('arrows traverse nested tasks and return to their parent prose', (
    tester,
  ) async {
    const source =
        '- [ ] Parent text\n  - [ ] Child text\n    - [ ] Grand text\n\n  Tail text\n- [ ] Sibling text';
    final root = await pumpEditor(
      tester,
      source,
      platform: defaultTargetPlatform,
    );
    final items = bodies(tester);
    expect(items, hasLength(4));
    await focusAt(tester, items.first, 8);
    final x = caretPosition(tester, items.first).dx;
    for (final target in [items[1], items[2], items.first, items.last]) {
      await arrow(tester, LogicalKeyboardKey.arrowDown);
      expect(
        target.focus.hasPrimaryFocus,
        isTrue,
        reason:
            'Expected ${target.text.text}; active: ${root.activeEditor.text.value}',
      );
      expect(caretPosition(tester, target).dx, closeTo(x, 9));
      if (identical(target, items.first)) {
        expect(
          target.text.selection.extentOffset,
          greaterThanOrEqualTo(target.text.text.indexOf('Tail')),
        );
      }
    }
    for (final target in [items.first, items[2], items[1], items.first]) {
      await arrow(tester, LogicalKeyboardKey.arrowUp);
      expect(target.focus.hasPrimaryFocus, isTrue);
    }
    expect(items.first.text.selection.extentOffset, 8);
    expect(root.text.text, source);
  }, variant: desktopPlatforms);

  testWidgets(
    'arrows leave selection extension and document edges to the text field',
    (tester) async {
      const source = '- [ ] First text\n- [ ] Final text';
      final root = await pumpEditor(
        tester,
        source,
        platform: defaultTargetPlatform,
      );
      final items = bodies(tester);
      await focusAt(tester, items.first, 4);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await arrow(tester, LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(items.first.focus.hasPrimaryFocus, isTrue);
      expect(items.first.text.selection.isCollapsed, isFalse);
      await focusAt(tester, items.first, 0);
      await arrow(tester, LogicalKeyboardKey.arrowUp);
      expect(items.first.focus.hasPrimaryFocus, isTrue);
      expect(items.first.text.selection.extentOffset, 0);
      await focusAt(tester, items.last, items.last.text.text.length);
      await arrow(tester, LogicalKeyboardKey.arrowDown);
      expect(items.last.focus.hasPrimaryFocus, isTrue);
      expect(
        items.last.text.selection.extentOffset,
        items.last.text.text.length,
      );
      expect(root.text.text, source);
    },
    variant: desktopPlatforms,
  );

  testWidgets('arrows reveal tasks below the document viewport', (
    tester,
  ) async {
    final source = List.generate(30, (i) => '- [ ] Task number $i').join('\n');
    final root = await pumpEditor(
      tester,
      source,
      platform: TargetPlatform.macOS,
    );
    final items = bodies(tester);
    await focusAt(tester, items.first, 4);
    for (final target in items.skip(1)) {
      await arrow(tester, LogicalKeyboardKey.arrowDown);
      expect(target.focus.hasPrimaryFocus, isTrue);
    }
    final viewport = tester.getRect(editable(root));
    expect(viewport.contains(caretPosition(tester, items.last)), isTrue);
    expect(root.text.imageScrollController!.offset, greaterThan(0));
    expect(root.text.text, source);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
