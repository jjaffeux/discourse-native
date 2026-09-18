// Run only while holding the shared native profiling slot.
// Embed the JSON fixture with CATEGORY_FIXTURE_BASE64 using --dart-define-from-file.
// flutter run --profile -d macos -t tool/category_grid_profile_main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/category_grid_fixture.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setPrefix('category_grid_profile.');
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final semantics = binding.ensureSemantics();
  final guard = _CaptureGuard(binding);
  binding.addObserver(guard);
  binding.addSemanticsEnabledListener(guard.semanticsChanged);
  final startRequested = Completer<void>();
  runApp(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: DButton(
            label: const Text('Start category capture'),
            onPressed: () {
              if (!startRequested.isCompleted) startRequested.complete();
            },
          ),
        ),
      ),
    ),
  );
  await binding.endOfFrame;
  stdout.writeln(
    'CATEGORY_PROFILE_READY: activate this fixture and press Start',
  );
  await startRequested.future;
  runApp(
    MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: Center(child: Text('Warming up category capture…')),
      ),
    ),
  );
  await binding.endOfFrame;
  final expectedView = _viewGeometry(binding);
  guard.begin(expectedView);
  stdout.writeln('CATEGORY_PROFILE_WARMUP: 10 seconds');
  await Future<void>.delayed(const Duration(seconds: 10));
  guard.finish(expectedView);
  stdout.writeln('CATEGORY_PROFILE_STARTED');
  final frames = <ui.FrameTiming>[];
  binding.addTimingsCallback(frames.addAll);
  final results = <Map<String, Object?>>[];
  for (final copies in [1, 5]) {
    final controller = await categoryGridController(
      categoryGridFixture(copies: copies),
    );
    for (final width in [390.0, 700.0, 1100.0]) {
      for (var repeat = 0; repeat < 6; repeat++) {
        final key = GlobalKey();
        runApp(categoryGridHost(controller, width, pageKey: key));
        await binding.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        ScrollController? scroll;
        List<Map<String, Object?>> geometry() {
          final cards = <Map<String, Object?>>[];
          void visit(Element element) {
            if (element.widget case CustomScrollView(:final controller)) {
              scroll = controller;
            }
            if (element.widget.key case ValueKey<String>(
              :final value,
            ) when value.startsWith('category-card-')) {
              final box = element.findRenderObject()! as RenderBox;
              final origin = box.localToGlobal(Offset.zero);
              if (!origin.dx.isFinite ||
                  !origin.dy.isFinite ||
                  !box.size.width.isFinite ||
                  !box.size.height.isFinite ||
                  box.size.width <= 0 ||
                  box.size.height <= 0) {
                throw StateError('Invalid numeric category card geometry');
              }
              cards.add({
                'key': value,
                'x': origin.dx,
                'y': origin.dy,
                'width': box.size.width,
                'height': box.size.height,
              });
            }
            element.visitChildren(visit);
          }

          visit(key.currentContext! as Element);
          return cards;
        }

        final startGeometry = geometry();
        final pageSize =
            (key.currentContext!.findRenderObject()! as RenderBox).size;
        if (startGeometry.isEmpty ||
            scroll == null ||
            pageSize.width != width ||
            !pageSize.height.isFinite ||
            pageSize.height <= 0) {
          throw StateError(
            'Production category fixture has unexpected geometry',
          );
        }
        guard.begin(expectedView);
        frames.clear();
        final offsets = <double>[];
        final startUtc = DateTime.now().toUtc().toIso8601String();
        final start = developer.Timeline.now;
        for (var step = 0; step < 60; step++) {
          final position = scroll!.position;
          scroll!.jumpTo(
            position.extentAfter < 1
                ? 0
                : (position.pixels + 90).clamp(0, position.maxScrollExtent),
          );
          await binding.endOfFrame;
          if (!scroll!.offset.isFinite) {
            throw StateError('Invalid numeric scroll offset');
          }
          offsets.add(scroll!.offset);
        }
        final end = developer.Timeline.now;
        final endGeometry = geometry();
        // Engine timings arrive in batches. Select by vsync time, not callback time.
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        guard.finish(expectedView);
        final finalPageSize =
            (key.currentContext!.findRenderObject()! as RenderBox).size;
        if (finalPageSize != pageSize ||
            !scroll!.position.maxScrollExtent.isFinite) {
          throw StateError(
            'Page geometry changed during capture or timing delivery',
          );
        }
        final selected = frames.where((frame) {
          final vsync = frame.timestampInMicroseconds(ui.FramePhase.vsyncStart);
          return vsync >= start && vsync <= end;
        }).toList();
        if (selected.isEmpty) throw StateError('No rendered scrolling frames');
        final view = binding.platformDispatcher.views.first;
        results.add({
          'collectorVersion': 2,
          'activationWarmupSeconds': 10,
          'categories': copies * 12,
          'requestedWidth': width,
          'pageWidth': pageSize.width,
          'pageHeight': pageSize.height,
          'physicalWidth': expectedView.physicalWidth,
          'physicalHeight': expectedView.physicalHeight,
          'viewWidth': view.physicalSize.width / view.devicePixelRatio,
          'viewHeight': view.physicalSize.height / view.devicePixelRatio,
          'devicePixelRatio': view.devicePixelRatio,
          'refreshRate': view.display.refreshRate,
          'semanticsEnabled': binding.semanticsEnabled,
          'lifecycleState': binding.lifecycleState?.name,
          'startUtc': startUtc,
          'windowDurationUs': end - start,
          'scrollExtent': scroll!.position.maxScrollExtent,
          'offsets': offsets,
          'startGeometry': startGeometry,
          'endGeometry': endGeometry,
          'repeat': repeat,
          'warmup': repeat == 0,
          'vsyncElapsedUs': selected
              .map(
                (f) =>
                    f.timestampInMicroseconds(ui.FramePhase.vsyncStart) - start,
              )
              .toList(),
          'buildUs': selected
              .map((f) => f.buildDuration.inMicroseconds)
              .toList(),
          'rasterUs': selected
              .map((f) => f.rasterDuration.inMicroseconds)
              .toList(),
        });
      }
    }
    runApp(const SizedBox.shrink());
    await binding.endOfFrame;
    controller.dispose();
  }
  binding.removeSemanticsEnabledListener(guard.semanticsChanged);
  binding.removeObserver(guard);
  semantics.dispose();
  stdout.writeln('CATEGORY_PROFILE ${jsonEncode(results)}');
  exit(0);
}

