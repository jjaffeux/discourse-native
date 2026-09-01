import 'package:discourse_native/src/plugin_api/composer_component.dart';
import 'package:discourse_native/src/shell/composer_quote_component.dart';
import 'package:discourse_native/src/shell/composer_quotes.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_composer_editor_host.dart';

const _quote =
    '[quote="Régis, post:5, topic:650, username:zogstrip"]\n'
    'Original body.\n'
    '[/quote]\n\n';
const _markdown =
    'Before\n$_quote'
    'After';

void main() {
  testWidgets(
    'declares an exact typed block and renders resolved captured contents',
    (tester) async {
      var formatterCalls = 0;
      final component = composerQuoteComponent(
        formatQuoteContents: (block) {
          formatterCalls += 1;
          return 'Formatted body.';
        },
        resolveQuoteContents: (block) => 'Resolved **body**.',
      );
      final candidate = component.find(_markdown).single;
      final instance = ComposerComponentInstance(
        range: candidate.range,
        source: _markdown.substring(candidate.range.start, candidate.range.end),
        value: candidate.value,
      );
      final renderContext = ComposerComponentRenderContext(
        range: instance.range,
        value: instance.value,
        baseStyle: const TextStyle(fontSize: 16),
        selected: false,
        hovered: false,
      );
      late BuildContext buildContext;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                buildContext = context;
                return component.builder(context, renderContext);
              },
            ),
          ),
        ),
      );

      expect(component.layout, ComposerComponentLayout.block);
      expect(candidate.range.start, 'Before\n'.length);
      expect(candidate.range.end, 'Before\n$_quote'.length);
      expect(candidate.value, isA<ComposerQuoteBlock>());
      expect(instance.source, _quote);

      final preview = tester.widget<ComposerQuotePreview>(
        find.byType(ComposerQuotePreview),
      );
      expect(preview.block, same(candidate.value));
      expect(preview.contents, 'Resolved **body**.');
      expect(formatterCalls, 0);
      final presentation = ComposerComponentPresentation(
        range: instance.range,
        value: instance.value,
      );
      expect(
        component.semanticLabel(buildContext, presentation),
        'Quote from Régis',
      );
      expect(component.onRemove, isNotNull);
    },
  );

  testWidgets('removal verifies exact captured source and commits by text', (
    tester,
  ) async {
    final component = composerQuoteComponent();
    final candidate = component.find(_markdown).single;
    final instance = ComposerComponentInstance(
      range: candidate.range,
      source: _quote,
      value: candidate.value,
    );
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const Scaffold()),
    );
    final context = tester.element(find.byType(Scaffold));
    final editor = FakeComposerEditorHost(
      const TextEditingValue(
        text: _markdown,
        selection: TextSelection.collapsed(offset: _markdown.length),
      ),
    );

    component.onRemove!(context, editor, instance);

    expect(editor.value.text, 'Before\nAfter');
    expect(
      editor.value.selection,
      const TextSelection.collapsed(offset: 'Before\n'.length),
    );
    expect(editor.commitCalls, 0);
    expect(editor.commitTextCalls, 1);
    expect(editor.focusRequested, isTrue);

    final stale = FakeComposerEditorHost(
      const TextEditingValue(
        text:
            'Before changed\n$_quote'
            'After',
      ),
    );
    component.onRemove!(context, stale, instance);

    expect(
      stale.value.text,
      'Before changed\n$_quote'
      'After',
    );
    expect(stale.commitTextCalls, 0);
    expect(stale.focusRequested, isFalse);
  });
}
