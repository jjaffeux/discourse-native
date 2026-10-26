import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'voice_callkit.dart';
import 'voice_models.dart';
import 'voice_settings.dart';

typedef _VoiceRingSubscription = ({
  String channel,
  PluginLiveChannelSubscription subscription,
});

/// How long a call answered from the system's UI waits for the user to
/// confirm the peer-to-peer warning in the app: long enough to unlock the
/// device and open the app, short enough that a forgotten answer does not
/// hold a silent system call open.
const voiceAnswerConfirmationWindow = Duration(seconds: 60);

/// How the system's call UI names a caller: by username and site, which the
/// caller cannot choose freely, never by display name.
String voiceSystemCallerLabel(String siteUrl, String username) =>
    appL10n.voiceSystemCallerLabel(username, _siteHost(siteUrl));

String _systemCallerHandle(String siteUrl, String username) =>
    '$username@${_siteHost(siteUrl)}';

String _siteHost(String siteUrl) {
  final host = Uri.tryParse(siteUrl)?.host;
  return host == null || host.isEmpty ? siteUrl : host;
}

/// A resolved incoming call, still owned by the account and answer that
/// requested it. UI continuations must recheck [isCurrent] after awaiting or
/// invoking navigation callbacks before joining.
final class VoiceIncomingCallAcceptance {
  VoiceIncomingCallAcceptance._(
    this.siteUrl,
    this.room,
    this.call,
    this._isCurrent,
  );

  final String siteUrl;
  final VoiceRoom room;
  final VoiceIncomingCall call;
  final bool Function() _isCurrent;

  bool get isCurrent => _isCurrent();
}

sealed class _VoiceIncomingAdmission {}

enum _VoiceIncomingPresentation { pending, local, system }

final class _VoiceIncomingRing extends _VoiceIncomingAdmission {
  _VoiceIncomingRing(this.siteUrl, this.call);

  final String siteUrl;
  final VoiceIncomingCall call;
  Timer? expiry;
  _VoiceIncomingPresentation presentation = _VoiceIncomingPresentation.pending;

  bool get presented => presentation == _VoiceIncomingPresentation.system;
}

final class _VoiceIncomingAnswer extends _VoiceIncomingAdmission {
  _VoiceIncomingAnswer({
    required this.siteUrl,
    required this.call,
    required this.presented,
    required this.joinTail,
    required this.isCurrent,
  });

  final String siteUrl;
  final VoiceIncomingCall call;
  final bool presented;
  final Object? joinTail;
  final bool Function() isCurrent;

  /// A system answer waiting for the peer-to-peer warning to be confirmed in
  /// the app. The system call is up but nothing has joined.
  VoiceIncomingCallAcceptance? parked;
  Timer? confirmationDeadline;

  /// The Mute the user set on the answered system call while no call could
  /// take its controls yet.
  bool systemMuted = false;

  void unpark() {
    confirmationDeadline?.cancel();
    confirmationDeadline = null;
    parked = null;
  }
}

/// Account-scoped resolution and attribution remain with the room directory.
abstract interface class VoiceIncomingRooms {
  bool Function() captureAccount(String siteUrl);
  Future<VoiceRoom?> resolve(
    String siteUrl,
    String slug, {
    required bool Function() ifCurrent,
  });
  void rememberCaller(String siteUrl, VoiceIncomingCall call);
}

/// The media owner remains authoritative for both pending and active joins.
abstract interface class VoiceIncomingJoins {
  Object? get admissionIdentity;
  bool get hasCallOrPendingJoin;
  bool isInRoom(String siteUrl, int roomId);
  Future<void> join(
    VoiceIncomingCallAcceptance acceptance, {
    required String siteName,
  });
}

/// What a system answer does once its room is open: join under [siteName],
/// or, with [confirmInApp], wait for the peer-to-peer warning to be accepted
/// in the app first.
typedef VoiceSystemAnswerPlan = ({String siteName, bool confirmInApp});

abstract interface class VoiceIncomingNavigation {
  /// Opens the accepted room and reports privacy policy under its original lease.
  /// Returns null when a callback or asynchronous read retires the acceptance.
  FutureOr<VoiceSystemAnswerPlan?> prepare(
    VoiceIncomingCallAcceptance acceptance,
  );
}

