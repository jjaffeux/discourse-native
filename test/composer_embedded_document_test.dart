import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
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
      addTearDown(parent.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DCard(
            child: Builder(
              builder: (context) => parent.buildEmbeddedDocument(
                context,
                kind: boxKind,
                identity: 1,
                bodyRange: const TextRange(start: 13, end: 18),
                expectedText: source,
                semanticLabel: 'Box body',
              )!,
            ),
          ),
        ),
      );
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
      addTearDown(parent.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DCard(
            child: Builder(
              builder: (context) {
                Widget? view({
                  ComposerSyntaxKind owner = boxKind,
                  TextRange range = const TextRange(start: 13, end: 18),
                  String snapshot = source,
                }) => parent.buildEmbeddedDocument(
                  context,
                  kind: owner,
                  identity: 1,
                  bodyRange: range,
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

class BoxProjection implements ComposerInteractiveSyntaxProjection {
  BoxProjection(this.start, this.source);
  @override
  final int start;
  @override
  final String source;
  @override
  int get end => start + source.length;
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
