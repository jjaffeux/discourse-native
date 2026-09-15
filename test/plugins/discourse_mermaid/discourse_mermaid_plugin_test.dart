import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/discourse_mermaid/discourse_mermaid_module.dart';
import 'package:discourse_native/src/plugins/discourse_mermaid/discourse_mermaid_plugin.dart';
import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

const _plugin = DiscourseMermaidPlugin();
const _cooked =
    '<pre data-code-height="200" data-code-wrap="mermaid"><code class="lang-mermaid">graph TD;\n  A --&gt; B;\n</code></pre>';

void main() {
  test('recognizes the live Discourse markup and preserves decoded source', () {
    final result =
        _plugin.cookedElement(null, html.parse(_cooked).querySelector('pre')!)
            as DMermaid;
    expect(result.source, 'graph TD;\n  A --> B;\n');
    expect(result.height, 200);
  });

  for (final source in [
    '<pre><code class="lang-mermaid">A</code></pre>',
    '<pre data-code-wrap="ruby"><code>A</code></pre>',
    '<div data-code-wrap="mermaid"><code>A</code></div>',
    '<pre data-code-wrap="mermaid">A</pre>',
    '<pre data-code-wrap="mermaid"><code> </code></pre>',
  ]) {
    test('leaves unrelated or incomplete markup to core: $source', () {
      expect(
        _plugin.cookedElement(null, html.parseFragment(source).children.first),
        isNull,
      );
    });
  }

  for (final entry in {
    'NaN': null,
    'Infinity': null,
    '-20': null,
    '1': 80.0,
    '99999': 1200.0,
  }.entries) {
    test('bounds height ${entry.key}', () {
      final element = html.parse(_cooked).querySelector('pre')!
        ..attributes['data-code-height'] = entry.key;
      expect(
        (_plugin.cookedElement(null, element) as DMermaid).height,
        entry.value,
      );
    });
  }

  testWidgets(
    'module installation intercepts cooked blocks, absence uses code',
    (tester) async {
      final installed = PluginInstaller.install(
        const PluginManifest([discourseMermaidModule]),
      );
      addTearDown(installed.close);
      Widget body(PluginRegistry registry) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: CookedHtml(
            html: _cooked,
            registry: registry,
            buildAsync: false,
          ),
        ),
      );
      await tester.pumpWidget(body(installed.registry));
      expect(find.byType(DMermaid), findsOneWidget);
      expect(find.byType(CodeBlock), findsNothing);
      await tester.pumpWidget(body(PluginRegistry.empty));
      expect(find.byType(DMermaid), findsNothing);
      expect(find.byType(CodeBlock), findsOneWidget);
    },
  );

  for (final state in ['editing', 'submitting', 'loading', 'retired']) {
    testWidgets('composer action respects $state admission', (tester) async {
      var current = true;
      final editor = ComposerController(
        const ComposerTarget(
          siteUrl: 'https://example.com',
          topicId: 1,
          slug: 'topic',
          topicTitle: 'Topic',
        ),
        isCurrentComposer: () => current,
      );
      addTearDown(editor.dispose);
      editor.text.value = const TextEditingValue(
        text: 'Before\n\nAfter',
        selection: TextSelection.collapsed(offset: 7),
      );
      late ComposerToolbarContribution action;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              action = _plugin.composerToolbar(context, editor).single;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      if (state == 'submitting') editor.beginSubmit();
      if (state == 'loading') editor.beginLoadingBody();
      if (state == 'retired') current = false;
      final before = editor.value;
      action.onInvoke();
      if (state == 'editing') {
        expect(
          editor.raw,
          contains('```mermaid\nflowchart TD\n    A --> B\n```'),
        );
        expect(editor.raw, startsWith('Before'));
        expect(editor.raw, endsWith('After'));
      } else {
        expect(editor.value, before);
        expect(
          _plugin.composerToolbar(
            tester.element(find.byType(SizedBox).first),
            editor,
          ),
          isEmpty,
        );
      }
    });
  }
}
