// Run only while holding the shared native profiling slot.
// Embed the JSON fixture with CATEGORY_FIXTURE_BASE64 using --dart-define-from-file.
// flutter run --profile -d macos -t tool/category_grid_profile_main.dart
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/category_grid_fixture.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setPrefix('category_grid_profile.');
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final semantics = binding.ensureSemantics();
  final lifecycle = _CaptureLifecycle();
  binding.addObserver(lifecycle);
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
            pageSize.width != width) {
          throw StateError(
            'Production category fixture has unexpected geometry',
          );
        }
        if (!binding.semanticsEnabled ||
            binding.lifecycleState != AppLifecycleState.resumed) {
          throw StateError(
            'Capture requires active app and enabled semantics: ${binding.lifecycleState}',
          );
        }
        lifecycle.begin();
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
          offsets.add(scroll!.offset);
        }
        final end = developer.Timeline.now;
        final endGeometry = geometry();
        // Engine timings arrive in batches. Select by vsync time, not callback time.
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        final lostForeground = lifecycle.finish();
        if (lostForeground ||
            binding.lifecycleState != AppLifecycleState.resumed) {
          throw StateError('App lost focus during capture or timing delivery');
        }
        final selected = frames.where((frame) {
          final vsync = frame.timestampInMicroseconds(ui.FramePhase.vsyncStart);
          return vsync >= start && vsync <= end;
        }).toList();
        if (selected.isEmpty) throw StateError('No rendered scrolling frames');
        final view = binding.platformDispatcher.views.first;
        results.add({
          'categories': copies * 12,
          'requestedWidth': width,
          'pageWidth': pageSize.width,
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
  binding.removeObserver(lifecycle);
  semantics.dispose();
  stdout.writeln('CATEGORY_PROFILE ${jsonEncode(results)}');
  exit(0);
}

/// Latches transient focus loss, including during batched timing delivery.
class _CaptureLifecycle extends WidgetsBindingObserver {
  bool _capturing = false;
  bool _lostForeground = false;

  void begin() {
    _lostForeground = false;
    _capturing = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_capturing && state != AppLifecycleState.resumed) {
      _lostForeground = true;
    }
  }

  bool finish() {
    _capturing = false;
    return _lostForeground;
  }
}
