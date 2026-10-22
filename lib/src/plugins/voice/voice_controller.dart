// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import '../chat/chat_contract.dart';
import 'voice_agents.dart';
import 'voice_api.dart';
import 'voice_callkit.dart';
import 'voice_diagnostics.dart';
import 'voice_idle.dart';
import 'voice_media.dart';
import 'voice_models.dart';
import 'voice_preferences.dart';
import 'voice_settings.dart';
import 'voice_signaling.dart';
import 'voice_video_handle.dart';

part 'voice_call_manager.dart';
part 'voice_call_session.dart';
part 'voice_chat_association.dart';
part 'voice_device_preferences.dart';
part 'voice_room_directory.dart';

enum VoiceCallStatus { joining, connected, reconnecting, leaving, failed }

/// A created direct call, still owned by the account that requested it.
/// UI continuations must recheck [isCurrent] through navigation and privacy
/// confirmation before joining.
final class VoiceOutgoingCall {
  VoiceOutgoingCall._(this.siteUrl, this.room, this._isCurrent);

  final String siteUrl;
  final VoiceRoom room;
  final bool Function() _isCurrent;

  bool get isCurrent => _isCurrent();
}

/// A resolved incoming call, still owned by the account and answer that
/// requested it. UI continuations must recheck [isCurrent] after awaiting or
/// invoking navigation callbacks before joining.
final class VoiceIncomingCallAcceptance {
  VoiceIncomingCallAcceptance._(this.siteUrl, this.room, this._isCurrent);

  final String siteUrl;
  final VoiceRoom room;
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
    required this.isCurrent,
  });

  final String siteUrl;
  final VoiceIncomingCall call;
  final bool presented;
  final bool Function() isCurrent;
}

enum _VoiceLeaveReason {
  user,
  roomToggle,
  roomSwitch,
  roomDestroyed,
  kicked,
  rosterRemoval,
  credentialsMissing,
  sessionExpired,
  idleDisconnect,
  systemAction,
  accountRemoval,
  sessionClose,
}

final class _VoiceDiagnosticFailure implements Exception {
  const _VoiceDiagnosticFailure({
    required this.operation,
    required this.errorType,
  });

  final String operation;
  final String errorType;

  @override
  String toString() => appL10n.voiceOperationFailed(
    (operation).toString(),
    (errorType).toString(),
  );
}

final class _VoiceCameraRestore {
  bool again = false;
}

String _joinFailureMessage(Object error, VoiceRoom room) {
  if (error is WriteException) return error.message;
  if (error is VoiceMicrophoneException) {
    return switch (error.kind) {
      VoiceMicrophoneFailureKind.permissionDenied =>
        appL10n
            .microphoneAccessIsBlockedAllowMicrophoneAccessInYourSystemSettings,
      VoiceMicrophoneFailureKind.unavailable =>
        appL10n.weCouldnTAccessYourMicrophoneCheckThatItIsConnected,
    };
  }
  return appL10n.couldnTJoin((room.name).toString());
}

String _voiceSignalingDiagnosticType(Object? value) => switch (value) {
  'offer' => 'offer',
  'answer' => 'answer',
  'candidate' => 'candidate',
  null => 'batch',
  _ => 'unknown',
};

String _voiceDirectoryDiagnosticType(Object? value) => switch (value) {
  'created' => 'created',
  'updated' => 'updated',
  'destroyed' => 'destroyed',
  _ => 'unknown',
};

/// Message bus positions only move forward: a cursor served or delivered
/// behind the one already held is a replay, not news.
int? _newerCursor(int? current, int? incoming) {
  if (incoming == null) return current;
  if (current == null || incoming > current) return incoming;
  return current;
}

@immutable
class VoiceChatSnapshot {
  const VoiceChatSnapshot({
    required this.session,
    this.messages = const [],
    this.loading = false,
    this.sending = false,
    this.canLoadMorePast = false,
    this.error,
  });

  final VoiceChatSession session;
  final List<ChatMessage> messages;
  final bool loading;
  final bool sending;
  final bool canLoadMorePast;
  final String? error;
}

@immutable
class VoiceCallSnapshot {
  const VoiceCallSnapshot({
    required this.siteUrl,
    required this.siteName,
    required this.room,
    required this.status,
    required this.media,
    this.muted = false,
    this.deafened = false,
    this.cameraEnabled = false,
    this.screenSharing = false,
    this.error,
  });

  final String siteUrl;
  final String siteName;
  final VoiceRoom room;
  final VoiceCallStatus status;
  final VoiceMediaSession media;
  final bool muted;
  final bool deafened;
  final bool cameraEnabled;
  final bool screenSharing;
  final String? error;

  VoiceCallSnapshot copyWith({
    VoiceRoom? room,
    VoiceCallStatus? status,
    bool? muted,
    bool? deafened,
    bool? cameraEnabled,
    bool? screenSharing,
    String? error,
    bool clearError = false,
  }) => VoiceCallSnapshot(
    siteUrl: siteUrl,
    siteName: siteName,
    room: room ?? this.room,
    status: status ?? this.status,
    media: media,
    muted: muted ?? this.muted,
    deafened: deafened ?? this.deafened,
    cameraEnabled: cameraEnabled ?? this.cameraEnabled,
    screenSharing: screenSharing ?? this.screenSharing,
    error: clearError ? null : error ?? this.error,
  );
}

/// A transient, user-facing message about a room the user is in or watching:
/// a role change, a dismissed request to speak, a recording starting. Shown
/// once and never persisted.
@immutable
final class VoiceNotice {
  const VoiceNotice(this.message);

  final String message;
}

typedef VoiceTrackerLookup = PluginLiveChannelHandle? Function(String siteUrl);
typedef VoiceSiteFlagReader = bool Function(String siteUrl);
typedef VoiceSiteNameLookup = String? Function(String siteUrl);
typedef VoiceIncomingCallAnswered =
    void Function(String siteUrl, VoiceRoom room);
typedef VoiceUserIdLookup = int? Function(String siteUrl);
typedef VoiceCapabilityResolver = Future<bool?> Function(String siteUrl);

/// The media state the controller's listeners read through
/// [VoiceCallSnapshot.media] rather than from the snapshot itself: the call
/// port's local preview, and the connection and screen share the call's
/// status is derived from. Speaking and remote tracks are not in it;
/// participant tiles listen to the media session for those.
typedef _VoiceMediaView = ({
  VoiceMediaConnectionState connectionState,
  Object? connectionFailure,
  bool screenSharing,
  VoiceVideoHandle? localVideoTrack,
});

/// Optional cancellation boundary for a Voice message-bus adapter whose
/// native teardown is asynchronous.
abstract interface class VoiceAwaitableSubscriptionTeardown {
  Future<void> cancelAndWait();
}

Future<bool?> _unknownVoiceCapability(String _) async => null;

/// App-global Voice state. Directories belong to sites; media belongs to the
/// one call, which deliberately survives selection of another site.
final class VoiceController extends ChangeNotifier {
  VoiceController({
    required this.api,
    required this.chatConversations,
    required PluginRequestHost requests,
    required this.trackerFor,
    required VoiceUserIdLookup userIdFor,
    required VoidCallback onCallSiteChanged,
    VoiceCapabilityResolver? capabilityEnabledFor,
    this.mediaFactory = const NativeVoiceMediaFactory(),
    VoiceSystemCall? systemCall,
    PluginDiagnosticsReporter reporter = const PluginDiagnosticsReporter.noop(),
    VoiceDiagnosticsRecorder? diagnostics,
    VoicePreferences? preferences,
    VoiceIdleThresholdsLookup? idleThresholdsFor,
    int Function(String siteUrl)? videoMaxPublishersFor,
    Duration Function()? idleClock,
    VoiceIdleTimerFactory? timerFactory,
    DateTime Function()? clock,
    VoiceSiteNameLookup? siteNameFor,
    VoiceSiteFlagReader? meshPrivacyWarningEnabledFor,
    VoiceIncomingCallAnswered? onIncomingCallAnswered,
    this.heartbeatInterval = const Duration(seconds: 10),
    this.signalBatchDelay = const Duration(milliseconds: 200),
  }) : _requests = requests,
       _idleThresholdsFor = idleThresholdsFor ?? _defaultIdleThresholds,
       _videoMaxPublishersFor =
           videoMaxPublishersFor ?? _defaultVideoMaxPublishers,
       _timerFactory = timerFactory ?? Timer.new,
       _idleClock = idleClock,
       _clock = clock ?? DateTime.now,
       _siteNameFor = siteNameFor,
       _meshPrivacyWarningEnabledFor = meshPrivacyWarningEnabledFor,
       _onIncomingCallAnswered = onIncomingCallAnswered,
       _userIdFor = userIdFor,
       _onCallSiteChanged = onCallSiteChanged,
       _capabilityEnabledFor = capabilityEnabledFor ?? _unknownVoiceCapability,
       _reporter = reporter,
       diagnostics = diagnostics ?? const NoopVoiceDiagnosticsRecorder(),
       systemCall =
           systemCall ??
           NativeVoiceSystemCall(
             diagnostics: diagnostics ?? const NoopVoiceDiagnosticsRecorder(),
           ),
       _preferences = preferences ?? const SharedPreferencesVoicePreferences() {
    _systemActions = this.systemCall.actions.listen(_onSystemAction);
    _devicePreferencesLoaded = _restoreDevicePreferences();
    unawaited(_restoreAutoStatusPreference());
  }

  static VoiceIdleThresholds _defaultIdleThresholds(String _) =>
      voiceIdleThresholds(const VoiceClientConfig());

  static int _defaultVideoMaxPublishers(String _) =>
      const VoiceClientConfig().videoMaxPublishers;

  final VoiceApi api;
  final ChatConversationCapability chatConversations;
  final PluginRequestHost _requests;
  final VoiceTrackerLookup trackerFor;
  final VoiceUserIdLookup _userIdFor;
  final VoiceCapabilityResolver _capabilityEnabledFor;
  final VoidCallback _onCallSiteChanged;
  final VoiceMediaFactory mediaFactory;
  final VoiceSystemCall systemCall;
  final PluginDiagnosticsReporter _reporter;
  final VoiceDiagnosticsRecorder diagnostics;
  final VoicePreferences _preferences;
  final VoiceIdleThresholdsLookup _idleThresholdsFor;
  final int Function(String siteUrl) _videoMaxPublishersFor;
  final VoiceIdleTimerFactory _timerFactory;
  final DateTime Function() _clock;
  final VoiceSiteNameLookup? _siteNameFor;
  final VoiceSiteFlagReader? _meshPrivacyWarningEnabledFor;
  final VoiceIncomingCallAnswered? _onIncomingCallAnswered;
  final Duration Function()? _idleClock;
  late final _VoiceCallManager _calls = _VoiceCallManager(this);
  final Map<String, PluginLiveChannelSubscription> _ringSubscriptions = {};
  final Set<String> _handledRings = {};
  _VoiceIncomingAdmission? _incomingAdmission;
  _VoiceIncomingRing? get _ringingCall => switch (_incomingAdmission) {
    _VoiceIncomingRing ring => ring,
    _ => null,
  };
  final Duration heartbeatInterval;
  final Duration signalBatchDelay;
  // Cancelled and awaited by the idempotent close lifecycle below.
  // ignore: cancel_subscriptions
  late final StreamSubscription<VoiceSystemCallAction> _systemActions;

