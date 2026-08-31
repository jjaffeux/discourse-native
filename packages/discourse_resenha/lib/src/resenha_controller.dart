// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'resenha_api.dart';
import 'resenha_callkit.dart';
import 'resenha_diagnostics.dart';
import 'resenha_media.dart';
import 'resenha_models.dart';
import 'resenha_preferences.dart';
import 'resenha_signaling.dart';

enum ResenhaCallStatus { joining, connected, reconnecting, leaving, failed }

enum _ResenhaLeaveReason {
  user,
  roomToggle,
  roomSwitch,
  roomDestroyed,
  kicked,
  rosterRemoval,
  credentialsMissing,
  systemAction,
  accountRemoval,
  sessionClose,
}

final class _ResenhaDiagnosticFailure implements Exception {
  const _ResenhaDiagnosticFailure({
    required this.operation,
    required this.errorType,
  });

  final String operation;
  final String errorType;

  @override
  String toString() => 'Resenha operation $operation failed ($errorType).';
}

final class _ResenhaParticipantSession {
  _ResenhaParticipantSession(this.id);

  String? id;
}

String _joinFailureMessage(Object error, ResenhaRoom room) {
  if (error is WriteException) return error.message;
  if (error is ResenhaMicrophoneException) {
    return switch (error.kind) {
      ResenhaMicrophoneFailureKind.permissionDenied =>
        'Microphone access is blocked. Allow microphone access in your '
            'system settings, then try joining again.',
      ResenhaMicrophoneFailureKind.unavailable =>
        "We couldn't access your microphone. Check that it is connected and "
            'not in use by another app, then try again.',
    };
  }
  return "Couldn't join ${room.name}.";
}

String _resenhaSignalingDiagnosticType(Object? value) => switch (value) {
  'offer' => 'offer',
  'answer' => 'answer',
  'candidate' => 'candidate',
  null => 'batch',
  _ => 'unknown',
};

String _resenhaDirectoryDiagnosticType(Object? value) => switch (value) {
  'created' => 'created',
  'updated' => 'updated',
  'destroyed' => 'destroyed',
  _ => 'unknown',
};

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
}

final class _ResenhaChatAssociation {
  _ResenhaChatAssociation({this.session = const ResenhaChatSession()});

  ResenhaChatSession session;
  ChatConversation? conversation;
  VoidCallback? conversationListener;
  bool visible = false;
  bool loading = false;
  bool sending = false;
  String? error;
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

typedef ResenhaTrackerLookup =
    PluginLiveChannelHandle? Function(String siteUrl);
typedef ResenhaUserIdLookup = int? Function(String siteUrl);
typedef ResenhaCapabilityResolver = Future<bool?> Function(String siteUrl);
typedef _ResenhaRequestCredentials = ({String apiKey, String clientId});

/// Optional cancellation boundary for a Resenha message-bus adapter whose
/// native teardown is asynchronous.
abstract interface class ResenhaAwaitableSubscriptionTeardown {
  Future<void> cancelAndWait();
}

Future<bool?> _unknownResenhaCapability(String _) async => null;

/// App-global Resenha state. Directories belong to sites; media belongs to the
/// one call, which deliberately survives selection of another site.
final class ResenhaController extends ChangeNotifier {
  ResenhaController({
    required this.api,
    required this.chatConversations,
    required PluginRequestHost requests,
    required this.trackerFor,
    required ResenhaUserIdLookup userIdFor,
    required VoidCallback onCallSiteChanged,
    ResenhaCapabilityResolver? capabilityEnabledFor,
    this.mediaFactory = const NativeResenhaMediaFactory(),
    ResenhaSystemCall? systemCall,
    PluginDiagnosticsReporter reporter = const PluginDiagnosticsReporter.noop(),
    ResenhaDiagnosticsRecorder? diagnostics,
    ResenhaPreferences? preferences,
    this.heartbeatInterval = const Duration(seconds: 10),
    this.signalBatchDelay = const Duration(milliseconds: 200),
  }) : _requests = requests,
       _userIdFor = userIdFor,
       _onCallSiteChanged = onCallSiteChanged,
       _capabilityEnabledFor =
           capabilityEnabledFor ?? _unknownResenhaCapability,
       _reporter = reporter,
       diagnostics = diagnostics ?? const NoopResenhaDiagnosticsRecorder(),
       systemCall =
           systemCall ??
           NativeResenhaSystemCall(
             diagnostics: diagnostics ?? const NoopResenhaDiagnosticsRecorder(),
           ),
       _preferences =
           preferences ?? const SharedPreferencesResenhaPreferences() {
    _systemActions = this.systemCall.actions.listen(_onSystemAction);
    unawaited(_restoreDevicePreferences());
  }

