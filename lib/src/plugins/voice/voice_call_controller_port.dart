// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

import 'voice_call_port.dart';
import 'voice_controller.dart';
import 'voice_plugin.dart';
import 'voice_room_view.dart';
import 'voice_shell_service.dart';

final class VoiceCallControllerPort extends ChangeNotifier
    implements VoiceCallPort {
  factory VoiceCallControllerPort({
    required VoiceController controller,
    required VoiceShellService shell,
  }) => VoiceCallControllerPort.controlled(
    runtime: controller,
    readState: () => _controllerState(controller),
    performAction: (action) => _performControllerAction(
      controller: controller,
      shell: shell,
      action: action,
    ),
  );

  @visibleForTesting
  VoiceCallControllerPort.controlled({
    required Listenable runtime,
    required VoiceCallPortState Function() readState,
    required FutureOr<void> Function(VoiceCallAction action) performAction,
  }) : _runtime = runtime,
       _readRuntimeState = readState,
       _performAction = performAction {
    _runtime.addListener(_runtimeChanged);
    _state = _readState();
  }

  final Listenable _runtime;
  final VoiceCallPortState Function() _readRuntimeState;
  final FutureOr<void> Function(VoiceCallAction action) _performAction;
  final Set<Future<void>> _actions = {};
  late VoiceCallPortState _state;
  Object? _actionRevision;
  Future<void>? _closeOperation;
  bool _closed = false;

  @override
  VoiceCallPortState get state => _state;

  @override
  void dispatch(VoiceCallAction action) {
    if (_closed || !_state.supported || _state.call == null) return;
    final revision = Object();
    _actionRevision = revision;
    late final Future<void> operation;
    operation = Future<void>.sync(() => _performAction(action))
        .then((_) {
          if (!_isCurrent(revision)) return;
          _state = _readState();
          notifyListeners();
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!_isCurrent(revision)) return;
          _state = VoiceCallPortState(
            supported: _state.supported,
            call: _state.call,
            failureMessage: _failureMessage(action, error),
          );
          notifyListeners();
        })
        .whenComplete(() => _actions.remove(operation));
    _actions.add(operation);
  }

  static Future<void> _performControllerAction({
    required VoiceController controller,
    required VoiceShellService shell,
    required VoiceCallAction action,
  }) async {
    final call = controller.call;
    if (call == null) return;
    switch (action) {
      case VoiceCallAction.openRoom:
        shell.openRoom(
          siteUrl: call.siteUrl,
          route: ContentRoute(
            id: VoicePlugin.routeId(call.room.id),
            title: call.room.name,
            icon: DIcons.microphoneLines,
            subtitle: call.siteName,
          ),
        );
      case VoiceCallAction.toggleMuted:
        await controller.setMuted(!call.muted);
      case VoiceCallAction.leave:
        await controller.leave();
    }
  }

  bool _isCurrent(Object revision) =>
      !_closed && identical(_actionRevision, revision);

  void _runtimeChanged() {
    if (_closed) return;
    _actionRevision = Object();
    _state = _readState();
    notifyListeners();
  }

  VoiceCallPortState _readState() {
    try {
      return _readRuntimeState();
    } catch (_) {
      return const VoiceCallPortState(
        supported: true,
        failureMessage: 'Voice calling is unavailable.',
      );
    }
  }

  static VoiceCallPortState _controllerState(VoiceController controller) {
    if (!controller.supportedPlatform) {
      return const VoiceCallPortState.unsupported();
    }
    final call = controller.call;
    if (call == null) return const VoiceCallPortState.idle();
    final localVideoTrack = call.media.localVideoTrack;
    return VoiceCallPortState(
      supported: true,
      call: VoiceCallPresentation(
        roomName: call.room.name,
        siteName: call.siteName,
        participantCount: call.room.participants.length,
        status: switch (call.status) {
          VoiceCallStatus.joining => VoiceCallPresentationStatus.joining,
          VoiceCallStatus.connected => VoiceCallPresentationStatus.connected,
          VoiceCallStatus.reconnecting =>
            VoiceCallPresentationStatus.reconnecting,
          VoiceCallStatus.leaving => VoiceCallPresentationStatus.leaving,
          VoiceCallStatus.failed => VoiceCallPresentationStatus.failed,
        },
        muted: call.muted,
        localVideoPreview: localVideoTrack == null
            ? null
            : VoiceVideoSurface(track: localVideoTrack),
        failureMessage: call.error,
      ),
    );
  }

  static String _failureMessage(VoiceCallAction action, Object error) {
    if (error is WriteException) return error.message;
    return switch (action) {
      VoiceCallAction.openRoom => "Couldn't open the voice room.",
      VoiceCallAction.toggleMuted => "Couldn't update the microphone.",
      VoiceCallAction.leave => "Couldn't leave the voice room.",
    };
  }

  @override
  Future<void> close() {
    final active = _closeOperation;
    if (active != null) return active;
    _closed = true;
    _actionRevision = Object();
    _runtime.removeListener(_runtimeChanged);
    final pending = List<Future<void>>.of(_actions);
    return _closeOperation = Future.wait(pending).then((_) {
      _actions.clear();
      dispose();
    });
  }
}
