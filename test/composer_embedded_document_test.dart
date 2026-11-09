import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer/components/core_artwork.dart';
import 'package:discourse_native/src/shell/composer/controller.dart'
    show ReplyComposerTarget;
import 'package:discourse_native/src/shell/composer/panel.dart'
    show ComposerRichBodyEditor;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const boxKind = ComposerSyntaxKind(owner: PluginId('fixture'), name: 'box');
const target = ReplyComposerTarget(
  privateMessageTopic: false,
  siteUrl: 'https://example.test',
  topicId: 1,
  slug: 'topic',
  topicTitle: 'Topic',
);
const source = 'Before\n[box]\nhello\n[/box]\nAfter';

void main() {
  testWidgets(
    'host rich body preserves its wrapper and owns toolbar targeting',
    (tester) async {
      final parent = ComposerController(
        target,
        syntaxPolicies: [const BoxPolicy()],
      );
      parent.text.text = source;
      parent.artwork = const CoreComposerArtwork();
      addTearDown(parent.dispose);
      Widget frame() => MaterialApp(
        theme: AppTheme.light,
        home: DCard(
          child: Builder(
            builder: (context) => parent.buildEmbeddedDocument(
              context,
              kind: boxKind,
              identity: 1,
              sourceRange: TextRange(
                start: 7,
                end: parent.value.text.indexOf('[/box]') + 6,
              ),
              expectedText: parent.value.text,
              semanticLabel: 'Box body',
            )!,
          ),
        ),
      );
      await tester.pumpWidget(frame());
      final rich = tester.widget<ComposerRichBodyEditor>(
        find.byType(ComposerRichBodyEditor),
      );
      expect(rich.composer.text.text, 'hello');
      rich.composer.focus.requestFocus();
      await tester.pump();
      expect(parent.activeEditor, same(rich.composer));
      rich.composer.text.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      parent.activeEditor.toggleMark(ComposerMark.bold);
      await tester.pump();
      expect(parent.value.text, 'Before\n[box]\n**hello**\n[/box]\nAfter');
      expect(rich.composer.isCurrent, isTrue);
      expect(rich.composer.history.undo(), isTrue);
      expect(parent.value.text, source);
      expect(rich.composer.history.redo(), isTrue);
      expect(parent.value.text, 'Before\n[box]\n**hello**\n[/box]\nAfter');
      rich.composer.text.text = '';
      rich.composer.text.text = 'again';
      expect(parent.value.text, 'Before\n[box]\nagain\n[/box]\nAfter');
      expect(rich.composer.isCurrent, isTrue);
      parent.history.startSession();
      rich.composer.text.text = 'parent history';
      expect(parent.history.undo(), isTrue);
      expect(rich.composer.text.text, 'again');
      expect(rich.composer.isCurrent, isTrue);
      expect(parent.history.redo(), isTrue);
      expect(rich.composer.text.text, 'parent history');
      rich.composer.text.text = '**hello**';
      rich.composer.text.value = rich.composer.value.copyWith(
        selection: const TextSelection.collapsed(offset: 3),
        composing: const TextRange(start: 2, end: 5),
      );
      final editingValue = rich.composer.value;
      await tester.pumpWidget(frame());
      final rebound = tester.widget<ComposerRichBodyEditor>(
        find.byType(ComposerRichBodyEditor),
      );
      expect(rebound.composer, same(rich.composer));
      expect(rebound.composer.value, editingValue);
      expect(rebound.composer.focus.hasFocus, isTrue);
      rebound.composer.text.value = editingValue.copyWith(
        composing: TextRange.empty,
      );

      parent.history.flush();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(parent.activeEditor, same(parent));
    },
  );

  testWidgets(
    'stale source and foreign or out-of-projection ranges fail closed',
    (tester) async {
      final parent = ComposerController(
        target,
        syntaxPolicies: [const BoxPolicy()],
      );
      parent.text.text = source;
      parent.artwork = const CoreComposerArtwork();
      addTearDown(parent.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DCard(
            child: Builder(
              builder: (context) {
                Widget? view({
                  ComposerSyntaxKind owner = boxKind,
                  TextRange range = const TextRange(start: 7, end: 25),
                  String snapshot = source,
                }) => parent.buildEmbeddedDocument(
                  context,
                  kind: owner,
                  identity: 1,
                  sourceRange: range,
                  expectedText: snapshot,
                  semanticLabel: 'Body',
                );
                expect(view(snapshot: 'old source'), isNull);
                expect(
                  view(
                    owner: const ComposerSyntaxKind(
                      owner: PluginId('foreign'),
                      name: 'box',
                    ),
                  ),
                  isNull,
                );
                expect(view(range: const TextRange(start: 0, end: 5)), isNull);
                expect(
                  view(range: const TextRange(start: 13, end: 18)),
                  isNull,
                );
                expect(
                  view(range: const TextRange(start: 18, end: 13)),
                  isNull,
                );
                return view()!;
              },
            ),
          ),
        ),
      );
      final body = tester
          .widget<ComposerRichBodyEditor>(find.byType(ComposerRichBodyEditor))
          .composer;
      parent.text.text = 'Changed before\n$source';
      body.text.text = 'must not overwrite';
      expect(parent.value.text, 'Changed before\n$source');
      expect(body.isCurrent, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class BoxPolicy implements ComposerSyntaxPolicy {
  const BoxPolicy();
  @override
  ComposerSyntaxKind get kind => kindValue;
  static const kindValue = boxKind;
  @override
  Object? get projectionState => null;
  @override
  TextInputFormatter? get inputFormatter => null;
  @override
  List<ComposerSyntaxProjection> parse(String source) {
    final start = source.indexOf('[box]');
    final close = source.indexOf('[/box]', start < 0 ? 0 : start);
    return start < 0 || close < 0
        ? []
        : [BoxProjection(start, source.substring(start, close + 6))];
  }
}

class BoxProjection
    implements
        ComposerInteractiveSyntaxProjection,
        ComposerEmbeddedDocumentProjection {
  BoxProjection(this.start, this.source);
  @override
  final int start;
  @override
  final String source;
  @override
  int get end => start + source.length;
  @override
  TextRange get bodyRange => TextRange(start: start + 6, end: end - 7);
  @override
  String replaceBody(String body, {bool multiline = false}) =>
      '[box]\n$body\n[/box]';
  @override
  bool get supportsHover => false;
  @override
  bool get protectsAdjacentDelete => true;
  @override
  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) => false;
  @override
  int caretAfter(String document) => end;
  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) =>
      document.copyWith(selection: TextSelection.collapsed(offset: end));
  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) =>
      [];
  @override
  void edit(BuildContext context, ComposerEditorHost editor) {}
  @override
  void remove(BuildContext context, ComposerEditorHost editor) {}
}
