import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final background in [const Color(0xFFF0E0D0), const Color(0xFF202830)]) {
    for (final height in [80.0, 160.0]) {
      testWidgets(
        'desktop rows disappear under $height-high controls on $background',
        (tester) async {
          final boundary = GlobalKey();
          var presses = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              home: Align(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: boundary,
                  child: ColoredBox(
                    color: background,
                    child: SizedBox(
                      width: 280,
                      height: 400,
                      child: DSidebarProvider(
                        mobileBreakpoint: 0,
                        child: DSidebar(
                          width: 280,
                          backgroundColor: Colors.transparent,
                          collapsible: DSidebarCollapsible.none,
                          child: DSidebarContent.slivers(
                            header: SizedBox(
                              height: height,
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: DButton(
                                  label: const Text('Search chat'),
                                  onPressed: () => presses++,
                                ),
                              ),
                            ),
                            slivers: const [
                              SliverToBoxAdapter(
                                child: SizedBox(
                                  height: 2000,
                                  child: ColoredBox(color: Color(0xFF0080FF)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final controller = tester
              .widget<CustomScrollView>(find.byType(CustomScrollView))
              .controller!;
          final button = tester.getRect(find.byType(DButton));
          final controlsBottom = (height + 16).round();
          for (final offset in [40.0, 350.0, 700.0]) {
            controller.jumpTo(offset);
            await tester.pumpAndSettle();
            final pixels = (await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              try {
                return await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                );
              } finally {
                image.dispose();
              }
            }))!;
            Color at(int y) => _pixel(pixels, 240, y);
            expect(
              at(controlsBottom - 8),
              background,
              reason: 'Rows must be invisible beneath the pinned controls.',
            );
            expect(at(controlsBottom - 1), background);
            final middle = at(controlsBottom + 7);
            expect(middle, isNot(background));
            expect(middle, isNot(const Color(0xFF0080FF)));
            expect(at(controlsBottom + 14), const Color(0xFF0080FF));
            expect(tester.getRect(find.byType(DButton)), button);
          }
          await tester.tap(find.byType(DButton));
          await tester.pump();
          expect(presses, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Color _pixel(ByteData pixels, int x, int y) {
  final offset = (y * 280 + x) * 4;
  return Color.fromARGB(
    pixels.getUint8(offset + 3),
    pixels.getUint8(offset),
    pixels.getUint8(offset + 1),
    pixels.getUint8(offset + 2),
  );
}
