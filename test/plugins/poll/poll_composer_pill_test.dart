import 'package:discourse_native/src/plugins/poll/poll_composer_editor.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_parser.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_pill.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source =
      '[poll name=lunch]\n'
      '# Lunch choice\n'
      '* Soup\n'
      '* Salad\n'
      '[/poll]';
  final block = parsePollComposerBlocks(source).single;

  test('summary uses title and option count', () {
    expect(pollComposerSummary(block), 'Poll · Lunch choice · 2 options');
  });

  test('number summary counts the generated values', () {
    const number =
        '[poll type=number min=0 max=10 step=2]\n'
        '# Score\n'
        '[/poll]';
    expect(
      pollComposerSummary(parsePollComposerBlocks(number).single),
      'Poll · Score · 6 options',
    );
  });

  testWidgets('collapsed spans retain offsets and end with a visual line', (
    tester,
  ) async {
    final spans = buildCollapsedPollSpans(
      block: block,
      baseStyle: const TextStyle(fontSize: 15),
    );
    final flattened = TextSpan(
      children: spans,
    ).toPlainText(includeSemanticsLabels: false);

    expect(flattened.length, source.length);
    expect(flattened.codeUnitAt(0), PlaceholderSpan.placeholderCodeUnit);
    expect(flattened.codeUnitAt(1), 0x0A);
    expect(
      spans.whereType<WidgetSpan>(),
      hasLength('\n'.allMatches(source).length + 1),
    );
    for (final span in spans.whereType<TextSpan>()) {
      if (span.text == '\n') {
        expect(span.style?.fontSize, 15);
      } else {
        expect(span.text, isNot(contains('\n')));
        expect(span.style?.fontSize, 0);
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 15),
              children: spans,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Poll · Lunch choice · 2 options'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DIcon && widget.icon == DIcons.squarePollHorizontal,
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(RichText).first).height,
      greaterThan(tester.getSize(find.byType(PollComposerPill)).height),
    );
  });

  testWidgets('before and after carets flank an EOF poll on separate lines', (
    tester,
  ) async {
    final controller = MarkdownEditingController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: TextField(controller: controller, maxLines: null),
          ),
        ),
      ),
    );

    final pillRect = tester.getRect(find.byType(PollComposerPill));
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    final render = editable.renderEditable;
    Rect caretAt(int offset) => render
        .getLocalRectForCaret(TextPosition(offset: offset))
        .shift(render.localToGlobal(Offset.zero));

    final before = caretAt(block.start);
    final after = caretAt(block.end);
    expect(before.left, lessThanOrEqualTo(pillRect.left + 1));
    expect(before.top, lessThan(pillRect.bottom));
    expect(after.top, greaterThanOrEqualTo(pillRect.bottom));
    expect(render.plainText.length, controller.text.length);

    for (final offset in [block.start, block.end]) {
      final caret = caretAt(offset);
      expect(
        render.getPositionForPoint(caret.center).offset,
        offset,
        reason: 'the caret at $offset must round-trip through hit testing',
      );
      controller.selection = TextSelection.collapsed(offset: offset);
      await tester.pump();
      expect(find.byType(PollComposerPill), findsOneWidget);
    }
  });

  testWidgets('the selected focus ring stays inside the pill bounds', (
    tester,
  ) async {
    const selectedKey = ValueKey('selected-poll');
    const unselectedKey = ValueKey('unselected-poll');
    const style = TextStyle(fontSize: 15);
    const label = 'Poll · Untitled · 2 options';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRect(
                child: PollComposerPill(
                  key: selectedKey,
                  label: label,
                  baseStyle: style,
                  highlighted: true,
                ),
              ),
              PollComposerPill(
                key: unselectedKey,
                label: label,
                baseStyle: style,
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(selectedKey)),
      tester.getSize(find.byKey(unselectedKey)),
      reason: 'selecting the pill must not move its caret or hit geometry',
    );

    final container = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byKey(selectedKey),
            matching: find.byType(Container),
          ),
        )
        .singleWhere((widget) => widget.foregroundDecoration != null);
    final background = container.decoration! as BoxDecoration;
    final foreground = container.foregroundDecoration! as BoxDecoration;
    final border = foreground.border! as Border;
    final primary = Theme.of(
      tester.element(find.byKey(selectedKey)),
    ).colorScheme.primary;

    expect(background.boxShadow, isNull);
    expect(foreground.borderRadius, background.borderRadius);
    for (final side in [border.top, border.right, border.bottom, border.left]) {
      expect(side.color, primary);
      expect(side.width, 1.5);
      expect(side.strokeAlign, BorderSide.strokeAlignInside);
    }
  });

  testWidgets(
    'the editable projection collapses and reveals without changing raw',
    (tester) async {
      final controller = MarkdownEditingController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: TextField(controller: controller, maxLines: null),
          ),
        ),
      );

      expect(find.byType(PollComposerPill), findsOneWidget);
      expect(controller.text, source);

      controller.selection = TextSelection.collapsed(offset: block.start + 4);
      await tester.pump();
      expect(find.byType(PollComposerPill), findsNothing);
      expect(controller.text, source);

      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: 0),
        composing: TextRange(start: block.start + 2, end: block.start + 5),
      );
      await tester.pump();
      expect(find.byType(PollComposerPill), findsNothing);

      controller.value = controller.value.copyWith(
        selection: TextSelection.collapsed(offset: block.end),
        composing: TextRange.empty,
      );
      await tester.pump();
      expect(find.byType(PollComposerPill), findsOneWidget);
      expect(
        controller
            .buildTextSpan(
              context: tester.element(find.byType(TextField)),
              style: const TextStyle(fontSize: 15),
              withComposing: true,
            )
            .toPlainText(includeSemanticsLabels: false)
            .length,
        source.length,
      );
    },
  );

  testWidgets('a verified insertion remains in EditableText undo history', (
    tester,
  ) async {
    final controller = MarkdownEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
          ),
        ),
      ),
    );
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump(const Duration(milliseconds: 600));

    final mutation = insertVerifiedPoll(
      current: controller.value,
      expectedDocument: '',
      expectedSelection: controller.selection,
      markup: source,
    );
    controller.value = mutation.value;
    await tester.pump(const Duration(milliseconds: 600));

    expect(controller.text, '$source\n');
    expect(find.byType(PollComposerPill), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(controller.text, isEmpty);
  });

  test('source offsets exclude the poll trailing boundary', () {
    const document = '$source\n\n[poll name=second]\n* A\n* B\n[/poll]';
    final blocks = parsePollComposerBlocks(document);
    expect(pollBlockAtComposerOffset(blocks, block.start + 3)?.name, 'lunch');
    expect(pollBlockAtComposerOffset(blocks, block.end), isNull);
    expect(pollBlockAtComposerOffset(blocks, document.length + 1), isNull);
  });

  test('the after caret consumes one real LF or CRLF', () {
    for (final (document, lineEndingLength) in [
      ('$source\n', 1),
      ('$source\r\n', 2),
    ]) {
      final controller = MarkdownEditingController(text: document);
      final projected = controller.pollBlocks.single;
      expect(
        controller.pollCaretAfter(projected),
        projected.end + lineEndingLength,
      );
      controller.dispose();
    }
  });

  testWidgets('resolves a collapsed poll from its editable source offset', (
    tester,
  ) async {
    final controller = MarkdownEditingController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: TextField(controller: controller)),
      ),
    );

    final projected = controller.pollBlocks.single;
    expect(
      controller.collapsedPollAtOffset(projected.end - 1),
      same(projected),
    );
    expect(controller.collapsedPollAtOffset(projected.start), isNull);
    expect(controller.collapsedPollAtOffset(projected.end), isNull);
  });

  test('selection and composition reveal raw source', () {
    for (final offset in [block.start, block.end]) {
      expect(
        pollBlockNeedsRawSource(
          block: block,
          value: TextEditingValue(
            text: source,
            selection: TextSelection.collapsed(offset: offset),
          ),
        ),
        isFalse,
      );
    }
    expect(
      pollBlockNeedsRawSource(
        block: block,
        value: TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: block.start + 4),
        ),
      ),
      isTrue,
    );
    expect(
      pollBlockNeedsRawSource(
        block: block,
        value: TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: block.start + 4),
        ),
        suppressCollapsedCaret: true,
      ),
      isFalse,
    );
    expect(
      pollBlockNeedsRawSource(
        block: block,
        value: TextEditingValue(
          text: source,
          selection: const TextSelection.collapsed(offset: 0),
          composing: TextRange(start: block.start + 2, end: block.start + 4),
        ),
        suppressCollapsedCaret: true,
      ),
      isTrue,
    );
  });

  test('explicit raw expansion ends when the caret leaves', () {
    final expansion = PollRawExpansion()..expand(block);
    expect(expansion.contains(block), isTrue);
    expansion.updateSelection(
      TextSelection.collapsed(offset: block.start + block.length ~/ 2),
    );
    expect(expansion.contains(block), isTrue);
    expansion.updateSelection(TextSelection.collapsed(offset: block.end));
    expect(expansion.contains(block), isFalse);
  });
}
