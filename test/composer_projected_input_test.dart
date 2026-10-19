import 'package:discourse_native/src/plugins/poll/poll_composer.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/composer/projected_component_input.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _target = ReplyComposerTarget(
  privateMessageTopic: false,
  siteUrl: 'https://example.test',
  topicId: 1,
  slug: 'topic',
  topicTitle: 'Topic',
);
const _image = '![Photo|100x100](upload://photo)';
const _sources = {
  'image': _image,
  'gallery': '[grid]\n$_image\n[/grid]',
  'quote': '[quote="sam, post:1, topic:1"]\nQuoted text\n[/quote]',
  'syntax': '[poll]\n* Tea\n* Coffee\n[/poll]',
};

Future<ComposerController> _pump(WidgetTester tester, String source) async {
  final composer = ComposerController(
    _target,
    syntaxPolicies: const [PollComposerSyntaxPolicy()],
  );
  addTearDown(composer.dispose);
  composer.text.value = TextEditingValue(
    text: source,
    selection: TextSelection.collapsed(offset: source.length),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ComposerEditor(
          composer: composer,
          hintText: 'Write a reply',
          textStyle: const TextStyle(fontSize: 16, height: 1.5),
          hintStyle: null,
        ),
      ),
    ),
  );
  composer.requestFocus();
  await tester.pumpAndSettle();
  return composer;
}

void main() {
  for (final entry in _sources.entries) {
    for (final software in [false, true]) {
      testWidgets(
        '${entry.key} typed input keeps UTF16 source and undo ($software)',
        (tester) async {
          const prefix = '😀\r\n\r\n';
          final original = '$prefix${entry.value}\r\n\r\nAfter';
          final composer = await _pump(tester, original);
          final text = composer.text;
          final component = text.collapsedComponentStartingAt(prefix.length)!;
          expect(component.start, prefix.length);
          expect(component.source, contains(entry.value));
          text.moveCaretBesideComponent(component, before: false);
          await tester.pump();
          final caret = text.selection.extentOffset;
          final command = text.adjacentComponentDeletion(
            caret: caret,
            backward: true,
          );
          expect(command, isA<ComposerRemoveComponent>());
          expect(
            (command! as ComposerRemoveComponent).component.sameAs(component),
            isTrue,
          );
          final proposed = TextEditingValue(
            text: original.replaceRange(caret - 1, caret, ''),
            selection: TextSelection.collapsed(offset: caret - 1),
            composing: const TextRange(start: 0, end: 2),
          );
          final edit = text.projectedComponentEdit(text.value, proposed);
          expect(edit.value.text, original);
          expect(edit.value.composing, TextRange.empty);
          expect(edit.command, isA<ComposerRemoveComponent>());
          if (software) {
            tester.testTextInput.updateEditingValue(proposed);
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          }
          await tester.pumpAndSettle();
          expect(composer.raw, isNot(contains(entry.value)));
          expect(composer.raw, startsWith('😀'));
          composer.history.undo();
          await tester.pumpAndSettle();
          expect(composer.raw, original);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }
  }

  testWidgets('deferred deletion cannot remove a replacement selection', (
    tester,
  ) async {
    final source = 'Before\n\n${_sources['syntax']}\n\nAfter';
    final composer = await _pump(tester, source);
    final text = composer.text;
    text.selectPillForKeyboard(
      ComposerSyntaxInput(
        text.syntaxBlocks.firstWhere((block) => block.kind.name == 'poll'),
      ),
    );
    await tester.pump();
    final before = text.value;
    final caret = before.selection.extentOffset;
    final editable = tester.widget<EditableText>(
      find.byWidgetPredicate(
        (widget) => widget is EditableText && widget.controller == text,
      ),
    );
    final protected = editable.inputFormatters!.first.formatEditUpdate(
      before,
      TextEditingValue(
        text: source.replaceRange(caret - 1, caret, ''),
        selection: TextSelection.collapsed(offset: caret - 1),
      ),
    );
    expect(protected, before);
    text.value = TextEditingValue(
      text: '$source!',
      selection: TextSelection.collapsed(offset: source.length + 1),
    );
    text.value = before;
    text.selectPillForKeyboard(
      ComposerSyntaxInput(
        text.syntaxBlocks.firstWhere((block) => block.kind.name == 'poll'),
      ),
    );
    await tester.pumpAndSettle();
    expect(composer.raw, source);
    expect(text.keyboardSelectedProjection, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'deferred deletion still applies after reselecting the same target',
    (tester) async {
      final source = 'Before\n\n${_sources['syntax']}\n\nAfter';
      final composer = await _pump(tester, source);
      final text = composer.text;
      final occurrence = text.syntaxBlocks.firstWhere(
        (block) => block.kind.name == 'poll',
      );
      text.selectPillForKeyboard(ComposerSyntaxInput(occurrence));
      await tester.pump();
      final before = text.value;
      final caret = before.selection.extentOffset;
      final editable = tester.widget<EditableText>(
        find.byWidgetPredicate(
          (widget) => widget is EditableText && widget.controller == text,
        ),
      );
      final protected = editable.inputFormatters!.first.formatEditUpdate(
        before,
        TextEditingValue(
          text: source.replaceRange(caret - 1, caret, ''),
          selection: TextSelection.collapsed(offset: caret - 1),
        ),
      );
      expect(protected, before);
      text.clearKeyboardPillSelection();
      text.selectPillForKeyboard(ComposerSyntaxInput(occurrence));
      await tester.pumpAndSettle();
      expect(composer.raw, isNot(contains('[poll]')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'outer quote and gallery input take precedence over their image',
    (tester) async {
      for (final source in [
        '[quote="sam, post:1, topic:1"]\n[grid]\n$_image\n[/grid]\n[/quote]',
        '[grid]\n$_image\n[/grid]',
      ]) {
        final composer = await _pump(tester, '$source\n\nAfter');
        final offset = composer.raw.indexOf('Photo') + 1;
        final component = composer.text.collapsedComponentContaining(offset)!;
        expect(component.start, 0);
        expect(
          component,
          source.startsWith('[quote')
              ? isA<ComposerQuoteInput>()
              : isA<ComposerGalleryInput>(),
        );
        composer.text.rawMarkdown = true;
        await tester.pumpAndSettle();
        expect(composer.text.collapsedComponents, isEmpty);
        expect(composer.text.collapsedComponentContaining(offset), isNull);
        expect(composer.raw, '$source\n\nAfter');
      }
    },
  );
}
