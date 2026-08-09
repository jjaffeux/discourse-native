import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import 'resenha_models.dart';
import 'resenha_reconnect.dart';

export 'resenha_reconnect.dart' show ResenhaMediaConnectionState;

typedef ResenhaSignalSender =
    Future<void> Function(int recipientId, Map<String, Object?> event);
typedef ResenhaLiveKitCredentialRefresher =
    Future<ResenhaLiveKitCredentials> Function();

abstract interface class ResenhaMediaSession implements Listenable {
  ResenhaTransport get transport;
  ResenhaMediaConnectionState get connectionState;
  Object? get localVideoTrack;
  Object? videoTrackFor(int participantId);
  Set<int> get speakingParticipantIds;

  Future<void> connect();
  Future<void> syncParticipants(List<ResenhaParticipant> participants);
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

abstract interface class ResenhaMediaFactory {
  ResenhaMediaSession create({
    required ResenhaJoinResponse join,
    required int localUserId,
    required ResenhaSignalSender sendSignal,
    required ResenhaLiveKitCredentialRefresher refreshLiveKitCredentials,
  });
}

final class NativeResenhaMediaFactory implements ResenhaMediaFactory {
  const NativeResenhaMediaFactory();

  @override
  ResenhaMediaSession create({
    required ResenhaJoinResponse join,
    required int localUserId,
    required ResenhaSignalSender sendSignal,
    required ResenhaLiveKitCredentialRefresher refreshLiveKitCredentials,
  }) => switch (join.transport) {
    ResenhaTransport.mesh => MeshResenhaMediaSession(
      join: join,
      localUserId: localUserId,
      sendSignal: sendSignal,
      audioPublishingAllowed: _canPublishAudio(join.room, localUserId),
    ),
    ResenhaTransport.livekit => LiveKitResenhaMediaSession(
      join: join,
      localUserId: localUserId,
      audioPublishingAllowed: _canPublishAudio(join.room, localUserId),
      refreshCredentials: refreshLiveKitCredentials,
    ),
  };

