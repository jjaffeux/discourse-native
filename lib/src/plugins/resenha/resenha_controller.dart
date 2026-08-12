import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import '../../data/api_credentials.dart';
import '../../data/discourse_api.dart';
import '../../data/site_tracker.dart';
import '../../diagnostics/diagnostics_controller.dart';
import '../chat/chat_message.dart';
import 'resenha_api.dart';
import 'resenha_callkit.dart';
import 'resenha_media.dart';
import 'resenha_models.dart';
import 'resenha_preferences.dart';

enum ResenhaCallStatus { joining, connected, reconnecting, leaving, failed }

@immutable
class ResenhaChatSnapshot {
  const ResenhaChatSnapshot({
    required this.session,
    this.messages = const [],
    this.loading = false,
    this.sending = false,
    this.canLoadMorePast = false,
    this.error,
  });

  final ResenhaChatSession session;
  final List<ChatMessage> messages;
  final bool loading;
  final bool sending;
  final bool canLoadMorePast;
  final String? error;

  ResenhaChatSnapshot copyWith({
    ResenhaChatSession? session,
    List<ChatMessage>? messages,
    bool? loading,
    bool? sending,
    bool? canLoadMorePast,
    String? error,
    bool clearError = false,
  }) => ResenhaChatSnapshot(
    session: session ?? this.session,
    messages: messages ?? this.messages,
    loading: loading ?? this.loading,
    sending: sending ?? this.sending,
    canLoadMorePast: canLoadMorePast ?? this.canLoadMorePast,
    error: clearError ? null : error ?? this.error,
  );
}

