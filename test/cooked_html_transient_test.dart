import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;

const _source = 'def private_note\n  puts "staff only"\nend';
const _fence = '<pre><code class="lang-ruby">$_source\n</code></pre>';

Future<void> _mount(
  WidgetTester tester,
  String html, {
  required bool transient,
  PluginRegistry? registry,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CookedHtml(
            html: html,
            transient: transient,
            registry: registry,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _highlight(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    final block = tester.widget<CodeBlock>(find.byType(CodeBlock));
    var colored = false;
    final line = tester.widget<Text>(find.text('def private_note'));
    line.textSpan!.visitChildren((span) {
      if (span.style?.color == CodeColors.light.keyword) colored = true;
      return true;
    });
    if (colored) return;
    expect(block.data.text, _source);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  fail('Ruby keywords were not highlighted');
}

void main() {
  setUp(clearSyntaxHighlightCacheForTesting);
  tearDown(clearSyntaxHighlightCacheForTesting);
  for (final markup in [
    _fence,
    '<aside class="onebox"><article class="onebox-body">$_fence</article></aside>',
  ]) {
    testWidgets(
      'transient nested code stays readable without shared cache or fullscreen: $markup',
      (tester) async {
        await _mount(tester, markup, transient: true);
        expect(highlightNeedsParse(_source, 'ruby'), isTrue);
        await _highlight(tester);
        expect(
          tester.widget<CodeBlock>(find.byType(CodeBlock)).data.text,
          _source,
        );
        expect(highlightNeedsParse(_source, 'ruby'), isTrue);
        expect(find.byTooltip('View code full screen'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(find.byType(CodeBlockFullscreen), findsNothing);
        expect(highlightNeedsParse(_source, 'ruby'), isTrue);
      },
    );
  }
  testWidgets('ordinary code retains highlighting cache and fullscreen', (
    tester,
  ) async {
    await _mount(tester, _fence, transient: false);
    await _highlight(tester);
    expect(highlightNeedsParse(_source, 'ruby'), isFalse);
    expect(find.byTooltip('View code full screen'), findsOneWidget);
  });
  testWidgets('transient rendering bypasses optional renderer callbacks', (
    tester,
  ) async {
    final plugin = _OptionalRenderer();
    final registry = PluginRegistry.validated([plugin]);
    await _mount(
      tester,
      '<div class="optional">private diagram</div>',
      transient: true,
      registry: registry,
    );
    expect(plugin.calls, 0);
    expect(find.text('private diagram', findRichText: true), findsOneWidget);
    await _mount(
      tester,
      '<div class="optional">public diagram</div>',
      transient: false,
      registry: registry,
    );
    expect(plugin.calls, greaterThan(0));
    expect(find.text('optional renderer'), findsOneWidget);
  });
}

final class _OptionalRenderer implements SitePlugin, CookedElementPlugin {
  int calls = 0;
  @override
  String get name => 'optional-test';
  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) {
    calls++;
    return element.classes.contains('optional')
        ? const DText('optional renderer')
        : null;
  }
}
