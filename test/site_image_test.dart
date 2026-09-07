import 'dart:ui' as ui;

import 'package:discourse_native/src/shell/site_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final cached in [false, true]) {
    testWidgets(
      'natural-size measurement releases image handles with cached frame $cached',
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
            child: SiteImage(
              url: provider.url,
              siteUrl: null,
              onNaturalSize: sizes.add,
            ),
          ),
        );
        if (!cached) frames.emit(image);
        await tester.pump();
        frames.emit(image);
        await tester.pump();

        expect(sizes, [const Size(40, 20)]);
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

final class _ImageFrames extends ImageStreamCompleter {
  void emit(ui.Image image) => setImage(ImageInfo(image: image.clone()));

  void fail() => reportError(exception: StateError('Invalid image'));
}