@immutable
class ResenhaCallSnapshot {
  const ResenhaCallSnapshot({
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
  final ResenhaRoom room;
  final ResenhaCallStatus status;
  final ResenhaMediaSession media;
  final bool muted;
  final bool deafened;
  final bool cameraEnabled;
  final bool screenSharing;
  final String? error;

  ResenhaCallSnapshot copyWith({
    ResenhaRoom? room,
    ResenhaCallStatus? status,
    bool? muted,
    bool? deafened,
    bool? cameraEnabled,
    bool? screenSharing,
    String? error,
    bool clearError = false,
  }) => ResenhaCallSnapshot(
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

typedef ResenhaTrackerLookup = SiteTracker? Function(String siteUrl);
typedef ResenhaUserIdLookup = int? Function(String siteUrl);

/// App-global Resenha state. Directories belong to sites; media belongs to the
/// one call, which deliberately survives selection of another site.
final class ResenhaController extends ChangeNotifier {
  ResenhaController({
    required this.api,
    required this.chatApi,
    required this.credentials,
    required this.trackerFor,
    required this.userIdFor,
    required this.onCallSiteChanged,
    this.mediaFactory = const NativeResenhaMediaFactory(),
    ResenhaSystemCall? systemCall,
    ResenhaPreferences? preferences,
    this.heartbeatInterval = const Duration(seconds: 10),
  }) : systemCall = systemCall ?? NativeResenhaSystemCall(),
       _preferences =
           preferences ?? const SharedPreferencesResenhaPreferences() {
    _systemActions = this.systemCall.actions.listen(_onSystemAction);
    unawaited(_restoreDevicePreferences());
  }

  final ResenhaApi api;
  final ChatApi chatApi;
  final ApiCredentialReader credentials;
  final ResenhaTrackerLookup trackerFor;
  final ResenhaUserIdLookup userIdFor;
  final VoidCallback onCallSiteChanged;
  final ResenhaMediaFactory mediaFactory;
  final ResenhaSystemCall systemCall;
  final ResenhaPreferences _preferences;
  final Duration heartbeatInterval;
  late final StreamSubscription<ResenhaSystemCallAction> _systemActions;

  final Map<String, ResenhaDirectory> _directories = {};
  final Map<String, Map<int, ResenhaRoom>> _linkedRooms = {};
  final Set<String> _loadingSites = {};
  final Set<String> _unavailableSites = {};
  final Map<String, SiteMessageBusSubscription> _directorySubscriptions = {};
  final Map<String, Map<int, SiteMessageBusSubscription>> _roomSubscriptions =
      {};
  final Map<String, String> _errors = {};
  final Map<String, ResenhaChatSnapshot> _chats = {};
  final Map<String, SiteMessageBusSubscription> _chatSubscriptions = {};
  final Map<String, Object> _siteSessions = {};
  final Map<String, Object> _directoryRequests = {};
  final Map<String, Object> _chatRequests = {};
  final Map<String, int> _roomVideoWatchers = {};
  Future<void> _joinTail = Future<void>.value();
  Future<void>? _pendingJoin;
  String? _pendingJoinKey;
  Object? _pendingJoinSession;
  Future<void>? _stateSync;
  Timer? _stateRetry;
  bool _stateSyncPending = false;
  Object? _joinRevision;
  Future<void>? _leaveOperation;
  ResenhaMediaSession? _leavingMedia;
  final Expando<Future<void>> _mediaDisposals = Expando<Future<void>>();
  Timer? _heartbeat;
  Future<void>? _heartbeatRequest;
  bool _heartbeatPending = false;
  ResenhaIdleState _idleState = ResenhaIdleState.active;
  ResenhaCallSnapshot? _call;
  bool _disposed = false;
  String? _audioInputDeviceId;
  String? _audioOutputDeviceId;
  String? _cameraDeviceId;
  bool _pushToTalkEnabled = false;

  ResenhaCallSnapshot? get call => _call;
  String? get activeSiteUrl => _call?.siteUrl;
  bool get hasCall => _call != null;
  bool get supportedPlatform =>
      Platform.isIOS || Platform.isMacOS || Platform.isLinux;
  String? get audioInputDeviceId => _audioInputDeviceId;
  String? get audioOutputDeviceId => _audioOutputDeviceId;
  String? get cameraDeviceId => _cameraDeviceId;
  bool get pushToTalkEnabled => _pushToTalkEnabled;

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

  bool _isWatching(ResenhaCallSnapshot call) =>
      (_roomVideoWatchers['${call.siteUrl}#${call.room.id}'] ?? 0) > 0;

  ResenhaDirectory? directory(String siteUrl) => _directories[siteUrl];
  String? errorFor(String siteUrl) => _errors[siteUrl];
  bool isLoading(String siteUrl) => _loadingSites.contains(siteUrl);
  ResenhaChatSnapshot? chat(String siteUrl, int roomId) =>
      _chats['$siteUrl#$roomId'];

  ResenhaRoom? room(String siteUrl, int roomId) {
    for (final room in _directories[siteUrl]?.rooms ?? const <ResenhaRoom>[]) {
      if (room.id == roomId) return room;
    }
    final call = _call;
    if (call?.siteUrl == siteUrl && call?.room.id == roomId) return call?.room;
    return _linkedRooms[siteUrl]?[roomId];
  }

  Future<ResenhaRoom?> resolveRoom(String siteUrl, String slug) async {
    final directory = _directories[siteUrl];
    for (final room in directory?.rooms ?? const <ResenhaRoom>[]) {
      if (room.slug == slug) return room;
    }
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null || !isCurrent()) return null;
    try {
      final clientId = await credentials.clientId();
      if (!isCurrent()) return null;
      final room = await api.room(
        siteUrl: siteUrl,
        slug: slug,
        apiKey: apiKey,
        clientId: clientId,
      );
      if (!isCurrent()) return null;
      (_linkedRooms[siteUrl] ??= {})[room.id] = room;
      notifyListeners();
      return room;
    } catch (error, stackTrace) {
      if (isCurrent()) _report(error, stackTrace, 'resenha.room');
      return null;
    }
  }

  Future<void> ensureLoaded(String siteUrl, {bool force = false}) async {
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
    final siteSession = _siteSession(siteUrl);
    final request = Object();
    _directoryRequests[siteUrl] = request;
    bool isCurrent() =>
        _isCurrentSiteSession(siteUrl, siteSession) &&
        identical(_directoryRequests[siteUrl], request);
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (!isCurrent()) return;
    if (apiKey == null) {
      forget(siteUrl);
      return;
    }
    _loadingSites.add(siteUrl);
    _errors.remove(siteUrl);
    notifyListeners();
    if (!isCurrent()) return;
    try {
      final clientId = await credentials.clientId();
      if (!isCurrent()) return;
      final directory = await api.rooms(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
      );
      if (!isCurrent()) return;
      _directories[siteUrl] = directory;
      _replaceSubscriptions(siteUrl, directory);
    } on SiteLookupException catch (error, stackTrace) {
      if (!isCurrent()) return;
      // Plugin absence and account refusal both mean no section for this site
      // session. Remember that negative capability so every later activation
      // does not probe the same missing route again. Network, rate-limit, 5xx,
      // and parse failures stay retryable without claiming the plugin exists.
      if (_isUnavailableDirectoryFailure(error)) {
        _directories.remove(siteUrl);
        _unavailableSites.add(siteUrl);
      } else {
        _errors[siteUrl] = "Couldn't load voice rooms.";
        _report(error, stackTrace, 'resenha.directory');
      }
    } catch (error, stackTrace) {
      if (!isCurrent()) return;
      _errors[siteUrl] = "Couldn't load voice rooms.";
      _report(error, stackTrace, 'resenha.directory');
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

  bool _isCurrentSiteSession(String siteUrl, Object session) =>
      !_disposed && identical(_siteSessions[siteUrl], session);

  bool _isCurrentCall(ResenhaCallSnapshot call, Object siteSession) =>
      _isCurrentSiteSession(call.siteUrl, siteSession) &&
      identical(_call?.media, call.media) &&
      _call?.status != ResenhaCallStatus.leaving;

  void attachTracker(String siteUrl) {
    final directory = _directories[siteUrl];
    if (directory != null) _replaceSubscriptions(siteUrl, directory);
  }

  void _replaceSubscriptions(String siteUrl, ResenhaDirectory directory) {
    final tracker = trackerFor(siteUrl);
    if (tracker == null) return;
    _directorySubscriptions.remove(siteUrl)?.cancel();
    _directorySubscriptions[siteUrl] = tracker.watchPluginChannel(
      '/resenha/rooms/index',
      (data) => _onDirectoryEvent(siteUrl, data),
      lastId: directory.messageBusLastId,
    );
    final subscriptions = _roomSubscriptions.putIfAbsent(siteUrl, () => {});
    final wanted = {for (final room in directory.rooms) room.id};
    for (final id
        in subscriptions.keys.where((id) => !wanted.contains(id)).toList()) {
      subscriptions.remove(id)?.cancel();
    }
    for (final room in directory.rooms) {
      subscriptions.putIfAbsent(
        room.id,
        () => tracker.watchPluginChannel(
          '/resenha/rooms/${room.id}',
          (data) => _onRoomEvent(siteUrl, room.id, data),
          lastId: room.messageBusLastId,
        ),
      );
    }
  }

  void _onDirectoryEvent(String siteUrl, Object? data) {
    if (_disposed || data is! Map<String, dynamic>) return;
    final rawRoom = data['room'];
    if (rawRoom is! Map<String, dynamic>) return;
    final incoming = ResenhaRoom.fromJson(rawRoom);
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
      case 'destroyed':
        rooms.removeWhere((room) => room.id == incoming.id);
        if (_call case final call?
            when call.siteUrl == siteUrl && call.room.id == incoming.id) {
          _observe(() => leave(notifyServer: false), 'resenha.roomDestroyed');
        }
      default:
        return;
    }
    _directories[siteUrl] = ResenhaDirectory(
      rooms: List.unmodifiable(rooms),
      canCreateRoom: held.canCreateRoom,
      messageBusLastId: held.messageBusLastId,
    );
    _replaceSubscriptions(siteUrl, _directories[siteUrl]!);
    notifyListeners();
  }

  static ResenhaRoom _preservePrivilegedFields(
    ResenhaRoom held,
    ResenhaRoom incoming,
  ) => incoming.copyWithPrivileged(held);

  void _onRoomEvent(String siteUrl, int roomId, Object? data) {
    if (_disposed || data is! Map<String, dynamic>) return;
    if (data['type'] == 'signal') {
      final senderId = data['sender_id'];
      final signal = data['data'];
      final call = _call;
      if (senderId is num &&
          signal is Map<String, dynamic> &&
          call?.siteUrl == siteUrl &&
          call?.room.id == roomId) {
        _observe(
          () => call!.media.handleSignal(senderId.toInt(), signal),
          'resenha.media.signal',
        );
      }
      return;
    }
    final event = ResenhaRoomEvent.fromJson(data);
    if (event == null) return;
    if (event is ResenhaKickedEvent) {
      final call = _call;
      if (call?.siteUrl == siteUrl && call?.room.id == roomId) {
        _observe(() => leave(notifyServer: false), 'resenha.kicked');
      }
      return;
    }
    if (event is ResenhaRoleChangedEvent) {
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
      return;
    }
    if (event is ResenhaParticipantsEvent) {
      _replaceParticipants(siteUrl, roomId, event.participants);
    }
    if (event is ResenhaRecordingEvent) {
      _replaceRecording(siteUrl, roomId, event.recording);
    }
  }

  static ResenhaParticipant _participantWithRole(
    ResenhaParticipant participant,
    ResenhaRole role,
  ) => ResenhaParticipant(
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

  void _replaceRecording(
    String siteUrl,
    int roomId,
    ResenhaRecording? recording,
  ) {
    final held = _directories[siteUrl];
    if (held != null) {
      _directories[siteUrl] = ResenhaDirectory(
        rooms: [
          for (final room in held.rooms)
            room.id == roomId ? room.withRecording(recording) : room,
        ],
        canCreateRoom: held.canCreateRoom,
        messageBusLastId: held.messageBusLastId,
      );
    }
    final call = _call;
    if (call?.siteUrl == siteUrl && call?.room.id == roomId) {
      _call = call!.copyWith(room: call.room.withRecording(recording));
    }
    notifyListeners();
  }

  void _replaceParticipants(
    String siteUrl,
    int roomId,
    List<ResenhaParticipant> participants,
  ) {
    final held = _directories[siteUrl];
    if (held != null) {
      _directories[siteUrl] = ResenhaDirectory(
        rooms: [
          for (final room in held.rooms)
            room.id == roomId ? room.withParticipants(participants) : room,
        ],
        canCreateRoom: held.canCreateRoom,
        messageBusLastId: held.messageBusLastId,
      );
    }
    final call = _call;
    if (call != null && call.siteUrl == siteUrl && call.room.id == roomId) {
      final userId = userIdFor(siteUrl);
      if (call.status != ResenhaCallStatus.leaving &&
          userId != null &&
          !participants.any((participant) => participant.id == userId)) {
        _observe(
          () => _leave(notifyServer: false, clearImmediately: true),
          'resenha.rosterRemoval',
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
            'resenha.media.audioPublishing',
          );
          if (!canPublishAudio) {
            await _runHandled(
              () => call.media.setMuted(true),
              'resenha.media.rosterMute',
            );
          }
        }
        await _runHandled(
          () => call.media.syncParticipants(participants),
          'resenha.media.participants',
        );
      }, 'resenha.media.participantUpdate');
    }
    notifyListeners();
  }

  static bool _canPublishAudio(
    ResenhaRoom room,
    List<ResenhaParticipant> participants,
    int userId,
  ) {
    if (room.type != ResenhaRoomType.stage) return true;
    final role = participants
        .where((participant) => participant.id == userId)
        .firstOrNull
        ?.role;
    final effective = role ?? room.membership?.role;
    return effective == ResenhaRole.moderator ||
        effective == ResenhaRole.speaker;
  }

  Future<void> join({
    required String siteUrl,
    required String siteName,
    required ResenhaRoom room,
  }) {
    final siteSession = _siteSession(siteUrl);
    final key = '$siteUrl#${room.id}';
    final pending = _pendingJoin;
    if (_pendingJoinKey == key &&
        identical(_pendingJoinSession, siteSession) &&
        pending != null) {
      return pending;
    }

    final operation = _joinTail.then(
      (_) => _join(
        siteUrl: siteUrl,
        siteName: siteName,
        room: room,
        siteSession: siteSession,
      ),
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
        _pendingJoinSession = null;
      }
    });
    _pendingJoin = tracked;
    _pendingJoinKey = key;
    _pendingJoinSession = siteSession;
    return tracked;
  }

  Future<void> _join({
    required String siteUrl,
    required String siteName,
    required ResenhaRoom room,
    required Object siteSession,
  }) async {
    bool siteIsCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    if (!supportedPlatform || !siteIsCurrent()) return;
    final pendingLeave = _leaveOperation;
    if (pendingLeave != null) await pendingLeave;
    if (!siteIsCurrent()) return;
    final held = _call;
    if (held?.siteUrl == siteUrl && held?.room.id == room.id) {
      await leave();
      return;
    }
    if (held != null) await leave();
    if (!siteIsCurrent()) return;
    final revision = Object();
    _joinRevision = revision;
    bool isCurrent() => siteIsCurrent() && identical(_joinRevision, revision);
    final apiKey = await credentials.apiKeyFor(siteUrl);
    final userId = userIdFor(siteUrl);
    if (apiKey == null || userId == null || !isCurrent()) return;
    ResenhaMediaSession? media;
    try {
      final clientId = await credentials.clientId();
      if (!isCurrent()) return;
      late ResenhaJoinResponse response;
      try {
        response = await api.join(
          siteUrl: siteUrl,
          roomId: room.id,
          apiKey: apiKey,
          clientId: clientId,
        );
      } on WriteException catch (error) {
        if (error.failure != WriteFailure.rateLimited) rethrow;
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
          clientId: clientId,
        );
      }
      if (!isCurrent()) return;
      ResenhaMediaSession? callbackMedia;
      bool mediaIsCurrent() =>
          isCurrent() &&
          callbackMedia != null &&
          identical(_call?.media, callbackMedia);
      media = mediaFactory.create(
        join: response,
        localUserId: userId,
        sendSignal: (recipientId, event) async {
          if (!mediaIsCurrent()) return;
          await api.signal(
            siteUrl: siteUrl,
            roomId: room.id,
            apiKey: apiKey,
            payload: {'recipient_id': recipientId, ...event},
          );
        },
        refreshLiveKitCredentials: () async {
          final fallback = response.livekit;
          if (fallback == null) {
            throw StateError('LiveKit credentials are unavailable.');
          }
          if (!mediaIsCurrent()) return fallback;
          final refreshClientId = await credentials.clientId();
          if (!mediaIsCurrent()) return fallback;
          final refreshed = await api.livekitToken(
            siteUrl: siteUrl,
            roomId: room.id,
            apiKey: apiKey,
            clientId: refreshClientId,
          );
          return mediaIsCurrent() ? refreshed : fallback;
        },
      );
      callbackMedia = media;
      final initiallyMuted = !_canPublishAudio(
        response.room,
        response.room.participants,
        userId,
      );
      await media.setMuted(initiallyMuted);
      if (!isCurrent()) {
        await _disposeMedia(media, 'resenha.media.disposeAfterCancelledJoin');
        return;
      }
      media.addListener(_mediaChanged);
      _call = ResenhaCallSnapshot(
        siteUrl: siteUrl,
        siteName: siteName,
        room: response.room,
        status: ResenhaCallStatus.joining,
        media: media,
        muted: initiallyMuted,
      );
      onCallSiteChanged();
      attachTracker(siteUrl);
      notifyListeners();
      if (!isCurrent()) return;
      await systemCall.start(roomName: room.name, siteName: siteName);
      if (!isCurrent()) return;
      await media.connect();
      if (!isCurrent()) return;
      if (_audioInputDeviceId case final deviceId?) {
        await media.selectAudioInput(deviceId);
        if (!isCurrent()) return;
      }
      if (_audioOutputDeviceId case final deviceId?) {
        await media.selectAudioOutput(deviceId);
        if (!isCurrent()) return;
      }
      _call = _call?.copyWith(
        status: ResenhaCallStatus.connected,
        clearError: true,
      );
      await _requestStateSync();
      if (!isCurrent()) return;
      if (initiallyMuted) {
        await systemCall.setMuted(true);
        if (!isCurrent()) return;
      }
      await systemCall.connected();
      if (!isCurrent()) return;
      _startHeartbeat();
      notifyListeners();
    } catch (error, stackTrace) {
      if (media case final activeMedia?) {
        await _disposeMedia(activeMedia, 'resenha.media.disposeAfterJoin');
      }
      if (!isCurrent()) return;
      await _runHandled(systemCall.failed, 'resenha.systemCall.failed');
      if (isCurrent()) {
        _call = null;
        _errors[siteUrl] = error is WriteException
            ? error.message
            : "Couldn't join ${room.name}.";
        onCallSiteChanged();
        notifyListeners();
      }
      if (isCurrent()) _report(error, stackTrace, 'resenha.join');
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeatPending = false;
    _scheduleHeartbeat();
  }

  void _scheduleHeartbeat() {
    _heartbeat?.cancel();
    if (_disposed || _call?.status != ResenhaCallStatus.connected) return;
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
      if (_disposed || _call?.status != ResenhaCallStatus.connected) return;
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
    if (call == null || call.status != ResenhaCallStatus.connected) return;
    final siteSession = _siteSession(call.siteUrl);
    bool isCurrent() =>
        _isCurrentCall(call, siteSession) &&
        _call?.status == ResenhaCallStatus.connected;
    try {
      final apiKey = await credentials.apiKeyFor(call.siteUrl);
      if (!isCurrent()) return;
      if (apiKey == null) {
        await leave(notifyServer: false);
        return;
      }
      await api.heartbeat(
        siteUrl: call.siteUrl,
        roomId: call.room.id,
        apiKey: apiKey,
        idle: _idleState,
      );
    } catch (error, stackTrace) {
      if (isCurrent()) _report(error, stackTrace, 'resenha.heartbeat');
    }
  }

  void setForeground(bool foreground) {
    if (_disposed) return;
    _idleState = foreground ? ResenhaIdleState.active : ResenhaIdleState.afk;
    if (_call != null) unawaited(_requestHeartbeat());
  }

  Future<void> setMuted(bool muted) => _setMuted(muted, syncSystem: true);

  void dismissCallError() {
    if (_disposed || _call == null) return;
    _call = _call?.copyWith(clearError: true);
    notifyListeners();
  }

  Future<void> _setMuted(bool muted, {required bool syncSystem}) =>
      _updateMediaState(
        media: (call) => call.media.setMuted(muted),
        update: (call) => call.copyWith(muted: muted),
        system: syncSystem ? () => systemCall.setMuted(muted) : null,
      );

  Future<void> setDeafened(bool deafened) => _updateMediaState(
    media: (call) => call.media.setDeafened(deafened),
    update: (call) => call.copyWith(deafened: deafened),
  );

  Future<void> setCameraEnabled(bool enabled, {String? deviceId}) =>
      _updateMediaState(
        media: (call) => call.media.setCameraEnabled(
          enabled,
          deviceId: deviceId ?? _cameraDeviceId,
        ),
        update: (call) => call.copyWith(cameraEnabled: enabled),
      );

  Future<List<rtc.MediaDeviceInfo>> mediaDevices() async => _disposed
      ? const []
      : await (_call?.media.devices() ?? Future.value(const []));

  Future<void> selectAudioInput(String deviceId) async {
    if (_disposed) return;
    _audioInputDeviceId = deviceId;
    await _persistPreference(
      () => _preferences.writeDevice(
        ResenhaDevicePreference.audioInput,
        deviceId,
      ),
      'resenha.preferences.audioInput',
    );
    if (_disposed) return;
    await _call?.media.selectAudioInput(deviceId);
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> selectAudioOutput(String deviceId) async {
    if (_disposed) return;
    _audioOutputDeviceId = deviceId;
    await _persistPreference(
      () => _preferences.writeDevice(
        ResenhaDevicePreference.audioOutput,
        deviceId,
      ),
      'resenha.preferences.audioOutput',
    );
    if (_disposed) return;
    await _call?.media.selectAudioOutput(deviceId);
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> selectCamera(String deviceId) async {
    if (_disposed) return;
    _cameraDeviceId = deviceId;
    await _persistPreference(
      () => _preferences.writeDevice(ResenhaDevicePreference.camera, deviceId),
      'resenha.preferences.camera',
    );
    if (_disposed) return;
    final call = _call;
    if (call?.cameraEnabled == true) {
      await call?.media.setCameraEnabled(false);
      if (_disposed || !identical(_call?.media, call?.media)) return;
      await call?.media.setCameraEnabled(true, deviceId: deviceId);
      if (_disposed || !identical(_call?.media, call?.media)) return;
    }
    notifyListeners();
  }

  Future<void> setPushToTalkEnabled(bool enabled) async {
    if (_disposed) return;
    _pushToTalkEnabled = enabled;
    await _persistPreference(
      () => _preferences.writePushToTalk(enabled),
      'resenha.preferences.pushToTalk',
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
      _report(error, stackTrace, 'resenha.preferences.readVolume');
      return 1;
    }
  }

  Future<void> setParticipantVolume(
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
      'resenha.preferences.writeVolume',
    );
  }

  Future<void> _restoreDevicePreferences() async {
    try {
      final preferences = await _preferences.readDevices();
      if (_disposed) return;
      _audioInputDeviceId = preferences.audioInputDeviceId;
      _audioOutputDeviceId = preferences.audioOutputDeviceId;
      _cameraDeviceId = preferences.cameraDeviceId;
      _pushToTalkEnabled = preferences.pushToTalkEnabled;
      notifyListeners();
    } catch (error, stackTrace) {
      // Tests and early startup may not have a preferences channel yet. Device
      // defaults remain usable and the next explicit selection persists.
      _report(error, stackTrace, 'resenha.preferences.restore');
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

  Future<void> setScreenSharing(bool enabled) => _updateMediaState(
    media: (call) => call.media.setScreenShareEnabled(enabled),
    update: (call) => call.copyWith(screenSharing: enabled),
  );

  Future<void> _updateMediaState({
    required Future<void> Function(ResenhaCallSnapshot call) media,
    required ResenhaCallSnapshot Function(ResenhaCallSnapshot call) update,
    Future<void> Function()? system,
  }) async {
    if (_disposed) return;
    final call = _call;
    if (call == null) return;
    final previous = call;
    _call = update(call);
    notifyListeners();
    try {
      await media(call);
    } catch (error, stackTrace) {
      if (!_disposed && identical(_call?.media, call.media)) {
        _call = previous.copyWith(error: 'The media setting was not applied.');
        notifyListeners();
      }
      _report(error, stackTrace, 'resenha.mediaState');
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
      _report(error, stackTrace, 'resenha.systemCallState');
    }
  }

  Future<void> _requestStateSync() {
    _stateSyncPending = true;
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
      if (call == null || call.status == ResenhaCallStatus.leaving) return;
      final siteSession = _siteSession(call.siteUrl);
      bool isCurrent() => _isCurrentCall(call, siteSession);
      try {
        final apiKey = await credentials.apiKeyFor(call.siteUrl);
        if (apiKey == null || !isCurrent()) return;
        await api.state(
          siteUrl: call.siteUrl,
          roomId: call.room.id,
          apiKey: apiKey,
          muted: call.muted,
          deafened: call.deafened,
          video: call.cameraEnabled,
          screen: call.screenSharing,
          watching: _isWatching(call),
        );
      } on WriteException catch (error, stackTrace) {
        if (!isCurrent()) return;
        if (error.failure != WriteFailure.rateLimited) {
          _report(error, stackTrace, 'resenha.state');
          return;
        }
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
        if (isCurrent()) _report(error, stackTrace, 'resenha.state');
        return;
      }
    }
  }

  Future<void> leave({bool notifyServer = true}) =>
      _leave(notifyServer: notifyServer);

  Future<void> _leave({
    required bool notifyServer,
    bool clearImmediately = false,
  }) {
    final active = _leaveOperation;
    final call = _call;
    if (call == null) return active ?? Future<void>.value();
    if (active != null && identical(_leavingMedia, call.media)) {
      if (clearImmediately && identical(_call?.media, call.media)) {
        _call = null;
        onCallSiteChanged();
        if (!_disposed) notifyListeners();
      }
      return active;
    }

    final completion = Completer<void>();
    final operation = completion.future;
    _leavingMedia = call.media;
    _leaveOperation = operation;
    _joinRevision = Object();
    _heartbeat?.cancel();
    _heartbeat = null;
    _heartbeatPending = false;
    _stateRetry?.cancel();
    _stateRetry = null;
    _stateSyncPending = false;
    _call = clearImmediately
        ? null
        : call.copyWith(status: ResenhaCallStatus.leaving);
    if (clearImmediately) onCallSiteChanged();
    if (!_disposed) notifyListeners();
    unawaited(
      _finishLeave(
        call,
        notifyServer: notifyServer,
        operation: operation,
        completion: completion,
      ),
    );
    return operation;
  }

  Future<void> _finishLeave(
    ResenhaCallSnapshot call, {
    required bool notifyServer,
    required Future<void> operation,
    required Completer<void> completion,
  }) async {
    if (notifyServer) {
      try {
        final apiKey = await credentials.apiKeyFor(call.siteUrl);
        if (apiKey != null) {
          await api.leave(
            siteUrl: call.siteUrl,
            roomId: call.room.id,
            apiKey: apiKey,
          );
        }
      } catch (error, stackTrace) {
        _report(error, stackTrace, 'resenha.leave');
      }
    }

    try {
      call.media.removeListener(_mediaChanged);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'resenha.media.removeListener');
    }
    await _disposeMedia(call.media, 'resenha.media.dispose');
    await _runHandled(systemCall.end, 'resenha.systemCall.end');

    if (identical(_leaveOperation, operation)) {
      _leaveOperation = null;
      _leavingMedia = null;
    }
    if (identical(_call?.media, call.media)) {
      _call = null;
      onCallSiteChanged();
    }
    if (!_disposed) notifyListeners();
    completion.complete();
  }

  Future<ResenhaRoom?> saveRoom({
    required String siteUrl,
    required ResenhaRoomDraft draft,
    int? roomId,
  }) async {
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null || !isCurrent()) return null;
    try {
      final room = roomId == null
          ? await api.createRoom(siteUrl: siteUrl, apiKey: apiKey, draft: draft)
          : await api.updateRoom(
              siteUrl: siteUrl,
              roomId: roomId,
              apiKey: apiKey,
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
      _report(error, stackTrace, 'resenha.saveRoom');
      notifyListeners();
      return null;
    }
  }

  Future<void> deleteRoom(String siteUrl, int roomId) async {
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null || !isCurrent()) return;
    try {
      await api.deleteRoom(siteUrl: siteUrl, roomId: roomId, apiKey: apiKey);
      if (!isCurrent()) return;
      await ensureLoaded(siteUrl, force: true);
    } catch (error, stackTrace) {
      if (!isCurrent()) return;
      _errors[siteUrl] = error is WriteException
          ? error.message
          : "Couldn't delete the voice room.";
      _report(error, stackTrace, 'resenha.deleteRoom');
      notifyListeners();
    }
  }

  Future<void> openChat(
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
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null || !isCurrent()) return;
    _chats[key] =
        (_chats[key] ??
                const ResenhaChatSnapshot(session: ResenhaChatSession()))
            .copyWith(loading: true, clearError: true);
    notifyListeners();
    try {
      final session = await api.chatSession(
        siteUrl: siteUrl,
        roomId: roomId,
        apiKey: apiKey,
      );
      if (!isCurrent()) return;
      final channelId = session.channelId;
      final threadId = session.threadId;
      var messages = const <ChatMessage>[];
      var canLoadMorePast = false;
      if (channelId != null && threadId != null) {
        final page = await chatApi.chatThreadMessages(
          siteUrl: siteUrl,
          channelId: channelId,
          threadId: threadId,
          apiKey: apiKey,
        );
        if (!isCurrent()) return;
        messages = page.messages;
        canLoadMorePast = page.canLoadMorePast;
        _subscribeChat(siteUrl, roomId, channelId, threadId);
        if (messages.isNotEmpty) {
          unawaited(
            chatApi.markChatThreadRead(
              siteUrl: siteUrl,
              apiKey: apiKey,
              channelId: channelId,
              threadId: threadId,
              messageId: messages.last.id,
            ),
          );
        }
      }
      _chats[key] = ResenhaChatSnapshot(
        session: session,
        messages: messages,
        canLoadMorePast: canLoadMorePast,
      );
    } catch (error, stackTrace) {
      if (!isCurrent()) return;
      _chats[key] =
          (_chats[key] ??
                  const ResenhaChatSnapshot(session: ResenhaChatSession()))
              .copyWith(loading: false, error: "Couldn't load room chat.");
      _report(error, stackTrace, 'resenha.chat.load');
    }
    if (isCurrent()) notifyListeners();
  }

