import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/shell/content_navigation_controls.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';
import 'support/fakes.dart';

const _capture = ValueKey('navigation-capture');
const _canvas = Color(0xff1645ad);

void main() {
  for (final material in DAppearanceMaterial.values) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('navigation paint: $material $brightness ${scale}x', (
          tester,
        ) async {
          final shadowsDisabled = debugDisableShadows;
          debugDisableShadows = false;
          try {
            final api = FakeDiscourseApi();
            final shell = ShellController(
              instanceStore: FakeInstanceStore([instance('meta.example')]),
              api: api,
              authenticator: FakeAuthenticator(),
              drafts: FakeDraftStore(),
              trackers: FakeSiteTracker.reset(),
              updater: FakeUpdater(),
              updateStore: FakeUpdateStore(),
            );
            await shell.load();
            addTearDown(shell.dispose);
            await tester.pumpWidget(
              MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                themeAnimationStyle: AnimationStyle.noAnimation,
                theme: DMaterialTheme.apply(
                  AppTheme.forBrightness(
                    brightness,
                  ).copyWith(platform: TargetPlatform.macOS),
                  material,
                ),
                home: ShellScope(
                  controller: shell,
                  child: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: const Center(
                      child: RepaintBoundary(
                        key: _capture,
                        child: ColoredBox(
                          color: _canvas,
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: ContentNavigationControls(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final origin = tester.getTopLeft(find.byKey(_capture));
            final group = tester.getRect(find.byType(DCard)).shift(-origin);
            final refresh = find.byKey(ContentNavigationControls.refreshKey);
            final button = tester.getRect(refresh).shift(-origin);
            final back = find.byKey(ContentNavigationControls.backKey);
            expect(tester.widget<DButton>(back).onPressed, isNull);
            expect(tester.widget<DButton>(refresh).onPressed, isNotNull);
            expect(button.top - group.top, 4);
            expect(group.bottom - button.bottom, 4);
            expect(group.right - button.right, 5);
            expect(button.width - button.height, 4);
            if (scale == 1) {
              expect(group.size, const Size(123, 36));
              expect(button.size, const Size(32, 28));
            }
            final captureName = '${material.name}-${brightness.name}-$scale';
            final rest = await _pixels(tester, '$captureName-rest');
            final well = Color.alphaBlend(
              Colors.black.withValues(
                alpha: brightness == Brightness.dark ? .16 : .045,
              ),
              _canvas,
            );
            final wellSample = rest.colorAt(
              Offset(group.left + 7, group.center.dy),
            );
            expect(wellSample.r, closeTo(well.r, 2 / 255));
            expect(wellSample.g, closeTo(well.g, 2 / 255));
            expect(wellSample.b, closeTo(well.b, 2 / 255));
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: origin + button.center);
            await tester.pumpAndSettle();
            final hovered = await _pixels(tester, '$captureName-hover');
            final dark = brightness == Brightness.dark;
            final tint = (dark ? Colors.white : Colors.black).withValues(
              alpha: dark ? .09 : .06,
            );
            final surface = buttonSurface(tester, of: refresh);
            expect(surface.color, tint);
            expect(surface.borderColor.a, 0);
            expect(
              surface.borderRadius,
              BorderRadius.circular(button.height / 2),
            );

            // The actual raster may change only inside the hovered button.
            // This catches the raised rim, blur and shadow in the reported image.
            var changed = 0;
            for (var y = 0; y < rest.height; y++) {
              for (var x = 0; x < rest.width; x++) {
                final point = Offset((x + .5) / 2, (y + .5) / 2);
                final index = (y * rest.width + x) * 4;
                for (var channel = 0; channel < 4; channel++) {
                  if (button.contains(point)) {
                    if (rest.bytes[index + channel] !=
                        hovered.bytes[index + channel]) {
                      changed++;
                    }
                  } else {
                    expect(
                      hovered.bytes[index + channel],
                      rest.bytes[index + channel],
                      reason: 'Hover paint escaped button at $point',
                    );
                  }
                }
                // No outer shadow in either Standard or Liquid glass.
                if (!group.inflate(1).contains(point)) {
                  expect(rest.bytes.sublist(index, index + 4), [
                    0x16,
                    0x45,
                    0xad,
                    255,
                  ]);
                }
              }
            }
            expect(changed, greaterThan(0));
            final sample = Offset(button.left + 5, button.center.dy);
            final expected = Color.alphaBlend(tint, rest.colorAt(sample));
            final actual = hovered.colorAt(sample);
            expect(actual.r, closeTo(expected.r, 2 / 255));
            expect(actual.g, closeTo(expected.g, 2 / 255));
            expect(actual.b, closeTo(expected.b, 2 / 255));

            // Disabled history buttons never acquire hover styling.
            await mouse.moveTo(tester.getCenter(back));
            await tester.pumpAndSettle();
            expect(buttonSurface(tester, of: back).color.a, 0);
            expect(buttonSurface(tester, of: refresh).color.a, 0);
            await mouse.removePointer();
            // The inset action remains reachable and visibly focused by keyboard.
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
            expect(
              buttonSurface(tester, of: refresh).ringWidth,
              greaterThan(0),
            );
            api.feedPaths.clear();
            for (final point in [
              button.centerLeft - const Offset(1, 0),
              button.centerRight + const Offset(1, 0),
              button.topCenter - const Offset(0, 1),
              button.bottomCenter + const Offset(0, 1),
            ]) {
              await tester.tapAt(origin + point);
              await tester.pumpAndSettle();
            }
            expect(api.feedPaths, isEmpty);
            await tester.tapAt(origin + button.center);
            await tester.pumpAndSettle();
            expect(api.feedPaths, ['/latest.json']);
            expect(tester.takeException(), isNull);
          } finally {
            debugDisableShadows = shadowsDisabled;
          }
        }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
      }
    }
  }
}

Future<_Pixels> _pixels(WidgetTester tester, String name) async =>
    (await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(_capture))
          .toImage(pixelRatio: 2);
      try {
        const directory = String.fromEnvironment('NAVIGATION_CAPTURE_DIR');
        if (directory.isNotEmpty) {
          await Directory(directory).create(recursive: true);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$directory/$name.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        }
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        return _Pixels(bytes!.buffer.asUint8List(), image.width, image.height);
      } finally {
        image.dispose();
      }
    }))!;

class _Pixels {
  const _Pixels(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;

  Color colorAt(Offset point) {
    final index = ((point.dy * 2).floor() * width + (point.dx * 2).floor()) * 4;
    return Color.fromARGB(
      bytes[index + 3],
      bytes[index],
      bytes[index + 1],
      bytes[index + 2],
    );
  }
}
