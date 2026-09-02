// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:discourse_native/src/plugins/voice/voice_call_port.dart';
import 'package:flutter/foundation.dart';

final class FakeVoiceCallPort extends ChangeNotifier implements VoiceCallPort {
  FakeVoiceCallPort({
    VoiceCallPortState state = const VoiceCallPortState.idle(),
    this.onDispatch,
  }) : _state = state;

  final Future<void> Function(VoiceCallAction action)? onDispatch;
  final List<VoiceCallAction> actions = [];
  VoiceCallPortState _state;
  bool _closed = false;
  int closeCalls = 0;
  int completedActions = 0;

  @override
  VoiceCallPortState get state => _state;

  void replaceState(VoiceCallPortState state) {
    if (_closed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispatch(VoiceCallAction action) {
    if (_closed) return;
    actions.add(action);
    final handler = onDispatch;
    if (handler == null) return;
    unawaited(
      handler(action).then<void>(
        (_) {
          completedActions++;
          if (!_closed) notifyListeners();
        },
        onError: (Object _, StackTrace _) {
          completedActions++;
          if (!_closed) notifyListeners();
        },
      ),
    );
  }

  @override
  Future<void> close() async {
    closeCalls++;
    if (_closed) return;
    _closed = true;
    dispose();
  }
}
