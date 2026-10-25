import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/topic_post_list.dart';
import '../test/support/topic_sheet_scroll_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('profile topic sheet scrolling', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('org.discourse.native/notification_opens');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
    final nativeSize = tester.view.physicalSize;
    final nativePixelRatio = tester.view.devicePixelRatio;
    final shell = await pumpTopicSheetScrollFixture(tester);
    tester.view.physicalSize = nativeSize;
    tester.view.devicePixelRatio = nativePixelRatio;
    await tester.pumpAndSettle();
    final scroll = topicPostList(tester).controller!;
    Future<void> sweep() async {
      for (final delta in [-2600.0, 2600.0]) {
        final origin = tester.getCenter(topicPostListFinder());
        final drag = scroll.position.drag(
          DragStartDetails(globalPosition: origin),
          () {},
        );
        final elapsed = Stopwatch()..start();
        var travelled = 0.0;
        while (elapsed.elapsed < const Duration(seconds: 2)) {
          final next =
              delta * (elapsed.elapsedMicroseconds / 2000000).clamp(0.0, 1.0);
          final movement = next - travelled;
          travelled = next;
          drag.update(
            DragUpdateDetails(
              globalPosition: origin + Offset(0, travelled),
              delta: Offset(0, movement),
              primaryDelta: movement,
            ),
          );
          await binding.endOfFrame;
        }
        drag.update(
          DragUpdateDetails(
            globalPosition: origin + Offset(0, delta),
            delta: Offset(0, delta - travelled),
            primaryDelta: delta - travelled,
          ),
        );
        drag.end(DragEndDetails(primaryVelocity: 0));
      }
    }

    {
      await shell.forumSettings.setShared(
        shell.forumSettings.shared.copyWith(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DSheetViewport), findsOneWidget);
      expect(scroll.position.maxScrollExtent, greaterThan(4000));
      scroll.jumpTo(600);
      await sweep();
      final frames = <ui.FrameTiming>[];
      void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
      final startUs = Timeline.now;
      final elapsed = Stopwatch()..start();
      binding.addTimingsCallback(collect);
      late final int endUs;
      try {
        for (var repeat = 0; repeat < 3; repeat++) {
          await sweep();
        }
        endUs = Timeline.now;
        elapsed.stop();
        await Future<void>.delayed(const Duration(seconds: 1));
      } finally {
        binding.removeTimingsCallback(collect);
      }
      frames.removeWhere((f) {
        final t = f.timestampInMicroseconds(ui.FramePhase.buildStart);
        return t < startUs || t > endUs;
      });
      expect(elapsed.elapsed, lessThan(const Duration(seconds: 18)));
      expect(frames.length, greaterThan(100));
      Map<String, Object> summary(Duration Function(ui.FrameTiming) duration) {
        final values =
            frames.map((f) => duration(f).inMicroseconds / 1000).toList()
              ..sort();
        return {
          'meanMs': values.reduce((a, b) => a + b) / values.length,
          'p50Ms': values[(values.length * .5).floor()],
          'p95Ms': values[(values.length * .95).floor()],
          'p99Ms': values[(values.length * .99).floor()],
          'over16ms': values.where((v) => v > 16.667).length,
          'over8ms': values.where((v) => v > 8.333).length,
        };
      }

      final report = {
        'label': const String.fromEnvironment(
          'PROFILE_LABEL',
          defaultValue: 'current',
        ),
        'debug': kDebugMode,
        'pixelRatio': tester.view.devicePixelRatio,
        'refreshRate': tester.view.display.refreshRate,
        'physicalSize': [
          tester.view.physicalSize.width,
          tester.view.physicalSize.height,
        ],
        'frames': frames.length,
        'build': summary((f) => f.buildDuration),
        'raster': summary((f) => f.rasterDuration),
      };
      debugPrint(
        'TOPIC_SHEET_SCROLL_PROFILE ${jsonEncode(report)}',
        wrapWidth: 2048,
      );
      binding.reportData ??= {};
      binding.reportData!['flat'] = report;
      expect(scroll.position.pixels, closeTo(600, 1));
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_TOPIC_SHEET')) {
        await binding.takeScreenshot('topic-sheet-flat');
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
