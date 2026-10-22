import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/ui/foundation/native_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'native artwork coalesces a blocked bridge and shows latest paint',
    (tester) async {
      final metrics = <Map<String, Object>>[];
      final color = ValueNotifier(const Color(0xff000000));
      addTearDown(color.dispose);
      NativeGlass.available.value = true;
      addTearDown(() => NativeGlass.available.value = false);
      final uploads = <Map<Object?, Object?>>[];
      final pending = <Completer<void>>[];
      var active = 0;
      var peak = 0;
      var blocked = false;
      var displayedVersion = 0;
      Uint8List? displayed;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeGlass.channel, (call) async {
            if (call.method == 'available') return true;
            if (call.method != 'image') return null;
            final payload = call.arguments as Map<Object?, Object?>;
            uploads.add(payload);
            final version = payload['version']! as int;
            if (version > displayedVersion) {
              displayedVersion = version;
              displayed = payload['png']! as Uint8List;
            }
            active++;
            if (active > peak) peak = active;
            if (blocked) {
              final done = Completer<void>();
              pending.add(done);
              await done.future;
            }
            active--;
            return null;
          });
      addTearDown(() {
        for (final done in pending) {
          if (!done.isCompleted) done.complete();
        }
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeGlass.channel, null);
      });

      Future<void> drain() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }

      Future<List<int>> pixel(Uint8List png) async {
        return (await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(png);
          final frame = await codec.getNextFrame();
          final bytes = await frame.image.toByteData();
          final result = bytes!.buffer.asUint8List().take(4).toList();
          frame.image.dispose();
          codec.dispose();
          return result;
        }))!;
      }

      for (var run = 0; run < 5; run++) {
        await tester.pumpWidget(const SizedBox.shrink());
        await drain();
        uploads.clear();
        pending.clear();
        displayedVersion = 0;
        peak = 0;
        color.value = const Color(0xff000000);
        await tester.pumpWidget(
          MaterialApp(
            theme: DMaterialTheme.apply(
              AppTheme.light.copyWith(platform: TargetPlatform.iOS),
              DAppearanceMaterial.liquidGlass,
            ),
            home: Center(
              child: NativeGlassScope(
                child: Builder(
                  builder: (context) => NativeGlassContent(
                    group: NativeGlass.of(context)!,
                    child: ValueListenableBuilder<Color>(
                      valueListenable: color,
                      builder: (context, value, _) => SizedBox.square(
                        dimension: 24,
                        child: ColoredBox(color: value),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        for (var retry = 0; uploads.isEmpty && retry < 20; retry++) {
          await drain();
        }
        expect(uploads, hasLength(1));
        final before = uploads.length;
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await drain();
        expect(uploads.length, before, reason: 'static frames need no artwork');
        blocked = true;
        uploads.clear();
        peak = 0;
        for (var paint = 1; paint <= 12; paint++) {
          color.value = Color.fromARGB(255, paint, 0, 0);
          await tester.pump();
          await drain();
        }
        final blockedUploads = uploads.length;
        blocked = false;
        for (final done in pending) {
          done.complete();
        }
        for (var retry = 0; retry < 20; retry++) {
          await drain();
        }
        final finalPixel = await pixel(displayed!);
        metrics.add({
          'run': run,
          'repaints': 12,
          'peakInFlightUploads': peak,
          'uploadsWhileBlocked': blockedUploads,
          'uploads': uploads.length,
          'bytes': uploads.fold<int>(
            0,
            (sum, payload) => sum + (payload['png']! as Uint8List).length,
          ),
          'latestArtwork': finalPixel[0] == 12,
          'finalPixel': finalPixel,
        });
        if (!const bool.fromEnvironment('CAPTURE_BASELINE')) {
          expect(peak, 1);
          expect(uploads.length, 2);
          expect(finalPixel, [12, 0, 0, 255]);
        }
      }
      // ignore: avoid_print
      print('NATIVE_GLASS_CAPTURE ${jsonEncode(metrics)}');
      expect(tester.takeException(), isNull);
    },
  );
}