  final Map<String, _VoiceRoomDirectory> _roomDirectories = {};
  final Set<_VoiceRoomDirectory> _closingDirectories = {};
  final Map<String, PluginLiveChannelHandle> _attachedTrackers = {};
  final Map<(String, int), _VoiceChatAssociation> _chats = {};
  final Map<String, Object> _siteSessions = {};
  final ChangeNotifier _roomListChanges = ChangeNotifier();
  Map<String, VoiceDirectory> _publishedDirectories = {};
  Set<(String, int)> _publishedJoining = {};

  final Map<String, _VoiceInviteRef> _pendingInviteRefs = {};
  final Map<String, int> _roomVideoWatchers = {};
  final StreamController<VoiceNotice> _notices =
      StreamController<VoiceNotice>.broadcast();
  Future<void>? _closeOperation;
  VoiceCallSnapshot? get _call => _calls.current?._call;
  bool _disposed = false;
  final _devicePreferences = _VoiceDevicePreferences();
  String? get _audioInputDeviceId => _devicePreferences.audioInput.value;
  String? get _audioOutputDeviceId => _devicePreferences.audioOutput.value;
  String? get _cameraDeviceId => _devicePreferences.camera.value.deviceId;
  VoiceCameraFacing? get _cameraFacing =>
      _devicePreferences.camera.value.facing;
  bool get _pushToTalkEnabled => _devicePreferences.pushToTalk.value;
  bool get _autoStatusEnabled => _devicePreferences.autoStatus.value;
  bool _foreground = true;
  late final Future<void> _devicePreferencesLoaded;
  final Map<(String, int), Future<bool>> _cameraPreferences = {};

  VoiceCallSnapshot? get call => _call;

  void _notifyCallChanged() {
    _notifyRoomListChanged();
    if (!_disposed) notifyListeners();
  }

  bool isJoining(String siteUrl, int roomId) =>
      !_disposed && _calls.isJoining(siteUrl, roomId);

  bool get cameraStarting => _calls.current?.cameraStarting ?? false;
  String? get activeSiteUrl => _call?.siteUrl;
  bool get supportedPlatform =>
      Platform.isIOS || Platform.isMacOS || Platform.isLinux;
  String? get audioInputDeviceId => _audioInputDeviceId;
  String? get audioOutputDeviceId => _audioOutputDeviceId;
  String? get cameraDeviceId => _cameraFacing == null ? _cameraDeviceId : null;
  bool get pushToTalkEnabled => _pushToTalkEnabled;

  /// Whether joining a room sets the user's status to it (when the site
  /// allows it). A per-device choice, like the web client's.
  bool get autoStatusEnabled => _autoStatusEnabled;

