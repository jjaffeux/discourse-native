// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';

/// `answer` and `decline` are the user acting on a ring the system
/// presented; the others concern the active call.
enum VoiceSystemCallAction { mute, unmute, end, answer, decline }

/// Why a ring the system was presenting ended without the user acting on
/// it there.
enum VoiceIncomingCallEndReason {
  /// The ring ran out.
  unanswered,

  /// The user joined the call some other way (a notification link, the
  /// app's own banner) while the system was still ringing.
  answeredElsewhere;

  String get wireName => switch (this) {
    VoiceIncomingCallEndReason.unanswered => 'unanswered',
    VoiceIncomingCallEndReason.answeredElsewhere => 'answered_elsewhere',
  };
}

abstract interface class VoiceSystemCall {
  Stream<VoiceSystemCallAction> get actions;
  Future<void> start({required String roomName, required String siteName});
  Future<void> connected();
  Future<void> failed();
  Future<void> setMuted(bool muted);
  Future<void> end();

  /// Asks the system to ring for a direct call. Answers whether it will:
  /// false on platforms without a system call UI, while another call is
  /// up, or when the system refused, so the caller shows its own ring.
  Future<bool> reportIncomingCall({
    required String callerName,
    required String roomName,
    required String handle,
  });

  /// The user answered the ring from the app's own UI while the system was
  /// presenting it; the system call becomes the active one.
  Future<void> answerIncomingCall();

  /// The user declined from the app's own UI.
  Future<void> declineIncomingCall();

  /// The ring ended without the user acting on the system's presentation.
  Future<void> endIncomingCall(VoiceIncomingCallEndReason reason);

  Future<void> dispose();
}

/// This deliberately exposes operations rather than the LiveKit singleton so
/// ownership and serialization stay in [NativeVoiceSystemCall].
abstract interface class VoiceAudioSession {
  Future<void> prepare();
  Future<void> activate();
  Future<void> deactivate();
  Future<void> reset();
}

final class _LiveKitVoiceAudioSession implements VoiceAudioSession {
  const _LiveKitVoiceAudioSession();

  @override
  Future<void> prepare() async {
    final audioManager = AudioManager.instance;
    await audioManager.setAudioSessionManagementMode(
      AudioSessionManagementMode.externalCallSystem,
    );
    await audioManager.setAudioSessionOptions(
      const AudioSessionOptions.communication(),
    );
    // The engine gate requires WebRTC's native audio device, but does not
    // trigger its lazy initialization. Create it before the first call.
    await LiveKitClient.initialize();
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

final class NativeVoiceSystemCall implements VoiceSystemCall {
  NativeVoiceSystemCall({
    @visibleForTesting bool installMethodCallHandlerForTesting = false,
    @visibleForTesting VoiceAudioSession? audioSessionForTesting,
    @visibleForTesting bool invokeNativeCommandsForTesting = false,
  }) : _handlesMethodCalls =
           Platform.isIOS ||
           installMethodCallHandlerForTesting ||
           invokeNativeCommandsForTesting,
       _invokesNativeCommands =
           Platform.isIOS || invokeNativeCommandsForTesting,
       _managesAudioSession =
           Platform.isIOS ||
           invokeNativeCommandsForTesting ||
           audioSessionForTesting != null,
       _audioSession =
           audioSessionForTesting ?? const _LiveKitVoiceAudioSession() {
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
    'org.discourse.native/voice_callkit',
  );
  static NativeVoiceSystemCall? _methodCallHandlerOwner;
  static NativeVoiceSystemCall? _audioSessionOwner;
  static Future<void> _audioSessionTail = Future<void>.value();
  final _actions = StreamController<VoiceSystemCallAction>.broadcast();

  final bool _handlesMethodCalls;
  final bool _invokesNativeCommands;
  final bool _managesAudioSession;
  final VoiceAudioSession _audioSession;
  late final Future<void> _ready;
  Future<void>? _disposeOperation;
  Object? _readyError;
  StackTrace? _readyStackTrace;

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

  Future<void> _prepareAudioSessionSafely() async {
    try {
      await _runOwnedAudioSessionOperation(_audioSession.prepare);
    } catch (error, stackTrace) {
      _readyError = error;
      _readyStackTrace = stackTrace;
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
  Stream<VoiceSystemCallAction> get actions => _actions.stream;

  Future<void> _onMethodCall(MethodCall call) async {
    if (call.method == 'audioActivated') {
      await _runOwnedAudioSessionOperation(_audioSession.activate);

      return;
    }
    if (call.method == 'audioDeactivated') {
      await _runOwnedAudioSessionOperation(_audioSession.deactivate);

      return;
    }
    final action = switch (call.method) {
      'mute' => VoiceSystemCallAction.mute,
      'unmute' => VoiceSystemCallAction.unmute,
      'end' => VoiceSystemCallAction.end,
      'answer' => VoiceSystemCallAction.answer,
      'decline' => VoiceSystemCallAction.decline,
      _ => null,
    };
    if (action != null && !_actions.isClosed) {
      _actions.add(action);
    }
  }

  @visibleForTesting
  Future<void> handleNativeMethodCall(MethodCall call) => _onMethodCall(call);

  @visibleForTesting
  Future<void> get audioSessionReadyForTesting => _ready;

  // Both boundaries are shared across instances, including while work is held
  // on readiness or a native response.
  bool get _ownsNativeCall =>
      _disposeOperation == null &&
      identical(_methodCallHandlerOwner, this) &&
      (!_managesAudioSession || identical(_audioSessionOwner, this));

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (!_invokesNativeCommands || !_ownsNativeCall) {
      return;
    }

    try {
      await _awaitReady();
      if (!_ownsNativeCall) return;
      await _channel.invokeMethod<void>(method, arguments);
      if (!_ownsNativeCall) return;
    } catch (error, stackTrace) {
      if (!_ownsNativeCall) return;

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
  Future<bool> reportIncomingCall({
    required String callerName,
    required String roomName,
    required String handle,
  }) async {
    if (!_invokesNativeCommands || !_ownsNativeCall) {
      return false;
    }

    try {
      await _awaitReady();
      if (!_ownsNativeCall) return false;
      final presented = await _channel.invokeMethod<bool>(
        'reportIncomingCall',
        {'callerName': callerName, 'roomName': roomName, 'handle': handle},
      );
      if (!_ownsNativeCall) return false;

      return presented == true;
    } catch (error) {
      if (!_ownsNativeCall) return false;
      // Not presenting is a fallback, not a failure: the app rings itself.

      return false;
    }
  }

  @override
  Future<void> answerIncomingCall() => _invoke('answerIncomingCall');

  @override
  Future<void> declineIncomingCall() => _invoke('declineIncomingCall');

  @override
  Future<void> endIncomingCall(VoiceIncomingCallEndReason reason) =>
      _invoke('endIncomingCall', {'reason': reason.wireName});

  @override
  Future<void> dispose() {
    final active = _disposeOperation;
    if (active != null) return active;
    if (_handlesMethodCalls) _releaseMethodCallHandler();
    return _disposeOperation = _dispose();
  }

  Future<void> _dispose() async {
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

    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace ?? StackTrace.current);
    }
  }
}
