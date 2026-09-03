import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import 'voice_diagnostics.dart';
import 'voice_livekit_endpoint.dart';
import 'voice_models.dart';
import 'voice_reconnect.dart';

export 'voice_reconnect.dart' show VoiceMediaConnectionState;

typedef VoiceSignalSender =
    Future<void> Function(int recipientId, Map<String, Object?> event);
typedef VoiceLiveKitCredentialRefresher =
    Future<VoiceLiveKitCredentials> Function();
typedef VoicePeerConnectionCreator =
    Future<rtc.RTCPeerConnection> Function(Map<String, dynamic> configuration);
typedef VoiceUserMediaGetter =
    Future<rtc.MediaStream> Function(Map<String, dynamic> constraints);
typedef VoiceMediaDeviceEnumerator =
    Future<List<rtc.MediaDeviceInfo>> Function();
typedef VoiceTrackVolumeSetter =
    Future<void> Function(double volume, rtc.MediaStreamTrack track);
typedef VoiceLiveKitRawStatsCollector =
    Future<List<Map<String, Object?>>> Function(lk.Room room);

enum VoiceMicrophoneFailureKind { permissionDenied, unavailable }

final class VoiceMicrophoneException implements Exception {
  const VoiceMicrophoneException(this.kind);

  factory VoiceMicrophoneException.from(Object error) {
    final message = error.toString().toLowerCase();
    final permissionDenied = <String>[
      'notallowed',
      'not allowed',
      'permissiondenied',
      'permission denied',
      'permission dismissed',
      'notauthorized',
      'not authorized',
      'media access denied',
    ].any(message.contains);
    return VoiceMicrophoneException(
      permissionDenied
          ? VoiceMicrophoneFailureKind.permissionDenied
          : VoiceMicrophoneFailureKind.unavailable,
    );
  }

  final VoiceMicrophoneFailureKind kind;

  @override
  String toString() => switch (kind) {
    VoiceMicrophoneFailureKind.permissionDenied =>
      'Microphone permission was denied.',
    VoiceMicrophoneFailureKind.unavailable => 'The microphone is unavailable.',
  };
}

Future<T> _withMicrophoneFailure<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on VoiceMicrophoneException {
    rethrow;
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(VoiceMicrophoneException.from(error), stackTrace);
  }
}

final class _VoiceMediaDiagnosticFailure implements Exception {
  const _VoiceMediaDiagnosticFailure(this.operation);

  final String operation;

  @override
  String toString() => 'Voice media operation $operation failed.';
}

abstract interface class VoiceLiveKitRoomAdapter {
  lk.Room get room;

  void listen({
    required VoidCallback onChanged,
    required VoidCallback onDisconnected,
  });
  Future<void> connect(String endpoint, String token);
  Future<void> cancelListener();
  Future<void> disconnect();
  Future<void> disposeRoom();
}

abstract interface class VoiceMediaSession implements Listenable {
  VoiceTransport get transport;
  VoiceMediaConnectionState get connectionState;
  Object? get localVideoTrack;
  bool get screenSharing;
  Object? videoTrackFor(int participantId);
  Set<int> get speakingParticipantIds;

  Future<void> connect();
  Future<void> syncParticipants(List<VoiceParticipant> participants);
  Future<void> handleSignal(int senderId, Map<String, dynamic> data);
  Future<void> setAudioPublishingAllowed(bool allowed);
  Future<void> setMuted(bool muted);
  Future<void> setDeafened(bool deafened);
  Future<void> setCameraEnabled(bool enabled, {String? deviceId});
  Future<void> setScreenShareEnabled(bool enabled);
  Future<void> setParticipantVolume(int participantId, double volume);
  Future<List<rtc.MediaDeviceInfo>> devices();
  Future<void> selectAudioInput(String deviceId);
  Future<void> selectAudioOutput(String deviceId);
  Future<void> dispose();
}

abstract interface class VoiceMediaFactory {
  VoiceMediaSession create({
    required VoiceJoinResponse join,
    required int localUserId,
    required VoiceSignalSender sendSignal,
    required VoiceLiveKitCredentialRefresher refreshLiveKitCredentials,
    VoiceDiagnosticsRecorder diagnostics = const NoopVoiceDiagnosticsRecorder(),
    String correlationId = 'uncorrelated',
  });
}

final class NativeVoiceMediaFactory implements VoiceMediaFactory {
  const NativeVoiceMediaFactory();

  @override
  VoiceMediaSession create({
    required VoiceJoinResponse join,
    required int localUserId,
    required VoiceSignalSender sendSignal,
    required VoiceLiveKitCredentialRefresher refreshLiveKitCredentials,
    VoiceDiagnosticsRecorder diagnostics = const NoopVoiceDiagnosticsRecorder(),
    String correlationId = 'uncorrelated',
  }) => switch (join.transport) {
    VoiceTransport.mesh => MeshVoiceMediaSession(
      join: join,
      localUserId: localUserId,
      sendSignal: sendSignal,
      audioPublishingAllowed: _canPublishAudio(join.room, localUserId),
      diagnostics: diagnostics,
      correlationId: correlationId,
    ),
    VoiceTransport.livekit => LiveKitVoiceMediaSession(
      join: join,
      localUserId: localUserId,
      audioPublishingAllowed: _canPublishAudio(join.room, localUserId),
      refreshCredentials: refreshLiveKitCredentials,
      diagnostics: diagnostics,
      correlationId: correlationId,
    ),
  };

  static bool _canPublishAudio(VoiceRoom room, int userId) {
    if (room.type != VoiceRoomType.stage) return true;
    final role = room.participants
        .where((participant) => participant.id == userId)
        .firstOrNull
        ?.role;
    final effective = role ?? room.membership?.role;
    return effective == VoiceRole.moderator || effective == VoiceRole.speaker;
  }
}