  static bool _canPublishAudio(ResenhaRoom room, int userId) {
    if (room.type != ResenhaRoomType.stage) return true;
    final role = room.participants
        .where((participant) => participant.id == userId)
        .firstOrNull
        ?.role;
    final effective = role ?? room.membership?.role;
    return effective == ResenhaRole.moderator ||
        effective == ResenhaRole.speaker;
  }
}

abstract base class _ResenhaMediaNotifier extends ChangeNotifier
    implements ResenhaMediaSession {
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

final class MeshResenhaMediaSession extends _ResenhaMediaNotifier {
  MeshResenhaMediaSession({
    required this.join,
    required this.localUserId,
    required this.sendSignal,
    required this.audioPublishingAllowed,
  });

  final ResenhaJoinResponse join;
  final int localUserId;
  final ResenhaSignalSender sendSignal;
  final Map<int, rtc.RTCPeerConnection> _peers = {};
  final Map<int, rtc.MediaStream> _remoteStreams = {};
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
  bool _pollingSpeaking = false;
  Set<int> _speaking = const {};
  String? _audioInputDeviceId;

  @override
  ResenhaTransport get transport => ResenhaTransport.mesh;

  @override
  ResenhaMediaConnectionState get connectionState =>
      ResenhaMediaConnectionState.connected;

  @override
  Object? get localVideoTrack =>
      _screenStream?.getVideoTracks().firstOrNull ??
      _localStream?.getVideoTracks().firstOrNull;

  @override
  Object? videoTrackFor(int participantId) => participantId == localUserId
      ? localVideoTrack
      : _remoteStreams[participantId]?.getVideoTracks().firstOrNull;

  @override
  Set<int> get speakingParticipantIds => _speaking;

  @override
  Future<void> connect() async {
    if (audioPublishingAllowed) await _ensureAudioTrack();
    await syncParticipants(join.room.participants);
    _speakingTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(_pollSpeakingLevels()),
    );
  }

  Future<void> _pollSpeakingLevels() async {
    if (_pollingSpeaking || disposed) return;
    _pollingSpeaking = true;
    final next = <int>{};
    try {
      for (final entry in _peers.entries) {
        final reports = await entry.value.getStats();
        final audible = reports.any((report) {
          if (report.type != 'inbound-rtp') return false;
          final values = report.values;
          if (values['kind'] != 'audio' && values['mediaType'] != 'audio') {
            return false;
          }
          final level = values['audioLevel'];
          return level is num && level > 0.01;
        });
        if (audible) next.add(entry.key);
      }
      if (!setEquals(next, _speaking)) {
        _speaking = Set.unmodifiable(next);
        changed();
      }
    } finally {
      _pollingSpeaking = false;
    }
  }

  Future<void> _ensureAudioTrack() async {
    if (_localStream?.getAudioTracks().isNotEmpty == true) return;
    final stream = await rtc.navigator.mediaDevices.getUserMedia({
      'audio': {
        'deviceId': ?_audioInputDeviceId,
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    _localStream ??= stream;
    final track = stream.getAudioTracks().first;
    track.enabled = !_muted;
    if (!identical(_localStream, stream)) await _localStream!.addTrack(track);
    await _replaceTrack(null, track);
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
  Future<void> syncParticipants(List<ResenhaParticipant> participants) async {
    final wanted = {
      for (final participant in participants)
        if (participant.id != localUserId) participant.id,
    };
    final gone = _peers.keys.where((id) => !wanted.contains(id)).toList();
    for (final id in gone) {
      await _closePeer(id);
    }
    for (final id in wanted) {
      if (!_peers.containsKey(id)) await _createPeer(id);
    }
  }

  Future<void> _createPeer(int peerId) async {
    if (disposed || _peers.containsKey(peerId)) return;
    final peer = await rtc.createPeerConnection(_configuration);
    _peers[peerId] = peer;
    peer.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _queueCandidate(peerId, candidate);
    };
    peer.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStreams[peerId] = event.streams.first;
        _applyRemoteAudio(peerId);
        changed();
      }
    };
    peer.onConnectionState = (state) {
      if (state == rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(_restartPeer(peerId));
      }
    };
    final local = _localStream;
    if (local != null) {
      for (final track in local.getTracks()) {
        final sender = await peer.addTrack(track, local);
        if (track.kind == 'audio') await _applyAudioQuality(sender);
      }
    }
    if (local?.getAudioTracks().isEmpty ?? true) {
      await peer.addTransceiver(
        kind: rtc.RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: rtc.RTCRtpTransceiverInit(
          direction: rtc.TransceiverDirection.RecvOnly,
        ),
      );
    }
    if (localUserId < peerId) await _offer(peerId);
  }

  void _queueCandidate(int peerId, rtc.RTCIceCandidate candidate) {
    (_outgoingCandidates[peerId] ??= []).add({
      'type': 'candidate',
      'candidate': candidate.toMap(),
    });
    _candidateTimers.putIfAbsent(
      peerId,
      () => Timer(
        const Duration(milliseconds: 30),
        () => unawaited(_flushOutgoingCandidates(peerId)),
      ),
    );
  }

  Future<void> _flushOutgoingCandidates(int peerId) async {
    _candidateTimers.remove(peerId)?.cancel();
    final events = _outgoingCandidates.remove(peerId);
    if (events == null || events.isEmpty || disposed) return;
    await sendSignal(peerId, {'events': events});
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
      await sendSignal(peerId, {'type': 'offer', 'sdp': offer.sdp});
    } finally {
      _makingOffer.remove(peerId);
    }
  }

  Future<void> _restartPeer(int peerId) async {
    if (disposed || !_peers.containsKey(peerId)) return;
    if (localUserId < peerId) {
      await _offer(peerId, restartIce: true);
    }
  }

  @override
  Future<void> handleSignal(int senderId, Map<String, dynamic> data) async {
    if (disposed) return;
    if (!_peers.containsKey(senderId)) await _createPeer(senderId);
    final peer = _peers[senderId];
    if (peer == null) return;
    switch (data['type']) {
      case 'offer':
        final sdp = data['sdp'];
        if (sdp is! String) return;
        final collision =
            _makingOffer.contains(senderId) ||
            peer.signalingState !=
                rtc.RTCSignalingState.RTCSignalingStateStable;
        final polite = localUserId > senderId;
        if (collision && !polite) return;
        if (collision) {
          await peer.setLocalDescription(
            rtc.RTCSessionDescription('', 'rollback'),
          );
        }
        await peer.setRemoteDescription(
          rtc.RTCSessionDescription(sdp, 'offer'),
        );
        await _flushCandidates(senderId);
        final answer = await peer.createAnswer();
        await peer.setLocalDescription(answer);
        await sendSignal(senderId, {'type': 'answer', 'sdp': answer.sdp});
      case 'answer':
        final sdp = data['sdp'];
        if (sdp is! String) return;
        await peer.setRemoteDescription(
          rtc.RTCSessionDescription(sdp, 'answer'),
        );
        await _flushCandidates(senderId);
      case 'candidate':
        final candidate = data['candidate'];
        if (candidate is! Map) return;
        final parsed = rtc.RTCIceCandidate(
          candidate['candidate'] as String?,
          candidate['sdpMid'] as String?,
          switch (candidate['sdpMLineIndex']) {
            final num value => value.toInt(),
            _ => null,
          },
        );
        if (await peer.getRemoteDescription() == null) {
          (_pendingCandidates[senderId] ??= []).add(parsed);
        } else {
          await peer.addCandidate(parsed);
        }
    }
  }

  Future<void> _flushCandidates(int peerId) async {
    final peer = _peers[peerId];
    if (peer == null) return;
    for (final candidate
        in _pendingCandidates.remove(peerId) ?? const <rtc.RTCIceCandidate>[]) {
      await peer.addCandidate(candidate);
    }
  }

  @override
  Future<void> selectAudioInput(String deviceId) async {
    _audioInputDeviceId = deviceId;
    if (!audioPublishingAllowed) return;
    final oldTracks =
        _localStream?.getAudioTracks() ?? const <rtc.MediaStreamTrack>[];
    for (final track in oldTracks) {
      await _replaceTrack(track, null);
      await track.stop();
      await _localStream?.removeTrack(track);
    }
    await _ensureAudioTrack();
  }

  @override
  Future<void> setAudioPublishingAllowed(bool allowed) async {
    if (audioPublishingAllowed == allowed) return;
    audioPublishingAllowed = allowed;
    if (allowed) {
      await _ensureAudioTrack();
      for (final peer in _peers.values) {
        for (final transceiver in await peer.getTransceivers()) {
          if (transceiver.receiver.track?.kind == 'audio') {
            await transceiver.setDirection(rtc.TransceiverDirection.SendRecv);
          }
        }
      }
      return;
    }
    for (final track
        in _localStream?.getAudioTracks() ?? const <rtc.MediaStreamTrack>[]) {
      await _replaceTrack(track, null);
      await track.stop();
      await _localStream?.removeTrack(track);
    }
    for (final peer in _peers.values) {
      for (final transceiver in await peer.getTransceivers()) {
        if (transceiver.receiver.track?.kind == 'audio') {
          await transceiver.setDirection(rtc.TransceiverDirection.RecvOnly);
        }
      }
    }
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    if (audioPublishingAllowed && !muted) await _ensureAudioTrack();
    for (final track
        in _localStream?.getAudioTracks() ?? const <rtc.MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> setDeafened(bool deafened) async {
    _deafened = deafened;
    for (final peerId in _remoteStreams.keys) {
      _applyRemoteAudio(peerId);
    }
  }

  void _applyRemoteAudio(int participantId, [double volume = 1]) {
    for (final track
        in _remoteStreams[participantId]?.getAudioTracks() ??
            const <rtc.MediaStreamTrack>[]) {
      track.enabled = !_deafened;
      unawaited(rtc.Helper.setVolume(_deafened ? 0 : volume, track));
    }
  }

  @override
  Future<void> setParticipantVolume(int participantId, double volume) async {
    _applyRemoteAudio(participantId, volume.clamp(0, 1));
  }

  @override
  Future<void> setCameraEnabled(bool enabled, {String? deviceId}) async {
    final existing =
        _localStream?.getVideoTracks() ?? const <rtc.MediaStreamTrack>[];
    if (!enabled) {
      for (final track in existing) {
        await track.stop();
        await _replaceTrack(track, null);
        await _localStream?.removeTrack(track);
      }
      changed();
      return;
    }
    if (existing.isNotEmpty) return;
    final (width, height, frameRate) = switch (join.room.maxQualityProfile) {
      ResenhaQualityProfile.standard => (640, 360, 15),
      ResenhaQualityProfile.high => (1280, 720, 24),
      ResenhaQualityProfile.maximum => (1920, 1080, 30),
    };
    final stream = await rtc.navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {
        'deviceId': ?deviceId,
        'width': {'ideal': width},
        'height': {'ideal': height},
        'frameRate': {'ideal': frameRate},
      },
    });
    final track = stream.getVideoTracks().first;
    if (_localStream == null) {
      _localStream = stream;
    } else {
      await _localStream!.addTrack(track);
    }
    await _replaceTrack(null, track);
    changed();
  }

  @override
  Future<void> setScreenShareEnabled(bool enabled) async {
    if (!enabled) {
      final stream = _screenStream;
      _screenStream = null;
      for (final track
          in stream?.getTracks() ?? const <rtc.MediaStreamTrack>[]) {
        await track.stop();
        await _replaceTrack(track, null);
      }
      changed();
      return;
    }
    if (_screenStream != null) return;
    final stream = await rtc.navigator.mediaDevices.getDisplayMedia({
      'video': true,
      'audio': true,
    });
    _screenStream = stream;
    for (final track in stream.getTracks()) {
      await _replaceTrack(null, track);
    }
    changed();
  }

  Future<void> _replaceTrack(
    rtc.MediaStreamTrack? oldTrack,
    rtc.MediaStreamTrack? newTrack,
  ) async {
    for (final peer in _peers.values) {
      final senders = await peer.getSenders();
      final sender = senders
          .where((value) => value.track?.kind == (oldTrack ?? newTrack)?.kind)
          .firstOrNull;
      if (sender != null) {
        await sender.replaceTrack(newTrack);
        if (newTrack?.kind == 'audio') await _applyAudioQuality(sender);
      } else if (newTrack != null) {
        final added = await peer.addTrack(
          newTrack,
          _screenStream ?? _localStream!,
        );
        if (newTrack.kind == 'audio') await _applyAudioQuality(added);
      }
    }
  }

  Future<void> _applyAudioQuality(rtc.RTCRtpSender sender) async {
    final parameters = sender.parameters;
    final bitrate = switch (join.room.maxQualityProfile) {
      ResenhaQualityProfile.standard => 24000,
      ResenhaQualityProfile.high => 48000,
      ResenhaQualityProfile.maximum => 96000,
    };
    for (final encoding
        in parameters.encodings ?? const <rtc.RTCRtpEncoding>[]) {
      encoding.maxBitrate = bitrate;
    }
    await sender.setParameters(parameters);
  }

  Future<void> _closePeer(int id) async {
    final peer = _peers.remove(id);
    _remoteStreams.remove(id);
    _pendingCandidates.remove(id);
    _candidateTimers.remove(id)?.cancel();
    _outgoingCandidates.remove(id);
    if (peer != null) {
      await peer.close();
      await peer.dispose();
    }
    changed();
  }

  @override
  Future<void> dispose() async {
    _speakingTimer?.cancel();
    _speakingTimer = null;
    for (final timer in _candidateTimers.values) {
      timer.cancel();
    }
    _candidateTimers.clear();
    _outgoingCandidates.clear();
    for (final id in _peers.keys.toList()) {
      await _closePeer(id);
    }
    for (final stream in [_localStream, _screenStream]) {
      for (final track
          in stream?.getTracks() ?? const <rtc.MediaStreamTrack>[]) {
        await track.stop();
      }
      await stream?.dispose();
    }
    _localStream = null;
    _screenStream = null;
    await super.dispose();
  }
}

final class LiveKitResenhaMediaSession extends _ResenhaMediaNotifier {
  LiveKitResenhaMediaSession({
    required this.join,
    required this.localUserId,
    required this.audioPublishingAllowed,
    required this.refreshCredentials,
  }) : _room = lk.Room(roomOptions: _roomOptions(join.room)) {
    _reconnect = ResenhaReconnectCoordinator(
      attempt: _reconnectOnce,
      onStateChanged: (_) => changed(),
    );
  }

