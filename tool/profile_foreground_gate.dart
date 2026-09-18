import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rejects profile samples unless the app stays resumed for the entire capture.
class ProfileForegroundGate extends WidgetsBindingObserver {
  ProfileForegroundGate() : _binding = WidgetsBinding.instance {
    _state = _binding.lifecycleState;
    _binding.addObserver(this);
  }

  final WidgetsBinding _binding;
  AppLifecycleState? _state;
  Completer<void>? _resumed;
  Completer<AppLifecycleState>? _lostForeground;

  Future<void> waitUntilResumed({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_state == AppLifecycleState.resumed) return;
    final resumed = _resumed ??= Completer<void>();
    await resumed.future.timeout(
      timeout,
      onTimeout: () => throw StateError(
        'Profile startup requires resumed; lifecycle is ${_state?.name}.',
      ),
    );
    _requireResumed();
  }

  /// A loss is latched even if the app resumes before [capture] completes.
  /// The loss also rejects immediately if a frame future stops completing.
  Future<T> runCapture<T>(Future<T> Function() capture) async {
    _requireResumed();
    if (_lostForeground != null) {
      throw StateError('Profile captures must not overlap.');
    }
    final lost = _lostForeground = Completer<AppLifecycleState>();
    try {
      final result = await Future.any([
        lost.future.then<T>(
          (state) => throw StateError(
            'Invalid profile capture: lifecycle changed to ${state.name}.',
          ),
        ),
        capture(),
      ]);
      // Do not accept a race in which completion and loss happen together.
      if (lost.isCompleted) {
        throw StateError('Invalid profile capture: foreground was lost.');
      }
      _requireResumed();
      return result;
    } finally {
      _lostForeground = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state = state;
    if (state == AppLifecycleState.resumed) {
      final resumed = _resumed;
      _resumed = null;
      if (resumed != null && !resumed.isCompleted) resumed.complete();
    } else {
      final lost = _lostForeground;
      if (lost != null && !lost.isCompleted) lost.complete(state);
    }
  }

  void _requireResumed() {
    if (_state != AppLifecycleState.resumed) {
      throw StateError(
        'Profile capture requires resumed; got ${_state?.name}.',
      );
    }
  }

  void dispose() => _binding.removeObserver(this);
}
