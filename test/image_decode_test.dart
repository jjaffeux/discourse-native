import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:discourse_native/src/diagnostics/diagnostics_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_uploads.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/image_decode.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/blank_png.dart';
import 'support/media_pipeline.dart';

final Uint8List onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8'
  'BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  testWidgets('decodes memory images at their physical layout bound', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    late ResizeImage provider;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            provider = memoryImageForLayout(
              context,
              Uint8List.fromList([1, 2, 3]),
              logicalSize: const Size(24, 18),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(provider.width, 60);
    expect(provider.height, 45);
    expect(provider.policy, ResizeImagePolicy.fit);
    expect(provider.allowUpscaling, isFalse);
  });

  testWidgets('rounds network decode hints up to physical pixels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    late int pixels;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pixels = imagePhysicalPixels(context, 16.1);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(pixels, 41);
  });

  test('coarse decode sizes cover the request with eight per doubling', () {
    var previous = 0;
    for (var pixels = 1; pixels <= 8192; pixels++) {
      final coarse = coarseDecodePixels(pixels);
      expect(coarse, greaterThanOrEqualTo(pixels));
      expect(coarse * 8, lessThan(pixels * 9), reason: 'at most 1/8 wider');
      expect(coarse, greaterThanOrEqualTo(previous));
      expect(coarseDecodePixels(coarse), coarse);
      previous = coarse;
    }
    expect(
      {
        for (var pixels = 641; pixels <= 704; pixels++)
          coarseDecodePixels(pixels),
      },
      {704},
    );
    expect({
      for (var pixels = 1025; pixels <= 2048; pixels++)
        coarseDecodePixels(pixels),
    }, hasLength(8));
  });

  testWidgets('layout decode widths are coarse physical widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    late List<int> widths;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            widths = [
              for (final logical in [352.5, 370.0, 384.0, 384.5])
                imageDecodeWidth(context, logical),
            ];
            return const SizedBox();
          },
        ),
      ),
    );

    // 705 to 768 physical pixels share one decode; 769 starts the next.
    expect(widths, [768, 768, 768, 832]);
  });

  testWidgets('fitted memory images share one key for every bound beyond '
      'the source', (tester) async {
    PaintingBinding.instance.imageCache.clear();
    addTearDown(PaintingBinding.instance.imageCache.clear);
    final bytes = await _pngBytes(tester, width: 640, height: 427);
    Future<FittedMemoryImage> keyFor(int width) => FittedMemoryImage(
      bytes,
      width: width,
    ).obtainKey(ImageConfiguration.empty);
    final source = FittedMemoryImage(bytes, width: 640);

    // Only the first key waits, to read the encoded header.
    expect(await tester.runAsync(() => keyFor(2304)), source);
    for (final width in [640, 700, 1000, 2304, 5000]) {
      expect(keyFor(width), isA<SynchronousFuture<FittedMemoryImage>>());
      expect(await keyFor(width), source);
    }
    final wide = await _decode(tester, FittedMemoryImage(bytes, width: 5000));
    expect(wide, (width: 640, height: 427), reason: 'never upscaled');

    final narrow = FittedMemoryImage(bytes, width: 500);
    expect(await keyFor(500), narrow);
    expect(await _decode(tester, narrow), (
      width: 500,
      height: 333,
    ), reason: 'never narrower than the bound');
  });

  testWidgets('fitted memory images refuse a source over the pixel cap '
      'without decoding it', (tester) async {
    const width = 8000;
    // One row over the cap. Decoding it would allocate 200 MB.
    const height = maximumFittedImagePixels ~/ width + 1;
    final provider = FittedMemoryImage(
      blankPng(width: width, height: height),
      width: 100,
    );

    await tester.runAsync(
      () => expectLater(
        _firstFrameSize(provider),
        throwsA(
          isA<ImageTooLargeException>().having(
            (error) => (error.width, error.height),
            'size',
            (width, height),
          ),
        ),
      ),
    );
  });

  testWidgets('unreadable bytes keep their requested bound as the key', (
    tester,
  ) async {
    final provider = FittedMemoryImage(
      Uint8List.fromList([1, 2, 3]),
      width: 10,
    );

    expect(
      await tester.runAsync(() => provider.obtainKey(ImageConfiguration.empty)),
      provider,
    );
  });

  testWidgets('chat thumbnails decode no wider than their layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: ChatUploads(
              siteUrl: 'https://site.test',
              uploads: [
                ChatUpload(
                  url: '/large.png',
                  originalFilename: 'large.png',
                  kind: ChatUploadKind.image,
                  width: 1200,
                  height: 600,
                ),
                ChatUpload(
                  url: '/small.png',
                  originalFilename: 'small.png',
                  kind: ChatUploadKind.image,
                  width: 100,
                  height: 50,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final providers = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .cast<ResizeImage>()
        .toList();
    expect(providers.map((provider) => provider.width), [600, 200]);
    expect(tester.getSize(find.byType(Image).first).height, 150);
    expect(
      providers.map((provider) => provider.allowUpscaling),
      everyElement(isFalse),
    );
  });

  testWidgets('avatars and emoji share the bounded decode policy', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    const avatarUrl = 'https://site.test/avatar.png';
    const emojiUrl = 'https://site.test/emoji.png';
    final pipeline = installTestMediaPipeline(
      client: MockClient((_) async => http.Response.bytes(onePixelPng, 200)),
    );
    await Future.wait([
      pipeline.avatars.load(avatarUrl),
      pipeline.emoji.load(emojiUrl),
    ]);

    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            AvatarImage(
              url: avatarUrl,
              size: 24,
              fallback: SizedBox.square(dimension: 24),
            ),
            EmojiImage(url: emojiUrl, size: 18, alt: ':wave:'),
          ],
        ),
      ),
    );

    final providers = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .cast<ResizeImage>()
        .toList();
    expect(providers.map((provider) => provider.width), [60, 45]);
    expect(providers.map((provider) => provider.height), [60, 45]);
    expect(
      providers.map((provider) => provider.policy),
      everyElement(ResizeImagePolicy.fit),
    );
  });

  for (final svg in [false, true]) {
    testWidgets(
      'quarantines invalid ${svg ? 'SVG' : 'raster'} avatars after one diagnostic',
      (tester) async {
        final diagnostics = _RecordingDiagnosticsSink();
        addTearDown(DiagnosticsSink.install(diagnostics).close);
        final url = 'https://site.test/broken-avatar.${svg ? 'svg' : 'png'}';
        final pipeline = installTestMediaPipeline(
          client: MockClient(
            (_) async => http.Response.bytes(
              svg ? utf8.encode('<svg><g></svg>') : [1, 2, 3],
              200,
              headers: {'content-type': svg ? 'image/svg+xml' : 'image/png'},
            ),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  AvatarImage(
                    url: url,
                    size: 24,
                    fallback: const Text('First avatar'),
                  ),
                  AvatarImage(
                    url: url,
                    size: 32,
                    fallback: const Text('Second avatar'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('First avatar'), findsOneWidget);
        expect(find.text('Second avatar'), findsOneWidget);
        expect(pipeline.avatars.isCached(url), isTrue);
        expect(pipeline.avatars.cached(url), isNull);
        expect(diagnostics.operations, ['avatar.decode']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('quarantines invalid emoji bytes after one diagnostic', (
    tester,
  ) async {
    final diagnostics = _RecordingDiagnosticsSink();
    addTearDown(DiagnosticsSink.install(diagnostics).close);
    const url = 'https://site.test/broken.png';
    final pipeline = installTestMediaPipeline(
      client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            EmojiImage(url: url, size: 18, alt: ':broken:'),
            EmojiImage(url: url, size: 20, alt: ':broken:'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(':broken:'), findsNWidgets(2));
    expect(pipeline.emoji.isCached(url), isTrue);
    expect(pipeline.emoji.cached(url), isNull);
    expect(diagnostics.operations, ['emoji.decode']);
    expect(tester.takeException(), isNull);
  });
}

Future<Uint8List> _pngBytes(
  WidgetTester tester, {
  required int width,
  required int height,
}) async => (await tester.runAsync(() async {
  final image = await createTestImage(
    width: width,
    height: height,
    cache: false,
  );
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}))!;

/// Resolves [provider] through the image cache and returns the size of its
/// first frame.
Future<({int width, int height})> _decode(
  WidgetTester tester,
  ImageProvider<Object> provider,
) async => (await tester.runAsync(() => _firstFrameSize(provider)))!;

Future<({int width, int height})> _firstFrameSize(
  ImageProvider<Object> provider,
) {
  final size = Completer<({int width, int height})>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      size.complete((width: info.image.width, height: info.image.height));
      info.dispose();
      stream.removeListener(listener);
    },
    onError: (error, stackTrace) {
      size.completeError(error, stackTrace);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return size.future;
}

final class _RecordingDiagnosticsSink implements DiagnosticsSink {
  final List<String?> operations = [];

  @override
  void reportError(
    Object error,
    StackTrace stackTrace, {
    String? operation,
    String source = 'application',
    DiagnosticSeverity severity = DiagnosticSeverity.error,
    bool handled = true,
    bool degraded = true,
    String? correlationId,
  }) {
    operations.add(operation);
  }

  @override
  void recordLog({
    required String name,
    String source = 'application',
    String? component,
    String? message,
    Map<String, Object?> attributes = const {},
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? operation,
    String? correlationId,
    bool handled = true,
    bool degraded = false,
  }) {}
}
