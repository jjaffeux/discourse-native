import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_code_block.dart';
import 'package:discourse_native/src/shell/composer_code_blocks.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _target = ComposerTarget(
  siteUrl: 'https://example.test',
  topicId: 1,
  slug: 'topic',
  topicTitle: 'Topic',
);

Finder get _codeInput => find.descendant(
  of: find.byType(DCodeEditor),
  matching: find.byType(EditableText),
);

Future<ComposerController> _pump(
  WidgetTester tester,
  String source, {
  double width = 700,
  double scale = 1,
  bool panel = false,
}) async {
  final composer = ComposerController(_target);
  addTearDown(composer.dispose);
  composer.text.value = TextEditingValue(
    text: source,
    selection: TextSelection.collapsed(offset: source.length),
  );
  Widget content = ComposerEditor(
    composer: composer,
    hintText: 'Reply',
    textStyle: const TextStyle(fontSize: 16, height: 1.5),
    hintStyle: null,
  );
  if (panel) {
    final shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    content = ShellScope(
      controller: shell,
      child: ComposerPanel(composer: composer, height: 550),
    );
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Center(
            child: SizedBox(width: width, height: 550, child: content),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return composer;
}

void main() {
  test('closed fences preserve surrounding text, whitespace and CRLF', () {
    const source =
        'Before\r\n\r\n  ~~~~  ruby  \r\n  puts 1\r\n\r\n  ~~~~~ \r\nAfter';
    final block = parseComposerCodeBlocks(source).single;
    expect(block.start, 10);
    expect(block.body, '  puts 1\r\n');
    expect(block.language, 'ruby');
    expect(source.substring(block.start, block.end), block.source);
    expect(
      block.withLanguage('dart'),
      block.source.replaceFirst('ruby', 'dart'),
    );
    expect(
      block.withBody('  puts 2\n'),
      block.source.replaceFirst('puts 1', 'puts 2'),
    );
  });

  test('incomplete fences stay raw and inner shorter fences stay code', () {
    expect(parseComposerCodeBlocks('```dart\ntext'), isEmpty);
    expect(parseComposerCodeBlocks('```dart\ntext\n~~~'), isEmpty);
    expect(parseComposerCodeBlocks('    ```\ntext\n    ```'), isEmpty);
    expect(parseComposerCodeBlocks('> ```\n> text\n> ```'), isEmpty);
    final block = parseComposerCodeBlocks(
      '````md\n```dart\ntext\n```\n````',
    ).single;
    expect(block.body, '```dart\ntext\n```');
    expect(parseComposerCodeBlocks('```\n```').single.body, '');
  });

  test('pasted fences and empty bodies serialize without escaping code', () {
    for (final body in ['', '  indented\n\n', '```\ncode\n````', '~~~']) {
      final source = composerCodeMarkdown(body);
      expect(parseComposerCodeBlocks(source).single.body, body);
      final edited = parseComposerCodeBlocks(
        '```text\n```',
      ).single.withBody(body);
      expect(parseComposerCodeBlocks(edited).single.body, body);
    }
    final tilde = parseComposerCodeBlocks(
      '~~~ruby\na\n~~~',
    ).single.withBody('~~~\na\n~~~~');
    expect(tilde, startsWith('~~~~~ruby'));
    expect(parseComposerCodeBlocks(tilde).single.body, '~~~\na\n~~~~');
  });

  test('hidden code is atomic for partial deletion and replacement', () {
    const source = 'Before\n\n```text\nhello\n```\n\nAfter';
    final block = parseComposerCodeBlocks(source).single;
    final old = TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: block.end),
    );
    const formatter = ComposerCodeInputFormatter();
    final partial = old.copyWith(
      text: source.replaceFirst('```text', '``text'),
    );
    expect(formatter.formatEditUpdate(old, partial), old);
    final selected = old.copyWith(
      selection: TextSelection(
        baseOffset: block.start,
        extentOffset: block.end,
      ),
    );
    final deleted = TextEditingValue(
      text: source.replaceRange(block.start, block.end, ''),
      selection: TextSelection.collapsed(offset: block.start),
    );
    expect(formatter.formatEditUpdate(selected, deleted), deleted);
    final history = TextEditingValue(
      text: source.replaceFirst('hello', 'new'),
      selection: TextSelection.collapsed(offset: block.end - 2),
    );
    expect(formatter.formatEditUpdate(old, history), history);
  });

  testWidgets(
    'editing code updates the draft and preserves focus and selection',
    (tester) async {
      final composer = await _pump(
        tester,
        'Before\n\n```dart\nprint(1);\n```\n\nAfter',
      );
      expect(find.byType(DCodeEditor), findsOneWidget);
      final input = tester.widget<EditableText>(_codeInput);
      expect(input.controller.text, 'print(1);');
      await tester.tap(_codeInput);
      await tester.enterText(_codeInput, '  print(2);\nprint(3);');
      await tester.pumpAndSettle();
      expect(
        composer.raw,
        'Before\n\n```dart\n  print(2);\nprint(3);\n```\n\nAfter',
      );
      expect(
        tester.widget<EditableText>(_codeInput).controller,
        same(input.controller),
      );
      expect(input.focusNode.hasFocus, isTrue);
      expect(
        input.controller.selection.extentOffset,
        input.controller.text.length,
      );
      await tester.tap(find.byTooltip('Done'));
      await tester.pumpAndSettle();
      expect(composer.focus.hasFocus, isTrue);
      expect(
        composer.text.selection.extentOffset,
        greaterThan(parseComposerCodeBlocks(composer.raw).single.end),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('language picker updates fences and restores external history', (
    tester,
  ) async {
    final composer = await _pump(tester, '```text\nhello\n```');
    final original = composer.value;
    await tester.tap(find.byKey(const ValueKey('composer-code-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dart').last);
    await tester.pumpAndSettle();
    expect(composer.raw, '```dart\nhello\n```');
    expect(
      tester.widget<DCodeEditor>(find.byType(DCodeEditor)).controller.language,
      isNotNull,
    );
    composer.text.value = original;
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DSelect<String>>(
            find.byKey(const ValueKey('composer-code-language')),
          )
          .value,
      'text',
    );
    expect(tester.widget<EditableText>(_codeInput).controller.text, 'hello');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'toolbar inserts and focuses a code block',
    (tester) async {
      final composer = await _pump(tester, '', width: 390, panel: true);
      expect(find.byTooltip('Inline code'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('composer-code-block')));
      await tester.pumpAndSettle();
      expect(composer.text.text, '```text\n\n```\n\n');
      expect(find.byType(DCodeEditor), findsOneWidget);
      expect(
        tester.widget<EditableText>(_codeInput).focusNode.hasFocus,
        isTrue,
      );
      await tester.enterText(_codeInput, 'test');
      await tester.pumpAndSettle();
      expect(composer.text.text, '```text\ntest\n```\n\n');
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'code inside details updates the enclosing draft during composition',
    (tester) async {
      final composer = await _pump(
        tester,
        '[details="Example"]\n```text\nold\n```\n[/details]',
      );
      await tester.showKeyboard(_codeInput);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'composing',
          selection: TextSelection.collapsed(offset: 9),
          composing: TextRange(start: 0, end: 9),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(_codeInput).controller.value.composing,
        const TextRange(start: 0, end: 9),
      );
      expect(
        composer.draft.reply,
        '[details="Example"]\n```text\ncomposing\n```\n[/details]',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selection becomes code and long lines fit a narrow scaled editor',
    (tester) async {
      final composer = await _pump(
        tester,
        'before\n\nselected\n\nafter',
        width: 320,
        scale: 1.5,
      );
      composer.text.selection = const TextSelection(
        baseOffset: 8,
        extentOffset: 16,
      );
      insertComposerCodeBlock(composer);
      await tester.pumpAndSettle();
      expect(parseComposerCodeBlocks(composer.raw).single.body, 'selected');
      await tester.enterText(_codeInput, List.filled(200, 'x').join());
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(ComposerCodeBlockEditor)).width,
        lessThanOrEqualTo(320),
      );
      expect(composer.raw, startsWith('before\n\n```text\n'));
      expect(composer.raw, endsWith('```\n\nafter'));
      expect(tester.takeException(), isNull);
    },
  );
}