  final ResenhaJoinResponse join;
  final int localUserId;
  final ResenhaLiveKitCredentialRefresher refreshCredentials;
  final lk.Room _room;

  static lk.RoomOptions _roomOptions(ResenhaRoom room) => lk.RoomOptions(
    adaptiveStream: true,
    dynacast: true,
    defaultAudioCaptureOptions: const lk.AudioCaptureOptions(
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
    ),
    defaultAudioPublishOptions: lk.AudioPublishOptions(
      encoding: switch (room.maxQualityProfile) {
        ResenhaQualityProfile.standard => lk.AudioEncoding.presetSpeech,
        ResenhaQualityProfile.high => lk.AudioEncoding.presetMusic,
        ResenhaQualityProfile.maximum =>
          lk.AudioEncoding.presetMusicHighQuality,
      },
    ),
  );
  lk.EventsListener<lk.RoomEvent>? _listener;
  bool audioPublishingAllowed;
  bool _muted = false;
  bool _closing = false;
  late final ResenhaReconnectCoordinator _reconnect;
  final Set<Future<void>> _roomConnections = {};

  @override
  ResenhaTransport get transport => ResenhaTransport.livekit;

  @override
  ResenhaMediaConnectionState get connectionState => _reconnect.connectionState;

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
  Future<void> connect() async {
    final credentials = join.livekit;
    if (credentials == null ||
        credentials.url.isEmpty ||
        credentials.token.isEmpty) {
      throw const FormatException('Missing LiveKit credentials');
    }
    _listener = _room.createListener()
      ..on<lk.RoomEvent>((event) {
        changed();
        if (event is lk.RoomDisconnectedEvent && !_closing) {
          _startReconnect();
        }
      });
    await _connectRoom(credentials);
    if (_closing || disposed) return;
    if (audioPublishingAllowed) {
      await _room.localParticipant?.setMicrophoneEnabled(true);
    }
    changed();
  }

