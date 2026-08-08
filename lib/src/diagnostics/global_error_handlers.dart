import 'dart:async';

import 'package:discourse_native/src/diagnostics/diagnostics_controller.dart';
import 'package:flutter/foundation.dart';

typedef _PlatformErrorHandler = bool Function(Object, StackTrace);

/// Installs diagnostics recording around Flutter's process-wide error hooks.
///
/// Existing handlers remain authoritative: Flutter errors are forwarded to the
/// previous handler (or Flutter's default presenter), and platform errors
/// return the previous handler's handled value. Recording is deliberately
/// best-effort so it can never alter either path.
final class DiagnosticsGlobalErrorBinding {
  DiagnosticsGlobalErrorBinding._({
    required this._sink,
    required this._previousFlutterHandler,
    required this._previousPlatformHandler,
  });

  final DiagnosticsSink _sink;
  final FlutterExceptionHandler? _previousFlutterHandler;
  final _PlatformErrorHandler? _previousPlatformHandler;
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
    final binding = DiagnosticsGlobalErrorBinding._(
      sink: sink,
      previousFlutterHandler: previousFlutterHandler,
      previousPlatformHandler: previousPlatformHandler,
    );
    FlutterError.onError = binding._installedFlutterHandler;
    PlatformDispatcher.instance.onError = binding._installedPlatformHandler;
    return binding;
  }

  /// Records an unhandled error once per object identity in this microtask.
  ///
  /// Flutter, the platform dispatcher, and the guarded root zone can observe
  /// the same exception in succession. Keeping this short-lived identity set
  /// avoids duplicate events without retaining raw exceptions in app state.
  void reportUnhandledError(
    Object error,
    StackTrace stackTrace, {
    required String source,
  }) {
    if (_closed || _wasReportedThisMicrotask(error)) return;
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

  /// Restores only hooks still owned by this binding.
  ///
  /// This makes cleanup safe when another subsystem installs a newer handler
  /// after diagnostics has been bound.
  void close() {
    if (_closed) return;
    _closed = true;
    _reportedErrorEpochs = Expando<Object>(
      'global diagnostics reported error epochs',
    );
    _errorEpoch = Object();
    _epochRotationScheduled = false;
    if (identical(FlutterError.onError, _installedFlutterHandler)) {
      FlutterError.onError = _previousFlutterHandler;
    }
    if (identical(
      PlatformDispatcher.instance.onError,
      _installedPlatformHandler,
    )) {
      PlatformDispatcher.instance.onError = _previousPlatformHandler;
    }
  }
}
