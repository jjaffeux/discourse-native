// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';

import 'resenha_diagnostics.dart';

enum ResenhaSystemCallAction { mute, unmute, end }

abstract interface class ResenhaSystemCall {
  Stream<ResenhaSystemCallAction> get actions;
  Future<void> start({required String roomName, required String siteName});
  Future<void> connected();
  Future<void> failed();
  Future<void> setMuted(bool muted);
  Future<void> end();
  Future<void> dispose();
}

/// This deliberately exposes operations rather than the LiveKit singleton so
/// ownership and serialization stay in [NativeResenhaSystemCall].
abstract interface class ResenhaAudioSession {
  Future<void> prepare();
  Future<void> activate();
  Future<void> deactivate();
  Future<void> reset();
}

final class _LiveKitResenhaAudioSession implements ResenhaAudioSession {
  const _LiveKitResenhaAudioSession();

  @override
  Future<void> prepare() async {
    final audioManager = AudioManager.instance;
    await audioManager.setAudioSessionManagementMode(
      AudioSessionManagementMode.externalCallSystem,
    );
    await audioManager.setAudioSessionOptions(
      const AudioSessionOptions.communication(),
    );
    await audioManager.setEngineAvailability(AudioEngineAvailability.none);
  }

  @override
  Future<void> activate() => AudioManager.instance.setEngineAvailability(
    AudioEngineAvailability.defaultAvailability,
  );

  @override
  Future<void> deactivate() =>
      AudioManager.instance.setEngineAvailability(AudioEngineAvailability.none);

  @override
  Future<void> reset() async {
    final audioManager = AudioManager.instance;
    await audioManager.setEngineAvailability(AudioEngineAvailability.none);
    await audioManager.setAudioSessionManagementMode(
      AudioSessionManagementMode.automatic,
    );
  }
}

final class NativeResenhaSystemCall implements ResenhaSystemCall {
  NativeResenhaSystemCall({
    this.diagnostics = const NoopResenhaDiagnosticsRecorder(),
    @visibleForTesting bool installMethodCallHandlerForTesting = false,
    @visibleForTesting ResenhaAudioSession? audioSessionForTesting,
  }) : _handlesMethodCalls =
           Platform.isIOS || installMethodCallHandlerForTesting,
       _managesAudioSession = Platform.isIOS || audioSessionForTesting != null,
       _audioSession =
           audioSessionForTesting ?? const _LiveKitResenhaAudioSession() {
    _record(
      'callkit.initialized',
      data: {'platform': Platform.operatingSystem},
    );
    if (_handlesMethodCalls) {
      _claimMethodCallHandler();
    }
    if (_managesAudioSession) {
      _audioSessionOwner = this;
      _ready = _prepareAudioSessionSafely();
    } else {
      _ready = Future<void>.value();
    }
  }

  static const MethodChannel _channel = MethodChannel(
    'org.discourse.native/resenha_callkit',
  );
  static NativeResenhaSystemCall? _methodCallHandlerOwner;
  static NativeResenhaSystemCall? _audioSessionOwner;
  static Future<void> _audioSessionTail = Future<void>.value();
  final _actions = StreamController<ResenhaSystemCallAction>.broadcast();
  final ResenhaDiagnosticsRecorder diagnostics;
  final bool _handlesMethodCalls;
  final bool _managesAudioSession;
  final ResenhaAudioSession _audioSession;
  late final Future<void> _ready;
  Future<void>? _disposeOperation;
  Object? _readyError;
  StackTrace? _readyStackTrace;
  String? _correlationId;

  void _claimMethodCallHandler() {
    _methodCallHandlerOwner = this;
    _channel.setMethodCallHandler(_onOwnedMethodCall);
  }

  Future<void> _onOwnedMethodCall(MethodCall call) {
    if (!identical(_methodCallHandlerOwner, this)) {
      return Future<void>.value();
    }
    return _onMethodCall(call);
  }

  void _releaseMethodCallHandler() {
    if (!identical(_methodCallHandlerOwner, this)) return;
    _methodCallHandlerOwner = null;
    _channel.setMethodCallHandler(null);
  }

  void associateDiagnostics(String? correlationId) {
    _correlationId = correlationId;
  }

  void _record(
    String event, {
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    Map<String, Object?> data = const {},
  }) {
    try {
      diagnostics.record(
        event,
        component: 'callkit',
        severity: severity,
        correlationId: _correlationId,
        data: data,
      );
    } catch (_) {}
  }

  void _recordRaw(
    String event, {
    DiagnosticSeverity severity = DiagnosticSeverity.debug,
    String? message,
    Map<String, Object?> data = const {},
  }) {
    try {
      if (!diagnostics.captureEnabled) return;
      diagnostics.recordRaw(
        event,
        component: 'callkit',
        severity: severity,
        correlationId: _correlationId,
        message: message,
        data: data,
      );
    } catch (_) {}
  }

  Future<void> _prepareAudioSessionSafely() async {
    try {
      await _runOwnedAudioSessionOperation(_audioSession.prepare);
      _record('callkit.audio_session.prepared');
    } catch (error, stackTrace) {
      _readyError = error;
      _readyStackTrace = stackTrace;
      _record(
        'callkit.audio_session.prepare_failed',
        severity: DiagnosticSeverity.warning,
        data: {'errorType': error.runtimeType.toString()},
      );
      _recordRaw(
        'callkit.audio_session.prepare_failure_detail',
        severity: DiagnosticSeverity.warning,
        message: error.toString(),
        data: {'stackTrace': stackTrace.toString()},
      );
    }
  }