typedef _ViewGeometry = ({
  double physicalWidth,
  double physicalHeight,
  double devicePixelRatio,
  double refreshRate,
});

_ViewGeometry _viewGeometry(WidgetsBinding binding) {
  final view = binding.platformDispatcher.views.single;
  final result = (
    physicalWidth: view.physicalSize.width,
    physicalHeight: view.physicalSize.height,
    devicePixelRatio: view.devicePixelRatio,
    refreshRate: view.display.refreshRate,
  );
  for (final value in [
    result.physicalWidth,
    result.physicalHeight,
    result.devicePixelRatio,
    result.refreshRate,
  ]) {
    if (!value.isFinite || value <= 0) {
      throw StateError('Invalid numeric viewport geometry: $result');
    }
  }
  return result;
}

/// Rejects transient changes even if the original state returns before the drain.
class _CaptureGuard extends WidgetsBindingObserver {
  _CaptureGuard(this.binding);

  final WidgetsBinding binding;
  bool _capturing = false;
  String? _invalidReason;

  void begin(_ViewGeometry expectedView) {
    _invalidReason = null;
    _capturing = true;
    _validate(expectedView);
  }

  void _invalidate(String reason) {
    if (_capturing) _invalidReason ??= reason;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _invalidate('App left resumed state: $state');
    }
  }

  @override
  void didChangeMetrics() => _invalidate('Viewport metrics changed');

  @override
  void didChangeAccessibilityFeatures() =>
      _invalidate('Accessibility features changed');

  void semanticsChanged() => _invalidate('Semantics state changed');

  void _validate(_ViewGeometry expectedView) {
    if (_invalidReason case final reason?) throw StateError(reason);
    if (!binding.semanticsEnabled ||
        binding.lifecycleState != AppLifecycleState.resumed) {
      throw StateError(
        'Capture requires active app and enabled semantics: ${binding.lifecycleState}',
      );
    }
    if (_viewGeometry(binding) != expectedView) {
      throw StateError(
        'Viewport geometry/DPR changed from activation baseline',
      );
    }
  }

  void finish(_ViewGeometry expectedView) {
    try {
      _validate(expectedView);
    } finally {
      _capturing = false;
    }
  }
}
