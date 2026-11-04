import 'dart:convert';
import 'dart:developer';
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/topic.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/mobile_shell_test.dart' show pumpMobileShellFixture;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('profile mobile sidebar buttons and swipes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('org.discourse.native/notification_opens');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      debugProfileBuildsEnabled = false;
      debugProfileLayoutsEnabled = false;
      debugProfilePaintsEnabled = false;
    });
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
    final shell = await pumpMobileShellFixture(
      tester,
      topics: [
        for (var id = 1; id <= 60; id++)
          Topic(
            id: id,
            title: 'Discussion $id about a responsive mobile sidebar',
            slug: 'discussion-$id',
            postsCount: 12,
          ),
      ],
    );
    tester.view.physicalSize = nativeSize;
    tester.view.devicePixelRatio = nativeRatio;
    await tester.pumpAndSettle();
    final frames = <ui.FrameTiming>[];
    final samples = <Map<String, Object>>[];
    void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
    final menu = find.byKey(const ValueKey('mobile-menu-button'));

    Future<void> transition(bool open, bool swipe, int repeat) async {
      expect(shell.mobileNavigation.sidebarOpen, !open);
      final task = TimelineTask()
        ..start(
          'sidebar-${swipe ? 'swipe' : 'button'}-${open ? 'open' : 'close'}',
        );
      final start = Timeline.now;
      var release = start;
      if (swipe) {
        final size = nativeSize / nativeRatio;
        final origin = Offset(open ? 2 : size.width - 2, size.height / 2);
        final gesture = await tester.startGesture(origin);
        await gesture.moveBy(Offset(open ? 24 : -24, 0));
        await binding.endOfFrame;
        final clock = Stopwatch()..start();
        var travelled = 24.0;
        while (clock.elapsedMilliseconds < 200) {
          final next =
              24 +
              size.width *
                  .6 *
                  (clock.elapsedMicroseconds / 200000).clamp(0.0, 1.0);
          await gesture.moveBy(
            Offset((next - travelled) * (open ? 1 : -1), 0),
            timeStamp: clock.elapsed,
          );
          travelled = next;
          await binding.endOfFrame;
        }
        release = Timeline.now;
        await gesture.up(timeStamp: clock.elapsed);
      } else if (open) {
        await tester.tap(menu);
      } else {
        // The header button is hidden with navigation open. Use the same
        // close action as Escape, without a synthetic hardware key mapping.
        shell.closeMobileSidebar();
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      final end = Timeline.now;
      task.finish();
      expect(shell.mobileNavigation.sidebarOpen, open);
      expect(tester.takeException(), isNull);
      samples.add({
        'repeat': repeat,
        'action': '${swipe ? 'swipe' : 'button'}-${open ? 'open' : 'close'}',
        'startUs': start,
        'endUs': end,
        'elapsedMs': (end - start) / 1000,
        'settleMs': (end - release) / 1000,
      });
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    // Warm both paths before collecting timings.
    for (final swipe in [false, true]) {
      await transition(true, swipe, -1);
      await transition(false, swipe, -1);
    }
    samples.clear();
    const trace = bool.fromEnvironment('PROFILE_SIDEBAR_WIDGETS');
    debugProfileBuildsEnabled = trace;
    debugProfileLayoutsEnabled = trace;
    debugProfilePaintsEnabled = trace;
    binding.addTimingsCallback(collect);
    Future<void> cycles() async {
      for (var repeat = 0; repeat < 6; repeat++) {
        for (final swipe in [false, true]) {
          await transition(true, swipe, repeat);
          await transition(false, swipe, repeat);
        }
      }
    }

    try {
      binding.reportData ??= {};
      if (trace) {
        await binding.traceAction(
          cycles,
          streams: const ['Dart', 'Embedder', 'GC'],
          reportKey: 'sidebar_timeline',
        );
      } else {
        await cycles();
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    } finally {
      binding.removeTimingsCallback(collect);
    }
    binding.reportData!['sidebar_frames'] = {
      'debug': kDebugMode,
      'profile': kProfileMode,
      'trace': trace,
      'physicalSize': [nativeSize.width, nativeSize.height],
      'pixelRatio': nativeRatio,
      'refreshRate': tester.view.display.refreshRate,
      'samples': samples,
      'frames': [
        for (final frame in frames)
          {
            'startUs': frame.timestampInMicroseconds(ui.FramePhase.buildStart),
            'buildMs': frame.buildDuration.inMicroseconds / 1000,
            'rasterMs': frame.rasterDuration.inMicroseconds / 1000,
          },
      ],
    };
    debugPrint('SIDEBAR_SAMPLES ${jsonEncode(samples)}', wrapWidth: 2048);
    expect(samples, hasLength(24));
    expect(frames, isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