/// Optional cancellation boundary for a Voice message-bus adapter whose
/// native teardown is asynchronous.
abstract interface class VoiceAwaitableSubscriptionTeardown {
  Future<void> cancelAndWait();
}

final class VoiceIncomingCalls {
  VoiceIncomingCalls({
    required this.rooms,
    required this.joins,
    required this.navigation,
    required this.systemCall,
    required this.onChanged,
    required this.clock,
    required this.timerFactory,
  });

  final VoiceIncomingRooms rooms;
  final VoiceIncomingJoins joins;
  final VoiceIncomingNavigation navigation;
  final VoiceSystemCall systemCall;
  final void Function() onChanged;
  final DateTime Function() clock;
  final Timer Function(Duration, void Function()) timerFactory;
  final Map<String, _VoiceRingSubscription> _rings = {};
  final Set<String> _handledRings = {};
  _VoiceIncomingAdmission? _incomingAdmission;
  bool _closed = false;
  Future<void>? _closeOperation;

  _VoiceIncomingRing? get _ringingCall => switch (_incomingAdmission) {
    _VoiceIncomingRing ring => ring,
    _ => null,
  };
  VoiceIncomingCall? get call => _ringingCall?.call;
  String? get siteUrl => _ringingCall?.siteUrl;
  bool get handledBySystem => _ringingCall?.presented ?? false;

  /// The system answer waiting for the peer-to-peer warning, while it is
  /// still owned by its account and no join has replaced it.
  VoiceIncomingCallAcceptance? get awaitingConfirmation =>
      switch (_incomingAdmission) {
        _VoiceIncomingAnswer(:final parked?) when parked.isCurrent => parked,
        _ => null,
      };

  /// Whether the user muted the answered system call before a call took it
  /// over. The system keeps showing Mute on, so that call joins muted.
  bool get answeredCallMuted => switch (_incomingAdmission) {
    _VoiceIncomingAnswer(:final systemMuted) => systemMuted,
    _ => false,
  };

  void answeredCallMuteChanged(bool muted) {
    if (_incomingAdmission case final _VoiceIncomingAnswer answer) {
      answer.systemMuted = muted;
    }
  }

  bool attach(
    String siteUrl,
    int? userId,
    PluginLiveChannelHandle tracker, {
    required VoiceNamespace namespace,
  }) {
    if (_closed || userId == null) return false;
    // A site's tracker can attach before its settings name the namespace, so
    // a later sync moves the ring to the channel the settings settle on.
    final channel = '${namespace.root}/call-ring/$userId';
    if (_rings[siteUrl]?.channel == channel) return false;
    _rings.remove(siteUrl)?.subscription.cancel();
    _rings[siteUrl] = (
      channel: channel,
      subscription: tracker.subscribe(
        channel,
        (data, _) => _onRingEvent(siteUrl, data),
      ),
    );
    return true;
  }

  void detach(String siteUrl) {
    _rings.remove(siteUrl)?.subscription.cancel();
    if (_ringingCall?.siteUrl == siteUrl) {
      _clearIncomingCall(tellSystem: VoiceIncomingCallEndReason.unanswered);
    }
  }

  /// Takes the ringing call: the room is resolved (and held) so the caller
  /// can open and join it. Joining through the invite ref credits the
  /// caller, the same as joining from the notification link.
  Future<VoiceIncomingCallAcceptance?> accept({bool fromSystem = false}) async {
    final answer = _takeIncomingCall();
    if (answer == null) return null;
    return _acceptIncomingCall(answer, fromSystem: fromSystem);
  }

  _VoiceIncomingAnswer? _takeIncomingCall() {
    final incoming = _ringingCall;
    if (_closed || incoming == null) return null;
    final accountIsCurrent = rooms.captureAccount(incoming.siteUrl);
    final joinTail = joins.admissionIdentity;
    late final _VoiceIncomingAnswer answer;
    answer = _VoiceIncomingAnswer(
      siteUrl: incoming.siteUrl,
      call: incoming.call,
      presented: incoming.presented,
      joinTail: joinTail,
      isCurrent: () =>
          identical(_incomingAdmission, answer) &&
          identical(joins.admissionIdentity, joinTail) &&
          !_closed &&
          accountIsCurrent(),
    );
    incoming.expiry?.cancel();
    _incomingAdmission = answer;
    return answer;
  }

