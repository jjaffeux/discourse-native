import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' as fixture;

void mobileMoreBackdropTests({bool native = false}) {
  for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
    testWidgets('More backdrop opens without flashing ${mode.name}', (
      tester,
    ) async {
      final previousDilation = timeDilation;
      if (native) timeDilation = 3;
      try {
        final shell = await fixture.pumpMobileShellFixture(tester);
        await shell.forumSettings.setThemeMode(
          'https://meta.discourse.org',
          mode,
        );
        await shell.forumSettings.setShared(
          shell.forumSettings.shared.copyWith(),
        );
        await tester.pumpAndSettle();
        final samples = <List<int>>[];
        var opening = 0;
        Future<void> sample(int frame) async {
          final pixels = await tester.runAsync(() async {
            final builder = ui.SceneBuilder();
            tester.binding.renderViews.first.debugLayer!.addToScene(builder);
            final scene = builder.build();
            final image = await scene.toImage(390, 844);
            try {
              final data = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              if (const bool.fromEnvironment('MORE_BACKDROP_CAPTURE')) {
                final png = (await image.toByteData(
                  format: ui.ImageByteFormat.png,
                ))!;
                await File(
                  '/private/tmp/more-backdrop-${native ? 'native' : 'widget'}-${mode.name}-flat-$opening-$frame.png',
                ).writeAsBytes(png.buffer.asUint8List());
              }
              return [
                // Both points stay on the page behind the sheet, whose menu
                // rises past the middle of the screen.
                for (final point in [
                  const Offset(180, 70),
                  const Offset(180, 250),
                ])
                  for (var channel = 0; channel < 3; channel++)
                    data.getUint8(
                      (point.dy.toInt() * 390 + point.dx.toInt()) * 4 + channel,
                    ),
              ];
            } finally {
              image.dispose();
              scene.dispose();
            }
          });
          samples.add(pixels!);
        }

        for (; opening < 2; opening++) {
          samples.clear();
          await sample(0);
          await tester.tap(find.byKey(const ValueKey('mobile-mode-more')));
          await tester.pump();
          for (var frame = 1; frame <= 32; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            await sample(frame);
          }
          if (const bool.fromEnvironment('MORE_BACKDROP_CAPTURE')) {
            debugPrint('MORE_BACKDROP_SAMPLES ${mode.name}/flat: $samples');
          }
          for (var frame = 1; frame < samples.length; frame++) {
            for (var channel = 0; channel < samples[frame].length; channel++) {
              expect(
                samples[frame][channel],
                lessThanOrEqualTo(samples[frame - 1][channel] + 2),
                reason:
                    'background brightened at frame $frame channel $channel',
              );
            }
          }
          await tester.pumpAndSettle();
          final sheet = find.byType(DSheetContent);
          expect(sheet, findsOneWidget);
          await tester.tapAt(Offset(180, tester.getTopLeft(sheet).dy - 30));
          await tester.pumpAndSettle();
          expect(find.byType(DDropdownMenuContent), findsNothing);
        }
        expect(tester.takeException(), isNull);
      } finally {
        timeDilation = previousDilation;
      }
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        ),
  );
  mobileMoreBackdropTests();
}
