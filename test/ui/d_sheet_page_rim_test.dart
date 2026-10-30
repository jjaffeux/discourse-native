import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = ValueKey('sheet-rim-capture');

Matcher _near(Color expected) => isA<Color>().having(
  (actual) => [
    (actual.r - expected.r).abs(),
    (actual.g - expected.g).abs(),
    (actual.b - expected.b).abs(),
  ].every((difference) => difference <= 2 / 255),
  'channels within two steps of $expected',
  isTrue,
);

void main() {
  for (final brightness in Brightness.values) {
    for (final start in DSheetReaderStart.values) {
      testWidgets(
        'page sheet has one continuous rim in ${brightness.name} at ${start.name}',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final fill = brightness == Brightness.dark
              ? const Color(0xff262626)
              : const Color(0xfff7f7f7);
          late BuildContext readerContext;
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.forBrightness(brightness),
              home: RepaintBoundary(
                key: _captureKey,
                child: ColoredBox(
                  color: const Color(0xff111111),
                  child: DSheetDragScope(
                    child: Builder(
                      builder: (context) {
                        DSheetDragScope.reportTopBar(context, 88);
                        return DSheetViewport(
                          readerStart: start,
                          content: DSheetContent(
                            side: DSheetSide.bottom,
                            variant: DSheetVariant.page,
                            showCloseButton: false,
                            backgroundColor: fill,
                            children: [
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    readerContext = context;
                                    return const SizedBox.expand();
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final edge = DSheetPageBand.edgeOf(readerContext)!.value;
          expect(edge, start == DSheetReaderStart.top ? isZero : isPositive);
          final expected = Color.alphaBlend(
            (brightness == Brightness.dark ? Colors.white : Colors.black)
                .withValues(alpha: .07),
            fill,
          );
          final pixels = (await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(find.byKey(_captureKey))
                .toImage(pixelRatio: 3);
            try {
              const directory = String.fromEnvironment(
                'sheetRimCaptureDirectory',
              );
              if (directory.isNotEmpty) {
                await Directory(directory).create(recursive: true);
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '$directory/${brightness.name}-${start.name}.png',
                ).writeAsBytes(png!.buffer.asUint8List());
              }
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              Color at(int x, int y) {
                final offset = (y * image.width + x) * 4;
                return Color.fromARGB(
                  bytes.getUint8(offset + 3),
                  bytes.getUint8(offset),
                  bytes.getUint8(offset + 1),
                  bytes.getUint8(offset + 2),
                );
              }

              return [
                for (final x in [1, image.width - 2])
                  for (final offset in [30, 32, 140])
                    (
                      side: x == 1 ? 'left' : 'right',
                      offset: offset,
                      color: at(x, ((edge + offset) * 3).round() + 1),
                    ),
              ];
            } finally {
              image.dispose();
            }
          }))!;
          for (final pixel in pixels) {
            expect(
              pixel.color,
              _near(expected),
              reason:
                  'The ${pixel.side} rim at ${pixel.offset} points '
                  'below the rounded top must have one coat.',
            );
          }
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );
    }
  }
}
