import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/api_credentials.dart';
import '../../data/discourse_api.dart';
import '../../data/site_tracker.dart';
import '../../diagnostics/diagnostics_controller.dart';
import '../chat/chat_message.dart';
import 'resenha_api.dart';
import 'resenha_callkit.dart';
import 'resenha_media.dart';
import 'resenha_models.dart';

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
    this.heartbeatInterval = const Duration(seconds: 10),
  }) : systemCall = systemCall ?? NativeResenhaSystemCall() {
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
  final Duration heartbeatInterval;
  late final StreamSubscription<ResenhaSystemCallAction> _systemActions;

  final Map<String, ResenhaDirectory> _directories = {};
  final Map<String, Map<int, ResenhaRoom>> _linkedRooms = {};
  final Set<String> _loadingSites = {};
  final Map<String, SiteMessageBusSubscription> _directorySubscriptions = {};
  final Map<String, Map<int, SiteMessageBusSubscription>> _roomSubscriptions =
      {};
  final Map<String, String> _errors = {};
  final Map<String, ResenhaChatSnapshot> _chats = {};
  final Map<String, SiteMessageBusSubscription> _chatSubscriptions = {};
  Future<void> _joinTail = Future<void>.value();
  Future<void>? _pendingJoin;
  String? _pendingJoinKey;
  Object? _joinRevision;
  Timer? _heartbeat;
  ResenhaIdleState _idleState = ResenhaIdleState.active;
  ResenhaCallSnapshot? _call;
  bool _disposed = false;
  String? _audioInputDeviceId;
  String? _audioOutputDeviceId;
  String? _cameraDeviceId;
  bool _pushToTalkEnabled = false;

  static const _audioInputKey = 'resenha.device.audio-input';
  static const _audioOutputKey = 'resenha.device.audio-output';
  static const _cameraKey = 'resenha.device.camera';
  static const _pushToTalkKey = 'resenha.device.push-to-talk';

  ResenhaCallSnapshot? get call => _call;
  String? get activeSiteUrl => _call?.siteUrl;
  bool get hasCall => _call != null;
  bool get supportedPlatform =>
      Platform.isIOS || Platform.isMacOS || Platform.isLinux;
  String? get audioInputDeviceId => _audioInputDeviceId;
  String? get audioOutputDeviceId => _audioOutputDeviceId;
  String? get cameraDeviceId => _cameraDeviceId;
  bool get pushToTalkEnabled => _pushToTalkEnabled;

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
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null) return null;
    try {
      final room = await api.room(
        siteUrl: siteUrl,
        slug: slug,
        apiKey: apiKey,
        clientId: await credentials.clientId(),
      );
      (_linkedRooms[siteUrl] ??= {})[room.id] = room;
      notifyListeners();
      return room;
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'resenha.room');
      return null;
    }
  }

  Future<void> ensureLoaded(String siteUrl, {bool force = false}) async {
    if (!supportedPlatform) return;
    if (_disposed || _loadingSites.contains(siteUrl)) return;
    if (!force && _directories.containsKey(siteUrl)) {
      attachTracker(siteUrl);
      return;
    }
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (_disposed) return;
    if (apiKey == null) {
      forget(siteUrl);
      return;
    }
    _loadingSites.add(siteUrl);
    _errors.remove(siteUrl);
    notifyListeners();
    try {
      final directory = await api.rooms(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: await credentials.clientId(),
      );
      if (_disposed) return;
      _directories[siteUrl] = directory;
      _replaceSubscriptions(siteUrl, directory);
    } on SiteLookupException catch (error, stackTrace) {
      // Plugin absence and account refusal both mean no section. Network and
      // parse failures stay available for an explicit retry without claiming
      // that the plugin exists.
      if (error.failure == SiteLookupFailure.unreachable) {
        _errors[siteUrl] = "Couldn't load voice rooms.";
        _report(error, stackTrace, 'resenha.directory');
      } else {
        _directories.remove(siteUrl);
      }
    } catch (error, stackTrace) {
      _errors[siteUrl] = "Couldn't load voice rooms.";
      _report(error, stackTrace, 'resenha.directory');
    } finally {
      _loadingSites.remove(siteUrl);
      if (!_disposed) notifyListeners();
    }
  }

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
          unawaited(leave(notifyServer: false));
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
        unawaited(call!.media.handleSignal(senderId.toInt(), signal));
      }
      return;
    }
    final event = ResenhaRoomEvent.fromJson(data);
    if (event == null) return;
    if (event is ResenhaKickedEvent) {
      final call = _call;
      if (call?.siteUrl == siteUrl && call?.room.id == roomId) {
        unawaited(leave(notifyServer: false));
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
        unawaited(_leave(notifyServer: false, clearImmediately: true));
        return;
      }
      var canPublishAudio = true;
      if (userId != null) {
        canPublishAudio = _canPublishAudio(call.room, participants, userId);
        unawaited(call.media.setAudioPublishingAllowed(canPublishAudio));
        if (!canPublishAudio) unawaited(call.media.setMuted(true));
      }
      _call = call.copyWith(
        room: call.room.withParticipants(participants),
        muted: canPublishAudio ? null : true,
      );
      unawaited(call.media.syncParticipants(participants));
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
    final key = '$siteUrl#${room.id}';
    final pending = _pendingJoin;
    if (_pendingJoinKey == key && pending != null) return pending;

    final operation = _joinTail.then(
      (_) => _join(siteUrl: siteUrl, siteName: siteName, room: room),
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
      }
    });
    _pendingJoin = tracked;
    _pendingJoinKey = key;
    return tracked;
  }

  Future<void> _join({
    required String siteUrl,
    required String siteName,
    required ResenhaRoom room,
  }) async {
    if (!supportedPlatform) return;
    final held = _call;
    if (held?.siteUrl == siteUrl && held?.room.id == room.id) {
      await leave();
      return;
    }
    if (held != null) await leave();
    final revision = Object();
    _joinRevision = revision;
    final apiKey = await credentials.apiKeyFor(siteUrl);
    final userId = userIdFor(siteUrl);
    if (apiKey == null || userId == null || _disposed) return;
    ResenhaMediaSession? media;
    try {
      final clientId = await credentials.clientId();
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
        if (_disposed || !identical(_joinRevision, revision)) return;
        response = await api.join(
          siteUrl: siteUrl,
          roomId: room.id,
          apiKey: apiKey,
          clientId: clientId,
        );
      }
      if (_disposed || !identical(_joinRevision, revision)) return;
      media = mediaFactory.create(
        join: response,
        localUserId: userId,
        sendSignal: (recipientId, event) => api.signal(
          siteUrl: siteUrl,
          roomId: room.id,
          apiKey: apiKey,
          payload: {'recipient_id': recipientId, ...event},
        ),
        refreshLiveKitCredentials: () async => api.livekitToken(
          siteUrl: siteUrl,
          roomId: room.id,
          apiKey: apiKey,
          clientId: await credentials.clientId(),
        ),
      );
      final initiallyMuted = !_canPublishAudio(
        response.room,
        response.room.participants,
        userId,
      );
      await media.setMuted(initiallyMuted);
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
      await systemCall.start(roomName: room.name, siteName: siteName);
      await media.connect();
      if (_audioInputDeviceId case final deviceId?) {
        await media.selectAudioInput(deviceId);
      }
      if (_audioOutputDeviceId case final deviceId?) {
        await media.selectAudioOutput(deviceId);
      }
      if (_disposed || !identical(_joinRevision, revision)) {
        await media.dispose();
        return;
      }
      _call = _call?.copyWith(
        status: ResenhaCallStatus.connected,
        clearError: true,
      );
      if (initiallyMuted) {
        await api.state(
          siteUrl: siteUrl,
          roomId: room.id,
          apiKey: apiKey,
          muted: true,
        );
        await systemCall.setMuted(true);
      }
      await systemCall.connected();
      _startHeartbeat();
      notifyListeners();
    } catch (error, stackTrace) {
      await media?.dispose();
      await systemCall.failed();
      if (!_disposed && identical(_joinRevision, revision)) {
        _call = null;
        _errors[siteUrl] = error is WriteException
            ? error.message
            : "Couldn't join ${room.name}.";
        onCallSiteChanged();
        notifyListeners();
      }
      _report(error, stackTrace, 'resenha.join');
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => unawaited(_beat()));
  }

  Future<void> _beat() async {
    final call = _call;
    if (call == null || call.status != ResenhaCallStatus.connected) return;
    final apiKey = await credentials.apiKeyFor(call.siteUrl);
    if (apiKey == null) {
      await leave(notifyServer: false);
      return;
    }
    try {
      await api.heartbeat(
        siteUrl: call.siteUrl,
        roomId: call.room.id,
        apiKey: apiKey,
        idle: _idleState,
      );
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'resenha.heartbeat');
    }
  }

  void setForeground(bool foreground) {
    _idleState = foreground ? ResenhaIdleState.active : ResenhaIdleState.afk;
    if (_call != null) unawaited(_beat());
  }

  Future<void> setMuted(bool muted) => _setMuted(muted, syncSystem: true);

  void dismissCallError() {
    if (_call == null) return;
    _call = _call?.copyWith(clearError: true);
    notifyListeners();
  }

  Future<void> _setMuted(bool muted, {required bool syncSystem}) =>
      _updateMediaState(
        media: (call) => call.media.setMuted(muted),
        server: (call, key) => api.state(
          siteUrl: call.siteUrl,
          roomId: call.room.id,
          apiKey: key,
          muted: muted,
        ),
        update: (call) => call.copyWith(muted: muted),
        system: syncSystem ? () => systemCall.setMuted(muted) : null,
      );

  Future<void> setDeafened(bool deafened) => _updateMediaState(
    media: (call) => call.media.setDeafened(deafened),
    server: (call, key) => api.state(
      siteUrl: call.siteUrl,
      roomId: call.room.id,
      apiKey: key,
      deafened: deafened,
    ),
    update: (call) => call.copyWith(deafened: deafened),
  );

  Future<void> setCameraEnabled(bool enabled, {String? deviceId}) =>
      _updateMediaState(
        media: (call) => call.media.setCameraEnabled(
          enabled,
          deviceId: deviceId ?? _cameraDeviceId,
        ),
        server: (call, key) => api.state(
          siteUrl: call.siteUrl,
          roomId: call.room.id,
          apiKey: key,
          video: enabled,
        ),
        update: (call) => call.copyWith(cameraEnabled: enabled),
      );

  Future<List<rtc.MediaDeviceInfo>> mediaDevices() async =>
      _call?.media.devices() ?? const [];

  Future<void> selectAudioInput(String deviceId) async {
    _audioInputDeviceId = deviceId;
    await _persistString(_audioInputKey, deviceId);
    await _call?.media.selectAudioInput(deviceId);
    notifyListeners();
  }

  Future<void> selectAudioOutput(String deviceId) async {
    _audioOutputDeviceId = deviceId;
    await _persistString(_audioOutputKey, deviceId);
    await _call?.media.selectAudioOutput(deviceId);
    notifyListeners();
  }

  Future<void> selectCamera(String deviceId) async {
    _cameraDeviceId = deviceId;
    await _persistString(_cameraKey, deviceId);
    final call = _call;
    if (call?.cameraEnabled == true) {
      await call?.media.setCameraEnabled(false);
      await call?.media.setCameraEnabled(true, deviceId: deviceId);
    }
    notifyListeners();
  }

  Future<void> setPushToTalkEnabled(bool enabled) async {
    _pushToTalkEnabled = enabled;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_pushToTalkKey, enabled);
    if (enabled) await setMuted(true);
    notifyListeners();
  }

  Future<double> participantVolume(
    String siteUrl,
    int roomId,
    int userId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getDouble(_volumeKey(siteUrl, roomId, userId)) ?? 1)
        .clamp(0, 1)
        .toDouble();
  }

  Future<void> setParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
    double volume,
  ) async {
    final normalized = volume.clamp(0, 1).toDouble();
    await _call?.media.setParticipantVolume(userId, normalized);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(
      _volumeKey(siteUrl, roomId, userId),
      normalized,
    );
  }

  Future<void> _restoreDevicePreferences() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (_disposed) return;
      _audioInputDeviceId = preferences.getString(_audioInputKey);
      _audioOutputDeviceId = preferences.getString(_audioOutputKey);
      _cameraDeviceId = preferences.getString(_cameraKey);
      _pushToTalkEnabled = preferences.getBool(_pushToTalkKey) ?? false;
      notifyListeners();
    } catch (_) {
      // Tests and early startup may not have a preferences channel yet. Device
      // defaults remain usable and the next explicit selection persists.
    }
  }

  Future<void> _persistString(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, value);
  }

  static String _volumeKey(String siteUrl, int roomId, int userId) =>
      'resenha.volume.${Uri.encodeComponent(siteUrl)}.$roomId.$userId';

  Future<void> setScreenSharing(bool enabled) => _updateMediaState(
    media: (call) => call.media.setScreenShareEnabled(enabled),
    server: (call, key) => api.state(
      siteUrl: call.siteUrl,
      roomId: call.room.id,
      apiKey: key,
      screen: enabled,
    ),
    update: (call) => call.copyWith(screenSharing: enabled),
  );

  Future<void> _updateMediaState({
    required Future<void> Function(ResenhaCallSnapshot call) media,
    required Future<void> Function(ResenhaCallSnapshot call, String key) server,
    required ResenhaCallSnapshot Function(ResenhaCallSnapshot call) update,
    Future<void> Function()? system,
  }) async {
    final call = _call;
    if (call == null) return;
    final previous = call;
    _call = update(call);
    notifyListeners();
    try {
      await media(call);
      final apiKey = await credentials.apiKeyFor(call.siteUrl);
      if (apiKey != null) await server(call, apiKey);
      await system?.call();
    } catch (error, stackTrace) {
      if (identical(_call?.media, call.media)) {
        _call = previous.copyWith(error: 'The media setting was not applied.');
        notifyListeners();
      }
      _report(error, stackTrace, 'resenha.mediaState');
    }
  }

  Future<void> leave({bool notifyServer = true}) =>
      _leave(notifyServer: notifyServer);

  Future<void> _leave({
    required bool notifyServer,
    bool clearImmediately = false,
  }) async {
    final call = _call;
    if (call == null) return;
    _joinRevision = Object();
    _heartbeat?.cancel();
    _heartbeat = null;
    _call = clearImmediately
        ? null
        : call.copyWith(status: ResenhaCallStatus.leaving);
    if (clearImmediately) onCallSiteChanged();
    notifyListeners();
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
    call.media.removeListener(_mediaChanged);
    await call.media.dispose();
    await systemCall.end();
    if (identical(_call?.media, call.media)) {
      _call = null;
      onCallSiteChanged();
    }
    if (!_disposed) notifyListeners();
  }

  Future<ResenhaRoom?> saveRoom({
    required String siteUrl,
    required ResenhaRoomDraft draft,
    int? roomId,
  }) async {
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null) return null;
    try {
      final room = roomId == null
          ? await api.createRoom(siteUrl: siteUrl, apiKey: apiKey, draft: draft)
          : await api.updateRoom(
              siteUrl: siteUrl,
              roomId: roomId,
              apiKey: apiKey,
              draft: draft,
            );
      await ensureLoaded(siteUrl, force: true);
      return room;
    } catch (error, stackTrace) {
      _errors[siteUrl] = error is WriteException
          ? error.message
          : "Couldn't save the voice room.";
      _report(error, stackTrace, 'resenha.saveRoom');
      notifyListeners();
      return null;
    }
  }

  Future<void> deleteRoom(String siteUrl, int roomId) async {
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null) return;
    try {
      await api.deleteRoom(siteUrl: siteUrl, roomId: roomId, apiKey: apiKey);
      await ensureLoaded(siteUrl, force: true);
    } catch (error, stackTrace) {
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
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null) return;
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
      _chats[key] =
          (_chats[key] ??
                  const ResenhaChatSnapshot(session: ResenhaChatSession()))
              .copyWith(loading: false, error: "Couldn't load room chat.");
      _report(error, stackTrace, 'resenha.chat.load');
    }
    notifyListeners();
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
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null) return;
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
      _chats[key] = state.copyWith(
        loading: false,
        error: "Couldn't load older messages.",
      );
      _report(error, stackTrace, 'resenha.chat.page');
    }
    notifyListeners();
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
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null) return;
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
      }
      if (session.threadId == null) {
        session = await api.firstChatMessage(
          siteUrl: siteUrl,
          roomId: roomId,
          apiKey: apiKey,
          message: text,
        );
      } else if (session.channelId case final channelId?) {
        await chatApi.sendChatMessage(
          siteUrl: siteUrl,
          apiKey: apiKey,
          channelId: channelId,
          threadId: session.threadId,
          message: text,
        );
      }
      _chats[key] = state.copyWith(session: session, sending: false);
      await openChat(siteUrl, roomId, force: true);
    } catch (error, stackTrace) {
      state = _chats[key] ?? state;
      _chats[key] = state.copyWith(sending: false, error: 'Message not sent.');
      _report(error, stackTrace, 'resenha.chat.send');
      notifyListeners();
    }
  }

  Future<void> requestToSpeak({int? userId, bool raised = true}) async {
    final call = _call;
    if (call == null) return;
    final apiKey = await credentials.apiKeyFor(call.siteUrl);
    if (apiKey == null) return;
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
    final apiKey = await credentials.apiKeyFor(call.siteUrl);
    if (apiKey == null) return;
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
    final apiKey = await credentials.apiKeyFor(call.siteUrl);
    if (apiKey == null) return false;
    final flagTypeId = await api.notifyModeratorsFlagType(
      siteUrl: call.siteUrl,
      apiKey: apiKey,
      clientId: await credentials.clientId(),
    );
    if (flagTypeId == null) return false;
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
    final apiKey = await credentials.apiKeyFor(call.siteUrl);
    if (apiKey == null) return;
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
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null) return const [];
    return api.memberships(siteUrl: siteUrl, roomId: roomId, apiKey: apiKey);
  }

  Future<void> addMember(
    String siteUrl,
    int roomId,
    String username,
    ResenhaRole role,
  ) async {
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null) return;
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
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null) return;
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
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (apiKey == null) return;
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
      final status = switch (call.media.connectionState) {
        ResenhaMediaConnectionState.connected => ResenhaCallStatus.connected,
        ResenhaMediaConnectionState.reconnecting =>
          ResenhaCallStatus.reconnecting,
        ResenhaMediaConnectionState.failed => ResenhaCallStatus.failed,
      };
      if (status != call.status && call.status != ResenhaCallStatus.leaving) {
        _call = call.copyWith(
          status: status,
          error: status == ResenhaCallStatus.failed
              ? 'The media connection could not be restored.'
              : null,
          clearError: status == ResenhaCallStatus.connected,
        );
      }
    }
    notifyListeners();
  }

  void _onSystemAction(ResenhaSystemCallAction action) {
    switch (action) {
      case ResenhaSystemCallAction.mute:
        unawaited(_setMuted(true, syncSystem: false));
      case ResenhaSystemCallAction.unmute:
        unawaited(_setMuted(false, syncSystem: false));
      case ResenhaSystemCallAction.end:
        unawaited(leave());
    }
  }

  void forget(String siteUrl) {
    if (_call?.siteUrl == siteUrl) unawaited(leave());
    _directories.remove(siteUrl);
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

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _heartbeat?.cancel();
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
    unawaited(_systemActions.cancel());
    final call = _call;
    if (call != null) {
      call.media.removeListener(_mediaChanged);
      unawaited(call.media.dispose());
    }
    unawaited(systemCall.dispose());
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