  Future<void> loadOlderChat(String siteUrl, int roomId) async {
    final key = '$siteUrl#$roomId';
    final state = _chats[key];
    final channelId = state?.session.channelId;
    final threadId = state?.session.threadId;
    if (state == null ||
        state.loading ||
        !state.canLoadMorePast ||
        state.messages.isEmpty ||
        channelId == null ||
        threadId == null) {
      return;
    }
    final siteSession = _siteSession(siteUrl);
    final request = Object();
    _chatRequests[key] = request;
    bool isCurrent() =>
        _isCurrentSiteSession(siteUrl, siteSession) &&
        identical(_chatRequests[key], request);
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null || !isCurrent()) return;
    _chats[key] = state.copyWith(loading: true, clearError: true);
    notifyListeners();
    try {
      final page = await chatApi.chatThreadMessages(
        siteUrl: siteUrl,
        channelId: channelId,
        threadId: threadId,
        before: state.messages.first.id,
        apiKey: apiKey,
      );
      if (!isCurrent()) return;
      final byId = {
        for (final message in [...page.messages, ...state.messages])
          message.id: message,
      };
      final merged = byId.values.toList()
        ..sort((left, right) => left.id.compareTo(right.id));
      _chats[key] = state.copyWith(
        messages: List.unmodifiable(merged),
        loading: false,
        canLoadMorePast: page.canLoadMorePast,
      );
    } catch (error, stackTrace) {
      if (!isCurrent()) return;
      _chats[key] = state.copyWith(
        loading: false,
        error: "Couldn't load older messages.",
      );
      _report(error, stackTrace, 'resenha.chat.page');
    }
    if (isCurrent()) notifyListeners();
  }

  void _subscribeChat(String siteUrl, int roomId, int channelId, int threadId) {
    final key = '$siteUrl#$roomId';
    if (_chatSubscriptions.containsKey(key)) return;
    final tracker = trackerFor(siteUrl);
    if (tracker == null) return;
    _chatSubscriptions[key] = tracker.watchPluginChannel('/chat/$channelId', (
      data,
    ) {
      if (data is Map<String, dynamic> &&
          (data['thread_id'] == threadId || data['thread_id'] == '$threadId')) {
        unawaited(openChat(siteUrl, roomId, force: true));
      }
    });
  }

  Future<void> sendChatMessage(
    String siteUrl,
    int roomId,
    String message,
  ) async {
    final text = message.trim();
    if (text.isEmpty) return;
    final key = '$siteUrl#$roomId';
    final siteSession = _siteSession(siteUrl);
    bool isCurrent() => _isCurrentSiteSession(siteUrl, siteSession);
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null || !isCurrent()) return;
    var state =
        _chats[key] ?? const ResenhaChatSnapshot(session: ResenhaChatSession());
    _chats[key] = state.copyWith(sending: true, clearError: true);
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
      if (session.threadId == null) {
        session = await api.firstChatMessage(
          siteUrl: siteUrl,
          roomId: roomId,
          apiKey: apiKey,
          message: text,
        );
        if (!isCurrent()) return;
      } else if (session.channelId case final channelId?) {
        await chatApi.sendChatMessage(
          siteUrl: siteUrl,
          apiKey: apiKey,
          channelId: channelId,
          threadId: session.threadId,
          message: text,
        );
        if (!isCurrent()) return;
      }
      state = _chats[key] ?? state;
      _chats[key] = state.copyWith(session: session, sending: false);
      await openChat(siteUrl, roomId, force: true);
    } catch (error, stackTrace) {
      if (!isCurrent()) return;
      state = _chats[key] ?? state;
      _chats[key] = state.copyWith(sending: false, error: 'Message not sent.');
      _report(error, stackTrace, 'resenha.chat.send');
      notifyListeners();
    }
  }

  Future<void> requestToSpeak({int? userId, bool raised = true}) async {
    final call = _call;
    if (call == null) return;
    final siteSession = _siteSession(call.siteUrl);
    final apiKey = await credentials.apiKeyFor(call.siteUrl);
    if (apiKey == null || !_isCurrentCall(call, siteSession)) return;
    await api.requestToSpeak(
      siteUrl: call.siteUrl,
      roomId: call.room.id,
      apiKey: apiKey,
      userId: userId,
      raised: raised,
    );
  }

  Future<void> kick(int userId) async {
    final call = _call;
    if (call == null) return;
    final siteSession = _siteSession(call.siteUrl);
    final apiKey = await credentials.apiKeyFor(call.siteUrl);
    if (apiKey == null || !_isCurrentCall(call, siteSession)) return;
    await api.kick(
      siteUrl: call.siteUrl,
      roomId: call.room.id,
      apiKey: apiKey,
      userId: userId,
    );
  }

  Future<bool> flagParticipant(int userId, String message) async {
    final call = _call;
    final text = message.trim();
    if (call == null || text.isEmpty) return false;
    final siteSession = _siteSession(call.siteUrl);
    bool isCurrent() => _isCurrentCall(call, siteSession);
    final apiKey = await credentials.apiKeyFor(call.siteUrl);
    if (apiKey == null || !isCurrent()) return false;
    final clientId = await credentials.clientId();
    if (!isCurrent()) return false;
    final flagTypeId = await api.notifyModeratorsFlagType(
      siteUrl: call.siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    if (flagTypeId == null || !isCurrent()) return false;
    await api.flag(
      siteUrl: call.siteUrl,
      roomId: call.room.id,
      apiKey: apiKey,
      userId: userId,
      flagTypeId: flagTypeId,
      message: text,
    );
    return true;
  }

  Future<void> setRecording(bool active) async {
    final call = _call;
    if (call == null) return;
    final siteSession = _siteSession(call.siteUrl);
    final apiKey = await credentials.apiKeyFor(call.siteUrl);
    if (apiKey == null || !_isCurrentCall(call, siteSession)) return;
    await api.setRecording(
      siteUrl: call.siteUrl,
      roomId: call.room.id,
      apiKey: apiKey,
      active: active,
    );
  }

  Future<List<ResenhaMembership>> memberships(
    String siteUrl,
    int roomId,
  ) async {
    final siteSession = _siteSession(siteUrl);
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null || !_isCurrentSiteSession(siteUrl, siteSession)) {
      return const [];
    }
    final memberships = await api.memberships(
      siteUrl: siteUrl,
      roomId: roomId,
      apiKey: apiKey,
    );
    return _isCurrentSiteSession(siteUrl, siteSession) ? memberships : const [];
  }

  Future<void> addMember(
    String siteUrl,
    int roomId,
    String username,
    ResenhaRole role,
  ) async {
    final siteSession = _siteSession(siteUrl);
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null || !_isCurrentSiteSession(siteUrl, siteSession)) return;
    await api.addMembership(
      siteUrl: siteUrl,
      roomId: roomId,
      apiKey: apiKey,
      username: username,
      role: role,
    );
  }

  Future<void> updateMember(
    String siteUrl,
    int roomId,
    int membershipId,
    ResenhaRole role,
  ) async {
    final siteSession = _siteSession(siteUrl);
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null || !_isCurrentSiteSession(siteUrl, siteSession)) return;
    await api.updateMembership(
      siteUrl: siteUrl,
      roomId: roomId,
      membershipId: membershipId,
      apiKey: apiKey,
      role: role,
    );
  }

  Future<void> removeMember(
    String siteUrl,
    int roomId,
    int membershipId,
  ) async {
    final siteSession = _siteSession(siteUrl);
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null || !_isCurrentSiteSession(siteUrl, siteSession)) return;
    await api.removeMembership(
      siteUrl: siteUrl,
      roomId: roomId,
      membershipId: membershipId,
      apiKey: apiKey,
    );
  }

  void _mediaChanged() {
    if (_disposed) return;
    final call = _call;
    if (call != null) {
      var updated = call;
      final status = switch (call.media.connectionState) {
        ResenhaMediaConnectionState.connected => ResenhaCallStatus.connected,
        ResenhaMediaConnectionState.reconnecting =>
          ResenhaCallStatus.reconnecting,
        ResenhaMediaConnectionState.failed => ResenhaCallStatus.failed,
      };
      if (status != call.status && call.status != ResenhaCallStatus.leaving) {
        updated = updated.copyWith(
          status: status,
          error: status == ResenhaCallStatus.failed
              ? 'The media connection could not be restored.'
              : null,
          clearError: status == ResenhaCallStatus.connected,
        );
      }
      final screenShareEnded =
          updated.status != ResenhaCallStatus.leaving &&
          updated.screenSharing &&
          !call.media.screenSharing;
      if (screenShareEnded) {
        updated = updated.copyWith(screenSharing: false);
      }
      _call = updated;
      if (screenShareEnded) unawaited(_requestStateSync());
    }
    notifyListeners();
  }

  void _onSystemAction(ResenhaSystemCallAction action) {
    switch (action) {
      case ResenhaSystemCallAction.mute:
        _observe(
          () => _setMuted(true, syncSystem: false),
          'resenha.systemAction.mute',
        );
      case ResenhaSystemCallAction.unmute:
        _observe(
          () => _setMuted(false, syncSystem: false),
          'resenha.systemAction.unmute',
        );
      case ResenhaSystemCallAction.end:
        _observe(leave, 'resenha.systemAction.end');
    }
  }

  void forget(String siteUrl) {
    if (_call?.siteUrl == siteUrl) {
      _observe(leave, 'resenha.accountRemoval');
    }
    _siteSessions.remove(siteUrl);
    _directoryRequests.remove(siteUrl);
    _chatRequests.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _directories.remove(siteUrl);
    _unavailableSites.remove(siteUrl);
    _linkedRooms.remove(siteUrl);
    _chats.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    for (final key
        in _chatSubscriptions.keys
            .where((key) => key.startsWith('$siteUrl#'))
            .toList()) {
      _chatSubscriptions.remove(key)?.cancel();
    }
    _errors.remove(siteUrl);
    _loadingSites.remove(siteUrl);
    _directorySubscriptions.remove(siteUrl)?.cancel();
    for (final subscription
        in _roomSubscriptions.remove(siteUrl)?.values ??
            const <SiteMessageBusSubscription>[]) {
      subscription.cancel();
    }
    if (!_disposed) notifyListeners();
  }

  void _report(Object error, StackTrace stackTrace, String operation) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'resenha',
      severity: DiagnosticSeverity.warning,
      handled: true,
      degraded: true,
    );
  }

  void _observe(Future<void> Function() action, String operation) {
    unawaited(_runHandled(action, operation));
  }

  Future<void> _runHandled(
    Future<void> Function() action,
    String operation,
  ) async {
    try {
      await action();
    } catch (error, stackTrace) {
      _report(error, stackTrace, operation);
    }
  }

  Future<void> _disposeMedia(ResenhaMediaSession media, String operation) {
    final active = _mediaDisposals[media];
    if (active != null) return active;

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

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _heartbeat?.cancel();
    _heartbeatPending = false;
    _stateRetry?.cancel();
    _roomVideoWatchers.clear();
    for (final subscription in _directorySubscriptions.values) {
      subscription.cancel();
    }
    for (final subscriptions in _roomSubscriptions.values) {
      for (final subscription in subscriptions.values) {
        subscription.cancel();
      }
    }
    for (final subscription in _chatSubscriptions.values) {
      subscription.cancel();
    }
    _observe(() => _systemActions.cancel(), 'resenha.systemActions.dispose');
    final call = _call;
    if (call != null && !identical(_leavingMedia, call.media)) {
      call.media.removeListener(_mediaChanged);
      _observe(
        () => _disposeMedia(call.media, 'resenha.media.dispose'),
        'resenha.media.dispose',
      );
    }
    final pendingLeave = _leaveOperation;
    _observe(() async {
      if (pendingLeave != null) await pendingLeave;
      await systemCall.dispose();
    }, 'resenha.systemCall.dispose');
    super.dispose();
  }
}

extension on ResenhaRoom {
  ResenhaRoom copyWithPrivileged(ResenhaRoom held) => ResenhaRoom(
    id: id,
    name: name,
    slug: slug,
    description: description,
    cookedDescription: cookedDescription,
    isPublic: isPublic,
    ephemeral: ephemeral,
    type: type,
    maxParticipants: maxParticipants,
    memberCount: memberCount,
    messageBusLastId: messageBusLastId,
    participants: participants,
    creatorId: creatorId,
    canManage: canManage || held.canManage,
    videoEnabled: videoEnabled,
    videoAllowed: videoAllowed,
    chatAvailable: chatAvailable || held.chatAvailable,
    chatChannelId: chatChannelId ?? held.chatChannelId,
    chatIdleMinutes: chatIdleMinutes ?? held.chatIdleMinutes,
    chatThreadTitleTemplate:
        chatThreadTitleTemplate ?? held.chatThreadTitleTemplate,
    livekitEnabled: livekitEnabled ?? held.livekitEnabled,
    maxQualityProfile: maxQualityProfile,
    membership: membership ?? held.membership,
    recording: recording ?? held.recording,
  );
}
