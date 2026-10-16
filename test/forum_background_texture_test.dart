import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_texture.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

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
      // Keep the cached shader future outside a per-test fake-async zone.
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.fromPalette(palette.resolve(Brightness.dark)),
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: false),
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
          ),
        ),
      );
      await _waitForTexture(tester, effect);
      final initial = await _capture(tester);
      counter.paints = 0;
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(await _capture(tester), isNot(orderedEquals(initial)));
      expect(counter.paints, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Lava stays animated over Native glass controls', (tester) async {
    final palette = forumThemePresets.first
        .forBrightness(Brightness.dark)
        .copyWith(
          background: const ForumBackground.appearance(
            effect: ForumBackgroundEffect.lava,
            noiseIntensity: 1,
          ),
        );
    await tester.pumpWidget(
      MaterialApp(
        theme: DMaterialTheme.apply(
          AppTheme.fromPalette(palette.resolve(Brightness.dark)),
          DAppearanceMaterial.liquidGlass,
        ),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Center(
            child: RepaintBoundary(
              key: const ValueKey('texture-capture'),
              child: SizedBox.square(
                dimension: 256,
                child: ForumWindowBackground(
                  child: Center(
                    child: DButton(
                      onPressed: () {},
                      label: const Text('Glass control'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _waitForTexture(tester, ForumBackgroundEffect.lava);
    expect(
      ui.ImageFilter.isShaderFilterSupported
          ? find.byType(LiquidGlassLens)
          : find.byType(LiquidGlassLite),
      findsWidgets,
    );
    final initial = await _capture(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(await _capture(tester), isNot(orderedEquals(initial)));
    expect(find.text('Glass control'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
