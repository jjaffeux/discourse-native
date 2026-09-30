import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/shell/composer_block_surface.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_table.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _table = '| One | Two |\n| --- | --- |\n| A | B |';
const _source = '**Bold** :smile: @sam\n\n> Quote\n\n$_table';
const _target = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'a-topic',
  topicTitle: 'A topic',
);

void main() {
  Future<ShellController> shell({bool raw = false}) async {
    final shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      appSettingsStore: AppSettingsStore(
        persistence: MemoryAppSettingsPersistence(rawMarkdownComposers: raw),
      ),
    );
    addTearDown(shell.dispose);
    await shell.load();
    return shell;
  }

  ComposerController composer(String source) {
    final composer = ComposerController(_target);
    composer.text.value = TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: source.length),
    );
    addTearDown(composer.dispose);
    return composer;
  }

  Future<void> pumpEditor(
    WidgetTester tester,
    ShellController shell,
    ComposerController composer,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.linux),
        home: ShellScope(
          controller: shell,
          child: Scaffold(
            body: ComposerEditor(
              composer: composer,
              hintText: 'Write a reply',
              textStyle: const TextStyle(fontSize: 16),
              hintStyle: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TextSpan painted(WidgetTester tester) =>
      tester
              .state<EditableTextState>(find.byType(EditableText).first)
              .renderEditable
              .text!
          as TextSpan;

  testWidgets('changing mode preserves a draft, selection and undo history', (
    tester,
  ) async {
    final settings = await shell();
    final draft = composer(_source);
    await pumpEditor(tester, settings, draft);
    expect(find.byType(ComposerTableEditor), findsOneWidget);
    final selection = TextSelection(
      baseOffset: _source.indexOf('Bold'),
      extentOffset: _source.indexOf('Bold') + 4,
    );
    draft.text.selection = selection;
    await tester.pump();

    await settings.appSettings.setRawMarkdownComposers(true);
    await tester.pumpAndSettle();
    expect(draft.raw, _source);
    expect(draft.text.selection, selection);
    expect(painted(tester).text, _source);
    expect(painted(tester).children, isNull);
    expect(find.byType(ComposerTableEditor), findsNothing);
    expect(find.byType(ComposerBlockSurface), findsNothing);
    expect(draft.history.canUndo, isFalse);

    await tester.enterText(find.byType(TextField), '$_source\n\nEdited');
    await tester.pump();
    expect(draft.history.canUndo, isTrue);
    await settings.appSettings.setRawMarkdownComposers(false);
    await tester.pumpAndSettle();
    expect(find.byType(ComposerTableEditor), findsOneWidget);
    expect(find.byType(ComposerBlockSurface), findsOneWidget);
    expect(draft.raw, '$_source\n\nEdited');
    draft.history.undo();
    await tester.pumpAndSettle();
    expect(draft.raw, _source);
    expect(draft.history.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved raw mode allows literal markers, newlines and IME edits', (
    tester,
  ) async {
    final settings = await shell(raw: true);
    final draft = composer(_source);
    await pumpEditor(tester, settings, draft);
    expect(draft.text.rawMarkdown, isTrue);
    expect(painted(tester).text, _source);
    await tester.showKeyboard(find.byType(TextField));

    // Moving through a visible quote marker must not jump over its prefix.
    final quote = _source.indexOf('>');
    draft.text.selection = TextSelection.collapsed(offset: quote);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(draft.text.selection.extentOffset, quote + 1);

    // Native edits delete only the selected source character, even inside
    // syntax that would otherwise be an atomic widget or hidden marker.
    for (final source in [
      '[quote="sam"]quoted[/quote]',
      '![photo](upload://photo.png)',
      '[poll]\n* One\n* Two\n[/poll]',
      '<ins>underlined</ins>',
      ':smile:',
      '- [ ] Task',
      _table,
    ]) {
      draft.text.value = TextEditingValue(
        text: source,
        selection: const TextSelection.collapsed(offset: 1),
      );
      await tester.pump();
      final edited = TextEditingValue(
        text: source.substring(1),
        selection: const TextSelection.collapsed(offset: 0),
      );
      tester.testTextInput.updateEditingValue(edited);
      await tester.pump();
      expect(draft.text.value, edited, reason: source);
      expect(painted(tester).text, edited.text);
    }

    await tester.enterText(find.byType(TextField), 'paragraph');
    // The platform text input supplies the newline after the hardware key.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'paragraph\n',
        selection: TextSelection.collapsed(offset: 10),
      ),
    );
    await tester.pump();
    expect(draft.text.text, 'paragraph\n');

    const composing = TextEditingValue(
      text: 'composing',
      selection: TextSelection.collapsed(offset: 9),
      composing: TextRange(start: 0, end: 9),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pump();
    expect(draft.text.value, composing);
    expect(painted(tester).toPlainText(), composing.text);
    expect(
      painted(tester).children!.whereType<TextSpan>().any(
        (span) => span.style?.decoration == TextDecoration.underline,
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