  Future<void> _awaitReady() async {
    await _ready;
    if (_readyError case final error?) {
      Error.throwWithStackTrace(error, _readyStackTrace ?? StackTrace.current);
    }
  }

  Future<void> _runOwnedAudioSessionOperation(
    Future<void> Function() operation,
  ) {
    final result = _audioSessionTail.then((_) async {
      if (!identical(_audioSessionOwner, this)) return;
      await operation();
    });
    _audioSessionTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  @override
  Stream<ResenhaSystemCallAction> get actions => _actions.stream;

  Future<void> _onMethodCall(MethodCall call) async {
    if (call.method == 'diagnostic') {
      _forwardNativeDiagnostic(call.arguments);
      return;
    }
    _record('callkit.action.received', data: {'method': call.method});
    if (call.method == 'audioActivated') {
      await _runOwnedAudioSessionOperation(_audioSession.activate);
      _record('callkit.audio.activated');
      return;
    }
    if (call.method == 'audioDeactivated') {
      await _runOwnedAudioSessionOperation(_audioSession.deactivate);
      _record('callkit.audio.deactivated');
      return;
    }
    final action = switch (call.method) {
      'mute' => ResenhaSystemCallAction.mute,
      'unmute' => ResenhaSystemCallAction.unmute,
      'end' => ResenhaSystemCallAction.end,
      _ => null,
    };
    if (action != null && !_actions.isClosed) {
      _actions.add(action);
      _record('callkit.action.emitted', data: {'action': action.name});
    }
  }

  void _forwardNativeDiagnostic(Object? arguments) {
    if (arguments is! Map) return;
    final event = arguments['event'];
    if (event is! String || event.isEmpty) return;
    final component = arguments['component'];
    final rawData = arguments['data'];
    final raw = <String, Object?>{};
    if (rawData is Map) {
      for (final entry in rawData.entries) {
        raw['${entry.key}'] = entry.value;
      }
    }
    final data = <String, Object?>{
      for (final entry in raw.entries)
        entry.key: ?_safeNativeDiagnosticValue(entry.key, entry.value),
    };
    try {
      diagnostics.record(
        event,
        component: component is String && component.isNotEmpty
            ? component
            : 'callkit.native',
        correlationId: _correlationId,
        data: data,
      );
      _recordRaw('$event.detail', data: raw);
    } catch (_) {}
  }

  Object? _safeNativeDiagnosticValue(String key, Object? value) {
    if (key == 'muted' && value is bool) return value;
    if (key == 'errorCode' && value is num) return value;
    if (key == 'action' &&
        value is String &&
        const {'start', 'mute', 'end', 'unknown'}.contains(value)) {
      return value;
    }
    if (key == 'reason' &&
        value is String &&
        const {
          'no_active_call',
          'already_in_state',
          'stale_call',
        }.contains(value)) {
      return value;
    }
    if (key == 'route' &&
        value is String &&
        const {
          'speaker',
          'receiver',
          'bluetooth',
          'headphones',
        }.contains(value)) {
      return value;
    }
    if (key == 'errorDomain' && value is String && value.length <= 128) {
      return value;
    }
    return null;
  }

  @visibleForTesting
  Future<void> handleNativeMethodCall(MethodCall call) => _onMethodCall(call);

  @visibleForTesting
  Future<void> get audioSessionReadyForTesting => _ready;

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (!Platform.isIOS) {
      _record('callkit.command.skipped', data: {'method': method});
      return;
    }
    _record('callkit.command.started', data: {'method': method});
    if (arguments != null) {
      _recordRaw(
        'callkit.command.arguments',
        data: {'method': method, 'arguments': arguments},
      );
    }
    try {
      await _awaitReady();
      await _channel.invokeMethod<void>(method, arguments);
      _record('callkit.command.completed', data: {'method': method});
    } catch (error, stackTrace) {
      _record(
        'callkit.command.failed',
        severity: DiagnosticSeverity.warning,
        data: {'method': method, 'errorType': error.runtimeType.toString()},
      );
      _recordRaw(
        'callkit.command.failure_detail',
        severity: DiagnosticSeverity.warning,
        message: error.toString(),
        data: {'method': method, 'stackTrace': stackTrace.toString()},
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> start({required String roomName, required String siteName}) =>
      _invoke('start', {'roomName': roomName, 'siteName': siteName});

  @override
  Future<void> connected() => _invoke('connected');

  @override
  Future<void> failed() => _invoke('failed');

  @override
  Future<void> setMuted(bool muted) => _invoke('setMuted', {'muted': muted});

  @override
  Future<void> end() => _invoke('end');

  @override
  Future<void> dispose() {
    final active = _disposeOperation;
    if (active != null) return active;
    if (_handlesMethodCalls) _releaseMethodCallHandler();
    return _disposeOperation = _dispose();
  }

  Future<void> _dispose() async {
    _record('callkit.dispose.started');
    Object? firstError;
    StackTrace? firstStackTrace;
    if (_managesAudioSession) {
      try {
        await _ready;
        if (_readyError == null) {
          await _runOwnedAudioSessionOperation(_audioSession.reset);
        }
      } catch (error, stackTrace) {
        firstError = error;
        firstStackTrace = stackTrace;
      } finally {
        if (identical(_audioSessionOwner, this)) {
          _audioSessionOwner = null;
        }
      }
    }
    try {
      await _actions.close();
    } catch (error, stackTrace) {
      if (firstError == null) {
        firstError = error;
        firstStackTrace = stackTrace;
      }
    }
    _record('callkit.dispose.completed');
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace ?? StackTrace.current);
    }
  }
}
