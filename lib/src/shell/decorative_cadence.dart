import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Repaints a decorative effect without keeping every display frame active.
class DecorativeCadence extends ChangeNotifier with WidgetsBindingObserver {
  DecorativeCadence() : _binding = WidgetsBinding.instance {
    _lifecycleState = _binding.lifecycleState;
    _binding.addObserver(this);
  }

  final WidgetsBinding _binding;
  AppLifecycleState? _lifecycleState;
  Timer? _timer;
  Duration? _interval;
  int? _frameCallbackId;
  int _generation = 0;
  bool _active = false;
  bool _disposed = false;
  Duration _elapsed = Duration.zero;
  Duration? _lastFrameTimeStamp;

  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    _updateCadence();
  }

  /// Samples active animation time from the current frame, excluding pauses.
  Duration sampleElapsed() {
    if (_interval == null || _binding.schedulerPhase == SchedulerPhase.idle) {
      return _elapsed;
    }
    final frameTimeStamp = _binding.currentFrameTimeStamp;
    final previous = _lastFrameTimeStamp;
    if (previous != null && frameTimeStamp > previous) {
      _elapsed += frameTimeStamp - previous;
    }
    _lastFrameTimeStamp = frameTimeStamp;
    return _elapsed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _updateCadence();
  }

  void _updateCadence() {
    final interval = !_active
        ? null
        : switch (_lifecycleState) {
            null ||
            AppLifecycleState.resumed => const Duration(microseconds: 33333),
            AppLifecycleState.inactive => const Duration(milliseconds: 100),
            _ => null,
          };
    if (interval == _interval) return;
    final wasRunning = _interval != null;
    _timer?.cancel();
    _timer = null;
    _interval = interval;
    if (interval == null) {
      _generation++;
      final callbackId = _frameCallbackId;
      if (callbackId != null) _binding.cancelFrameCallbackWithId(callbackId);
      _frameCallbackId = null;
      _lastFrameTimeStamp = null;
      return;
    }
    _timer = Timer.periodic(interval, (_) => _queueFrame());
    if (!wasRunning) _queueFrame();
  }

  void _queueFrame() {
    if (_disposed || _interval == null || _frameCallbackId != null) return;
    final generation = _generation;
    _frameCallbackId = _binding.scheduleFrameCallback((_) {
      if (_disposed || generation != _generation) return;
      _frameCallbackId = null;
      if (_interval == null) return;
      sampleElapsed();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _active = false;
    _updateCadence();
    _disposed = true;
    _binding.removeObserver(this);
    super.dispose();
  }
}
