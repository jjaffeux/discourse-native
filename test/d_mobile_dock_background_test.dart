import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'd_mobile_dock_test.dart' as fixture;

void main() {
  for (final brightness in Brightness.values) {
    for (final foot in [0.0, 34.0]) {
      testWidgets(
        'closing the expanded bar keeps its background ($brightness, foot $foot)',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpWidget(
            fixture.fixture(
              theme: brightness == Brightness.dark
                  ? AppTheme.dark
                  : AppTheme.light,
              foot: foot,
            ),
          );
          await tester.pumpAndSettle();
          final surface = find.byKey(const ValueKey('mobile-dock-surface'));
          final rest = tester.getRect(surface);
          final point = rest.bottomCenter - const Offset(0, 3);
          final background = await _pixel(tester, point);

          await tester.tap(find.byKey(DMobileDock.moreKey));
          await tester.pumpAndSettle();
          expect(find.byKey(DMobileDock.panelKey), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          // Include the handoff from the overlay to the bar and any
          // implicit animation that starts during that handoff.
          for (var frame = 0; frame < 60; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              await _pixel(tester, point),
              background,
              reason: 'bar background changed at closing frame $frame',
            );
          }
          expect(find.byKey(DMobileDock.panelKey), findsNothing);
          expect(tester.getRect(surface), rest);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Future<Color> _pixel(WidgetTester tester, Offset point) async =>
    (await tester.runAsync(() async {
      final builder = ui.SceneBuilder();
      tester.binding.renderViews.first.debugLayer!.addToScene(builder);
      final scene = builder.build();
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      final image = await scene.toImage(size.width.ceil(), size.height.ceil());
      try {
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset = (point.dy.floor() * image.width + point.dx.floor()) * 4;
        return Color.fromARGB(
          data.getUint8(offset + 3),
          data.getUint8(offset),
          data.getUint8(offset + 1),
          data.getUint8(offset + 2),
        );
      } finally {
        image.dispose();
        scene.dispose();
      }
    }))!;
