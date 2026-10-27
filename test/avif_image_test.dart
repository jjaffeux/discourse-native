import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/src/data/avif.dart';
import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/image_decode.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

void main() {
  final animated = File('test/fixtures/avif/animated.avif').readAsBytesSync();
  final still = File('test/fixtures/avif/white.avif').readAsBytesSync();

  setUpAll(() async {
    // Native reply ports must be created outside a widget test's fake clock.
    await encodedImageSize(animated);
    await encodedImageSize(still);
  });

  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  test(
    'detects still and sequence brands without trusting the URL or MIME',
    () {
      expect(avifKind(still), AvifKind.still);
      expect(avifKind(animated), AvifKind.animated);
      expect(avifKind(Uint8List.sublistView(animated, 0, 20)), isNull);
      expect(
        avifKind(Uint8List.fromList('not an avif file'.codeUnits)),
        isNull,
      );
      final generic = Uint8List.fromList(animated);
      generic.setRange(8, 12, 'mif1'.codeUnits);
      expect(avifKind(generic), AvifKind.animated);
      // A brand-like minor version must not turn a still into a sequence.
      final minor = Uint8List.fromList(still);
      minor.setRange(12, 16, 'avis'.codeUnits);
      expect(avifKind(minor), AvifKind.still);
    },
  );

  test(
    'the repository recognizes AVIF sequences on signed upload URLs',
    () async {
      final repository = _repository(animated);
      addTearDown(repository.dispose);
      final loaded = await repository.load(siteUrl: _site, url: _url);
      expect(loaded?.mediaType, SiteImageMediaType.avif);
      expect(loaded?.isAnimated, isTrue);
    },
  );

  for (final sizing in ['original', 'fit', 'cover']) {
    testWidgets('AVIF $sizing renders distinct frames and pauses', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = _repository(animated);
      addTearDown(repository.dispose);
      await repository.load(siteUrl: _site, url: _url);
      final sizes = <Size>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SiteImage(
              url: _url,
              siteUrl: _site,
              repository: repository,
              width: 60,
              height: 40,
              cacheWidth: sizing == 'fit' ? 30 : null,
              cacheHeight: sizing == 'fit' ? 20 : null,
              fit: sizing == 'cover' ? BoxFit.cover : BoxFit.contain,
              coverDecodeSize: sizing == 'cover' ? const Size(60, 40) : null,
              gifPlaybackControls: true,
              onNaturalSize: sizes.add,
            ),
          ),
        ),
      );
      await _waitForImage(tester);
      final first = _image(tester).clone();
      addTearDown(first.dispose);
      expect(first.width, switch (sizing) {
        'fit' => 20,
        'cover' => 60,
        _ => 150,
      });
      expect(first.height, first.width);
      final firstPixels = await tester.runAsync(() => first.toByteData());
      await _nextFrame(tester);
      final secondPixels = await tester.runAsync(
        () => _image(tester).toByteData(),
      );
      expect(
        secondPixels!.buffer.asUint8List(),
        isNot(orderedEquals(firstPixels!.buffer.asUint8List())),
      );
      expect(sizes, [const Size(150, 150)]);

      await tester.tap(find.byKey(const ValueKey('gif-playback-toggle')));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      final paused = _image(tester).clone();
      addTearDown(paused.dispose);
      await _nextFrame(tester);
      expect(paused.isCloneOf(_image(tester)), isTrue);
      await tester.tap(find.byKey(const ValueKey('gif-playback-toggle')));
      await tester.pump();
      await _nextFrame(tester);
      expect(paused.isCloneOf(_image(tester)), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('AVIF pauses offscreen and resumes when scrolled back', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);
    final repository = _repository(animated);
    final scroll = ScrollController();
    addTearDown(repository.dispose);
    addTearDown(scroll.dispose);
    await repository.load(siteUrl: _site, url: _url);
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          controller: scroll,
          child: Column(
            children: [
              SiteImage(
                url: _url,
                siteUrl: _site,
                repository: repository,
                width: 60,
                height: 60,
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    await _waitForImage(tester);
    scroll.jumpTo(900);
    await tester.pump();
    await tester.pump();
    final paused = _image(tester).clone();
    addTearDown(paused.dispose);
    for (var i = 0; i < 5; i++) {
      await _nextFrame(tester);
      expect(paused.isCloneOf(_image(tester)), isTrue);
    }
    scroll.jumpTo(0);
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 10 && paused.isCloneOf(_image(tester)); i++) {
      await _nextFrame(tester);
    }
    expect(paused.isCloneOf(_image(tester)), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('malformed AVIF uses the existing error fallback', (
    tester,
  ) async {
    final repository = _repository(Uint8List.sublistView(animated, 0, 44));
    addTearDown(repository.dispose);
    await repository.load(siteUrl: _site, url: _url);
    await tester.pumpWidget(
      MaterialApp(
        home: SiteImage(
          url: _url,
          siteUrl: _site,
          repository: repository,
          cacheWidth: 30,
          errorBuilder: (_, _, _) => const Text('unavailable'),
        ),
      ),
    );
    for (
      var i = 0;
      i < 50 && find.text('unavailable').evaluate().isEmpty;
      i++
    ) {
      await _nextFrame(tester);
    }
    expect(find.text('unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('still AVIF keeps its dimensions without animation controls', (
    tester,
  ) async {
    final repository = _repository(still);
    addTearDown(repository.dispose);
    await repository.load(siteUrl: _site, url: _url);
    await tester.pumpWidget(
      MaterialApp(
        home: SiteImage(
          url: _url,
          siteUrl: _site,
          repository: repository,
          cacheWidth: 100,
          gifPlaybackControls: true,
        ),
      ),
    );
    await _waitForImage(tester);
    expect((_image(tester).width, _image(tester).height), (1, 1));
    expect(find.byKey(const ValueKey('gif-playback-toggle')), findsNothing);
    expect(await encodedImageSize(still), const Size(1, 1));
  });
}

const _site = 'https://forum.example';
const _url = '$_site/secure-uploads/image?signature=example';

SiteImageRepository _repository(Uint8List bytes) => SiteImageRepository(
  credentials: FakeApiCredentialReader(),
  lifecycle: SiteLifecycle(),
  client: MockClient((_) async => http.Response.bytes(bytes, 200)),
);

ui.Image _image(WidgetTester tester) =>
    tester.widget<RawImage>(find.byType(RawImage)).image!;

Future<void> _waitForImage(WidgetTester tester) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (find
        .byType(RawImage)
        .evaluate()
        .any((element) => (element.widget as RawImage).image != null)) {
      return;
    }
  }
  fail('AVIF did not produce a frame: ${tester.takeException()}');
}

Future<void> _nextFrame(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump(const Duration(milliseconds: 40));
  await tester.pump();
}
