import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;

import 'support/native_ui_evidence.dart';

const _generic = '''
<aside class="onebox" data-onebox-src="https://example.com/article">
<header class="source"><a href="https://example.com/article">Example</a></header>
<article class="onebox-body"><h3><a href="https://example.com/article">A readable link preview</a></h3>
<p>This preview stays within the same reading width as a post, even in a wide conversation.</p></article>
</aside>
''';

class _PreviewPlugin implements SitePlugin, CookedElementPlugin {
  const _PreviewPlugin();
  @override
  String get name => 'preview-fixture';
  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) =>
      element.classes.contains('onebox')
      ? const DCard(
          key: ValueKey('owned-preview'),
          children: [DCardContent(child: Text('Plugin-owned preview'))],
        )
      : null;
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'OneboxReview',
    )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
  });
  testWidgets(
    'compact preview keeps its external link under content-sized constraints',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final launched = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.binding.setSurfaceSize(const Size(1440, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: CookedHtml(
                    html: _generic,
                    contentSized: true,
                    registry: PluginRegistry([]),
                    buildAsync: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(OneboxCard)).width,
        lessThanOrEqualTo(825),
      );
      await tester.tap(find.text('A readable link preview'));
      await tester.pumpAndSettle();
      expect(launched, ['https://example.com/article']);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [390.0, 1100.0, 1440.0]) {
    for (final plugin in [false, true]) {
      testWidgets('onebox width $width plugin=$plugin', (tester) async {
        await prepareNativeUiEvidence(tester);
        await tester.binding.setSurfaceSize(Size(width, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final theme = AppTheme.light;
        await tester.pumpWidget(
          MaterialApp(
            builder: nativeUiEvidenceBuilder,
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'OneboxReview'),
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: CookedHtml(
                  html: _generic,
                  registry: PluginRegistry([
                    if (plugin) const _PreviewPlugin(),
                  ]),
                  buildAsync: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = plugin
            ? find.byKey(const ValueKey('owned-preview'))
            : find.byType(OneboxCard);
        expect(card, findsOneWidget);
        expect(
          tester.getSize(card).width,
          lessThanOrEqualTo(width < 825 ? width : 825),
        );
        expect(tester.takeException(), isNull);
        if (!plugin) {
          await captureNativeUi(tester, 'chat-onebox-${width.toInt()}');
        }
      });
    }
  }
}
