import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_details.dart';
import 'package:discourse_native/src/shell/composer_details_blocks.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _source =
    'Before\n\n[details="Summary" open future=keep]\n**Hidden**\n[/details]\n\nAfter';
Finder _field(String name) => find.descendant(
  of: find.byKey(ValueKey('details-$name')),
  matching: find.byType(EditableText),
);

Future<ComposerController> _pump(
  WidgetTester tester, {
  String source = _source,
  bool narrow = false,
}) async {
  final composer = ComposerController(
    const ComposerTarget(
      siteUrl: 'https://example.test',
      topicId: 1,
      slug: 'topic',
      topicTitle: 'Topic',
    ),
  );
  addTearDown(composer.dispose);
  composer.text.value = TextEditingValue(
    text: source,
    selection: TextSelection.collapsed(offset: source.length),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: narrow ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: narrow ? 320 : 760,
            child: ComposerEditor(
              composer: composer,
              hintText: 'Reply',
              textStyle: const TextStyle(fontSize: 16, height: 1.5),
              hintStyle: null,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return composer;
}

void main() {
  testWidgets(
    'summary and body edits update canonical source without losing attributes',
    (tester) async {
      final composer = await _pump(tester);
      expect(find.byType(ComposerDetailsEditor), findsOneWidget);
      await tester.enterText(_field('summary'), 'New summary');
      await tester.pump();
      await tester.enterText(
        _field('body'),
        'New **content**\n\nSecond paragraph',
      );
      await tester.pump();
      expect(
        composer.raw,
        _source
            .replaceFirst('"Summary"', '"New summary"')
            .replaceFirst('**Hidden**', 'New **content**\n\nSecond paragraph'),
      );
      expect(tester.takeException(), isNull);
      expect(composer.draft.reply, composer.raw);
    },
  );

  testWidgets('collapse retains text and removal preserves surrounding prose', (
    tester,
  ) async {
    final composer = await _pump(tester);
    await tester.tap(find.text('Summary').first);
    await tester.pumpAndSettle();
    expect(_field('body'), findsNothing);
    expect(composer.raw, _source);
    await tester.tap(find.text('Summary').first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(_field('body')).controller.text,
      '**Hidden**',
    );
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is DButton && widget.tooltip == 'Remove details',
      ),
    );
    await tester.pumpAndSettle();
    expect(composer.raw, 'Before\n\n\n\nAfter');
  });

  testWidgets('body select all and backspace stay inside the embedded field', (
    tester,
  ) async {
    final composer = await _pump(tester);
    await tester.showKeyboard(_field('body'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(composer.raw, _source.replaceFirst('**Hidden**', ''));
  });

  testWidgets('inserted empty details can be filled on a narrow dark surface', (
    tester,
  ) async {
    final composer = await _pump(tester, source: 'Before', narrow: true);
    insertComposerDetails(composer);
    await tester.pumpAndSettle();
    await tester.enterText(_field('body'), 'Content');
    await tester.pumpAndSettle();
    expect(parseComposerDetails(composer.raw).single.body, 'Content');
    expect(tester.takeException(), isNull);
  });

  testWidgets('external history updates the focused embedded field', (
    tester,
  ) async {
    final composer = await _pump(tester);
    await tester.enterText(_field('body'), 'Changed');
    await tester.pump();
    composer.text.value = const TextEditingValue(
      text: _source,
      selection: TextSelection.collapsed(offset: _source.length),
    );
    await tester.pump();
    expect(
      tester.widget<EditableText>(_field('body')).controller.text,
      '**Hidden**',
    );
  });

  testWidgets(
    'incomplete nested markup is saved and exposed as editable source',
    (tester) async {
      final composer = await _pump(tester);
      await tester.enterText(_field('body'), '[details]\nUnfinished');
      await tester.pumpAndSettle();
      expect(
        composer.raw,
        _source.replaceFirst('**Hidden**', '[details]\nUnfinished'),
      );
      expect(find.byType(ComposerDetailsEditor), findsNothing);
    },
  );

  testWidgets('submission rejects retained field and removal callbacks', (
    tester,
  ) async {
    final composer = await _pump(tester);
    final summary = tester.widget<DInput>(
      find.byKey(const ValueKey('details-summary')),
    );
    final body = tester
        .widget<ComposerRichBodyEditor>(
          find.byKey(const ValueKey('details-body')),
        )
        .composer;
    final remove = tester.widget<DButton>(
      find.byWidgetPredicate(
        (widget) => widget is DButton && widget.tooltip == 'Remove details',
      ),
    );
    composer.beginSubmit();
    await tester.pump();
    summary.onChanged!('Changed');
    body.commitText(
      expectedText: body.text.text,
      value: const TextEditingValue(text: 'Changed'),
    );
    remove.onPressed!();
    insertComposerDetails(composer);
    expect(composer.raw, _source);
    expect(
      tester
          .widget<DInput>(find.byKey(const ValueKey('details-summary')))
          .enabled,
      isFalse,
    );
    expect(tester.widget<EditableText>(_field('body')).readOnly, isTrue);
  });

  testWidgets(
    'local undo and formatting keep body focus and canonical drafts',
    (tester) async {
      final composer = await _pump(tester);
      await tester.showKeyboard(_field('body'));
      final field = tester.widget<EditableText>(_field('body'));
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(_field('body'), 'Changed');
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(composer.raw, _source);
      expect(field.focusNode.hasFocus, isTrue);
      field.controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 8,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(composer.raw, _source.replaceFirst('**Hidden**', '***Hidden***'));
      expect(composer.draft.reply, composer.raw);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(composer.focus.hasFocus, isTrue);
    },
  );

  testWidgets('details can be inserted from the real composer toolbar', (
    tester,
  ) async {
    final composer = await _pump(tester, source: 'Intro');
    final shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ShellScope(
          controller: shell,
          child: Scaffold(body: ComposerPanel(composer: composer, height: 550)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-insert')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(composer.raw, startsWith('Intro\n\n[details="Summary"]'));
    expect(find.byType(ComposerDetailsEditor), findsOneWidget);
  });
}
