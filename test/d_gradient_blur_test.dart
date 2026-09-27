import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/gradient_blur_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final edge in DGradientBlurEdge.values) {
    testWidgets('$edge progressively blurs without tinting or spilling', (
      tester,
    ) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox(
                width: 256,
                height: 192,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var stripe = 0; stripe < 32; stripe++)
                          Expanded(
                            child: ColoredBox(
                              color: stripe.isEven
                                  ? Colors.black
                                  : Colors.white,
                            ),
                          ),
                      ],
                    ),
                    Positioned(
                      top: 32,
                      bottom: 32,
                      left: 0,
                      right: 0,
                      child: DGradientBlur(edge: edge),
                    ),
                    const Positioned(
                      top: 80,
                      right: 8,
                      width: 16,
                      height: 32,
                      child: ColoredBox(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final pixels = await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        try {
          return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        } finally {
          image.dispose();
        }
      });
      int row(int topRow) =>
          edge == DGradientBlurEdge.top ? topRow : 191 - topRow;
      final strong = _row(pixels!, row(40));
      final middle = _row(pixels, row(96));
      final clear = _row(pixels, row(152));
      int contrast(List<int> row) =>
          row.reduce(math.max) - row.reduce(math.min);
      expect(contrast(strong), lessThan(40));
      expect(contrast(middle), greaterThan(contrast(strong) + 30));
      expect(contrast(clear), greaterThan(contrast(middle) + 30));
      expect(contrast(clear), greaterThan(220));
      for (final samples in [strong, middle, clear]) {
        final mean = samples.reduce((a, b) => a + b) / samples.length;
        expect(
          mean,
          closeTo(127.5, 4),
          reason: 'The blur must not add a tint.',
        );
      }
      for (final y in [16, 176]) {
        expect(_row(pixels, y).toSet(), {0, 255});
      }
      const foreground = (96 * 256 + 240) * 4;
      expect(
        List.generate(4, (channel) => pixels.getUint8(foreground + channel)),
        [244, 67, 54, 255],
        reason: 'Controls painted above the blur must remain sharp.',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('decorative blur passes taps and semantics to the control', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Center(
            child: Stack(
              children: [
                DButton(
                  label: const Text('Tap through blur'),
                  onPressed: () => taps++,
                ),
                const Positioned.fill(child: DGradientBlur()),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DButton));
      await tester.pump();
      expect(taps, 1);
      expect(find.bySemanticsLabel('Tap through blur'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('styleguide controls scroll through both blurred edges', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Center(
          child: SizedBox(
            width: 320,
            child: Builder(
              builder: gradientBlurExamples.examples.single.builder,
            ),
          ),
        ),
      ),
    );
    final scroll = tester
        .widget<DScrollArea>(find.byType(DScrollArea))
        .controller!;
    await tester.tap(find.byTooltip('Scroll to bottom'));
    await tester.pumpAndSettle();
    expect(scroll.position.extentAfter, 0);
    await tester.tap(find.byTooltip('Scroll to top'));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(tester.takeException(), isNull);
  });
}

List<int> _row(ByteData pixels, int y) => [
  for (var x = 64; x < 192; x++) pixels.getUint8((y * 256 + x) * 4),
];