  void _startReconnect() {
    final observed = _reconnect.reconnect().then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'Resenha media',
            context: ErrorDescription('while reconnecting a LiveKit room'),
          ),
        );
      },
    );
    unawaited(observed);
  }

  Future<void> _reconnectOnce() async {
    final credentials = await refreshCredentials();
    if (_closing || disposed || _reconnect.cancelled) return;
    await _connectRoom(credentials);
    if (_closing || disposed || _reconnect.cancelled) return;
    if (audioPublishingAllowed && !_muted) {
      await _room.localParticipant?.setMicrophoneEnabled(true);
    }
  }

  Future<void> _connectRoom(ResenhaLiveKitCredentials credentials) async {
    if (_closing || disposed) return;
    final connection = _room.connect(credentials.url, credentials.token);
    _roomConnections.add(connection);
    try {
      await connection;
    } finally {
      _roomConnections.remove(connection);
    }
  }

  @override
  Future<void> syncParticipants(List<ResenhaParticipant> participants) async {}

  @override
  Future<void> handleSignal(int senderId, Map<String, dynamic> data) async {}

  @override
  Future<void> selectAudioInput(String deviceId) async {
    final enabled = audioPublishingAllowed && !_muted;
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
    _muted = muted;
    await _room.localParticipant?.setMicrophoneEnabled(
      audioPublishingAllowed && !muted,
    );
    changed();
  }

  @override
  Future<void> setDeafened(bool deafened) async {
    for (final participant in _room.remoteParticipants.values) {
      for (final publication in participant.audioTrackPublications) {
        if (deafened) {
          await publication.unsubscribe();
        } else {
          await publication.subscribe();
        }
      }
    }
    changed();
  }

  @override
  Future<void> setCameraEnabled(bool enabled, {String? deviceId}) async {
    await _room.localParticipant?.setCameraEnabled(
      enabled,
      cameraCaptureOptions: lk.CameraCaptureOptions(
        deviceId: deviceId,
        params: switch (join.room.maxQualityProfile) {
          ResenhaQualityProfile.standard => lk.VideoParametersPresets.h360_169,
          ResenhaQualityProfile.high => lk.VideoParametersPresets.h720_169,
          ResenhaQualityProfile.maximum => lk.VideoParametersPresets.h1080_169,
        },
      ),
    );
    changed();
  }

  @override
  Future<void> setScreenShareEnabled(bool enabled) async {
    await _room.localParticipant?.setScreenShareEnabled(
      enabled,
      captureScreenAudio: true,
      screenShareCaptureOptions: lk.ScreenShareCaptureOptions(
        captureScreenAudio: true,
        params: switch (join.room.maxQualityProfile) {
          ResenhaQualityProfile.standard =>
            lk.VideoParametersPresets.screenShareH360FPS3,
          ResenhaQualityProfile.high =>
            lk.VideoParametersPresets.screenShareH720FPS15,
          ResenhaQualityProfile.maximum =>
            lk.VideoParametersPresets.screenShareH1080FPS30,
        },
      ),
    );
    changed();
  }

  @override
  Future<void> setParticipantVolume(int participantId, double volume) async {
    final participant = _participant(participantId);
    for (final publication in participant?.audioTrackPublications ?? const []) {
      final track = publication.track;
      if (track is lk.RemoteAudioTrack) {
        await rtc.Helper.setVolume(volume.clamp(0, 1), track.mediaStreamTrack);
      }
    }
  }

  @override
  Future<void> dispose() async {
    _closing = true;
    _reconnect.cancel();
    final pendingConnections = _roomConnections.toList();
    await _listener?.dispose();
    await _room.disconnect();
    for (final connection in pendingConnections) {
      try {
        await connection;
      } catch (_) {
        // Disconnecting an in-flight connection is an expected teardown path.
      }
    }
    await _room.dispose();
    await super.dispose();
  }
}
