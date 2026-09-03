// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'voice_api.dart';
import 'voice_callkit.dart';
import 'voice_diagnostics.dart';
import 'voice_idle.dart';
import 'voice_media.dart';
import 'voice_models.dart';
import 'voice_preferences.dart';
import 'voice_settings.dart';
import 'voice_signaling.dart';

enum VoiceCallStatus { joining, connected, reconnecting, leaving, failed }

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
  String toString() => 'Voice operation $operation failed ($errorType).';
}

final class _VoiceParticipantSession {
  _VoiceParticipantSession(this.id);

  String? id;
}

String _joinFailureMessage(Object error, VoiceRoom room) {
  if (error is WriteException) return error.message;
  if (error is VoiceMicrophoneException) {
    return switch (error.kind) {
      VoiceMicrophoneFailureKind.permissionDenied =>
        'Microphone access is blocked. Allow microphone access in your '
            'system settings, then try joining again.',
      VoiceMicrophoneFailureKind.unavailable =>
        "We couldn't access your microphone. Check that it is connected and "
            'not in use by another app, then try again.',
    };
  }
  return "Couldn't join ${room.name}.";
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

final class _VoiceChatAssociation {
  _VoiceChatAssociation({this.session = const VoiceChatSession()});

  VoiceChatSession session;
  ChatConversation? conversation;
  VoidCallback? conversationListener;

  /// The room's chat channel, watched while the panel is open: the server
  /// publishes a content-free "updated" there when the session's thread
  /// changes (someone's first message opened it, or it rolled over).
  PluginLiveChannelSubscription? liveUpdates;
  bool visible = false;
  bool loading = false;
  bool sending = false;
  String? error;
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
/// once and never persisted; a surface that is not showing the room may drop
/// it.
@immutable
final class VoiceNotice {
  const VoiceNotice(
    this.message, {
    required this.siteUrl,
    required this.roomId,
  });

  final String message;
  final String siteUrl;
  final int roomId;
}

/// At most this many rooms reached by link (rather than listed in the
/// directory) keep a live subscription per site. Direct-call rooms are the
/// usual case: they never appear in the directory, and the server reaps them
/// once empty, so nothing else would ever release their channel.
const _maxLinkedRoomsPerSite = 8;

typedef VoiceTrackerLookup = PluginLiveChannelHandle? Function(String siteUrl);
typedef VoiceSiteFlagReader = bool Function(String siteUrl);
typedef VoiceSiteNameLookup = String? Function(String siteUrl);
typedef VoiceIncomingCallAnswered =
    void Function(String siteUrl, VoiceRoom room);
typedef VoiceUserIdLookup = int? Function(String siteUrl);
typedef VoiceCapabilityResolver = Future<bool?> Function(String siteUrl);
typedef _VoiceRequestCredentials = ({String apiKey, String clientId});

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
       _timerFactory = timerFactory ?? Timer.new,
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
    _idleTracker = VoiceIdleTracker(
      thresholds: _activeIdleThresholds,
      onStateChanged: _onIdleStateChanged,
      onAutoMute: _onIdleAutoMute,
      onDisconnect: _onIdleDisconnect,
      clock: idleClock,
      timerFactory: _timerFactory,
    );
    _systemActions = this.systemCall.actions.listen(_onSystemAction);
    unawaited(_restoreDevicePreferences());
    unawaited(_restoreAutoStatusPreference());
  }

  static VoiceIdleThresholds _defaultIdleThresholds(String _) =>
      voiceIdleThresholds(const VoiceClientConfig());

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
  final VoiceIdleTimerFactory _timerFactory;
  final DateTime Function() _clock;
  final VoiceSiteNameLookup? _siteNameFor;
  final VoiceSiteFlagReader? _meshPrivacyWarningEnabledFor;
  final VoiceIncomingCallAnswered? _onIncomingCallAnswered;
  late final VoiceIdleTracker _idleTracker;
  final Map<String, PluginLiveChannelSubscription> _ringSubscriptions = {};
  final Set<String> _handledRings = {};
  ({String siteUrl, VoiceIncomingCall call})? _incomingCall;
  Timer? _incomingCallExpiry;
  bool _incomingCallSystemPresented = false;
  final Duration heartbeatInterval;
  final Duration signalBatchDelay;
  // Cancelled and awaited by the idempotent close lifecycle below.
  // ignore: cancel_subscriptions
  late final StreamSubscription<VoiceSystemCallAction> _systemActions;

  final Map<String, VoiceDirectory> _directories = {};
  final Map<String, PluginLiveChannelHandle> _attachedTrackers = {};
  final Map<String, Map<int, VoiceRoom>> _linkedRooms = {};
  final Set<String> _loadingSites = {};
  final Set<String> _unavailableSites = {};
  final Map<String, PluginLiveChannelSubscription> _directorySubscriptions = {};
  final Map<String, Map<int, PluginLiveChannelSubscription>>
  _roomSubscriptions = {};
  final Map<String, _VoiceLiveCursors> _liveCursors = {};
  final Map<String, String> _errors = {};
  final Map<String, _VoiceChatAssociation> _chats = {};
  final Map<String, Object> _siteSessions = {};
  final Map<String, Object> _directoryRequests = {};
  final Map<String, Object> _chatRequests = {};
  final Map<String, _VoiceInviteRef> _pendingInviteRefs = {};
  final Map<String, int> _roomVideoWatchers = {};
  final StreamController<VoiceNotice> _notices =
      StreamController<VoiceNotice>.broadcast();
  Future<void>? _joinTail;
  Future<void>? _pendingJoin;
  String? _pendingJoinKey;
  String? _pendingJoinCorrelationId;
  Object? _pendingJoinSession;
  Future<void>? _stateSync;
  Timer? _stateRetry;
  bool _stateSyncPending = false;
  Object? _joinRevision;
  Future<void>? _leaveOperation;
  VoiceMediaSession? _leavingMedia;
  Future<void>? _closeOperation;
  final Expando<Future<void>> _mediaDisposals = Expando<Future<void>>();
  final Expando<String> _mediaCorrelations = Expando<String>();
  final Expando<_VoiceParticipantSession> _participantSessions =
      Expando<_VoiceParticipantSession>();
  final Expando<VoiceSignalBatcher> _signalBatchers =
      Expando<VoiceSignalBatcher>();
  Timer? _heartbeat;
  Future<void>? _heartbeatRequest;
  bool _heartbeatPending = false;
  VoiceIdleState _idleState = VoiceIdleState.active;
  VoiceCallSnapshot? _call;
  bool _disposed = false;
  String? _audioInputDeviceId;
  String? _audioOutputDeviceId;
  String? _cameraDeviceId;
  bool _pushToTalkEnabled = false;
  bool _autoStatusEnabled = true;

  VoiceCallSnapshot? get call => _call;
  String? get activeSiteUrl => _call?.siteUrl;
  bool get hasCall => _call != null;
  bool get supportedPlatform =>
      Platform.isIOS || Platform.isMacOS || Platform.isLinux;
  String? get audioInputDeviceId => _audioInputDeviceId;
  String? get audioOutputDeviceId => _audioOutputDeviceId;
  String? get cameraDeviceId => _cameraDeviceId;
  bool get pushToTalkEnabled => _pushToTalkEnabled;

  /// Whether joining a room sets the user's status to it (when the site
  /// allows it). A per-device choice, like the web client's.
  bool get autoStatusEnabled => _autoStatusEnabled;

  Future<void> setAutoStatusEnabled(bool enabled) async {
    if (_disposed) return;
    _autoStatusEnabled = enabled;
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

  Stream<VoiceNotice> get notices => _notices.stream;

  /// The direct call ringing this user right now, if any. Cleared when it
  /// is answered, declined, or has run out.
  VoiceIncomingCall? get incomingCall => _incomingCall?.call;

  String? get incomingCallSiteUrl => _incomingCall?.siteUrl;

  /// The system (CallKit) is ringing for [incomingCall], so the app's own
  /// banner would only duplicate it; the answer arrives as a system action.
  bool get incomingCallHandledBySystem =>
      _incomingCall != null && _incomingCallSystemPresented;

  /// Starts a direct call to [username] on [siteUrl]. The server answers
  /// with the ephemeral call room, which is held beside the directory so
  /// its roster and signals arrive; the caller then joins it like any room.
  /// Failures surface to the caller: the server explains a refusal (a user
  /// who cannot be called, too many calls) in its own words.
  Future<VoiceRoom> callUser(String siteUrl, String username) async {
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final credentials = await _requestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) {
      throw const WriteException(WriteFailure.forbidden);
    }
    final room = await _reporter.runOperation(
      'voice.call',
      () => api.callUser(
        siteUrl: siteUrl,
        apiKey: credentials.apiKey,
        username: username,
        clientId: credentials.clientId,
      ),
    );
    if (!isCurrent()) return room;
    _record('call.direct.started', data: {..._roomDiagnosticData(room)});
    _rememberLinkedRoom(siteUrl, room);
    _syncSubscriptions(siteUrl);
    notifyListeners();
    return room;
  }

  /// Takes the ringing call: the room is resolved (and held) so the caller
  /// can open and join it. Joining through the invite ref credits the
  /// caller, the same as joining from the notification link.
  Future<({String siteUrl, VoiceRoom room})?> acceptIncomingCall({
    bool fromSystem = false,
  }) async {
    final incoming = _incomingCall;
    if (incoming == null) return null;
    final presented = _incomingCallSystemPresented;
    _clearIncomingCall();
    _record(
      'call.ring.answered',
      data: {'roomId': incoming.call.roomId, 'fromSystem': fromSystem},
    );
    if (presented && !fromSystem) {
      // The system is still ringing; its call becomes the active one so the
      // join below does not place a second call.
      await _runHandled(
        systemCall.answerIncomingCall,
        'voice.systemCall.answerIncoming',
      );
    }
    rememberInviteRef(
      siteUrl: incoming.siteUrl,
      roomSlug: incoming.call.roomSlug,
      username: incoming.call.caller.username.toLowerCase(),
    );
    final room = await resolveRoom(incoming.siteUrl, incoming.call.roomSlug);
    if (room == null) return null;
    return (siteUrl: incoming.siteUrl, room: room);
  }

  void declineIncomingCall({bool fromSystem = false}) {
    final incoming = _incomingCall;
    if (incoming == null) return;
    final presented = _incomingCallSystemPresented;
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
    _incomingCallExpiry?.cancel();
    _incomingCallExpiry = null;
    _incomingCall = null;
    final presented = _incomingCallSystemPresented;
    _incomingCallSystemPresented = false;
    if (presented && tellSystem != null) {
      _observe(
        () => systemCall.endIncomingCall(tellSystem),
        'voice.systemCall.endIncoming',
      );
    }
  }

  /// A ring the system may present too: the phone rings with the system
  /// ringtone and on the lock screen, and answering or declining there
  /// comes back as a system action. When the system declines to (no
  /// system call UI on this platform, a call already up, the ring already
  /// over), the app's own banner stays.
  Future<void> _presentIncomingCall(
    String siteUrl,
    VoiceIncomingCall call,
  ) async {
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
    final current = _incomingCall;
    if (current == null ||
        current.siteUrl != siteUrl ||
        current.call.key != call.key) {
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
    if (presented != _incomingCallSystemPresented) {
      _incomingCallSystemPresented = presented;
      notifyListeners();
    }
  }

  /// The user answered from the system's call UI. There is no app surface
  /// to ask anything on (the app may be behind the lock screen), so the
  /// join proceeds directly; a peer-to-peer privacy warning the site would
  /// have shown before a join is said afterwards instead.
  Future<void> _answerFromSystem() async {
    final accepted = await acceptIncomingCall(fromSystem: true);
    if (accepted == null) {
      _record(
        'call.ring.system_answer.unresolved',
        severity: DiagnosticSeverity.warning,
      );
      await _runHandled(systemCall.failed, 'voice.systemCall.failed');
      return;
    }
    final (:siteUrl, :room) = accepted;
    _onIncomingCallAnswered?.call(siteUrl, room);
    if ((_meshPrivacyWarningEnabledFor?.call(siteUrl) ?? false) &&
        room.expectedTransport == VoiceTransport.mesh &&
        !await meshPrivacyAcknowledged()) {
      _notify(
        siteUrl,
        room.id,
        'This call connects participants directly, so other participants '
        'may be able to see your IP address.',
      );
    }
    await join(
      siteUrl: siteUrl,
      siteName: _siteNameFor?.call(siteUrl) ?? siteUrl,
      room: room,
    );
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
    _clearIncomingCall(tellSystem: VoiceIncomingCallEndReason.unanswered);
    _incomingCall = (siteUrl: siteUrl, call: call);
    _incomingCallExpiry = _timerFactory(remaining, () {
      _incomingCallExpiry = null;
      if (_incomingCall?.call.key != call.key) return;
      _record('call.ring.expired', data: {'roomId': call.roomId});
      _clearIncomingCall(tellSystem: VoiceIncomingCallEndReason.unanswered);
      if (!_disposed) notifyListeners();
    });
    notifyListeners();
    unawaited(_presentIncomingCall(siteUrl, call));
  }

  void _notify(String siteUrl, int roomId, String message) {
    if (_disposed || _notices.isClosed) return;
    _notices.add(VoiceNotice(message, siteUrl: siteUrl, roomId: roomId));
  }

  void watchRoomVideo({required String siteUrl, required int roomId}) {
    if (_disposed) return;
    final key = '$siteUrl#$roomId';
    final previous = _roomVideoWatchers[key] ?? 0;
    _roomVideoWatchers[key] = previous + 1;
    if (previous == 0 && _isCurrentWatchedRoom(siteUrl, roomId)) {
      unawaited(_requestStateSync());
    }
  }

  void stopWatchingRoomVideo({required String siteUrl, required int roomId}) {
    if (_disposed) return;
    final key = '$siteUrl#$roomId';
    final previous = _roomVideoWatchers[key] ?? 0;
    if (previous <= 1) {
      _roomVideoWatchers.remove(key);
      if (previous == 1 && _isCurrentWatchedRoom(siteUrl, roomId)) {
        unawaited(_requestStateSync());
      }
    } else {
      _roomVideoWatchers[key] = previous - 1;
    }
  }

  bool _isCurrentWatchedRoom(String siteUrl, int roomId) =>
      _call?.siteUrl == siteUrl && _call?.room.id == roomId;

  bool _isWatching(VoiceCallSnapshot call) =>
      (_roomVideoWatchers['${call.siteUrl}#${call.room.id}'] ?? 0) > 0;

  VoiceDirectory? directory(String siteUrl) => _directories[siteUrl];
  String? errorFor(String siteUrl) => _errors[siteUrl];
  bool isLoading(String siteUrl) => _loadingSites.contains(siteUrl);
  VoiceChatSnapshot? chat(String siteUrl, int roomId) {
    final state = _chats['$siteUrl#$roomId'];
    if (state == null) return null;
    final conversation = state.conversation?.value;
    return VoiceChatSnapshot(
      session: state.session,
      messages: conversation?.messages ?? const [],
      loading: state.loading || (conversation?.loading ?? false),
      sending: state.sending || (conversation?.sending ?? false),
      canLoadMorePast: conversation?.canLoadMorePast ?? false,
      error: state.error ?? conversation?.error,
    );
  }

  VoiceRoom? room(String siteUrl, int roomId) {
    for (final room in _directories[siteUrl]?.rooms ?? const <VoiceRoom>[]) {
      if (room.id == roomId) return room;
    }
    final call = _call;
    if (call?.siteUrl == siteUrl && call?.room.id == roomId) return call?.room;
    return _linkedRooms[siteUrl]?[roomId];
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

  Future<VoiceRoom?> _resolveRoom(String siteUrl, String slug) async {
    if (_unavailableSites.contains(siteUrl)) return null;
    final capabilityEnabled = await _capabilityEnabledFor(siteUrl);
    if (capabilityEnabled == false) return null;
    final directory = _directories[siteUrl];
    for (final room in directory?.rooms ?? const <VoiceRoom>[]) {
      if (room.slug == slug) return room;
    }
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    try {
      final credentials = await _requestCredentials(
        siteUrl,
        ifCurrent: isCurrent,
      );
      if (credentials == null) return null;
      final room = await api.room(
        siteUrl: siteUrl,
        slug: slug,
        apiKey: credentials.apiKey,
        clientId: credentials.clientId,
      );
      if (!isCurrent()) return null;
      _rememberLinkedRoom(siteUrl, room);
      _syncSubscriptions(siteUrl);
      notifyListeners();
      return room;
    } catch (error, stackTrace) {
      if (isCurrent()) _report(error, stackTrace, 'voice.room');
      return null;
    }
  }

  /// A room reached by link is held (and subscribed) beside the directory
  /// so its roster and signals arrive like any listed room's. Bounded: the
  /// oldest link goes first, but never the room of the active call.
  void _rememberLinkedRoom(String siteUrl, VoiceRoom room) {
    final linked = _linkedRooms[siteUrl] ??= {};
    linked.remove(room.id);
    linked[room.id] = room;
    final call = _call;
    final protectedId = call?.siteUrl == siteUrl ? call?.room.id : null;
    for (final id in linked.keys.toList()) {
      if (linked.length <= _maxLinkedRoomsPerSite) break;
      if (id == room.id || id == protectedId) continue;
      linked.remove(id);
    }
  }

  Future<void> ensureLoaded(String siteUrl, {bool force = false}) =>
      _runPublicOperation(
        () => _ensureLoaded(siteUrl, force: force),
        'voice.directory',
      );

  Future<void> _ensureLoaded(String siteUrl, {bool force = false}) async {
    if (!supportedPlatform) return;
    if (_disposed ||
        _loadingSites.contains(siteUrl) ||
        _unavailableSites.contains(siteUrl)) {
      return;
    }
    if (!force && _directories.containsKey(siteUrl)) {
      attachTracker(siteUrl);
      return;
    }
    _record(
      'room.directory.load_started',
      component: 'room',
      data: {'force': force},
    );
    _recordRaw(
      'room.directory.load_context',
      component: 'room',
      data: {'siteUrl': siteUrl},
    );
    final siteSession = _siteSession(siteUrl);
    final request = Object();
    _directoryRequests[siteUrl] = request;
    bool isCurrent() =>
        _isCurrentSiteSession(siteUrl, siteSession) &&
        identical(_directoryRequests[siteUrl], request);
    final capabilityEnabled = await _capabilityEnabledFor(siteUrl);
    if (!isCurrent()) return;
    if (capabilityEnabled == false) {
      _directories.remove(siteUrl);
      _pruneChatAssociations(siteUrl, const {});
      _directoryRequests.remove(siteUrl);
      _record('room.directory.skipped', component: 'room');
      notifyListeners();
      return;
    }
    final credentials = await _requestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) {
      if (!isCurrent()) return;
      forget(siteUrl);
      return;
    }
    _loadingSites.add(siteUrl);
    _errors.remove(siteUrl);
    notifyListeners();
    if (!isCurrent()) return;
    try {
      final directory = await api.rooms(
        siteUrl: siteUrl,
        apiKey: credentials.apiKey,
        clientId: credentials.clientId,
      );
      if (!isCurrent()) return;
      _directories[siteUrl] = directory;
      _pruneChatAssociations(siteUrl, {
        for (final room in directory.rooms) room.id,
      });
      _record(
        'room.directory.load_completed',
        component: 'room',
        data: {'roomCount': directory.rooms.length},
      );
      _syncSubscriptions(siteUrl);
    } on SiteLookupException catch (error, stackTrace) {
      if (!isCurrent()) return;
      // Plugin absence and account refusal both mean no section for this site
      // session. Remember that negative capability so every later activation
      // does not probe the same missing route again. Network, rate-limit, 5xx,
      // and parse failures stay retryable without claiming the plugin exists.
      if (_isUnavailableDirectoryFailure(error)) {
        _directories.remove(siteUrl);
        _pruneChatAssociations(siteUrl, const {});
        _unavailableSites.add(siteUrl);
      } else {
        _errors[siteUrl] = "Couldn't load voice rooms.";
        _report(error, stackTrace, 'voice.directory');
      }
    } catch (error, stackTrace) {
      if (!isCurrent()) return;
      _errors[siteUrl] = "Couldn't load voice rooms.";
      _report(error, stackTrace, 'voice.directory');
    } finally {
      if (isCurrent()) {
        _directoryRequests.remove(siteUrl);
        _loadingSites.remove(siteUrl);
        notifyListeners();
      }
    }
  }

  static bool _isUnavailableDirectoryFailure(SiteLookupException error) =>
      error.failure == SiteLookupFailure.notDiscourse ||
      error.statusCode == HttpStatus.notFound;

  Object _siteSession(String siteUrl) =>
      _siteSessions.putIfAbsent(siteUrl, Object.new);

  Future<_VoiceRequestCredentials?> _requestCredentials(
    String siteUrl, {
    bool Function()? ifCurrent,
  }) async {
    final snapshot = await _requests.credentialsFor(siteUrl);
    if (ifCurrent != null && !ifCurrent()) return null;
    final apiKey = snapshot.apiKey;
    return apiKey == null
        ? null
        : (apiKey: apiKey, clientId: snapshot.clientId);
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
    _syncSubscriptions(siteUrl);
  }

  PluginLiveChannelHandle? _trackerFor(String siteUrl) =>
      _attachedTrackers[siteUrl] ?? trackerFor(siteUrl);

  void _cancelTrackerSubscriptions(String siteUrl) {
    _directorySubscriptions.remove(siteUrl)?.cancel();
    _ringSubscriptions.remove(siteUrl)?.cancel();
    for (final entry in _chats.entries) {
      if (entry.key.startsWith('$siteUrl#')) _unwatchChatUpdates(entry.value);
    }
    if (_incomingCall?.siteUrl == siteUrl) {
      _clearIncomingCall(tellSystem: VoiceIncomingCallEndReason.unanswered);
    }
    for (final subscription
        in _roomSubscriptions.remove(siteUrl)?.values ??
            const <PluginLiveChannelSubscription>[]) {
      subscription.cancel();
    }
  }

  /// Every room this controller holds for the site: the directory listing,
  /// rooms reached by link, and the active call's room. A direct call's
  /// ephemeral room is in none of the first two until it is linked or
  /// joined, and the directory never lists it at all.
  Map<int, VoiceRoom> _heldRooms(String siteUrl) => {
    for (final room in _directories[siteUrl]?.rooms ?? const <VoiceRoom>[])
      room.id: room,
    for (final room in _linkedRooms[siteUrl]?.values ?? const <VoiceRoom>[])
      room.id: room,
    if (_call case final call? when call.siteUrl == siteUrl)
      call.room.id: call.room,
  };

  /// Brings the site's subscriptions in line with what it holds: the index
  /// (once a directory has loaded) and every held room without one are
  /// subscribed, rooms no longer held are cancelled. A live subscription
  /// keeps its own position on the wire and is never replaced here:
  /// re-subscribing from the snapshot cursor would replay every message
  /// published since the load, and each replay would arrive in
  /// [_onDirectoryEvent] to trigger the next. Subscriptions are replaced only
  /// with the tracker ([attachTracker]) and dropped only with the site
  /// ([forget]).
  void _syncSubscriptions(String siteUrl) {
    final tracker = _trackerFor(siteUrl);
    if (tracker == null) return;
    final cursors = _liveCursors.putIfAbsent(siteUrl, _VoiceLiveCursors.new);
    var changed = false;
    final directory = _directories[siteUrl];
    if (directory != null && !_directorySubscriptions.containsKey(siteUrl)) {
      _directorySubscriptions[siteUrl] = tracker.subscribe(
        '/voice/rooms/index',
        (data, messageId) => _onDirectoryEvent(siteUrl, data, messageId),
        lastId: cursors.directoryCursor(directory.messageBusLastId),
      );
      changed = true;
    }
    // Rings arrive whether or not any Voice surface is on screen, so the
    // per-user ring channel is watched as soon as the site has a tracker.
    final userId = _userIdFor(siteUrl);
    if (userId != null && !_ringSubscriptions.containsKey(siteUrl)) {
      _ringSubscriptions[siteUrl] = tracker.subscribe(
        '/voice/call-ring/$userId',
        (data, _) => _onRingEvent(siteUrl, data),
      );
      changed = true;
    }
    final subscriptions = _roomSubscriptions.putIfAbsent(siteUrl, () => {});
    final wanted = _heldRooms(siteUrl);
    for (final id
        in subscriptions.keys.where((id) => !wanted.containsKey(id)).toList()) {
      subscriptions.remove(id)?.cancel();
      cursors.dropRoom(id);
      changed = true;
    }
    for (final room in wanted.values) {
      if (subscriptions.containsKey(room.id)) continue;
      subscriptions[room.id] = tracker.subscribe(
        '/voice/rooms/${room.id}',
        (data, messageId) => _onRoomEvent(siteUrl, room.id, data, messageId),
        lastId: cursors.roomCursor(room.id, room.messageBusLastId),
      );
      changed = true;
    }
    for (final entry in _chats.entries) {
      if (!entry.key.startsWith('$siteUrl#') || !entry.value.visible) continue;
      final roomId = int.tryParse(entry.key.substring(siteUrl.length + 1));
      if (roomId == null) continue;
      _watchChatUpdates(siteUrl, roomId, entry.key, entry.value);
    }
    if (!changed) return;
    _record(
      'room.subscriptions.synced',
      component: 'room',
      correlationId: _correlationForSite(siteUrl),
      data: {'roomCount': wanted.length},
    );
  }

  void _onDirectoryEvent(String siteUrl, Object? data, int messageId) {
    if (_disposed) return;
    // A delivered message is consumed whether or not its payload is
    // understood; the cursor moves so a replacement tracker is not handed it
    // again.
    _liveCursors[siteUrl]?.directoryDelivered(messageId);
    if (data is! Map<String, dynamic>) return;
    final rawRoom = data['room'];
    if (rawRoom is! Map<String, dynamic>) return;
    final incoming = VoiceRoom.fromJson(rawRoom);
    final call = _call;
    _record(
      'room.directory_event',
      component: 'room',
      correlationId: call?.siteUrl == siteUrl && call?.room.id == incoming.id
          ? _correlationFor(call)
          : null,
      data: {
        ..._roomDiagnosticData(incoming),
        'type': _voiceDirectoryDiagnosticType(data['type']),
      },
    );
    final held = _directories[siteUrl];
    if (held == null) return;
    final rooms = [...held.rooms];
    final index = rooms.indexWhere((room) => room.id == incoming.id);
    switch (data['type']) {
      case 'created':
        if (index < 0) rooms.add(incoming);
      case 'updated':
        if (index < 0) {
          rooms.add(incoming);
        } else {
          rooms[index] = _preservePrivilegedFields(rooms[index], incoming);
        }
        _refreshCallRoom(siteUrl, incoming);
      case 'destroyed':
        rooms.removeWhere((room) => room.id == incoming.id);
        _linkedRooms[siteUrl]?.remove(incoming.id);
        _removeChatAssociation(siteUrl, incoming.id);
        if (_call case final call?
            when call.siteUrl == siteUrl && call.room.id == incoming.id) {
          _observe(
            () => _leave(
              notifyServer: false,
              reason: _VoiceLeaveReason.roomDestroyed,
            ),
            'voice.roomDestroyed',
          );
        }
      default:
        return;
    }
    _directories[siteUrl] = VoiceDirectory(
      rooms: List.unmodifiable(rooms),
      canCreateRoom: held.canCreateRoom,
      messageBusLastId: held.messageBusLastId,
    );
    _syncSubscriptions(siteUrl);
    notifyListeners();
  }

  static VoiceRoom _preservePrivilegedFields(
    VoiceRoom held,
    VoiceRoom incoming,
  ) => incoming.copyWithPrivileged(held);

  /// A room edited while its call is up: the call keeps its own roster and
  /// ring state (the room channel is the authority for those) but takes the
  /// new name, type, and capabilities. A type change re-applies the stage
  /// speaking rule, and video that the room no longer allows stops now
  /// rather than at the next toggle.
  void _refreshCallRoom(String siteUrl, VoiceRoom incoming) {
    final call = _call;
    if (call == null ||
        call.siteUrl != siteUrl ||
        call.room.id != incoming.id) {
      return;
    }
    final room = _preservePrivilegedFields(call.room, incoming).copyWith(
      participants: call.room.participants,
      ringing: call.room.ringing,
    );
    final userId = _userIdFor(siteUrl);
    final couldPublishAudio =
        userId == null ||
        _canPublishAudio(call.room, call.room.participants, userId);
    final canPublishAudio =
        userId == null || _canPublishAudio(room, room.participants, userId);
    final canPublishVideo = canPublishAudio && room.videoAllowed;
    final stopsVideo =
        !canPublishVideo && (call.cameraEnabled || call.screenSharing);
    _call = call.copyWith(room: room, muted: canPublishAudio ? null : true);
    if (canPublishAudio != couldPublishAudio) {
      _observe(() async {
        await _runHandled(
          () => call.media.setAudioPublishingAllowed(canPublishAudio),
          'voice.media.audioPublishing',
        );
        if (!canPublishAudio) {
          await _runHandled(
            () => call.media.setMuted(true),
            'voice.media.rosterMute',
          );
        }
      }, 'voice.media.roomUpdate');
    }
    if (stopsVideo) {
      _record(
        'media.video.room_disallowed',
        component: 'media',
        correlationId: _correlationFor(call),
        data: {'roomId': room.id},
      );
      _observe(() async {
        if (call.cameraEnabled) await _setCameraEnabled(false);
        if (call.screenSharing) await _setScreenSharing(false);
      }, 'voice.media.roomVideoDisabled');
      _notify(siteUrl, room.id, 'Video was turned off in this room.');
    }
  }

  void _onRoomEvent(String siteUrl, int roomId, Object? data, int messageId) {
    if (_disposed) return;
    _liveCursors[siteUrl]?.roomDelivered(roomId, messageId);
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
          siteUrl,
          roomId,
          event.role == VoiceRole.participant
              ? "You've been moved to listeners."
              : "You've been made a speaker.",
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
            _notify(siteUrl, roomId, 'This call is now being recorded.');
          }
        } else if (wasRecording) {
          _notify(siteUrl, roomId, 'The recording has stopped.');
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
        _notify(siteUrl, roomId, 'Your request to speak was dismissed.');
      }
    } else if (inCall && event.raised && (held?.canManage ?? false)) {
      final raiser = held?.participants
          .where((participant) => participant.id == event.userId)
          .firstOrNull;
      if (raiser != null) {
        _notify(
          siteUrl,
          roomId,
          '${raiser.name ?? raiser.username} raised their hand to speak.',
        );
      }
    }
    notifyListeners();
  }

  Future<void> _handleSignalEnvelope(
    String siteUrl,
    int roomId,
    Map<String, dynamic> envelope,
  ) async {
    final sender = envelope['sender_id'];
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
        'senderPresent': sender is num,
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
          if (sender is num) 'senderId': sender.toInt(),
          'signals': events,
        },
      );
    }
    if (call == null ||
        sender is! num ||
        call.siteUrl != siteUrl ||
        call.room.id != roomId ||
        events.isEmpty) {
      return;
    }
    final activeCall = call;
    final senderId = sender.toInt();

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
          final held = _directories[siteUrl];
          if (held != null) {
            _directories[siteUrl] = VoiceDirectory(
              rooms: [
                for (final room in held.rooms)
                  room.id == roomId
                      ? room.withParticipants(participants)
                      : room,
              ],
              canCreateRoom: held.canCreateRoom,
              messageBusLastId: held.messageBusLastId,
            );
          }
          if (identical(_call?.media, activeCall.media)) {
            _call = activeCall.copyWith(
              room: activeCall.room.withParticipants(participants),
            );
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
    final held = _directories[siteUrl];
    if (held != null && held.rooms.any((room) => room.id == roomId)) {
      _directories[siteUrl] = VoiceDirectory(
        rooms: List.unmodifiable([
          for (final room in held.rooms)
            room.id == roomId ? update(room) : room,
        ]),
        canCreateRoom: held.canCreateRoom,
        messageBusLastId: held.messageBusLastId,
      );
    }
    final linked = _linkedRooms[siteUrl];
    final linkedRoom = linked?[roomId];
    if (linkedRoom != null) linked![roomId] = update(linkedRoom);
    final call = _call;
    if (updateCall &&
        call != null &&
        call.siteUrl == siteUrl &&
        call.room.id == roomId) {
      _call = call.copyWith(room: update(call.room));
    }
  }

  void _replaceRecording(
    String siteUrl,
    int roomId,
    VoiceRecording? recording,
  ) {
    _updateRoom(siteUrl, roomId, (room) => room.withRecording(recording));
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
    final call = _call;
    if (call != null && call.siteUrl == siteUrl && call.room.id == roomId) {
      final userId = _userIdFor(siteUrl);
      // Room subscriptions are cursored from the directory load, not from the
      // join response, so a roster published before join.json committed can
      // still be delivered while the join settles. The local user's absence
      // from such a roster is not evidence of removal until the call has
      // connected.
      if (call.status != VoiceCallStatus.leaving &&
          call.status != VoiceCallStatus.joining &&
          userId != null &&
          !participants.any((participant) => participant.id == userId)) {
        _observe(
          () => _leave(
            notifyServer: false,
            clearImmediately: true,
            reason: _VoiceLeaveReason.rosterRemoval,
          ),
          'voice.rosterRemoval',
        );
        return;
      }
      var canPublishAudio = true;
      if (userId != null) {
        canPublishAudio = _canPublishAudio(call.room, participants, userId);
      }
      _call = call.copyWith(
        room: call.room.withParticipants(participants),
        muted: canPublishAudio ? null : true,
      );
      _observe(() async {
        if (userId != null) {
          await _runHandled(
            () => call.media.setAudioPublishingAllowed(canPublishAudio),
            'voice.media.audioPublishing',
          );
          if (!canPublishAudio) {
            await _runHandled(
              () => call.media.setMuted(true),
              'voice.media.rosterMute',
            );
          }
        }
        await _runHandled(
          () => call.media.syncParticipants(participants),
          'voice.media.participants',
        );
      }, 'voice.media.participantUpdate');
    }
    notifyListeners();
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
  }) {
    final siteSession = _siteSession(siteUrl);
    final key = '$siteUrl#${room.id}';
    final pending = _pendingJoin;
    if (_pendingJoinKey == key &&
        identical(_pendingJoinSession, siteSession) &&
        pending != null) {
      _record(
        'call.join.coalesced',
        correlationId: _pendingJoinCorrelationId,
        data: _roomDiagnosticData(room),
      );
      return pending;
    }

    final correlationId = _nextCallCorrelationId();
    _record(
      'call.join.requested',
      correlationId: correlationId,
      data: _roomDiagnosticData(room),
    );
    _recordRaw(
      'call.join.context',
      correlationId: correlationId,
      data: _rawRoomDiagnosticData(siteUrl, room, siteName: siteName),
    );
    final previousJoin = _joinTail;
    Future<void> runJoin() => _runPublicOperation(
      () => _join(
        siteUrl: siteUrl,
        siteName: siteName,
        room: room,
        siteSession: siteSession,
        correlationId: correlationId,
      ),
      'voice.join',
      correlationId: correlationId,
    );
    final operation = _reporter.runOperation(
      'voice.join',
      () => previousJoin == null
          ? runJoin()
          : previousJoin.then((_) => runJoin()),
      correlationId: correlationId,
    );
    // Room taps can arrive while the preceding transport is still connecting.
    // Keep each leave/join transition atomic so a later tap cannot dispose the
    // media session that the earlier transition is still establishing.
    _joinTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    late final Future<void> tracked;
    tracked = operation.whenComplete(() {
      if (identical(_pendingJoin, tracked)) {
        _pendingJoin = null;
        _pendingJoinKey = null;
        _pendingJoinCorrelationId = null;
        _pendingJoinSession = null;
      }
    });
    _pendingJoin = tracked;
    _pendingJoinKey = key;
    _pendingJoinCorrelationId = correlationId;
    _pendingJoinSession = siteSession;
    return tracked;
  }

  Future<void> _join({
    required String siteUrl,
    required String siteName,
    required VoiceRoom room,
    required Object siteSession,
    required String correlationId,
  }) async {
    bool siteIsCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    if (!supportedPlatform || !siteIsCurrent()) {
      _record(
        'call.join.skipped',
        correlationId: correlationId,
        data: {
          ..._roomDiagnosticData(room),
          'reason': !supportedPlatform ? 'unsupported_platform' : 'stale_site',
          'platform': Platform.operatingSystem,
        },
      );
      return;
    }
    _record(
      'call.join.started',
      correlationId: correlationId,
      data: _roomDiagnosticData(room),
    );
    final pendingLeave = _leaveOperation;
    if (pendingLeave != null) await pendingLeave;
    if (!siteIsCurrent()) return;
    final held = _call;
    if (held?.siteUrl == siteUrl && held?.room.id == room.id) {
      _record(
        'call.join.cancelled',
        correlationId: correlationId,
        data: {'reason': 'active_room_toggle'},
      );
      await _leave(notifyServer: true, reason: _VoiceLeaveReason.roomToggle);
      return;
    }
    if (held != null) {
      await _leave(notifyServer: true, reason: _VoiceLeaveReason.roomSwitch);
    }
    if (!siteIsCurrent()) return;
    final revision = Object();
    _joinRevision = revision;
    bool isCurrent() => siteIsCurrent() && identical(_joinRevision, revision);
    final credentials = await _requestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    final userId = _userIdFor(siteUrl);
    if (credentials == null || userId == null || !isCurrent()) {
      _record(
        'call.join.skipped',
        correlationId: correlationId,
        data: {
          'reason': !isCurrent()
              ? 'cancelled'
              : credentials == null
              ? 'missing_api_key'
              : 'missing_user_id',
        },
      );
      return;
    }
    _errors.remove(siteUrl);
    final apiKey = credentials.apiKey;
    final clientId = credentials.clientId;
    final invitedBy = _consumeInviteRef(siteUrl, room);
    VoiceMediaSession? media;
    _VoiceParticipantSession? participantSession;
    String? joinedParticipantSessionId;
    var serverJoinActive = false;
    try {
      late VoiceJoinResponse response;
      try {
        _record(
          'call.join.server_request.started',
          correlationId: correlationId,
          data: {'roomId': room.id},
        );
        response = await api.join(
          siteUrl: siteUrl,
          roomId: room.id,
          apiKey: apiKey,
          skipStatus: !_autoStatusEnabled,
          invitedBy: invitedBy,
          clientId: clientId,
        );
      } on WriteException catch (error) {
        if (error.failure != WriteFailure.rateLimited) rethrow;
        _record(
          'call.join.server_request.rate_limited',
          correlationId: correlationId,
          severity: DiagnosticSeverity.warning,
          data: {
            'retryAfterMilliseconds':
                (error.retryAfter ?? const Duration(seconds: 1)).inMilliseconds,
          },
        );
        // A 429 is the one write failure that is safe to retry: Discourse
        // rejected it before the room mutation ran. Native user API keys share
        // a site-wide request budget, so a room switch can legitimately land
        // behind ordinary app refreshes or WebRTC signaling.
        await Future<void>.delayed(
          (error.retryAfter ?? const Duration(seconds: 1)) +
              const Duration(milliseconds: 150),
        );
        if (!isCurrent()) return;
        response = await api.join(
          siteUrl: siteUrl,
          roomId: room.id,
          apiKey: apiKey,
          skipStatus: !_autoStatusEnabled,
          invitedBy: invitedBy,
          clientId: clientId,
        );
      }
      joinedParticipantSessionId = response.participantSessionId;
      serverJoinActive = true;
      if (!isCurrent()) {
        await _runHandled(
          () => api.leave(
            siteUrl: siteUrl,
            roomId: room.id,
            apiKey: apiKey,
            participantSessionId: response.participantSessionId,
            clientId: clientId,
          ),
          'voice.leaveSupersededJoin',
        );
        serverJoinActive = false;
        return;
      }
      _record(
        'call.join.server_request.completed',
        correlationId: correlationId,
        data: {
          'transport': response.transport.name,
          'participantCount': response.room.participants.length,
        },
      );
      _recordRoster(
        'call.join.initial_roster',
        siteUrl,
        room.id,
        response.room.participants,
        correlationId: correlationId,
      );
      final session = _VoiceParticipantSession(response.participantSessionId);
      participantSession = session;
      final signalBatcher = VoiceSignalBatcher(
        batchDelay: signalBatchDelay,
        sendBatch: (payload) async {
          await _reporter.runOperation(
            'voice.signal',
            () => api.signal(
              siteUrl: siteUrl,
              roomId: room.id,
              apiKey: apiKey,
              payload: payload,
              participantSessionId: session.id,
              clientId: clientId,
            ),
            correlationId: correlationId,
          );
        },
      );
      VoiceMediaSession? callbackMedia;
      bool mediaIsCurrent() =>
          isCurrent() &&
          callbackMedia != null &&
          identical(_call?.media, callbackMedia);
      media = mediaFactory.create(
        join: response,
        localUserId: userId,
        sendSignal: (recipientId, event) async {
          if (!mediaIsCurrent()) return;
          _record(
            'signaling.send.started',
            component: 'signaling',
            correlationId: correlationId,
            data: {
              'roomId': room.id,
              'recipientPresent': true,
              'type': _voiceSignalingDiagnosticType(event['type']),
            },
          );
          _recordRaw(
            'signaling.send.raw',
            component: 'signaling',
            correlationId: correlationId,
            data: {
              'siteUrl': siteUrl,
              'roomId': room.id,
              'recipientId': recipientId,
              'signal': event,
            },
          );
          try {
            await signalBatcher.send(recipientId, event);
            _record(
              'signaling.send.completed',
              component: 'signaling',
              correlationId: correlationId,
            );
          } catch (error, stackTrace) {
            _record(
              'signaling.send.failed',
              component: 'signaling',
              correlationId: correlationId,
              severity: DiagnosticSeverity.warning,
              data: {'errorType': error.runtimeType.toString()},
            );
            _recordRaw(
              'signaling.send.failure_detail',
              component: 'signaling',
              correlationId: correlationId,
              severity: DiagnosticSeverity.warning,
              message: error.toString(),
              data: {
                'recipientId': recipientId,
                'stackTrace': stackTrace.toString(),
              },
            );
            rethrow;
          }
        },
        refreshLiveKitCredentials: () async {
          final fallback = response.livekit;
          if (fallback == null) {
            throw StateError('LiveKit credentials are unavailable.');
          }
          if (!mediaIsCurrent()) return fallback;
          _record(
            'livekit.credentials.refresh.requested',
            component: 'livekit',
            correlationId: correlationId,
            data: {'roomId': room.id},
          );
          final refreshCredentials = await _requests.credentialsFor(siteUrl);
          if (!mediaIsCurrent()) return fallback;
          final refreshed = await _reporter.runOperation(
            'voice.livekitToken',
            () => api.livekitToken(
              siteUrl: siteUrl,
              roomId: room.id,
              apiKey: apiKey,
              clientId: refreshCredentials.clientId,
            ),
            correlationId: correlationId,
          );
          if (refreshed.participantSessionId case final renewed?) {
            session.id = renewed;
          }
          _record(
            'livekit.credentials.refresh.received',
            component: 'livekit',
            correlationId: correlationId,
          );
          return mediaIsCurrent() ? refreshed : fallback;
        },
        diagnostics: diagnostics,
        correlationId: correlationId,
      );
      callbackMedia = media;
      _mediaCorrelations[media] = correlationId;
      _participantSessions[media] = session;
      _signalBatchers[media] = signalBatcher;
      _record(
        'media.session.created',
        component: 'media',
        correlationId: correlationId,
        data: {'transport': media.transport.name},
      );
      final initiallyMuted = !_canPublishAudio(
        response.room,
        response.room.participants,
        userId,
      );
      await media.setMuted(initiallyMuted);
      if (!isCurrent()) {
        _record(
          'call.join.cancelled',
          correlationId: correlationId,
          data: {'reason': 'cancelled_after_media_creation'},
        );
        await _runHandled(
          () => api.leave(
            siteUrl: siteUrl,
            roomId: room.id,
            apiKey: apiKey,
            participantSessionId: session.id,
            clientId: clientId,
          ),
          'voice.leaveCancelledJoin',
        );
        serverJoinActive = false;
        await _disposeMedia(media, 'voice.media.disposeAfterCancelledJoin');
        return;
      }
      media.addListener(_mediaChanged);
      if (_incomingCall case final incoming?
          when incoming.siteUrl == siteUrl && incoming.call.roomId == room.id) {
        _clearIncomingCall(
          tellSystem: VoiceIncomingCallEndReason.answeredElsewhere,
        );
      }
      _call = VoiceCallSnapshot(
        siteUrl: siteUrl,
        siteName: siteName,
        room: response.room,
        status: VoiceCallStatus.joining,
        media: media,
        muted: initiallyMuted,
      );
      if (systemCall case final NativeVoiceSystemCall nativeSystemCall) {
        nativeSystemCall.associateDiagnostics(correlationId);
      }
      _record(
        'call.status_changed',
        correlationId: correlationId,
        data: {
          'from': null,
          'to': VoiceCallStatus.joining.name,
          'transport': media.transport.name,
        },
      );
      _onCallSiteChanged();
      attachTracker(siteUrl);
      notifyListeners();
      if (!isCurrent()) return;
      _record(
        'callkit.command.requested',
        component: 'callkit',
        correlationId: correlationId,
        data: {'command': 'start'},
      );
      await systemCall.start(roomName: room.name, siteName: siteName);
      _record(
        'callkit.command.completed',
        component: 'callkit',
        correlationId: correlationId,
        data: {'command': 'start'},
      );
      if (!isCurrent()) return;
      _record(
        'media.connect.started',
        component: 'media',
        correlationId: correlationId,
      );
      await media.connect();
      _record(
        'media.connect.completed',
        component: 'media',
        correlationId: correlationId,
      );
      if (!isCurrent()) return;
      if (_audioInputDeviceId case final deviceId?) {
        await _selectSavedAudioDevice(
          kind: 'audio_input',
          deviceId: deviceId,
          correlationId: correlationId,
          selectDevice: media.selectAudioInput,
          isCurrent: isCurrent,
        );
        if (!isCurrent()) return;
      }
      if (_audioOutputDeviceId case final deviceId?) {
        await _selectSavedAudioDevice(
          kind: 'audio_output',
          deviceId: deviceId,
          correlationId: correlationId,
          selectDevice: media.selectAudioOutput,
          isCurrent: isCurrent,
        );
        if (!isCurrent()) return;
      }
      _call = _call?.copyWith(
        status: VoiceCallStatus.connected,
        clearError: true,
      );
      _record(
        'call.status_changed',
        correlationId: correlationId,
        data: {
          'from': VoiceCallStatus.joining.name,
          'to': VoiceCallStatus.connected.name,
        },
      );
      await _requestStateSync();
      if (!isCurrent()) return;
      if (initiallyMuted) {
        await systemCall.setMuted(true);
        if (!isCurrent()) return;
      }
      await systemCall.connected();
      _record(
        'callkit.command.completed',
        component: 'callkit',
        correlationId: correlationId,
        data: {'command': 'connected'},
      );
      if (!isCurrent()) return;
      _startHeartbeat();
      _idleTracker.start();
      _record(
        'call.join.completed',
        correlationId: correlationId,
        data: {
          ..._roomDiagnosticData(response.room),
          'transport': response.transport.name,
        },
      );
      notifyListeners();
    } catch (error, stackTrace) {
      if (media case final activeMedia?) {
        await _disposeMedia(activeMedia, 'voice.media.disposeAfterJoin');
      }
      if (serverJoinActive) {
        await _runHandled(
          () => api.leave(
            siteUrl: siteUrl,
            roomId: room.id,
            apiKey: apiKey,
            participantSessionId:
                participantSession?.id ?? joinedParticipantSessionId,
            clientId: clientId,
          ),
          'voice.leaveFailedJoin',
        );
      }
      if (!isCurrent()) return;
      _record(
        'call.join.failed',
        correlationId: correlationId,
        severity: DiagnosticSeverity.error,
        data: {'errorType': error.runtimeType.toString()},
      );
      _recordRaw(
        'call.join.failure_detail',
        correlationId: correlationId,
        severity: DiagnosticSeverity.error,
        message: error.toString(),
        data: {'stackTrace': stackTrace.toString()},
      );
      await _runHandled(systemCall.failed, 'voice.systemCall.failed');
      if (systemCall case final NativeVoiceSystemCall nativeSystemCall) {
        nativeSystemCall.associateDiagnostics(null);
      }
      if (isCurrent()) {
        _call = null;
        if (serverJoinActive) _removeLocalParticipant(siteUrl, room.id);
        _errors[siteUrl] = _joinFailureMessage(error, room);
        _onCallSiteChanged();
        notifyListeners();
      }
      if (isCurrent()) _report(error, stackTrace, 'voice.join');
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeatPending = false;
    _recordRaw(
      'heartbeat.started',
      component: 'heartbeat',
      correlationId: _correlationFor(_call),
      data: {'intervalMilliseconds': heartbeatInterval.inMilliseconds},
    );
    _scheduleHeartbeat();
  }

  void _scheduleHeartbeat() {
    _heartbeat?.cancel();
    if (_disposed || _call?.status != VoiceCallStatus.connected) return;
    _heartbeat = Timer(heartbeatInterval, () {
      _heartbeat = null;
      unawaited(_requestHeartbeat());
    });
  }

  Future<void> _requestHeartbeat() {
    final active = _heartbeatRequest;
    if (active != null) {
      _heartbeatPending = true;
      return active;
    }

    _heartbeat?.cancel();
    _heartbeat = null;
    late final Future<void> request;
    request = _beat().whenComplete(() {
      if (!identical(_heartbeatRequest, request)) return;
      _heartbeatRequest = null;
      if (_disposed || _call?.status != VoiceCallStatus.connected) return;
      if (_heartbeatPending) {
        _heartbeatPending = false;
        unawaited(_requestHeartbeat());
      } else {
        _scheduleHeartbeat();
      }
    });
    _heartbeatRequest = request;
    return request;
  }

  Future<void> _beat() async {
    final call = _call;
    if (call == null || call.status != VoiceCallStatus.connected) return;
    final siteSession = _siteSession(call.siteUrl);
    bool isCurrent() =>
        _isCurrentCall(call, siteSession) &&
        _call?.status == VoiceCallStatus.connected;
    try {
      final correlationId = _correlationFor(call);
      _recordRaw(
        'heartbeat.requested',
        component: 'heartbeat',
        correlationId: correlationId,
        data: {
          'siteUrl': call.siteUrl,
          'roomId': call.room.id,
          'idleState': _idleState.name,
        },
      );
      final credentials = await _requestCredentials(
        call.siteUrl,
        ifCurrent: isCurrent,
      );
      if (credentials == null) {
        if (!isCurrent()) return;
        _record(
          'heartbeat.credentials_missing',
          component: 'heartbeat',
          correlationId: correlationId,
          severity: DiagnosticSeverity.warning,
        );
        await _leave(
          notifyServer: false,
          reason: _VoiceLeaveReason.credentialsMissing,
        );
        return;
      }
      await _reporter.runOperation(
        'voice.heartbeat',
        () => api.heartbeat(
          siteUrl: call.siteUrl,
          roomId: call.room.id,
          apiKey: credentials.apiKey,
          idle: _idleState,
          participantSessionId: _participantSessions[call.media]?.id,
        ),
        correlationId: correlationId,
      );
      _recordRaw(
        'heartbeat.completed',
        component: 'heartbeat',
        correlationId: correlationId,
      );
    } on WriteException catch (error, stackTrace) {
      if (!isCurrent()) return;
      if (_isExpulsion(error)) {
        // The server no longer recognizes this session — it lapsed while the
        // app was cut off, the room was deleted, or access was revoked.
        // Every later beat would be refused the same way, and if nobody else
        // is in the room no roster broadcast will ever prune the local
        // user, so the call is unwound here the way the web client does.
        _record(
          'heartbeat.expelled',
          component: 'heartbeat',
          correlationId: _correlationFor(call),
          severity: DiagnosticSeverity.warning,
          data: {'statusCode': error.statusCode},
        );
        _errors[call.siteUrl] = error.errors.isNotEmpty
            ? error.errors.join('\n')
            : 'Your call session has expired. Rejoin the room to start a '
                  'new one.';
        await _leave(
          notifyServer: error.statusCode != HttpStatus.notFound,
          reason: _VoiceLeaveReason.sessionExpired,
        );
        return;
      }
      _recordRaw(
        'heartbeat.failed',
        component: 'heartbeat',
        correlationId: _correlationFor(call),
        severity: DiagnosticSeverity.warning,
        message: error.toString(),
        data: {
          'errorType': error.runtimeType.toString(),
          'statusCode': error.statusCode,
          'stackTrace': stackTrace.toString(),
        },
      );
      _report(error, stackTrace, 'voice.heartbeat');
    } catch (error, stackTrace) {
      if (isCurrent()) {
        _recordRaw(
          'heartbeat.failed',
          component: 'heartbeat',
          correlationId: _correlationFor(call),
          severity: DiagnosticSeverity.warning,
          message: error.toString(),
          data: {
            'errorType': error.runtimeType.toString(),
            'stackTrace': stackTrace.toString(),
          },
        );
        _report(error, stackTrace, 'voice.heartbeat');
      }
    }
  }

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
    if (foreground) _idleTracker.recordActivity();
    if (_call != null) unawaited(_requestHeartbeat());
  }

  VoiceIdleThresholds _activeIdleThresholds() {
    final call = _call;
    if (call == null) return _defaultIdleThresholds('');
    try {
      return _idleThresholdsFor(call.siteUrl);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'voice.idle.thresholds');
      return _defaultIdleThresholds(call.siteUrl);
    }
  }

  void _onIdleStateChanged(VoiceIdleState state, {required bool wasAutoMuted}) {
    if (_disposed) return;
    final call = _call;
    if (call == null || call.status == VoiceCallStatus.leaving) return;
    _idleState = state;
    _record(
      'idle.state_changed',
      component: 'idle',
      correlationId: _correlationFor(call),
      data: {'state': state.name, 'wasAutoMuted': wasAutoMuted},
    );
    final userId = _userIdFor(call.siteUrl);
    if (userId != null) {
      _updateRoom(
        call.siteUrl,
        call.room.id,
        (room) => room.withParticipants([
          for (final participant in room.participants)
            participant.id == userId
                ? _participantWithIdleState(participant, state)
                : participant,
        ]),
      );
    }
    if (state == VoiceIdleState.active && wasAutoMuted && call.muted) {
      _notify(
        call.siteUrl,
        call.room.id,
        'You were auto-muted after being idle. Unmute to keep talking.',
      );
    }
    unawaited(_requestHeartbeat());
    notifyListeners();
  }

  void _onIdleAutoMute() {
    final call = _call;
    if (_disposed || call == null || call.status == VoiceCallStatus.leaving) {
      return;
    }
    _record(
      'idle.auto_muted',
      component: 'idle',
      correlationId: _correlationFor(call),
      data: {'alreadyMuted': call.muted},
    );
    if (!call.muted) {
      _observe(() => _setMuted(true, syncSystem: true), 'voice.idle.autoMute');
    }
  }

  void _onIdleDisconnect() {
    final call = _call;
    if (_disposed || call == null || call.status == VoiceCallStatus.leaving) {
      return;
    }
    _record(
      'idle.disconnected',
      component: 'idle',
      correlationId: _correlationFor(call),
      severity: DiagnosticSeverity.warning,
    );
    _errors[call.siteUrl] =
        'You were disconnected from ${call.room.name} due to inactivity.';
    _observe(
      () =>
          _leave(notifyServer: true, reason: _VoiceLeaveReason.idleDisconnect),
      'voice.idle.disconnect',
    );
  }

  /// Every deliberate call control counts as the user being present.
  void _userActed() {
    if (_disposed) return;
    _idleTracker.recordActivity();
  }

  Future<void> setMuted(bool muted) {
    // Cleared before the activity is recorded: an unmute is the user acting
    // on an automatic mute, not a return that needs telling about it.
    if (!muted) _idleTracker.wasAutoMuted = false;
    _userActed();
    return _setMuted(muted, syncSystem: true);
  }

  void dismissCallError([String? siteUrl]) {
    if (_disposed) return;
    final clearedSiteError = siteUrl != null && _errors.remove(siteUrl) != null;
    final clearedCallError = _call?.error != null;
    if (clearedCallError) _call = _call?.copyWith(clearError: true);
    if (clearedSiteError || clearedCallError) notifyListeners();
  }

  Future<void> _setMuted(bool muted, {required bool syncSystem}) =>
      _updateMediaState(
        media: (call) => call.media.setMuted(muted),
        update: (call) => call.copyWith(muted: muted),
        rollback: (current, previous) =>
            current.copyWith(muted: previous.muted),
        system: syncSystem ? () => systemCall.setMuted(muted) : null,
      );

  Future<void> setDeafened(bool deafened) {
    _userActed();
    return _setDeafened(deafened);
  }

  Future<void> _setDeafened(bool deafened) => _updateMediaState(
    media: (call) => call.media.setDeafened(deafened),
    update: (call) => call.copyWith(deafened: deafened),
    rollback: (current, previous) =>
        current.copyWith(deafened: previous.deafened),
  );

  Future<void> setCameraEnabled(bool enabled, {String? deviceId}) {
    _userActed();
    return _setCameraEnabled(enabled, deviceId: deviceId);
  }

  Future<void> _setCameraEnabled(bool enabled, {String? deviceId}) =>
      _updateMediaState(
        media: (call) => call.media.setCameraEnabled(
          enabled,
          deviceId: deviceId ?? _cameraDeviceId,
        ),
        update: (call) => call.copyWith(cameraEnabled: enabled),
        rollback: (current, previous) =>
            current.copyWith(cameraEnabled: previous.cameraEnabled),
      );

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
    if (_disposed) return;
    _audioInputDeviceId = deviceId;
    final correlationId =
        _activeDiagnosticCorrelationId ??
        _reporter.newCorrelationId('voice-device');
    await _traceDeviceSelection(
      kind: 'audio_input',
      origin: 'user',
      deviceId: deviceId,
      applied: _call != null,
      correlationId: correlationId,
      action: () async {
        await _persistPreference(
          () => _preferences.writeDevice(
            VoiceDevicePreference.audioInput,
            deviceId,
          ),
          'voice.preferences.audioInput',
        );
        if (_disposed) return;
        await _call?.media.selectAudioInput(deviceId);
      },
    );
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> selectAudioOutput(String deviceId) => _runPublicOperation(
    () => _selectAudioOutput(deviceId),
    'voice.media.selectAudioOutput',
    correlationId: _activeDiagnosticCorrelationId,
  );

  Future<void> _selectAudioOutput(String deviceId) async {
    if (_disposed) return;
    _audioOutputDeviceId = deviceId;
    final correlationId =
        _activeDiagnosticCorrelationId ??
        _reporter.newCorrelationId('voice-device');
    await _traceDeviceSelection(
      kind: 'audio_output',
      origin: 'user',
      deviceId: deviceId,
      applied: _call != null,
      correlationId: correlationId,
      action: () async {
        await _persistPreference(
          () => _preferences.writeDevice(
            VoiceDevicePreference.audioOutput,
            deviceId,
          ),
          'voice.preferences.audioOutput',
        );
        if (_disposed) return;
        await _call?.media.selectAudioOutput(deviceId);
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

  Future<void> _selectCamera(String deviceId) async {
    if (_disposed) return;
    _cameraDeviceId = deviceId;
    final correlationId =
        _activeDiagnosticCorrelationId ??
        _reporter.newCorrelationId('voice-device');
    await _traceDeviceSelection(
      kind: 'camera',
      origin: 'user',
      deviceId: deviceId,
      applied: _call?.cameraEnabled == true,
      correlationId: correlationId,
      action: () async {
        await _persistPreference(
          () =>
              _preferences.writeDevice(VoiceDevicePreference.camera, deviceId),
          'voice.preferences.camera',
        );
        if (_disposed) return;
        final call = _call;
        if (call == null || !call.cameraEnabled) return;
        final media = call.media;
        await media.setCameraEnabled(false);
        if (_disposed || !identical(_call?.media, media)) return;
        await media.setCameraEnabled(true, deviceId: deviceId);
        if (_disposed || !identical(_call?.media, media)) return;
      },
    );
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> setPushToTalkEnabled(bool enabled) async {
    if (_disposed) return;
    _pushToTalkEnabled = enabled;
    await _persistPreference(
      () => _preferences.writePushToTalk(enabled),
      'voice.preferences.pushToTalk',
    );
    if (_disposed) return;
    if (enabled) await setMuted(true);
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
    await _call?.media.setParticipantVolume(userId, normalized);
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
      _audioInputDeviceId = preferences.audioInputDeviceId;
      _audioOutputDeviceId = preferences.audioOutputDeviceId;
      _cameraDeviceId = preferences.cameraDeviceId;
      _pushToTalkEnabled = preferences.pushToTalkEnabled;
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
      _autoStatusEnabled = stored;
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
    required Future<void> Function(String) selectDevice,
    required bool Function() isCurrent,
  }) async {
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
      if (!isCurrent()) return;
      if (deviceId == 'default') rethrow;

      // Saved devices may be disconnected. Explicitly restore the default so
      // a failed microphone switch cannot leave capture using a stale device.
      await _traceDeviceSelection(
        kind: kind,
        origin: 'saved_join_fallback',
        deviceId: 'default',
        applied: true,
        correlationId: correlationId,
        action: () => selectDevice('default'),
      );
    }
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

  Future<void> _setScreenSharing(bool enabled) => _updateMediaState(
    media: (call) => call.media.setScreenShareEnabled(enabled),
    update: (call) => call.copyWith(screenSharing: enabled),
    rollback: (current, previous) =>
        current.copyWith(screenSharing: previous.screenSharing),
  );

  Future<void> _updateMediaState({
    required Future<void> Function(VoiceCallSnapshot call) media,
    required VoiceCallSnapshot Function(VoiceCallSnapshot call) update,
    required VoiceCallSnapshot Function(
      VoiceCallSnapshot current,
      VoiceCallSnapshot previous,
    )
    rollback,
    Future<void> Function()? system,
  }) async {
    if (_disposed) return;
    final call = _call;
    if (call == null) return;
    _call = update(call);
    notifyListeners();
    try {
      await media(call);
    } catch (error, stackTrace) {
      final current = _call;
      if (!_disposed &&
          current != null &&
          identical(current.media, call.media)) {
        // Roster, status, and recording updates can land while the media call
        // is in flight; restoring the pre-toggle snapshot would erase them.
        // Revert only the toggled field on the current snapshot.
        _call = rollback(
          current,
          call,
        ).copyWith(error: 'The media setting was not applied.');
        notifyListeners();
      }
      _report(error, stackTrace, 'voice.mediaState');
      return;
    }

    if (_disposed) return;
    await _requestStateSync();
    if (_disposed) return;
    try {
      await system?.call();
    } catch (error, stackTrace) {
      // The local media operation already succeeded. A platform call-control
      // sync failure must not roll it back or claim that the device rejected
      // the setting.
      _report(error, stackTrace, 'voice.systemCallState');
    }
  }

  Future<void> _requestStateSync() {
    _stateSyncPending = true;
    _recordRaw(
      'state_sync.queued',
      component: 'state',
      correlationId: _correlationFor(_call),
      data: {'coalesced': _stateSync != null || _stateRetry != null},
    );
    final active = _stateSync;
    if (active != null || _stateRetry != null) {
      return active ?? Future<void>.value();
    }

    late final Future<void> operation;
    operation = _drainStateSync().whenComplete(() {
      if (identical(_stateSync, operation)) _stateSync = null;
      if (_stateSyncPending && _stateRetry == null && !_disposed) {
        unawaited(_requestStateSync());
      }
    });
    _stateSync = operation;
    return operation;
  }

  Future<void> _drainStateSync() async {
    while (_stateSyncPending && _stateRetry == null && !_disposed) {
      _stateSyncPending = false;
      final call = _call;
      if (call == null || call.status == VoiceCallStatus.leaving) return;
      final siteSession = _siteSession(call.siteUrl);
      bool isCurrent() => _isCurrentCall(call, siteSession);
      try {
        final correlationId = _correlationFor(call);
        _recordRaw(
          'state_sync.requested',
          component: 'state',
          correlationId: correlationId,
          data: {
            'siteUrl': call.siteUrl,
            'roomId': call.room.id,
            'muted': call.muted,
            'deafened': call.deafened,
            'video': call.cameraEnabled,
            'screen': call.screenSharing,
            'watching': _isWatching(call),
          },
        );
        final credentials = await _requestCredentials(
          call.siteUrl,
          ifCurrent: isCurrent,
        );
        if (credentials == null) return;
        await _reporter.runOperation(
          'voice.state',
          () => api.state(
            siteUrl: call.siteUrl,
            roomId: call.room.id,
            apiKey: credentials.apiKey,
            muted: call.muted,
            deafened: call.deafened,
            video: call.cameraEnabled,
            screen: call.screenSharing,
            watching: _isWatching(call),
            participantSessionId: _participantSessions[call.media]?.id,
          ),
          correlationId: correlationId,
        );
        _recordRaw(
          'state_sync.completed',
          component: 'state',
          correlationId: correlationId,
        );
      } on WriteException catch (error, stackTrace) {
        if (!isCurrent()) return;
        if (error.failure != WriteFailure.rateLimited) {
          _report(error, stackTrace, 'voice.state');
          return;
        }
        _recordRaw(
          'state_sync.rate_limited',
          component: 'state',
          correlationId: _correlationFor(call),
          severity: DiagnosticSeverity.warning,
          data: {
            'retryAfterMilliseconds':
                (error.retryAfter ?? const Duration(seconds: 1)).inMilliseconds,
          },
        );
        _stateSyncPending = true;
        _stateRetry = Timer(
          (error.retryAfter ?? const Duration(seconds: 1)) +
              const Duration(milliseconds: 150),
          () {
            _stateRetry = null;
            if (!_disposed) unawaited(_requestStateSync());
          },
        );
      } catch (error, stackTrace) {
        if (isCurrent()) _report(error, stackTrace, 'voice.state');
        return;
      }
    }
  }

  Future<void> leave({bool notifyServer = true}) =>
      _leave(notifyServer: notifyServer, reason: _VoiceLeaveReason.user);

  Future<void> _leave({
    required bool notifyServer,
    required _VoiceLeaveReason reason,
    bool clearImmediately = false,
  }) {
    final active = _leaveOperation;
    final call = _call;
    if (call == null) return active ?? Future<void>.value();
    if (active != null && identical(_leavingMedia, call.media)) {
      _record(
        'call.leave.coalesced',
        correlationId: _correlationFor(call),
        data: {'reason': reason.name, 'clearImmediately': clearImmediately},
      );
      if (clearImmediately && identical(_call?.media, call.media)) {
        _call = null;
        _onCallSiteChanged();
        if (!_disposed) notifyListeners();
      }
      return active;
    }

    final completion = Completer<void>();
    final operation = completion.future;
    _leavingMedia = call.media;
    _leaveOperation = operation;
    _joinRevision = Object();
    _signalBatchers[call.media]?.close();
    _heartbeat?.cancel();
    _heartbeat = null;
    _heartbeatPending = false;
    _stateRetry?.cancel();
    _stateRetry = null;
    _stateSyncPending = false;
    _idleTracker.stop();
    _idleState = VoiceIdleState.active;
    final correlationId = _correlationFor(call);
    _record(
      'call.leave.started',
      correlationId: correlationId,
      data: {
        ..._roomDiagnosticData(call.room),
        'reason': reason.name,
        'notifyServer': notifyServer,
        'clearImmediately': clearImmediately,
        'status': call.status.name,
      },
    );
    _recordRaw(
      'call.leave.context',
      correlationId: correlationId,
      data: {
        ..._rawRoomDiagnosticData(
          call.siteUrl,
          call.room,
          siteName: call.siteName,
        ),
        'reason': reason.name,
      },
    );
    _call = clearImmediately
        ? null
        : call.copyWith(status: VoiceCallStatus.leaving);
    // A delayed roster broadcast must not leave our avatar beside Join room.
    _removeLocalParticipant(call.siteUrl, call.room.id);
    if (!clearImmediately && call.status != VoiceCallStatus.leaving) {
      _record(
        'call.status_changed',
        correlationId: correlationId,
        data: {
          'from': call.status.name,
          'to': VoiceCallStatus.leaving.name,
          'reason': reason.name,
        },
      );
    }
    if (clearImmediately) _onCallSiteChanged();
    if (!_disposed) notifyListeners();
    unawaited(
      _finishLeave(
        call,
        notifyServer: notifyServer,
        reason: reason,
        operation: operation,
        completion: completion,
      ),
    );
    return operation;
  }

  Future<void> _finishLeave(
    VoiceCallSnapshot call, {
    required bool notifyServer,
    required _VoiceLeaveReason reason,
    required Future<void> operation,
    required Completer<void> completion,
  }) async {
    final correlationId = _correlationFor(call);
    try {
      if (notifyServer) {
        try {
          _record(
            'call.leave.server_request.started',
            correlationId: correlationId,
            data: {'roomId': call.room.id},
          );
          final credentials = await _requestCredentials(call.siteUrl);
          if (credentials != null) {
            await _reporter.runOperation(
              'voice.leave',
              () => api.leave(
                siteUrl: call.siteUrl,
                roomId: call.room.id,
                apiKey: credentials.apiKey,
                participantSessionId: _participantSessions[call.media]?.id,
              ),
              correlationId: correlationId,
            );
            _record(
              'call.leave.server_request.completed',
              correlationId: correlationId,
            );
          } else {
            _record(
              'call.leave.server_request.skipped',
              correlationId: correlationId,
              severity: DiagnosticSeverity.warning,
              data: {'reason': 'missing_api_key'},
            );
          }
        } catch (error, stackTrace) {
          _record(
            'call.leave.server_request.failed',
            correlationId: correlationId,
            severity: DiagnosticSeverity.warning,
            data: {'errorType': error.runtimeType.toString()},
          );
          _recordRaw(
            'call.leave.server_request.failure_detail',
            correlationId: correlationId,
            severity: DiagnosticSeverity.warning,
            message: error.toString(),
            data: {'stackTrace': stackTrace.toString()},
          );
          _report(error, stackTrace, 'voice.leave');
        }
      } else {
        _record(
          'call.leave.server_request.skipped',
          correlationId: correlationId,
          data: {'reason': 'local_only'},
        );
      }

      try {
        call.media.removeListener(_mediaChanged);
      } catch (error, stackTrace) {
        _report(error, stackTrace, 'voice.media.removeListener');
      }
      _record(
        'media.dispose.started',
        component: 'media',
        correlationId: correlationId,
      );
      await _disposeMedia(call.media, 'voice.media.dispose');
      _record(
        'media.dispose.completed',
        component: 'media',
        correlationId: correlationId,
      );
      _record(
        'callkit.command.requested',
        component: 'callkit',
        correlationId: correlationId,
        data: {'command': 'end'},
      );
      await _runHandled(systemCall.end, 'voice.systemCall.end');
      _record(
        'callkit.command.completed',
        component: 'callkit',
        correlationId: correlationId,
        data: {'command': 'end'},
      );
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'voice.leave.dispose');
    } finally {
      if (identical(_leaveOperation, operation)) {
        _leaveOperation = null;
        _leavingMedia = null;
      }
      if (identical(_call?.media, call.media)) {
        _call = null;
        try {
          _onCallSiteChanged();
        } catch (error, stackTrace) {
          _report(error, stackTrace, 'voice.callSiteChanged.dispose');
        }
      }
      _record(
        'call.leave.completed',
        correlationId: correlationId,
        data: {'reason': reason.name},
      );
      if (systemCall case final NativeVoiceSystemCall nativeSystemCall) {
        nativeSystemCall.associateDiagnostics(null);
      }
      if (!_disposed) {
        try {
          notifyListeners();
        } catch (error, stackTrace) {
          _report(error, stackTrace, 'voice.listeners.dispose');
        }
      }
      if (!completion.isCompleted) completion.complete();
    }
  }

  Future<VoiceRoom?> saveRoom({
    required String siteUrl,
    required VoiceRoomDraft draft,
    int? roomId,
  }) => _runPublicValueOperation<VoiceRoom?>(
    () => _saveRoom(siteUrl: siteUrl, draft: draft, roomId: roomId),
    'voice.saveRoom',
    fallback: null,
  );

  Future<VoiceRoom?> _saveRoom({
    required String siteUrl,
    required VoiceRoomDraft draft,
    int? roomId,
  }) async {
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final credentials = await _requestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return null;
    try {
      final room = roomId == null
          ? await api.createRoom(
              siteUrl: siteUrl,
              apiKey: credentials.apiKey,
              draft: draft,
            )
          : await api.updateRoom(
              siteUrl: siteUrl,
              roomId: roomId,
              apiKey: credentials.apiKey,
              draft: draft,
            );
      if (!isCurrent()) return null;
      await ensureLoaded(siteUrl, force: true);
      return isCurrent() ? room : null;
    } catch (error, stackTrace) {
      if (!isCurrent()) return null;
      _errors[siteUrl] = error is WriteException
          ? error.message
          : "Couldn't save the voice room.";
      _report(error, stackTrace, 'voice.saveRoom');
      notifyListeners();
      return null;
    }
  }

  Future<void> deleteRoom(String siteUrl, int roomId) => _runPublicOperation(
    () => _deleteRoom(siteUrl, roomId),
    'voice.deleteRoom',
  );

  Future<void> _deleteRoom(String siteUrl, int roomId) async {
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final credentials = await _requestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return;
    try {
      await api.deleteRoom(
        siteUrl: siteUrl,
        roomId: roomId,
        apiKey: credentials.apiKey,
      );
      if (!isCurrent()) return;
      await ensureLoaded(siteUrl, force: true);
    } catch (error, stackTrace) {
      if (!isCurrent()) return;
      _errors[siteUrl] = error is WriteException
          ? error.message
          : "Couldn't delete the voice room.";
      _report(error, stackTrace, 'voice.deleteRoom');
      notifyListeners();
    }
  }

  Future<void> openChat(String siteUrl, int roomId, {bool force = false}) =>
      _runPublicOperation(
        () => _openChat(siteUrl, roomId, force: force),
        'voice.chat.load',
      );

  void closeChat(String siteUrl, int roomId) {
    final key = '$siteUrl#$roomId';
    _chatRequests.remove(key);
    final state = _chats[key];
    if (state == null) return;
    state
      ..visible = false
      ..loading = false;
    _unwatchChatUpdates(state);
    _closeChatConversation(state);
    if (!_disposed) notifyListeners();
  }

  Future<void> _openChat(
    String siteUrl,
    int roomId, {
    bool force = false,
  }) async {
    final key = '$siteUrl#$roomId';
    if (!force && (_chats[key]?.loading ?? false)) return;
    final siteSession = _siteSession(siteUrl);
    final request = Object();
    _chatRequests[key] = request;
    bool isCurrent() =>
        _isCurrentSiteSession(siteUrl, siteSession) &&
        identical(_chatRequests[key], request);
    final state = _chats.putIfAbsent(key, _VoiceChatAssociation.new);
    state
      ..visible = true
      ..loading = true
      ..error = null;
    notifyListeners();
    try {
      final credentials = await _requestCredentials(
        siteUrl,
        ifCurrent: isCurrent,
      );
      if (credentials == null) return;
      final session = await api.chatSession(
        siteUrl: siteUrl,
        roomId: roomId,
        apiKey: credentials.apiKey,
      );
      if (!isCurrent()) return;
      state.session = session;
      // Watched only once the session has been read: a change published
      // before that is reflected in the read itself, and a panel whose site
      // was forgotten mid-read must not leave a subscription behind.
      _watchChatUpdates(siteUrl, roomId, key, state);
      final conversation = _bindChatConversation(siteUrl, key, state);
      if (conversation != null) await conversation.refresh(force: force);
    } catch (error, stackTrace) {
      if (!isCurrent()) return;
      state.error = "Couldn't load room chat.";
      _report(error, stackTrace, 'voice.chat.load');
    } finally {
      if (isCurrent()) {
        _chatRequests.remove(key);
        state.loading = false;
        notifyListeners();
      }
    }
  }

  void _watchChatUpdates(
    String siteUrl,
    int roomId,
    String key,
    _VoiceChatAssociation state,
  ) {
    if (state.liveUpdates != null) return;
    final tracker = _trackerFor(siteUrl);
    if (tracker == null) return;
    state.liveUpdates = tracker.subscribe('/voice/rooms/$roomId/chat', (
      data,
      _,
    ) {
      if (_disposed || !state.visible || !identical(_chats[key], state)) {
        return;
      }
      if (data is Map && data['type'] == 'updated') {
        _observe(
          () => _refreshChatSession(siteUrl, roomId),
          'voice.chat.refresh',
        );
      }
    });
  }

  void _unwatchChatUpdates(_VoiceChatAssociation state) {
    state.liveUpdates?.cancel();
    state.liveUpdates = null;
  }

  /// The panel is open and the server said the session changed: re-read it
  /// through the chat_session endpoint (which re-checks this user's access)
  /// and follow the thread it names now. Deliberately not [_openChat]: no
  /// loading state, so the panel does not blink on every rollover.
  Future<void> _refreshChatSession(String siteUrl, int roomId) async {
    final key = '$siteUrl#$roomId';
    final state = _chats[key];
    if (state == null || !state.visible) return;
    final siteSession = _siteSession(siteUrl);
    final request = Object();
    _chatRequests[key] = request;
    bool isCurrent() =>
        _isCurrentSiteSession(siteUrl, siteSession) &&
        identical(_chatRequests[key], request) &&
        identical(_chats[key], state) &&
        state.visible;
    try {
      final credentials = await _requestCredentials(
        siteUrl,
        ifCurrent: isCurrent,
      );
      if (credentials == null) return;
      final session = await api.chatSession(
        siteUrl: siteUrl,
        roomId: roomId,
        apiKey: credentials.apiKey,
      );
      if (!isCurrent()) return;
      final changed =
          session.channelId != state.session.channelId ||
          session.threadId != state.session.threadId;
      state.session = session;
      final conversation = _bindChatConversation(siteUrl, key, state);
      if (conversation != null && changed) {
        await conversation.refresh(force: true);
      }
      if (isCurrent()) notifyListeners();
    } catch (error, stackTrace) {
      if (isCurrent()) _report(error, stackTrace, 'voice.chat.refresh');
    } finally {
      if (identical(_chatRequests[key], request)) _chatRequests.remove(key);
    }
  }

  Future<void> loadOlderChat(String siteUrl, int roomId) =>
      _chats['$siteUrl#$roomId']?.conversation?.loadOlder() ??
      Future<void>.value();

  Future<void> sendChatMessage(String siteUrl, int roomId, String message) {
    _userActed();
    return _runPublicOperation(
      () => _sendChatMessage(siteUrl, roomId, message),
      'voice.chat.send',
    );
  }

  Future<void> _sendChatMessage(
    String siteUrl,
    int roomId,
    String message,
  ) async {
    final text = message.trim();
    if (text.isEmpty) return;
    final key = '$siteUrl#$roomId';
    var state = _chats.putIfAbsent(key, _VoiceChatAssociation.new);
    final heldConversation = state.conversation;
    if (heldConversation != null) {
      await heldConversation.send(text);
      return;
    }
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final credentials = await _requestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return;
    final apiKey = credentials.apiKey;
    state
      ..sending = true
      ..error = null;
    notifyListeners();
    try {
      var session = state.session;
      if (session.channelId == null) {
        session = await api.chatSession(
          siteUrl: siteUrl,
          roomId: roomId,
          apiKey: apiKey,
          ensure: true,
        );
        if (!isCurrent()) return;
      }
      var sentFirstMessage = false;
      if (session.threadId == null) {
        session = await api.firstChatMessage(
          siteUrl: siteUrl,
          roomId: roomId,
          apiKey: apiKey,
          message: text,
        );
        if (!isCurrent()) return;
        sentFirstMessage = true;
      }
      state = _chats[key] ?? state;
      state
        ..session = session
        ..sending = false;
      final retainConversation = state.visible && identical(_chats[key], state);
      final conversation = retainConversation
          ? _bindChatConversation(siteUrl, key, state)
          : sentFirstMessage
          ? null
          : _temporaryChatConversation(siteUrl, state.session);
      try {
        if (conversation != null) {
          if (sentFirstMessage) {
            if (retainConversation) await conversation.refresh(force: true);
          } else {
            await conversation.send(text);
            final sendError = conversation.value.error;
            if (!retainConversation && sendError != null) {
              state.error = sendError;
            }
          }
        }
      } finally {
        if (!retainConversation) conversation?.close();
      }
      if (isCurrent()) notifyListeners();
    } catch (error, stackTrace) {
      if (!isCurrent()) return;
      state = _chats[key] ?? state;
      state
        ..sending = false
        ..error = 'Message not sent.';
      _report(error, stackTrace, 'voice.chat.send');
      notifyListeners();
    }
  }

  ChatConversation? _bindChatConversation(
    String siteUrl,
    String key,
    _VoiceChatAssociation state,
  ) {
    if (!state.visible || !identical(_chats[key], state)) {
      _closeChatConversation(state);
      return null;
    }
    final channelId = state.session.channelId;
    final threadId = state.session.threadId;
    final held = state.conversation;
    if (channelId == null || threadId == null) {
      _closeChatConversation(state);
      return null;
    }
    if (held != null &&
        held.channelId == channelId &&
        held.threadId == threadId) {
      return held;
    }

    _closeChatConversation(state);
    final conversation = chatConversations.openThread(
      siteUrl: siteUrl,
      channelId: channelId,
      threadId: threadId,
    );
    void conversationChanged() {
      if (!_disposed && identical(_chats[key], state)) notifyListeners();
    }

    state
      ..conversation = conversation
      ..conversationListener = conversationChanged;
    conversation.addListener(conversationChanged);
    return conversation;
  }

  ChatConversation? _temporaryChatConversation(
    String siteUrl,
    VoiceChatSession session,
  ) {
    final channelId = session.channelId;
    final threadId = session.threadId;
    if (channelId == null || threadId == null) return null;
    return chatConversations.openThread(
      siteUrl: siteUrl,
      channelId: channelId,
      threadId: threadId,
    );
  }

  void _closeChatConversation(_VoiceChatAssociation state) {
    final conversation = state.conversation;
    final listener = state.conversationListener;
    if (conversation != null && listener != null) {
      conversation.removeListener(listener);
    }
    conversation?.close();
    state
      ..conversation = null
      ..conversationListener = null;
  }

  void _removeChatAssociation(String siteUrl, int roomId) {
    final key = '$siteUrl#$roomId';
    _chatRequests.remove(key);
    final state = _chats.remove(key);
    if (state != null) {
      _unwatchChatUpdates(state);
      _closeChatConversation(state);
    }
  }

  void _pruneChatAssociations(String siteUrl, Set<int> roomIds) {
    final prefix = '$siteUrl#';
    for (final key in {
      ..._chats.keys.where((key) => key.startsWith(prefix)),
      ..._chatRequests.keys.where((key) => key.startsWith(prefix)),
    }) {
      final roomId = int.tryParse(key.substring(prefix.length));
      if (roomId != null && roomIds.contains(roomId)) continue;
      _chatRequests.remove(key);
      final state = _chats.remove(key);
      if (state != null) {
        _unwatchChatUpdates(state);
        _closeChatConversation(state);
      }
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
    final credentials = await _requestCredentials(
      call.siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return;
    await api.requestToSpeak(
      siteUrl: call.siteUrl,
      roomId: call.room.id,
      apiKey: credentials.apiKey,
      userId: userId,
      raised: raised,
      participantSessionId: _participantSessions[call.media]?.id,
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
    if (call == null) return;
    final siteSession = _siteSession(call.siteUrl);
    bool isCurrent() => _isCurrentCall(call, siteSession);
    final credentials = await _requestCredentials(
      call.siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return;
    await api.addMembership(
      siteUrl: call.siteUrl,
      roomId: call.room.id,
      apiKey: credentials.apiKey,
      userId: userId,
      role: role,
      clientId: credentials.clientId,
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
    final credentials = await _requestCredentials(
      call.siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return;
    await api.kick(
      siteUrl: call.siteUrl,
      roomId: call.room.id,
      apiKey: credentials.apiKey,
      userId: userId,
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
    final flagTypeId = await api.notifyModeratorsFlagType(
      siteUrl: call.siteUrl,
      apiKey: credentials.apiKey,
      clientId: credentials.clientId,
    );
    if (flagTypeId == null || !isCurrent()) return false;
    await api.flag(
      siteUrl: call.siteUrl,
      roomId: call.room.id,
      apiKey: credentials.apiKey,
      userId: userId,
      flagTypeId: flagTypeId,
      message: text,
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
    final credentials = await _requestCredentials(
      call.siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return;
    await api.setRecording(
      siteUrl: call.siteUrl,
      roomId: call.room.id,
      apiKey: credentials.apiKey,
      active: active,
    );
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
      () => api.invite(
        siteUrl: siteUrl,
        roomId: roomId,
        apiKey: credentials.apiKey,
        usernames: usernames,
        clientId: credentials.clientId,
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
      return api.inviteSuggestions(
        siteUrl: siteUrl,
        roomId: roomId,
        apiKey: credentials.apiKey,
        clientId: credentials.clientId,
      );
    },
    'voice.inviteSuggestions',
    fallback: const [],
  );

  Future<List<VoiceMembership>> memberships(String siteUrl, int roomId) =>
      _runPublicValueOperation<List<VoiceMembership>>(
        () => _memberships(siteUrl, roomId),
        'voice.memberships',
        fallback: const [],
      );

  Future<List<VoiceMembership>> _memberships(String siteUrl, int roomId) async {
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final credentials = await _requestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return const [];
    final memberships = await api.memberships(
      siteUrl: siteUrl,
      roomId: roomId,
      apiKey: credentials.apiKey,
    );
    return isCurrent() ? memberships : const [];
  }

  Future<void> addMember(
    String siteUrl,
    int roomId,
    String username,
    VoiceRole role,
  ) => _runPublicOperation(
    () => _addMember(siteUrl, roomId, username, role),
    'voice.membership.add',
  );

  Future<void> _addMember(
    String siteUrl,
    int roomId,
    String username,
    VoiceRole role,
  ) async {
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final credentials = await _requestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return;
    await api.addMembership(
      siteUrl: siteUrl,
      roomId: roomId,
      apiKey: credentials.apiKey,
      username: username,
      role: role,
    );
  }

  Future<void> updateMember(
    String siteUrl,
    int roomId,
    int membershipId,
    VoiceRole role,
  ) => _runPublicOperation(
    () => _updateMember(siteUrl, roomId, membershipId, role),
    'voice.membership.update',
  );

  Future<void> _updateMember(
    String siteUrl,
    int roomId,
    int membershipId,
    VoiceRole role,
  ) async {
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final credentials = await _requestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return;
    await api.updateMembership(
      siteUrl: siteUrl,
      roomId: roomId,
      membershipId: membershipId,
      apiKey: credentials.apiKey,
      role: role,
    );
  }

  Future<void> removeMember(String siteUrl, int roomId, int membershipId) =>
      _runPublicOperation(
        () => _removeMember(siteUrl, roomId, membershipId),
        'voice.membership.remove',
      );

  Future<void> _removeMember(
    String siteUrl,
    int roomId,
    int membershipId,
  ) async {
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final credentials = await _requestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    if (credentials == null) return;
    await api.removeMembership(
      siteUrl: siteUrl,
      roomId: roomId,
      membershipId: membershipId,
      apiKey: credentials.apiKey,
    );
  }

  void _mediaChanged() {
    if (_disposed) return;
    final call = _call;
    if (call != null) {
      if (!call.muted &&
          call.media.speakingParticipantIds.contains(
            _userIdFor(call.siteUrl),
          )) {
        _idleTracker.recordVoiceActivity();
      }
      var updated = call;
      final status = switch (call.media.connectionState) {
        VoiceMediaConnectionState.connected => VoiceCallStatus.connected,
        VoiceMediaConnectionState.reconnecting => VoiceCallStatus.reconnecting,
        VoiceMediaConnectionState.failed => VoiceCallStatus.failed,
      };
      // Only a call that has already settled takes its status from the media
      // layer. A join reaches `connected` at the end of its own sequence —
      // after the state sync, the saved devices and the platform call — and
      // the transports notify from inside `connect()`, so letting media
      // promote a `joining` call would announce the call before any of that
      // ran and would lift the guard that keeps a roster published before
      // join.json committed from tearing the call down.
      if (status != call.status &&
          call.status != VoiceCallStatus.leaving &&
          call.status != VoiceCallStatus.joining) {
        _record(
          'call.status_changed',
          correlationId: _correlationFor(call),
          severity: status == VoiceCallStatus.failed
              ? DiagnosticSeverity.error
              : DiagnosticSeverity.info,
          data: {
            'from': call.status.name,
            'to': status.name,
            'mediaConnectionState': call.media.connectionState.name,
          },
        );
        updated = updated.copyWith(
          status: status,
          error: status == VoiceCallStatus.failed
              ? 'The media connection could not be restored.'
              : null,
          clearError: status == VoiceCallStatus.connected,
        );
      }
      final screenShareEnded =
          updated.status != VoiceCallStatus.leaving &&
          updated.screenSharing &&
          !call.media.screenSharing;
      if (screenShareEnded) {
        _record(
          'media.screen_share.ended',
          component: 'media',
          correlationId: _correlationFor(call),
          data: {'cause': 'track_ended'},
        );
        updated = updated.copyWith(screenSharing: false);
      }
      _call = updated;
      // A heartbeat that fires while the call is away from connected declines
      // to reschedule itself, so a recovered connection must restart the chain
      // or server presence expires and the roster prunes the local user.
      if (updated.status == VoiceCallStatus.connected &&
          call.status != VoiceCallStatus.connected) {
        _startHeartbeat();
      }
      if (screenShareEnded) unawaited(_requestStateSync());
    }
    notifyListeners();
  }

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
        _idleTracker.wasAutoMuted = false;
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
    if (_call?.siteUrl == siteUrl) {
      _observe(
        () => _leave(
          notifyServer: true,
          reason: _VoiceLeaveReason.accountRemoval,
        ),
        'voice.accountRemoval',
      );
    }
    _siteSessions.remove(siteUrl);
    _directoryRequests.remove(siteUrl);
    _chatRequests.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _pendingInviteRefs.remove(siteUrl);
    _directories.remove(siteUrl);
    _liveCursors.remove(siteUrl);
    _attachedTrackers.remove(siteUrl);
    _unavailableSites.remove(siteUrl);
    _linkedRooms.remove(siteUrl);
    final forgottenChats = <_VoiceChatAssociation>[];
    _chats.removeWhere((key, state) {
      if (!key.startsWith('$siteUrl#')) return false;
      forgottenChats.add(state);
      return true;
    });
    for (final state in forgottenChats) {
      _unwatchChatUpdates(state);
      _closeChatConversation(state);
    }
    _cancelTrackerSubscriptions(siteUrl);
    _errors.remove(siteUrl);
    _loadingSites.remove(siteUrl);
    if (!_disposed) notifyListeners();
  }

  String _nextCallCorrelationId() {
    return _reporter.newCorrelationId('voice-call');
  }

  String? _correlationFor(VoiceCallSnapshot? call) =>
      call == null ? null : _mediaCorrelations[call.media];

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
    final leavingMedia = _leavingMedia;
    return leavingMedia == null ? null : _mediaCorrelations[leavingMedia];
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

  Future<void> _disposeMedia(VoiceMediaSession media, String operation) {
    final active = _mediaDisposals[media];
    if (active != null) return active;

    _signalBatchers[media]?.close();
    final completion = Completer<void>();
    final result = completion.future;
    _mediaDisposals[media] = result;
    unawaited(
      _runHandled(media.dispose, operation).then((_) {
        if (!completion.isCompleted) completion.complete();
      }),
    );
    return result;
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
    _joinRevision = Object();
    _heartbeat?.cancel();
    _heartbeat = null;
    _heartbeatPending = false;
    _stateRetry?.cancel();
    _stateRetry = null;
    _stateSyncPending = false;
    _roomVideoWatchers.clear();
    _pendingInviteRefs.clear();
    _attachedTrackers.clear();
    for (final state in _chats.values) {
      _unwatchChatUpdates(state);
      _closeChatConversation(state);
    }
    _chats.clear();
    _idleTracker.stop();
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
    super.dispose();
    return operation;
  }

  Future<void> _cancelSubscriptions() {
    final subscriptions = <PluginLiveChannelSubscription>[
      ..._directorySubscriptions.values,
      ..._ringSubscriptions.values,
      for (final siteSubscriptions in _roomSubscriptions.values)
        ...siteSubscriptions.values,
    ];
    _directorySubscriptions.clear();
    _ringSubscriptions.clear();
    _roomSubscriptions.clear();
    _clearIncomingCall(tellSystem: VoiceIncomingCallEndReason.unanswered);
    return Future.wait([
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

    await _runHandled(() async {
      final call = _call;
      final leave = call == null
          ? _leaveOperation
          : _leave(notifyServer: true, reason: _VoiceLeaveReason.sessionClose);
      if (leave != null) await leave;

      // A join may own media before publishing it through [_call].
      // Invalidating [_joinRevision] above makes it clean that media up;
      // waiting here keeps a half-created native session from escaping
      // PluginSession.close.
      final joinTail = _joinTail;
      if (joinTail != null) await joinTail;
      final lateLeave = _leaveOperation;
      if (lateLeave != null) await lateLeave;
      if (_call case final lateCall?) {
        await _leave(
          notifyServer: true,
          reason: _VoiceLeaveReason.sessionClose,
        );
        assert(!identical(_call?.media, lateCall.media));
      }
    }, 'voice.session.leave');

    await _runHandled(() async {
      final stateSync = _stateSync;
      if (stateSync != null) await stateSync;
      final heartbeatRequest = _heartbeatRequest;
      if (heartbeatRequest != null) await heartbeatRequest;
    }, 'voice.session.requests.dispose');
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

/// Where a site's live channels have been read to. The directory and room
/// records keep the cursors their payloads were served with; these advance
/// with every delivered message, so a replacement tracker resumes after the
/// last message this client consumed instead of replaying everything the
/// server published since the load.
final class _VoiceLiveCursors {
  int? _directory;
  final Map<int, int> _rooms = {};

  int? directoryCursor(int? snapshot) => _newerCursor(snapshot, _directory);

  int? roomCursor(int roomId, int? snapshot) =>
      _newerCursor(snapshot, _rooms[roomId]);

  void directoryDelivered(int messageId) {
    final current = _directory;
    if (current == null || messageId > current) _directory = messageId;
  }

  void roomDelivered(int roomId, int messageId) {
    final current = _rooms[roomId];
    if (current == null || messageId > current) _rooms[roomId] = messageId;
  }

  void dropRoom(int roomId) => _rooms.remove(roomId);
}

extension on VoiceRoom {
  /// A refreshed room, keeping whatever the held copy could see that this one
  /// could not. A directory listing is answered to whoever asked for it, so a
  /// room fetched anonymously omits the management and chat fields the joined
  /// copy already carries, and a listing serialized before the held copy's
  /// last room message carries an older channel cursor.
  VoiceRoom copyWithPrivileged(VoiceRoom held) => copyWith(
    messageBusLastId: _newerCursor(held.messageBusLastId, messageBusLastId),
    canManage: canManage || held.canManage,
    chatAvailable: chatAvailable || held.chatAvailable,
    chatChannelId: chatChannelId ?? held.chatChannelId,
    chatIdleMinutes: chatIdleMinutes ?? held.chatIdleMinutes,
    livekitEnabled: livekitEnabled ?? held.livekitEnabled,
    membership: membership ?? held.membership,
    recording: recording ?? held.recording,
  );
}
