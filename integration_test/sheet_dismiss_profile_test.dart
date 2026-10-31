import 'dart:convert';
import 'dart:developer';
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/topic.dart';
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
  testWidgets('profile repeated topic sheet dismissal', (tester) async {
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
    final nativeRatio = tester.view.devicePixelRatio;
    final shell = await pumpTopicSheetScrollFixture(tester);
    tester.view.physicalSize = nativeSize;
    tester.view.devicePixelRatio = nativeRatio;
    await tester.pumpAndSettle();
    final frames = <ui.FrameTiming>[];
    final samples = <Map<String, Object?>>[];
    void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
    binding.addTimingsCallback(collect);
    try {
      Future<void> dismissCycles() async {
        for (var repeat = 0; repeat < 6; repeat++) {
          if (repeat > 0) {
            shell.openTopic(
              const Topic(
                id: 7,
                title: 'Reading a rich discussion in a sheet',
                slug: 'topic-7',
              ),
            );
            await tester.pumpAndSettle();
          }
          final scroll = topicPostList(tester).controller!;
          scroll.jumpTo(repeat.isOdd ? 900 : 0);
          await tester.pumpAndSettle();
          final handle = find.byKey(const ValueKey('sheet-drag-handle'));
          expect(handle, findsOneWidget);
          final origin = tester.getCenter(handle);
          final startUs = Timeline.now;
          final task = TimelineTask()..start('sheet-drag-$repeat');
          final gesture = await tester.startGesture(origin);
          await gesture.moveBy(const Offset(0, 24));
          await binding.endOfFrame;
          final clock = Stopwatch()..start();
          var travelled = 0.0;
          while (clock.elapsedMilliseconds < 600) {
            final next =
                240.0 * (clock.elapsedMicroseconds / 600000).clamp(0.0, 1.0);
            await gesture.moveBy(
              Offset(0, next - travelled),
              timeStamp: clock.elapsed,
            );
            travelled = next;
            await binding.endOfFrame;
          }
          await gesture.moveBy(
            Offset(0, 240 - travelled),
            timeStamp: clock.elapsed,
          );
          await binding.endOfFrame;
          final pulled = tester.getCenter(handle).dy - origin.dy;
          expect(pulled, greaterThan(120));
          task.finish();
          final releaseUs = Timeline.now;
          final release = TimelineTask()..start('sheet-release-$repeat');
          await gesture.up(timeStamp: clock.elapsed);
          final timeout = Stopwatch()..start();
          while (handle.evaluate().isNotEmpty &&
              timeout.elapsedMilliseconds < 3000) {
            await binding.endOfFrame;
          }
          final removedUs = Timeline.now;
          await tester.pumpAndSettle(const Duration(milliseconds: 16));
          release.finish();
          final endUs = Timeline.now;
          expect(find.byKey(const ValueKey('sheet-drag-handle')), findsNothing);
          expect(tester.takeException(), isNull);
          samples.add({
            'repeat': repeat,
            'scrolled': repeat.isOdd,
            'startUs': startUs,
            'releaseUs': releaseUs,
            'removedUs': removedUs,
            'endUs': endUs,
            'pulled': pulled,
            'releaseMs': (endUs - releaseUs) / 1000,
            'releaseToRemovalMs': (removedUs - releaseUs) / 1000,
          });
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      binding.reportData ??= {};
      if (const bool.fromEnvironment('PROFILE_TIMELINE')) {
        await binding.traceAction(
          dismissCycles,
          streams: const ['Dart', 'Embedder', 'GC'],
          reportKey: 'sheet_dismiss_timeline',
        );
      } else {
        await dismissCycles();
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    } finally {
      binding.removeTimingsCallback(collect);
    }
    final report = {
      'debug': kDebugMode,
      'profile': kProfileMode,
      'timeline': const bool.fromEnvironment('PROFILE_TIMELINE'),
      'pixelRatio': nativeRatio,
      'physicalSize': [nativeSize.width, nativeSize.height],
      'refreshRate': tester.view.display.refreshRate,
      'samples': samples,
      'frames': [
        for (final f in frames)
          {
            'startUs': f.timestampInMicroseconds(ui.FramePhase.buildStart),
            'buildMs': f.buildDuration.inMicroseconds / 1000,
            'rasterMs': f.rasterDuration.inMicroseconds / 1000,
            'totalMs': f.totalSpan.inMicroseconds / 1000,
          },
      ],
    };
    binding.reportData!['sheet_dismiss_frames'] = report;
    debugPrint('SHEET_DISMISS_SAMPLES ${jsonEncode(samples)}', wrapWidth: 2048);
    expect(samples, hasLength(6));
    expect(frames, isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
