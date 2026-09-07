import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/composer_images.dart';
import 'package:discourse_native/src/shell/lightbox.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photo_view/photo_view.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://forum.example';
const _imageUrl = '$_siteUrl/image.png';

void main() {
  for (final cached in [false, true]) {
    testWidgets(
      'an unknown 8K composer image reports its size without full decoding '
      '(cached: $cached)',
      (tester) async {
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        // A solid, 1-bit grayscale PNG: tiny encoded data, 126.6 MiB of RGBA
        // pixels at full resolution. Loading the fixture creates no ui.Image.
        final bytes = File('test/fixtures/8k.png').readAsBytesSync();
        const siteUrl = 'https://forum.example';
        const url = '$siteUrl/secure-uploads/original/8k.png';
        final requests = <http.Request>[];
        final repository = SiteImageRepository(
          credentials: FakeApiCredentialReader()..keys[siteUrl] = 'account-key',
          lifecycle: SiteLifecycle(),
          client: MockClient((request) async {
            requests.add(request);
            return http.Response.bytes(bytes, 200);
          }),
        );
        final shell = ShellController(
          instanceStore: FakeInstanceStore(),
          api: FakeDiscourseApi(),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          siteImages: repository,
        );
        addTearDown(shell.dispose);
        if (cached) {
          await repository.load(siteUrl: siteUrl, url: url);
        }
        final decodedSizes = <Size>[];
        final previousOnCreate = ui.Image.onCreate;
        ui.Image.onCreate = (image) {
          previousOnCreate?.call(image);
          decodedSizes.add(
            Size(image.width.toDouble(), image.height.toDouble()),
          );
        };
        addTearDown(() => ui.Image.onCreate = previousOnCreate);
        final sizes = <Size>[];
        final image = parseComposerImages('![8K photo]($url)').single;
        expect(image.hasDimensions, isFalse);

        await tester.pumpWidget(
          MaterialApp(
            home: ShellScope(
              controller: shell,
              child: Center(
                child: ComposerImagePreview(
                  image: image,
                  url: url,
                  siteUrl: siteUrl,
                  onNaturalSize: sizes.add,
                ),
              ),
            ),
          ),
        );
        await _waitForImage(tester);

        expect(sizes, [const Size(7680, 4320)]);
        final decoded = tester.widget<RawImage>(find.byType(RawImage)).image!;
        expect(decoded.width, lessThanOrEqualTo(676));
        expect(decoded.height, lessThanOrEqualTo(380));
        expect(decoded.width / decoded.height, closeTo(16 / 9, 0.01));
        expect(decodedSizes, isNotEmpty);
        for (final size in decodedSizes) {
          expect(size.width, lessThanOrEqualTo(676));
          expect(size.height, lessThanOrEqualTo(380));
        }
        final loaded = repository.cached(siteUrl: siteUrl, url: url)!;
        expect(
          PaintingBinding.instance.imageCache.containsKey(
            MemoryImage(loaded.bytes),
          ),
          isFalse,
          reason: 'measuring dimensions must not cache a full-size image',
        );
        expect(requests, hasLength(1));
        expect(requests.single.headers['User-Api-Key'], 'account-key');
        expect(requests.single.headers['User-Api-Client-Id'], 'test-client');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final change in ['url', 'repository', 'callback', 'unmount']) {
    testWidgets('pending byte metadata is retired on $change change', (
      tester,
    ) async {
      final bytes = await _pngBytes(tester, width: 40, height: 20);
      final replacement = await _pngBytes(tester, width: 20, height: 40);
      final repository = SiteImageRepository(
        credentials: FakeApiCredentialReader(),
        lifecycle: SiteLifecycle(),
        client: MockClient(
          (request) async => http.Response.bytes(
            request.url.path == '/replacement.png' ? replacement : bytes,
            200,
          ),
        ),
      );
      addTearDown(repository.dispose);
      final otherRepository = _repository(replacement);
      const otherUrl = '$_siteUrl/replacement.png';
      await Future.wait([
        repository.load(siteUrl: _siteUrl, url: _imageUrl),
        repository.load(siteUrl: _siteUrl, url: otherUrl),
        otherRepository.load(siteUrl: _siteUrl, url: _imageUrl),
      ]);
      final sizes = <Size>[];
      final replacementSizes = <Size>[];
      await tester.pumpWidget(const SizedBox());
      _buildBeforeMicrotasks(
        tester,
        SiteImage(
          url: _imageUrl,
          siteUrl: _siteUrl,
          repository: repository,
          cacheWidth: 10,
          cacheHeight: 10,
          onNaturalSize: sizes.add,
        ),
      );
      expect(sizes, isEmpty, reason: 'metadata is still pending');
      final state = tester.state(find.byType(SiteImage));
      _buildBeforeMicrotasks(
        tester,
        change == 'unmount'
            ? const SizedBox()
            : SiteImage(
                url: change == 'url' ? otherUrl : _imageUrl,
                siteUrl: _siteUrl,
                repository: change == 'repository'
                    ? otherRepository
                    : repository,
                cacheWidth: 10,
                cacheHeight: 10,
                onNaturalSize: change == 'callback'
                    ? null
                    : replacementSizes.add,
              ),
      );
      if (change != 'unmount') {
        expect(tester.state(find.byType(SiteImage)), same(state));
        await _waitForImage(tester);
        final decoded = tester.widget<RawImage>(find.byType(RawImage)).image!;
        expect(
          Size(decoded.width.toDouble(), decoded.height.toDouble()),
          change == 'callback' ? const Size(10, 5) : const Size(5, 10),
        );
      } else {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }

      expect(sizes, isEmpty);
      expect(
        replacementSizes,
        change == 'url' || change == 'repository'
            ? [const Size(20, 40)]
            : isEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final removed in [false, true]) {
    testWidgets('invalid byte metadata keeps the image fallback ($removed)', (
      tester,
    ) async {
      final repository = _repository(Uint8List.fromList([1, 2, 3]));
      await repository.load(siteUrl: _siteUrl, url: _imageUrl);
      final sizes = <Size>[];
      await tester.pumpWidget(const SizedBox());
      _buildBeforeMicrotasks(
        tester,
        SiteImage(
          url: _imageUrl,
          siteUrl: _siteUrl,
          repository: repository,
          cacheWidth: 10,
          onNaturalSize: sizes.add,
          errorBuilder: (_, _, _) => const Text('Image unavailable'),
        ),
      );
      if (removed) _buildBeforeMicrotasks(tester, const SizedBox());
      await tester.pump();

      expect(sizes, isEmpty);
      expect(
        find.text('Image unavailable'),
        removed ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('SVG bytes keep vector rendering without raster measurement', (
    tester,
  ) async {
    final repository = _repository(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20">'
        '<rect width="40" height="20" fill="red"/></svg>',
      ),
    );
    await repository.load(siteUrl: _siteUrl, url: _imageUrl);
    final sizes = <Size>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SiteImage(
          url: _imageUrl,
          siteUrl: _siteUrl,
          repository: repository,
          onNaturalSize: sizes.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(sizes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('byte metadata leaves GIF playback and pause controls working', (
    tester,
  ) async {
    // Two 1x1 frames, alternating black and white every 100 ms, looping.
    final bytes = base64Decode(
      'R0lGODlhAQABAIAAAAAAAP///yH/C05FVFNDQVBFMi4wAwEAAAAh+QQACgAAACw'
      'AAAAAAQABAAACAkQBACH5BAAKAAAALAAAAAABAAEAAAICTAEAOw==',
    );
    final repository = _repository(bytes);
    await repository.load(siteUrl: _siteUrl, url: _imageUrl);
    final sizes = <Size>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SiteImage(
            url: _imageUrl,
            siteUrl: _siteUrl,
            repository: repository,
            width: 100,
            height: 100,
            cacheWidth: 10,
            cacheHeight: 10,
            gifPlaybackControls: true,
            onNaturalSize: sizes.add,
          ),
        ),
      ),
    );
    await _waitForImage(tester);
    final initial = tester.widget<RawImage>(find.byType(RawImage)).image!;
    // Keep a test-owned handle while Flutter advances to the next frame.
    final first = initial.clone();
    addTearDown(first.dispose);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 110));
    await tester.pump();
    final second = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(first.isCloneOf(second), isFalse);
    expect(sizes, [const Size(1, 1)]);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gif-playback-toggle')));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    final paused = tester.widget<RawImage>(find.byType(RawImage)).image!;
    final pausedHandle = paused.clone();
    addTearDown(pausedHandle.dispose);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      pausedHandle.isCloneOf(
        tester.widget<RawImage>(find.byType(RawImage)).image!,
      ),
      isTrue,
    );
    expect(sizes, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('byte metadata sets full-size lightbox geometry', (tester) async {
    final bytes = await _pngBytes(tester, width: 1200, height: 600);
    final repository = _repository(bytes);
    final shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      siteImages: repository,
    );
    addTearDown(shell.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ShellScope(
          controller: shell,
          child: const LightboxGallery(
            siteUrl: _siteUrl,
            initialIndex: 0,
            images: [
              LightboxImage(
                fullSrc: _imageUrl,
                thumbnailSrc: null,
                title: 'Full image',
                description: null,
                details: null,
                downloadHref: null,
                width: null,
                height: null,
                heroTag: 'full-image',
              ),
            ],
          ),
        ),
      ),
    );
    await _waitForImage(tester);
    await tester.pump();
    final photoView = tester.widget<PhotoView>(find.byType(PhotoView));
    expect(photoView.childSize, const Size(1200, 600));
    final viewport = tester.getSize(find.byType(PhotoView));
    final contained = [
      viewport.width / 1200,
      viewport.height / 600,
    ].reduce((a, b) => a < b ? a : b);
    expect(photoView.controller!.scale, closeTo(contained, 0.001));
    final decoded = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(
      Size(decoded.width.toDouble(), decoded.height.toDouble()),
      const Size(1200, 600),
    );
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    expect(tester.takeException(), isNull);
  });

  for (final cached in [false, true]) {
    testWidgets(
      'network composer measurement shares its image and releases handles '
      '(cached frame: $cached)',
      (tester) async {
        final image = (await tester.runAsync(
          () => createTestImage(width: 40, height: 20, cache: false),
        ))!;
        addTearDown(image.dispose);
        const provider = NetworkImage('https://images.example/size.png');
        final frames = _ImageFrames();
        final retained = frames.keepAlive();
        var released = false;
        void release() {
          if (released) return;
          released = true;
          PaintingBinding.instance.imageCache.evict(provider);
          retained.dispose();
        }

        addTearDown(release);
        PaintingBinding.instance.imageCache.putIfAbsent(provider, () => frames);
        if (cached) frames.emit(image);
        final sizes = <Size>[];

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: ComposerImagePreview(
              image: parseComposerImages('![photo](${provider.url})').single,
              url: provider.url,
              siteUrl: cached ? 'https://images.example' : null,
              onNaturalSize: sizes.add,
            ),
          ),
        );
        if (!cached) frames.emit(image);
        await tester.pump();
        frames.emit(image);
        await tester.pump();

        expect(sizes, [const Size(40, 20)]);
        expect(tester.widget<Image>(find.byType(Image)).image, provider);
        expect(tester.widget<RawImage>(find.byType(RawImage)).image?.width, 40);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        release();
        // ImageCache releases its keep-alive handles after the next frame.
        tester.binding.scheduleFrame();
        await tester.pump();

        expect(frames.hasListeners, isFalse);
        expect(
          image.debugGetOpenHandleStackTraces(),
          hasLength(1),
          reason:
              'only the test owner may retain the image after the widget and cache release it',
        );
      },
    );
  }

  for (final removed in [false, true]) {
    testWidgets(
      'a failed natural-size probe is handled after removal $removed',
      (tester) async {
        const provider = NetworkImage('https://images.example/broken.png');
        final resized = ResizeImage.resizeIfNeeded(20, 10, provider);
        final resizedKey = await resized.obtainKey(const ImageConfiguration());
        final naturalFrames = _ImageFrames();
        final displayFrames = _ImageFrames();
        final naturalRetained = naturalFrames.keepAlive();
        final displayRetained = displayFrames.keepAlive();
        final cache = PaintingBinding.instance.imageCache;
        cache.putIfAbsent(provider, () => naturalFrames);
        cache.putIfAbsent(resizedKey, () => displayFrames);
        addTearDown(() {
          cache.evict(provider);
          cache.evict(resizedKey);
          naturalRetained.dispose();
          displayRetained.dispose();
        });
        final sizes = <Size>[];
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SiteImage(
              url: provider.url,
              siteUrl: null,
              cacheWidth: 20,
              cacheHeight: 10,
              onNaturalSize: sizes.add,
              errorBuilder: (_, _, _) => const Text('Image unavailable'),
            ),
          ),
        );

        if (removed) await tester.pumpWidget(const SizedBox());
        naturalFrames.fail();
        displayFrames.fail();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(
          find.text('Image unavailable'),
          removed ? findsNothing : findsOneWidget,
        );
        expect(sizes, isEmpty);
      },
    );
  }
}

Future<void> _waitForImage(WidgetTester tester) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (find.byType(RawImage).evaluate().isNotEmpty &&
        tester.widget<RawImage>(find.byType(RawImage)).image != null) {
      return;
    }
  }
  fail('The image did not decode');
}

SiteImageRepository _repository(Uint8List bytes) {
  final repository = SiteImageRepository(
    credentials: FakeApiCredentialReader(),
    lifecycle: SiteLifecycle(),
    client: MockClient((_) async => http.Response.bytes(bytes, 200)),
  );
  addTearDown(repository.dispose);
  return repository;
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

void _buildBeforeMicrotasks(WidgetTester tester, Widget child) {
  // Build twice before metadata futures can resume, so replacement/disposal
  // races are deterministic even when bytes were already cached.
  final binding = tester.binding;
  binding.attachRootWidget(
    binding.wrapWithDefaultView(
      Directionality(textDirection: TextDirection.ltr, child: child),
    ),
  );
  binding.buildOwner!.buildScope(binding.rootElement!);
  binding.buildOwner!.finalizeTree();
  binding.scheduleFrame();
}

final class _ImageFrames extends ImageStreamCompleter {
  void emit(ui.Image image) => setImage(ImageInfo(image: image.clone()));

  void fail() => reportError(exception: StateError('Invalid image'));
}