  Future<VoiceIncomingCallAcceptance?> _acceptIncomingCall(
    _VoiceIncomingAnswer answer, {
    required bool fromSystem,
  }) async {
    if (!answer.isCurrent()) return null;
    if (answer.presented && !fromSystem) {
      // The system is still ringing; its call becomes the active one so the
      // join below does not place a second call.
      await _runHandled(systemCall.answerIncomingCall);
    }
    if (!answer.isCurrent()) return null;
    final room = await rooms.resolve(
      answer.siteUrl,
      answer.call.roomSlug,
      ifCurrent: answer.isCurrent,
    );
    if (room == null || !answer.isCurrent()) return null;
    rooms.rememberCaller(answer.siteUrl, answer.call);
    return VoiceIncomingCallAcceptance._(
      answer.siteUrl,
      room,
      answer.call,
      answer.isCurrent,
    );
  }

  void decline({bool fromSystem = false}) {
    final incoming = _ringingCall;
    if (incoming == null) return;
    final presented = incoming.presented;

    _clearIncomingCall();
    if (presented && !fromSystem) {
      _observe(systemCall.declineIncomingCall);
    }
    onChanged();
  }

  void _clearIncomingCall({VoiceIncomingCallEndReason? tellSystem}) {
    final incoming = _ringingCall;
    if (incoming == null) return;
    incoming.expiry?.cancel();
    _incomingAdmission = null;
    if (incoming.presented && tellSystem != null) {
      _observe(() => systemCall.endIncomingCall(tellSystem));
    }
  }

  void retireAnswer() {
    if (_incomingAdmission case final _VoiceIncomingAnswer answer) {
      final wasParked = answer.parked != null;
      answer.unpark();
      _incomingAdmission = null;
      if (wasParked && !_closed) onChanged();
    }
  }

  /// The user turned down the peer-to-peer warning (or hung up) for a parked
  /// system answer: the answered system call ends with nothing joined.
  void cancelAwaitingAnswer() {
    if (_incomingAdmission case final _VoiceIncomingAnswer answer
        when answer.parked != null) {
      _abandonParked(answer, systemCall.end);
      if (!_closed) onChanged();
    }
  }

  /// Drops a parked answer. Unless a join has since taken over the system
  /// call, that call has nothing behind it and [endSystemCall] ends it.
  void _abandonParked(
    _VoiceIncomingAnswer answer,
    Future<void> Function() endSystemCall,
  ) {
    answer.unpark();
    if (identical(_incomingAdmission, answer)) _incomingAdmission = null;
    if (!_closed && identical(joins.admissionIdentity, answer.joinTail)) {
      _observe(endSystemCall);
    }
  }

  void roomJoined(String siteUrl, int roomId) {
    if (_incomingAdmission case final _VoiceIncomingAnswer answer) {
      answer.unpark();
    }
    final incoming = _ringingCall;
    if (incoming?.siteUrl == siteUrl && incoming?.call.roomId == roomId) {
      _clearIncomingCall(
        tellSystem: VoiceIncomingCallEndReason.answeredElsewhere,
      );
    }
  }

  /// A ring the system may present too: the phone rings with the system
  /// ringtone and on the lock screen, and answering or declining there
  /// comes back as a system action. When the system declines to (no
  /// system call UI on this platform, a call already up, the ring already
  /// over), the app's own banner stays.
  Future<void> _presentIncomingCall(_VoiceIncomingRing incoming) async {
    final call = incoming.call;
    final username = call.caller.username;
    final presented = await _runHandledValue(
      () => systemCall.reportIncomingCall(
        callerName: voiceSystemCallerLabel(incoming.siteUrl, username),
        roomName: call.roomName,
        handle: _systemCallerHandle(incoming.siteUrl, username),
      ),

      fallback: false,
    );
    if (_closed) return;
    if (!identical(_incomingAdmission, incoming)) {
      if (presented) {
        _observe(
          () =>
              systemCall.endIncomingCall(VoiceIncomingCallEndReason.unanswered),
        );
      }
      return;
    }

    incoming.presentation = presented
        ? _VoiceIncomingPresentation.system
        : _VoiceIncomingPresentation.local;
    if (presented) {
      onChanged();
    }
  }

