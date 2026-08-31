import 'package:discourse_native/src/plugins/poll/poll_composer_editor.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_pill.dart';
import 'package:discourse_native/src/plugins/poll/poll_icons.dart';
import 'package:discourse_native/src/plugins/poll/poll_plugin.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
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

  group('poll summary and creation policy', () {
    test('produce the title and option count for choice polls', () {
      expect(pollComposerSummary(block), 'Poll · Lunch choice · 2 options');
    });

    test('count the generated values for number polls', () {
      const number =
          '[poll type=number min=0 max=10 step=2]\n'
          '# Score\n'
          '[/poll]';
      expect(
        pollComposerSummary(parsePollComposerBlocks(number).single),
        'Poll · Score · 6 options',
      );
    });

    test('fail closed until the session permission is fresh', () {
      PollCurrentUser? freshUser;
      final controller = ComposerController(
        const ComposerTarget(
          siteUrl: 'https://example.com',
          topicId: 1,
          slug: 'topic',
          topicTitle: 'Topic',
        ),
        syntaxPolicies: [
          PollComposerSyntaxPolicy(
            settings: const PollSettings(
              maximumOptions: 37,
              defaultPublic: false,
            ),
            freshUserReader: () => freshUser,
          ),
        ],
      );
      addTearDown(controller.dispose);
      final policy = controller.syntaxPolicy<PollComposerSyntaxPolicy>(
        pollComposerSyntaxKind,
      )!;

      expect(policy.projectionState, 37);
      expect(policy.canCreate(controller), isFalse);

      freshUser = const PollCurrentUser(canCreatePoll: true);
      expect(policy.canCreate(controller), isTrue);

      freshUser = const PollCurrentUser(canCreatePoll: false);
      expect(policy.canCreate(controller), isFalse);
    });
  });

  group('collapsed poll projection, layout, and caret', () {
    testWidgets('preserve raw offsets and end with a visible line', (
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
              widget is DIcon && widget.icon == PollIcons.squarePollHorizontal,
        ),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byType(RichText).first).height,
        greaterThan(tester.getSize(find.byType(PollComposerPill)).height),
      );
    });

    testWidgets(
      'place and round-trip EOF carets on opposite sides of the pill',
      (tester) async {
        final controller = MarkdownEditingController(
          text: source,
          syntaxPolicies: const [PollComposerSyntaxPolicy()],
        );
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
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
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
      },
    );

    testWidgets('keep end carets measurable after poll-owned whitespace', (
      tester,
    ) async {
      // `[/poll]   ` keeps its trailing whitespace: the block owns it, byte for
      // byte, so the editor can write it back. Projected as `fontSize: 0` text
      // that made the document end in a space with no glyph, and `TextPainter`
      // anchors an end-of-text caret to the paragraph's last glyph whenever the
      // paragraph ends in a space separator. It asserted in debug and had
      // nothing to measure in release.
      for (final trailing in const [' ', '  ', '\t', ' \t ']) {
        final text = '$source$trailing';
        final controller = MarkdownEditingController(
          text: text,
          syntaxPolicies: const [PollComposerSyntaxPolicy()],
        );
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
        expect(
          parsePollComposerBlocks(text).single.end,
          text.length,
          reason: 'the block is expected to own $trailing',
        );

        controller.selection = TextSelection.collapsed(offset: text.length);
        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'trailing $trailing');
        final render = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        expect(render.plainText.length, text.length);
        expect(find.byType(PollComposerPill), findsOneWidget);
      }
    });

    testWidgets(
      'keep selected focus rings inside pill bounds without resizing',
      (tester) async {
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
        for (final side in [
          border.top,
          border.right,
          border.bottom,
          border.left,
        ]) {
          expect(side.color, primary);
          expect(side.width, 1.5);
          expect(side.strokeAlign, BorderSide.strokeAlignInside);
        }
      },
    );
  });

  group('poll reveal, edit, and undo', () {
    testWidgets(
      'collapse and reveal the editable projection without changing raw source',
      (tester) async {
        final controller = MarkdownEditingController(
          text: source,
          syntaxPolicies: const [PollComposerSyntaxPolicy()],
        );
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

    testWidgets('retain verified insertions in EditableText undo history', (
      tester,
    ) async {
      final controller = MarkdownEditingController(
        syntaxPolicies: const [PollComposerSyntaxPolicy()],
      );
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
  });

  group('poll source offsets and reveal decisions', () {
    test("exclude a poll's trailing boundary from source lookup", () {
      const document = '$source\n\n[poll name=second]\n* A\n* B\n[/poll]';
      final blocks = parsePollComposerBlocks(document);
      expect(pollBlockAtComposerOffset(blocks, block.start + 3)?.name, 'lunch');
      expect(pollBlockAtComposerOffset(blocks, block.end), isNull);
      expect(pollBlockAtComposerOffset(blocks, document.length + 1), isNull);
    });

    test('advance the after caret across exactly one LF or CRLF', () {
      for (final (document, lineEndingLength) in [
        ('$source\n', 1),
        ('$source\r\n', 2),
      ]) {
        final controller = MarkdownEditingController(
          text: document,
          syntaxPolicies: const [PollComposerSyntaxPolicy()],
        );
        addTearDown(controller.dispose);
        final projected = controller.pollBlocks.single;
        expect(
          controller.pollCaretAfter(projected),
          projected.end + lineEndingLength,
        );
      }
    });

    testWidgets('resolve collapsed polls only from interior editable offsets', (
      tester,
    ) async {
      final controller = MarkdownEditingController(
        text: source,
        syntaxPolicies: const [PollComposerSyntaxPolicy()],
      );
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

    test('reveal raw source for interior carets and active composition', () {
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
  });

  group('poll selection lifecycle', () {
    test('clamps native range selection to a pointer-held poll end', () {
      final controller = MarkdownEditingController(
        text: source,
        syntaxPolicies: const [PollComposerSyntaxPolicy()],
      );
      addTearDown(controller.dispose);
      final projected = controller.pollBlocks.single;
      controller.keepPollCollapsedForPointerEdit(projected);

      controller.selection = TextSelection(
        baseOffset: projected.start + 1,
        extentOffset: projected.end - 1,
      );

      expect(
        controller.selection,
        TextSelection.collapsed(offset: controller.pollCaretAfter(projected)),
      );

      controller.releasePollPointerEdit(projected);
      final range = TextSelection(
        baseOffset: projected.start + 1,
        extentOffset: projected.end - 1,
      );
      controller.selection = range;
      expect(controller.selection, range);
    });

    test('discards stale keyboard pill selection after source edits', () {
      final controller = MarkdownEditingController(
        text: source,
        syntaxPolicies: const [PollComposerSyntaxPolicy()],
      );
      addTearDown(controller.dispose);
      controller.selectPillForKeyboard(controller.syntaxBlocks.single);

      controller.value = const TextEditingValue(
        text: '$source!',
        selection: TextSelection.collapsed(offset: source.length + 1),
      );
      expect(controller.keyboardSelectedPoll, isNull);

      controller.value = const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: source.length),
      );
      expect(controller.keyboardSelectedPoll, isNull);

      controller.selection = const TextSelection.collapsed(offset: 0);
      expect(controller.selection.extentOffset, 0);
    });
  });
}