  final ResenhaApi api;
  final ChatConversationCapability chatConversations;
  final PluginRequestHost _requests;
  final ResenhaTrackerLookup trackerFor;
  final ResenhaUserIdLookup _userIdFor;
  final ResenhaCapabilityResolver _capabilityEnabledFor;
  final VoidCallback _onCallSiteChanged;
  final ResenhaMediaFactory mediaFactory;
  final ResenhaSystemCall systemCall;
  final PluginDiagnosticsReporter _reporter;
  final ResenhaDiagnosticsRecorder diagnostics;
  final ResenhaPreferences _preferences;
  final Duration heartbeatInterval;
  final Duration signalBatchDelay;
  // Cancelled and awaited by the idempotent close lifecycle below.
  // ignore: cancel_subscriptions
  late final StreamSubscription<ResenhaSystemCallAction> _systemActions;

  final Map<String, ResenhaDirectory> _directories = {};
  final Map<String, PluginLiveChannelHandle> _attachedTrackers = {};
  final Map<String, Map<int, ResenhaRoom>> _linkedRooms = {};
  final Set<String> _loadingSites = {};
  final Set<String> _unavailableSites = {};
  final Map<String, PluginLiveChannelSubscription> _directorySubscriptions = {};
  final Map<String, Map<int, PluginLiveChannelSubscription>>
  _roomSubscriptions = {};
  final Map<String, String> _errors = {};
  final Map<String, _ResenhaChatAssociation> _chats = {};
  final Map<String, Object> _siteSessions = {};
  final Map<String, Object> _directoryRequests = {};
  final Map<String, Object> _chatRequests = {};
  final Map<String, int> _roomVideoWatchers = {};
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
  ResenhaMediaSession? _leavingMedia;
  Future<void>? _closeOperation;
  final Expando<Future<void>> _mediaDisposals = Expando<Future<void>>();
  final Expando<String> _mediaCorrelations = Expando<String>();
  final Expando<_ResenhaParticipantSession> _participantSessions =
      Expando<_ResenhaParticipantSession>();
  final Expando<ResenhaSignalBatcher> _signalBatchers =
      Expando<ResenhaSignalBatcher>();
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

  int? currentUserIdFor(String siteUrl) => _userIdFor(siteUrl);

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
  ResenhaChatSnapshot? chat(String siteUrl, int roomId) {
    final state = _chats['$siteUrl#$roomId'];
    if (state == null) return null;
    final conversation = state.conversation?.value;
    return ResenhaChatSnapshot(
      session: state.session,
      messages: conversation?.messages ?? const [],
      loading: state.loading || (conversation?.loading ?? false),
      sending: state.sending || (conversation?.sending ?? false),
      canLoadMorePast: conversation?.canLoadMorePast ?? false,
      error: state.error ?? conversation?.error,
    );
  }

  ResenhaRoom? room(String siteUrl, int roomId) {
    for (final room in _directories[siteUrl]?.rooms ?? const <ResenhaRoom>[]) {
      if (room.id == roomId) return room;
    }
    final call = _call;
    if (call?.siteUrl == siteUrl && call?.room.id == roomId) return call?.room;
    return _linkedRooms[siteUrl]?[roomId];
  }

  Future<ResenhaRoom?> resolveRoom(String siteUrl, String slug) =>
      _runPublicValueOperation<ResenhaRoom?>(
        () => _resolveRoom(siteUrl, slug),
        'resenha.room',
        fallback: null,
      );

  Future<ResenhaRoom?> _resolveRoom(String siteUrl, String slug) async {
    if (_unavailableSites.contains(siteUrl)) return null;
    final capabilityEnabled = await _capabilityEnabledFor(siteUrl);
    if (capabilityEnabled == false) return null;
    final directory = _directories[siteUrl];
    for (final room in directory?.rooms ?? const <ResenhaRoom>[]) {
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
      (_linkedRooms[siteUrl] ??= {})[room.id] = room;
      notifyListeners();
      return room;
    } catch (error, stackTrace) {
      if (isCurrent()) _report(error, stackTrace, 'resenha.room');
      return null;
    }
  }

