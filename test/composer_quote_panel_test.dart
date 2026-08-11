import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_quotes.dart';
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
  testWidgets('renders a selected post quote as a read-only post-style block', (
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
    final previewBottom = tester
        .getBottomLeft(find.byType(ComposerQuotePreview))
        .dy;
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    final render = editable.renderEditable;
    final caretTop = render
        .localToGlobal(
          render.getLocalRectForCaret(TextPosition(offset: quote.end)).topLeft,
        )
        .dy;

    expect(caretTop - previewBottom, inInclusiveRange(0, 32));

    composer.text.selection = TextSelection.collapsed(offset: quote.start + 1);
    await tester.pump();

    expect(composer.text.selection, TextSelection.collapsed(offset: quote.end));
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

  testWidgets('Backspace and Delete remove a quote atomically', (tester) async {
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

  testWidgets('shows the full quote and places following text below it', (
    tester,
  ) async {
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

    final previewBottom = tester
        .getBottomLeft(find.byType(ComposerQuotePreview))
        .dy;
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    final render = editable.renderEditable;
    final caretTop = render
        .localToGlobal(
          render.getLocalRectForCaret(TextPosition(offset: quote.end)).topLeft,
        )
        .dy;

    expect(caretTop, greaterThanOrEqualTo(previewBottom));
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
