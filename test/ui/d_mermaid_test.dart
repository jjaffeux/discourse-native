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
        await rootBundle.loadString('$assets/mermaid-11.17.2.min.js'),
        contains('11.17.2'),
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

  Widget consumers(List<({String source, bool visible})> diagrams) =>
      DefaultAssetBundle(
        bundle: assets,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (var index = 0; index < diagrams.length; index++)
                    Offstage(
                      key: ValueKey(index),
                      offstage: !diagrams[index].visible,
                      child: TickerMode(
                        enabled: diagrams[index].visible,
                        child: DMermaid(source: diagrams[index].source),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

  testWidgets('concurrent identical consumers share one renderer and artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      consumers(List.filled(8, (source: _source, visible: true))),
    );
    await tester.pump();
    expect(platform.controllers, hasLength(1));
    expect(find.byType(WebViewWidget), findsOneWidget);
    send(_rendered());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(8));
    expect(find.byType(WebViewWidget), findsNothing);
    expect(platform.controllers.single.channels, isEmpty);
  });

  testWidgets('hidden initial consumers wait until visible before rendering', (
    tester,
  ) async {
    await tester.pumpWidget(
      consumers(List.filled(8, (source: _source, visible: false))),
    );
    await tester.pump();
    expect(platform.controllers, isEmpty);
    await tester.pumpWidget(
      consumers(List.filled(8, (source: _source, visible: true))),
    );
    await tester.pump();
    expect(platform.controllers, hasLength(1));
    send(_rendered());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(8));
  });

  testWidgets(
    'distinct renderers queue globally and time out only on admission',
    (tester) async {
      await tester.pumpWidget(
        consumers([
          for (var index = 0; index < 4; index++)
            (source: 'flowchart TD\nA --> B$index', visible: true),
        ]),
      );
      await tester.pump();
      expect(platform.controllers, hasLength(2));
      expect(find.byType(WebViewWidget), findsNWidgets(2));
      await tester.pump(const Duration(seconds: 21));
      await tester.pump();
      expect(find.text('Diagram rendering timed out.'), findsNWidgets(2));
      expect(platform.controllers, hasLength(4));
      for (final controller in platform.controllers.skip(2)) {
        send(_rendered(), controller);
      }
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(2));
      expect(platform.controllers.every((c) => c.channels.isEmpty), isTrue);
    },
  );

  testWidgets(
    'queued consumer retirement prevents its renderer from starting',
    (tester) async {
      final diagrams = [
        for (var index = 0; index < 3; index++)
          (source: 'flowchart TD\nA --> B$index', visible: true),
      ];
      await tester.pumpWidget(consumers(diagrams));
      await tester.pump();
      expect(platform.controllers, hasLength(2));
      diagrams[2] = (source: diagrams[2].source, visible: false);
      await tester.pumpWidget(consumers(diagrams));
      send(_rendered(), platform.controllers.first);
      await tester.pump();
      expect(platform.controllers, hasLength(2));
      send(_rendered(), platform.controllers.last);
      await tester.pumpAndSettle();
      diagrams[2] = (source: diagrams[2].source, visible: true);
      await tester.pumpWidget(consumers(diagrams));
      await tester.pump();
      expect(platform.controllers, hasLength(3));
      send(_rendered());
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(3));
    },
  );

  testWidgets(
    'cancelled setup retains admission until its continuation drains',
    (tester) async {
      final gate = Completer<void>();
      platform.nextGate = (
        MediaWebViewConfigurationStage.javaScript,
        gate.future,
      );
      final diagrams = [
        for (var index = 0; index < 3; index++)
          (source: 'flowchart TD\nA --> B$index', visible: true),
      ];
      await tester.pumpWidget(consumers(diagrams));
      final retired = platform.controllers.first;
      diagrams[0] = (source: diagrams[0].source, visible: false);
      await tester.pumpWidget(consumers(diagrams));
      await tester.pump();
      expect(platform.controllers, hasLength(2));
      gate.complete();
      await tester.pump();
      expect(retired.operations, [MediaWebViewConfigurationStage.javaScript]);
      expect(platform.controllers, hasLength(3));
      for (final controller in platform.controllers.skip(1)) {
        send(_rendered(), controller);
      }
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(2));
    },
  );

  testWidgets('one visible duplicate retains the mounted renderer on handoff', (
    tester,
  ) async {
    await tester.pumpWidget(
      consumers(List.filled(2, (source: _source, visible: true))),
    );
    await tester.pump();
    expect(platform.controllers, hasLength(1));
    final renderer = tester.element(find.byType(WebViewWidget));
    final controller = platform.controllers.single;
    await tester.pumpWidget(
      consumers([
        (source: _source, visible: false),
        (source: _source, visible: true),
      ]),
    );
    await tester.pump();
    expect(platform.controllers, hasLength(1));
    expect(tester.element(find.byType(WebViewWidget)), same(renderer));
    expect(controller.channels, contains('NativeMermaid'));
    expect(controller.documents, hasLength(1));
    send(_rendered());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(
      consumers(List.filled(2, (source: _source, visible: true))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(2));
    expect(platform.controllers, hasLength(1));
  });

  testWidgets('unmounting the first duplicate keeps shared rendering alive', (
    tester,
  ) async {
    Widget pair(bool first) => DefaultAssetBundle(
      bundle: assets,
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              if (first)
                const DMermaid(key: ValueKey('first'), source: _source),
              const DMermaid(key: ValueKey('second'), source: _source),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(pair(true));
    await tester.pump();
    final renderer = tester.element(find.byType(WebViewWidget));
    final controller = platform.controllers.single;
    await tester.pumpWidget(pair(false));
    await tester.pump();
    expect(tester.element(find.byType(WebViewWidget)), same(renderer));
    expect(controller.channels, contains('NativeMermaid'));
    send(_rendered());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(platform.controllers, hasLength(1));
  });

  testWidgets('a surviving overlay root resumes after the render host closes', (
    tester,
  ) async {
    Widget roots(bool first) => DefaultAssetBundle(
      bundle: assets,
      child: MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              if (first)
                const Expanded(
                  key: ValueKey('first'),
                  child: _DiagramOverlay(),
                ),
              const Expanded(key: ValueKey('second'), child: _DiagramOverlay()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(roots(true));
    await tester.pump();
    expect(platform.controllers, hasLength(1));
    final retired = platform.controllers.single;
    final callback = retired.channels['NativeMermaid']!;
    await tester.pumpWidget(roots(false));
    await tester.pump();
    await tester.pump();
    expect(platform.controllers, hasLength(2));
    expect(retired.channels, isEmpty);
    expect(retired.documents.last.html, '<!doctype html><html></html>');
    callback.onMessageReceived(JavaScriptMessage(message: _rendered()));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    send(_rendered());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Could not start the diagram renderer.'), findsNothing);
  });

  testWidgets(
    'last visible consumer cancels and resumes with a fresh renderer',
    (tester) async {
      await tester.pumpWidget(consumers([(source: _source, visible: true)]));
      await tester.pump();
      final retired = platform.controllers.single;
      final callback = retired.channels['NativeMermaid']!;
      await tester.pumpWidget(consumers([(source: _source, visible: false)]));
      await tester.pump();
      expect(retired.channels, isEmpty);
      expect(retired.documents.last.html, '<!doctype html><html></html>');
      await tester.pump(const Duration(seconds: 21));
      callback.onMessageReceived(JavaScriptMessage(message: _rendered()));
      await tester.pump();
      await tester.pumpWidget(consumers([(source: _source, visible: true)]));
      await tester.pump();
      expect(platform.controllers, hasLength(2));
      expect(find.byType(Image), findsNothing);
      expect(find.text('Diagram rendering timed out.'), findsNothing);
      send(_rendered());
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
    },
  );

  testWidgets('backgrounding releases work and foregrounding resumes it', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(host());
    final retired = platform.controllers.single;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    await tester.pump();
    expect(retired.channels, isEmpty);
    expect(retired.documents.last.html, '<!doctype html><html></html>');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(platform.controllers, hasLength(2));
    send(_rendered());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('shared errors release admission and allow a later retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      consumers([
        (source: _source, visible: true),
        (source: _source, visible: true),
        (source: 'flowchart TD\nA --> C', visible: true),
        (source: 'flowchart TD\nA --> D', visible: true),
      ]),
    );
    await tester.pump();
    expect(platform.controllers, hasLength(2));
    send(
      jsonEncode({'type': 'error', 'message': 'Parse error'}),
      platform.controllers.first,
    );
    await tester.pump();
    expect(find.text('Parse error'), findsNWidgets(2));
    await tester.pump();
    expect(platform.controllers, hasLength(3));
    for (final controller in platform.controllers.skip(1)) {
      send(_rendered(), controller);
    }
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host());
    expect(platform.controllers, hasLength(4));
    send(_rendered());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('stuck retired setup gives queued consumers a bounded outcome', (
    tester,
  ) async {
    final gate = Completer<void>();
    assets = _GatedAssets(gate.future);
    final diagrams = [
      for (var index = 0; index < 3; index++)
        (source: 'flowchart TD\nA --> B$index', visible: true),
    ];
    await tester.pumpWidget(consumers(diagrams));
    await tester.pump();
    expect(platform.controllers, hasLength(2));
    await tester.pump(const Duration(seconds: 21));
    expect(find.text('Diagram rendering timed out.'), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 21));
    expect(find.text('Could not start the diagram renderer.'), findsOneWidget);
    expect(platform.controllers, hasLength(2));
    diagrams[2] = (source: 'flowchart TD\nA --> C', visible: true);
    await tester.pumpWidget(consumers(diagrams));
    expect(find.text('Could not start the diagram renderer.'), findsOneWidget);
    expect(platform.controllers, hasLength(2));
    gate.complete();
    await tester.pumpAndSettle();
    diagrams[2] = (source: 'flowchart TD\nA --> D', visible: true);
    await tester.pumpWidget(consumers(diagrams));
    await tester.pump();
    expect(platform.controllers, hasLength(3));
    send(_rendered());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Could not start the diagram renderer.'), findsNothing);
    expect(
      platform.controllers.take(2).every((c) => c.channels.isEmpty),
      isTrue,
    );
  });

  testWidgets(
    'bounds total admitted distinct jobs with recoverable source actions',
    (tester) async {
      await tester.pumpWidget(
        consumers([
          for (var index = 0; index < 33; index++)
            (source: 'flowchart TD\nA --> B$index', visible: true),
        ]),
      );
      await tester.pump();
      expect(platform.controllers, hasLength(2));
      expect(
        find.text('Could not start the diagram renderer.'),
        findsOneWidget,
      );
      expect(find.text('View source'), findsNWidgets(33));
    },
  );

  testWidgets('render keys distinguish brightness and asset bundle identity', (
    tester,
  ) async {
    final firstBundle = _EqualAssets();
    final secondBundle = _EqualAssets();
    expect(firstBundle, secondBundle);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                for (final (bundle, brightness) in [
                  (firstBundle, Brightness.light),
                  (firstBundle, Brightness.dark),
                  (secondBundle, Brightness.light),
                ])
                  DefaultAssetBundle(
                    bundle: bundle,
                    child: Theme(
                      data: ThemeData(brightness: brightness),
                      child: const DMermaid(source: _source),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(platform.controllers, hasLength(2));
    expect(
      platform.controllers[0].documents.single.html,
      contains('"dark":false'),
    );
    expect(
      platform.controllers[1].documents.single.html,
      contains('"dark":true'),
    );
    send(_rendered(), platform.controllers.first);
    await tester.pump();
    await tester.pump();
    expect(platform.controllers, hasLength(3));
    for (final controller in platform.controllers.skip(1)) {
      send(_rendered(), controller);
    }
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(3));
  });

  testWidgets('asset load failures reach all consumers and free the queue', (
    tester,
  ) async {
    assets = _FailingAssets();
    await tester.pumpWidget(
      consumers([
        (source: _source, visible: true),
        (source: _source, visible: true),
        (source: 'flowchart TD\nA --> C', visible: true),
        (source: 'flowchart TD\nA --> D', visible: true),
      ]),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Could not start the diagram renderer.'),
      findsNWidgets(4),
    );
    expect(platform.controllers, hasLength(3));
    expect(platform.controllers.every((c) => c.channels.isEmpty), isTrue);
    expect(find.byType(WebViewWidget), findsNothing);
  });

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
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    expect(find.byType(DSpinner), findsNothing);
    expect(tester.getSize(find.byType(DSkeleton)).height, 160);
    expect(find.text('Rendering diagram'), findsNothing);
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
    expect(find.byType(DSkeletonRegion), findsNothing);
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
    await tester.pump();
    await tester.pump();
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

class _EqualAssets extends _Assets {
  @override
  bool operator ==(Object other) => other is _EqualAssets;

  @override
  int get hashCode => 0;
}

class _FailingAssets extends _Assets {
  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      throw StateError('Renderer assets unavailable');
}

class _GatedAssets extends _Assets {
  _GatedAssets(this.ready);

  final Future<void> ready;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    await ready;
    return '';
  }
}

class _DiagramOverlay extends StatefulWidget {
  const _DiagramOverlay();

  @override
  State<_DiagramOverlay> createState() => _DiagramOverlayState();
}

class _DiagramOverlayState extends State<_DiagramOverlay> {
  late final _entry = OverlayEntry(
    builder: (_) => const Align(
      alignment: Alignment.topCenter,
      child: DMermaid(source: _source),
    ),
  );

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LookupBoundary(child: Overlay(initialEntries: [_entry]));
}
