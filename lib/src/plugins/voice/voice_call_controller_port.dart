// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import 'voice_call_port.dart';

final class VoiceCallControllerPort extends ChangeNotifier
    implements VoiceCallPort {
  VoiceCallControllerPort({
    required Listenable runtime,
    required VoiceCallPortState Function() readState,
    required FutureOr<void> Function(VoiceCallAction action) performAction,
    Future<void> Function()? closeRuntime,
  }) : _runtime = runtime,
       _readRuntimeState = readState,
       _performAction = performAction,
       _closeRuntime = closeRuntime {
    _runtime.addListener(_runtimeChanged);
    _state = _readState();
  }

  final Listenable _runtime;
  final VoiceCallPortState Function() _readRuntimeState;
  final FutureOr<void> Function(VoiceCallAction action) _performAction;
  final Future<void> Function()? _closeRuntime;
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
            roomVisible: _state.roomVisible,
            usesMobileNavigation: _state.usesMobileNavigation,
            pictureInPictureActive: _state.pictureInPictureActive,
          );
          notifyListeners();
        })
        .whenComplete(() => _actions.remove(operation));
    _actions.add(operation);
  }

  bool _isCurrent(Object revision) =>
      !_closed && identical(_actionRevision, revision);

  void _runtimeChanged() {
    if (_closed) return;
    _actionRevision = Object();
    final next = _readState();
    if (identical(next, _state)) return;
    _state = next;
    notifyListeners();
  }

  VoiceCallPortState _readState() {
    try {
      return _readRuntimeState();
    } catch (_) {
      return VoiceCallPortState(
        supported: true,
        failureMessage: appL10n.voiceCallingIsUnavailable,
      );
    }
  }

  static String _failureMessage(VoiceCallAction action, Object error) {
    return failureText(
      error,
      fallback: switch (action) {
        VoiceCallAction.openRoom => appL10n.couldnTOpenTheVoiceRoom,
        VoiceCallAction.toggleMuted => appL10n.couldnTUpdateTheMicrophone,
        VoiceCallAction.leave => appL10n.couldnTLeaveTheVoiceRoom,
      },
    );
  }

  @override
  Future<void> close() {
    final active = _closeOperation;
    if (active != null) return active;
    _closed = true;
    _actionRevision = Object();
    _runtime.removeListener(_runtimeChanged);
    final pending = List<Future<void>>.of(_actions);
    return _closeOperation = Future.wait(pending).then((_) async {
      _actions.clear();
      await _closeRuntime?.call();
      dispose();
    });
  }
}
