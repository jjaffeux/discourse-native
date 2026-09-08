import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/inline_video.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/shell/youtube_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://forum.example';
const _posterUrl = '$_siteUrl/secure-uploads/original/poster.png';

void main() {
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    addTearDown(PaintingBinding.instance.imageCache.clear);
  });
  for (final youtube in [false, true]) {
    for (final cached in [false, true]) {
      testWidgets(
        '${youtube ? 'YouTube' : 'uploaded'} 8K poster bounds retained pixels '
        'and reuses the decoded cache (cached bytes: $cached)',
        (tester) async {
          tester.view.devicePixelRatio = 2;
          addTearDown(tester.view.reset);
          final harness = _PosterHarness(
            File('test/fixtures/8k.png').readAsBytesSync(),
          );
          if (cached) await harness.preload();
          final sizes = <Size>[];
          final previousOnCreate = ui.Image.onCreate;
          ui.Image.onCreate = (image) {
            previousOnCreate?.call(image);
            sizes.add(Size(image.width.toDouble(), image.height.toDouble()));
          };
          addTearDown(() => ui.Image.onCreate = previousOnCreate);

          await tester.pumpWidget(harness.app(youtube: youtube));
          await _waitForImage(tester);
          final raw = tester.widget<RawImage>(find.byType(RawImage));
          final decoded = raw.image!;
          final size = tester.getSize(find.byType(RawImage));
          final retainedPixels = decoded.width * decoded.height;
          debugPrint(
            'POSTER ${youtube ? 'YouTube' : 'uploaded'} cached=$cached '
            'layout=$size dpr=2 decoded=${decoded.width}x${decoded.height} '
            'retainedPixels=$retainedPixels rgbaBytes=${retainedPixels * 4} '
            'cacheBytes=${PaintingBinding.instance.imageCache.currentSizeBytes} '
            'created=$sizes',
          );
          expect(size, Size(320, youtube ? 200 : 180));
          expect(raw.fit, BoxFit.cover);
          expect(decoded.width / decoded.height, closeTo(16 / 9, 0.01));
          expect(decoded.width, greaterThanOrEqualTo(640));
          expect(decoded.height, greaterThanOrEqualTo(youtube ? 400 : 360));
          expect(retainedPixels, lessThanOrEqualTo(youtube ? 285000 : 230400));
          expect(
            PaintingBinding.instance.imageCache.currentSizeBytes,
            retainedPixels * 4,
          );
          expect(sizes, isNotEmpty);
          expect(
            sizes.every((size) => size.width * size.height <= 285000),
            isTrue,
          );
          final bytes = harness.repository.cached(
            siteUrl: _siteUrl,
            url: _posterUrl,
          )!;
          expect(
            PaintingBinding.instance.imageCache.containsKey(
              MemoryImage(bytes.bytes),
            ),
            isFalse,
          );
          expect(harness.requests, hasLength(1));
          expect(
            harness.requests.single.headers['User-Api-Key'],
            'account-key',
          );
          expect(
            harness.requests.single.headers['User-Api-Client-Id'],
            'test-client',
          );
          expect(harness.playerBuilds, 0);
          expect(
            find.bySemanticsLabel('Play video: Poster clip'),
            findsOneWidget,
          );

          final handle = decoded.clone();
          addTearDown(handle.dispose);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(harness.app(youtube: youtube));
          await _waitForImage(tester);
          expect(
            handle.isCloneOf(
              tester.widget<RawImage>(find.byType(RawImage)).image!,
            ),
            isTrue,
          );
          expect(harness.requests, hasLength(1));
          expect(PaintingBinding.instance.imageCache.currentSize, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final sample in [
      (
        name: 'normal',
        source: const Size(1280, 720),
        uploaded: const Size(640, 360),
        youtube: const Size(711, 400),
      ),
      (
        name: 'very wide',
        source: const Size(6400, 800),
        uploaded: const Size(2880, 360),
        youtube: const Size(3200, 400),
      ),
      (
        name: 'very tall',
        source: const Size(800, 6400),
        uploaded: const Size(640, 5120),
        youtube: const Size(640, 5120),
      ),
      (
        name: 'small',
        source: const Size(80, 40),
        uploaded: const Size(80, 40),
        youtube: const Size(80, 40),
      ),
      (
        name: 'short',
        source: const Size(1280, 80),
        uploaded: const Size(1280, 80),
        youtube: const Size(1280, 80),
      ),
      (
        name: 'narrow',
        source: const Size(80, 1280),
        uploaded: const Size(80, 1280),
        youtube: const Size(80, 1280),
      ),
    ]) {
      testWidgets(
        '${youtube ? 'YouTube' : 'uploaded'} ${sample.name} poster preserves cover crop without decoding an upscale',
        (tester) async {
          tester.view.devicePixelRatio = 2;
          addTearDown(tester.view.reset);
          final harness = _PosterHarness(
            await _pngBytes(tester, sample.source),
          );
          await tester.pumpWidget(harness.app(youtube: youtube));
          final expected = youtube ? sample.youtube : sample.uploaded;
          await _waitForImage(tester, expected: expected);
          final raw = tester.widget<RawImage>(find.byType(RawImage));
          expect(raw.fit, BoxFit.cover);
          final viewport = tester.getSize(find.byType(RawImage));
          final originalCrop = applyBoxFit(
            BoxFit.cover,
            sample.source,
            viewport,
          );
          final decodedCrop = applyBoxFit(raw.fit!, expected, viewport);
          expect(
            decodedCrop.source.width / expected.width,
            closeTo(originalCrop.source.width / sample.source.width, 0.002),
          );
          expect(
            decodedCrop.source.height / expected.height,
            closeTo(originalCrop.source.height / sample.source.height, 0.002),
          );
          expect(decodedCrop.destination, viewport);
          expect(
            PaintingBinding.instance.imageCache.currentSizeBytes,
            expected.width * expected.height * 4,
          );
          debugPrint(
            'CONTROL ${youtube ? 'YouTube' : 'uploaded'} ${sample.name} source=${sample.source} decoded=$expected',
          );
          expect(harness.playerBuilds, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '${youtube ? 'YouTube' : 'uploaded'} poster follows size, DPR, and source changes and bounds cached variants',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final first = await _pngBytes(tester, const Size(1280, 720));
        final replacement = await _pngBytes(tester, const Size(720, 1280));
        final harness = _PosterHarness(
          first,
          respond: (request) async => http.Response.bytes(
            request.url.path.endsWith('replacement.png') ? replacement : first,
            200,
          ),
        );
        await tester.pumpWidget(harness.app(youtube: youtube));
        await _waitForImage(
          tester,
          expected: youtube ? const Size(356, 200) : const Size(320, 180),
        );
        final state = tester.state(find.byType(SiteImage));
        await tester.pumpWidget(harness.app(youtube: youtube, width: 400));
        await _waitForImage(tester, expected: const Size(400, 225));
        tester.view.devicePixelRatio = 2;
        await tester.pump();
        await _waitForImage(tester, expected: const Size(800, 450));
        await tester.pumpWidget(
          harness.app(
            youtube: youtube,
            width: 400,
            url: '$_siteUrl/replacement.png',
          ),
        );
        await _waitForImage(tester, expected: const Size(720, 1280));
        expect(tester.state(find.byType(SiteImage)), same(state));
        expect(harness.requests.map((request) => request.url.toString()), [
          _posterUrl,
          '$_siteUrl/replacement.png',
        ]);
        expect(PaintingBinding.instance.imageCache.currentSize, 4);
        final firstPixels = youtube ? 356 * 200 : 320 * 180;
        expect(
          PaintingBinding.instance.imageCache.currentSizeBytes,
          (firstPixels + 400 * 225 + 800 * 450 + 720 * 1280) * 4,
        );
        expect(harness.playerBuilds, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${youtube ? 'YouTube' : 'uploaded'} poster retires a pending source without decoding its late response',
      (tester) async {
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final oldResponse = Completer<http.Response>();
        final firstRequested = Completer<void>();
        final first = File('test/fixtures/8k.png').readAsBytesSync();
        final replacement = await _pngBytes(tester, const Size(80, 40));
        addTearDown(() {
          if (!oldResponse.isCompleted) {
            oldResponse.complete(http.Response.bytes(first, 200));
          }
        });
        final harness = _PosterHarness(
          first,
          respond: (request) {
            if (request.url.toString() == _posterUrl) {
              firstRequested.complete();
              return oldResponse.future;
            }
            return Future.value(http.Response.bytes(replacement, 200));
          },
        );
        final sizes = <Size>[];
        final previousOnCreate = ui.Image.onCreate;
        ui.Image.onCreate = (image) {
          previousOnCreate?.call(image);
          sizes.add(Size(image.width.toDouble(), image.height.toDouble()));
        };
        addTearDown(() => ui.Image.onCreate = previousOnCreate);
        await tester.pumpWidget(harness.app(youtube: youtube));
        await firstRequested.future;
        expect(find.byType(RawImage), findsNothing);
        expect(
          find.bySemanticsLabel('Play video: Poster clip'),
          findsOneWidget,
        );
        expect(harness.playerBuilds, 0);
        await tester.pumpWidget(
          harness.app(youtube: youtube, url: '$_siteUrl/replacement.png'),
        );
        await _waitForImage(tester, expected: const Size(80, 40));
        oldResponse.complete(http.Response.bytes(first, 200));
        await harness.repository.load(siteUrl: _siteUrl, url: _posterUrl);
        await tester.pumpAndSettle();
        expect(sizes, isNotEmpty);
        expect(sizes.toSet(), {const Size(80, 40)});
        expect(harness.requests, hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );

    for (final response in ['SVG', 'invalid raster', 'HTTP error']) {
      testWidgets(
        '${youtube ? 'YouTube' : 'uploaded'} $response poster keeps an accessible lazy play action',
        (tester) async {
          final bytes = response == 'SVG'
              ? Uint8List.fromList(
                  utf8.encode(
                    '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="80"><rect width="40" height="80" fill="red"/></svg>',
                  ),
                )
              : Uint8List.fromList([1, 2, 3]);
          final harness = _PosterHarness(
            bytes,
            respond: (_) async => http.Response.bytes(
              bytes,
              response == 'HTTP error' ? 404 : 200,
            ),
          );
          await harness.preload();
          await tester.pumpWidget(harness.app(youtube: youtube));
          if (response == 'SVG') {
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<SvgPicture>(
                    find.descendant(
                      of: find.byType(SiteImage),
                      matching: find.byType(SvgPicture),
                    ),
                  )
                  .fit,
              BoxFit.cover,
            );
          } else {
            await _waitUntil(
              tester,
              () => find.byType(RawImage).evaluate().isEmpty,
              'the poster error fallback',
            );
          }
          expect(
            find.byType(Image),
            response == 'SVG' || response == 'HTTP error'
                ? findsNothing
                : findsOneWidget,
          );
          expect(
            find.bySemanticsLabel('Play video: Poster clip'),
            findsOneWidget,
          );
          expect(harness.playerBuilds, 0);
          await tester.tap(find.bySemanticsLabel('Play video: Poster clip'));
          await tester.pumpAndSettle();
          expect(harness.playerBuilds, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '${youtube ? 'YouTube' : 'uploaded'} network poster evicts a failed decode and retries at cover resolution',
      (tester) async {
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final client = _PosterHttpClient(Uint8List.fromList([1, 2, 3]));
        final previousClient = debugNetworkImageHttpClientProvider;
        debugNetworkImageHttpClientProvider = () => client;
        try {
          final harness = _PosterHarness(Uint8List(0));
          await tester.pumpWidget(harness.app(youtube: youtube, siteUrl: null));
          await _waitUntil(
            tester,
            () => find.byType(RawImage).evaluate().isEmpty,
            'the failed network decode',
          );
          expect(client.requests, [Uri.parse(_posterUrl)]);
          expect(PaintingBinding.instance.imageCache.currentSize, 0);
          expect(PaintingBinding.instance.imageCache.pendingImageCount, 0);
          expect(harness.playerBuilds, 0);
          await tester.pumpWidget(const SizedBox.shrink());
          client.bytes = File('test/fixtures/8k.png').readAsBytesSync();
          await tester.pumpWidget(harness.app(youtube: youtube, siteUrl: null));
          final expected = youtube
              ? const Size(711, 400)
              : const Size(640, 360);
          await _waitForImage(tester, expected: expected);
          expect(
            PaintingBinding.instance.imageCache.containsKey(
              const NetworkImage(_posterUrl),
            ),
            isFalse,
          );
          expect(
            PaintingBinding.instance.imageCache.currentSizeBytes,
            expected.width * expected.height * 4,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(harness.app(youtube: youtube, siteUrl: null));
          await _waitForImage(tester, expected: expected);
          expect(client.requests, [
            Uri.parse(_posterUrl),
            Uri.parse(_posterUrl),
          ]);
          expect(harness.requests, isEmpty);
          expect(harness.playerBuilds, 0);
          expect(tester.takeException(), isNull);
        } finally {
          debugNetworkImageHttpClientProvider = previousClient;
        }
      },
    );
  }
}

final class _PosterHarness {
  _PosterHarness(
    Uint8List bytes, {
    Future<http.Response> Function(http.Request)? respond,
  }) {
    repository = SiteImageRepository(
      credentials: FakeApiCredentialReader()..keys[_siteUrl] = 'account-key',
      lifecycle: SiteLifecycle(),
      client: MockClient((request) async {
        requests.add(request);
        return respond == null
            ? http.Response.bytes(bytes, 200)
            : await respond(request);
      }),
    );
    shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      siteImages: repository,
    );
    addTearDown(shell.dispose);
  }

  late final SiteImageRepository repository;
  late final ShellController shell;
  final requests = <http.Request>[];
  var playerBuilds = 0;

  Future<void> preload() async {
    await repository.load(siteUrl: _siteUrl, url: _posterUrl);
  }

  Widget app({
    required bool youtube,
    double width = 320,
    String url = _posterUrl,
    String? siteUrl = _siteUrl,
  }) => MaterialApp(
    home: ShellScope(
      controller: shell,
      child: Center(
        child: SizedBox(
          width: width,
          child: youtube
              ? YoutubeVideo(
                  data: YoutubeVideoData(
                    videoId: 'poster-video',
                    listId: null,
                    title: 'Poster clip',
                    thumbnailUrl: url,
                    startSeconds: null,
                    endSeconds: null,
                    loop: false,
                  ),
                  siteUrl: siteUrl,
                  playerBuilder: (_, _) {
                    playerBuilds++;
                    return const SizedBox.shrink();
                  },
                )
              : InlineVideo(
                  data: InlineVideoData.fromUpload(
                    url: '$_siteUrl/video.mp4',
                    title: 'Poster clip',
                    siteUrl: _siteUrl,
                    posterUrl: url,
                    aspectRatio: 16 / 9,
                  )!,
                  siteUrl: siteUrl,
                  playerBuilder: (_, _) {
                    playerBuilds++;
                    return const SizedBox.shrink();
                  },
                ),
        ),
      ),
    ),
  );
}

Future<void> _waitForImage(WidgetTester tester, {Size? expected}) => _waitUntil(
  tester,
  () {
    if (find.byType(RawImage).evaluate().isEmpty) return false;
    final image = tester.widget<RawImage>(find.byType(RawImage)).image;
    return image != null &&
        (expected == null ||
            Size(image.width.toDouble(), image.height.toDouble()) == expected);
  },
  'the decoded poster${expected == null ? '' : ' at $expected'}',
);

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail('Timed out waiting for $description');
}

Future<Uint8List> _pngBytes(WidgetTester tester, Size size) async =>
    (await tester.runAsync(() async {
      final image = await createTestImage(
        width: size.width.toInt(),
        height: size.height.toInt(),
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

final class _PosterHttpClient implements HttpClient {
  _PosterHttpClient(this.bytes);

  Uint8List bytes;
  final requests = <Uri>[];

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests.add(url);
    return _PosterHttpRequest(bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _PosterHttpRequest implements HttpClientRequest {
  _PosterHttpRequest(this.bytes);

  final Uint8List bytes;

  @override
  Future<HttpClientResponse> close() async => _PosterHttpResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _PosterHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _PosterHttpResponse(this.bytes);

  final Uint8List bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
