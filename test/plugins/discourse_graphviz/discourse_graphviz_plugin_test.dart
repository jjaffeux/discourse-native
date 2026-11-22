import 'dart:convert';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/plugins/discourse_graphviz/discourse_graphviz_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_graphviz/graphviz_diagram.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:webview_all/webview_all.dart';

import '../../support/blank_png.dart';
import '../../support/fake_media_webview.dart';

const _source = 'digraph { lead -> "Research & Development" }';
const _pluginHtml =
    '<div class="graphviz is-loading" data-engine="neato">\n'
    'digraph { lead -&gt; "Research &amp; Development" }\n'
    '</div>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'matches both cooked formats and preserves old images and code examples',
    () {
      const plugin = DiscourseGraphvizPlugin();
      Widget? read(String markup) => plugin.cookedElement(
        null,
        html.parseFragment(markup).children.single,
      );
      final block = read(_pluginHtml) as GraphvizDiagram;
      expect(block.source, '\n$_source\n');
      expect(block.engine, 'neato');
      expect(block.height, isNull);

      final fence =
          read(
                '<pre data-code-wrap="graphviz" data-code-engine="sfdp" data-code-height="9000">'
                '<code>graph { a -- b }\n</code></pre>',
              )
              as GraphvizDiagram;
      expect(fence.source, 'graph { a -- b }\n');
      expect(fence.engine, 'sfdp');
      expect(fence.height, 1200);

      final defaults =
          read(
                '<pre data-code-wrap="graphviz" data-code-engine="bogus" data-code-height="NaN">'
                '<code>graph { a -- b }</code></pre>',
              )
              as GraphvizDiagram;
      expect(defaults.engine, 'dot');
      expect(defaults.height, isNull);

      expect(read('<div class="graphviz is-loading"> </div>'), isNull);
      expect(
        read('<div class="graphviz"><img src="/graph.png"></div>'),
        isNull,
      );
      expect(read('<pre data-code-wrap="graphviz"></pre>'), isNull);
      expect(read('<pre><code class="lang-dot">$_source</code></pre>'), isNull);
    },
  );

  for (final profile in CookingProfile.values) {
    test('${profile.name} cooking emits a Graphviz theme block', () async {
      final installed = PluginInstaller.install(bundledPluginManifest);
      addTearDown(installed.close);
      final cooking = OfflineCookingService();
      addTearDown(cooking.dispose);

      final result = await cooking.cook(
        CookingRequest(
          raw: '```graphviz engine=neato,height=200\n$_source\n```',
          profile: profile,
          configuration: cookingConfiguration(installed.cookingPlugins),
          snapshot: CookingSnapshot(
            siteId: 'https://graphviz.example',
            accountId: 'test',
          ),
        ),
      );

      expect(result.failure, isNull);
      final block = html
          .parseFragment(result.html)
          .querySelector('pre[data-code-wrap="graphviz"]');
      expect(block, isNotNull);
      final diagram =
          const DiscourseGraphvizPlugin().cookedElement(null, block!)
              as GraphvizDiagram;
      expect(diagram.source, '$_source\n');
      expect(diagram.engine, 'neato');
      expect(diagram.height, 200);
    });
  }

  late FakeMediaWebViewPlatform platform;
  setUp(() {
    platform = FakeMediaWebViewPlatform();
    final previous = WebViewPlatform.instance ?? platform;
    WebViewPlatform.instance = platform;
    addTearDown(() => WebViewPlatform.instance = previous);
  });

  Widget host(PluginRegistry registry, {String markup = _pluginHtml}) =>
      DefaultAssetBundle(
        bundle: _Assets(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: CookedHtml(
              html: markup,
              registry: registry,
              buildAsync: false,
            ),
          ),
        ),
      );

  testWidgets('bundled cooked Graphviz can be opened as an image and source', (
    tester,
  ) async {
    final installed = PluginInstaller.install(bundledPluginManifest);
    addTearDown(installed.close);

    await tester.pumpWidget(host(installed.registry));
    await tester.pump();
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    final controller = platform.controllers.single;
    expect(controller.documents.single.html, contains('"engine":"neato"'));
    final renderer = controller.channels['NativeGraphviz']!;
    renderer.onMessageReceived(
      JavaScriptMessage(
        message: jsonEncode({
          'type': 'rendered',
          'width': 160,
          'height': 90,
          'png': base64Encode(blankPng(width: 4, height: 3)),
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DImagePreview), findsOneWidget);
    expect(find.byType(WebViewWidget), findsNothing);

    await tester.tap(find.byType(DImagePreview));
    await tester.pumpAndSettle();
    expect(find.byType(DDialogTitle), findsOneWidget);
    expect(find.text('Graphviz diagram'), findsOneWidget);
    Navigator.of(tester.element(find.byType(DDialogTitle))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('View source'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CodeBlock>(find.byType(CodeBlock)).data.text,
      '\n$_source\n',
    );
  });

  testWidgets('invalid DOT retains viewable source', (tester) async {
    final installed = PluginInstaller.install(bundledPluginManifest);
    addTearDown(installed.close);

    await tester.pumpWidget(
      host(
        installed.registry,
        markup: '<pre data-code-wrap="graphviz"><code>digraph {</code></pre>',
      ),
    );
    await tester.pump();
    platform.controllers.single.channels['NativeGraphviz']!.onMessageReceived(
      const JavaScriptMessage(
        message: '{"type":"error","message":"Syntax error"}',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DImagePreview), findsNothing);
    expect(find.text('Syntax error'), findsOneWidget);
    await tester.tap(find.text('View source'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CodeBlock>(find.byType(CodeBlock)).data.text,
      'digraph {',
    );
  });

  test('ships Viz.js and licenses as app assets', () async {
    const base =
        'packages/discourse_native/src/plugins/discourse_graphviz/assets';
    expect(
      await rootBundle.loadString('$base/viz-3.31.0.js'),
      contains('Viz.js 3.31.0'),
    );
    expect(
      await rootBundle.loadString('$base/LICENSE-graphviz'),
      contains('Eclipse Public License'),
    );
    for (final name in ['emscripten', 'expat', 'viz']) {
      expect(await rootBundle.loadString('$base/LICENSE-$name'), isNotEmpty);
    }
  });
}

class _Assets extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      key.endsWith('.js')
      ? Future.value('')
      : rootBundle.loadString(key, cache: cache);

  @override
  Future<ByteData> load(String key) => rootBundle.load(key);
}
