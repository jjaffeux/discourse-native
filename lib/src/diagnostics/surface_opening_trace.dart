import 'dart:developer' as developer;

import 'package:flutter/scheduler.dart';

/// Opt-in, content-free opening milestones. Enable in DevTools with
/// --dart-define=TRACE_SURFACE_OPENING=true, or attach a profile recorder.
abstract final class SurfaceOpeningTrace {
  static const _enabled = bool.fromEnvironment('TRACE_SURFACE_OPENING');

  static void Function(String name, int timestamp)? observer;

  static bool get enabled => _enabled || observer != null;

  static void mark(String name) {
    if (!enabled) return;
    if (_enabled) developer.Timeline.instantSync('opening.$name');
    observer?.call(name, developer.Timeline.now);
  }

  /// Marks completion of layout/paint, not delivery of a rasterized frame.
  /// FrameTiming is recorded separately by the native profile harness.
  static void afterFrame(String name, {required bool Function() isCurrent}) {
    if (!enabled) return;
    final listener = observer;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (identical(listener, observer) && isCurrent()) mark(name);
    });
  }
}