  /// The user answered from the system's call UI. There is no app surface
  /// to ask anything on (the app may be behind the lock screen), so when the
  /// site's peer-to-peer warning applies the answer parks instead of joining:
  /// the room opens, and the app asks before anything connects. An answer
  /// left unconfirmed ends the system call after
  /// [voiceAnswerConfirmationWindow].
  Future<void> answerFromSystem() async {
    // CallKit can echo a local answer or deliver its action more than once.
    // Once taken, that answer alone owns resolution and failure handling.
    if (_closed ||
        (_ringingCall == null &&
            (_incomingAdmission is _VoiceIncomingAnswer ||
                joins.hasCallOrPendingJoin))) {
      return;
    }
    final answer = _takeIncomingCall();
    final accepted = answer == null
        ? null
        : await _acceptIncomingCall(answer, fromSystem: true);
    bool isCurrent() =>
        answer?.isCurrent() ??
        (!_closed && _incomingAdmission == null && !joins.hasCallOrPendingJoin);
    if (!isCurrent()) return;
    if (accepted == null) {
      if (!isCurrent()) return;
      await _runHandled(systemCall.failed);
      return;
    }
    final preparation = navigation.prepare(accepted);
    final plan = preparation is Future<VoiceSystemAnswerPlan?>
        ? await preparation
        : preparation;
    if (plan == null || !isCurrent()) return;
    if (plan.confirmInApp && answer != null) {
      _park(answer, accepted);
      return;
    }
    await joins.join(accepted, siteName: plan.siteName);
  }

  void _park(
    _VoiceIncomingAnswer answer,
    VoiceIncomingCallAcceptance accepted,
  ) {
    answer.parked = accepted;
    answer.confirmationDeadline = timerFactory(
      voiceAnswerConfirmationWindow,
      () {
        if (identical(_incomingAdmission, answer) && answer.parked != null) {
          _abandonParked(answer, systemCall.failed);
          if (!_closed) onChanged();
        }
      },
    );
    onChanged();
  }

  void _onRingEvent(String siteUrl, Object? data) {
    if (_closed || data is! Map<String, dynamic>) return;
    final call = VoiceIncomingCall.fromJson(data);
    if (call == null) return;
    final now = clock();
    final remaining = call.remainingAt(now);

    if (remaining <= Duration.zero) return;
    if (joins.isInRoom(siteUrl, call.roomId)) {
      return;
    }
    if (!_handledRings.add(call.key)) return;
    if (_handledRings.length > 50) _handledRings.remove(_handledRings.first);
    if (_incomingAdmission case final _VoiceIncomingAnswer answer
        when answer.parked != null) {
      _abandonParked(answer, systemCall.failed);
    }
    retireAnswer();
    _clearIncomingCall(tellSystem: VoiceIncomingCallEndReason.unanswered);
    final incoming = _VoiceIncomingRing(siteUrl, call);
    _incomingAdmission = incoming;
    incoming.expiry = timerFactory(remaining, () {
      if (!identical(_incomingAdmission, incoming)) return;

      _clearIncomingCall(tellSystem: VoiceIncomingCallEndReason.unanswered);
      if (!_closed) onChanged();
    });
    onChanged();
    unawaited(_presentIncomingCall(incoming));
  }

  Future<void> close() {
    if (_closeOperation case final operation?) return operation;
    final completion = Completer<void>();
    _closeOperation = completion.future;
    _closed = true;
    final subscriptions = [for (final ring in _rings.values) ring.subscription];
    _rings.clear();
    retireAnswer();
    _clearIncomingCall(tellSystem: VoiceIncomingCallEndReason.unanswered);
    unawaited(
      Future.wait([
        for (final subscription in subscriptions)
          _cancelSubscription(subscription),
      ]).then((_) => completion.complete(), onError: completion.completeError),
    );
    return completion.future;
  }

  Future<void> _cancelSubscription(
    PluginLiveChannelSubscription subscription,
  ) => _runHandled(() async {
    if (subscription case final VoiceAwaitableSubscriptionTeardown value) {
      await value.cancelAndWait();
    } else {
      subscription.cancel();
    }
  });

  void _observe(Future<void> Function() action) =>
      unawaited(_runHandled(action));

  Future<void> _runHandled(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  Future<T> _runHandledValue<T>(
    Future<T> Function() action, {
    required T fallback,
  }) async {
    try {
      return await action();
    } catch (_) {
      return fallback;
    }
  }
}
