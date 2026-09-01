import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:logger/logger.dart' as native_logger;
import 'package:logging/logging.dart' as dart_logging;

import 'voice_diagnostics.dart';

/// LiveKit exposes a Dart logging stream on every supported platform. The
/// vendored flutter_webrtc native hook currently exists only on iOS/macOS, so
/// Linux records an explicit availability marker instead of pretending native
/// WebRTC lines are being captured there.
final class NativeVoiceDiagnosticsSdkLogBridge
    implements VoiceDiagnosticsSdkLogBridge {
  static final native_logger.Logger _silentWebRtcLogger = native_logger.Logger(
    filter: native_logger.ProductionFilter(),
    level: native_logger.Level.off,
  );
  static final List<NativeVoiceDiagnosticsSdkLogBridge> _globalOwners = [];
  static Future<void> _globalTail = Future<void>.value();
  static void Function()? _enableLiveKitLogging;
  static void Function()? _restoreBaselineLiveKitLevel;

  // The subscription spans the explicit capture window and is cancelled by
  // the guarded multi-resource cleanup in uninstall().
  // ignore: cancel_subscriptions
  StreamSubscription<dynamic>? _liveKitSubscription;
  native_logger.Logger? _webRtcLogger;
  bool _installed = false;

  @override
  Future<void> install(VoiceDiagnosticsRecorder recorder) async {
    if (_installed) return;
    _installed = true;

    _liveKitSubscription = livekit.logger.onRecord.listen((record) {
      if (!record.loggerName.toString().startsWith('livekit')) return;
      recorder.recordRaw(
        'sdk.livekit.log',
        component: 'livekit_sdk',
        severity: _liveKitSeverity(record.level.name.toString()),
        message: record.message.toString(),
        data: {
          'level': record.level.name.toString(),
          if (record.error != null) 'error': record.error.toString(),
          if (record.stackTrace != null)
            'stackTrace': record.stackTrace.toString(),
        },
      );
    });
    if (!Platform.isIOS && !Platform.isMacOS) {
      await _claimGlobalLogging();
      recorder.recordRaw(
        'sdk.webrtc.native_log_hook.unavailable',
        component: 'webrtc_sdk',
        severity: DiagnosticSeverity.info,
        data: {'platform': Platform.operatingSystem},
      );
      return;
    }

    final logger = native_logger.Logger(
      filter: native_logger.ProductionFilter(),
      printer: native_logger.SimplePrinter(colors: false),
      output: _VoiceWebRtcLogOutput(recorder),
      level: native_logger.Level.trace,
    );
    _webRtcLogger = logger;
    await logger.init;
    await _claimGlobalLogging();
  }

  @override
  Future<void> uninstall() async {
    if (!_installed) return;
    _installed = false;

    final subscription = _liveKitSubscription;
    final webRtcLogger = _webRtcLogger;
    _liveKitSubscription = null;
    _webRtcLogger = null;

    await runVoiceSdkCleanup([
      _releaseGlobalLogging,
      if (subscription != null) subscription.cancel,
      if (webRtcLogger != null) webRtcLogger.close,
    ]);
  }

  Future<void> _claimGlobalLogging() => _serializeGlobal(() async {
    if (!_installed) return;
    if (_globalOwners.isEmpty) {
      if (dart_logging.hierarchicalLoggingEnabled) {
        final baseline = livekit.logger.level;
        _enableLiveKitLogging = () {
          livekit.setLoggingLevel(livekit.LoggerLevel.kALL);
        };
        _restoreBaselineLiveKitLevel = () {
          livekit.logger.level = baseline;
        };
      } else {
        final baseline = dart_logging.Logger.root.level;
        _enableLiveKitLogging = () {
          dart_logging.Logger.root.level = dart_logging.Level.ALL;
        };
        _restoreBaselineLiveKitLevel = () {
          dart_logging.Logger.root.level = baseline;
        };
      }
    }
    _globalOwners
      ..remove(this)
      ..add(this);
    _enableLiveKitLogging?.call();
    if (Platform.isIOS || Platform.isMacOS) {
      final logger = _webRtcLogger;
      if (logger != null) await rtc.Helper.setLogger(logger, 'verbose');
    }
  });

  Future<void> _releaseGlobalLogging() => _serializeGlobal(() async {
    final wasOwner = identical(_globalOwners.lastOrNull, this);
    _globalOwners.remove(this);
    if (!wasOwner) return;

    final replacement = _globalOwners.lastOrNull;
    await runVoiceSdkCleanup([
      if (Platform.isIOS || Platform.isMacOS)
        () async {
          final logger = replacement?._webRtcLogger;
          if (logger == null) {
            // flutter_webrtc retains the logger and does not accept null.
            // A process-lifetime silent logger safely absorbs late native
            // lines after the final capture owner leaves.
            await rtc.Helper.setLogger(_silentWebRtcLogger, 'none');
          } else {
            await rtc.Helper.setLogger(logger, 'verbose');
          }
        },
      () {
        if (replacement != null) {
          _enableLiveKitLogging?.call();
          return;
        }
        _enableLiveKitLogging = null;
        final restore = _restoreBaselineLiveKitLevel;
        _restoreBaselineLiveKitLevel = null;
        restore?.call();
      },
    ]);
  });

  static Future<void> _serializeGlobal(Future<void> Function() operation) {
    final current = _globalTail.then((_) => operation());
    _globalTail = current.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return current;
  }
}

/// Exposed for deterministic failure-injection tests; production uses it to
/// keep LiveKit and WebRTC verbose logging from being stranded on after stop.
@visibleForTesting
Future<void> runVoiceSdkCleanup(
  Iterable<FutureOr<void> Function()> operations,
) async {
  Object? firstError;
  StackTrace? firstStackTrace;
  for (final operation in operations) {
    try {
      await operation();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }
  if (firstError != null) {
    Error.throwWithStackTrace(firstError, firstStackTrace!);
  }
}

final class _VoiceWebRtcLogOutput extends native_logger.LogOutput {
  _VoiceWebRtcLogOutput(this.recorder);

  final VoiceDiagnosticsRecorder recorder;

  @override
  void output(native_logger.OutputEvent event) {
    recorder.recordRaw(
      'sdk.webrtc.log',
      component: 'webrtc_sdk',
      severity: _webRtcSeverity(event.level),
      message: event.origin.message.toString(),
      data: {
        'level': event.level.name,
        if (event.origin.error != null) 'error': event.origin.error.toString(),
        if (event.origin.stackTrace != null)
          'stackTrace': event.origin.stackTrace.toString(),
      },
    );
  }
}

DiagnosticSeverity _liveKitSeverity(String level) {
  final normalized = level.toUpperCase();
  if (normalized == 'SHOUT' || normalized == 'SEVERE') {
    return DiagnosticSeverity.error;
  }
  if (normalized == 'WARNING') return DiagnosticSeverity.warning;
  if (normalized == 'INFO' || normalized == 'CONFIG') {
    return DiagnosticSeverity.info;
  }
  return DiagnosticSeverity.debug;
}

DiagnosticSeverity _webRtcSeverity(native_logger.Level level) {
  if (level >= native_logger.Level.error) return DiagnosticSeverity.error;
  if (level >= native_logger.Level.warning) {
    return DiagnosticSeverity.warning;
  }
  if (level >= native_logger.Level.info) return DiagnosticSeverity.info;
  return DiagnosticSeverity.debug;
}
