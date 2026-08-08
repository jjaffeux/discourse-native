import 'package:discourse_native/src/plugins/poll/poll_composer_editor.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_parser.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_pill.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
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

  testWidgets('collapsed spans retain one code unit per source code unit', (
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
    expect(
      spans.whereType<WidgetSpan>(),
      hasLength('\n'.allMatches(source).length + 1),
    );
    for (final span in spans.whereType<TextSpan>()) {
      expect(span.text, isNot(contains('\n')));
      expect(span.style?.fontSize, 0);
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
    expect(tester.getSize(find.byType(RichText).first).height, lessThan(40));
  });

  testWidgets('the inline pill reports its own hover', (tester) async {
    final hovering = <bool>[];
    final controller = MarkdownEditingController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: NotificationListener<PollComposerPillHoverNotification>(
            onNotification: (notification) {
              hovering.add(notification.hovering);
              expect(notification.block.source, block.source);
              return true;
            },
            child: Center(
              child: TextField(controller: controller, maxLines: null),
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(PollComposerPill)));
    await tester.pump();
    await mouse.moveTo(Offset.zero);
    await tester.pump();

    expect(hovering, [isTrue, isFalse]);
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

    expect(controller.text, source);
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

  test('selection and composition reveal raw source', () {
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