void _recordDiagnostic(
  VoiceDiagnosticsRecorder diagnostics,
  String event, {
  required String component,
  required String correlationId,
  DiagnosticSeverity severity = DiagnosticSeverity.info,
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

void _recordRawDiagnostic(
  VoiceDiagnosticsRecorder diagnostics,
  String event, {
  required String component,
  required String correlationId,
  DiagnosticSeverity severity = DiagnosticSeverity.debug,
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

String _diagnosticEnumName(Object? value) {
  final text = '$value';
  final separator = text.lastIndexOf('.');
  return separator < 0 ? text : text.substring(separator + 1);
}

String _diagnosticSignalType(Object? value) => switch (value) {
  'offer' => 'offer',
  'answer' => 'answer',
  'candidate' => 'candidate',
  null => 'batch',
  _ => 'unknown',
};

List<Map<String, Object?>> _serializeStatsReports(
  List<rtc.StatsReport> reports,
) => [
  for (final report in reports)
    {
      'id': report.id,
      'type': report.type,
      'timestamp': report.timestamp,
      'values': {
        for (final value in report.values.entries) '${value.key}': value.value,
      },
    },
];

Future<List<Map<String, Object?>>> _collectLiveKitRawStats(lk.Room room) async {
  final samples = <Map<String, Object?>>[];
  final participants = <lk.Participant>[
    ?room.localParticipant,
    ...room.remoteParticipants.values,
  ];
  for (final participant in participants) {
    for (final publication in participant.trackPublications.values) {
      final track = publication.track;
      if (track == null) continue;
      final endpoints = <(String, Object?)>[
        ('sender', track.sender),
        ('receiver', track.receiver),
      ];
      for (final (direction, endpoint) in endpoints) {
        if (endpoint == null) continue;
        final context = <String, Object?>{
          'participantSid': participant.sid,
          'participantIdentity': participant.identity,
          'participantName': participant.name,
          'trackSid': publication.sid,
          'trackName': publication.name,
          'kind': publication.kind.name,
          'source': publication.source.name,
          'direction': direction,
        };
        try {
          final reports = switch (endpoint) {
            rtc.RTCRtpSender sender => await sender.getStats(),
            rtc.RTCRtpReceiver receiver => await receiver.getStats(),
            _ => const <rtc.StatsReport>[],
          };
          samples.add({...context, 'reports': _serializeStatsReports(reports)});
        } catch (error, stackTrace) {
          samples.add({
            ...context,
            'errorType': error.runtimeType.toString(),
            'error': error.toString(),
            'stackTrace': stackTrace.toString(),
          });
        }
      }
    }
  }
  return samples;
}

Future<List<rtc.MediaDeviceInfo>> _enumerateDevicesWithDiagnostics({
  required VoiceMediaDeviceEnumerator enumerateDevices,
  required VoiceDiagnosticsRecorder diagnostics,
  required String correlationId,
}) async {
  try {
    final devices = await enumerateDevices();
    _recordRawDiagnostic(
      diagnostics,
      'media.devices.enumerated',
      component: 'webrtc',
      correlationId: correlationId,
      data: {
        'count': devices.length,
        'devices': [
          for (final device in devices)
            {
              'deviceId': device.deviceId,
              'groupId': device.groupId,
              'kind': device.kind,
              'label': device.label,
            },
        ],
      },
    );
    return devices;
  } catch (error, stackTrace) {
    _recordRawDiagnostic(
      diagnostics,
      'media.devices.enumeration_failed',
      component: 'webrtc',
      correlationId: correlationId,
      severity: DiagnosticSeverity.warning,
      message: error.toString(),
      data: {
        'errorType': error.runtimeType.toString(),
        'stackTrace': stackTrace.toString(),
      },
    );
    rethrow;
  }
}

abstract base class _VoiceMediaNotifier extends ChangeNotifier
    implements VoiceMediaSession {
  bool _disposed = false;

  @protected
  bool get disposed => _disposed;

  @protected
  void changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  Future<List<rtc.MediaDeviceInfo>> devices() =>
      rtc.navigator.mediaDevices.enumerateDevices();

  @override
  Future<void> selectAudioOutput(String deviceId) =>
      rtc.Helper.selectAudioOutput(deviceId);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

enum _MeshSource { microphone, video, screenAudio }

const int _maxMeshSdpCodeUnits = 32 * 1024;
const int _maxMeshCandidateCodeUnits = 2 * 1024;
const int _maxMeshSdpMidCodeUnits = 256;
const int _meshSignalFlushEventThreshold = 20;

// ICE agents normally produce far fewer candidates. This still leaves ample
// room for multiple interfaces and TURN transports while bounding queued text
// to roughly half a megabyte per peer before an SDP description arrives.
const int _maxPendingMeshCandidatesPerPeer = 64;

enum _MeshSdpKind { offer, answer }

sealed class _MeshInboundSignal {
  const _MeshInboundSignal();
}

final class _MeshSdpSignal extends _MeshInboundSignal {
  const _MeshSdpSignal(this.kind, this.sdp);

  final _MeshSdpKind kind;
  final String sdp;
}

final class _MeshCandidateSignal extends _MeshInboundSignal {
  const _MeshCandidateSignal({
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });

  final String? candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
}

final class _MeshEndOfCandidatesSignal extends _MeshInboundSignal {
  const _MeshEndOfCandidatesSignal();
}

_MeshInboundSignal? _parseMeshInboundSignal(Map<String, dynamic> data) {
  switch (data['type']) {
    case 'offer' || 'answer':
      final sdp = data['sdp'];
      if (sdp is! String || sdp.length > _maxMeshSdpCodeUnits) return null;
      return _MeshSdpSignal(
        data['type'] == 'offer' ? _MeshSdpKind.offer : _MeshSdpKind.answer,
        sdp,
      );
    case 'candidate':
      final raw = data['candidate'];
      if (raw is! Map) return null;
      final candidate = raw['candidate'];
      if (candidate != null && candidate is! String) return null;
      if (candidate is String &&
          candidate.length > _maxMeshCandidateCodeUnits) {
        return null;
      }
      if (candidate == null || (candidate is String && candidate.isEmpty)) {
        return const _MeshEndOfCandidatesSignal();
      }
      final sdpMid = raw['sdpMid'];
      if (sdpMid != null && sdpMid is! String) return null;
      if (sdpMid is String && sdpMid.length > _maxMeshSdpMidCodeUnits) {
        return null;
      }
      final rawIndex = raw['sdpMLineIndex'];
      final parsedIndex = rawIndex is String
          ? int.tryParse(rawIndex)
          : rawIndex;
      final int? sdpMLineIndex;
      if (parsedIndex == null && rawIndex == null) {
        sdpMLineIndex = null;
      } else if (parsedIndex is num &&
          parsedIndex.isFinite &&
          parsedIndex == parsedIndex.truncate() &&
          parsedIndex >= 0 &&
          parsedIndex <= 65535) {
        sdpMLineIndex = parsedIndex.toInt();
      } else {
        return null;
      }
      return _MeshCandidateSignal(
        candidate: candidate as String?,
        sdpMid: sdpMid as String?,
        sdpMLineIndex: sdpMLineIndex,
      );
    default:
      return null;
  }
}

final class _MeshSendSlots {
  _MeshSendSlots({
    required this.microphone,
    required this.video,
    required this.screenAudio,
  });

  rtc.RTCRtpSender microphone;
  rtc.RTCRtpSender video;
  rtc.RTCRtpSender screenAudio;

  rtc.RTCRtpSender sender(_MeshSource source) => switch (source) {
    _MeshSource.microphone => microphone,
    _MeshSource.video => video,
    _MeshSource.screenAudio => screenAudio,
  };

  void bind(_MeshSource source, rtc.RTCRtpSender sender) {
    switch (source) {
      case _MeshSource.microphone:
        microphone = sender;
      case _MeshSource.video:
        video = sender;
      case _MeshSource.screenAudio:
        screenAudio = sender;
    }
  }
}

final class _MeshRemoteSlots {
  rtc.MediaStreamTrack? microphone;
  rtc.MediaStreamTrack? video;
  rtc.MediaStreamTrack? screenAudio;

  Iterable<rtc.MediaStreamTrack> get audioTracks sync* {
    if (microphone case final track?) yield track;
    if (screenAudio case final track?) yield track;
  }

  Iterable<rtc.MediaStreamTrack> get tracks sync* {
    yield* audioTracks;
    if (video case final track?) yield track;
  }

  void accept(rtc.RTCTrackEvent event) {
    final track = event.track;
    if (track.kind == 'video') {
      video = track;
    } else if (event.streams.isEmpty) {
      screenAudio = track;
    } else {
      microphone = track;
    }
  }

  void remove(rtc.MediaStreamTrack track) {
    bool matches(rtc.MediaStreamTrack? value) =>
        identical(value, track) ||
        (track.id != null && value?.id != null && value?.id == track.id);
    if (matches(microphone)) microphone = null;
    if (matches(video)) video = null;
    if (matches(screenAudio)) screenAudio = null;
  }
}

final class MeshVoiceMediaSession extends _VoiceMediaNotifier {
  MeshVoiceMediaSession({
    required this.join,
    required this.localUserId,
    required this.sendSignal,
    required this.audioPublishingAllowed,
    this.diagnostics = const NoopVoiceDiagnosticsRecorder(),
    this.correlationId = 'uncorrelated',
    this.rawStatsInterval = const Duration(seconds: 5),
    VoicePeerConnectionCreator? createPeerConnection,
    VoiceUserMediaGetter? getUserMedia,
    VoiceUserMediaGetter? getDisplayMedia,
    VoiceMediaDeviceEnumerator? enumerateDevices,
    VoiceTrackVolumeSetter? setTrackVolume,
  }) : _createPeerConnection = createPeerConnection ?? rtc.createPeerConnection,
       _getUserMedia =
           getUserMedia ??
           ((constraints) =>
               rtc.navigator.mediaDevices.getUserMedia(constraints)),
       _getDisplayMedia =
           getDisplayMedia ??
           ((constraints) =>
               rtc.navigator.mediaDevices.getDisplayMedia(constraints)),
       _enumerateDevices =
           enumerateDevices ??
           (() => rtc.navigator.mediaDevices.enumerateDevices()),
       _setTrackVolume = setTrackVolume ?? rtc.Helper.setVolume;

  final VoiceJoinResponse join;
  final int localUserId;
  final VoiceSignalSender sendSignal;
  final VoiceDiagnosticsRecorder diagnostics;
  final String correlationId;
  final Duration rawStatsInterval;
  final VoicePeerConnectionCreator _createPeerConnection;
  final VoiceUserMediaGetter _getUserMedia;
  final VoiceUserMediaGetter _getDisplayMedia;
  final VoiceMediaDeviceEnumerator _enumerateDevices;
  final VoiceTrackVolumeSetter _setTrackVolume;
  final Map<int, rtc.RTCPeerConnection> _peers = {};
  final Map<int, String> _peerDiagnosticAliases = {};
  final Expando<String> _trackDiagnosticAliases = Expando<String>();
  final Map<int, Future<void>> _peerCreations = {};
  final Map<int, _MeshSendSlots> _sendSlots = {};
  final Map<int, _MeshRemoteSlots> _remoteTracks = {};
  final Map<int, double> _participantVolumes = {};
  final Map<int, VoiceRole> _participantRoles = {};
  final Set<int> _currentRemoteParticipantIds = {};
  final Set<int> _peerEligibleParticipantIds = {};
  final Set<rtc.MediaStream> _ownedLocalStreams =
      Set<rtc.MediaStream>.identity();
  final Map<int, List<rtc.RTCIceCandidate>> _pendingCandidates = {};
  final Map<int, List<Map<String, Object?>>> _outgoingCandidates = {};
  final Map<int, Timer> _candidateTimers = {};
  final Set<int> _makingOffer = {};
  rtc.MediaStream? _localStream;
  rtc.MediaStream? _screenStream;
  bool _deafened = false;
  bool _muted = false;
  bool audioPublishingAllowed;
  Timer? _speakingTimer;
  Timer? _rawStatsTimer;
  bool _pollingSpeaking = false;
  bool _pollingRawStats = false;
  bool _deviceInventoryCaptured = false;
  int _nextPeerDiagnosticAlias = 1;
  int _nextTrackDiagnosticAlias = 1;
  Set<int> _speaking = const {};
  String? _audioInputDeviceId;
  Future<void> _mutationTail = Future<void>.value();
  bool _closing = false;

  String _peerDiagnosticAlias(int peerId) => _peerDiagnosticAliases.putIfAbsent(
    peerId,
    () => 'peer-${_nextPeerDiagnosticAlias++}',
  );

  String _trackDiagnosticAlias(rtc.MediaStreamTrack track) =>
      _trackDiagnosticAliases[track] ??= 'track-${_nextTrackDiagnosticAlias++}';

  @override
  VoiceTransport get transport => VoiceTransport.mesh;

  @override
  VoiceMediaConnectionState get connectionState =>
      VoiceMediaConnectionState.connected;

  @override
  Object? get localVideoTrack => _screenVideoTrack ?? _cameraTrack;

  @override
  bool get screenSharing => _screenStream != null;

  @override
  Object? videoTrackFor(int participantId) => participantId == localUserId
      ? localVideoTrack
      : _remoteTracks[participantId]?.video;

  rtc.MediaStreamTrack? get _microphoneTrack =>
      _localStream?.getAudioTracks().firstOrNull;
  rtc.MediaStreamTrack? get _cameraTrack =>
      _localStream?.getVideoTracks().firstOrNull;
  rtc.MediaStreamTrack? get _screenVideoTrack =>
      _screenStream?.getVideoTracks().firstOrNull;
  rtc.MediaStreamTrack? get _screenAudioTrack =>
      _screenStream?.getAudioTracks().firstOrNull;
  rtc.MediaStreamTrack? get _publishedVideoTrack =>
      _screenVideoTrack ?? _cameraTrack;

  @override
  Set<int> get speakingParticipantIds => _speaking;

  @override
  Future<List<rtc.MediaDeviceInfo>> devices() async {
    final result = await _enumerateDevicesWithDiagnostics(
      enumerateDevices: _enumerateDevices,
      diagnostics: diagnostics,
      correlationId: correlationId,
    );
    try {
      if (diagnostics.captureEnabled) _deviceInventoryCaptured = true;
    } catch (_) {}
    return result;
  }

  @override
  Future<void> connect() => _serialize(_connect);

  Future<void> _connect() async {
    _recordDiagnostic(
      diagnostics,
      'mesh.session.connect.started',
      component: 'mesh',
      correlationId: correlationId,
      data: {
        'participantCount': join.room.participants.length,
        'audioPublishingAllowed': audioPublishingAllowed,
        'relayOnly': join.ice.relayOnly,
        'iceServerCount': join.ice.servers.length,
      },
    );
    try {
      if (audioPublishingAllowed) await _ensureAudioTrack();
      await _syncParticipants(join.room.participants);
      if (_closing || disposed) return;
      _speakingTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => unawaited(_pollSpeakingLevels()),
      );
      if (rawStatsInterval > Duration.zero) {
        _rawStatsTimer = Timer.periodic(
          rawStatsInterval,
          (_) => unawaited(_pollRawStats()),
        );
      }
      _recordDiagnostic(
        diagnostics,
        'mesh.session.connect.completed',
        component: 'mesh',
        correlationId: correlationId,
        data: {'peerCount': _peers.length},
      );
    } catch (error, stackTrace) {
      _recordDiagnostic(
        diagnostics,
        'mesh.session.connect.failed',
        component: 'mesh',
        correlationId: correlationId,
        severity: DiagnosticSeverity.error,
        data: {'errorType': error.runtimeType.toString()},
      );
      _recordRawDiagnostic(
        diagnostics,
        'mesh.session.connect.failure_detail',
        component: 'mesh',
        correlationId: correlationId,
        severity: DiagnosticSeverity.error,
        message: error.toString(),
        data: {'stackTrace': stackTrace.toString()},
      );
      rethrow;
    }
  }

  Future<void> _serialize(Future<void> Function() action) {
    if (_closing || disposed) return Future<void>.value();
    final operation = _mutationTail.then((_) async {
      if (_closing || disposed) return;
      await action();
    });
    _mutationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _pollSpeakingLevels() async {
    if (_pollingSpeaking || _closing || disposed) return;
    _pollingSpeaking = true;
    final next = <int>{};
    try {
      for (final entry in _peers.entries.toList()) {
        if (_closing || disposed) return;
        if (!identical(_peers[entry.key], entry.value)) continue;
        List<rtc.StatsReport> reports;
        try {
          reports = await entry.value.getStats();
        } catch (_) {
          continue;
        }
        if (!identical(_peers[entry.key], entry.value)) continue;
        var audible = false;
        var localAudible = false;
        for (final report in reports) {
          final values = report.values;
          if (values['kind'] != 'audio' && values['mediaType'] != 'audio') {
            continue;
          }
          final level = values['audioLevel'];
          if (level is! num || level <= 0.01) continue;
          if (report.type == 'inbound-rtp') audible = true;
          // The local microphone's level rides the sending side's
          // `media-source` report, so the local user gets a speaking
          // indicator too and the idle ladder can hear them talking.
          if (report.type == 'media-source') localAudible = true;
        }
        if (audible) next.add(entry.key);
        if (localAudible && !_muted) next.add(localUserId);
      }
      if (!_closing && !disposed && !setEquals(next, _speaking)) {
        _speaking = Set.unmodifiable(next);
        changed();
      }
    } finally {
      _pollingSpeaking = false;
    }
  }

  Future<void> _pollRawStats() async {
    if (_pollingRawStats || _closing || disposed) return;
    try {
      if (!diagnostics.captureEnabled) {
        _deviceInventoryCaptured = false;
        return;
      }
    } catch (_) {
      return;
    }
    _pollingRawStats = true;
    try {
      if (!_deviceInventoryCaptured) {
        try {
          await devices();
        } catch (_) {}
      }
      for (final entry in _peers.entries.toList()) {
        if (_closing || disposed) return;
        if (!identical(_peers[entry.key], entry.value)) continue;
        try {
          final reports = await entry.value.getStats();
          if (!identical(_peers[entry.key], entry.value)) continue;
          _recordRawDiagnostic(
            diagnostics,
            'mesh.peer.stats',
            component: 'webrtc',
            correlationId: correlationId,
            data: {
              'peerId': entry.key,
              'reports': _serializeStatsReports(reports),
            },
          );
        } catch (error, stackTrace) {
          _recordRawDiagnostic(
            diagnostics,
            'mesh.peer.stats_failed',
            component: 'webrtc',
            correlationId: correlationId,
            severity: DiagnosticSeverity.warning,
            message: error.toString(),
            data: {'peerId': entry.key, 'stackTrace': stackTrace.toString()},
          );
        }
      }
    } finally {
      _pollingRawStats = false;
    }
  }

  Future<void> _ensureAudioTrack({bool syncPeers = true}) async {
    if (_localStream?.getAudioTracks().isNotEmpty == true) return;
    final (stream, track) = await _captureAudioTrack();
    final previousLocalStream = _localStream;
    track.enabled = !_muted;
    try {
      await _attachLocalTrack(stream, track);
      if (syncPeers) await _setSourceTrack(_MeshSource.microphone, track);
    } catch (_) {
      await _discardCapturedTrack(
        stream,
        track,
        previousLocalStream: previousLocalStream,
      );
      rethrow;
    }
  }

  Future<(rtc.MediaStream, rtc.MediaStreamTrack)> _captureAudioTrack() async {
    return _withMicrophoneFailure(() async {
      final stream = await _getUserMedia({
        'audio': {
          'deviceId': ?_audioInputDeviceId,
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      final track = stream.getAudioTracks().first;
      _ownedLocalStreams.add(stream);
      return (stream, track);
    });
  }

  Future<void> _attachLocalTrack(
    rtc.MediaStream stream,
    rtc.MediaStreamTrack track,
  ) async {
    if (_localStream == null) {
      _localStream = stream;
    } else if (!identical(_localStream, stream)) {
      await _localStream!.addTrack(track);
    }
  }

  Future<void> _discardCapturedTrack(
    rtc.MediaStream stream,
    rtc.MediaStreamTrack track, {
    required rtc.MediaStream? previousLocalStream,
  }) async {
    if (previousLocalStream == null && identical(_localStream, stream)) {
      _localStream = null;
    } else {
      await _localStream?.removeTrack(track);
    }
    await track.stop();
    _ownedLocalStreams.remove(stream);
    await stream.dispose();
  }

  Map<String, dynamic> get _configuration => {
    'iceServers': [
      for (final server in join.ice.servers)
        {
          'urls': server.urls,
          if (server.username != null) 'username': server.username,
          if (server.credential != null) 'credential': server.credential,
        },
    ],
    'iceTransportPolicy': join.ice.relayOnly ? 'relay' : 'all',
    'sdpSemantics': 'unified-plan',
  };

  @override
  Future<void> syncParticipants(List<VoiceParticipant> participants) =>
      _serialize(() => _syncParticipants(participants));

  Future<void> _syncParticipants(List<VoiceParticipant> participants) async {
    _recordRawDiagnostic(
      diagnostics,
      'mesh.roster.sync',
      component: 'mesh',
      correlationId: correlationId,
      data: {
        'participants': [
          for (final participant in participants)
            {
              'peerAlias': participant.id == localUserId
                  ? 'local'
                  : _peerDiagnosticAlias(participant.id),
              'id': participant.id,
              'username': participant.username,
              'name': participant.name,
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
    final currentRemoteIds = {
      for (final participant in participants)
        if (participant.id != localUserId) participant.id,
    };
    final wanted = {
      for (final participant in participants)
        if (participant.id != localUserId &&
            (join.room.type != VoiceRoomType.stage ||
                audioPublishingAllowed ||
                participant.role == VoiceRole.moderator ||
                participant.role == VoiceRole.speaker))
          participant.id,
    };
    // Update the trust boundary before teardown. Even if a native peer rejects
    // close, a departed participant must stop being an accepted signal sender.
    _currentRemoteParticipantIds
      ..clear()
      ..addAll(currentRemoteIds);
    _peerEligibleParticipantIds
      ..clear()
      ..addAll(wanted);
    final changedRoles = {
      for (final participant in participants)
        if (participant.id != localUserId &&
            _participantRoles[participant.id] != null &&
            _participantRoles[participant.id] != participant.role)
          participant.id,
    };
    final gone = _peers.keys.where((id) => !wanted.contains(id)).toList();
    for (final id in gone) {
      await _closePeer(id);
      _participantVolumes.remove(id);
    }
    for (final id in changedRoles.difference(gone.toSet())) {
      await _closePeer(id);
    }
    _participantRoles
      ..removeWhere((id, _) => id != localUserId && !wanted.contains(id))
      ..addEntries(
        participants.map(
          (participant) => MapEntry(participant.id, participant.role),
        ),
      );
    await Future.wait([
      for (final id in wanted)
        if (!_peers.containsKey(id)) _createPeer(id),
    ]);
  }

  Future<void> _createPeer(int peerId) {
    if (_closing || disposed || _peers.containsKey(peerId)) {
      return Future.value();
    }
    return _peerCreations.putIfAbsent(peerId, () async {
      try {
        await _createPeerNow(peerId);
      } finally {
        final _ = _peerCreations.remove(peerId);
      }
    });
  }

  Future<void> _createPeerNow(int peerId) async {
    if (_closing || disposed || _peers.containsKey(peerId)) return;
    final peerAlias = _peerDiagnosticAlias(peerId);
    _recordRawDiagnostic(
      diagnostics,
      'mesh.peer.identity',
      component: 'webrtc',
      correlationId: correlationId,
      data: {'peerAlias': peerAlias, 'peerId': peerId},
    );
    _recordDiagnostic(
      diagnostics,
      'mesh.peer.create.started',
      component: 'webrtc',
      correlationId: correlationId,
      data: {'peerAlias': peerAlias},
    );
    late final rtc.RTCPeerConnection peer;
    try {
      peer = await _createPeerConnection(_configuration);
    } catch (error, stackTrace) {
      _recordDiagnostic(
        diagnostics,
        'mesh.peer.create.failed',
        component: 'webrtc',
        correlationId: correlationId,
        severity: DiagnosticSeverity.error,
        data: {
          'peerAlias': peerAlias,
          'errorType': error.runtimeType.toString(),
        },
      );
      _recordRawDiagnostic(
        diagnostics,
        'mesh.peer.create.failure_detail',
        component: 'webrtc',
        correlationId: correlationId,
        severity: DiagnosticSeverity.error,
        message: error.toString(),
        data: {
          'peerAlias': peerAlias,
          'peerId': peerId,
          'stackTrace': stackTrace.toString(),
        },
      );
      rethrow;
    }
    var registered = false;
    if (_closing || disposed || _peers.containsKey(peerId)) {
      await peer.close();
      await peer.dispose();
      return;
    }
    try {
      peer.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        _recordRawDiagnostic(
          diagnostics,
          'mesh.ice.candidate.local',
          component: 'webrtc',
          correlationId: correlationId,
          data: {
            'peerAlias': peerAlias,
            'peerId': peerId,
            'candidate': candidate.toMap(),
          },
        );
        _queueCandidate(peerId, candidate);
      };
      peer.onTrack = (event) {
        if (!identical(_peers[peerId], peer)) return;
        final trackAlias = _trackDiagnosticAlias(event.track);
        _recordRawDiagnostic(
          diagnostics,
          'mesh.track.received',
          component: 'webrtc',
          correlationId: correlationId,
          data: {
            'peerAlias': peerAlias,
            'peerId': peerId,
            'trackAlias': trackAlias,
            'trackId': event.track.id,
            'kind': event.track.kind,
            'streamIds': [for (final stream in event.streams) stream.id],
          },
        );
        if (!_remoteTrackAllowed(peerId, event)) {
          _recordDiagnostic(
            diagnostics,
            'mesh.track.rejected',
            component: 'webrtc',
            correlationId: correlationId,
            severity: DiagnosticSeverity.warning,
            data: {
              'peerAlias': peerAlias,
              'trackAlias': trackAlias,
              'kind': event.track.kind,
            },
          );
          unawaited(_stopRemoteTrackBestEffort(event.track));
          return;
        }
        final slots = _remoteTracks[peerId] ??= _MeshRemoteSlots();
        slots.accept(event);
        event.track.onEnded = () {
          if (!identical(_peers[peerId], peer)) return;
          _recordDiagnostic(
            diagnostics,
            'mesh.track.ended',
            component: 'webrtc',
            correlationId: correlationId,
            data: {
              'peerAlias': peerAlias,
              'trackAlias': trackAlias,
              'kind': event.track.kind,
            },
          );
          slots.remove(event.track);
          _applyRemoteAudio(peerId);
          changed();
        };
        _applyRemoteAudio(peerId);
        changed();
      };
      peer.onConnectionState = (state) {
        if (!identical(_peers[peerId], peer)) return;
        _recordDiagnostic(
          diagnostics,
          'mesh.peer.connection_state',
          component: 'webrtc',
          correlationId: correlationId,
          severity:
              state == rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed
              ? DiagnosticSeverity.warning
              : DiagnosticSeverity.info,
          data: {'peerAlias': peerAlias, 'state': _diagnosticEnumName(state)},
        );
        if (state == rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          unawaited(_serialize(() => _restartPeer(peerId)));
        }
      };
      peer.onIceConnectionState = (state) {
        if (!identical(_peers[peerId], peer)) return;
        _recordDiagnostic(
          diagnostics,
          'mesh.peer.ice_connection_state',
          component: 'webrtc',
          correlationId: correlationId,
          data: {'peerAlias': peerAlias, 'state': _diagnosticEnumName(state)},
        );
      };
      peer.onIceGatheringState = (state) {
        if (!identical(_peers[peerId], peer)) return;
        _recordDiagnostic(
          diagnostics,
          'mesh.peer.ice_gathering_state',
          component: 'webrtc',
          correlationId: correlationId,
          data: {'peerAlias': peerAlias, 'state': _diagnosticEnumName(state)},
        );
      };
      peer.onSignalingState = (state) {
        if (!identical(_peers[peerId], peer)) return;
        _recordDiagnostic(
          diagnostics,
          'mesh.peer.signaling_state',
          component: 'webrtc',
          correlationId: correlationId,
          data: {'peerAlias': peerAlias, 'state': _diagnosticEnumName(state)},
        );
      };

      final microphone = _microphoneTrack;
      final publishingDirection = audioPublishingAllowed
          ? rtc.TransceiverDirection.SendRecv
          : rtc.TransceiverDirection.RecvOnly;
      final microphoneSender = microphone != null && _localStream != null
          ? await peer.addTrack(microphone, _localStream!)
          : (await peer.addTransceiver(
              kind: rtc.RTCRtpMediaType.RTCRtpMediaTypeAudio,
              init: rtc.RTCRtpTransceiverInit(direction: publishingDirection),
            )).sender;
      final video = await peer.addTransceiver(
        kind: rtc.RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: rtc.RTCRtpTransceiverInit(direction: publishingDirection),
      );
      final screenAudio = await peer.addTransceiver(
        kind: rtc.RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: rtc.RTCRtpTransceiverInit(direction: publishingDirection),
      );
      if (_publishedVideoTrack case final track?) {
        await video.sender.replaceTrack(track);
      }
      if (_screenAudioTrack case final track?) {
        await screenAudio.sender.replaceTrack(track);
      }

      if (_closing || disposed || _peers.containsKey(peerId)) return;

      _sendSlots[peerId] = _MeshSendSlots(
        microphone: microphoneSender,
        video: video.sender,
        screenAudio: screenAudio.sender,
      );
      _peers[peerId] = peer;
      registered = true;
      _recordDiagnostic(
        diagnostics,
        'mesh.peer.create.completed',
        component: 'webrtc',
        correlationId: correlationId,
        data: {'peerAlias': peerAlias, 'initiatesOffer': localUserId < peerId},
      );
      if (microphone != null) await _applyAudioQuality(microphoneSender);
      if (_screenAudioTrack != null) {
        await _applyAudioQuality(screenAudio.sender);
      }
      if (localUserId < peerId) await _offer(peerId);
    } catch (error, stackTrace) {
      _recordDiagnostic(
        diagnostics,
        'mesh.peer.setup_failed',
        component: 'webrtc',
        correlationId: correlationId,
        severity: DiagnosticSeverity.error,
        data: {
          'peerAlias': peerAlias,
          'errorType': error.runtimeType.toString(),
        },
      );
      _recordRawDiagnostic(
        diagnostics,
        'mesh.peer.setup_failure_detail',
        component: 'webrtc',
        correlationId: correlationId,
        severity: DiagnosticSeverity.error,
        message: error.toString(),
        data: {
          'peerAlias': peerAlias,
          'peerId': peerId,
          'stackTrace': stackTrace.toString(),
        },
      );
      if (registered && identical(_peers[peerId], peer)) {
        await _closePeer(peerId);
      } else {
        await peer.close();
        await peer.dispose();
      }
      rethrow;
    } finally {
      if (!registered &&
          !identical(_peers[peerId], peer) &&
          (_closing || disposed || _peers.containsKey(peerId))) {
        try {
          await peer.close();
          await peer.dispose();
        } catch (_) {
          // The peer may already have been released by the early-exit path.
        }
      }
    }
  }

  void _queueCandidate(int peerId, rtc.RTCIceCandidate candidate) {
    final queued = _outgoingCandidates[peerId] ??= [];
    queued.add({'type': 'candidate', 'candidate': candidate.toMap()});
    if (queued.length >= _meshSignalFlushEventThreshold) {
      _candidateTimers.remove(peerId)?.cancel();
      unawaited(_flushOutgoingCandidatesAtTerminal(peerId));
      return;
    }
    _candidateTimers.putIfAbsent(
      peerId,
      () => Timer(
        const Duration(milliseconds: 30),
        () => unawaited(_flushOutgoingCandidatesAtTerminal(peerId)),
      ),
    );
  }

  Future<void> _flushOutgoingCandidatesAtTerminal(int peerId) async {
    try {
      await _flushOutgoingCandidates(peerId);
    } catch (_) {
      // `_sendPeerSignal` already emitted safe metadata and capture-gated raw
      // detail. This timer is the terminal owner of the detached future, so it
      // must consume the failure instead of letting it reach global handlers.
    }
  }

  Future<void> _flushOutgoingCandidates(int peerId) async {
    _candidateTimers.remove(peerId)?.cancel();
    final events = _outgoingCandidates.remove(peerId);
    if (events == null || events.isEmpty || disposed) return;
    await _sendPeerSignal(peerId, {'events': events});
  }

  Future<void> _offer(int peerId, {bool restartIce = false}) async {
    final peer = _peers[peerId];
    if (peer == null || _makingOffer.contains(peerId)) return;
    _makingOffer.add(peerId);
    try {
      if (restartIce) await peer.restartIce();
      final offer = await peer.createOffer({
        if (restartIce) 'iceRestart': true,
      });
      await peer.setLocalDescription(offer);
      await _sendPeerSignal(peerId, {'type': 'offer', 'sdp': offer.sdp});
    } finally {
      _makingOffer.remove(peerId);
    }
  }

  Future<void> _restartPeer(int peerId) async {
    if (disposed || !_peers.containsKey(peerId)) return;
    _recordDiagnostic(
      diagnostics,
      'mesh.peer.ice_restart.requested',
      component: 'webrtc',
      correlationId: correlationId,
      data: {
        'peerAlias': _peerDiagnosticAlias(peerId),
        'isOfferer': localUserId < peerId,
      },
    );
    if (localUserId < peerId) {
      await _offer(peerId, restartIce: true);
    }
  }

  @override
  Future<void> handleSignal(int senderId, Map<String, dynamic> data) =>
      _serialize(() {
        _recordDiagnostic(
          diagnostics,
          'mesh.signaling.received',
          component: 'webrtc',
          correlationId: correlationId,
          data: {
            'peerAlias': _peerDiagnosticAlias(senderId),
            'type': _diagnosticSignalType(data['type']),
            if (data['events'] is List)
              'eventCount': (data['events'] as List).length,
          },
        );
        _recordRawDiagnostic(
          diagnostics,
          'mesh.signaling.received.raw',
          component: 'webrtc',
          correlationId: correlationId,
          data: {
            'peerAlias': _peerDiagnosticAlias(senderId),
            'peerId': senderId,
            'signal': data,
          },
        );
        return _handleSignal(senderId, data);
      });

  Future<void> _sendPeerSignal(int peerId, Map<String, Object?> event) async {
    _recordDiagnostic(
      diagnostics,
      'mesh.signaling.sent',
      component: 'webrtc',
      correlationId: correlationId,
      data: {
        'peerAlias': _peerDiagnosticAlias(peerId),
        'type': _diagnosticSignalType(event['type']),
        if (event['events'] is List)
          'eventCount': (event['events'] as List).length,
      },
    );
    _recordRawDiagnostic(
      diagnostics,
      'mesh.signaling.sent.raw',
      component: 'webrtc',
      correlationId: correlationId,
      data: {
        'peerAlias': _peerDiagnosticAlias(peerId),
        'peerId': peerId,
        'signal': event,
      },
    );
    try {
      await sendSignal(peerId, event);
    } catch (error, stackTrace) {
      _recordDiagnostic(
        diagnostics,
        'mesh.signaling.send_failed',
        component: 'webrtc',
        correlationId: correlationId,
        severity: DiagnosticSeverity.warning,
        data: {
          'peerAlias': _peerDiagnosticAlias(peerId),
          'errorType': error.runtimeType.toString(),
        },
      );
      _recordRawDiagnostic(
        diagnostics,
        'mesh.signaling.send_failure_detail',
        component: 'webrtc',
        correlationId: correlationId,
        severity: DiagnosticSeverity.warning,
        message: error.toString(),
        data: {
          'peerAlias': _peerDiagnosticAlias(peerId),
          'peerId': peerId,
          'stackTrace': stackTrace.toString(),
        },
      );
      rethrow;
    }
  }

  Future<void> _handleSignal(int senderId, Map<String, dynamic> data) async {
    if (disposed ||
        senderId == localUserId ||
        !_currentRemoteParticipantIds.contains(senderId) ||
        !_peerEligibleParticipantIds.contains(senderId)) {
      return;
    }
    final signal = _parseMeshInboundSignal(data);
    if (signal == null) return;
    if (!_peers.containsKey(senderId)) await _createPeer(senderId);
    final peer = _peers[senderId];
    if (peer == null) return;
    switch (signal) {
      case _MeshSdpSignal(kind: _MeshSdpKind.offer, :final sdp):
        final signalingState = await peer.getSignalingState();
        final collision =
            _makingOffer.contains(senderId) ||
            signalingState != rtc.RTCSignalingState.RTCSignalingStateStable;
        if (collision) {
          // Mesh creation deterministically assigns the lower user ID as the
          // offerer. Keep that negotiation when both clients briefly offer:
          // flutter_webrtc's Darwin bridge cannot represent a rollback
          // description because the native SDK rejects its required empty SDP.
          _recordDiagnostic(
            diagnostics,
            'mesh.signaling.offer_ignored',
            component: 'webrtc',
            correlationId: correlationId,
            data: {
              'peerAlias': _peerDiagnosticAlias(senderId),
              'makingOffer': _makingOffer.contains(senderId),
              'signalingState': _diagnosticEnumName(signalingState),
            },
          );
          return;
        }
        await peer.setRemoteDescription(
          rtc.RTCSessionDescription(sdp, 'offer'),
        );
        await _alignSendSlotsForAnswer(senderId, peer);
        await _flushCandidates(senderId);
        final answer = await peer.createAnswer();
        await peer.setLocalDescription(answer);
        await _sendPeerSignal(senderId, {'type': 'answer', 'sdp': answer.sdp});
        await _refreshSendSlotsBestEffort(senderId, peer);
      case _MeshSdpSignal(kind: _MeshSdpKind.answer, :final sdp):
        if (await peer.getSignalingState() !=
            rtc.RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
          return;
        }
        await peer.setRemoteDescription(
          rtc.RTCSessionDescription(sdp, 'answer'),
        );
        await _flushCandidates(senderId);
        await _refreshSendSlotsBestEffort(senderId, peer);
      case _MeshCandidateSignal(
        :final candidate,
        :final sdpMid,
        :final sdpMLineIndex,
      ):
        final parsed = rtc.RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
        if (await peer.getRemoteDescription() == null) {
          final pending = _pendingCandidates[senderId] ??= [];
          if (pending.length >= _maxPendingMeshCandidatesPerPeer) return;
          pending.add(parsed);
          _recordDiagnostic(
            diagnostics,
            'mesh.ice.candidate.queued',
            component: 'webrtc',
            correlationId: correlationId,
            data: {'peerAlias': _peerDiagnosticAlias(senderId)},
          );
        } else {
          await peer.addCandidate(parsed);
          _recordDiagnostic(
            diagnostics,
            'mesh.ice.candidate.added',
            component: 'webrtc',
            correlationId: correlationId,
            data: {'peerAlias': _peerDiagnosticAlias(senderId)},
          );
        }
      case _MeshEndOfCandidatesSignal():
        _recordDiagnostic(
          diagnostics,
          'mesh.ice.end_of_candidates.received',
          component: 'webrtc',
          correlationId: correlationId,
          data: {'peerAlias': _peerDiagnosticAlias(senderId)},
        );
    }
  }

  bool _remoteTrackAllowed(int peerId, rtc.RTCTrackEvent event) {
    if (!_currentRemoteParticipantIds.contains(peerId)) return false;
    final role = _participantRoles[peerId];
    if (join.room.type == VoiceRoomType.stage &&
        role != VoiceRole.moderator &&
        role != VoiceRole.speaker) {
      return false;
    }
    final isScreenAudio = event.track.kind == 'audio' && event.streams.isEmpty;
    if ((event.track.kind == 'video' || isScreenAudio) &&
        !join.room.videoAllowed) {
      return false;
    }
    return true;
  }

  Future<void> _stopRemoteTrackBestEffort(rtc.MediaStreamTrack track) async {
    try {
      await track.stop();
    } catch (_) {
      // A remote track may already have ended while the policy check runs.
    }
  }

  Future<void> _alignSendSlotsForAnswer(
    int peerId,
    rtc.RTCPeerConnection peer,
  ) async {
    final slots = _sendSlots[peerId];
    if (slots == null) return;
    final associated = (await peer.getTransceivers())
        .where((transceiver) => transceiver.mid.isNotEmpty)
        .toList();
    final audio = associated
        .where((transceiver) => transceiver.receiver.track?.kind == 'audio')
        .toList();
    final video = associated
        .where((transceiver) => transceiver.receiver.track?.kind == 'video')
        .firstOrNull;

    if (audio.isNotEmpty) {
      slots.microphone = await _adoptAnswerSender(
        _MeshSource.microphone,
        slots.microphone,
        audio.first,
      );
    }
    if (video != null) {
      slots.video = await _adoptAnswerSender(
        _MeshSource.video,
        slots.video,
        video,
      );
    }
    if (audio.length >= 2) {
      slots.screenAudio = await _adoptAnswerSender(
        _MeshSource.screenAudio,
        slots.screenAudio,
        audio.last,
      );
    }
  }

  Future<rtc.RTCRtpSender> _adoptAnswerSender(
    _MeshSource source,
    rtc.RTCRtpSender oldSender,
    rtc.RTCRtpTransceiver associated,
  ) async {
    await associated.setDirection(
      audioPublishingAllowed
          ? rtc.TransceiverDirection.SendRecv
          : rtc.TransceiverDirection.RecvOnly,
    );
    final sender = associated.sender;
    if (sender.senderId == oldSender.senderId) return sender;
    final track = oldSender.track;
    if (source == _MeshSource.microphone &&
        track != null &&
        _localStream != null) {
      await sender.setStreams([_localStream!]);
    }
    if (track != null) await sender.replaceTrack(track);
    await oldSender.replaceTrack(null);
    return sender;
  }

  Future<void> _refreshSendSlots(int peerId, rtc.RTCPeerConnection peer) async {
    final slots = _sendSlots[peerId];
    if (slots == null) return;
    final senders = {
      for (final sender in await peer.getSenders()) sender.senderId: sender,
    };
    for (final source in _MeshSource.values) {
      final current = slots.sender(source);
      final refreshed = senders[current.senderId];
      if (refreshed != null) slots.bind(source, refreshed);
    }
  }

  Future<void> _applySlotAudioQuality(int peerId) async {
    final slots = _sendSlots[peerId];
    if (slots == null) return;
    if (slots.microphone.track != null) {
      await _applyAudioQuality(slots.microphone);
    }
    if (slots.screenAudio.track != null) {
      await _applyAudioQuality(slots.screenAudio);
    }
  }

  Future<void> _refreshSendSlotsBestEffort(
    int peerId,
    rtc.RTCPeerConnection peer,
  ) async {
    try {
      await _refreshSendSlots(peerId, peer);
      await _applySlotAudioQuality(peerId);
    } catch (_) {
      // Sender wrappers and bitrate limits are performance hints after SDP is
      // committed. A platform-specific refresh failure must not tear down a
      // working media connection.
    }
  }

  Future<void> _flushCandidates(int peerId) async {
    final peer = _peers[peerId];
    if (peer == null) return;
    final pending =
        _pendingCandidates.remove(peerId) ?? const <rtc.RTCIceCandidate>[];
    for (final candidate in pending) {
      await peer.addCandidate(candidate);
    }
    if (pending.isNotEmpty) {
      _recordDiagnostic(
        diagnostics,
        'mesh.ice.candidates.flushed',
        component: 'webrtc',
        correlationId: correlationId,
        data: {
          'peerAlias': _peerDiagnosticAlias(peerId),
          'count': pending.length,
        },
      );
    }
  }

  @override
  Future<void> selectAudioInput(String deviceId) =>
      _serialize(() => _selectAudioInput(deviceId));

  Future<void> _selectAudioInput(String deviceId) async {
    _audioInputDeviceId = deviceId;
    if (!audioPublishingAllowed) return;
    final oldTracks = List<rtc.MediaStreamTrack>.of(
      _localStream?.getAudioTracks() ?? const <rtc.MediaStreamTrack>[],
    );
    final (stream, replacement) = await _captureAudioTrack();
    final previousLocalStream = _localStream;
    replacement.enabled = !_muted;
    try {
      await _attachLocalTrack(stream, replacement);
      await _setSourceTrack(_MeshSource.microphone, replacement);
    } catch (_) {
      await _discardCapturedTrack(
        stream,
        replacement,
        previousLocalStream: previousLocalStream,
      );
      rethrow;
    }
    for (final track in oldTracks) {
      await _localStream?.removeTrack(track);
      await track.stop();
    }
  }

  @override
  Future<void> setAudioPublishingAllowed(bool allowed) =>
      _serialize(() => _setAudioPublishingAllowed(allowed));

  Future<void> _setAudioPublishingAllowed(bool allowed) async {
    final previous = audioPublishingAllowed;
    final sourceIsConsistent = allowed
        ? _microphoneTrack != null
        : _microphoneTrack == null;
    if (previous == allowed && sourceIsConsistent) return;
    final peerIds = _peers.keys.toList();
    try {
      audioPublishingAllowed = allowed;
      if (allowed) {
        await _ensureAudioTrack(syncPeers: false);
      } else {
        await _detachAndStopMicrophone();
      }
      await _replacePeers(peerIds);
    } catch (error, stackTrace) {
      audioPublishingAllowed = previous;
      await _restoreAudioPublishingBestEffort(previous, peerIds);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _detachAndStopMicrophone() async {
    await _setSourceTrack(_MeshSource.microphone, null);
    for (final track in List<rtc.MediaStreamTrack>.of(
      _localStream?.getAudioTracks() ?? const <rtc.MediaStreamTrack>[],
    )) {
      await _localStream?.removeTrack(track);
      await track.stop();
    }
  }

  Future<void> _replacePeers(Iterable<int> peerIds) async {
    final wanted = peerIds.toSet();
    for (final peerId in _peers.keys.toList()) {
      await _closePeer(peerId);
    }
    for (final peerId in wanted) {
      await _createPeer(peerId);
    }
  }

  Future<void> _restoreAudioPublishingBestEffort(
    bool allowed,
    Iterable<int> peerIds,
  ) async {
    await _setSourceTrackBestEffort(_MeshSource.microphone, null);
    await _removeAllMicrophoneTracksBestEffort();
    if (allowed) {
      try {
        await _ensureAudioTrack(syncPeers: false);
      } catch (_) {
        // The original transition error remains authoritative. Rebuilding
        // without a microphone is safer than retaining a half-migrated sender.
      }
    }
    await _replacePeersBestEffort(peerIds);
  }

  Future<void> _removeAllMicrophoneTracksBestEffort() async {
    final tracks = Set<rtc.MediaStreamTrack>.identity();
    tracks.addAll(
      _localStream?.getAudioTracks() ?? const <rtc.MediaStreamTrack>[],
    );
    for (final stream in _ownedLocalStreams) {
      tracks.addAll(stream.getAudioTracks());
    }
    for (final track in tracks) {
      try {
        await _localStream?.removeTrack(track);
      } catch (_) {}
      try {
        await track.stop();
      } catch (_) {}
    }
  }

  Future<void> _replacePeersBestEffort(Iterable<int> peerIds) async {
    final wanted = peerIds.toSet();
    for (final peerId in _peers.keys.toList()) {
      try {
        await _closePeer(peerId);
      } catch (_) {}
    }
    for (final peerId in wanted) {
      try {
        await _createPeer(peerId);
      } catch (_) {}
    }
  }

  @override
  Future<void> setMuted(bool muted) => _serialize(() => _setMuted(muted));

  Future<void> _setMuted(bool muted) async {
    // Adopt the state only after capture succeeds; `_ensureAudioTrack` reads
    // `_muted` when deciding whether a new track starts enabled.
    if (audioPublishingAllowed && !muted) await _ensureAudioTrack();
    _muted = muted;
    for (final track
        in _localStream?.getAudioTracks() ?? const <rtc.MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> setDeafened(bool deafened) async {
    _deafened = deafened;
    for (final peerId in _remoteTracks.keys) {
      _applyRemoteAudio(peerId);
    }
  }

  void _applyRemoteAudio(int participantId) {
    final volume = _participantVolumes[participantId] ?? 1;
    for (final track
        in _remoteTracks[participantId]?.audioTracks ??
            const <rtc.MediaStreamTrack>[]) {
      track.enabled = !_deafened;
      unawaited(
        _setRemoteTrackVolume(participantId, track, _deafened ? 0 : volume),
      );
    }
  }

  Future<void> _setRemoteTrackVolume(
    int participantId,
    rtc.MediaStreamTrack track,
    double volume,
  ) async {
    final peerAlias = _peerDiagnosticAlias(participantId);
    final trackAlias = _trackDiagnosticAlias(track);
    try {
      await _setTrackVolume(volume, track);
    } catch (error, stackTrace) {
      _recordDiagnostic(
        diagnostics,
        'mesh.track.volume_failed',
        component: 'webrtc',
        correlationId: correlationId,
        severity: DiagnosticSeverity.warning,
        data: {
          'peerAlias': peerAlias,
          'trackAlias': trackAlias,
          'errorType': error.runtimeType.toString(),
        },
      );
      _recordRawDiagnostic(
        diagnostics,
        'mesh.track.volume_failure_detail',
        component: 'webrtc',
        correlationId: correlationId,
        severity: DiagnosticSeverity.warning,
        message: error.toString(),
        data: {
          'peerAlias': peerAlias,
          'peerId': participantId,
          'trackAlias': trackAlias,
          'trackId': track.id,
          'stackTrace': stackTrace.toString(),
        },
      );
    }
  }

  @override
  Future<void> setParticipantVolume(int participantId, double volume) async {
    _participantVolumes[participantId] = volume.clamp(0, 1);
    _applyRemoteAudio(participantId);
  }

  @override
  Future<void> setCameraEnabled(bool enabled, {String? deviceId}) =>
      _serialize(() => _setCameraEnabled(enabled, deviceId: deviceId));

  Future<void> _setCameraEnabled(bool enabled, {String? deviceId}) async {
    final existing = List<rtc.MediaStreamTrack>.of(
      _localStream?.getVideoTracks() ?? const <rtc.MediaStreamTrack>[],
    );
    if (!enabled) {
      await _setSourceTrack(_MeshSource.video, _screenVideoTrack);
      for (final track in existing) {
        await _localStream?.removeTrack(track);
        await track.stop();
      }
      changed();
      return;
    }
    if (existing.isNotEmpty) return;
    final (width, height, frameRate) = switch (join.room.maxQualityProfile) {
      VoiceQualityProfile.standard => (640, 360, 15),
      VoiceQualityProfile.high => (1280, 720, 24),
      VoiceQualityProfile.maximum => (1920, 1080, 30),
    };
    final stream = await _getUserMedia({
      'audio': false,
      'video': {
        'deviceId': ?deviceId,
        'width': {'ideal': width},
        'height': {'ideal': height},
        'frameRate': {'ideal': frameRate},
      },
    });
    final track = stream.getVideoTracks().first;
    _ownedLocalStreams.add(stream);
    final previousLocalStream = _localStream;
    try {
      await _attachLocalTrack(stream, track);
      await _setSourceTrack(_MeshSource.video, _publishedVideoTrack);
    } catch (_) {
      await _discardCapturedTrack(
        stream,
        track,
        previousLocalStream: previousLocalStream,
      );
      rethrow;
    }
    changed();
  }

  @override
  Future<void> setScreenShareEnabled(bool enabled) =>
      _serialize(() => _setScreenShareEnabled(enabled));

  Future<void> _setScreenShareEnabled(bool enabled) async {
    if (!enabled) {
      final stream = _screenStream;
      if (stream == null) return;
      try {
        await _setSourceTrack(_MeshSource.video, _cameraTrack);
        await _setSourceTrack(_MeshSource.screenAudio, null);
      } catch (_) {
        await _setSourceTrackBestEffort(_MeshSource.video, _screenVideoTrack);
        await _setSourceTrackBestEffort(
          _MeshSource.screenAudio,
          _screenAudioTrack,
        );
        rethrow;
      }
      _screenStream = null;
      await _disposeStreamBestEffort(stream);
      changed();
      return;
    }
    if (_screenStream != null) return;
    final stream = await _getDisplayMedia({'video': true, 'audio': true});
    _screenStream = stream;
    if (stream.getVideoTracks().firstOrNull case final screenVideo?) {
      screenVideo.onEnded = () {
        if (!identical(_screenStream, stream) || _closing || disposed) return;
        unawaited(
          _serialize(() async {
            if (identical(_screenStream, stream)) {
              await _setScreenShareEnabled(false);
            }
          }),
        );
      };
    }
    try {
      await _setSourceTrack(_MeshSource.video, _publishedVideoTrack);
      await _setSourceTrack(_MeshSource.screenAudio, _screenAudioTrack);
    } catch (error, stackTrace) {
      _screenStream = null;
      await _setSourceTrackBestEffort(_MeshSource.video, _cameraTrack);
      await _setSourceTrackBestEffort(_MeshSource.screenAudio, null);
      await _disposeStreamBestEffort(stream);
      Error.throwWithStackTrace(error, stackTrace);
    }
    changed();
  }

  Future<void> _setSourceTrackBestEffort(
    _MeshSource source,
    rtc.MediaStreamTrack? track,
  ) async {
    try {
      await _setSourceTrack(source, track);
    } catch (_) {
      // Preserve the primary capture/transition error while restoring as many
      // senders as the surviving peer connections allow.
    }
  }

  Future<void> _disposeStreamBestEffort(rtc.MediaStream stream) async {
    for (final track in stream.getTracks()) {
      try {
        await track.stop();
      } catch (_) {}
    }
    try {
      await stream.dispose();
    } catch (_) {}
  }

  Future<void> _setSourceTrack(
    _MeshSource source,
    rtc.MediaStreamTrack? track,
  ) async {
    final changedSenders = <(rtc.RTCRtpSender, rtc.MediaStreamTrack?)>[];
    bool sameTrack(
      rtc.MediaStreamTrack? current,
      rtc.MediaStreamTrack? desired,
    ) =>
        identical(current, desired) ||
        (current == null && desired == null) ||
        (current?.id != null &&
            desired?.id != null &&
            current?.id == desired?.id);
    try {
      for (final entry in _sendSlots.entries.toList()) {
        if (!identical(_sendSlots[entry.key], entry.value)) continue;
        final sender = entry.value.sender(source);
        final previous = sender.track;
        if (sameTrack(previous, track)) continue;
        await sender.replaceTrack(track);
        changedSenders.add((sender, previous));
      }
    } catch (_) {
      for (final (sender, previous) in changedSenders.reversed) {
        try {
          await sender.replaceTrack(previous);
        } catch (_) {}
      }
      rethrow;
    }
    if (track != null && source != _MeshSource.video) {
      for (final (sender, _) in changedSenders) {
        await _applyAudioQuality(sender);
      }
    }
  }

  Future<void> _applyAudioQuality(rtc.RTCRtpSender sender) async {
    try {
      final parameters = sender.parameters;
      final bitrate = switch (join.room.maxQualityProfile) {
        VoiceQualityProfile.standard => 24000,
        VoiceQualityProfile.high => 48000,
        VoiceQualityProfile.maximum => 96000,
      };
      for (final encoding
          in parameters.encodings ?? const <rtc.RTCRtpEncoding>[]) {
        encoding.maxBitrate = bitrate;
      }
      await sender.setParameters(parameters);
    } catch (_) {
      // Bitrate is a best-effort quality cap, never a prerequisite for media.
    }
  }

  Future<void> _closePeer(int id) async {
    final peer = _peers.remove(id);
    _sendSlots.remove(id);
    final remote = _remoteTracks.remove(id);
    if (remote != null) {
      for (final track in remote.tracks) {
        await _stopRemoteTrackBestEffort(track);
      }
    }
    _pendingCandidates.remove(id);
    _candidateTimers.remove(id)?.cancel();
    _outgoingCandidates.remove(id);
    _makingOffer.remove(id);
    if (peer != null) {
      _recordDiagnostic(
        diagnostics,
        'mesh.peer.close.started',
        component: 'webrtc',
        correlationId: correlationId,
        data: {'peerAlias': _peerDiagnosticAlias(id)},
      );
      await peer.close();
      await peer.dispose();
      _recordDiagnostic(
        diagnostics,
        'mesh.peer.close.completed',
        component: 'webrtc',
        correlationId: correlationId,
        data: {'peerAlias': _peerDiagnosticAlias(id)},
      );
    }
    changed();
  }

  @override
  Future<void> dispose() async {
    if (_closing || disposed) return;
    _closing = true;
    try {
      await _mutationTail;
      _speakingTimer?.cancel();
      _speakingTimer = null;
      _rawStatsTimer?.cancel();
      _rawStatsTimer = null;
      for (final timer in _candidateTimers.values) {
        timer.cancel();
      }
      _candidateTimers.clear();
      _outgoingCandidates.clear();
      for (final id in _peers.keys.toList()) {
        try {
          await _closePeer(id);
        } catch (_) {}
      }
      final streams = Set<rtc.MediaStream>.identity()
        ..addAll(_ownedLocalStreams);
      if (_localStream case final stream?) streams.add(stream);
      if (_screenStream case final stream?) streams.add(stream);
      final tracks = Set<rtc.MediaStreamTrack>.identity();
      for (final stream in streams) {
        tracks.addAll(stream.getTracks());
      }
      for (final track in tracks) {
        try {
          await track.stop();
        } catch (_) {}
      }
      for (final stream in streams) {
        try {
          await stream.dispose();
        } catch (_) {}
      }
    } finally {
      _localStream = null;
      _screenStream = null;
      _ownedLocalStreams.clear();
      _participantVolumes.clear();
      _participantRoles.clear();
      _currentRemoteParticipantIds.clear();
      _peerEligibleParticipantIds.clear();
      _recordDiagnostic(
        diagnostics,
        'mesh.session.disposed',
        component: 'mesh',
        correlationId: correlationId,
      );
      await super.dispose();
    }
  }
}

final class _NativeVoiceLiveKitRoomAdapter implements VoiceLiveKitRoomAdapter {
  _NativeVoiceLiveKitRoomAdapter(this.room);

  @override
  final lk.Room room;
  lk.EventsListener<lk.RoomEvent>? _listener;

  void listenToRoomEvents(ValueChanged<lk.RoomEvent> onEvent) {
    _listener = room.createListener()..on<lk.RoomEvent>(onEvent);
  }

  @override
  void listen({
    required VoidCallback onChanged,
    required VoidCallback onDisconnected,
  }) {
    _listener = room.createListener()
      ..on<lk.RoomEvent>((event) {
        onChanged();
        if (event is lk.RoomDisconnectedEvent) onDisconnected();
      });
  }

  @override
  Future<void> connect(String endpoint, String token) =>
      room.connect(endpoint, token);

  @override
  Future<void> cancelListener() async {
    final listener = _listener;
    _listener = null;
    await listener?.dispose();
  }

  @override
  Future<void> disconnect() async {
    if (room.connectionState == lk.ConnectionState.disconnected) return;
    await room.disconnect();
  }

  @override
  Future<void> disposeRoom() async {
    await room.dispose();
  }
}

final class LiveKitVoiceMediaSession extends _VoiceMediaNotifier {
  LiveKitVoiceMediaSession({
    required this.join,
    required this.localUserId,
    required this.audioPublishingAllowed,
    required this.refreshCredentials,
    this.diagnostics = const NoopVoiceDiagnosticsRecorder(),
    this.correlationId = 'uncorrelated',
    this.rawStatsInterval = const Duration(seconds: 5),
    VoiceLiveKitRawStatsCollector? collectRawStats,
    VoiceMediaDeviceEnumerator? enumerateDevices,
    VoiceLiveKitRoomAdapter? roomAdapter,
  }) : _collectRawStats = collectRawStats ?? _collectLiveKitRawStats,
       _enumerateDevices =
           enumerateDevices ??
           (() => rtc.navigator.mediaDevices.enumerateDevices()) {
    _roomAdapter =
        roomAdapter ??
        _NativeVoiceLiveKitRoomAdapter(
          lk.Room(roomOptions: _roomOptions(join.room)),
        );
    _reconnect = VoiceReconnectCoordinator(
      attempt: _reconnectOnce,
      onStateChanged: (state) {
        _recordDiagnostic(
          diagnostics,
          'livekit.reconnect.state_changed',
          component: 'livekit',
          correlationId: correlationId,
          severity: state == VoiceMediaConnectionState.failed
              ? DiagnosticSeverity.error
              : DiagnosticSeverity.info,
          data: {'state': state.name},
        );
        changed();
      },
      onAttemptStarted: (attemptNumber, delay) {
        _recordDiagnostic(
          diagnostics,
          'livekit.reconnect.attempt_started',
          component: 'livekit',
          correlationId: correlationId,
          data: {
            'attempt': attemptNumber,
            'delayMilliseconds': delay.inMilliseconds,
          },
        );
      },
      onAttemptFailed: (attemptNumber, error, stackTrace) {
        _recordDiagnostic(
          diagnostics,
          'livekit.reconnect.attempt_failed',
          component: 'livekit',
          correlationId: correlationId,
          severity: DiagnosticSeverity.warning,
          data: {
            'attempt': attemptNumber,
            'errorType': error.runtimeType.toString(),
          },
        );
        _recordRawDiagnostic(
          diagnostics,
          'livekit.reconnect.attempt_failure_detail',
          component: 'livekit',
          correlationId: correlationId,
          severity: DiagnosticSeverity.warning,
          message: error.toString(),
          data: {'attempt': attemptNumber, 'stackTrace': stackTrace.toString()},
        );
      },
      onExhausted: (attemptCount) {
        _recordDiagnostic(
          diagnostics,
          'livekit.reconnect.exhausted',
          component: 'livekit',
          correlationId: correlationId,
          severity: DiagnosticSeverity.error,
          data: {'attemptCount': attemptCount},
        );
      },
    );
  }

  final VoiceJoinResponse join;
  final int localUserId;
  final VoiceLiveKitCredentialRefresher refreshCredentials;
  final VoiceDiagnosticsRecorder diagnostics;
  final String correlationId;
  final Duration rawStatsInterval;
  final VoiceLiveKitRawStatsCollector _collectRawStats;
  final VoiceMediaDeviceEnumerator _enumerateDevices;
  late final VoiceLiveKitRoomAdapter _roomAdapter;
  lk.Room get _room => _roomAdapter.room;

  static lk.RoomOptions _roomOptions(VoiceRoom room) => lk.RoomOptions(
    adaptiveStream: true,
    dynacast: true,
    defaultAudioCaptureOptions: const lk.AudioCaptureOptions(
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
    ),
    defaultAudioPublishOptions: lk.AudioPublishOptions(
      encoding: switch (room.maxQualityProfile) {
        VoiceQualityProfile.standard => lk.AudioEncoding.presetSpeech,
        VoiceQualityProfile.high => lk.AudioEncoding.presetMusic,
        VoiceQualityProfile.maximum => lk.AudioEncoding.presetMusicHighQuality,
      },
    ),
  );
  bool audioPublishingAllowed;
  bool _muted = false;

  /// Shared by connect, reconnect, and stage changes so a mute that lands while
  /// the socket opens cannot be overwritten by the ensuing connect.
  @visibleForTesting
  bool get shouldPublishMicrophone => audioPublishingAllowed && !_muted;

  bool _deafened = false;

  @visibleForTesting
  bool get deafened => _deafened;

  /// Retained because disconnect drops local publications; a rebuilt session
  /// must republish a camera the app still reports as enabled.
  bool _cameraEnabled = false;
  String? _cameraDeviceId;

  @visibleForTesting
  bool get cameraEnabled => _cameraEnabled;
  bool _closing = false;
  bool _pollingRawStats = false;
  bool _deviceInventoryCaptured = false;
  Timer? _rawStatsTimer;
  late final VoiceReconnectCoordinator _reconnect;
  final Set<Future<void>> _roomConnections = {};
  Future<void>? _disposeFuture;

  @override
  VoiceTransport get transport => VoiceTransport.livekit;

  @override
  VoiceMediaConnectionState get connectionState => _reconnect.connectionState;

  @override
  bool get screenSharing =>
      _room.localParticipant?.isScreenShareEnabled() ?? false;

  lk.Participant? _participant(int id) => _room.remoteParticipants['$id'];

  @override
  Object? get localVideoTrack => _videoTrack(_room.localParticipant);

  @override
  Object? videoTrackFor(int participantId) => participantId == localUserId
      ? localVideoTrack
      : _videoTrack(_participant(participantId));

  static lk.VideoTrack? _videoTrack(lk.Participant? participant) {
    if (participant == null) return null;
    for (final publication in participant.videoTrackPublications) {
      final track = publication.track;
      if (track is lk.VideoTrack && !publication.muted) return track;
    }
    return null;
  }

  @override
  Set<int> get speakingParticipantIds {
    final result = <int>{};
    for (final participant in _room.activeSpeakers) {
      final id = int.tryParse(participant.identity);
      if (id != null) result.add(id);
    }
    return result;
  }

  @override
  Future<List<rtc.MediaDeviceInfo>> devices() async {
    final result = await _enumerateDevicesWithDiagnostics(
      enumerateDevices: _enumerateDevices,
      diagnostics: diagnostics,
      correlationId: correlationId,
    );
    try {
      if (diagnostics.captureEnabled) _deviceInventoryCaptured = true;
    } catch (_) {}
    return result;
  }

  @override
  Future<void> connect() async {
    if (_closing || disposed) return;
    final credentials = join.livekit;
    if (credentials == null ||
        credentials.url.isEmpty ||
        credentials.token.isEmpty) {
      throw const FormatException('Missing LiveKit credentials');
    }
    _recordDiagnostic(
      diagnostics,
      'livekit.session.connect.started',
      component: 'livekit',
      correlationId: correlationId,
      data: {'audioPublishingAllowed': audioPublishingAllowed},
    );
    final adapter = _roomAdapter;
    if (adapter is _NativeVoiceLiveKitRoomAdapter) {
      adapter.listenToRoomEvents((event) {
        _recordRoomEvent(event);
        changed();
        // Auto-subscribe means a new publication arrives audible, so a
        // deafened reader has to refuse each one as it appears.
        if (_deafened &&
            (event is lk.TrackPublishedEvent ||
                event is lk.TrackSubscribedEvent ||
                event is lk.ParticipantConnectedEvent)) {
          unawaited(_applyDeafened());
        }
        if (event is lk.RoomDisconnectedEvent && !_closing) {
          _startReconnect(reason: event.reason);
        }
      });
    } else {
      adapter.listen(
        onChanged: changed,
        onDisconnected: () {
          if (!_closing) _startReconnect();
        },
      );
    }
    try {
      await _connectRoom(credentials);
      if (_closing || disposed) return;
      // A mute can land while connect is in flight, before a local participant
      // exists; apply the latest state once the room is ready.
      if (shouldPublishMicrophone) {
        await _withMicrophoneFailure(
          () async => _room.localParticipant?.setMicrophoneEnabled(true),
        );
        if (_closing || disposed) return;
      }
      _startRawStatsTimer();
      _recordDiagnostic(
        diagnostics,
        'livekit.session.connect.completed',
        component: 'livekit',
        correlationId: correlationId,
      );
      changed();
    } catch (error, stackTrace) {
      _recordDiagnostic(
        diagnostics,
        'livekit.session.connect.failed',
        component: 'livekit',
        correlationId: correlationId,
        severity: DiagnosticSeverity.error,
        data: {'errorType': error.runtimeType.toString()},
      );
      _recordRawDiagnostic(
        diagnostics,
        'livekit.session.connect.failure_detail',
        component: 'livekit',
        correlationId: correlationId,
        severity: DiagnosticSeverity.error,
        message: error.toString(),
        data: {'stackTrace': stackTrace.toString()},
      );
      rethrow;
    }
  }

  Future<void> _pollRawStats() async {
    if (_pollingRawStats || _closing || disposed) return;
    try {
      if (!diagnostics.captureEnabled) {
        _deviceInventoryCaptured = false;
        return;
      }
    } catch (_) {
      return;
    }
    _pollingRawStats = true;
    try {
      if (!_deviceInventoryCaptured) {
        try {
          await devices();
        } catch (_) {}
      }
      final samples = await _collectRawStats(_room);
      if (_closing || disposed) return;
      if (samples.isEmpty) {
        _recordRawDiagnostic(
          diagnostics,
          'livekit.room.stats',
          component: 'livekit',
          correlationId: correlationId,
          data: {
            'connectionState': _room.connectionState.name,
            'participantCount':
                _room.remoteParticipants.length +
                (_room.localParticipant == null ? 0 : 1),
            'trackEndpointCount': 0,
          },
        );
      } else {
        for (final sample in samples) {
          _recordRawDiagnostic(
            diagnostics,
            'livekit.track.stats',
            component: 'livekit',
            correlationId: correlationId,
            data: sample,
          );
        }
      }
    } catch (error, stackTrace) {
      _recordRawDiagnostic(
        diagnostics,
        'livekit.room.stats_failed',
        component: 'livekit',
        correlationId: correlationId,
        severity: DiagnosticSeverity.warning,
        message: error.toString(),
        data: {
          'errorType': error.runtimeType.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
    } finally {
      _pollingRawStats = false;
    }
  }

  @visibleForTesting
  Future<void> pollRawStatsForTesting() => _pollRawStats();

  void _startRawStatsTimer() {
    if (rawStatsInterval <= Duration.zero || _rawStatsTimer != null) return;
    _rawStatsTimer = Timer.periodic(
      rawStatsInterval,
      (_) => unawaited(_pollRawStats()),
    );
  }

  @visibleForTesting
  void startRawStatsTimerForTesting() => _startRawStatsTimer();

  void _startReconnect({lk.DisconnectReason? reason}) {
    _recordDiagnostic(
      diagnostics,
      'livekit.reconnect.requested',
      component: 'livekit',
      correlationId: correlationId,
      severity: DiagnosticSeverity.warning,
      data: {'cause': reason?.name ?? 'room_disconnected'},
    );
    final observed = _reconnect.reconnect().then<void>(
      (_) {},
      onError: _reportUnexpectedReconnectFailure,
    );
    unawaited(observed);
  }

  @visibleForTesting
  void reportUnexpectedReconnectFailureForTesting(
    Object error,
    StackTrace stackTrace,
  ) => _reportUnexpectedReconnectFailure(error, stackTrace);

  void _reportUnexpectedReconnectFailure(Object error, StackTrace stackTrace) {
    _recordDiagnostic(
      diagnostics,
      'livekit.reconnect.unhandled_failure',
      component: 'livekit',
      correlationId: correlationId,
      severity: DiagnosticSeverity.error,
      data: {'errorType': error.runtimeType.toString()},
    );
    _recordRawDiagnostic(
      diagnostics,
      'livekit.reconnect.unhandled_failure_detail',
      component: 'livekit',
      correlationId: correlationId,
      severity: DiagnosticSeverity.error,
      message: error.toString(),
      data: {'stackTrace': stackTrace.toString()},
    );
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: const _VoiceMediaDiagnosticFailure('livekit.reconnect'),
        stack: stackTrace,
        library: 'Voice media',
        context: ErrorDescription('while reconnecting a LiveKit room'),
      ),
    );
  }

  Future<void> _reconnectOnce() async {
    _recordDiagnostic(
      diagnostics,
      'livekit.credentials.refresh.started',
      component: 'livekit',
      correlationId: correlationId,
    );
    final credentials = await refreshCredentials();
    _recordDiagnostic(
      diagnostics,
      'livekit.credentials.refresh.completed',
      component: 'livekit',
      correlationId: correlationId,
    );
    if (_closing || disposed || _reconnect.cancelled) return;
    await _connectRoom(credentials);
    if (_closing || disposed || _reconnect.cancelled) return;
    if (shouldPublishMicrophone) {
      await _room.localParticipant?.setMicrophoneEnabled(true);
    }
    // The rebuilt room subscribes everything again, so a reader who was
    // deafened before the drop would come back hearing the room.
    await _applyDeafened();
    if (_cameraEnabled) {
      await _publishCamera(true, deviceId: _cameraDeviceId);
    }
  }

  Future<void> _connectRoom(VoiceLiveKitCredentials credentials) async {
    if (_closing || disposed) return;
    _recordDiagnostic(
      diagnostics,
      'livekit.room.connect.started',
      component: 'livekit',
      correlationId: correlationId,
    );
    final endpoint = requireSafeLiveKitEndpoint(credentials.url);
    final connection = _roomAdapter.connect(
      endpoint.toString(),
      credentials.token,
    );
    _roomConnections.add(connection);
    try {
      await connection;
      _recordDiagnostic(
        diagnostics,
        'livekit.room.connect.completed',
        component: 'livekit',
        correlationId: correlationId,
      );
    } finally {
      _roomConnections.remove(connection);
    }
  }

  void _recordRoomEvent(lk.RoomEvent event) {
    if (event is lk.RoomConnectedEvent) {
      _recordDiagnostic(
        diagnostics,
        'livekit.room.connected',
        component: 'livekit',
        correlationId: correlationId,
      );
      return;
    }
    if (event is lk.RoomReconnectingEvent) {
      _recordDiagnostic(
        diagnostics,
        'livekit.room.reconnecting',
        component: 'livekit',
        correlationId: correlationId,
        severity: DiagnosticSeverity.warning,
        data: {'mode': 'full'},
      );
      return;
    }
    if (event is lk.RoomResumingEvent) {
      _recordDiagnostic(
        diagnostics,
        'livekit.room.reconnecting',
        component: 'livekit',
        correlationId: correlationId,
        severity: DiagnosticSeverity.warning,
        data: {'mode': 'signal_resume'},
      );
      return;
    }
    if (event is lk.RoomAttemptReconnectEvent) {
      _recordDiagnostic(
        diagnostics,
        'livekit.room.reconnect_attempt',
        component: 'livekit',
        correlationId: correlationId,
        data: {
          'attempt': event.attempt,
          'maxAttempts': event.maxAttemptsRetry,
          'nextDelayMilliseconds': event.nextRetryDelaysInMs,
        },
      );
      return;
    }
    if (event is lk.RoomReconnectedEvent) {
      _recordDiagnostic(
        diagnostics,
        'livekit.room.reconnected',
        component: 'livekit',
        correlationId: correlationId,
      );
      return;
    }
    if (event is lk.RoomDisconnectedEvent) {
      final expected =
          _closing || event.reason == lk.DisconnectReason.clientInitiated;
      _recordDiagnostic(
        diagnostics,
        'livekit.room.disconnected',
        component: 'livekit',
        correlationId: correlationId,
        severity: expected
            ? DiagnosticSeverity.info
            : DiagnosticSeverity.warning,
        data: {'reason': event.reason?.name ?? 'unknown', 'expected': expected},
      );
      return;
    }
    if (event is lk.ParticipantConnectedEvent) {
      _recordLiveKitParticipantEvent(
        'livekit.participant.connected',
        event.participant,
      );
      return;
    }
    if (event is lk.ParticipantDisconnectedEvent) {
      _recordLiveKitParticipantEvent(
        'livekit.participant.disconnected',
        event.participant,
      );
      return;
    }
    if (event is lk.ParticipantConnectionQualityUpdatedEvent) {
      _recordRawDiagnostic(
        diagnostics,
        'livekit.participant.connection_quality',
        component: 'livekit',
        correlationId: correlationId,
        data: {
          'participant': _liveKitParticipantData(event.participant),
          'quality': event.connectionQuality.name,
        },
      );
      return;
    }
    if (event is lk.TrackPublishedEvent) {
      _recordLiveKitTrackEvent(
        'livekit.track.published',
        event.participant,
        event.publication,
      );
      return;
    }
    if (event is lk.TrackUnpublishedEvent) {
      _recordLiveKitTrackEvent(
        'livekit.track.unpublished',
        event.participant,
        event.publication,
      );
      return;
    }
    if (event is lk.LocalTrackPublishedEvent) {
      _recordLiveKitTrackEvent(
        'livekit.track.local_published',
        event.participant,
        event.publication,
      );
      return;
    }
    if (event is lk.LocalTrackUnpublishedEvent) {
      _recordLiveKitTrackEvent(
        'livekit.track.local_unpublished',
        event.participant,
        event.publication,
      );
      return;
    }
    if (event is lk.TrackSubscribedEvent) {
      _recordLiveKitTrackEvent(
        'livekit.track.subscribed',
        event.participant,
        event.publication,
      );
      return;
    }
    if (event is lk.TrackUnsubscribedEvent) {
      _recordLiveKitTrackEvent(
        'livekit.track.unsubscribed',
        event.participant,
        event.publication,
      );
      return;
    }
    if (event is lk.TrackMutedEvent) {
      _recordLiveKitTrackEvent(
        'livekit.track.muted',
        event.participant,
        event.publication,
      );
      return;
    }
    if (event is lk.TrackUnmutedEvent) {
      _recordLiveKitTrackEvent(
        'livekit.track.unmuted',
        event.participant,
        event.publication,
      );
      return;
    }
    if (event is lk.TrackStreamStateUpdatedEvent) {
      _recordLiveKitTrackEvent(
        'livekit.track.stream_state',
        event.participant,
        event.publication,
        extra: {'state': event.streamState.name},
      );
      return;
    }
    if (event is lk.TrackSubscriptionExceptionEvent) {
      _recordRawDiagnostic(
        diagnostics,
        'livekit.track.subscription_failed',
        component: 'livekit',
        correlationId: correlationId,
        severity: DiagnosticSeverity.warning,
        data: {
          if (event.participant case final participant?)
            'participant': _liveKitParticipantData(participant),
          'trackSid': event.sid,
          'reason': event.reason.name,
        },
      );
      return;
    }
    if (event is lk.RoomRecordingStatusChanged) {
      _recordDiagnostic(
        diagnostics,
        'livekit.room.recording_changed',
        component: 'livekit',
        correlationId: correlationId,
        data: {'active': event.activeRecording},
      );
    }
  }

  @visibleForTesting
  void recordRoomEventForTesting(lk.RoomEvent event) => _recordRoomEvent(event);

  void _recordLiveKitParticipantEvent(
    String event,
    lk.Participant participant,
  ) {
    _recordRawDiagnostic(
      diagnostics,
      event,
      component: 'livekit',
      correlationId: correlationId,
      data: {'participant': _liveKitParticipantData(participant)},
    );
  }

  void _recordLiveKitTrackEvent(
    String event,
    lk.Participant participant,
    lk.TrackPublication publication, {
    Map<String, Object?> extra = const {},
  }) {
    _recordRawDiagnostic(
      diagnostics,
      event,
      component: 'livekit',
      correlationId: correlationId,
      data: {
        'participant': _liveKitParticipantData(participant),
        'publication': {
          'sid': publication.sid,
          'name': publication.name,
          'kind': publication.kind.name,
          'source': publication.source.name,
          'muted': publication.muted,
          'subscribed': publication.subscribed,
          'mimeType': publication.mimeType,
        },
        ...extra,
      },
    );
  }

  Map<String, Object?> _liveKitParticipantData(lk.Participant participant) => {
    'sid': participant.sid,
    'identity': participant.identity,
    'name': participant.name,
    'kind': participant.kind.name,
    'state': participant.state.name,
    'isSpeaking': participant.isSpeaking,
    'isMuted': participant.isMuted,
  };

  @override
  Future<void> syncParticipants(List<VoiceParticipant> participants) async {}

  @override
  Future<void> handleSignal(int senderId, Map<String, dynamic> data) async {}

  @override
  Future<void> selectAudioInput(String deviceId) async {
    final enabled = shouldPublishMicrophone;
    await _room.localParticipant?.setMicrophoneEnabled(false);
    if (enabled) {
      await _room.localParticipant?.setMicrophoneEnabled(
        true,
        audioCaptureOptions: lk.AudioCaptureOptions(deviceId: deviceId),
      );
    }
    changed();
  }

  @override
  Future<void> setAudioPublishingAllowed(bool allowed) async {
    audioPublishingAllowed = allowed;
    await _room.localParticipant?.setMicrophoneEnabled(allowed && !_muted);
    changed();
  }

  @override
  Future<void> setMuted(bool muted) async {
    // Commit only after the SDK accepts the change; controller rollback and
    // later publishing decisions must observe the same value.
    await _room.localParticipant?.setMicrophoneEnabled(
      audioPublishingAllowed && !muted,
    );
    _muted = muted;
    changed();
  }

  @override
  Future<void> setDeafened(bool deafened) async {
    _deafened = deafened;
    await _applyDeafened();
    changed();
  }

  /// Reapply whenever publications change because LiveKit auto-subscribes them.
  Future<void> _applyDeafened() async {
    for (final participant in _room.remoteParticipants.values) {
      for (final publication in participant.audioTrackPublications) {
        if (_deafened) {
          await publication.unsubscribe();
        } else {
          await publication.subscribe();
        }
      }
    }
  }

  @override
  Future<void> setCameraEnabled(bool enabled, {String? deviceId}) async {
    await _publishCamera(enabled, deviceId: deviceId);
    _cameraEnabled = enabled;
    if (enabled) _cameraDeviceId = deviceId;
    changed();
  }

  Future<void> _publishCamera(bool enabled, {String? deviceId}) =>
      _room.localParticipant?.setCameraEnabled(
        enabled,
        cameraCaptureOptions: lk.CameraCaptureOptions(
          deviceId: deviceId,
          params: switch (join.room.maxQualityProfile) {
            VoiceQualityProfile.standard => lk.VideoParametersPresets.h360_169,
            VoiceQualityProfile.high => lk.VideoParametersPresets.h720_169,
            VoiceQualityProfile.maximum => lk.VideoParametersPresets.h1080_169,
          },
        ),
      ) ??
      Future<void>.value();

  @override
  Future<void> setScreenShareEnabled(bool enabled) async {
    await _room.localParticipant?.setScreenShareEnabled(
      enabled,
      captureScreenAudio: true,
      screenShareCaptureOptions: lk.ScreenShareCaptureOptions(
        captureScreenAudio: true,
        params: switch (join.room.maxQualityProfile) {
          VoiceQualityProfile.standard =>
            lk.VideoParametersPresets.screenShareH360FPS3,
          VoiceQualityProfile.high =>
            lk.VideoParametersPresets.screenShareH720FPS15,
          VoiceQualityProfile.maximum =>
            lk.VideoParametersPresets.screenShareH1080FPS30,
        },
      ),
    );
    changed();
  }

  @override
  Future<void> setParticipantVolume(int participantId, double volume) async {
    final participant = _participant(participantId);
    if (participant == null) return;
    for (final publication in participant.audioTrackPublications) {
      final track = publication.track;
      if (track is lk.RemoteAudioTrack) {
        await rtc.Helper.setVolume(volume.clamp(0, 1), track.mediaStreamTrack);
      }
    }
  }

  @override
  Future<void> dispose() {
    final active = _disposeFuture;
    if (active != null) return active;

    // Close the mutation boundary before the first asynchronous cleanup step.
    // A caller may start disposing without awaiting it and then race another
    // connect attempt in the same event-loop turn.
    _closing = true;
    _rawStatsTimer?.cancel();
    _rawStatsTimer = null;
    _reconnect.cancel();
    final pendingConnections = _roomConnections.toList();
    final roomCleanup = _disposeLiveKit(pendingConnections);
    return _disposeFuture = roomCleanup.then<void>(
      (_) => super.dispose(),
      onError: (Object error, StackTrace stackTrace) async {
        try {
          await super.dispose();
        } catch (_) {
          // Preserve the first cleanup failure after reaching terminal state.
        }
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  Future<void> _disposeLiveKit(List<Future<void>> pendingConnections) async {
    Object? firstError;
    StackTrace? firstStackTrace;
    Future<void> clean(Future<void> Function() action) async {
      try {
        await action();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    await clean(_roomAdapter.cancelListener);
    await clean(_roomAdapter.disconnect);
    for (final connection in pendingConnections) {
      try {
        await connection;
      } catch (_) {
        // Disconnecting an in-flight connection is an expected teardown path.
      }
    }
    await clean(_roomAdapter.disposeRoom);
    _roomConnections.clear();
    _recordDiagnostic(
      diagnostics,
      'livekit.session.disposed',
      component: 'livekit',
      correlationId: correlationId,
    );

    final error = firstError;
    if (error != null) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }
}
