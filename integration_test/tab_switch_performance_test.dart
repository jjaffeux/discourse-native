import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/tab_switch_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('profiles rapid document tab buttons', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('org.discourse.native/notification_opens');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
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
    final shell = await pumpTabSwitchFixture(tester);
    tester.view.physicalSize = nativeSize;
    tester.view.devicePixelRatio = nativeRatio;
    await tester.pumpAndSettle();
    debugPrint('TAB_SWITCH_SETUP shell ready');
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      await const MethodChannel(
        'org.discourse.native/window',
      ).invokeMethod<void>('dismissLaunchScreen');
    }
    for (var round = 0; round < 2; round++) {
      for (final id in tabSwitchIds) {
        await tapDocumentTab(tester, id);
        await tester.pumpAndSettle();
      }
    }
    debugPrint('TAB_SWITCH_SETUP tabs warmed');
    final frames = <ui.FrameTiming>[];
    void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
    binding.addTimingsCallback(collect);
    final start = Timeline.now;
    for (var round = 0; round < 12; round++) {
      for (final id in tabSwitchIds) {
        await tapDocumentTab(tester, id);
        await tester.pump();
        expect(shell.activeTabId, id);
        await Future<void>.delayed(const Duration(milliseconds: 65));
      }
    }
    final end = Timeline.now;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    binding.removeTimingsCallback(collect);
    frames.removeWhere((frame) {
      final timestamp = frame.timestampInMicroseconds(ui.FramePhase.buildStart);
      return timestamp < start || timestamp > end;
    });
    expect(frames.length, greaterThanOrEqualTo(48));
    Map<String, Object> summarize(Duration Function(ui.FrameTiming) time) {
      final ms =
          frames.map((frame) => time(frame).inMicroseconds / 1000).toList()
            ..sort();
      return {
        'p50Ms': ms[(ms.length * .5).floor()],
        'p95Ms': ms[(ms.length * .95).floor()],
        'maxMs': ms.last,
        'over16ms': ms.where((v) => v > 16.667).length,
      };
    }

    debugPrint(
      'TAB_SWITCH_FRAMES ${jsonEncode({'label': const String.fromEnvironment('PROFILE_LABEL', defaultValue: 'current'), 'debug': kDebugMode, 'frames': frames.length, 'build': summarize((frame) => frame.buildDuration), 'raster': summarize((frame) => frame.rasterDuration)})}',
    );
    expect(tester.takeException(), isNull);
  });
}
