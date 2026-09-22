import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('noise has dense grain and a shaded gradient in $brightness', (
      tester,
    ) async {
      final pixels = await _render(
        tester,
        brightness: brightness,
        strength: 1,
        noiseIntensity: 1,
      );
      // Adjacent pixels across a whole patch must carry texture, rather than
      // mostly unchanged flat color with a few isolated dots.
      expect(_grainContrast(pixels), greaterThan(5));
      expect(
        (_mean(pixels, 16, 16) - _mean(pixels, 208, 208)).abs(),
        greaterThan(10),
        reason: 'The grain sits over a visible color gradient.',
      );
      final subtle = await _render(tester, brightness: brightness, strength: 1);
      expect(_grainContrast(subtle), lessThan(_grainContrast(pixels) * .6));
      final smooth = await _render(
        tester,
        brightness: brightness,
        strength: 1,
        noiseIntensity: 0,
      );
      // Allow sub-channel rounding/dithering in the smooth gradient.
      expect(_grainContrast(smooth), lessThan(1));
      expect(
        (_mean(smooth, 16, 16) - _mean(smooth, 208, 208)).abs(),
        greaterThan(10),
        reason: 'Disabling noise must retain the gradient.',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('grain stays dense on a large window', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(tester.view.reset);
    final small = await _render(tester, strength: .8);
    final large = await _render(
      tester,
      strength: .8,
      size: const Size(1600, 1000),
    );
    expect(
      _grainContrast(large, width: 1600, left: 768, top: 468),
      closeTo(_grainContrast(small), 2),
      reason: 'Grain scale and density must not depend on window area.',
    );
  });

  testWidgets(
    'noise is static and independent of transparency and color strength',
    (tester) async {
      final original = await _render(tester, strength: .8);
      await tester.pump(const Duration(seconds: 30));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(await _capture(tester), orderedEquals(original));
      final rebuilt = await _render(tester, strength: .8);
      expect(rebuilt, orderedEquals(original));
      expect(
        await _render(tester, strength: .8, transparency: .2),
        orderedEquals(original),
        reason: 'Panel transparency must not affect the grain on the canvas.',
      );
      final untinted = await _render(tester, strength: 0);
      expect(_grainContrast(untinted), greaterThan(.5));

      final disabled = await _render(tester, strength: 0, noiseIntensity: 0);
      expect(find.byKey(const ValueKey('forum-window-effect')), findsNothing);
      final normal = await _render(
        tester,
        strength: 0,
        effect: ForumBackgroundEffect.normal,
      );
      expect(disabled, orderedEquals(normal));
      // Switching effects retains the same seeded texture.
      expect(await _render(tester, strength: .8), orderedEquals(original));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}

Future<Uint8List> _render(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  required double strength,
  double noiseIntensity = ForumBackground.defaultNoiseIntensity,
  double transparency = ForumBackground.defaultTransparency,
  ForumBackgroundEffect effect = ForumBackgroundEffect.noise,
  Size size = const Size.square(256),
}) async {
  final theme = ForumTheme.fromJson({
    ...forumThemePresets.firstWhere((theme) => theme.id == 'dracula').toJson(),
    'background': ForumBackground(
      color: const Color(0xff874ad7),
      strength: strength,
      effect: effect,
      noiseIntensity: noiseIntensity,
      transparency: transparency,
    ).toJson(),
  }, id: 'custom-grain-test');
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.fromPalette(theme.resolve(brightness)),
      home: Center(
        child: RepaintBoundary(
          key: const ValueKey('grain-capture'),
          child: SizedBox.fromSize(
            size: size,
            child: const ForumWindowBackground(child: SizedBox.expand()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _capture(tester);
}

Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('grain-capture')),
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

double _grainContrast(
  Uint8List pixels, {
  int width = 256,
  int left = 96,
  int top = 96,
}) {
  var total = 0;
  for (var y = top; y < top + 64; y++) {
    for (var x = left; x < left + 64; x++) {
      final index = (y * width + x) * 4;
      for (var channel = 0; channel < 3; channel++) {
        total += (pixels[index + channel] - pixels[index + 4 + channel]).abs();
      }
    }
  }
  return total / (64 * 64 * 3);
}

double _mean(Uint8List pixels, int left, int top) {
  var total = 0;
  for (var y = top; y < top + 32; y++) {
    for (var x = left; x < left + 32; x++) {
      final index = (y * 256 + x) * 4;
      total += pixels[index] + pixels[index + 1] + pixels[index + 2];
    }
  }
  return total / (32 * 32 * 3);
}