  Future<void> setAutoStatusEnabled(bool enabled) async {
    if (_disposed) return;
    _devicePreferences.autoStatus.select(enabled);
    notifyListeners();
    try {
      await _preferences.writeAutoStatusEnabled(enabled);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'voice.preferences.autoStatus');
    }
  }

  /// Whether this device has accepted the peer-to-peer IP exposure warning.
  /// A failed read answers false: the warning is the safe side.
  Future<bool> meshPrivacyAcknowledged() async {
    try {
      return await _preferences.readMeshPrivacyAcknowledged();
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'voice.preferences.meshPrivacy');
      return false;
    }
  }

  Future<void> acknowledgeMeshPrivacy() async {
    try {
      await _preferences.writeMeshPrivacyAcknowledged(true);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'voice.preferences.meshPrivacy');
    }
  }

  int? currentUserIdFor(String siteUrl) => _userIdFor(siteUrl);

  /// Captures the account lifetime for a continuation across Voice operations.
  /// Recheck after awaits and callbacks that can retire or replace the account.
  bool Function() captureSiteSession(String siteUrl) {
    final siteSession = _siteSession(siteUrl);
    final lease = _requests.capture(siteUrl);
    return () => _isCurrentSiteSession(siteUrl, siteSession) && lease.isCurrent;
  }

  Stream<VoiceNotice> get notices => _notices.stream;

  /// The direct call ringing this user right now, if any. Cleared when it
  /// is answered, declined, or has run out.
  VoiceIncomingCall? get incomingCall => _ringingCall?.call;

  String? get incomingCallSiteUrl => _ringingCall?.siteUrl;

  /// The system (CallKit) is ringing for [incomingCall], so the app's own
  /// banner would only duplicate it; the answer arrives as a system action.
  bool get incomingCallHandledBySystem => _ringingCall?.presented ?? false;

  /// Starts a direct call to [username] on [siteUrl]. The server answers
  /// with the ephemeral call room, which is held beside the directory so
  /// its roster and signals arrive; the caller then joins it like any room.
  /// Returns null if the requesting account retires before completion.
  /// Failures surface to the caller: the server explains a refusal (a user
  /// who cannot be called, too many calls) in its own words.
  Future<VoiceOutgoingCall?> callUser(String siteUrl, String username) async {
    final isCurrent = captureSiteSession(siteUrl);
    final credentials = await _requestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    if (!isCurrent()) return null;
    if (credentials == null) {
      throw const WriteException(WriteFailure.forbidden);
    }
    final room = await _reporter.runOperation(
      'voice.call',
      () => credentials.run(
        () => api.callUser(
          siteUrl: siteUrl,
          apiKey: credentials.apiKey!,
          username: username,
          clientId: credentials.clientId,
        ),
      ),
    );
    if (!isCurrent()) return null;
    _record('call.direct.started', data: {..._roomDiagnosticData(room)});
    _roomDirectory(siteUrl).rememberLinkedRoom(room);
    notifyListeners();
    return isCurrent() ? VoiceOutgoingCall._(siteUrl, room, isCurrent) : null;
  }

  /// Takes the ringing call: the room is resolved (and held) so the caller
  /// can open and join it. Joining through the invite ref credits the
  /// caller, the same as joining from the notification link.
  Future<VoiceIncomingCallAcceptance?> acceptIncomingCall({
    bool fromSystem = false,
  }) async {
    final answer = _takeIncomingCall();
    if (answer == null) return null;
    return _acceptIncomingCall(answer, fromSystem: fromSystem);
  }

  _VoiceIncomingAnswer? _takeIncomingCall() {
    final incoming = _ringingCall;
    if (_disposed || incoming == null) return null;
    final siteSession = _siteSession(incoming.siteUrl);
    final lease = _requests.capture(incoming.siteUrl);
    // A later join takes ownership even before it has created its media.
    final joinTail = _calls.admissionIdentity;
    late final _VoiceIncomingAnswer answer;
    answer = _VoiceIncomingAnswer(
      siteUrl: incoming.siteUrl,
      call: incoming.call,
      presented: incoming.presented,
      isCurrent: () =>
          identical(_incomingAdmission, answer) &&
          identical(_calls.admissionIdentity, joinTail) &&
          _isCurrentSiteSession(incoming.siteUrl, siteSession) &&
          lease.isCurrent,
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
    _record(
      'call.ring.answered',
      data: {'roomId': answer.call.roomId, 'fromSystem': fromSystem},
    );
    if (!answer.isCurrent()) return null;
    if (answer.presented && !fromSystem) {
      // The system is still ringing; its call becomes the active one so the
      // join below does not place a second call.
      await _runHandled(
        systemCall.answerIncomingCall,
        'voice.systemCall.answerIncoming',
      );
    }
    if (!answer.isCurrent()) return null;
    final room = await _resolveRoom(
      answer.siteUrl,
      answer.call.roomSlug,
      ifCurrent: answer.isCurrent,
    );
    if (room == null || !answer.isCurrent()) return null;
    rememberInviteRef(
      siteUrl: answer.siteUrl,
      roomSlug: answer.call.roomSlug,
      username: answer.call.caller.username.toLowerCase(),
    );
    return VoiceIncomingCallAcceptance._(
      answer.siteUrl,
      room,
      answer.isCurrent,
    );
  }

  void declineIncomingCall({bool fromSystem = false}) {
    final incoming = _ringingCall;
    if (incoming == null) return;
    final presented = incoming.presented;
    _record(
      'call.ring.declined',
      data: {'roomId': incoming.call.roomId, 'fromSystem': fromSystem},
    );
    _clearIncomingCall();
    if (presented && !fromSystem) {
      _observe(
        systemCall.declineIncomingCall,
        'voice.systemCall.declineIncoming',
      );
    }
    notifyListeners();
  }

  /// Forgets the ring locally. [tellSystem] ends the system's presentation
  /// with that reason when it was ringing too; the answer and decline paths
  /// settle the system call themselves.
  void _clearIncomingCall({VoiceIncomingCallEndReason? tellSystem}) {
    final incoming = _ringingCall;
    if (incoming == null) return;
    incoming.expiry?.cancel();
    _incomingAdmission = null;
    if (incoming.presented && tellSystem != null) {
      _observe(
        () => systemCall.endIncomingCall(tellSystem),
        'voice.systemCall.endIncoming',
      );
    }
  }

  void _retireIncomingAnswer() {
    if (_incomingAdmission is _VoiceIncomingAnswer) _incomingAdmission = null;
  }

  void _incomingRoomJoined(String siteUrl, int roomId) {
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
    final caller = call.caller;
    final presented = await _runHandledValue(
      () => systemCall.reportIncomingCall(
        callerName: caller.name ?? caller.username,
        roomName: call.roomName,
        handle: caller.username,
      ),
      'voice.systemCall.reportIncoming',
      fallback: false,
    );
    if (_disposed) return;
    if (!identical(_incomingAdmission, incoming)) {
      // The ring ended (or was replaced) while the system was being asked.
      if (presented) {
        _observe(
          () =>
              systemCall.endIncomingCall(VoiceIncomingCallEndReason.unanswered),
          'voice.systemCall.endIncoming',
        );
      }
      return;
    }
    _record(
      'call.ring.system_presentation',
      data: {'roomId': call.roomId, 'presented': presented},
    );
    incoming.presentation = presented
        ? _VoiceIncomingPresentation.system
        : _VoiceIncomingPresentation.local;
    if (presented) {
      notifyListeners();
    }
  }

  /// The user answered from the system's call UI. There is no app surface
  /// to ask anything on (the app may be behind the lock screen), so the
  /// join proceeds directly; a peer-to-peer privacy warning the site would
  /// have shown before a join is said afterwards instead.
  Future<void> _answerFromSystem() async {
    // CallKit can echo a local answer or deliver its action more than once.
    // Once taken, that answer alone owns resolution and failure handling.
    if (_disposed ||
        (_ringingCall == null &&
            (_incomingAdmission is _VoiceIncomingAnswer ||
                _call != null ||
                _calls.hasPendingJoin))) {
      return;
    }
    final answer = _takeIncomingCall();
    final accepted = answer == null
        ? null
        : await _acceptIncomingCall(answer, fromSystem: true);
    bool isCurrent() =>
        answer?.isCurrent() ??
        (!_disposed &&
            _incomingAdmission == null &&
            _call == null &&
            !_calls.hasPendingJoin);
    if (!isCurrent()) return;
    if (accepted == null) {
      _record(
        'call.ring.system_answer.unresolved',
        severity: DiagnosticSeverity.warning,
      );
      if (!isCurrent()) return;
      await _runHandled(systemCall.failed, 'voice.systemCall.failed');
      return;
    }
    final siteUrl = accepted.siteUrl;
    final room = accepted.room;
    final privacyWarningEnabled =
        _meshPrivacyWarningEnabledFor?.call(siteUrl) ?? false;
    if (!isCurrent()) return;
    var warnAboutPrivacy = false;
    if (privacyWarningEnabled &&
        room.expectedTransport == VoiceTransport.mesh &&
        !await meshPrivacyAcknowledged()) {
      warnAboutPrivacy = true;
    }
    if (!isCurrent()) return;
    final siteName = _siteNameFor?.call(siteUrl) ?? siteUrl;
    if (!isCurrent()) return;
    _onIncomingCallAnswered?.call(siteUrl, room);
    if (!isCurrent()) return;
    if (warnAboutPrivacy) {
      _notify(
        appL10n
            .thisCallConnectsParticipantsDirectlySoOtherParticipantsMayBeAble,
      );
    }
    await join(siteUrl: siteUrl, siteName: siteName, room: room);
  }

  /// A ring for this user. Rings replayed from a message-bus backlog after
  /// the app wakes are only real while still within their window; a ring
  /// for the room the user is already in (answered from the notification)
  /// is nothing new; and the same ring is handled once.
  void _onRingEvent(String siteUrl, Object? data) {
    if (_disposed || data is! Map<String, dynamic>) return;
    final call = VoiceIncomingCall.fromJson(data);
    if (call == null) return;
    final now = _clock();
    final remaining = call.remainingAt(now);
    _record(
      'call.ring.received',
      data: {
        'roomId': call.roomId,
        'remainingMilliseconds': remaining.inMilliseconds,
      },
    );
    if (remaining <= Duration.zero) return;
    final active = _call;
    if (active != null &&
        active.siteUrl == siteUrl &&
        active.room.id == call.roomId) {
      return;
    }
    if (!_handledRings.add(call.key)) return;
    if (_handledRings.length > 50) _handledRings.remove(_handledRings.first);
    _retireIncomingAnswer();
    _clearIncomingCall(tellSystem: VoiceIncomingCallEndReason.unanswered);
    final incoming = _VoiceIncomingRing(siteUrl, call);
    _incomingAdmission = incoming;
    incoming.expiry = _timerFactory(remaining, () {
      if (!identical(_incomingAdmission, incoming)) return;
      _record('call.ring.expired', data: {'roomId': call.roomId});
      _clearIncomingCall(tellSystem: VoiceIncomingCallEndReason.unanswered);
      if (!_disposed) notifyListeners();
    });
    notifyListeners();
    unawaited(_presentIncomingCall(incoming));
  }

  void _notify(String message) {
    if (_disposed || _notices.isClosed) return;
    _notices.add(VoiceNotice(message));
  }

  void watchRoomVideo({required String siteUrl, required int roomId}) {
    if (_disposed) return;
    final key = '$siteUrl#$roomId';
    final previous = _roomVideoWatchers[key] ?? 0;
    _roomVideoWatchers[key] = previous + 1;
    if (previous == 0 && _isCurrentWatchedRoom(siteUrl, roomId)) {
      unawaited((_calls.current?._requestStateSync() ?? Future<void>.value()));
      _calls.current?._restorePreferredCamera();
    }
  }

  void stopWatchingRoomVideo({required String siteUrl, required int roomId}) {
    if (_disposed) return;
    final key = '$siteUrl#$roomId';
    final previous = _roomVideoWatchers[key] ?? 0;
    if (previous <= 1) {
      _roomVideoWatchers.remove(key);
      if (previous == 1 && _isCurrentWatchedRoom(siteUrl, roomId)) {
        _calls.current?.invalidateCamera();
        unawaited(
          (_calls.current?._requestStateSync() ?? Future<void>.value()),
        );
      }
    } else {
      _roomVideoWatchers[key] = previous - 1;
    }
  }

  bool _isCurrentWatchedRoom(String siteUrl, int roomId) =>
      _call?.siteUrl == siteUrl && _call?.room.id == roomId;

  bool _isWatching(VoiceCallSnapshot call) =>
      (_roomVideoWatchers['${call.siteUrl}#${call.room.id}'] ?? 0) > 0;

  /// Room directory and join-loading changes, independent of call controls,
  /// incoming rings, embedded Chat and device preferences.
  Listenable get roomListenable => _roomListChanges;

  _VoiceRoomDirectory _roomDirectory(String siteUrl) =>
      _roomDirectories.putIfAbsent(
        siteUrl,
        () => _VoiceRoomDirectory(this, siteUrl, _siteSession(siteUrl)),
      );

  VoiceDirectory? directory(String siteUrl) =>
      _roomDirectories[siteUrl]?.snapshot;
  String? errorFor(String siteUrl) => _roomDirectories[siteUrl]?.error;
  bool isLoading(String siteUrl) => _roomDirectories[siteUrl]?.loading ?? false;

  void _setSiteError(String siteUrl, String? error) =>
      _roomDirectory(siteUrl).setError(error);

  void _notifyDirectoryChanged(_VoiceRoomDirectory directory) {
    if (!directory.isCurrent) return;
    _notifyRoomListChanged();
    if (directory.isCurrent) notifyListeners();
  }

  void _notifyRoomListChanged() {
    if (_disposed) return;
    final directories = {
      for (final entry in _roomDirectories.entries)
        entry.key: ?entry.value.snapshot,
    };
    final joining = _calls.joiningRooms;
    if (!mapEquals(directories, _publishedDirectories) ||
        !setEquals(joining, _publishedJoining)) {
      _publishedDirectories = directories;
      _publishedJoining = joining;
      _roomListChanges.notifyListeners();
    }
  }

  VoiceChatSnapshot? chat(String siteUrl, int roomId) =>
      _chats[(siteUrl, roomId)]?.snapshot;

  VoiceRoom? room(String siteUrl, int roomId) =>
      _roomDirectories[siteUrl]?.room(roomId) ??
      (_retainedRoom(siteUrl)?.id == roomId ? _retainedRoom(siteUrl) : null);

  VoiceRoom? _retainedRoom(String siteUrl) =>
      _call?.siteUrl == siteUrl ? _call?.room : null;

  void _refreshRetainedRoom(String siteUrl, VoiceRoom room) =>
      _calls.current?._refreshCallRoom(siteUrl, room);

  void _directoryRoomDestroyed(String siteUrl, int roomId) {
    _removeChatAssociation(siteUrl, roomId);
    if (_call?.siteUrl == siteUrl && _call?.room.id == roomId) {
      _observe(
        () => _leave(
          notifyServer: false,
          reason: _VoiceLeaveReason.roomDestroyed,
        ),
        'voice.roomDestroyed',
      );
    }
  }

  void rememberInviteRef({
    required String siteUrl,
    required String roomSlug,
    required String username,
  }) {
    _pendingInviteRefs[siteUrl] = _VoiceInviteRef(
      roomSlug: roomSlug,
      username: username,
    );
  }

  String? _consumeInviteRef(String siteUrl, VoiceRoom room) {
    final invite = _pendingInviteRefs[siteUrl];
    if (invite == null || invite.roomSlug != room.slug) return null;
    _pendingInviteRefs.remove(siteUrl);
    return invite.username;
  }

  Future<VoiceRoom?> resolveRoom(String siteUrl, String slug) =>
      _runPublicValueOperation<VoiceRoom?>(
        () => _resolveRoom(siteUrl, slug),
        'voice.room',
        fallback: null,
      );

  Future<VoiceRoom?> _resolveRoom(
    String siteUrl,
    String slug, {
    bool Function()? ifCurrent,
  }) => _roomDirectory(siteUrl).resolveRoom(slug, ifCurrent: ifCurrent);

  Future<void> ensureLoaded(String siteUrl, {bool force = false}) =>
      _runPublicOperation(
        () => _roomDirectory(siteUrl).ensureLoaded(force: force),
        'voice.directory',
      );

  Object _siteSession(String siteUrl) =>
      _siteSessions.putIfAbsent(siteUrl, Object.new);

  Future<PluginRequestCredentials?> _requestCredentials(
    String siteUrl, {
    bool Function()? ifCurrent,
  }) async {
    final snapshot = await _requests.credentialsFor(siteUrl);
    if (ifCurrent != null && !ifCurrent()) return null;
    final apiKey = snapshot.apiKey;
    return apiKey == null ? null : snapshot;
  }

  Future<PluginRequestCredentials?> _keyRequestCredentials(
    String siteUrl, {
    bool Function()? ifCurrent,
  }) async {
    final result = await _requests.writeCredentialFor(siteUrl);
    if (ifCurrent != null && !ifCurrent()) return null;
    if (result.failure case final failure?) {
      if (failure.failure == WriteFailure.forbidden) return null;
      throw failure;
    }
    return result.credentials;
  }

  bool _isCurrentSiteSession(String siteUrl, Object session) =>
      !_disposed && identical(_siteSessions[siteUrl], session);

  bool _isCurrentCall(VoiceCallSnapshot call, Object siteSession) =>
      _isCurrentSiteSession(call.siteUrl, siteSession) &&
      identical(_call?.media, call.media) &&
      _call?.status != VoiceCallStatus.leaving;

  void attachTracker(String siteUrl, [PluginLiveChannelHandle? tracker]) {
    final replaced =
        tracker != null && !identical(_attachedTrackers[siteUrl], tracker);
    if (replaced) {
      _cancelTrackerSubscriptions(siteUrl);
      _attachedTrackers[siteUrl] = tracker;
    }
    _roomDirectory(siteUrl).syncSubscriptions();
  }

  PluginLiveChannelHandle? _trackerFor(String siteUrl) =>
      _attachedTrackers[siteUrl] ?? trackerFor(siteUrl);

  void _cancelTrackerSubscriptions(String siteUrl) {
    _roomDirectories[siteUrl]?.detachTracker();
    _ringSubscriptions.remove(siteUrl)?.cancel();
    for (final entry in _chats.entries) {
      if (entry.key.$1 == siteUrl) entry.value.detachTracker();
    }
    if (_ringingCall?.siteUrl == siteUrl) {
      _clearIncomingCall(tellSystem: VoiceIncomingCallEndReason.unanswered);
    }
  }

  bool _syncAuxiliarySubscriptions(
    String siteUrl,
    PluginLiveChannelHandle tracker,
  ) {
    var changed = false;
    final userId = _userIdFor(siteUrl);
    if (userId != null && !_ringSubscriptions.containsKey(siteUrl)) {
      _ringSubscriptions[siteUrl] = tracker.subscribe(
        '/voice/call-ring/$userId',
        (data, _) => _onRingEvent(siteUrl, data),
      );
      changed = true;
    }
    for (final entry in _chats.entries) {
      if (entry.key.$1 == siteUrl) entry.value.syncTracker();
    }
    return changed;
  }

  static VoiceRoom _mergeRoom(
    VoiceRoom? held,
    VoiceRoom incoming, {
    bool preserveRecording = false,
  }) => incoming
      .mergeUserFields(held)
      .copyWith(
        messageBusLastId: _newerCursor(
          held?.messageBusLastId,
          incoming.messageBusLastId,
        ),
        recording: preserveRecording
            ? incoming.recording ?? held?.recording
            : incoming.recording,
      );

  void _onRoomEvent(String siteUrl, int roomId, Object? data, int messageId) {
    if (_disposed) return;
    if (data is! Map<String, dynamic>) return;
    if (data['type'] == 'signal') {
      _observe(
        () => _handleSignalEnvelope(siteUrl, roomId, data),
        'voice.media.signal',
      );
      return;
    }
    final event = VoiceRoomEvent.fromJson(data);
    if (event == null) return;
    if (event is VoiceKickedEvent) {
      final call = _call;
      if (call?.siteUrl == siteUrl && call?.room.id == roomId) {
        _record(
          'room.kicked',
          component: 'room',
          correlationId: _correlationFor(call),
          severity: DiagnosticSeverity.warning,
          data: {'roomId': roomId},
        );
        _observe(
          () => _leave(notifyServer: false, reason: _VoiceLeaveReason.kicked),
          'voice.kicked',
        );
      }
      return;
    }
    _roomDirectories[siteUrl]?.liveRoomChanged(roomId);
    if (event is VoiceRoleChangedEvent) {
      _record(
        'room.role_changed',
        component: 'roster',
        correlationId: _correlationForRoom(siteUrl, roomId),
        data: {
          'roomId': roomId,
          'participantScope': event.userId == _userIdFor(siteUrl)
              ? 'local'
              : 'remote',
          'role': event.role.name,
        },
      );
      _recordRaw(
        'room.role_changed.detail',
        component: 'roster',
        correlationId: _correlationForRoom(siteUrl, roomId),
        data: {'roomId': roomId, 'userId': event.userId},
      );
      final held = room(siteUrl, roomId);
      if (held != null &&
          held.participants.any(
            (participant) => participant.id == event.userId,
          )) {
        _replaceParticipants(siteUrl, roomId, [
          for (final participant in held.participants)
            participant.id == event.userId
                ? _participantWithRole(participant, event.role)
                : participant,
        ]);
      }
      if (event.userId == _userIdFor(siteUrl) &&
          _call?.siteUrl == siteUrl &&
          _call?.room.id == roomId) {
        _notify(
          event.role == VoiceRole.participant
              ? appL10n.youVeBeenMovedToListeners
              : appL10n.youVeBeenMadeASpeaker,
        );
      }
      return;
    }
    if (event is VoiceHandRaiseEvent) {
      _applyHandRaise(siteUrl, roomId, event);
      return;
    }
    if (event is VoiceRingingEvent) {
      _updateRoom(siteUrl, roomId, (room) => room.withRinging(event.entry));
      _notifyRoomListChanged();
      notifyListeners();
      return;
    }
    if (event is VoiceParticipantsEvent) {
      _recordRoster(
        'room.roster_received',
        siteUrl,
        roomId,
        event.participants,
        correlationId: _correlationForRoom(siteUrl, roomId),
      );
      _replaceParticipants(siteUrl, roomId, event.participants);
    }
    if (event is VoiceRecordingEvent) {
      _record(
        'room.recording_changed',
        component: 'room',
        correlationId: _correlationForRoom(siteUrl, roomId),
        data: {'roomId': roomId, 'active': event.recording?.active ?? false},
      );
      final wasRecording = room(siteUrl, roomId)?.recording?.active ?? false;
      _replaceRecording(siteUrl, roomId, event.recording);
      // Only people in the call are told; the moderator who pressed the
      // button watched their own control change.
      final call = _call;
      if (call?.siteUrl == siteUrl && call?.room.id == roomId) {
        final recording = event.recording;
        if (recording != null && recording.active) {
          if (recording.startedById != _userIdFor(siteUrl)) {
            _notify(appL10n.thisCallIsNowBeingRecorded);
          }
        } else if (wasRecording) {
          _notify(appL10n.theRecordingHasStopped);
        }
      }
    }
  }

  /// The lightweight hand-raise event lands before the roster broadcast that
  /// carries the same change, so the raise is applied to the held roster at
  /// once. The toasts mirror the web client: a dismissed request tells its
  /// owner, a new raise tells the room's managers.
  void _applyHandRaise(String siteUrl, int roomId, VoiceHandRaiseEvent event) {
    final userId = _userIdFor(siteUrl);
    _updateRoom(siteUrl, roomId, (room) {
      if (!room.participants.any((p) => p.id == event.userId)) return room;
      return room.withParticipants([
        for (final participant in room.participants)
          participant.id == event.userId
              ? _participantWithHandRaised(
                  participant,
                  event.raised ? (event.raisedAt ?? DateTime.now()) : null,
                )
              : participant,
      ]);
    });
    // The call's copy of the room is the one serialized for this user, so
    // it is the one that knows whether they manage it.
    final call = _call;
    final inCall =
        call != null && call.siteUrl == siteUrl && call.room.id == roomId;
    final held = inCall ? call.room : room(siteUrl, roomId);
    if (inCall && event.userId == userId) {
      if (!event.raised && event.reason == 'dismissed') {
        _notify(appL10n.yourRequestToSpeakWasDismissed);
      }
    } else if (inCall && event.raised && (held?.canManage ?? false)) {
      final raiser = held?.participants
          .where((participant) => participant.id == event.userId)
          .firstOrNull;
      if (raiser != null) {
        _notify(
          appL10n.raisedTheirHandToSpeak(
            (raiser.name ?? raiser.username).toString(),
          ),
        );
      }
    }
    _notifyRoomListChanged();
    notifyListeners();
  }

  Future<void> _handleSignalEnvelope(
    String siteUrl,
    int roomId,
    Map<String, dynamic> envelope,
  ) async {
    final senderId = liveRefreshId(envelope['sender_id']);
    if (senderId == null) return;

    final events = <Map<String, dynamic>>[];
    final rawEvents = envelope['events'];
    if (rawEvents is Iterable) {
      for (final value in rawEvents.take(25)) {
        if (value is Map) events.add(Map<String, dynamic>.from(value));
      }
    } else {
      final legacyEvent = envelope['data'];
      if (legacyEvent is Map) {
        events.add(Map<String, dynamic>.from(legacyEvent));
      }
    }
    final call = _call;
    final isActiveCall =
        call != null && call.siteUrl == siteUrl && call.room.id == roomId;
    final correlationId = isActiveCall ? _correlationFor(call) : null;
    _record(
      'signaling.received',
      component: 'signaling',
      correlationId: correlationId,
      data: {
        'roomId': roomId,
        'senderPresent': true,
        'eventCount': events.length,
        if (events.firstOrNull case final first?)
          'type': _voiceSignalingDiagnosticType(first['type']),
      },
    );
    if (events.isNotEmpty) {
      _recordRaw(
        'signaling.received.raw',
        component: 'signaling',
        correlationId: correlationId,
        data: {
          'siteUrl': siteUrl,
          'roomId': roomId,
          'senderId': senderId,
          'signals': events,
        },
      );
    }
    if (call == null ||
        call.siteUrl != siteUrl ||
        call.room.id != roomId ||
        events.isEmpty) {
      return;
    }
    final activeCall = call;

    // Voice attests the sender and includes their basic serialization so an
    // offer can beat the asynchronous roster broadcast without creating an
    // invisible peer. Stage rooms still wait for the authoritative roster,
    // because the basic serialization does not carry the sender's stage role.
    if (activeCall.room.type == VoiceRoomType.open &&
        events.any((event) => event['type'] == 'offer') &&
        !activeCall.room.participants.any(
          (participant) => participant.id == senderId,
        )) {
      final rawSender = envelope['sender'];
      if (rawSender is Map) {
        final participant = VoiceParticipant.fromJson(
          Map<String, dynamic>.from(rawSender),
        );
        if (participant.id == senderId) {
          final participants = canonicalVoiceParticipants([
            ...activeCall.room.participants,
            participant,
          ]);
          _roomDirectories[siteUrl]?.updateListedRoom(
            roomId,
            (room) => room.withParticipants(participants),
          );
          if (identical(_call?.media, activeCall.media)) {
            _calls.current?.updateRoom(
              (room) => room.withParticipants(participants),
            );
            _notifyRoomListChanged();
            notifyListeners();
            await activeCall.media.syncParticipants(participants);
          }
        }
      }
    }

    if (!identical(_call?.media, activeCall.media)) return;
    for (final event in events) {
      await activeCall.media.handleSignal(senderId, event);
    }
  }

  static VoiceParticipant _participantWithRole(
    VoiceParticipant participant,
    VoiceRole role,
  ) => VoiceParticipant(
    id: participant.id,
    username: participant.username,
    externalAgent: participant.externalAgent,
    livekitIdentity: participant.livekitIdentity,
    role: role,
    name: participant.name,
    avatarTemplate: participant.avatarTemplate,
    muted: participant.muted,
    deafened: participant.deafened,
    videoOn: participant.videoOn,
    screenSharing: participant.screenSharing,
    watchingVideo: participant.watchingVideo,
    idleState: participant.idleState,
    handRaisedAt: participant.handRaisedAt,
  );

  static VoiceParticipant _participantWithIdleState(
    VoiceParticipant participant,
    VoiceIdleState idleState,
  ) => VoiceParticipant(
    id: participant.id,
    username: participant.username,
    externalAgent: participant.externalAgent,
    livekitIdentity: participant.livekitIdentity,
    role: participant.role,
    name: participant.name,
    avatarTemplate: participant.avatarTemplate,
    muted: participant.muted,
    deafened: participant.deafened,
    videoOn: participant.videoOn,
    screenSharing: participant.screenSharing,
    watchingVideo: participant.watchingVideo,
    idleState: idleState,
    handRaisedAt: participant.handRaisedAt,
  );

  static VoiceParticipant _participantWithHandRaised(
    VoiceParticipant participant,
    DateTime? handRaisedAt,
  ) => VoiceParticipant(
    id: participant.id,
    username: participant.username,
    externalAgent: participant.externalAgent,
    livekitIdentity: participant.livekitIdentity,
    role: participant.role,
    name: participant.name,
    avatarTemplate: participant.avatarTemplate,
    muted: participant.muted,
    deafened: participant.deafened,
    videoOn: participant.videoOn,
    screenSharing: participant.screenSharing,
    watchingVideo: participant.watchingVideo,
    idleState: participant.idleState,
    handRaisedAt: handRaisedAt,
  );

  /// Applies [update] to every copy of the room this controller holds — the
  /// directory listing, a room reached by link, and (unless [updateCall] is
  /// off) the active call — so no surface reads a stale copy.
  void _updateRoom(
    String siteUrl,
    int roomId,
    VoiceRoom Function(VoiceRoom room) update, {
    bool updateCall = true,
  }) {
    _roomDirectories[siteUrl]?.updateRoom(roomId, update);
    final call = _call;
    if (updateCall &&
        call != null &&
        call.siteUrl == siteUrl &&
        call.room.id == roomId) {
      _calls.current?.updateRoom(update);
    }
  }

  void _replaceRecording(
    String siteUrl,
    int roomId,
    VoiceRecording? recording,
  ) {
    _updateRoom(siteUrl, roomId, (room) => room.withRecording(recording));
    _notifyRoomListChanged();
    notifyListeners();
  }

  void _replaceParticipants(
    String siteUrl,
    int roomId,
    List<VoiceParticipant> participants,
  ) {
    _updateRoom(
      siteUrl,
      roomId,
      (room) => room.withParticipants(participants),
      updateCall: false,
    );
    if (_calls.current case final session?) {
      session.receiveParticipants(siteUrl, roomId, participants);
    } else {
      _notifyRoomListChanged();
      notifyListeners();
    }
  }

  void _removeLocalParticipant(String siteUrl, int roomId) {
    final userId = _userIdFor(siteUrl);
    if (userId == null) return;
    _updateRoom(
      siteUrl,
      roomId,
      (room) => room.withParticipants([
        for (final participant in room.participants)
          if (participant.id != userId) participant,
      ]),
    );
  }

  static bool _canPublishAudio(
    VoiceRoom room,
    List<VoiceParticipant> participants,
    int userId,
  ) {
    if (room.type != VoiceRoomType.stage) return true;
    final role = participants
        .where((participant) => participant.id == userId)
        .firstOrNull
        ?.role;
    final effective = role ?? room.membership?.role;
    return effective == VoiceRole.moderator || effective == VoiceRole.speaker;
  }

  Future<void> join({
    required String siteUrl,
    required String siteName,
    required VoiceRoom room,
  }) => _calls.join(siteUrl: siteUrl, siteName: siteName, room: room);

  /// A heartbeat refused with a membership-shaped status: the participant
  /// session is gone or was never ours to keep (403), the room is gone (404),
  /// or the call instance ended (410). Anything else is transient.
  static bool _isExpulsion(WriteException error) => switch (error.statusCode) {
    HttpStatus.forbidden ||
    HttpStatus.unauthorized ||
    HttpStatus.notFound ||
    HttpStatus.gone => true,
    null => error.failure == WriteFailure.forbidden,
    _ => false,
  };

  /// Coming to the foreground is activity; going to the background is not
  /// absence. A call continues from a pocket or behind another window, and
  /// the server's away status dims the participant for everyone, so the
  /// ladder in [VoiceIdleTracker] decides from elapsed silence instead. A
  /// heartbeat goes out either way so presence is refreshed at the moment
  /// the app can least rely on its timers.
  void setForeground(bool foreground) {
    if (_disposed) return;
    _foreground = foreground;
    if (foreground) {
      _calls.current?._restorePreferredCamera();
    } else {
      _calls.current?.invalidateCamera();
    }
    if (foreground) _calls.current?._userActed();
    if (_call != null) {
      unawaited((_calls.current?._requestHeartbeat() ?? Future<void>.value()));
    }
  }

  /// Every deliberate call control counts as the user being present.

  void _userActed() => _calls.current?._userActed();

  Future<void> setMuted(bool muted) {
    // Cleared before the activity is recorded: an unmute is the user acting
    // on an automatic mute, not a return that needs telling about it.
    if (!muted) _calls.current?.acknowledgeUnmute();
    _userActed();
    return _setMuted(muted, syncSystem: true);
  }

  void dismissCallError([String? siteUrl]) {
    if (_disposed) return;
    final clearedSiteError = _roomDirectories[siteUrl]?.setError(null) ?? false;
    final clearedCallError = _call?.error != null;
    if (clearedCallError) _calls.current?.dismissError();
    if (clearedSiteError || clearedCallError) notifyListeners();
  }

  Future<void> _setMuted(bool muted, {required bool syncSystem}) =>
      _calls.current?._setMuted(muted, syncSystem: syncSystem) ??
      Future<void>.value();

  Future<void> setDeafened(bool deafened) {
    _userActed();
    return _setDeafened(deafened);
  }

  Future<void> _setDeafened(bool deafened) =>
      _calls.current?._setDeafened(deafened) ?? Future<void>.value();

  Future<void> setCameraEnabled(bool enabled, {String? deviceId}) {
    _userActed();
    return _calls.current?._setCameraEnabled(
          enabled,
          deviceId: deviceId,
          remember: true,
        ) ??
        Future<void>.value();
  }

  Future<void> _rememberCamera(String siteUrl, int userId, bool enabled) {
    _cameraPreferences[(siteUrl, userId)] = Future.value(enabled);
    return _persistPreference(
      () => _preferences.writeCameraEnabled(siteUrl, userId, enabled),
      'voice.preferences.cameraEnabled',
    );
  }

  Future<bool> _readCameraPreference(String siteUrl, int userId) async {
    try {
      return await _preferences.readCameraEnabled(siteUrl, userId);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'voice.preferences.cameraEnabled');
      return false;
    }
  }

  Future<List<rtc.MediaDeviceInfo>> mediaDevices() =>
      _runPublicValueOperation<List<rtc.MediaDeviceInfo>>(
        () async {
          if (_disposed) return const <rtc.MediaDeviceInfo>[];
          final media = _call?.media;
          if (media == null) return const <rtc.MediaDeviceInfo>[];
          final result = await media.devices();
          return _disposed ? const <rtc.MediaDeviceInfo>[] : result;
        },
        'voice.media.devices',
        fallback: const [],
      );

  Future<void> selectAudioInput(String deviceId) => _runPublicOperation(
    () => _selectAudioInput(deviceId),
    'voice.media.selectAudioInput',
    correlationId: _activeDiagnosticCorrelationId,
  );

  Future<void> _selectAudioInput(String deviceId) async {
    await _selectAudioDevice(
      deviceId,
      choice: _devicePreferences.audioInput,
      preference: VoiceDevicePreference.audioInput,
      kind: 'audio_input',
      selectDevice: (media) => media.selectAudioInput(deviceId),
    );
  }

  Future<void> selectAudioOutput(String deviceId) => _runPublicOperation(
    () => _selectAudioOutput(deviceId),
    'voice.media.selectAudioOutput',
    correlationId: _activeDiagnosticCorrelationId,
  );

  Future<void> _selectAudioOutput(String deviceId) async {
    await _selectAudioDevice(
      deviceId,
      choice: _devicePreferences.audioOutput,
      preference: VoiceDevicePreference.audioOutput,
      kind: 'audio_output',
      selectDevice: (media) => media.selectAudioOutput(deviceId),
    );
  }

  Future<void> _selectAudioDevice(
    String deviceId, {
    required _VoicePreferenceChoice<String?> choice,
    required VoiceDevicePreference preference,
    required String kind,
    required Future<void> Function(VoiceMediaSession) selectDevice,
  }) async {
    if (_disposed) return;
    final intent = choice.select(deviceId);
    final session = _calls.current;
    final media = session?._call?.media;
    bool isCurrent() =>
        !_disposed &&
        choice.isCurrent(intent) &&
        session != null &&
        session.isActive &&
        identical(session._call?.media, media);
    final correlationId =
        _activeDiagnosticCorrelationId ??
        _reporter.newCorrelationId('voice-device');
    await _traceDeviceSelection(
      kind: kind,
      origin: 'user',
      deviceId: deviceId,
      applied: media != null,
      correlationId: correlationId,
      action: () async {
        await _persistPreference(
          () => _preferences.writeDevice(preference, deviceId),
          'voice.preferences.${preference.name}',
        );
        if (media == null || !isCurrent()) return;
        await _devicePreferences.audioOperations.run(
          owner: media,
          key: preference,
          operation: () async {
            if (isCurrent()) await selectDevice(media);
          },
        );
      },
    );
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> selectCamera(String deviceId) => _runPublicOperation(
    () => _selectCamera(deviceId),
    'voice.media.selectCamera',
    correlationId: _activeDiagnosticCorrelationId,
  );

  Future<void> switchCamera() => _runPublicOperation(
    () async {
      final call = _call;
      if (_disposed ||
          call == null ||
          call.status != VoiceCallStatus.connected ||
          !call.cameraEnabled ||
          call.screenSharing ||
          cameraStarting) {
        return;
      }
      _userActed();
      await _selectCamera(
        null,
        facing: call.media.cameraFacing == VoiceCameraFacing.front
            ? VoiceCameraFacing.back
            : VoiceCameraFacing.front,
      );
    },
    'voice.media.switchCamera',
    correlationId: _activeDiagnosticCorrelationId,
  );

  Future<void> _selectCamera(
    String? deviceId, {
    VoiceCameraFacing? facing,
  }) async {
    if (_disposed) return;
    final selection = _devicePreferences.selectCamera(deviceId, facing);
    final session = _calls.current;
    if (session?._call != null) {
      await session!._selectCamera(deviceId, facing: facing);
      return;
    }
    notifyListeners();
    final correlationId = _reporter.newCorrelationId('voice-device');
    await _traceDeviceSelection(
      kind: 'camera',
      origin: 'user',
      deviceId: deviceId ?? facing!.name,
      applied: false,
      correlationId: correlationId,
      action: () async {
        if (deviceId != null) {
          await _persistPreference(
            () => _preferences.writeDevice(
              VoiceDevicePreference.camera,
              deviceId,
            ),
            'voice.preferences.camera',
          );
        }
        if (!_disposed && _devicePreferences.camera.isCurrent(selection)) {
          _calls.current?._restorePreferredCamera();
        }
      },
    );
    if (!_disposed) notifyListeners();
  }

  Future<void> setPushToTalkEnabled(bool enabled) async {
    if (_disposed) return;
    final choice = _devicePreferences.pushToTalk;
    final intent = choice.select(enabled);
    final session = _calls.current;
    await _persistPreference(
      () => _preferences.writePushToTalk(enabled),
      'voice.preferences.pushToTalk',
    );
    if (_disposed) return;
    if (enabled && choice.isCurrent(intent) && session?.isActive == true) {
      session!._userActed();
      await session._setMuted(true, syncSystem: true);
    }
    if (_disposed) return;
    notifyListeners();
  }

  Future<double> participantVolume(
    String siteUrl,
    int roomId,
    int userId,
  ) async {
    if (_disposed) return 1;
    try {
      return ((await _preferences.readParticipantVolume(
                siteUrl,
                roomId,
                userId,
              )) ??
              1)
          .clamp(0, 1)
          .toDouble();
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'voice.preferences.readVolume');
      return 1;
    }
  }

  Future<void> setParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
    double volume,
  ) => _runPublicOperation(
    () => _setParticipantVolume(siteUrl, roomId, userId, volume),
    'voice.media.participantVolume',
    correlationId: _activeDiagnosticCorrelationId,
  );

  Future<void> _setParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
    double volume,
  ) async {
    if (_disposed) return;
    final normalized = volume.clamp(0, 1).toDouble();
    final call = _call;
    final media = call?.siteUrl == siteUrl && call?.room.id == roomId
        ? call?.media
        : null;
    if (media != null) {
      _calls.current?.claimParticipantVolume(userId);
    }
    await media?.setParticipantVolume(userId, normalized);
    if (_disposed) return;
    await _persistPreference(
      () => _preferences.writeParticipantVolume(
        siteUrl,
        roomId,
        userId,
        normalized,
      ),
      'voice.preferences.writeVolume',
    );
  }

  Future<void> _restoreDevicePreferences() async {
    final correlationId = _reporter.newCorrelationId('voice-preferences');
    _record(
      'preferences.devices.restore_started',
      component: 'preferences',
      correlationId: correlationId,
    );
    try {
      final preferences = await _preferences.readDevices();
      if (_disposed) return;
      _devicePreferences.restoreDevices(preferences);
      _record(
        'preferences.devices.restore_completed',
        component: 'preferences',
        correlationId: correlationId,
        data: {
          'audioInputPresent': preferences.audioInputDeviceId != null,
          'audioOutputPresent': preferences.audioOutputDeviceId != null,
          'cameraPresent': preferences.cameraDeviceId != null,
          'pushToTalkEnabled': preferences.pushToTalkEnabled,
        },
      );
      _recordRaw(
        'preferences.devices.restore_detail',
        component: 'preferences',
        correlationId: correlationId,
        data: {
          'audioInputDeviceId': ?preferences.audioInputDeviceId,
          'audioOutputDeviceId': ?preferences.audioOutputDeviceId,
          'cameraDeviceId': ?preferences.cameraDeviceId,
        },
      );
      notifyListeners();
    } catch (error, stackTrace) {
      // Tests and early startup may not have a preferences channel yet. Device
      // defaults remain usable and the next explicit selection persists.
      _record(
        'preferences.devices.restore_failed',
        component: 'preferences',
        correlationId: correlationId,
        severity: DiagnosticSeverity.warning,
        data: {'errorType': error.runtimeType.toString()},
      );
      _recordRaw(
        'preferences.devices.restore_failure_detail',
        component: 'preferences',
        correlationId: correlationId,
        severity: DiagnosticSeverity.warning,
        message: error.toString(),
        data: {'stackTrace': stackTrace.toString()},
      );
      _report(error, stackTrace, 'voice.preferences.restore');
    }
  }

  Future<void> _restoreAutoStatusPreference() async {
    try {
      final stored = await _preferences.readAutoStatusEnabled();
      if (_disposed || stored == null) return;
      _devicePreferences.autoStatus.restore(stored);
      notifyListeners();
    } catch (error, stackTrace) {
      // Same contract as the device restore: the default stays usable and
      // the next explicit choice persists.
      _report(error, stackTrace, 'voice.preferences.restore');
    }
  }

  Future<void> _selectSavedAudioDevice({
    required String kind,
    required String deviceId,
    required String correlationId,
    required VoiceMediaSession media,
    required VoiceDevicePreference preference,
    required _VoicePreferenceChoice<String?> choice,
    required Future<void> Function(String) selectDevice,
    required bool Function() isCurrent,
  }) {
    final intent = choice.intent;
    bool selectionIsCurrent() => isCurrent() && choice.isCurrent(intent);
    return _devicePreferences.audioOperations.run(
      owner: media,
      key: preference,
      operation: () async {
        if (!selectionIsCurrent()) return;
        try {
          await _traceDeviceSelection(
            kind: kind,
            origin: 'saved_join',
            deviceId: deviceId,
            applied: true,
            correlationId: correlationId,
            action: () => selectDevice(deviceId),
          );
        } on Exception {
          if (!selectionIsCurrent()) return;
          if (deviceId == 'default') rethrow;

          await _traceDeviceSelection(
            kind: kind,
            origin: 'saved_join_fallback',
            deviceId: 'default',
            applied: true,
            correlationId: correlationId,
            action: () => selectDevice('default'),
          );
        }
      },
    );
  }

  Future<void> _traceDeviceSelection({
    required String kind,
    required String origin,
    required String deviceId,
    required bool applied,
    required String correlationId,
    required Future<void> Function() action,
  }) async {
    final safeData = <String, Object?>{
      'kind': kind,
      'origin': origin,
      'applied': applied,
    };
    _record(
      'media.device_selection.attempted',
      component: 'media',
      correlationId: correlationId,
      data: safeData,
    );
    _recordRaw(
      'media.device_selection.attempt_detail',
      component: 'media',
      correlationId: correlationId,
      data: {...safeData, 'deviceId': deviceId},
    );
    try {
      await action();
      _record(
        'media.device_selection.succeeded',
        component: 'media',
        correlationId: correlationId,
        data: safeData,
      );
      _recordRaw(
        'media.device_selection.success_detail',
        component: 'media',
        correlationId: correlationId,
        data: {...safeData, 'deviceId': deviceId},
      );
    } catch (error, stackTrace) {
      _record(
        'media.device_selection.failed',
        component: 'media',
        correlationId: correlationId,
        severity: DiagnosticSeverity.warning,
        data: {...safeData, 'errorType': error.runtimeType.toString()},
      );
      _recordRaw(
        'media.device_selection.failure_detail',
        component: 'media',
        correlationId: correlationId,
        severity: DiagnosticSeverity.warning,
        message: error.toString(),
        data: {
          ...safeData,
          'deviceId': deviceId,
          'errorType': error.runtimeType.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _persistPreference(
    Future<void> Function() write,
    String operation,
  ) async {
    try {
      await write();
    } catch (error, stackTrace) {
      _report(error, stackTrace, operation);
    }
  }

  Future<void> setScreenSharing(bool enabled) {
    _userActed();
    return _setScreenSharing(enabled);
  }

  Future<void> _setScreenSharing(bool enabled) =>
      _calls.current?._setScreenSharing(enabled) ?? Future<void>.value();

  Future<void> leave({bool notifyServer = true}) =>
      _leave(notifyServer: notifyServer, reason: _VoiceLeaveReason.user);

  Future<void> _leave({
    required bool notifyServer,
    required _VoiceLeaveReason reason,
    bool clearImmediately = false,
  }) => _calls.leave(
    notifyServer: notifyServer,
    reason: reason,
    clearImmediately: clearImmediately,
  );

  Future<VoiceRoom?> saveRoom({
    required String siteUrl,
    required VoiceRoomDraft draft,
    int? roomId,
  }) => _runPublicValueOperation<VoiceRoom?>(
    () => _roomDirectory(siteUrl).saveRoom(draft: draft, roomId: roomId),
    'voice.saveRoom',
    fallback: null,
  );

  void _notifyChatChanged(_VoiceChatAssociation association) {
    if (association.isCurrent) notifyListeners();
  }

  _VoiceChatAssociation _chatAssociation(String siteUrl, int roomId) =>
      _chats.putIfAbsent((
        siteUrl,
        roomId,
      ), () => _VoiceChatAssociation(this, siteUrl, roomId));

  Future<void> openChat(String siteUrl, int roomId, {bool force = false}) =>
      _runPublicOperation(
        () => _chatAssociation(siteUrl, roomId).open(force: force),
        'voice.chat.load',
      );

  void closeChat(String siteUrl, int roomId) {
    final association = _chats[(siteUrl, roomId)];
    if (association == null) return;
    association.hide();
    if (!_disposed) notifyListeners();
  }

  Future<void> loadOlderChat(String siteUrl, int roomId) =>
      _chats[(siteUrl, roomId)]?.loadOlder() ?? Future<void>.value();

  Future<void> sendChatMessage(String siteUrl, int roomId, String message) {
    _userActed();
    return _runPublicOperation(
      () => message.trim().isEmpty
          ? Future<void>.value()
          : _chatAssociation(siteUrl, roomId).send(message),
      'voice.chat.send',
    );
  }

  void _removeChatAssociation(String siteUrl, int roomId) {
    _chats.remove((siteUrl, roomId))?.retire();
  }

  void _pruneChatAssociations(String siteUrl, Set<int> roomIds) {
    final removed = _chats.keys
        .where((key) => key.$1 == siteUrl && !roomIds.contains(key.$2))
        .toList();
    for (final key in removed) {
      _chats.remove(key)?.retire();
    }
  }

  Future<void> requestToSpeak({int? userId, bool raised = true}) {
    _userActed();
    return _runPublicOperation(
      () => _requestToSpeak(userId: userId, raised: raised),
      'voice.requestToSpeak',
      correlationId: _activeDiagnosticCorrelationId,
    );
  }

  Future<void> _requestToSpeak({int? userId, bool raised = true}) async {
    final call = _call;
    if (call == null) return;
    final siteSession = _siteSession(call.siteUrl);
    bool isCurrent() => _isCurrentCall(call, siteSession);
    final credentials = await _keyRequestCredentials(
      call.siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return;
    await credentials.run(
      () => api.requestToSpeak(
        siteUrl: call.siteUrl,
        roomId: call.room.id,
        apiKey: credentials.apiKey!,
        userId: userId,
        raised: raised,
        participantSessionId: _calls.current?._participantSessionId,
      ),
    );
  }

  /// Makes [userId] a speaker or moves them back to the listeners of the
  /// active stage room. A membership write: the server re-broadcasts the
  /// roster with the new role, and a promoted listener's raised hand is
  /// lowered by it.
  Future<void> setParticipantRole(int userId, VoiceRole role) {
    _userActed();
    return _runPublicOperation(
      () => _setParticipantRole(userId, role),
      'voice.setParticipantRole',
      correlationId: _activeDiagnosticCorrelationId,
    );
  }

  Future<void> _setParticipantRole(int userId, VoiceRole role) async {
    final call = _call;
    if (call == null ||
        userId < 0 ||
        call.room.participants.any((p) => p.id == userId && p.isAgent)) {
      return;
    }
    final siteSession = _siteSession(call.siteUrl);
    bool isCurrent() => _isCurrentCall(call, siteSession);
    final credentials = await _requestCredentials(
      call.siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return;
    await credentials.run(
      () => api.addMembership(
        siteUrl: call.siteUrl,
        roomId: call.room.id,
        apiKey: credentials.apiKey!,
        userId: userId,
        role: role,
        clientId: credentials.clientId,
      ),
    );
  }

  Future<void> kick(int userId) => _runPublicOperation(
    () => _kick(userId),
    'voice.kick',
    correlationId: _activeDiagnosticCorrelationId,
  );

  Future<void> _kick(int userId) async {
    final call = _call;
    if (call == null) return;
    final siteSession = _siteSession(call.siteUrl);
    bool isCurrent() => _isCurrentCall(call, siteSession);
    final credentials = await _keyRequestCredentials(
      call.siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return;
    await credentials.run(
      () => api.kick(
        siteUrl: call.siteUrl,
        roomId: call.room.id,
        apiKey: credentials.apiKey!,
        userId: userId,
      ),
    );
  }

  Future<bool> flagParticipant(int userId, String message) =>
      _runPublicValueOperation<bool>(
        () => _flagParticipant(userId, message),
        'voice.flag',
        fallback: false,
        correlationId: _activeDiagnosticCorrelationId,
      );

  Future<bool> _flagParticipant(int userId, String message) async {
    final call = _call;
    final text = message.trim();
    if (call == null || text.isEmpty) return false;
    final siteSession = _siteSession(call.siteUrl);
    bool isCurrent() => _isCurrentCall(call, siteSession);
    final credentials = await _requestCredentials(
      call.siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return false;
    final flagTypeId = await credentials.run(
      () => api.notifyModeratorsFlagType(
        siteUrl: call.siteUrl,
        apiKey: credentials.apiKey!,
        clientId: credentials.clientId,
      ),
    );
    if (flagTypeId == null || !isCurrent()) return false;
    final writeCredentials = await _keyRequestCredentials(
      call.siteUrl,
      ifCurrent: isCurrent,
    );
    if (writeCredentials == null) return false;
    await writeCredentials.run(
      () => api.flag(
        siteUrl: call.siteUrl,
        roomId: call.room.id,
        apiKey: writeCredentials.apiKey!,
        userId: userId,
        flagTypeId: flagTypeId,
        message: text,
      ),
    );
    return true;
  }

  Future<void> setRecording(bool active) => _runPublicOperation(
    () => _setRecording(active),
    'voice.recording',
    correlationId: _activeDiagnosticCorrelationId,
  );

  Future<void> _setRecording(bool active) async {
    final call = _call;
    if (call == null) return;
    final siteSession = _siteSession(call.siteUrl);
    bool isCurrent() => _isCurrentCall(call, siteSession);
    final credentials = await _keyRequestCredentials(
      call.siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return;
    await credentials.run(
      () => api.setRecording(
        siteUrl: call.siteUrl,
        roomId: call.room.id,
        apiKey: credentials.apiKey!,
        active: active,
      ),
    );
  }

  final Map<
    String,
    ({VoiceAgentPermission permission, bool Function() current})
  >
  _agentPermissions = {};
  final Map<String, Object> _agentPermissionRequests = {};
  final Map<(String, int), Object> _agentSubmissions = {};
  final _agentPermissionRevision = FrameSafeValueNotifier(0);
  Listenable get agentPermissions => _agentPermissionRevision;

  Future<void> refreshAgentPermission(String siteUrl) async {
    if (_disposed) return;
    _agentPermissions.remove(siteUrl);
    _agentPermissionRevision.value++;
    final ownsAccount = captureSiteSession(siteUrl);
    final request = Object();
    _agentPermissionRequests[siteUrl] = request;
    bool current() =>
        ownsAccount() && identical(_agentPermissionRequests[siteUrl], request);
    try {
      final credentials = await _requestCredentials(
        siteUrl,
        ifCurrent: current,
      );
      if (credentials == null) return;
      final permission = await credentials.run(
        () => api.agentPermission(
          siteUrl: siteUrl,
          apiKey: credentials.apiKey!,
          clientId: credentials.clientId,
        ),
      );
      if (!current()) return;
      _agentPermissions[siteUrl] = (
        permission: permission,
        current: ownsAccount,
      );
    } catch (_) {
      if (!current()) return;
      _agentPermissions.remove(siteUrl);
    } finally {
      if (current()) _agentPermissionRevision.value++;
    }
  }

  bool canInviteAgent(String siteUrl, int roomId) {
    final grant = _agentPermissions[siteUrl];
    final target = room(siteUrl, roomId);
    return !_disposed &&
        grant != null &&
        grant.current() &&
        target != null &&
        grant.permission.allows(target);
  }

  VoiceAgentInvitation agentInvitation(
    String siteUrl,
    int roomId, {
    bool Function()? ifCurrent,
  }) {
    final ownsAccount = captureSiteSession(siteUrl);
    final target = room(siteUrl, roomId);
    final active = _call;
    final ownsCall = active?.siteUrl == siteUrl && active?.room.id == roomId;
    bool current() =>
        ownsAccount() &&
        (ifCurrent?.call() ?? true) &&
        target != null &&
        room(siteUrl, roomId)?.slug == target.slug &&
        (!ownsCall || identical(_call?.media, active?.media));
    late final VoiceAgentInvitation invitation;
    bool available() => invitation.isCurrent && canInviteAgent(siteUrl, roomId);
    invitation = VoiceAgentInvitation(
      isCurrent: current,
      load: (refresh) async {
        if (!available()) return const [];
        final credentials = await _requestCredentials(
          siteUrl,
          ifCurrent: available,
        );
        if (credentials == null) return const [];
        final names = await credentials.run(
          () => api.agents(
            siteUrl: siteUrl,
            apiKey: credentials.apiKey!,
            clientId: credentials.clientId,
            refresh: refresh,
          ),
        );
        return available() ? names : const [];
      },
      invite: (name) async {
        final key = (siteUrl, roomId);
        if (!available() || _agentSubmissions.containsKey(key)) return false;
        final submission = Object();
        _agentSubmissions[key] = submission;
        try {
          final credentials = await _requestCredentials(
            siteUrl,
            ifCurrent: available,
          );
          if (credentials == null) return false;
          await credentials.run(
            () => api.inviteAgent(
              siteUrl: siteUrl,
              roomId: roomId,
              apiKey: credentials.apiKey!,
              clientId: credentials.clientId,
              agentName: name,
            ),
          );
          return current();
        } finally {
          if (identical(_agentSubmissions[key], submission)) {
            _agentSubmissions.remove(key);
          }
        }
      },
    );
    return invitation;
  }

  /// Invites [usernames] to the room. Refusals propagate: the server's own
  /// message (a rate limit, no permission) is what the dialog should show.
  Future<VoiceInviteResult> invite(
    String siteUrl,
    int roomId,
    List<String> usernames,
  ) async {
    _userActed();
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final credentials = await _requestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) {
      throw const WriteException(WriteFailure.forbidden);
    }
    final result = await _reporter.runOperation(
      'voice.invite',
      () => credentials.run(
        () => api.invite(
          siteUrl: siteUrl,
          roomId: roomId,
          apiKey: credentials.apiKey!,
          usernames: usernames,
          clientId: credentials.clientId,
        ),
      ),
      correlationId: _correlationForRoom(siteUrl, roomId),
    );
    _record(
      'room.invites.sent',
      component: 'room',
      correlationId: _correlationForRoom(siteUrl, roomId),
      data: {
        'roomId': roomId,
        'invited': result.invitedUsernames.length,
        'skipped': result.skippedUsernames.length,
      },
    );
    return result;
  }

  /// Best effort: an unavailable shortlist leaves the dialog with the
  /// username field and the link.
  Future<List<VoiceInviteSuggestion>> inviteSuggestions(
    String siteUrl,
    int roomId,
  ) => _runPublicValueOperation<List<VoiceInviteSuggestion>>(
    () async {
      final credentials = await _requestCredentials(siteUrl);
      if (credentials == null) return const [];
      return credentials.run(
        () => api.inviteSuggestions(
          siteUrl: siteUrl,
          roomId: roomId,
          apiKey: credentials.apiKey!,
          clientId: credentials.clientId,
        ),
      );
    },
    'voice.inviteSuggestions',
    fallback: const [],
  );

  /// Null when the roster could not be read, so the members dialog keeps
  /// what it shows rather than reading the failure as an empty room.
  Future<List<VoiceMembership>?> memberships(String siteUrl, int roomId) =>
      _runPublicValueOperation<List<VoiceMembership>?>(
        () => _memberships(siteUrl, roomId),
        'voice.memberships',
        fallback: null,
      );

  Future<List<VoiceMembership>?> _memberships(
    String siteUrl,
    int roomId,
  ) async {
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final credentials = await _keyRequestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return null;
    final memberships = await credentials.run(
      () => api.memberships(
        siteUrl: siteUrl,
        roomId: roomId,
        apiKey: credentials.apiKey!,
      ),
    );
    return isCurrent() ? memberships : null;
  }

  /// Null once [username] is a member; otherwise what the members dialog
  /// should say instead.
  Future<String?> addMember(
    String siteUrl,
    int roomId,
    String username,
    VoiceRole role,
  ) => _runMembershipWrite(
    () => _addMember(siteUrl, roomId, username, role),
    'voice.membership.add',
    failure: appL10n.couldnTAddTheMember,
  );

  Future<void> _addMember(
    String siteUrl,
    int roomId,
    String username,
    VoiceRole role,
  ) async {
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final credentials = await _keyRequestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) {
      throw const WriteException(WriteFailure.forbidden);
    }
    await credentials.run(
      () => api.addMembership(
        siteUrl: siteUrl,
        roomId: roomId,
        apiKey: credentials.apiKey!,
        username: username,
        role: role,
      ),
    );
  }

  /// Null once the role changed; otherwise what the members dialog should
  /// say instead.
  Future<String?> updateMember(
    String siteUrl,
    int roomId,
    int membershipId,
    VoiceRole role,
  ) => _runMembershipWrite(
    () => _updateMember(siteUrl, roomId, membershipId, role),
    'voice.membership.update',
    failure: appL10n.couldnTChangeTheMemberSRole,
  );

  Future<void> _updateMember(
    String siteUrl,
    int roomId,
    int membershipId,
    VoiceRole role,
  ) async {
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final credentials = await _keyRequestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) {
      throw const WriteException(WriteFailure.forbidden);
    }
    await credentials.run(
      () => api.updateMembership(
        siteUrl: siteUrl,
        roomId: roomId,
        membershipId: membershipId,
        apiKey: credentials.apiKey!,
        role: role,
      ),
    );
  }

  /// Null once the member is removed; otherwise what the members dialog
  /// should say instead.
  Future<String?> removeMember(String siteUrl, int roomId, int membershipId) =>
      _runMembershipWrite(
        () => _removeMember(siteUrl, roomId, membershipId),
        'voice.membership.remove',
        failure: appL10n.couldnTRemoveTheMember,
      );

  Future<void> _removeMember(
    String siteUrl,
    int roomId,
    int membershipId,
  ) async {
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final credentials = await _keyRequestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) {
      throw const WriteException(WriteFailure.forbidden);
    }
    await credentials.run(
      () => api.removeMembership(
        siteUrl: siteUrl,
        roomId: roomId,
        membershipId: membershipId,
        apiKey: credentials.apiKey!,
      ),
    );
  }

  static _VoiceMediaView _mediaView(VoiceMediaSession media) => (
    connectionState: media.connectionState,
    connectionFailure: media.connectionFailure,
    screenSharing: media.screenSharing,
    localVideoTrack: media.localVideoTrack,
  );

  static bool _sameMediaView(_VoiceMediaView a, _VoiceMediaView b) =>
      a.connectionState == b.connectionState &&
      identical(a.connectionFailure, b.connectionFailure) &&
      a.screenSharing == b.screenSharing &&
      identical(a.localVideoTrack, b.localVideoTrack);

  void _onSystemAction(VoiceSystemCallAction action) {
    _record(
      'callkit.action',
      component: 'callkit',
      correlationId: _correlationFor(_call),
      data: {'action': action.name},
    );
    switch (action) {
      case VoiceSystemCallAction.mute:
        _userActed();
        _observe(
          () => _setMuted(true, syncSystem: false),
          'voice.systemAction.mute',
        );
      case VoiceSystemCallAction.unmute:
        _calls.current?.acknowledgeUnmute();
        _userActed();
        _observe(
          () => _setMuted(false, syncSystem: false),
          'voice.systemAction.unmute',
        );
      case VoiceSystemCallAction.end:
        _observe(
          () => _leave(
            notifyServer: true,
            reason: _VoiceLeaveReason.systemAction,
          ),
          'voice.systemAction.end',
        );
      case VoiceSystemCallAction.answer:
        _observe(_answerFromSystem, 'voice.systemAction.answer');
      case VoiceSystemCallAction.decline:
        declineIncomingCall(fromSystem: true);
    }
  }

  void forget(String siteUrl) {
    _cameraPreferences.removeWhere((account, _) => account.$1 == siteUrl);
    if (_calls.current?.siteUrl == siteUrl) {
      _observe(
        () => _leave(
          notifyServer: true,
          reason: _VoiceLeaveReason.accountRemoval,
        ),
        'voice.accountRemoval',
      );
    }
    _siteSessions.remove(siteUrl);
    final directory = _roomDirectories.remove(siteUrl);
    if (directory != null) {
      _closingDirectories.add(directory);
      unawaited(
        directory.close().whenComplete(
          () => _closingDirectories.remove(directory),
        ),
      );
    }
    _agentPermissions.remove(siteUrl);
    _agentPermissionRequests.remove(siteUrl);
    _agentSubmissions.removeWhere((key, _) => key.$1 == siteUrl);
    _pendingInviteRefs.remove(siteUrl);
    _attachedTrackers.remove(siteUrl);
    final forgottenChats = <_VoiceChatAssociation>[];
    _chats.removeWhere((key, state) {
      if (key.$1 != siteUrl) return false;
      forgottenChats.add(state);
      return true;
    });
    for (final state in forgottenChats) {
      state.retire();
    }
    _cancelTrackerSubscriptions(siteUrl);
    _notifyRoomListChanged();
    if (!_disposed) notifyListeners();
  }

  String _nextCallCorrelationId() {
    return _reporter.newCorrelationId('voice-call');
  }

  String? _correlationFor(VoiceCallSnapshot? call) =>
      call == null ? null : _calls.forMedia(call.media)?.correlationId;

  String? _correlationForSite(String siteUrl) {
    final call = _call;
    return call?.siteUrl == siteUrl ? _correlationFor(call) : null;
  }

  String? _correlationForRoom(String siteUrl, int roomId) {
    final call = _call;
    return call?.siteUrl == siteUrl && call?.room.id == roomId
        ? _correlationFor(call)
        : null;
  }

  String? get _activeDiagnosticCorrelationId {
    final active = _correlationFor(_call);
    if (active != null) return active;
    return _calls.leavingCorrelationId;
  }

  void _record(
    String event, {
    String component = 'controller',
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? correlationId,
    Map<String, Object?> data = const {},
  }) {
    try {
      diagnostics.record(
        event,
        component: component,
        severity: severity,
        correlationId: correlationId,
        data: data,
      );
    } catch (_) {}
  }

  void _recordRaw(
    String event, {
    String component = 'controller',
    DiagnosticSeverity severity = DiagnosticSeverity.debug,
    String? correlationId,
    String? message,
    Map<String, Object?> data = const {},
  }) {
    try {
      if (!diagnostics.captureEnabled) return;
      diagnostics.recordRaw(
        event,
        component: component,
        severity: severity,
        correlationId: correlationId,
        message: message,
        data: data,
      );
    } catch (_) {}
  }

  Map<String, Object?> _roomDiagnosticData(VoiceRoom room) => {
    'roomId': room.id,
    'roomType': room.type.name,
    'participantCount': room.participants.length,
  };

  Map<String, Object?> _rawRoomDiagnosticData(
    String siteUrl,
    VoiceRoom room, {
    String? siteName,
  }) => {
    'siteUrl': siteUrl,
    'siteName': ?siteName,
    'roomId': room.id,
    'roomName': room.name,
    'roomSlug': room.slug,
    'roomType': room.type.name,
    'participantCount': room.participants.length,
  };

  void _recordRoster(
    String event,
    String siteUrl,
    int roomId,
    List<VoiceParticipant> participants, {
    String? correlationId,
  }) {
    _recordRaw(
      event,
      component: 'roster',
      correlationId: correlationId,
      data: {
        'siteUrl': siteUrl,
        'roomId': roomId,
        'participants': [
          for (final participant in participants)
            {
              'id': participant.id,
              'username': participant.username,
              'name': participant.name,
              'avatarTemplate': participant.avatarTemplate,
              'role': participant.role.name,
              'muted': participant.muted,
              'deafened': participant.deafened,
              'videoOn': participant.videoOn,
              'screenSharing': participant.screenSharing,
              'watchingVideo': participant.watchingVideo,
              'idleState': participant.idleState.name,
              'handRaisedAt': participant.handRaisedAt
                  ?.toUtc()
                  .toIso8601String(),
            },
        ],
      },
    );
  }

  void _report(
    Object error,
    StackTrace stackTrace,
    String operation, {
    String? correlationId,
  }) {
    final effectiveCorrelationId =
        correlationId ??
        _activeDiagnosticCorrelationId ??
        _reporter.currentCorrelationId;
    _record(
      'runtime.error',
      severity: DiagnosticSeverity.warning,
      correlationId: effectiveCorrelationId,
      data: {'operation': operation, 'errorType': error.runtimeType.toString()},
    );
    _recordRaw(
      'runtime.error_detail',
      severity: DiagnosticSeverity.warning,
      correlationId: effectiveCorrelationId,
      message: error.toString(),
      data: {'operation': operation, 'stackTrace': stackTrace.toString()},
    );
    try {
      _reporter.reportError(
        _VoiceDiagnosticFailure(
          operation: operation,
          errorType: error.runtimeType.toString(),
        ),
        stackTrace,
        operation: operation,
        source: 'voice',
        severity: DiagnosticSeverity.warning,
        handled: true,
        degraded: true,
        correlationId: effectiveCorrelationId,
      );
    } catch (_) {}
  }

  void _observe(Future<void> Function() action, String operation) {
    unawaited(_runHandled(action, operation));
  }

  Future<void> _runHandled(
    Future<void> Function() action,
    String operation, {
    String? correlationId,
  }) async {
    try {
      await action();
    } catch (error, stackTrace) {
      _report(error, stackTrace, operation, correlationId: correlationId);
    }
  }

  Future<T> _runHandledValue<T>(
    Future<T> Function() action,
    String operation, {
    required T fallback,
  }) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      _report(error, stackTrace, operation);
      return fallback;
    }
  }

  Future<void> _runPublicOperation(
    Future<void> Function() action,
    String operation, {
    String? correlationId,
  }) => _runHandled(action, operation, correlationId: correlationId);

  Future<T> _runPublicValueOperation<T>(
    Future<T> Function() action,
    String operation, {
    required T fallback,
    String? correlationId,
  }) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      _report(error, stackTrace, operation, correlationId: correlationId);
      return fallback;
    }
  }

  /// Contained like any public operation, but answers with what the user
  /// should be told: the server's own refusal, or [failure]. The error's
  /// private cause stays behind the diagnostics boundary.
  Future<String?> _runMembershipWrite(
    Future<void> Function() action,
    String operation, {
    required String failure,
  }) async {
    try {
      await action();
      return null;
    } catch (error, stackTrace) {
      _report(error, stackTrace, operation);
      return error is WriteException ? error.message : failure;
    }
  }

  /// Closes the complete native session and resolves only after every owned
  /// asynchronous teardown boundary has settled.
  ///
  /// [ChangeNotifier.dispose] cannot expose that completion to callers, so the
  /// plugin lifecycle uses this method while widget-owned callers can retain
  /// the ordinary synchronous [dispose] contract.
  Future<void> close() {
    final active = _closeOperation;
    if (active != null) return active;

    _disposed = true;
    _agentPermissionRevision.dispose();
    _calls.retire();
    _roomVideoWatchers.clear();
    _pendingInviteRefs.clear();
    _attachedTrackers.clear();
    for (final state in _chats.values) {
      state.retire();
    }
    _chats.clear();
    unawaited(_notices.close());
    final subscriptionCancellation = _cancelSubscriptions();

    final systemActionsCancellation = _runHandled(
      _systemActions.cancel,
      'voice.systemActions.dispose',
    );
    final operation = _finishClose(
      systemActionsCancellation,
      subscriptionCancellation,
    );
    _closeOperation = operation;

    // Detach UI listeners synchronously, matching ChangeNotifier's disposal
    // contract even when the caller intentionally does not await [close].
    _roomListChanges.dispose();
    super.dispose();
    return operation;
  }

  Future<void> _cancelSubscriptions() {
    final subscriptions = <PluginLiveChannelSubscription>[
      ..._ringSubscriptions.values,
    ];
    _ringSubscriptions.clear();
    _clearIncomingCall(tellSystem: VoiceIncomingCallEndReason.unanswered);
    final directories = [..._roomDirectories.values, ..._closingDirectories];
    _roomDirectories.clear();
    return Future.wait([
      for (final directory in directories) directory.close(),
      for (final subscription in subscriptions)
        _cancelSubscription(subscription),
    ]);
  }

  Future<void> _cancelSubscription(
    PluginLiveChannelSubscription subscription,
  ) async {
    try {
      if (subscription case final VoiceAwaitableSubscriptionTeardown value) {
        await value.cancelAndWait();
      } else {
        subscription.cancel();
      }
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'voice.subscription.dispose');
    }
  }

  Future<void> _finishClose(
    Future<void> systemActionsCancellation,
    Future<void> subscriptionCancellation,
  ) async {
    _record('session.close.started', component: 'lifecycle');

    await _runHandled(_calls.close, 'voice.session.leave');
    await subscriptionCancellation;
    await systemActionsCancellation;
    await _runHandled(systemCall.dispose, 'voice.systemCall.dispose');

    _record('session.close.completed', component: 'lifecycle');
    if (diagnostics case final VoiceDiagnosticsFlusher flusher) {
      await _runHandled(flusher.flushDiagnostics, 'voice.diagnostics.flush');
    }
  }

  // [close] invokes ChangeNotifier's synchronous disposal before returning its
  // asynchronous teardown future.
  @override
  // ignore: must_call_super
  void dispose() {
    unawaited(close());
  }
}

final class _VoiceInviteRef {
  const _VoiceInviteRef({required this.roomSlug, required this.username});

  final String roomSlug;
  final String username;
}
