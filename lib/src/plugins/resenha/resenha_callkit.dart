// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';

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

final class NativeResenhaSystemCall implements ResenhaSystemCall {
  NativeResenhaSystemCall() {
    if (Platform.isIOS) {
      _channel.setMethodCallHandler(_onMethodCall);
      unawaited(
        AudioManager.instance
            .setAudioSessionManagementMode(
              AudioSessionManagementMode.externalCallSystem,
            )
            .then(
              (_) => AudioManager.instance.setEngineAvailability(
                AudioEngineAvailability.none,
              ),
            ),
      );
    }
  }

  static const MethodChannel _channel = MethodChannel(
    'org.discourse.native/resenha_callkit',
  );
  final _actions = StreamController<ResenhaSystemCallAction>.broadcast();

  @override
  Stream<ResenhaSystemCallAction> get actions => _actions.stream;

  Future<void> _onMethodCall(MethodCall call) async {
    if (call.method == 'audioActivated') {
      await AudioManager.instance.setEngineAvailability(
        AudioEngineAvailability.defaultAvailability,
      );
      return;
    }
    if (call.method == 'audioDeactivated') {
      await AudioManager.instance.setEngineAvailability(
        AudioEngineAvailability.none,
      );
      return;
    }
    final action = switch (call.method) {
      'mute' => ResenhaSystemCallAction.mute,
      'unmute' => ResenhaSystemCallAction.unmute,
      'end' => ResenhaSystemCallAction.end,
      _ => null,
    };
    if (action != null && !_actions.isClosed) _actions.add(action);
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod<void>(method, arguments);
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
  Future<void> dispose() async {
    if (Platform.isIOS) _channel.setMethodCallHandler(null);
    if (Platform.isIOS) {
      await AudioManager.instance.setEngineAvailability(
        AudioEngineAvailability.none,
      );
      await AudioManager.instance.setAudioSessionManagementMode(
        AudioSessionManagementMode.automatic,
      );
    }
    await _actions.close();
  }
}
