import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_texture.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final effect in [
    ForumBackgroundEffect.lava,
    ForumBackgroundEffect.gradient,
  ]) {
    testWidgets('$effect animates without repainting static content', (
      tester,
    ) async {
      final counter = _PaintCounter();
      final palette = forumThemePresets.first
          .forBrightness(Brightness.dark)
          .copyWith(
            background: ForumBackground.appearance(
              effect: effect,
              noiseIntensity: .7,
            ),
          );
      Widget host({required bool reducedMotion}) => MaterialApp(
        theme: AppTheme.fromPalette(palette.resolve(Brightness.dark)),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: Center(
            child: RepaintBoundary(
              key: const ValueKey('texture-capture'),
              child: SizedBox.square(
                dimension: 256,
                child: ForumWindowBackground(
                  child: CustomPaint(
                    painter: counter,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() => tester.pumpWidget(host(reducedMotion: true)));
      await _waitForTexture(tester, effect);
      await tester.pumpWidget(host(reducedMotion: false));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      final painter = tester
          .widget<CustomPaint>(
            find.byKey(
              ValueKey(
                effect == ForumBackgroundEffect.gradient
                    ? 'forum-gradient-texture'
                    : 'forum-reference-texture',
              ),
            ),
          )
          .painter!;
      var repaints = 0;
      void countRepaint() => repaints++;
      painter.addListener(countRepaint);
      try {
        final initial = await _capture(tester);
        counter.paints = 0;
        for (var frame = 0; frame < 60; frame++) {
          await tester.pump(const Duration(microseconds: 16667));
        }
        expect(repaints, inInclusiveRange(29, 31));
        expect(await _capture(tester), isNot(orderedEquals(initial)));
        expect(counter.paints, 0);
        expect(tester.takeException(), isNull);
      } finally {
        painter.removeListener(countRepaint);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets('Paper and Lava lamp are visible at maximum intensity', (
    tester,
  ) async {
    Future<Uint8List> capture(
      ForumBackgroundEffect effect,
      double intensity,
    ) async {
      final palette = forumThemePresets.first
          .forBrightness(Brightness.dark)
          .copyWith(
            background: ForumBackground.appearance(
              effect: effect,
              noiseIntensity: intensity,
            ),
          );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.fromPalette(palette.resolve(Brightness.dark)),
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Center(
              child: RepaintBoundary(
                key: ValueKey('texture-capture'),
                child: SizedBox.square(
                  dimension: 256,
                  child: ForumWindowBackground(child: SizedBox.expand()),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        if (intensity == 0 ||
            find
                .byKey(const ValueKey('forum-reference-texture'))
                .evaluate()
                .isNotEmpty) {
          break;
        }
      }
      if (intensity > 0) {
        expect(tester.takeException(), isNull);
        expect(find.byType(ForumTexture), findsOneWidget);
        expect(
          find.byKey(const ValueKey('forum-reference-texture')),
          findsOneWidget,
        );
      }
      return _capture(tester);
    }

    for (final effect in [
      ForumBackgroundEffect.paper,
      ForumBackgroundEffect.lava,
    ]) {
      final plain = await capture(effect, 0);
      final textured = await capture(effect, 1);
      var difference = 0;
      for (var i = 0; i < plain.length; i++) {
        difference += (plain[i] - textured[i]).abs();
      }
      expect(difference / plain.length, greaterThan(0.2), reason: '$effect');
    }
    expect(tester.takeException(), isNull);
  });

  for (final (effect, intensity, reducedMotion, tickersEnabled) in [
    (ForumBackgroundEffect.lava, 1.0, true, true),
    (ForumBackgroundEffect.lava, 1.0, false, false),
    (ForumBackgroundEffect.lava, 0.0, false, true),
    (ForumBackgroundEffect.paper, 1.0, false, true),
    (ForumBackgroundEffect.hatch, 1.0, false, true),
    (ForumBackgroundEffect.normal, 1.0, false, true),
  ]) {
    testWidgets('$effect intensity=$intensity reducedMotion=$reducedMotion '
        'TickerMode=$tickersEnabled does not schedule decorative frames', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(disableAnimations: reducedMotion),
            child: TickerMode(
              enabled: tickersEnabled,
              child: RepaintBoundary(
                key: const ValueKey('texture-capture'),
                child: SizedBox.square(
                  dimension: 256,
                  child: ForumTexture(
                    background: ForumBackground.appearance(
                      effect: effect,
                      noiseIntensity: intensity,
                    ),
                    accent: const Color(0xff5078cc),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      if (intensity > 0 &&
          (effect == ForumBackgroundEffect.lava ||
              effect == ForumBackgroundEffect.paper)) {
        await _waitForTexture(tester, effect);
      }
      await tester.pump();
      final initial = await _capture(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(await _capture(tester), orderedEquals(initial));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _waitForTexture(
  WidgetTester tester,
  ForumBackgroundEffect effect,
) async {
  final texture = find.byKey(
    ValueKey(
      effect == ForumBackgroundEffect.gradient
          ? 'forum-gradient-texture'
          : 'forum-reference-texture',
    ),
  );
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (texture.evaluate().isNotEmpty) break;
  }
  expect(texture, findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('texture-capture')),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    image.dispose();
    return bytes;
  }))!;
}

class _PaintCounter extends CustomPainter {
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) => paints++;

  @override
  bool shouldRepaint(_PaintCounter oldDelegate) => false;
}
