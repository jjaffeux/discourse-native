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

  group('srcsetCandidate', () {
    const src = 'https://example.com/a_690x388.png';
    const oneAndAHalf = 'https://example.com/a_1035x582.png';
    const two = 'https://example.com/a_1380x776.png';
    // What Discourse's post processor writes by default.
    const discourse = '$src, $oneAndAHalf 1.5x, $two 2x';

    String at(double ratio, {String? srcset = discourse}) =>
        srcsetCandidate(src: src, srcset: srcset, devicePixelRatio: ratio);

    test('takes the smallest density that covers the screen', () {
      expect(at(1), src);
      expect(at(1.25), oneAndAHalf);
      expect(at(1.5), oneAndAHalf);
      expect(at(1.75), two);
      expect(at(2), two);
    });

    test('takes the largest density on a denser screen', () {
      expect(at(3), two);
    });

    test('keeps a ratio that rounds past a density on that density', () {
      expect(at(1.0000001), src);
      expect(at(1.5000001), oneAndAHalf);
      expect(at(1.02), oneAndAHalf);
    });

    test('stands src in for a 1x the srcset does not list', () {
      expect(at(1, srcset: '$two 2x'), src);
      expect(at(2, srcset: '$two 2x'), two);
      expect(
        at(1, srcset: 'https://example.com/listed.png 1x, $two 2x'),
        'https://example.com/listed.png',
      );
    });

    test('keeps the first candidate of each density', () {
      expect(at(2, srcset: '$two 2x, https://example.com/later.png 2.0x'), two);
    });

    test('returns a relative candidate as written', () {
      expect(
        at(2, srcset: '/uploads/a_690x388.png, /uploads/a_1380x776.png 2x'),
        '/uploads/a_1380x776.png',
      );
    });

    test('reads a URL up to whitespace, commas and all', () {
      const srcset =
          'https://example.com/a,1.png 1x,https://example.com/a,2.png 2x';

      expect(at(1, srcset: srcset), 'https://example.com/a,1.png');
      expect(at(2, srcset: srcset), 'https://example.com/a,2.png');
    });

    test('ends a URL at trailing commas, leaving it 1x', () {
      const srcset = 'https://example.com/one.png,, $two 2x';

      expect(at(1, srcset: srcset), 'https://example.com/one.png');
      expect(at(2, srcset: srcset), two);
    });

    test('keeps a comma within parentheses inside its descriptor', () {
      // Split at every comma, `syntax)` would be a 1x candidate.
      const srcset =
          'https://example.com/bad.png 1.5x (future, syntax), $two 2x';

      expect(at(1, srcset: srcset), src);
      expect(at(1.5, srcset: srcset), two);
    });

    test('skips candidates the standard rejects', () {
      for (final descriptor in [
        '2',
        '2X',
        'x',
        '2.x',
        '-2x',
        'NaNx',
        '1e999x',
        '2x 3x',
        '2x 100h',
        '100h',
        '(2x)',
        '2x (future)',
      ]) {
        expect(
          at(3, srcset: 'https://example.com/bad.png $descriptor'),
          src,
          reason: descriptor,
        );
      }
      expect(at(3, srcset: 'https://example.com/bad.png 3X, $two 2x'), two);
    });

    test('falls back to src for width descriptors', () {
      expect(at(2, srcset: '$src 690w, $two 1380w'), src);
      expect(at(2, srcset: '$two 2x, $oneAndAHalf 1035w'), src);
      expect(at(2, srcset: '$two 2x, $oneAndAHalf 1035w 582h'), src);
    });

    test('falls back to src without a usable srcset', () {
      for (final srcset in [null, '', ' , ,, ', 'not a srcset, at all']) {
        expect(at(2, srcset: srcset), src, reason: srcset);
      }
    });
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