  Future<void> ensureLoaded(String siteUrl, {bool force = false}) =>
      _runPublicOperation(
        () => _ensureLoaded(siteUrl, force: force),
        'resenha.directory',
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
      _replaceSubscriptions(siteUrl, directory);
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

  Future<_ResenhaRequestCredentials?> _requestCredentials(
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

  bool _isCurrentCall(ResenhaCallSnapshot call, Object siteSession) =>
      _isCurrentSiteSession(call.siteUrl, siteSession) &&
      identical(_call?.media, call.media) &&
      _call?.status != ResenhaCallStatus.leaving;

  void attachTracker(String siteUrl, [PluginLiveChannelHandle? tracker]) {
    final replaced =
        tracker != null && !identical(_attachedTrackers[siteUrl], tracker);
    if (replaced) {
      _cancelTrackerSubscriptions(siteUrl);
      _attachedTrackers[siteUrl] = tracker;
    }
    final directory = _directories[siteUrl];
    if (directory != null) _replaceSubscriptions(siteUrl, directory);
  }

  PluginLiveChannelHandle? _trackerFor(String siteUrl) =>
      _attachedTrackers[siteUrl] ?? trackerFor(siteUrl);

  void _cancelTrackerSubscriptions(String siteUrl) {
    _directorySubscriptions.remove(siteUrl)?.cancel();
    for (final subscription
        in _roomSubscriptions.remove(siteUrl)?.values ??
            const <PluginLiveChannelSubscription>[]) {
      subscription.cancel();
    }
  }

  void _replaceSubscriptions(String siteUrl, ResenhaDirectory directory) {
    final tracker = _trackerFor(siteUrl);
    if (tracker == null) return;
    _record(
      'room.subscriptions.synced',
      component: 'room',
      correlationId: _correlationForSite(siteUrl),
      data: {'roomCount': directory.rooms.length},
    );
    _directorySubscriptions.remove(siteUrl)?.cancel();
    _directorySubscriptions[siteUrl] = tracker.subscribe(
      '/resenha/rooms/index',
      (data, _) => _onDirectoryEvent(siteUrl, data),
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
        () => tracker.subscribe(
          '/resenha/rooms/${room.id}',
          (data, _) => _onRoomEvent(siteUrl, room.id, data),
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
    final call = _call;
    _record(
      'room.directory_event',
      component: 'room',
      correlationId: call?.siteUrl == siteUrl && call?.room.id == incoming.id
          ? _correlationFor(call)
          : null,
      data: {
        ..._roomDiagnosticData(incoming),
        'type': _resenhaDirectoryDiagnosticType(data['type']),
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
      case 'destroyed':
        rooms.removeWhere((room) => room.id == incoming.id);
        _removeChatAssociation(siteUrl, incoming.id);
        if (_call case final call?
            when call.siteUrl == siteUrl && call.room.id == incoming.id) {
          _observe(
            () => _leave(
              notifyServer: false,
              reason: _ResenhaLeaveReason.roomDestroyed,
            ),
            'resenha.roomDestroyed',
          );
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
      _observe(
        () => _handleSignalEnvelope(siteUrl, roomId, data),
        'resenha.media.signal',
      );
      return;
    }
    final event = ResenhaRoomEvent.fromJson(data);
    if (event == null) return;
    if (event is ResenhaKickedEvent) {
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
          () => _leave(notifyServer: false, reason: _ResenhaLeaveReason.kicked),
          'resenha.kicked',
        );
      }
      return;
    }
    if (event is ResenhaRoleChangedEvent) {
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
      return;
    }
    if (event is ResenhaParticipantsEvent) {
      _recordRoster(
        'room.roster_received',
        siteUrl,
        roomId,
        event.participants,
        correlationId: _correlationForRoom(siteUrl, roomId),
      );
      _replaceParticipants(siteUrl, roomId, event.participants);
    }
    if (event is ResenhaRecordingEvent) {
      _record(
        'room.recording_changed',
        component: 'room',
        correlationId: _correlationForRoom(siteUrl, roomId),
        data: {'roomId': roomId, 'active': event.recording?.active ?? false},
      );
      _replaceRecording(siteUrl, roomId, event.recording);
    }
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
          'type': _resenhaSignalingDiagnosticType(first['type']),
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

    // Resenha attests the sender and includes their basic serialization so an
    // offer can beat the asynchronous roster broadcast without creating an
    // invisible peer. Stage rooms still wait for the authoritative roster,
    // because the basic serialization does not carry the sender's stage role.
    if (activeCall.room.type == ResenhaRoomType.open &&
        events.any((event) => event['type'] == 'offer') &&
        !activeCall.room.participants.any(
          (participant) => participant.id == senderId,
        )) {
      final rawSender = envelope['sender'];
      if (rawSender is Map) {
        final participant = ResenhaParticipant.fromJson(
          Map<String, dynamic>.from(rawSender),
        );
        if (participant.id == senderId) {
          final participants = [...activeCall.room.participants, participant];
          final held = _directories[siteUrl];
          if (held != null) {
            _directories[siteUrl] = ResenhaDirectory(
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
      final userId = _userIdFor(siteUrl);
      // Room subscriptions are cursored from the directory load, not from the
      // join response, so a roster published before join.json committed can
      // still be delivered while the join settles. The local user's absence
      // from such a roster is not evidence of removal until the call has
      // connected.
      if (call.status != ResenhaCallStatus.leaving &&
          call.status != ResenhaCallStatus.joining &&
          userId != null &&
          !participants.any((participant) => participant.id == userId)) {
        _observe(
          () => _leave(
            notifyServer: false,
            clearImmediately: true,
            reason: _ResenhaLeaveReason.rosterRemoval,
          ),
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
      'resenha.join',
      correlationId: correlationId,
    );
    final operation = _reporter.runOperation(
      'resenha.join',
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
    required ResenhaRoom room,
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
      await _leave(notifyServer: true, reason: _ResenhaLeaveReason.roomToggle);
      return;
    }
    if (held != null) {
      await _leave(notifyServer: true, reason: _ResenhaLeaveReason.roomSwitch);
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
    ResenhaMediaSession? media;
    _ResenhaParticipantSession? participantSession;
    String? joinedParticipantSessionId;
    var serverJoinActive = false;
    try {
      late ResenhaJoinResponse response;
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
          'resenha.leaveSupersededJoin',
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
      final session = _ResenhaParticipantSession(response.participantSessionId);
      participantSession = session;
      final signalBatcher = ResenhaSignalBatcher(
        batchDelay: signalBatchDelay,
        sendBatch: (payload) async {
          await _reporter.runOperation(
            'resenha.signal',
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
          _record(
            'signaling.send.started',
            component: 'signaling',
            correlationId: correlationId,
            data: {
              'roomId': room.id,
              'recipientPresent': true,
              'type': _resenhaSignalingDiagnosticType(event['type']),
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
            'resenha.livekitToken',
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
          'resenha.leaveCancelledJoin',
        );
        serverJoinActive = false;
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
      if (systemCall case final NativeResenhaSystemCall nativeSystemCall) {
        nativeSystemCall.associateDiagnostics(correlationId);
      }
      _record(
        'call.status_changed',
        correlationId: correlationId,
        data: {
          'from': null,
          'to': ResenhaCallStatus.joining.name,
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
        await _traceDeviceSelection(
          kind: 'audio_input',
          origin: 'saved_join',
          deviceId: deviceId,
          applied: true,
          correlationId: correlationId,
          action: () => media!.selectAudioInput(deviceId),
        );
        if (!isCurrent()) return;
      }
      if (_audioOutputDeviceId case final deviceId?) {
        await _traceDeviceSelection(
          kind: 'audio_output',
          origin: 'saved_join',
          deviceId: deviceId,
          applied: true,
          correlationId: correlationId,
          action: () => media!.selectAudioOutput(deviceId),
        );
        if (!isCurrent()) return;
      }
      _call = _call?.copyWith(
        status: ResenhaCallStatus.connected,
        clearError: true,
      );
      _record(
        'call.status_changed',
        correlationId: correlationId,
        data: {
          'from': ResenhaCallStatus.joining.name,
          'to': ResenhaCallStatus.connected.name,
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
        await _disposeMedia(activeMedia, 'resenha.media.disposeAfterJoin');
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
          'resenha.leaveFailedJoin',
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
      await _runHandled(systemCall.failed, 'resenha.systemCall.failed');
      if (systemCall case final NativeResenhaSystemCall nativeSystemCall) {
        nativeSystemCall.associateDiagnostics(null);
      }
      if (isCurrent()) {
        _call = null;
        _errors[siteUrl] = _joinFailureMessage(error, room);
        _onCallSiteChanged();
        notifyListeners();
      }
      if (isCurrent()) _report(error, stackTrace, 'resenha.join');
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
          reason: _ResenhaLeaveReason.credentialsMissing,
        );
        return;
      }
      await _reporter.runOperation(
        'resenha.heartbeat',
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
        _report(error, stackTrace, 'resenha.heartbeat');
      }
    }
  }

  void setForeground(bool foreground) {
    if (_disposed) return;
    _idleState = foreground ? ResenhaIdleState.active : ResenhaIdleState.afk;
    if (_call != null) unawaited(_requestHeartbeat());
  }

  Future<void> setMuted(bool muted) => _setMuted(muted, syncSystem: true);

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

  Future<void> setDeafened(bool deafened) => _updateMediaState(
    media: (call) => call.media.setDeafened(deafened),
    update: (call) => call.copyWith(deafened: deafened),
    rollback: (current, previous) =>
        current.copyWith(deafened: previous.deafened),
  );

  Future<void> setCameraEnabled(bool enabled, {String? deviceId}) =>
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
        'resenha.media.devices',
        fallback: const [],
      );

  Future<void> selectAudioInput(String deviceId) => _runPublicOperation(
    () => _selectAudioInput(deviceId),
    'resenha.media.selectAudioInput',
    correlationId: _activeDiagnosticCorrelationId,
  );

  Future<void> _selectAudioInput(String deviceId) async {
    if (_disposed) return;
    _audioInputDeviceId = deviceId;
    final correlationId =
        _activeDiagnosticCorrelationId ??
        _reporter.newCorrelationId('resenha-device');
    await _traceDeviceSelection(
      kind: 'audio_input',
      origin: 'user',
      deviceId: deviceId,
      applied: _call != null,
      correlationId: correlationId,
      action: () async {
        await _persistPreference(
          () => _preferences.writeDevice(
            ResenhaDevicePreference.audioInput,
            deviceId,
          ),
          'resenha.preferences.audioInput',
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
    'resenha.media.selectAudioOutput',
    correlationId: _activeDiagnosticCorrelationId,
  );

  Future<void> _selectAudioOutput(String deviceId) async {
    if (_disposed) return;
    _audioOutputDeviceId = deviceId;
    final correlationId =
        _activeDiagnosticCorrelationId ??
        _reporter.newCorrelationId('resenha-device');
    await _traceDeviceSelection(
      kind: 'audio_output',
      origin: 'user',
      deviceId: deviceId,
      applied: _call != null,
      correlationId: correlationId,
      action: () async {
        await _persistPreference(
          () => _preferences.writeDevice(
            ResenhaDevicePreference.audioOutput,
            deviceId,
          ),
          'resenha.preferences.audioOutput',
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
    'resenha.media.selectCamera',
    correlationId: _activeDiagnosticCorrelationId,
  );

  Future<void> _selectCamera(String deviceId) async {
    if (_disposed) return;
    _cameraDeviceId = deviceId;
    final correlationId =
        _activeDiagnosticCorrelationId ??
        _reporter.newCorrelationId('resenha-device');
    await _traceDeviceSelection(
      kind: 'camera',
      origin: 'user',
      deviceId: deviceId,
      applied: _call?.cameraEnabled == true,
      correlationId: correlationId,
      action: () async {
        await _persistPreference(
          () => _preferences.writeDevice(
            ResenhaDevicePreference.camera,
            deviceId,
          ),
          'resenha.preferences.camera',
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
  ) => _runPublicOperation(
    () => _setParticipantVolume(siteUrl, roomId, userId, volume),
    'resenha.media.participantVolume',
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
      'resenha.preferences.writeVolume',
    );
  }

  Future<void> _restoreDevicePreferences() async {
    final correlationId = _reporter.newCorrelationId('resenha-preferences');
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
      _report(error, stackTrace, 'resenha.preferences.restore');
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

  Future<void> setScreenSharing(bool enabled) => _updateMediaState(
    media: (call) => call.media.setScreenShareEnabled(enabled),
    update: (call) => call.copyWith(screenSharing: enabled),
    rollback: (current, previous) =>
        current.copyWith(screenSharing: previous.screenSharing),
  );

  Future<void> _updateMediaState({
    required Future<void> Function(ResenhaCallSnapshot call) media,
    required ResenhaCallSnapshot Function(ResenhaCallSnapshot call) update,
    required ResenhaCallSnapshot Function(
      ResenhaCallSnapshot current,
      ResenhaCallSnapshot previous,
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
      if (call == null || call.status == ResenhaCallStatus.leaving) return;
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
          'resenha.state',
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
          _report(error, stackTrace, 'resenha.state');
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
        if (isCurrent()) _report(error, stackTrace, 'resenha.state');
        return;
      }
    }
  }

  Future<void> leave({bool notifyServer = true}) =>
      _leave(notifyServer: notifyServer, reason: _ResenhaLeaveReason.user);

  Future<void> _leave({
    required bool notifyServer,
    required _ResenhaLeaveReason reason,
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
        : call.copyWith(status: ResenhaCallStatus.leaving);
    if (!clearImmediately && call.status != ResenhaCallStatus.leaving) {
      _record(
        'call.status_changed',
        correlationId: correlationId,
        data: {
          'from': call.status.name,
          'to': ResenhaCallStatus.leaving.name,
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
    ResenhaCallSnapshot call, {
    required bool notifyServer,
    required _ResenhaLeaveReason reason,
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
              'resenha.leave',
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
          _report(error, stackTrace, 'resenha.leave');
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
        _report(error, stackTrace, 'resenha.media.removeListener');
      }
      _record(
        'media.dispose.started',
        component: 'media',
        correlationId: correlationId,
      );
      await _disposeMedia(call.media, 'resenha.media.dispose');
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
      await _runHandled(systemCall.end, 'resenha.systemCall.end');
      _record(
        'callkit.command.completed',
        component: 'callkit',
        correlationId: correlationId,
        data: {'command': 'end'},
      );
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'resenha.leave.dispose');
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
          _report(error, stackTrace, 'resenha.callSiteChanged.dispose');
        }
      }
      _record(
        'call.leave.completed',
        correlationId: correlationId,
        data: {'reason': reason.name},
      );
      if (systemCall case final NativeResenhaSystemCall nativeSystemCall) {
        nativeSystemCall.associateDiagnostics(null);
      }
      if (!_disposed) {
        try {
          notifyListeners();
        } catch (error, stackTrace) {
          _report(error, stackTrace, 'resenha.listeners.dispose');
        }
      }
      if (!completion.isCompleted) completion.complete();
    }
  }

  Future<ResenhaRoom?> saveRoom({
    required String siteUrl,
    required ResenhaRoomDraft draft,
    int? roomId,
  }) => _runPublicValueOperation<ResenhaRoom?>(
    () => _saveRoom(siteUrl: siteUrl, draft: draft, roomId: roomId),
    'resenha.saveRoom',
    fallback: null,
  );

  Future<ResenhaRoom?> _saveRoom({
    required String siteUrl,
    required ResenhaRoomDraft draft,
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
      _report(error, stackTrace, 'resenha.saveRoom');
      notifyListeners();
      return null;
    }
  }

  Future<void> deleteRoom(String siteUrl, int roomId) => _runPublicOperation(
    () => _deleteRoom(siteUrl, roomId),
    'resenha.deleteRoom',
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
      _report(error, stackTrace, 'resenha.deleteRoom');
      notifyListeners();
    }
  }

  Future<void> openChat(String siteUrl, int roomId, {bool force = false}) =>
      _runPublicOperation(
        () => _openChat(siteUrl, roomId, force: force),
        'resenha.chat.load',
      );

  void closeChat(String siteUrl, int roomId) {
    final key = '$siteUrl#$roomId';
    _chatRequests.remove(key);
    final state = _chats[key];
    if (state == null) return;
    state
      ..visible = false
      ..loading = false;
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
    final state = _chats.putIfAbsent(key, _ResenhaChatAssociation.new);
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
      final conversation = _bindChatConversation(siteUrl, key, state);
      if (conversation != null) await conversation.refresh(force: force);
    } catch (error, stackTrace) {
      if (!isCurrent()) return;
      state.error = "Couldn't load room chat.";
      _report(error, stackTrace, 'resenha.chat.load');
    } finally {
      if (isCurrent()) {
        _chatRequests.remove(key);
        state.loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadOlderChat(String siteUrl, int roomId) =>
      _chats['$siteUrl#$roomId']?.conversation?.loadOlder() ??
      Future<void>.value();

  Future<void> sendChatMessage(String siteUrl, int roomId, String message) =>
      _runPublicOperation(
        () => _sendChatMessage(siteUrl, roomId, message),
        'resenha.chat.send',
      );

  Future<void> _sendChatMessage(
    String siteUrl,
    int roomId,
    String message,
  ) async {
    final text = message.trim();
    if (text.isEmpty) return;
    final key = '$siteUrl#$roomId';
    var state = _chats.putIfAbsent(key, _ResenhaChatAssociation.new);
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
      _report(error, stackTrace, 'resenha.chat.send');
      notifyListeners();
    }
  }

  ChatConversation? _bindChatConversation(
    String siteUrl,
    String key,
    _ResenhaChatAssociation state,
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
    ResenhaChatSession session,
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

  void _closeChatConversation(_ResenhaChatAssociation state) {
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
    if (state != null) _closeChatConversation(state);
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
      if (state != null) _closeChatConversation(state);
    }
  }

  Future<void> requestToSpeak({int? userId, bool raised = true}) =>
      _runPublicOperation(
        () => _requestToSpeak(userId: userId, raised: raised),
        'resenha.requestToSpeak',
        correlationId: _activeDiagnosticCorrelationId,
      );

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

  Future<void> kick(int userId) => _runPublicOperation(
    () => _kick(userId),
    'resenha.kick',
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
        'resenha.flag',
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
    'resenha.recording',
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

  Future<List<ResenhaMembership>> memberships(String siteUrl, int roomId) =>
      _runPublicValueOperation<List<ResenhaMembership>>(
        () => _memberships(siteUrl, roomId),
        'resenha.memberships',
        fallback: const [],
      );

  Future<List<ResenhaMembership>> _memberships(
    String siteUrl,
    int roomId,
  ) async {
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
    ResenhaRole role,
  ) => _runPublicOperation(
    () => _addMember(siteUrl, roomId, username, role),
    'resenha.membership.add',
  );

  Future<void> _addMember(
    String siteUrl,
    int roomId,
    String username,
    ResenhaRole role,
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
    ResenhaRole role,
  ) => _runPublicOperation(
    () => _updateMember(siteUrl, roomId, membershipId, role),
    'resenha.membership.update',
  );

  Future<void> _updateMember(
    String siteUrl,
    int roomId,
    int membershipId,
    ResenhaRole role,
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
        'resenha.membership.remove',
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
      var updated = call;
      final status = switch (call.media.connectionState) {
        ResenhaMediaConnectionState.connected => ResenhaCallStatus.connected,
        ResenhaMediaConnectionState.reconnecting =>
          ResenhaCallStatus.reconnecting,
        ResenhaMediaConnectionState.failed => ResenhaCallStatus.failed,
      };
      // Only a call that has already settled takes its status from the media
      // layer. A join reaches `connected` at the end of its own sequence —
      // after the state sync, the saved devices and the platform call — and
      // the transports notify from inside `connect()`, so letting media
      // promote a `joining` call would announce the call before any of that
      // ran and would lift the guard that keeps a roster published before
      // join.json committed from tearing the call down.
      if (status != call.status &&
          call.status != ResenhaCallStatus.leaving &&
          call.status != ResenhaCallStatus.joining) {
        _record(
          'call.status_changed',
          correlationId: _correlationFor(call),
          severity: status == ResenhaCallStatus.failed
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
      if (updated.status == ResenhaCallStatus.connected &&
          call.status != ResenhaCallStatus.connected) {
        _startHeartbeat();
      }
      if (screenShareEnded) unawaited(_requestStateSync());
    }
    notifyListeners();
  }

  void _onSystemAction(ResenhaSystemCallAction action) {
    _record(
      'callkit.action',
      component: 'callkit',
      correlationId: _correlationFor(_call),
      data: {'action': action.name},
    );
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
        _observe(
          () => _leave(
            notifyServer: true,
            reason: _ResenhaLeaveReason.systemAction,
          ),
          'resenha.systemAction.end',
        );
    }
  }

  void forget(String siteUrl) {
    if (_call?.siteUrl == siteUrl) {
      _observe(
        () => _leave(
          notifyServer: true,
          reason: _ResenhaLeaveReason.accountRemoval,
        ),
        'resenha.accountRemoval',
      );
    }
    _siteSessions.remove(siteUrl);
    _directoryRequests.remove(siteUrl);
    _chatRequests.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _directories.remove(siteUrl);
    _attachedTrackers.remove(siteUrl);
    _unavailableSites.remove(siteUrl);
    _linkedRooms.remove(siteUrl);
    final forgottenChats = <_ResenhaChatAssociation>[];
    _chats.removeWhere((key, state) {
      if (!key.startsWith('$siteUrl#')) return false;
      forgottenChats.add(state);
      return true;
    });
    for (final state in forgottenChats) {
      _closeChatConversation(state);
    }
    _cancelTrackerSubscriptions(siteUrl);
    _errors.remove(siteUrl);
    _loadingSites.remove(siteUrl);
    if (!_disposed) notifyListeners();
  }

  String _nextCallCorrelationId() {
    return _reporter.newCorrelationId('resenha-call');
  }

  String? _correlationFor(ResenhaCallSnapshot? call) =>
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

  Map<String, Object?> _roomDiagnosticData(ResenhaRoom room) => {
    'roomId': room.id,
    'roomType': room.type.name,
    'participantCount': room.participants.length,
  };

  Map<String, Object?> _rawRoomDiagnosticData(
    String siteUrl,
    ResenhaRoom room, {
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
    List<ResenhaParticipant> participants, {
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
        _ResenhaDiagnosticFailure(
          operation: operation,
          errorType: error.runtimeType.toString(),
        ),
        stackTrace,
        operation: operation,
        source: 'resenha',
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

  Future<void> _disposeMedia(ResenhaMediaSession media, String operation) {
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
    _attachedTrackers.clear();
    for (final state in _chats.values) {
      _closeChatConversation(state);
    }
    _chats.clear();
    final subscriptionCancellation = _cancelSubscriptions();

    final systemActionsCancellation = _runHandled(
      _systemActions.cancel,
      'resenha.systemActions.dispose',
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
      for (final siteSubscriptions in _roomSubscriptions.values)
        ...siteSubscriptions.values,
    ];
    _directorySubscriptions.clear();
    _roomSubscriptions.clear();
    return Future.wait([
      for (final subscription in subscriptions)
        _cancelSubscription(subscription),
    ]);
  }

  Future<void> _cancelSubscription(
    PluginLiveChannelSubscription subscription,
  ) async {
    try {
      if (subscription case final ResenhaAwaitableSubscriptionTeardown value) {
        await value.cancelAndWait();
      } else {
        subscription.cancel();
      }
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'resenha.subscription.dispose');
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
          : _leave(
              notifyServer: true,
              reason: _ResenhaLeaveReason.sessionClose,
            );
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
          reason: _ResenhaLeaveReason.sessionClose,
        );
        assert(!identical(_call?.media, lateCall.media));
      }
    }, 'resenha.session.leave');

    await _runHandled(() async {
      final stateSync = _stateSync;
      if (stateSync != null) await stateSync;
      final heartbeatRequest = _heartbeatRequest;
      if (heartbeatRequest != null) await heartbeatRequest;
    }, 'resenha.session.requests.dispose');
    await subscriptionCancellation;
    await systemActionsCancellation;
    await _runHandled(systemCall.dispose, 'resenha.systemCall.dispose');

    _record('session.close.completed', component: 'lifecycle');
    if (diagnostics case final ResenhaDiagnosticsFlusher flusher) {
      await _runHandled(flusher.flushDiagnostics, 'resenha.diagnostics.flush');
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

extension on ResenhaRoom {
  /// A refreshed room, keeping whatever the held copy could see that this one
  /// could not. A directory listing is answered to whoever asked for it, so a
  /// room fetched anonymously omits the management and chat fields the joined
  /// copy already carries.
  ResenhaRoom copyWithPrivileged(ResenhaRoom held) => copyWith(
    canManage: canManage || held.canManage,
    chatAvailable: chatAvailable || held.chatAvailable,
    chatChannelId: chatChannelId ?? held.chatChannelId,
    chatIdleMinutes: chatIdleMinutes ?? held.chatIdleMinutes,
    livekitEnabled: livekitEnabled ?? held.livekitEnabled,
    membership: membership ?? held.membership,
    recording: recording ?? held.recording,
  );
}
