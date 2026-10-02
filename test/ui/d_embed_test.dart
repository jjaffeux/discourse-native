import 'dart:async';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/ui/foundation/embed_document.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:webview_all/webview_all.dart';

import '../support/fake_media_webview.dart';

final _embedUri = Uri.parse('https://embed.example.com/post/first/?embed=true');
final _externalUri = Uri.parse('https://example.com/post/first/');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeMediaWebViewPlatform platform;
  late WebViewPlatform previous;
  late List<Uri> opened;
  late List<Object> errors;

  setUp(() {
    previous = WebViewPlatform.instance ?? FakeMediaWebViewPlatform();
    platform = FakeMediaWebViewPlatform();
    WebViewPlatform.instance = platform;
    opened = [];
    errors = [];
  });
  tearDown(() => WebViewPlatform.instance = previous);

  Widget host({
    Uri? uri,
    DEmbedPresentation presentation = DEmbedPresentation.card,
  }) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DEmbed(
          presentation: presentation,
          uri: uri ?? _embedUri,
          origins: const {
            'https://embed.example.com',
            'https://redirect.example.com',
          },
          title: 'Example post',
          externalUri: _externalUri,
          height: 300,
          resizeMessageType: 'resize.embed',
          onOpenLink: opened.add,
          onError: (error, _) => errors.add(error),
        ),
      ),
    ),
  );

  void send(String message, [FakeMediaWebViewController? controller]) =>
      (controller ?? platform.controllers.last).channels['NativeEmbed']!
          .onMessageReceived(JavaScriptMessage(message: message));

  test(
    'iframe attributes and script values cannot escape the host document',
    () {
      const hostile = '</script><script>unexpected()</script>"';
      final document = html.parse(
        embedDocument(
          uri: _embedUri,
          title: hostile,
          origins: const {'https://embed.example.com', hostile},
          resizeMessageType: hostile,
        ),
      );
      expect(document.querySelectorAll('script'), hasLength(1));
      expect(document.querySelectorAll('iframe'), hasLength(1));
      expect(document.querySelector('iframe')!.attributes['title'], hostile);
      expect(
        document.querySelector('script')!.text,
        contains(r'\u003c/script>'),
      );
    },
  );

  testWidgets(
    'loads inline and stays inside the card border after bounded resizes',
    (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();
      expect(find.byType(DSpinner), findsOneWidget);
      expect(tester.getSize(find.byType(WebViewWidget)).height, 300);
      final controller = platform.controllers.single;
      expect(controller.documents.single.baseUrl, 'https://embed.example.com/');
      controller.delegate!.onPageFinished!('https://embed.example.com/');
      await tester.pump();
      expect(find.byType(DSpinner), findsOneWidget);
      send('loaded');
      send('{"height":420}');
      await tester.pumpAndSettle();
      expect(find.byType(DSpinner), findsNothing);
      expect(tester.getSize(find.byType(WebViewWidget)).height, 420);
      expect(find.text('Open in browser'), findsNothing);
      expect(
        tester.getBottomLeft(find.byType(WebViewWidget)),
        tester.getBottomLeft(find.byType(DCard)) + const Offset(1, -1),
      );
      expect(
        tester.getBottomRight(find.byType(WebViewWidget)),
        tester.getBottomRight(find.byType(DCard)) + const Offset(-1, -1),
      );
      for (final bad in [
        'bad',
        '[]',
        '{"height":0}',
        '{"height":-2}',
        '{"height":"400"}',
      ]) {
        send(bad);
      }
      await tester.pump();
      expect(tester.getSize(find.byType(WebViewWidget)).height, 420);
      send('{"height":1000000}');
      await tester.pump();
      expect(tester.getSize(find.byType(WebViewWidget)).height, 2000);
      send('{"height":1}');
      await tester.pump();
      expect(tester.getSize(find.byType(WebViewWidget)).height, 120);
      expect(
        tester.getBottomLeft(find.byType(WebViewWidget)),
        tester.getBottomLeft(find.byType(DCard)) + const Offset(1, -1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.channels, isEmpty);
      expect(controller.documents.last.html, isNot(contains('<iframe')));
    },
  );

  testWidgets(
    'preserves provider pixels at all four corners after loading and resizing',
    (tester) async {
      const surfaceColor = Color(0xFFFF0000);
      platform.view = const ColoredBox(color: surfaceColor);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: host(presentation: DEmbedPresentation.provider),
        ),
      );
      await tester.pump();
      send('loaded');
      await tester.pumpAndSettle();

      for (final height in [300, 420]) {
        send('{"height":$height}');
        await tester.pumpAndSettle();
        final bounds = tester.getRect(find.byType(WebViewWidget));
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final pixels = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            for (final point in [
              bounds.topLeft + const Offset(1, 1),
              bounds.topRight + const Offset(-2, 1),
              bounds.bottomLeft + const Offset(1, -2),
              bounds.bottomRight + const Offset(-2, -2),
            ]) {
              final offset =
                  (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
              expect(
                pixels.buffer.asUint8List(offset, 4),
                [255, 0, 0, 255],
                reason: 'Provider content must retain its own corner at $point',
              );
            }
          } finally {
            image.dispose();
          }
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'allows provider redirects and sends other destinations to the caller',
    (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();
      final delegate = platform.controllers.single.delegate!;
      expect(
        await delegate.navigate('about:blank'),
        NavigationDecision.navigate,
      );
      expect(
        await delegate.navigate(_embedUri.toString(), isMainFrame: false),
        NavigationDecision.navigate,
      );
      expect(
        await delegate.navigate(
          'https://redirect.example.com/post/first/?embed=true',
          isMainFrame: false,
        ),
        NavigationDecision.navigate,
      );
      expect(
        await delegate.navigate(_externalUri.toString(), isMainFrame: false),
        NavigationDecision.prevent,
      );
      expect(opened, [_externalUri]);
      for (final url in [
        'javascript:alert(1)',
        'file:///private/file',
        'https://user@example.com/post',
      ]) {
        expect(await delegate.navigate(url), NavigationDecision.prevent);
      }
      expect(opened, [_externalUri]);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        await delegate.navigate('about:blank'),
        NavigationDecision.navigate,
      );
      expect(
        await delegate.navigate('https://example.com/stale'),
        NavigationDecision.prevent,
      );
      expect(opened, [_externalUri]);
    },
  );

  testWidgets(
    'macOS clips pointer input and forwards wheel input to the reader',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var taps = 0;
      platform.view = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => taps++,
        child: const SizedBox.expand(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                height: 300,
                child: SingleChildScrollView(
                  controller: scroll,
                  child: Column(
                    children: [
                      const SizedBox(height: 100),
                      DEmbed(
                        uri: _embedUri,
                        origins: const {'https://embed.example.com'},
                        title: 'Example post',
                        externalUri: _externalUri,
                        height: 300,
                        onOpenLink: opened.add,
                      ),
                      const SizedBox(height: 600),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      send('loaded');
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 250));
      expect(taps, 1);
      await tester.tapAt(const Offset(200, 320));
      expect(taps, 1);
      await tester.tapAt(const Offset(0.5, 250));
      expect(taps, 1);

      Future<void> wheel(Offset point) =>
          tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'org.discourse.native/youtube_scroll',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('scroll', {
                'x': point.dx,
                'y': point.dy,
                'deltaY': 40,
              }),
            ),
            (_) {},
          );

      await wheel(const Offset(200, 320));
      await tester.pump();
      expect(scroll.offset, 0);
      await wheel(const Offset(200, 250));
      await tester.pump();
      expect(scroll.offset, 40);

      send('{"height":420}');
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(WebViewWidget)).height, 420);
      expect(
        tester.getBottomLeft(find.byType(WebViewWidget)),
        tester.getBottomLeft(find.byType(DCard)) + const Offset(1, -1),
      );
      expect(platform.controllers, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await wheel(const Offset(200, 250));
      expect(platform.controllers.single.channels, isEmpty);
      expect(find.byType(WebViewWidget), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  for (final reverse in [false, true]) {
    testWidgets(
      'native embed wheel direction matches its reader (reverse: $reverse)',
      (tester) async {
        platform.view = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: const SizedBox.expand(),
        );
        final scroll = ScrollController(initialScrollOffset: 200);
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox.expand(
              child: SingleChildScrollView(
                controller: scroll,
                reverse: reverse,
                child: Column(
                  children: [
                    const SizedBox(height: 400),
                    DEmbed(
                      uri: _embedUri,
                      origins: const {'https://embed.example.com'},
                      title: 'Example post',
                      externalUri: _externalUri,
                      height: 300,
                      onOpenLink: opened.add,
                    ),
                    const SizedBox(height: 400),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        send('loaded');
        await tester.pumpAndSettle();
        for (final delta in [40.0, -40.0]) {
          final before = scroll.offset;
          // Move over ordinary reader content, then over the native surface.
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: const Offset(20, 580),
              scrollDelta: Offset(0, delta),
            ),
          );
          await tester.pumpAndSettle();
          expect(scroll.offset, before + (reverse ? -delta : delta));
          final point = tester.getCenter(find.byType(WebViewWidget));
          await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'org.discourse.native/youtube_scroll',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('scroll', {
                'x': point.dx,
                'y': point.dy,
                'deltaY': delta,
              }),
            ),
            (_) {},
          );
          await tester.pumpAndSettle();
          expect(scroll.offset, before + (reverse ? -2 * delta : 2 * delta));
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    );
  }

  testWidgets('HTTP failures show retry and retain the browser destination', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(presentation: DEmbedPresentation.provider));
    await tester.pump();
    final controller = platform.controllers.single;
    controller.delegate!.onHttpError!(
      const HttpResponseError(
        response: WebResourceResponse(uri: null, statusCode: 403),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load this embed.'), findsOneWidget);
    expect(find.byType(WebViewWidget), findsNothing);
    expect(errors, hasLength(1));
    final link = find.bySemanticsLabel('Open in browser');
    expect(
      tester.getSemantics(link),
      isSemantics(isLink: true, isButton: false, hasTapAction: true),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, [_externalUri]);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(platform.controllers, hasLength(2));
    expect(find.byType(WebViewWidget), findsOneWidget);
    send('loaded');
    await tester.pumpAndSettle();
    expect(find.text('Could not load this embed.'), findsNothing);
    expect(find.text('Open in browser'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('ignores resource failures but handles a failed embed document', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pump();
    final delegate = platform.controllers.single.delegate!;
    delegate.onWebResourceError!(
      const WebResourceError(
        errorCode: -1,
        description: 'tracker failed',
        isForMainFrame: false,
        url: 'https://tracker.example.com/pixel',
      ),
    );
    expect(errors, isEmpty);
    delegate.onWebResourceError!(
      WebResourceError(
        errorCode: -1,
        description: 'embed failed',
        isForMainFrame: false,
        url: _embedUri.toString(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load this embed.'), findsOneWidget);
    expect(errors, hasLength(1));
  });

  testWidgets('times out instead of leaving a blank frame', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(find.text('Could not load this embed.'), findsOneWidget);
    expect(errors.single, isA<TimeoutException>());
  });

  testWidgets('invalid source URLs do not create a platform view', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(uri: Uri.parse('https://untrusted.example/post')),
    );
    await tester.pumpAndSettle();
    expect(platform.controllers, isEmpty);
    expect(find.text('Could not load this embed.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await tester.tap(find.text('Open in browser'));
    expect(opened, [_externalUri]);
  });

  for (final stage in [
    MediaWebViewConfigurationStage.javaScript,
    MediaWebViewConfigurationStage.background,
    MediaWebViewConfigurationStage.navigation,
  ]) {
    for (final replace in [false, true]) {
      testWidgets(
        '${replace ? 'replacement' : 'disposal'} during ${stage.name} retires setup',
        (tester) async {
          final gate = Completer<void>();
          platform.nextGate = (stage, gate.future);
          await tester.pumpWidget(host());
          final old = platform.controllers.single;
          final operations = List.of(old.operations);
          if (replace) {
            await tester.pumpWidget(
              host(uri: Uri.parse('https://embed.example.com/post/second/')),
            );
            await tester.pump();
            send('loaded');
            expect(
              platform.controllers.last.documents.single.html,
              contains('/post/second/'),
            );
          } else {
            await tester.pumpWidget(const SizedBox.shrink());
          }
          gate.complete();
          await tester.pumpAndSettle();
          expect(old.operations, operations);
          expect(old.channels, isEmpty);
          expect(
            old.documents.where(
              (document) => document.html.contains('<iframe'),
            ),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
