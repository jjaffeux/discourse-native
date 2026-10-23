import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:discourse_native/src/shell/resizable_pane.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/tab_switch_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('profiles dragging the sidebar and panel seam', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // Per-widget events slow every frame. Use them to find the work, never
    // to report its duration.
    const profileWidgets = bool.fromEnvironment('PROFILE_RESIZE_WIDGETS');
    debugProfileBuildsEnabled = profileWidgets;
    debugProfileLayoutsEnabled = profileWidgets;
    debugProfilePaintsEnabled = profileWidgets;
    // High contrast resolves every glass surface to its opaque fill.
    const highContrast = bool.fromEnvironment('PROFILE_RESIZE_HIGH_CONTRAST');
    if (highContrast) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
    }
    addTearDown(() {
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      debugProfileBuildsEnabled = false;
      debugProfileLayoutsEnabled = false;
      debugProfilePaintsEnabled = false;
    });
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
    await pumpTabSwitchFixture(tester);
    tester.view.physicalSize = nativeSize;
    tester.view.devicePixelRatio = nativeRatio;
    await tester.pumpAndSettle();
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      const window = MethodChannel('org.discourse.native/window');
      await window.invokeMethod<void>('dismissLaunchScreen');
      // Glass reads back the pixels behind it, so its cost follows the size
      // of the window.
      if (const bool.fromEnvironment('PROFILE_RESIZE_MAXIMIZED')) {
        await window.invokeMethod<void>('toggleMaximized');
        tester.view
          ..resetPhysicalSize()
          ..resetDevicePixelRatio();
        // The zoom animates; a drag that starts mid-zoom races the panels'
        // window-resize anchoring.
        var settled = 0;
        var size = tester.view.physicalSize;
        while (settled < 4) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await tester.pumpAndSettle();
          final next = tester.view.physicalSize;
          settled = next == size ? settled + 1 : 0;
          size = next;
        }
      }
    }
    final viewSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    // Both documents are laid out once before any drag is measured.
    await tapDocumentTab(tester, 'reader-a');
    await tester.pumpAndSettle();

    // The widest each drag made its pane, against where it started.
    final growth = <String, double>{};
    Future<void> Function({required int steps}) dragHandle(String handle) =>
        ({required steps}) async {
          final finder = find.byKey(ValueKey('$handle-resize-handle'));
          expect(finder, findsOneWidget);
          final pane = find.ancestor(
            of: finder,
            matching: find.byType(ResizablePane),
          );
          final startWidth = tester.getSize(pane).width;
          var widest = startWidth;
          final gesture = await tester.startGesture(
            tester.getCenter(finder),
            kind: PointerDeviceKind.mouse,
          );
          // Grow first: the sidebar starts 8 pixels above its minimum, so a
          // shrinking drag would spend its frames clamped.
          for (var pass = 0; pass < 2; pass++) {
            for (final direction in const [1.0, -1.0]) {
              for (var step = 0; step < steps; step++) {
                await gesture.moveBy(Offset(direction * 2, 0));
                await tester.pump();
              }
              widest = math.max(widest, tester.getSize(pane).width);
            }
          }
          await gesture.up();
          await tester.pumpAndSettle();
          growth[handle] = widest - startWidth;
        };

    // The same number of frames without a layout change, for comparison.
    Future<void> scrollReader({required int steps}) async {
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(
          tester.getCenter(
            find.byKey(const ValueKey('desktop-panel-secondary')),
          ),
        ),
      );
      for (var pass = 0; pass < 2; pass++) {
        for (final direction in const [1.0, -1.0]) {
          for (var step = 0; step < steps; step++) {
            await tester.sendEventToBinding(
              pointer.scroll(Offset(0, direction * 24)),
            );
            await tester.pump();
          }
        }
      }
      await tester.pumpAndSettle();
    }

    Future<Map<String, Object>> profile(
      String name,
      Future<void> Function({required int steps}) drag,
    ) async {
      await drag(steps: 20);
      final frames = <ui.FrameTiming>[];
      void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
      binding.addTimingsCallback(collect);
      final start = Timeline.now;
      final wallStart = DateTime.now().microsecondsSinceEpoch;
      if (profileWidgets) {
        await binding.traceAction(
          () => drag(steps: 60),
          reportKey: 'timeline-$name',
        );
      } else {
        await drag(steps: 60);
      }
      final end = Timeline.now;
      final wallEnd = DateTime.now().microsecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      binding.removeTimingsCallback(collect);
      frames.removeWhere((frame) {
        final timestamp = frame.timestampInMicroseconds(
          ui.FramePhase.buildStart,
        );
        return timestamp < start || timestamp > end;
      });
      expect(frames.length, greaterThanOrEqualTo(120));
      Map<String, Object> summarize(Duration Function(ui.FrameTiming) time) {
        final ms =
            frames.map((frame) => time(frame).inMicroseconds / 1000).toList()
              ..sort();
        return {
          'meanMs': ms.reduce((a, b) => a + b) / ms.length,
          'p50Ms': ms[(ms.length * .5).floor()],
          'p95Ms': ms[(ms.length * .95).floor()],
          'maxMs': ms.last,
          'over8ms': ms.where((v) => v > 8.333).length,
          'over16ms': ms.where((v) => v > 16.667).length,
        };
      }

      return {
        'case': name,
        // Wall-clock bounds let a Metal System Trace attribute GPU time.
        'wallStartUs': wallStart,
        'wallEndUs': wallEnd,
        'view': [viewSize.width, viewSize.height, tester.view.devicePixelRatio],
        'grewPx': ?growth[name],
        'frames': frames.length,
        'build': summarize((frame) => frame.buildDuration),
        'raster': summarize((frame) => frame.rasterDuration),
      };
    }

    for (final (name, drag) in [
      ('sidebar', dragHandle('sidebar')),
      ('main-panel', dragHandle('main-panel')),
      ('reader-scroll', scrollReader),
    ]) {
      final report = await profile(name, drag);
      debugPrint(
        'PANEL_RESIZE_FRAMES ${jsonEncode({'label': const String.fromEnvironment('PROFILE_LABEL', defaultValue: 'current'), 'debug': kDebugMode, 'highContrast': highContrast, ...report})}',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
