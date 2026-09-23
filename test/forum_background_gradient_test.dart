import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Gradient is visible with zero tint and opaque $brightness panels',
      (tester) async {
        await _show(tester, brightness: brightness, intensity: 0);
        final plain = await _capture(tester);
        await _show(tester, brightness: brightness, intensity: .25);
        final subtle = await _capture(tester);
        await _show(tester, brightness: brightness, intensity: 1);
        final strong = await _capture(tester);
        expect(_difference(plain, subtle), greaterThan(.1));
        expect(_difference(plain, strong), greaterThan(1));
        expect(
          _difference(plain, strong),
          greaterThan(_difference(plain, subtle) * 2),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('maximum Gradient intensity preserves black and white ink', (
    tester,
  ) async {
    await _show(
      tester,
      content: const Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: ColoredBox(color: Colors.black)),
          Expanded(child: ColoredBox(color: Colors.white)),
        ],
      ),
    );
    final pixels = await _capture(tester);
    for (final (x, channel) in [(64, 0), (192, 255)]) {
      final offset = (128 * 256 + x) * 4;
      expect(pixels.sublist(offset, offset + 3), everyElement(channel));
    }
  });

  testWidgets('Gradient animates once per window and respects reduced motion', (
    tester,
  ) async {
    await _show(tester, reducedMotion: false);
    expect(
      find.byKey(const ValueKey('forum-gradient-texture')),
      findsOneWidget,
    );
    final initial = await _capture(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(_difference(initial, await _capture(tester)), greaterThan(1));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await _show(tester);
    final frozen = await _capture(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(await _capture(tester), orderedEquals(frozen));
    expect(tester.binding.hasScheduledFrame, isFalse);

    await _show(tester, reducedMotion: false, intensity: 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _show(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  double intensity = 1,
  bool reducedMotion = true,
  Widget? content,
}) async {
  final palette = forumThemePresets
      .firstWhere((theme) => theme.id == 'solarized')
      .forBrightness(brightness)
      .copyWith(
        background: ForumBackground.appearance(
          effect: ForumBackgroundEffect.gradient,
          noiseIntensity: intensity,
        ),
      );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.fromPalette(palette.resolve(brightness)),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Center(
          child: RepaintBoundary(
            key: const ValueKey('gradient-capture'),
            child: SizedBox.square(
              dimension: 256,
              child: ForumWindowBackground(
                child: ForumWindowBackground(
                  child: DPageSurface(
                    framed: true,
                    backgroundColor: palette.secondary,
                    child: content ?? const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('gradient-capture')),
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

double _difference(Uint8List first, Uint8List second) {
  var total = 0;
  for (var i = 0; i < first.length; i++) {
    total += (first[i] - second[i]).abs();
  }
  return total / first.length;
}
