import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/ui/foundation/mermaid_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:webview_all/webview_all.dart';

import '../support/fake_media_webview.dart';

const _source = 'flowchart TD\n    A --> B';
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
String _rendered() =>
    jsonEncode({'type': 'rendered', 'width': 600, 'height': 300, 'png': _png});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeMediaWebViewPlatform platform;
  late WebViewPlatform previous;
  late _Assets assets;
  setUp(() {
    previous = WebViewPlatform.instance ?? FakeMediaWebViewPlatform();
    platform = FakeMediaWebViewPlatform();
    WebViewPlatform.instance = platform;
    assets = _Assets();
  });
  tearDown(() => WebViewPlatform.instance = previous);

  test(
    'ships the offline runtime, renderer and license as package assets',
    () async {
      const assets = 'packages/discourse_native/src/ui/assets/mermaid';
      expect(
        await rootBundle.loadString('$assets/mermaid-11.15.0.min.js'),
        contains('11.15.0'),
      );
      expect(
        await rootBundle.loadString('$assets/render.js'),
        contains('renderNativeMermaid'),
      );
      expect(await rootBundle.loadString('$assets/LICENSE'), contains('MIT'));
    },
  );

  Widget host({
    String source = _source,
    bool dark = false,
    bool narrow = false,
  }) => DefaultAssetBundle(
    bundle: assets,
    child: MaterialApp(
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: narrow ? 320 : 600,
            child: DMermaid(source: source),
          ),
        ),
      ),
    ),
  );

  void send(String message, [FakeMediaWebViewController? controller]) =>
      (controller ?? platform.controllers.last).channels['NativeMermaid']!
          .onMessageReceived(JavaScriptMessage(message: message));

  test('author source cannot escape the offline document', () {
    const source = 'flowchart TD\nA["</script><script>alert(1)</script>"]';
    final document = html.parse(
      mermaidDocument(
        runtime: 'runtime();',
        renderer: 'renderer();',
        source: source,
        dark: false,
      ),
    );
    expect(document.querySelectorAll('script'), hasLength(3));
    expect(
      document.querySelectorAll('script').last.text,
      contains(r'\u003c/script>'),
    );
    final policy = document
        .querySelector('meta[http-equiv]')!
        .attributes['content']!;
    expect(policy, contains("default-src 'none'"));
    expect(policy, contains("script-src 'nonce-native-mermaid'"));
    expect(document.querySelectorAll('script[src],iframe,link,img'), isEmpty);
  });

  testWidgets('renders to an image and releases the native view and channel', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pump();
    expect(find.byType(DSpinner), findsOneWidget);
    final controller = platform.controllers.single;
    expect(controller.documents.single.baseUrl, isNull);
    expect(controller.documents.single.html, contains('flowchart TD'));
    final delegate = controller.delegate!;
    for (final url in [
      'https://example.com',
      'file:///etc/passwd',
      'javascript:alert(1)',
      'data:text/html,test',
    ]) {
      expect(await delegate.navigate(url), NavigationDecision.prevent);
    }
    send(_rendered());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(WebViewWidget), findsNothing);
    expect(find.byType(DSpinner), findsNothing);
    expect(controller.channels, isEmpty);
    expect(controller.documents.last.html, '<!doctype html><html></html>');
    expect(await delegate.navigate('about:blank'), NavigationDecision.prevent);
  });

  testWidgets('expand reuses artwork, zooms, resets, and closes with Escape', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    send(_rendered());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expand diagram'));
    await tester.pumpAndSettle();
    expect(platform.controllers, hasLength(1));
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    await tester.tap(find.text('Zoom in'));
    await tester.pump();
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );
    final beforePan = viewer.transformationController!.value.storage[12];
    Focus.of(tester.element(find.byType(InteractiveViewer))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(
      viewer.transformationController!.value.storage[12],
      lessThan(beforePan),
    );
    await tester.tap(find.text('Fit'));
    await tester.pump();
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.text('Expand diagram'), findsOneWidget);
  });

  testWidgets('syntax errors retain exact source for viewing and copying', (
    tester,
  ) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(host());
    send(jsonEncode({'type': 'error', 'message': 'Parse error on line 2'}));
    await tester.pumpAndSettle();
    expect(find.text('Parse error on line 2'), findsOneWidget);
    await tester.tap(find.text('Copy source'));
    await tester.pump();
    expect(copied, _source);
    expect(find.text('Copied'), findsOneWidget);
    await tester.tap(find.text('View source'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      _source,
    );
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).textDirection,
      TextDirection.ltr,
    );
  });

  testWidgets('edits and palette changes retire stale renders', (tester) async {
    await tester.pumpWidget(host());
    final stale = platform.controllers.single.channels['NativeMermaid']!;
    await tester.pumpWidget(
      host(source: 'sequenceDiagram\nA->>B: Hello', dark: true),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final latest = platform.controllers.last;
    expect(latest.documents.single.html, contains('"dark":true'));
    stale.onMessageReceived(JavaScriptMessage(message: _rendered()));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    send(_rendered());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });

  for (final stage in MediaWebViewConfigurationStage.values.where(
    (stage) => stage != MediaWebViewConfigurationStage.userScript,
  )) {
    testWidgets('unmounting during ${stage.name} cancels further setup', (
      tester,
    ) async {
      final gate = Completer<void>();
      platform.nextGate = (stage, gate.future);
      await tester.pumpWidget(host());
      final controller = platform.controllers.single;
      final admitted = List.of(controller.operations);
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await tester.pump();
      expect(controller.operations, admitted);
      expect(
        controller.documents.every(
          (document) => !document.html.contains('renderNativeMermaid'),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('timeout releases the renderer and leaves source actions', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    final callback = platform.controllers.single.channels['NativeMermaid']!;
    await tester.pump(const Duration(seconds: 21));
    expect(find.text('Diagram rendering timed out.'), findsOneWidget);
    callback.onMessageReceived(JavaScriptMessage(message: _rendered()));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('View source'), findsOneWidget);
  });

  testWidgets('oversized source does not start a WebView', (tester) async {
    await tester.pumpWidget(host(source: 'a' * 50001));
    expect(platform.controllers, isEmpty);
    expect(
      find.text('The diagram exceeds the 50,000 character limit.'),
      findsOneWidget,
    );
  });

  testWidgets('malformed image output produces a recoverable error', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    send(
      jsonEncode({'type': 'rendered', 'width': 0, 'height': 100, 'png': _png}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not read the rendered diagram.'), findsOneWidget);
    expect(find.byType(WebViewWidget), findsNothing);
  });

  testWidgets('narrow RTL and large text preserve actions without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: assets,
        child: MaterialApp(
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
          ),
          home: const Scaffold(body: DMermaid(source: _source)),
        ),
      ),
    );
    send(_rendered());
    await tester.pumpAndSettle();
    expect(find.text('Expand diagram'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Expand diagram'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Assets extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async => '';
  @override
  Future<ByteData> load(String key) => rootBundle.load(key);
}
