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

import 'voice_idle.dart';
import 'voice_incoming_calls.dart';

import 'voice_media.dart';
import 'voice_models.dart';
import 'voice_preferences.dart';
import 'voice_settings.dart';
import 'voice_signaling.dart';
import 'voice_video_handle.dart';

export 'voice_incoming_calls.dart'
    show VoiceIncomingCallAcceptance, VoiceAwaitableSubscriptionTeardown;

part 'voice_call_commands.dart';
part 'voice_call_manager.dart';
part 'voice_call_session.dart';
part 'voice_chat_association.dart';
part 'voice_device_preferences.dart';
part 'voice_incoming_call_adapters.dart';
part 'voice_membership_editor.dart';
part 'voice_room_directory.dart';
part 'voice_room_events.dart';
part 'voice_user_invitation_session.dart';

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

       systemCall = systemCall ?? NativeVoiceSystemCall(),
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
  late final _roomEvents = _VoiceRoomEvents(
    calls: _calls,
    directoryFor: (siteUrl) => _roomDirectories[siteUrl],
    userIdFor: _userIdFor,
    publish: () {
      _notifyRoomListChanged();
      notifyListeners();
    },
    notify: _notify,
    observe: _observe,
  );
  late final _incoming = VoiceIncomingCalls(
    rooms: _VoiceIncomingRoomAccess(this),
    joins: _VoiceIncomingJoinAccess(this),
    navigation: _VoiceIncomingSystemNavigation(this),
    systemCall: systemCall,
    onChanged: () {
      if (!_disposed) notifyListeners();
    },
    clock: _clock,
    timerFactory: _timerFactory,
  );
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
    } catch (_) {}
  }

  /// Whether this device has accepted the peer-to-peer IP exposure warning.
  /// A failed read answers false: the warning is the safe side.
  Future<bool> meshPrivacyAcknowledged() async {
    try {
      return await _preferences.readMeshPrivacyAcknowledged();
    } catch (error) {
      return false;
    }
  }

  Future<void> acknowledgeMeshPrivacy() async {
    try {
      await _preferences.writeMeshPrivacyAcknowledged(true);
    } catch (_) {}
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
  VoiceIncomingCall? get incomingCall => _incoming.call;

  String? get incomingCallSiteUrl => _incoming.siteUrl;

  /// The system (CallKit) is ringing for [incomingCall], so the app's own
  /// banner would only duplicate it; the answer arrives as a system action.
  bool get incomingCallHandledBySystem => _incoming.handledBySystem;

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
    final room = await credentials.run(
      () => api.callUser(
        siteUrl: siteUrl,
        apiKey: credentials.apiKey!,
        username: username,
        clientId: credentials.clientId,
      ),
    );
    if (!isCurrent()) return null;

    _roomDirectory(siteUrl).rememberLinkedRoom(room);
    notifyListeners();
    return isCurrent() ? VoiceOutgoingCall._(siteUrl, room, isCurrent) : null;
  }

  Future<VoiceIncomingCallAcceptance?> acceptIncomingCall({
    bool fromSystem = false,
  }) => _incoming.accept(fromSystem: fromSystem);

  void declineIncomingCall({bool fromSystem = false}) =>
      _incoming.decline(fromSystem: fromSystem);

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
      _observe(() => _leave(notifyServer: false));
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
      _runHandledValue<VoiceRoom?>(
        () => _resolveRoom(siteUrl, slug),

        fallback: null,
      );

  Future<VoiceRoom?> _resolveRoom(
    String siteUrl,
    String slug, {
    bool Function()? ifCurrent,
  }) => _roomDirectory(siteUrl).resolveRoom(slug, ifCurrent: ifCurrent);

  Future<void> ensureLoaded(String siteUrl, {bool force = false}) =>
      _runHandled(() => _roomDirectory(siteUrl).ensureLoaded(force: force));

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
    _incoming.detach(siteUrl);
    for (final entry in _chats.entries) {
      if (entry.key.$1 == siteUrl) entry.value.detachTracker();
    }
  }

  bool _syncAuxiliarySubscriptions(
    String siteUrl,
    PluginLiveChannelHandle tracker,
  ) {
    final changed = _incoming.attach(siteUrl, _userIdFor(siteUrl), tracker);
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

  void _removeLocalParticipant(String siteUrl, int roomId) {
    final userId = _userIdFor(siteUrl);
    if (userId == null) return;
    _roomEvents.updateRoom(
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
    return _runHandled(
      () => _preferences.writeCameraEnabled(siteUrl, userId, enabled),
    );
  }

  Future<bool> _readCameraPreference(String siteUrl, int userId) async {
    try {
      return await _preferences.readCameraEnabled(siteUrl, userId);
    } catch (error) {
      return false;
    }
  }

  Future<List<rtc.MediaDeviceInfo>> mediaDevices() =>
      _runHandledValue<List<rtc.MediaDeviceInfo>>(() async {
        if (_disposed) return const <rtc.MediaDeviceInfo>[];
        final media = _call?.media;
        if (media == null) return const <rtc.MediaDeviceInfo>[];
        final result = await media.devices();
        return _disposed ? const <rtc.MediaDeviceInfo>[] : result;
      }, fallback: const []);

  Future<void> selectAudioInput(String deviceId) =>
      _runHandled(() => _selectAudioInput(deviceId));

  Future<void> _selectAudioInput(String deviceId) async {
    await _selectAudioDevice(
      deviceId,
      choice: _devicePreferences.audioInput,
      preference: VoiceDevicePreference.audioInput,

      selectDevice: (media) => media.selectAudioInput(deviceId),
    );
  }

  Future<void> selectAudioOutput(String deviceId) =>
      _runHandled(() => _selectAudioOutput(deviceId));

  Future<void> _selectAudioOutput(String deviceId) async {
    await _selectAudioDevice(
      deviceId,
      choice: _devicePreferences.audioOutput,
      preference: VoiceDevicePreference.audioOutput,

      selectDevice: (media) => media.selectAudioOutput(deviceId),
    );
  }

  Future<void> _selectAudioDevice(
    String deviceId, {
    required _VoicePreferenceChoice<String?> choice,
    required VoiceDevicePreference preference,

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

    await (() async {
      await _runHandled(() => _preferences.writeDevice(preference, deviceId));
      if (media == null || !isCurrent()) return;
      await _devicePreferences.audioOperations.run(
        owner: media,
        key: preference,
        operation: () async {
          if (isCurrent()) await selectDevice(media);
        },
      );
    })();
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> selectCamera(String deviceId) =>
      _runHandled(() => _selectCamera(deviceId));

  Future<void> switchCamera() => _runHandled(() async {
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
  });

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

    await (() async {
      if (deviceId != null) {
        await _runHandled(
          () =>
              _preferences.writeDevice(VoiceDevicePreference.camera, deviceId),
        );
      }
      if (!_disposed && _devicePreferences.camera.isCurrent(selection)) {
        _calls.current?._restorePreferredCamera();
      }
    })();
    if (!_disposed) notifyListeners();
  }

  Future<void> setPushToTalkEnabled(bool enabled) async {
    if (_disposed) return;
    final choice = _devicePreferences.pushToTalk;
    final intent = choice.select(enabled);
    final session = _calls.current;
    await _runHandled(() => _preferences.writePushToTalk(enabled));
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
    } catch (error) {
      return 1;
    }
  }

  Future<void> setParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
    double volume,
  ) =>
      _runHandled(() => _setParticipantVolume(siteUrl, roomId, userId, volume));

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
    await _runHandled(
      () => _preferences.writeParticipantVolume(
        siteUrl,
        roomId,
        userId,
        normalized,
      ),
    );
  }

  Future<void> _restoreDevicePreferences() async {
    try {
      final preferences = await _preferences.readDevices();
      if (_disposed) return;
      _devicePreferences.restoreDevices(preferences);

      notifyListeners();
    } catch (_) {
      // Tests and early startup may not have a preferences channel yet. Device
      // defaults remain usable and the next explicit selection persists.
    }
  }

  Future<void> _restoreAutoStatusPreference() async {
    try {
      final stored = await _preferences.readAutoStatusEnabled();
      if (_disposed || stored == null) return;
      _devicePreferences.autoStatus.restore(stored);
      notifyListeners();
    } catch (_) {
      // Same contract as the device restore: the default stays usable and
      // the next explicit choice persists.
    }
  }

  Future<void> _selectSavedAudioDevice({
    required String deviceId,

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
          await selectDevice(deviceId);
        } on Exception {
          if (!selectionIsCurrent()) return;
          if (deviceId == 'default') rethrow;

          await selectDevice('default');
        }
      },
    );
  }

  Future<void> setScreenSharing(bool enabled) {
    _userActed();
    return _setScreenSharing(enabled);
  }

  Future<void> _setScreenSharing(bool enabled) =>
      _calls.current?._setScreenSharing(enabled) ?? Future<void>.value();

  Future<void> leave({bool notifyServer = true}) =>
      _leave(notifyServer: notifyServer);

  Future<void> _leave({
    required bool notifyServer,

    bool clearImmediately = false,
  }) => _calls.leave(
    notifyServer: notifyServer,

    clearImmediately: clearImmediately,
  );

  Future<VoiceRoom?> saveRoom({
    required String siteUrl,
    required VoiceRoomDraft draft,
    int? roomId,
  }) => _runHandledValue<VoiceRoom?>(
    () => _roomDirectory(siteUrl).saveRoom(draft: draft, roomId: roomId),

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
      _runHandled(() => _chatAssociation(siteUrl, roomId).open(force: force));

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
    return _runHandled(
      () => message.trim().isEmpty
          ? Future<void>.value()
          : _chatAssociation(siteUrl, roomId).send(message),
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
    return _runHandled(
      () async => _VoiceCallCommands.admit(
        this,
      )?.requestToSpeak(userId: userId, raised: raised),
    );
  }

  /// Makes [userId] a speaker or moves them back to the listeners of the
  /// active stage room. A membership write: the server re-broadcasts the
  /// roster with the new role, and a promoted listener's raised hand is
  /// lowered by it.
  Future<void> setParticipantRole(int userId, VoiceRole role) {
    _userActed();
    return _runHandled(
      () async =>
          _VoiceCallCommands.admit(this)?.setParticipantRole(userId, role),
    );
  }

  Future<void> kick(int userId) =>
      _runHandled(() async => _VoiceCallCommands.admit(this)?.kick(userId));

  Future<bool> flagParticipant(int userId, String message) =>
      _runHandledValue<bool>(
        () async =>
            await _VoiceCallCommands.admit(
              this,
            )?.flagParticipant(userId, message) ??
            false,
        fallback: false,
      );

  Future<void> setRecording(bool active) => _runHandled(
    () async => _VoiceCallCommands.admit(this)?.setRecording(active),
  );

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

  VoiceUserInvitationSession userInvitation(String siteUrl, int roomId) =>
      VoiceUserInvitationSession._(
        this,
        siteUrl,
        roomId,
        captureSiteSession(siteUrl),
      );

  Future<VoiceMembershipOpenResult> openMembershipEditor(
    String siteUrl,
    int roomId,
  ) async {
    final ownsAccount = captureSiteSession(siteUrl);
    final editor = VoiceMembershipEditor._(this, siteUrl, roomId, ownsAccount);
    final loaded = await editor._refresh();
    if (!editor.isCurrent || !loaded) {
      editor.dispose();
      return VoiceMembershipOpenFailure(ownsAccount);
    }
    return VoiceMembershipOpened(editor);
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
    switch (action) {
      case VoiceSystemCallAction.mute:
        _userActed();
        _observe(() => _setMuted(true, syncSystem: false));
      case VoiceSystemCallAction.unmute:
        _calls.current?.acknowledgeUnmute();
        _userActed();
        _observe(() => _setMuted(false, syncSystem: false));
      case VoiceSystemCallAction.end:
        _observe(() => _leave(notifyServer: true));
      case VoiceSystemCallAction.answer:
        _observe(_incoming.answerFromSystem);
      case VoiceSystemCallAction.decline:
        declineIncomingCall(fromSystem: true);
    }
  }

  void forget(String siteUrl) {
    _cameraPreferences.removeWhere((account, _) => account.$1 == siteUrl);
    if (_calls.current?.siteUrl == siteUrl) {
      _observe(() => _leave(notifyServer: true));
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

  void _observe(Future<void> Function() action) {
    unawaited(_runHandled(action));
  }

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
    } catch (error) {
      return fallback;
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

    final systemActionsCancellation = _runHandled(_systemActions.cancel);
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
    final incomingCancellation = _incoming.close();
    final directories = [..._roomDirectories.values, ..._closingDirectories];
    _roomDirectories.clear();
    return Future.wait([
      for (final directory in directories) directory.close(),
      incomingCancellation,
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
    } catch (_) {}
  }

  Future<void> _finishClose(
    Future<void> systemActionsCancellation,
    Future<void> subscriptionCancellation,
  ) async {
    await _runHandled(_calls.close);
    await subscriptionCancellation;
    await systemActionsCancellation;
    await _runHandled(systemCall.dispose);
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
