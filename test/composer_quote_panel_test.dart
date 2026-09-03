import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/composer_autocomplete.dart';
import 'package:discourse_native/src/shell/composer_blockquote.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_quotes.dart';
import 'package:discourse_native/src/shell/composer_triggers.dart';
import 'package:discourse_native/src/shell/quote_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _quote =
    '[quote="Régis, post:5, topic:650, username:zogstrip"]\n'
    'You’ll yell the story at me. I’ll try to solve the cube.\n'
    '[/quote]';

const _longQuoteBody =
    'I’ll put on a blindfold.\n'
    'You’ll yell the story at me.\n'
    'I’ll try to solve the cube.\n'
    'This is either going to work beautifully\n'
    'or fail spectacularly.\n'
    'Either way, keep every quoted line.';

const _longQuote =
    '[quote="Régis, post:5, topic:650, username:zogstrip"]\n'
    '$_longQuoteBody\n'
    '[/quote]';

void main() {
  group('quote editing', () {
    testWidgets(
      'Enter accepts suggestions while Shift+Enter adds a quote line',
      (tester) async {
        final composer = ComposerController(
          _target,
          search: (
            users: (_) async => const [
              ComposerSuggestion(
                kind: ComposerTriggerKind.mention,
                value: 'sam',
                label: 'sam',
              ),
            ],
            hashtags: (_) async => const [],
            emojis: (_) async => const [],
          ),
        );
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        await _pumpPanel(tester, shell, composer);
        final field = find.byType(TextField);

        await tester.enterText(field, '> @sa');
        await tester.pump(ComposerAutocomplete.debounce);
        await tester.pumpAndSettle();
        expect(composer.autocomplete.isOpen, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(composer.text.text, '> @sam ');

        await tester.enterText(field, '> @sa');
        await tester.pump(ComposerAutocomplete.debounce);
        await tester.pumpAndSettle();
        expect(composer.autocomplete.isOpen, isTrue);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(composer.text.text, '> @sa\n> ');
      },
    );

    testWidgets('Shift+Enter stays in a quote until two plain Enter presses', (
      tester,
    ) async {
      final composer = ComposerController(_target);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer);
      await tester.enterText(find.byType(TextField), '> words');
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      for (var count = 1; count <= 3; count++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(composer.text.text, '> words${'\n> ' * count}');
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(composer.text.text, '> words${'\n> ' * 4}');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(composer.text.text, '> words${'\n> ' * 3}\n');
      expect(composer.text.selection.extentOffset, composer.text.text.length);
    });

    testWidgets(
      'typing a quote continues and exits through normal text input',
      (tester) async {
        final composer = ComposerController(_target);
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        await _pumpPanel(tester, shell, composer);
        final field = find.byType(TextField);

        await tester.enterText(field, '>');
        await tester.pump();
        expect(find.byType(ComposerBlockquoteMarker), findsNothing);
        await tester.enterText(field, '> ');
        await tester.pump();
        expect(find.byType(ComposerBlockquoteMarker), findsOneWidget);
        await tester.enterText(field, '> xxxx');
        await tester.pump();
        expect(composer.raw, '> xxxx');

        await tester.enterText(field, '> xxxx\n');
        await tester.pump();
        expect(composer.text.text, '> xxxx\n> ');
        expect(composer.text.selection.extentOffset, '> xxxx\n> '.length);
        expect(find.byType(ComposerBlockquoteMarker), findsNWidgets(2));

        await tester.enterText(field, '> xxxx\n> \n');
        await tester.pump();
        expect(composer.text.text, '> xxxx\n');
        expect(find.byType(ComposerBlockquoteMarker), findsOneWidget);
        final render = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        final caret = render.getLocalRectForCaret(
          TextPosition(offset: composer.text.selection.extentOffset),
        );
        expect(
          render.localToGlobal(caret.topLeft).dx,
          closeTo(tester.getTopLeft(find.byType(ComposerEditor)).dx, 1),
        );
        final quoteStart = render.getLocalRectForCaret(
          const TextPosition(offset: 2),
        );
        expect(
          quoteStart.left - caret.left,
          closeTo(ComposerBlockquoteDecoration.gutter, 0.01),
        );

        await tester.enterText(field, '> xxxx\nNormal text');
        await tester.pump();
        expect(composer.raw, '> xxxx\nNormal text');
      },
    );

    testWidgets('projects a selected quote as a read-only post block', (
      tester,
    ) async {
      final composer = ComposerController(_target);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.value = const TextEditingValue(
        text: 'Before\n\n$_quote\n\nAfter',
        selection: TextSelection.collapsed(offset: 0),
      );

      await _pumpPanel(tester, shell, composer);
      await tester.pump();

      expect(find.byType(ComposerQuotePreview), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ComposerQuotePreview),
          matching: find.byType(QuotePanel),
        ),
        findsOneWidget,
      );
      expect(find.text('Régis'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ComposerQuotePreview),
          matching: find.textContaining('You’ll yell the story'),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Remove quote'), findsOneWidget);

      final quote = composer.text.quoteBlocks.single;
      final previewBottom = composer.text
          .collapsedQuoteGlobalRect(quote)!
          .bottom;
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final render = editable.renderEditable;
      final caretTop = render
          .localToGlobal(
            render
                .getLocalRectForCaret(TextPosition(offset: quote.end))
                .topLeft,
          )
          .dy;

      expect(caretTop - previewBottom, inInclusiveRange(0, 32));

      composer.text.selection = TextSelection.collapsed(
        offset: quote.start + 1,
      );
      await tester.pump();

      expect(
        composer.text.selection,
        TextSelection.collapsed(offset: quote.end),
      );
      expect(find.byType(ComposerQuotePreview), findsOneWidget);
      expect(composer.text.text, 'Before\n\n$_quote\n\nAfter');
    });

    testWidgets('the remove affordance deletes the complete quote', (
      tester,
    ) async {
      final composer = ComposerController(_target);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text = '$_quote\n\n';

      await _pumpPanel(tester, shell, composer);
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.byTooltip('Remove quote')));
      await tester.pump();

      expect(composer.text.text, isEmpty);
      expect(find.byType(ComposerQuotePreview), findsNothing);
    });

    testWidgets('does not offer formatting for a selected quote', (
      tester,
    ) async {
      final composer = ComposerController(_target);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      const source = 'Before\n\n$_quote';
      composer.text.text = source;

      await _pumpPanel(tester, shell, composer);
      await tester.pump();

      final quote = composer.text.quoteBlocks.single;
      composer.text.selection = TextSelection(
        baseOffset: quote.start + 1,
        extentOffset: quote.end - 1,
      );
      composer.focus.requestFocus();
      await tester.pumpAndSettle();

      expect(
        composer.text.selection,
        TextSelection(baseOffset: quote.start, extentOffset: quote.end),
      );
      expect(
        find.byKey(const ValueKey('composer-selection-toolbar')),
        findsNothing,
      );
      expect(find.byTooltip('Bold'), findsNothing);
      expect(find.byTooltip('Italic'), findsNothing);

      composer.text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: quote.start,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('composer-selection-toolbar')),
        findsNothing,
      );
      expect(composer.text.text, source);
    });

    testWidgets('backspace and delete remove a quote atomically', (
      tester,
    ) async {
      final composer = ComposerController(_target);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text = _quote;

      await _pumpPanel(tester, shell, composer);
      await tester.pump();
      var quote = composer.text.quoteBlocks.single;
      composer.text.selection = TextSelection.collapsed(offset: quote.end);
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(composer.text.text, isEmpty);

      composer.text.text = _quote;
      await tester.pump();
      quote = composer.text.quoteBlocks.single;
      composer.text.selection = TextSelection.collapsed(offset: quote.start);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(composer.text.text, isEmpty);
    });
  });

  group('preview rendering', () {
    testWidgets('shows the full body above following text', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final composer = ComposerController(_target);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text = '$_longQuote\n\nTyped after the quote';

      await _pumpPanel(tester, shell, composer);
      final quote = composer.text.quoteBlocks.single;
      composer.text.selection = TextSelection.collapsed(
        offset: composer.text.text.length,
      );
      composer.focus.requestFocus();
      await tester.pumpAndSettle();

      expect(composer.text.imageScrollController!.offset, greaterThan(0));

      final body = tester.widget<Text>(
        find.descendant(
          of: find.byType(ComposerQuotePreview),
          matching: find.text(_longQuoteBody),
        ),
      );
      expect(body.maxLines, isNull);
      expect(body.overflow, isNot(TextOverflow.ellipsis));

      final previewBottom = composer.text
          .collapsedQuoteGlobalRect(quote)!
          .bottom;
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final render = editable.renderEditable;
      final caretTop = render
          .localToGlobal(
            render
                .getLocalRectForCaret(TextPosition(offset: quote.end))
                .topLeft,
          )
          .dy;

      expect(caretTop - previewBottom, inInclusiveRange(-16, 32));
    });

    testWidgets('keeps the preview element stable while typing below it', (
      tester,
    ) async {
      // Every keystroke rebuilds the composer's span tree, and each quote in it
      // is a `WidgetSpan` whose child comes with it. The controller used to mint
      // a fresh `GlobalKey` per quote on every text change, so that child was not
      // rebuilt but *recreated* — new element, new render objects, and every
      // memo below them thrown away, including the scan of the quoted text. A
      // reply is mostly quotation often enough for that to be the largest thing
      // on the typing path.
      //
      // Typing under a quote does not move it, so nothing about it has changed.
      final composer = ComposerController(_target);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text = '$_longQuote\n\n';

      await _pumpPanel(tester, shell, composer);
      final preview = tester.element(find.byType(ComposerQuotePreview));
      final scansAfterFirstBuild = ComposerQuotePreview.scans;
      expect(scansAfterFirstBuild, greaterThan(0));

      for (final typed in const ['T', 'Ty', 'Typ', 'Type', 'Typed']) {
        final text = '$_longQuote\n\n$typed';
        composer.text.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        await tester.pump();
      }

      expect(ComposerQuotePreview.scans, scansAfterFirstBuild);
      expect(
        tester.element(find.byType(ComposerQuotePreview)),
        same(preview),
        reason: 'the quote was recreated rather than left alone',
      );
    });

    testWidgets('redraws a moved quote from its own text', (tester) async {
      // The other half: keys are pruned to the quotes that are there, so text
      // typed *above* one gives it a new start and a new key. What must not
      // happen is a preview reusing an element and going on showing the text of
      // whatever used to be at that offset.
      final composer = ComposerController(_target);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text = '$_longQuote\n\n';

      await _pumpPanel(tester, shell, composer);
      expect(find.text(_longQuoteBody), findsOneWidget);

      const before = 'Before.\n\n';
      const moved = '$before$_longQuote\n\n';
      composer.text.value = const TextEditingValue(
        text: moved,
        selection: TextSelection.collapsed(offset: moved.length),
      );
      await tester.pumpAndSettle();

      expect(find.text(_longQuoteBody), findsOneWidget);
      expect(composer.text.quoteBlocks.single.start, before.length);
    });

    testWidgets('renders markdown without exposing source markers', (
      tester,
    ) async {
      const body = 'First paragraph.\n\nSecond **bold** and *italic* line.';
      const quote = '[quote="Régis"]\n$body\n[/quote]';
      final composer = ComposerController(_target);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text = quote;

      await _pumpPanel(tester, shell, composer);
      await tester.pump();

      final bodyText = tester.widget<Text>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.textSpan?.toPlainText() ==
                  'First paragraph.\n\nSecond bold and italic line.',
        ),
      );
      final styles = <TextStyle?>[];
      bodyText.textSpan!.visitChildren((span) {
        if (span is TextSpan) styles.add(span.style);
        return true;
      });

      expect(
        styles.any((style) => style?.fontWeight == FontWeight.w700),
        isTrue,
      );
      expect(
        styles.any((style) => style?.fontStyle == FontStyle.italic),
        isTrue,
      );
    });

    testWidgets('recovers paragraphs from a cached cooked post', (
      tester,
    ) async {
      const cooked =
          '<p>I’ll put on a blindfold.</p>'
          '<p>You’ll yell the story at me.</p>'
          '<p>I’ll try to solve the cube.</p>'
          '<p>This is either going to work beautifully or fail spectacularly.</p>';
      const flattened =
          'I’ll put on a blindfold.'
          'You’ll yell the story at me.'
          'I’ll try to solve the cube.'
          'This is either going to work beautifully or fail spectacularly.';
      const expected =
          'I’ll put on a blindfold.\n\n'
          'You’ll yell the story at me.\n\n'
          'I’ll try to solve the cube.\n\n'
          'This is either going to work beautifully or fail spectacularly.';
      final composer = ComposerController(_target);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      shell.store.put(
        _target.siteUrl,
        const TopicDetail(id: 650, title: 'Quote support', stream: [42]),
      );
      shell.store.put(
        _target.siteUrl,
        const Post(
          id: 42,
          postNumber: 5,
          username: 'zogstrip',
          name: 'Régis',
          cooked: cooked,
        ),
      );
      composer.text.text =
          '[quote="Régis, post:5, topic:650, username:zogstrip"]\n'
          '$flattened\n'
          '[/quote]';

      await _pumpPanel(tester, shell, composer);
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.textSpan?.toPlainText() == expected,
        ),
        findsOneWidget,
      );
      expect(composer.text.text, contains(flattened));
    });
  });
}

Future<ShellController> _shell() async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  return shell;
}

Future<void> _pumpPanel(
  WidgetTester tester,
  ShellController shell,
  ComposerController composer,
) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.dark,
    home: ShellScope(
      controller: shell,
      child: Scaffold(body: ComposerPanel(composer: composer)),
    ),
  ),
);

const _target = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 650,
  slug: 'quote-support',
  topicTitle: 'Quote support',
);
