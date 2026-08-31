import 'dart:async';

import 'package:discourse_native/src/diagnostics/diagnostics_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

typedef _PlatformErrorHandler = bool Function(Object, StackTrace);

final class DiagnosticsGlobalErrorBinding {
  DiagnosticsGlobalErrorBinding._({
    required this._sink,
    required this._previousFlutterHandler,
    required this._previousPlatformHandler,
    required this._previousFlutterBinding,
    required this._previousPlatformBinding,
  });

  static DiagnosticsGlobalErrorBinding? _flutterBinding;
  static DiagnosticsGlobalErrorBinding? _platformBinding;

  final DiagnosticsSink _sink;
  final FlutterExceptionHandler? _previousFlutterHandler;
  final _PlatformErrorHandler? _previousPlatformHandler;
  final DiagnosticsGlobalErrorBinding? _previousFlutterBinding;
  final DiagnosticsGlobalErrorBinding? _previousPlatformBinding;
  Expando<Object> _reportedErrorEpochs = Expando<Object>(
    'global diagnostics reported error epochs',
  );
  Object _errorEpoch = Object();
  bool _epochRotationScheduled = false;
  late final FlutterExceptionHandler _installedFlutterHandler =
      _handleFlutterError;
  late final _PlatformErrorHandler _installedPlatformHandler =
      _handlePlatformError;
  bool _closed = false;

  static DiagnosticsGlobalErrorBinding install(DiagnosticsSink sink) {
    final previousFlutterHandler = FlutterError.onError;
    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    final activeFlutterBinding = _flutterBinding;
    final activePlatformBinding = _platformBinding;
    final binding = DiagnosticsGlobalErrorBinding._(
      sink: sink,
      previousFlutterHandler: previousFlutterHandler,
      previousPlatformHandler: previousPlatformHandler,
      previousFlutterBinding:
          activeFlutterBinding != null &&
              identical(
                previousFlutterHandler,
                activeFlutterBinding._installedFlutterHandler,
              )
          ? activeFlutterBinding
          : null,
      previousPlatformBinding:
          activePlatformBinding != null &&
              identical(
                previousPlatformHandler,
                activePlatformBinding._installedPlatformHandler,
              )
          ? activePlatformBinding
          : null,
    );
    FlutterError.onError = binding._installedFlutterHandler;
    PlatformDispatcher.instance.onError = binding._installedPlatformHandler;
    _flutterBinding = binding;
    _platformBinding = binding;
    return binding;
  }

  void reportUnhandledError(
    Object error,
    StackTrace stackTrace, {
    required String source,
  }) {
    if (_closed || _wasReportedThisMicrotask(error)) return;

    // Framework errors can be reported while Flutter is laying out or
    // painting. Recording them immediately would notify diagnostics widgets,
    // whose rebuild then schedules another frame from inside the current one.
    // Keep forwarding the original error synchronously, but publish its
    // diagnostic once the frame has finished.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _recordUnhandledError(error, stackTrace, source: source);
      });
      return;
    }

    _recordUnhandledError(error, stackTrace, source: source);
  }

  void _recordUnhandledError(
    Object error,
    StackTrace stackTrace, {
    required String source,
  }) {
    if (_closed) return;
    try {
      _sink.reportError(
        error,
        stackTrace,
        operation: 'unhandled',
        source: source,
        handled: false,
        degraded: false,
      );
    } on Object {
      // Diagnostics must never change framework error handling behavior.
    }
  }

  bool _wasReportedThisMicrotask(Object error) {
    try {
      if (identical(_reportedErrorEpochs[error], _errorEpoch)) return true;
      _reportedErrorEpochs[error] = _errorEpoch;
    } on Object {
      // Primitive thrown values cannot be weak Expando keys. Avoid retaining
      // them strongly for a diagnostic-only optimization.
      return false;
    }
    if (!_epochRotationScheduled) {
      _epochRotationScheduled = true;
      scheduleMicrotask(() {
        _errorEpoch = Object();
        _epochRotationScheduled = false;
      });
    }
    return false;
  }

  void _handleFlutterError(FlutterErrorDetails details) {
    reportUnhandledError(
      details.exception,
      details.stack ?? StackTrace.current,
      source: 'flutter',
    );
    final previous = _previousFlutterHandler;
    if (previous != null) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }
  }

  bool _handlePlatformError(Object error, StackTrace stackTrace) {
    reportUnhandledError(error, stackTrace, source: 'platform');
    return _previousPlatformHandler?.call(error, stackTrace) ?? false;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _reportedErrorEpochs = Expando<Object>(
      'global diagnostics reported error epochs',
    );
    _errorEpoch = Object();
    _epochRotationScheduled = false;
    _releaseFlutterHandler();
    _releasePlatformHandler();
  }

  void _releaseFlutterHandler() {
    if (!identical(_flutterBinding, this)) return;
    if (!identical(FlutterError.onError, _installedFlutterHandler)) {
      // A handler installed outside this binding stack is authoritative.
      _flutterBinding = null;
      return;
    }

    var handler = _previousFlutterHandler;
    var binding = _previousFlutterBinding;
    while (binding != null && binding._closed) {
      handler = binding._previousFlutterHandler;
      binding = binding._previousFlutterBinding;
    }
    _flutterBinding = binding;
    FlutterError.onError = binding?._installedFlutterHandler ?? handler;
  }

  void _releasePlatformHandler() {
    if (!identical(_platformBinding, this)) return;
    if (!identical(
      PlatformDispatcher.instance.onError,
      _installedPlatformHandler,
    )) {
      // A handler installed outside this binding stack is authoritative.
      _platformBinding = null;
      return;
    }

    var handler = _previousPlatformHandler;
    var binding = _previousPlatformBinding;
    while (binding != null && binding._closed) {
      handler = binding._previousPlatformHandler;
      binding = binding._previousPlatformBinding;
    }
    _platformBinding = binding;
    PlatformDispatcher.instance.onError =
        binding?._installedPlatformHandler ?? handler;
  }
}
