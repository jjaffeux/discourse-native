import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
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

Future<void> lineEnd(WidgetTester tester, {bool extend = false}) async {
  final apple = defaultTargetPlatform == TargetPlatform.macOS;
  final modifiers = [
    if (extend) LogicalKeyboardKey.shiftLeft,
    if (apple) LogicalKeyboardKey.metaLeft,
  ];
  for (final key in modifiers) {
    await tester.sendKeyDownEvent(key);
  }
  await arrow(
    tester,
    apple ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.end,
  );
  for (final key in modifiers.reversed) {
    await tester.sendKeyUpEvent(key);
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('arrows enter adjacent paragraphs at their boundaries', (
    tester,
  ) async {
    const first = 'this is a good day\nto do something';
    const second = 'what do you want\nto do';
    const source = '$first\n\n$second';
    final root = await pumpEditor(
      tester,
      source,
      platform: defaultTargetPlatform,
      width: 420,
    );
    await focusAt(tester, root, first.indexOf('day'));
    final start = caretPosition(tester, root);
    await arrow(tester, LogicalKeyboardKey.arrowDown);
    expect(caretPosition(tester, root).dx, closeTo(start.dx, 1));
    expect(caretPosition(tester, root).dy, greaterThan(start.dy));
    expect(root.text.selection.extentOffset, first.length);

    await focusAt(tester, root, first.length);
    await arrow(tester, LogicalKeyboardKey.arrowDown);
    expect(root.text.selection.extentOffset, first.length + 2);
    await arrow(tester, LogicalKeyboardKey.arrowDown);
    expect(root.text.selection.extentOffset, source.lastIndexOf('to do'));
    await focusAt(tester, root, first.length + 2 + second.indexOf('want'));
    await arrow(tester, LogicalKeyboardKey.arrowUp);
    expect(root.text.selection.extentOffset, first.length);
    final end = caretPosition(tester, root);
    await arrow(tester, LogicalKeyboardKey.arrowUp);
    expect(caretPosition(tester, root).dx, closeTo(end.dx, 1));
    expect(caretPosition(tester, root).dy, lessThan(end.dy));
    expect(root.text.text, source);
  }, variant: desktopPlatforms);

  testWidgets('arrows retain their column across short lines within a block', (
    tester,
  ) async {
    const source = 'A long first line\nx\nA long final line\n\nNext paragraph';
    final root = await pumpEditor(
      tester,
      source,
      platform: defaultTargetPlatform,
    );
    await focusAt(tester, root, 8);
    await arrow(tester, LogicalKeyboardKey.arrowDown);
    expect(root.text.selection.extentOffset, source.indexOf('\nx') + 2);
    await arrow(tester, LogicalKeyboardKey.arrowDown);
    expect(
      root.text.selection.extentOffset,
      source.indexOf('A long final') + 8,
    );
    await arrow(tester, LogicalKeyboardKey.arrowUp);
    expect(root.text.selection.extentOffset, source.indexOf('\nx') + 2);
    await arrow(tester, LogicalKeyboardKey.arrowUp);
    expect(root.text.selection.extentOffset, 8);
    expect(root.text.text, source);
  }, variant: desktopPlatforms);

  testWidgets('native macOS selectors enter adjacent paragraph boundaries', (
    tester,
  ) async {
    const first = 'this is a good day\nto do something';
    final root = await pumpEditor(
      tester,
      '$first\n\nwhat do you want\nto do',
      platform: TargetPlatform.macOS,
    );
    await focusAt(tester, root, first.length);
    final state = tester.state<EditableTextState>(editable(root));
    state.performSelector('moveDown:');
    await tester.pumpAndSettle();
    expect(root.text.selection.extentOffset, first.length + 2);
    state.performSelector('moveUp:');
    await tester.pumpAndSettle();
    expect(root.text.selection.extentOffset, first.length);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

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
    expect(items.first.text.selection.extentOffset, 'First'.length);
    await focusAt(tester, items.first, 3);
    tester
        .state<EditableTextState>(editable(items.first))
        .performSelector('moveDown:');
    await tester.pumpAndSettle();
    expect(items.last.focus.hasPrimaryFocus, isTrue);
    expect(items.last.text.selection.extentOffset, 0);
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
    expect(items.first.text.selection.extentOffset, 0);
    await arrow(tester, LogicalKeyboardKey.arrowDown);
    expect(root.focus.hasPrimaryFocus, isTrue);
    expect(root.text.selection.extentOffset, source.indexOf('\n\n\n') + 2);
    await arrow(tester, LogicalKeyboardKey.arrowDown);
    expect(items.last.focus.hasPrimaryFocus, isTrue);
    expect(items.last.text.selection.extentOffset, 0);
    await arrow(tester, LogicalKeyboardKey.arrowDown);
    expect(root.focus.hasPrimaryFocus, isTrue);
    expect(root.text.selection.extentOffset, source.length);
    await arrow(tester, LogicalKeyboardKey.arrowUp);
    expect(items.last.focus.hasPrimaryFocus, isTrue);
    expect(items.last.text.selection.extentOffset, 'Final text'.length);
    expect(root.text.text, source);
  }, variant: desktopPlatforms);

  testWidgets(
    'arrows cross task, list and paragraph boundaries at the destination block edges',
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
      for (final (key, target, offset) in [
        (LogicalKeyboardKey.arrowDown, items[1], 0),
        (LogicalKeyboardKey.arrowDown, items.last, 0),
        (LogicalKeyboardKey.arrowDown, root, source.indexOf('After text')),
        (LogicalKeyboardKey.arrowUp, items.last, 'Third text'.length),
        (LogicalKeyboardKey.arrowUp, items[1], 'Other text'.length),
        (LogicalKeyboardKey.arrowUp, items.first, 'First text'.length),
        (LogicalKeyboardKey.arrowUp, root, 'Before text'.length),
        (LogicalKeyboardKey.arrowDown, items.first, 0),
      ]) {
        await arrow(tester, key);
        expect(target.focus.hasPrimaryFocus, isTrue);
        expect(target.text.selection.extentOffset, offset);
      }
      expect(root.text.text, source);
    },
    variant: desktopPlatforms,
  );

  testWidgets(
    'held arrows enter destination block boundaries across short and empty tasks',
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
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(items[1].focus.hasPrimaryFocus, isTrue);
      expect(items[1].text.selection.extentOffset, 0);
      for (final target in items.skip(2)) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(target.focus.hasPrimaryFocus, isTrue);
        expect(target.text.selection.extentOffset, 0);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      for (final target in items.reversed.skip(1)) {
        await arrow(tester, LogicalKeyboardKey.arrowUp);
        expect(target.focus.hasPrimaryFocus, isTrue);
        expect(target.text.selection.extentOffset, target.text.text.length);
      }
      expect(root.text.text, source);
      expect(tester.takeException(), isNull);
    },
    variant: desktopPlatforms,
  );

  testWidgets(
    'the last line of a wrapped paragraph ends before the paragraph break',
    (tester) async {
      const first =
          'A first paragraph that wraps across several visual lines before it ends.';
      const source = '$first\n\nSecond paragraph';
      final root = await pumpEditor(
        tester,
        source,
        platform: defaultTargetPlatform,
      );
      final render = tester
          .state<EditableTextState>(editable(root))
          .renderEditable;
      final lastLine = render
          .getLineAtOffset(const TextPosition(offset: first.length - 1))
          .start;
      expect(first.substring(lastLine), 'ends.');

      await focusAt(tester, root, lastLine);
      await lineEnd(tester);
      expect(root.text.selection.extentOffset, first.length);
      await lineEnd(tester);
      expect(root.text.selection.extentOffset, first.length);
      await arrow(tester, LogicalKeyboardKey.arrowRight);
      expect(root.text.selection.extentOffset, first.length + 2);

      root.text.selection = TextSelection.collapsed(
        offset: lastLine,
        affinity: TextAffinity.upstream,
      );
      await tester.pumpAndSettle();
      await arrow(tester, LogicalKeyboardKey.arrowDown);
      expect(root.text.selection.extentOffset, first.length + 2);

      final end = render.localToGlobal(
        render
            .getLocalRectForCaret(const TextPosition(offset: first.length))
            .center,
      );
      for (var i = 0; i < 2; i++) {
        root.text.selection = const TextSelection.collapsed(offset: 0);
        await tester.pump();
        await tester.tapAt(end + const Offset(40, 0));
        await tester.pumpAndSettle(kDoubleTapTimeout);
        expect(root.text.selection.extentOffset, first.length);
      }

      await focusAt(tester, root, lastLine);
      await lineEnd(tester, extend: true);
      await arrow(tester, LogicalKeyboardKey.backspace);
      expect(
        root.text.text,
        '${first.substring(0, lastLine)}\n\nSecond paragraph',
      );
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
      expect(items.last.text.selection.extentOffset, 0);
      await arrow(tester, LogicalKeyboardKey.arrowUp);
      expect(items.first.focus.hasPrimaryFocus, isTrue);
      expect(
        items.first.text.selection.extentOffset,
        items.first.text.text.length,
      );
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
    for (final (target, offset) in [
      (items[1], 0),
      (items[2], 0),
      (items.first, items.first.text.text.indexOf('Tail text')),
      (items.last, 0),
    ]) {
      await arrow(tester, LogicalKeyboardKey.arrowDown);
      expect(
        target.focus.hasPrimaryFocus,
        isTrue,
        reason:
            'Expected ${target.text.text}; active: ${root.activeEditor.text.value}',
      );
      expect(target.text.selection.extentOffset, offset);
    }
    for (final (target, offset) in [
      (items.first, items.first.text.text.length),
      (items[2], 'Grand text'.length),
      (items[1], 'Child text'.length),
      (items.first, 'Parent text'.length),
    ]) {
      await arrow(tester, LogicalKeyboardKey.arrowUp);
      expect(target.focus.hasPrimaryFocus, isTrue);
      expect(target.text.selection.extentOffset, offset);
    }
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
