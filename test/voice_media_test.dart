import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/plugins/voice/voice_diagnostics.dart';
import 'package:discourse_native/src/plugins/voice/voice_media.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_reconnect.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

VoiceJoinResponse join({
  required VoiceRoomType roomType,
  required VoiceRole role,
}) => VoiceJoinResponse(
  transport: VoiceTransport.mesh,
  ice: const VoiceIceConfiguration(servers: [], relayOnly: false),
  room: VoiceRoom(
    id: 1,
    name: 'Room',
    slug: 'room',
    isPublic: true,
    ephemeral: false,
    type: roomType,
    participants: [VoiceParticipant(id: 10, username: 'sam', role: role)],
  ),
);

typedef _RecordedDiagnostic = ({
  String event,
  String component,
  DiagnosticSeverity severity,
  String? correlationId,
  String? message,
  Map<String, Object?> data,
});

final class _DiagnosticsRecorder implements VoiceDiagnosticsRecorder {
  @override
  bool captureEnabled = false;

  final List<_RecordedDiagnostic> records = [];
  final List<_RecordedDiagnostic> rawRecords = [];

  @override
  void record(
    String event, {
    String component = 'runtime',
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? correlationId,
    Map<String, Object?> data = const {},
  }) {
    records.add((
      event: event,
      component: component,
      severity: severity,
      correlationId: correlationId,
      message: null,
      data: data,
    ));
  }

  @override
  void recordRaw(
    String event, {
    String component = 'sdk',
    DiagnosticSeverity severity = DiagnosticSeverity.debug,
    String? correlationId,
    String? message,
    Map<String, Object?> data = const {},
  }) {
    rawRecords.add((
      event: event,
      component: component,
      severity: severity,
      correlationId: correlationId,
      message: message,
      data: data,
    ));
  }
}

void main() {
  test('stage listeners do not acquire an outgoing audio publication', () {
    final media = const NativeVoiceMediaFactory().create(
      join: join(roomType: VoiceRoomType.stage, role: VoiceRole.participant),
      localUserId: 10,
      sendSignal: (_, _) async {},
      refreshLiveKitCredentials: () async =>
          const VoiceLiveKitCredentials(url: '', token: ''),
    );

    expect((media as MeshVoiceMediaSession).audioPublishingAllowed, isFalse);
  });

  test('stage speakers and open-room participants may publish audio', () {
    for (final response in [
      join(roomType: VoiceRoomType.stage, role: VoiceRole.speaker),
      join(roomType: VoiceRoomType.open, role: VoiceRole.participant),
    ]) {
      final media = const NativeVoiceMediaFactory().create(
        join: response,
        localUserId: 10,
        sendSignal: (_, _) async {},
        refreshLiveKitCredentials: () async =>
            const VoiceLiveKitCredentials(url: '', token: ''),
      );

      expect((media as MeshVoiceMediaSession).audioPublishingAllowed, isTrue);
    }
  });

  group('MeshVoiceMediaSession', () {
    test('classifies a denied microphone permission during capture', () async {
      final media = _meshSession(
        peer: _FakePeerConnection(),
        audioPublishingAllowed: true,
        getUserMedia: (_) async =>
            throw StateError('NotAllowedError: Permission denied'),
      );

      await expectLater(
        media.connect(),
        throwsA(
          isA<VoiceMicrophoneException>().having(
            (error) => error.kind,
            'kind',
            VoiceMicrophoneFailureKind.permissionDenied,
          ),
        ),
      );
      await media.dispose();
    });

    test(
      'pre-negotiates microphone, video, and screen audio in order',
      () async {
        final peer = _FakePeerConnection();
        final media = _meshSession(peer: peer, audioPublishingAllowed: false);

        await media.connect();

        expect(peer.mediaPlan, [
          'transceiver:audio',
          'transceiver:video',
          'transceiver:audio',
        ]);
        expect(
          peer.createdTransceivers.map((value) => value.direction),
          everyElement(rtc.TransceiverDirection.RecvOnly),
        );
        expect(peer.addedTracks, isEmpty);
        await media.dispose();
      },
    );

    test('disposal continues when a peer rejects close', () async {
      final microphone = _FakeTrack('microphone', 'audio');
      final stream = _FakeStream('microphone-stream', [microphone]);
      final peer = _FakePeerConnection(failClose: true);
      final media = _meshSession(
        peer: peer,
        audioPublishingAllowed: true,
        getUserMedia: (_) async => stream,
      );

      await media.connect();
      await media.dispose();
      await media.dispose();

      expect(microphone.stopped, isTrue);
      expect(stream.disposed, isTrue);
    });

    test(
      'stage listeners connect only to participants who can speak',
      () async {
        final peer = _FakePeerConnection();
        var peerCreations = 0;
        final media = MeshVoiceMediaSession(
          join: _meshJoin(
            localUserId: 10,
            remoteUserId: 20,
            roomType: VoiceRoomType.stage,
          ),
          localUserId: 10,
          sendSignal: (_, _) async {},
          audioPublishingAllowed: false,
          createPeerConnection: (_) async {
            peerCreations++;
            return peer;
          },
        );

        await media.connect();
        expect(peerCreations, 0);

        await media.syncParticipants(
          _meshJoin(
            localUserId: 10,
            remoteUserId: 20,
            roomType: VoiceRoomType.stage,
            remoteRole: VoiceRole.speaker,
          ).room.participants,
        );
        expect(peerCreations, 1);

        await media.syncParticipants(
          _meshJoin(
            localUserId: 10,
            remoteUserId: 20,
            roomType: VoiceRoomType.stage,
          ).room.participants,
        );
        expect(peer.closed, isTrue);
        await media.dispose();
      },
    );

    test('a microphone device change reuses its negotiated sender', () async {
      final events = <String>[];
      final oldTrack = _FakeTrack('old-mic', 'audio', events);
      final newTrack = _FakeTrack('new-mic', 'audio', events);
      final streams = <_FakeStream>[
        _FakeStream('old-stream', [oldTrack]),
        _FakeStream('new-stream', [newTrack]),
      ];
      final peer = _FakePeerConnection(events: events);
      final media = _meshSession(
        peer: peer,
        audioPublishingAllowed: true,
        getUserMedia: (_) async => streams.removeAt(0),
      );

      await media.connect();
      final microphoneSender = peer.addedTrackSenders.single;
      await media.selectAudioInput('replacement');

      expect(peer.addedTracks, [oldTrack]);
      expect(microphoneSender.track, same(newTrack));
      expect(oldTrack.stopped, isTrue);
      expect(
        events.indexOf('replace:microphone:new-mic'),
        lessThan(events.indexOf('stop:old-mic')),
      );
      await media.dispose();
    });

    test(
      'stage promotion rebuilds the peer with a stream-associated mic',
      () async {
        final firstPeer = _FakePeerConnection();
        final promotedPeer = _FakePeerConnection();
        final peers = <_FakePeerConnection>[firstPeer, promotedPeer];
        final microphone = _FakeTrack('promoted-mic', 'audio');
        final media = MeshVoiceMediaSession(
          join: _meshJoin(localUserId: 10, remoteUserId: 20),
          localUserId: 10,
          sendSignal: (_, _) async {},
          audioPublishingAllowed: false,
          createPeerConnection: (_) async => peers.removeAt(0),
          getUserMedia: (_) async =>
              _FakeStream('promoted-stream', [microphone]),
        );

        await media.connect();
        await media.setAudioPublishingAllowed(true);

        expect(firstPeer.addedTracks, isEmpty);
        expect(promotedPeer.addedTracks, [microphone]);
        expect(promotedPeer.mediaPlan, [
          'track:audio',
          'transceiver:video',
          'transceiver:audio',
        ]);
        await media.dispose();
      },
    );

    test('failed stage promotion restores a receive-only peer', () async {
      final firstPeer = _FakePeerConnection();
      final restoredPeer = _FakePeerConnection();
      final microphone = _FakeTrack('promoted-mic', 'audio');
      var creations = 0;
      final media = MeshVoiceMediaSession(
        join: _meshJoin(localUserId: 10, remoteUserId: 20),
        localUserId: 10,
        sendSignal: (_, _) async {},
        audioPublishingAllowed: false,
        createPeerConnection: (_) async => switch (creations++) {
          0 => firstPeer,
          1 => throw StateError('peer rebuild failed'),
          _ => restoredPeer,
        },
        getUserMedia: (_) async => _FakeStream('promoted-stream', [microphone]),
      );

      await media.connect();
      await expectLater(
        media.setAudioPublishingAllowed(true),
        throwsStateError,
      );

      expect(media.audioPublishingAllowed, isFalse);
      expect(microphone.stopped, isTrue);
      expect(restoredPeer.addedTracks, isEmpty);
      await media.dispose();
    });

    test('failed stage demotion restores a stream-associated mic', () async {
      final firstPeer = _FakePeerConnection();
      final restoredPeer = _FakePeerConnection();
      final original = _FakeTrack('original-mic', 'audio');
      final replacement = _FakeTrack('restored-mic', 'audio');
      final captures = <_FakeStream>[
        _FakeStream('original-stream', [original]),
        _FakeStream('restored-stream', [replacement]),
      ];
      var creations = 0;
      final media = MeshVoiceMediaSession(
        join: _meshJoin(localUserId: 10, remoteUserId: 20),
        localUserId: 10,
        sendSignal: (_, _) async {},
        audioPublishingAllowed: true,
        createPeerConnection: (_) async => switch (creations++) {
          0 => firstPeer,
          1 => throw StateError('peer rebuild failed'),
          _ => restoredPeer,
        },
        getUserMedia: (_) async => captures.removeAt(0),
      );

      await media.connect();
      await expectLater(
        media.setAudioPublishingAllowed(false),
        throwsStateError,
      );

      expect(media.audioPublishingAllowed, isTrue);
      expect(original.stopped, isTrue);
      expect(replacement.stopped, isFalse);
      expect(restoredPeer.addedTracks, [replacement]);
      await media.dispose();
    });

    test(
      'camera and screen share keep independent negotiated sources',
      () async {
        final microphone = _FakeTrack('mic', 'audio');
        final camera = _FakeTrack('camera', 'video');
        final screenVideo = _FakeTrack('screen-video', 'video');
        final screenAudio = _FakeTrack('screen-audio', 'audio');
        final captures = <_FakeStream>[
          _FakeStream('microphone-stream', [microphone]),
          _FakeStream('camera-stream', [camera]),
        ];
        final screen = _FakeStream('screen-stream', [screenVideo, screenAudio]);
        final peer = _FakePeerConnection();
        final media = _meshSession(
          peer: peer,
          audioPublishingAllowed: true,
          getUserMedia: (_) async => captures.removeAt(0),
          getDisplayMedia: (_) async => screen,
        );

        await media.connect();
        final microphoneSender = peer.addedTrackSenders.single;
        final videoSender = peer.createdTransceivers[0].sender;
        final screenAudioSender = peer.createdTransceivers[1].sender;

        await media.setCameraEnabled(true);
        expect(videoSender.track, same(camera));
        await media.setScreenShareEnabled(true);
        expect(videoSender.track, same(screenVideo));
        expect(screenAudioSender.track, same(screenAudio));
        expect(microphoneSender.track, same(microphone));

        await media.setScreenShareEnabled(false);
        expect(videoSender.track, same(camera));
        expect(screenAudioSender.track, isNull);
        expect(microphoneSender.track, same(microphone));
        await media.dispose();
      },
    );

    test('a system-ended screen share restores the camera', () async {
      final camera = _FakeTrack('camera', 'video');
      final screenVideo = _FakeTrack('screen-video', 'video');
      final screenAudio = _FakeTrack('screen-audio', 'audio');
      final screen = _FakeStream('screen-stream', [screenVideo, screenAudio]);
      final peer = _FakePeerConnection();
      final media = _meshSession(
        peer: peer,
        audioPublishingAllowed: false,
        getUserMedia: (_) async => _FakeStream('camera-stream', [camera]),
        getDisplayMedia: (_) async => screen,
      );

      await media.connect();
      final videoSender = peer.createdTransceivers
          .firstWhere((value) => value.receiver.track?.kind == 'video')
          .sender;
      await media.setCameraEnabled(true);
      await media.setScreenShareEnabled(true);
      expect(media.screenSharing, isTrue);

      screenVideo.onEnded?.call();
      await _pumpEventQueue();
      await _pumpEventQueue();

      expect(media.screenSharing, isFalse);
      expect(videoSender.track, same(camera));
      expect(screen.disposed, isTrue);
      await media.dispose();
    });

    test('retains a streamless remote video track until it ends', () async {
      final peer = _FakePeerConnection();
      final media = _meshSession(peer: peer, audioPublishingAllowed: false);
      await media.connect();
      final video = _FakeTrack('remote-video', 'video');

      peer.onTrack?.call(rtc.RTCTrackEvent(streams: const [], track: video));
      expect(media.videoTrackFor(20), same(video));

      video.onEnded?.call();
      expect(media.videoTrackFor(20), isNull);
      await media.dispose();
    });

    test('rejects media published by a stage listener', () async {
      final peer = _FakePeerConnection();
      final response = _meshJoin(
        localUserId: 10,
        remoteUserId: 20,
        roomType: VoiceRoomType.stage,
        localRole: VoiceRole.speaker,
      );
      final media = MeshVoiceMediaSession(
        join: response,
        localUserId: 10,
        sendSignal: (_, _) async {},
        audioPublishingAllowed: true,
        createPeerConnection: (_) async => peer,
        getUserMedia: (_) async =>
            _FakeStream('local-stream', [_FakeTrack('local-mic', 'audio')]),
      );
      await media.connect();
      final track = _FakeTrack('untrusted-listener-mic', 'audio');

      peer.onTrack?.call(
        rtc.RTCTrackEvent(
          streams: [
            _FakeStream('untrusted-stream', [track]),
          ],
          track: track,
        ),
      );
      await _pumpEventQueue();

      expect(track.stopped, isTrue);
      await media.dispose();
    });

    test('rejects video and screen audio when video is disabled', () async {
      final peer = _FakePeerConnection();
      final response = _meshJoin(
        localUserId: 10,
        remoteUserId: 20,
        videoAllowed: false,
      );
      final media = MeshVoiceMediaSession(
        join: response,
        localUserId: 10,
        sendSignal: (_, _) async {},
        audioPublishingAllowed: true,
        createPeerConnection: (_) async => peer,
        getUserMedia: (_) async =>
            _FakeStream('local-stream', [_FakeTrack('local-mic', 'audio')]),
      );
      await media.connect();
      final video = _FakeTrack('untrusted-video', 'video');
      final screenAudio = _FakeTrack('untrusted-screen-audio', 'audio');

      peer.onTrack?.call(rtc.RTCTrackEvent(streams: const [], track: video));
      peer.onTrack?.call(
        rtc.RTCTrackEvent(streams: const [], track: screenAudio),
      );
      await _pumpEventQueue();

      expect(video.stopped, isTrue);
      expect(screenAudio.stopped, isTrue);
      expect(media.videoTrackFor(20), isNull);
      await media.dispose();
    });

    test('stops already received media after a stage demotion', () async {
      final firstPeer = _FakePeerConnection();
      final rebuiltPeer = _FakePeerConnection();
      final peers = [firstPeer, rebuiltPeer];
      final response = _meshJoin(
        localUserId: 10,
        remoteUserId: 20,
        roomType: VoiceRoomType.stage,
        localRole: VoiceRole.speaker,
        remoteRole: VoiceRole.speaker,
      );
      final media = MeshVoiceMediaSession(
        join: response,
        localUserId: 10,
        sendSignal: (_, _) async {},
        audioPublishingAllowed: true,
        createPeerConnection: (_) async => peers.removeAt(0),
        getUserMedia: (_) async =>
            _FakeStream('local-stream', [_FakeTrack('local-mic', 'audio')]),
      );
      await media.connect();
      final remoteVideo = _FakeTrack('speaker-video', 'video');
      firstPeer.onTrack?.call(
        rtc.RTCTrackEvent(streams: const [], track: remoteVideo),
      );
      expect(media.videoTrackFor(20), same(remoteVideo));

      await media.syncParticipants([
        response.room.participants.first,
        const VoiceParticipant(
          id: 20,
          username: 'remote',
          role: VoiceRole.participant,
        ),
      ]);

      expect(remoteVideo.stopped, isTrue);
      expect(media.videoTrackFor(20), isNull);
      await media.dispose();
    });

    test(
      'ignores signals from self and participants outside the roster',
      () async {
        final peer = _FakePeerConnection();
        var peerCreations = 0;
        final response = _meshJoin(localUserId: 10, remoteUserId: 20);
        final media = MeshVoiceMediaSession(
          join: response,
          localUserId: 10,
          sendSignal: (_, _) async {},
          audioPublishingAllowed: false,
          createPeerConnection: (_) async {
            peerCreations++;
            return peer;
          },
        );
        await media.connect();
        expect(peerCreations, 1);

        await media.syncParticipants([
          response.room.participants.firstWhere(
            (participant) => participant.id == 10,
          ),
        ]);
        expect(peer.closed, isTrue);

        for (final senderId in [10, 20, 99]) {
          await expectLater(
            media.handleSignal(senderId, {
              'type': 'offer',
              'sdp': 'untrusted-offer',
            }),
            completes,
            reason: '$senderId',
          );
        }

        expect(peerCreations, 1);
        await media.dispose();
      },
    );

    test('drops oversized SDP and candidate fields without throwing', () async {
      final peer = _FakePeerConnection();
      final media = _meshSession(
        peer: peer,
        localUserId: 20,
        remoteUserId: 10,
        audioPublishingAllowed: false,
      );
      await media.connect();

      await expectLater(
        media.handleSignal(10, {
          'type': 'offer',
          'sdp': List.filled(300 * 1024, 's').join(),
        }),
        completes,
      );
      for (final candidate in [
        {
          'candidate': List.filled(9 * 1024, 'c').join(),
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
        {
          'candidate': 'candidate:valid-sized',
          'sdpMid': List.filled(300, 'm').join(),
          'sdpMLineIndex': 0,
        },
        {'candidate': 12, 'sdpMid': '0', 'sdpMLineIndex': double.nan},
      ]) {
        await expectLater(
          media.handleSignal(10, {'type': 'candidate', 'candidate': candidate}),
          completes,
        );
      }

      expect(await peer.getRemoteDescription(), isNull);
      expect(peer.createdAnswers, 0);
      await media.handleSignal(10, {'type': 'offer', 'sdp': 'valid-offer'});
      expect(peer.addedCandidates, isEmpty);
      await media.dispose();
    });

    test('caps candidates queued before a remote description', () async {
      const pendingCandidateCap = 64;
      final peer = _FakePeerConnection();
      final media = _meshSession(
        peer: peer,
        localUserId: 20,
        remoteUserId: 10,
        audioPublishingAllowed: false,
      );
      await media.connect();

      for (var index = 0; index < pendingCandidateCap + 20; index++) {
        await media.handleSignal(10, {
          'type': 'candidate',
          'candidate': {
            'candidate': 'candidate:$index',
            'sdpMid': '0',
            'sdpMLineIndex': 0,
          },
        });
      }
      await media.handleSignal(10, {'type': 'offer', 'sdp': 'valid-offer'});

      expect(peer.addedCandidates, hasLength(pendingCandidateCap));
      expect(peer.addedCandidates.first.candidate, 'candidate:0');
      expect(
        peer.addedCandidates.last.candidate,
        'candidate:${pendingCandidateCap - 1}',
      );
      await media.dispose();
    });

    test('accepts string SDP m-line indexes from remote candidates', () async {
      final peer = _FakePeerConnection();
      final media = _meshSession(
        peer: peer,
        localUserId: 20,
        remoteUserId: 10,
        audioPublishingAllowed: false,
      );
      await media.connect();
      await media.handleSignal(10, {'type': 'offer', 'sdp': 'remote-offer'});

      await media.handleSignal(10, {
        'type': 'candidate',
        'candidate': {
          'candidate':
              'candidate:1 1 UDP 2122260223 2001:db8::1 54321 typ host',
          'sdpMid': '0',
          'sdpMLineIndex': '0',
        },
      });

      expect(peer.addedCandidates, hasLength(1));
      expect(peer.addedCandidates.single.sdpMLineIndex, 0);

      await media.handleSignal(10, {
        'type': 'candidate',
        'candidate': {'candidate': '', 'sdpMid': '0', 'sdpMLineIndex': '0'},
      });

      expect(peer.addedCandidates, hasLength(1));
      await media.dispose();
    });

    test('adopts offered source slots before creating an answer', () async {
      final microphone = _FakeTrack('mic', 'audio');
      final peer = _FakePeerConnection();
      final media = _meshSession(
        peer: peer,
        localUserId: 20,
        remoteUserId: 10,
        audioPublishingAllowed: true,
        getUserMedia: (_) async =>
            _FakeStream('microphone-stream', [microphone]),
      );
      await media.connect();
      final orphanMicrophone = peer.addedTrackSenders.single;
      final associated = peer.prepareAssociatedTransceivers();

      await media.handleSignal(10, {'type': 'offer', 'sdp': 'remote-offer'});

      expect(associated[0].sender.track, same(microphone));
      expect(associated[0].sender.streams, hasLength(1));
      expect(orphanMicrophone.track, isNull);
      expect(
        associated.map((value) => value.direction),
        everyElement(rtc.TransceiverDirection.SendRecv),
      );
      expect(peer.createdAnswers, 1);
      await media.dispose();
    });

    test(
      'keeps answer transceivers receive-only for stage listeners',
      () async {
        final peer = _FakePeerConnection();
        final response = _meshJoin(
          localUserId: 20,
          remoteUserId: 10,
          roomType: VoiceRoomType.stage,
          remoteRole: VoiceRole.speaker,
        );
        final media = MeshVoiceMediaSession(
          join: response,
          localUserId: 20,
          sendSignal: (_, _) async {},
          audioPublishingAllowed: false,
          createPeerConnection: (_) async => peer,
        );
        await media.connect();
        final associated = peer.prepareAssociatedTransceivers();

        await media.handleSignal(10, {'type': 'offer', 'sdp': 'remote-offer'});

        expect(
          associated.map((value) => value.direction),
          everyElement(rtc.TransceiverDirection.RecvOnly),
        );
        await media.dispose();
      },
    );

    test(
      'accepts a first offer before the cached signaling state is set',
      () async {
        final peer = _FakePeerConnection(exposeNullCachedSignalingState: true);
        final media = _meshSession(
          peer: peer,
          localUserId: 20,
          remoteUserId: 10,
          audioPublishingAllowed: false,
        );
        await media.connect();

        await media.handleSignal(10, {
          'type': 'offer',
          'sdp': 'first-remote-offer',
        });

        expect(peer.createdAnswers, 1);
        await media.dispose();
      },
    );

    test(
      'the peer with the lower ID keeps its offer during a collision',
      () async {
        final peer = _FakePeerConnection();
        final media = _meshSession(peer: peer, audioPublishingAllowed: false);
        await media.connect();
        peer.prepareAssociatedTransceivers();

        await media.handleSignal(20, {
          'type': 'offer',
          'sdp': 'fallback-offer',
        });

        expect(peer.rollbackCount, 0);
        expect(peer.createdAnswers, 0);
        expect((await peer.getLocalDescription())?.type, 'offer');
        expect(await peer.getRemoteDescription(), isNull);
        await media.dispose();
      },
    );

    test('ignores an answer when no local offer is outstanding', () async {
      final peer = _FakePeerConnection();
      final media = _meshSession(
        peer: peer,
        localUserId: 20,
        remoteUserId: 10,
        audioPublishingAllowed: false,
      );
      await media.connect();

      await media.handleSignal(10, {'type': 'answer', 'sdp': 'stale-answer'});

      expect(await peer.getRemoteDescription(), isNull);
      await media.dispose();
    });

    test('records correlated peer, signaling, ICE, and track events', () async {
      final diagnostics = _DiagnosticsRecorder()..captureEnabled = true;
      final peer = _FakePeerConnection();
      final media = _meshSession(
        peer: peer,
        audioPublishingAllowed: false,
        diagnostics: diagnostics,
        correlationId: 'call-42',
      );
      await media.connect();

      peer.onConnectionState?.call(
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      );
      peer.onIceConnectionState?.call(
        rtc.RTCIceConnectionState.RTCIceConnectionStateChecking,
      );
      peer.onSignalingState?.call(
        rtc.RTCSignalingState.RTCSignalingStateHaveLocalOffer,
      );
      peer.onIceCandidate?.call(rtc.RTCIceCandidate('candidate:raw', '0', 0));
      final track = _FakeTrack('remote-video', 'video');
      peer.onTrack?.call(rtc.RTCTrackEvent(streams: const [], track: track));
      await media.handleSignal(20, {
        'type': 'candidate',
        'candidate': {
          'candidate': 'candidate:remote',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      });

      expect(
        diagnostics.records.map((record) => record.event),
        containsAll({
          'mesh.peer.create.completed',
          'mesh.peer.connection_state',
          'mesh.peer.ice_connection_state',
          'mesh.peer.signaling_state',
          'mesh.signaling.received',
          'mesh.ice.candidate.queued',
        }),
      );
      expect(
        diagnostics.rawRecords.map((record) => record.event),
        containsAll({
          'mesh.ice.candidate.local',
          'mesh.track.received',
          'mesh.signaling.received.raw',
        }),
      );
      expect(
        diagnostics.records.every(
          (record) => record.correlationId == 'call-42',
        ),
        isTrue,
      );
      await media.dispose();
    });

    test(
      'keeps stable media identities out of capture-off diagnostics',
      () async {
        const localUserId = 731946201;
        const remoteUserId = 731946202;
        const localUsername = 'privacy-local-alice';
        const remoteUsername = 'privacy-remote-bob';
        const deviceId = 'privacy-device-7e65';
        const groupId = 'privacy-group-8f76';
        const trackId = 'privacy-track-9a87';
        const streamId = 'privacy-stream-ab98';
        const candidateIp = '203.0.113.77';
        final diagnostics = _DiagnosticsRecorder();
        final peer = _FakePeerConnection();
        final media = _meshSession(
          peer: peer,
          audioPublishingAllowed: false,
          localUserId: localUserId,
          remoteUserId: remoteUserId,
          localUsername: localUsername,
          remoteUsername: remoteUsername,
          diagnostics: diagnostics,
          correlationId: 'privacy-call',
          enumerateDevices: () async => [
            rtc.MediaDeviceInfo(
              deviceId: deviceId,
              groupId: groupId,
              kind: 'videoinput',
              label: 'Privacy sentinel camera',
            ),
          ],
        );
        await media.connect();

        peer.onConnectionState?.call(
          rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected,
        );
        peer.onIceCandidate?.call(
          rtc.RTCIceCandidate(
            'candidate:1 1 udp 2122260223 $candidateIp 54321 typ host',
            '0',
            0,
          ),
        );
        final track = _FakeTrack(trackId, 'video');
        final stream = _FakeStream(streamId, [track]);
        peer.onTrack?.call(rtc.RTCTrackEvent(streams: [stream], track: track));
        await media.handleSignal(remoteUserId, {
          'type': 'candidate',
          'candidate': {
            'candidate':
                'candidate:2 1 udp 2122260223 $candidateIp 54322 typ host',
            'sdpMid': '0',
            'sdpMLineIndex': 0,
          },
        });
        await media.handleSignal(remoteUserId, {
          'type': 'untrusted-$candidateIp-$trackId',
        });
        track.onEnded?.call();
        await media.devices();

        final ordinaryExport = jsonEncode([
          for (final record in diagnostics.records)
            {
              'event': record.event,
              'component': record.component,
              'correlationId': record.correlationId,
              'data': record.data,
            },
        ]);
        for (final sentinel in [
          '$localUserId',
          '$remoteUserId',
          localUsername,
          remoteUsername,
          deviceId,
          groupId,
          trackId,
          streamId,
          candidateIp,
        ]) {
          expect(ordinaryExport, isNot(contains(sentinel)));
        }
        for (final rawIdentityKey in [
          'peerId',
          'localUserId',
          'participantSid',
          'participantIdentity',
          'participantName',
          'trackId',
          'trackSid',
          'streamIds',
          'deviceId',
          'groupId',
        ]) {
          expect(ordinaryExport, isNot(contains('"$rawIdentityKey"')));
        }
        expect(ordinaryExport, contains('peer-1'));
        expect(ordinaryExport, contains('track-1'));
        expect(diagnostics.rawRecords, isEmpty);
        await media.dispose();
      },
    );

    test(
      'contains candidate batch timer failures at the terminal boundary',
      () async {
        const privateCause =
            'candidate-private-user device-private 203.0.113.120';
        final uncaught = <Object>[];
        final timers = <_ManualTimer>[];
        final sendAttempted = Completer<void>();
        final diagnostics = _DiagnosticsRecorder();
        final peer = _FakePeerConnection();
        final media = _meshSession(
          peer: peer,
          localUserId: 20,
          remoteUserId: 10,
          audioPublishingAllowed: false,
          diagnostics: diagnostics,
          correlationId: 'candidate-failure-call',
          sendSignal: (_, _) async {
            if (!sendAttempted.isCompleted) sendAttempted.complete();
            throw StateError(privateCause);
          },
        );
        await media.connect();

        runZonedGuarded<void>(
          () {
            peer.onIceCandidate?.call(
              rtc.RTCIceCandidate(
                'candidate:1 1 udp 2122260223 203.0.113.120 54321 typ host',
                '0',
                0,
              ),
            );
            expect(timers.single.delay, const Duration(milliseconds: 30));
            timers.single.fire();
          },
          (error, _) => uncaught.add(error),
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) {
              final timer = _ManualTimer(
                duration,
                () => zone.runGuarded(callback),
              );
              timers.add(timer);
              return timer;
            },
          ),
        );
        expect(sendAttempted.isCompleted, isTrue);
        await _pumpEventQueue();

        expect(uncaught, isEmpty);
        final failure = diagnostics.records.singleWhere(
          (record) => record.event == 'mesh.signaling.send_failed',
        );
        expect(failure.data['peerAlias'], 'peer-1');
        expect(failure.data['errorType'], 'StateError');
        final ordinaryExport = jsonEncode([
          for (final record in diagnostics.records)
            {'event': record.event, 'data': record.data},
        ]);
        expect(ordinaryExport, isNot(contains(privateCause)));
        expect(diagnostics.rawRecords, isEmpty);
        await media.dispose();
      },
    );

    test(
      'contains detached remote volume failures without exposing raw cause',
      () async {
        const privateCause = 'volume-private-user track-private 203.0.113.121';
        final uncaught = <Object>[];
        final diagnostics = _DiagnosticsRecorder();
        final peer = _FakePeerConnection();
        final media = _meshSession(
          peer: peer,
          audioPublishingAllowed: false,
          diagnostics: diagnostics,
          correlationId: 'volume-failure-call',
          setTrackVolume: (_, _) async => throw StateError(privateCause),
        );
        await media.connect();

        final operation = runZonedGuarded<Future<void>>(() async {
          final track = _FakeTrack('track-private', 'audio');
          final stream = _FakeStream('stream-private', [track]);
          peer.onTrack?.call(
            rtc.RTCTrackEvent(streams: [stream], track: track),
          );
          await _pumpEventQueue();
        }, (error, _) => uncaught.add(error));
        await operation;

        expect(uncaught, isEmpty);
        final failure = diagnostics.records.singleWhere(
          (record) => record.event == 'mesh.track.volume_failed',
        );
        expect(failure.data['peerAlias'], 'peer-1');
        expect(failure.data['trackAlias'], 'track-1');
        expect(failure.data['errorType'], 'StateError');
        final ordinaryExport = jsonEncode([
          for (final record in diagnostics.records)
            {'event': record.event, 'data': record.data},
        ]);
        expect(ordinaryExport, isNot(contains(privateCause)));
        expect(ordinaryExport, isNot(contains('track-private')));
        expect(diagnostics.rawRecords, isEmpty);
        await media.dispose();
      },
    );

    test(
      'reports speakers from inbound and local media-source levels',
      () async {
        final timers = <_ManualPeriodicTimer>[];
        final peer = _FakePeerConnection();
        final media = _meshSession(peer: peer, audioPublishingAllowed: false);
        final changes = <Set<int>>[];
        media.addListener(() => changes.add(media.speakingParticipantIds));

        await runZoned(
          () async {
            await media.connect();
            final speakingTimer = timers.singleWhere(
              (timer) => timer.delay == const Duration(milliseconds: 250),
            );

            peer.stats = [
              rtc.StatsReport('in-1', 'inbound-rtp', 1, {
                'kind': 'audio',
                'audioLevel': 0.4,
              }),
              rtc.StatsReport('src-1', 'media-source', 1, {
                'kind': 'audio',
                'audioLevel': 0.2,
              }),
              rtc.StatsReport('src-2', 'media-source', 1, {
                'kind': 'video',
                'audioLevel': 0.9,
              }),
            ];
            speakingTimer.fire();
            await _pumpEventQueue();
            expect(media.speakingParticipantIds, {20, 10});

            peer.stats = [
              rtc.StatsReport('in-1', 'inbound-rtp', 2, {
                'kind': 'audio',
                'audioLevel': 0.005,
              }),
              rtc.StatsReport('src-1', 'media-source', 2, {
                'mediaType': 'audio',
                'audioLevel': 0.3,
              }),
            ];
            speakingTimer.fire();
            await _pumpEventQueue();
            expect(media.speakingParticipantIds, {10});

            await media.setMuted(true);
            speakingTimer.fire();
            await _pumpEventQueue();
            expect(media.speakingParticipantIds, isEmpty);
            expect(changes, [
              {20, 10},
              {10},
              <int>{},
            ]);
            await media.dispose();
          },
          zoneSpecification: ZoneSpecification(
            createPeriodicTimer: (self, parent, zone, duration, callback) {
              final timer = _ManualPeriodicTimer(
                duration,
                (timer) => zone.runUnaryGuarded(callback, timer),
              );
              timers.add(timer);
              return timer;
            },
          ),
        );
      },
    );

    test('samples raw peer stats only while capture is enabled', () async {
      final diagnostics = _DiagnosticsRecorder();
      final timers = <_ManualPeriodicTimer>[];
      final peer = _FakePeerConnection();
      final media = _meshSession(
        peer: peer,
        audioPublishingAllowed: false,
        diagnostics: diagnostics,
        correlationId: 'stats-call',
        rawStatsInterval: const Duration(milliseconds: 5),
        enumerateDevices: () async => const [],
      );

      await runZoned(
        () async {
          await media.connect();

          final statsTimer = timers.singleWhere(
            (timer) => timer.delay == const Duration(milliseconds: 5),
          );
          statsTimer.fire();
          await _pumpEventQueue();
          expect(
            diagnostics.rawRecords.where(
              (record) => record.event == 'mesh.peer.stats',
            ),
            isEmpty,
          );

          diagnostics.captureEnabled = true;
          statsTimer.fire();
          await _pumpEventQueue();
          final stats = diagnostics.rawRecords.where(
            (record) => record.event == 'mesh.peer.stats',
          );
          expect(stats, isNotEmpty);
          expect(
            stats.every((record) => record.correlationId == 'stats-call'),
            true,
          );
          await media.dispose();
        },
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, duration, callback) {
            final timer = _ManualPeriodicTimer(
              duration,
              (timer) => zone.runUnaryGuarded(callback, timer),
            );
            timers.add(timer);
            return timer;
          },
        ),
      );
    });

    test('records full device inventory only during deep capture', () async {
      final diagnostics = _DiagnosticsRecorder();
      final devices = [
        rtc.MediaDeviceInfo(
          deviceId: 'microphone-1',
          groupId: 'headset-1',
          kind: 'audioinput',
          label: 'USB headset microphone',
        ),
        rtc.MediaDeviceInfo(
          deviceId: 'camera-1',
          groupId: 'camera-group-1',
          kind: 'videoinput',
          label: 'External camera',
        ),
      ];
      final media = _meshSession(
        peer: _FakePeerConnection(),
        audioPublishingAllowed: false,
        diagnostics: diagnostics,
        correlationId: 'device-call',
        enumerateDevices: () async => devices,
      );

      expect(await media.devices(), devices);
      expect(diagnostics.rawRecords, isEmpty);

      diagnostics.captureEnabled = true;
      expect(await media.devices(), devices);
      final inventory = diagnostics.rawRecords.single;
      expect(inventory.event, 'media.devices.enumerated');
      expect(inventory.correlationId, 'device-call');
      expect(inventory.data['count'], 2);
      final recordedDevices = inventory.data['devices'] as List<Object?>;
      expect(
        recordedDevices.first,
        containsPair('label', 'USB headset microphone'),
      );
      expect(recordedDevices.first, containsPair('deviceId', 'microphone-1'));
      expect(recordedDevices.last, containsPair('kind', 'videoinput'));
      await media.dispose();
    });
  });

  test('a mute during connect is not overwritten by the connect', () async {
    final meshJoin = _meshJoin(localUserId: 10, remoteUserId: 20);
    final media = LiveKitVoiceMediaSession(
      join: VoiceJoinResponse(
        transport: VoiceTransport.livekit,
        ice: meshJoin.ice,
        room: meshJoin.room,
        livekit: const VoiceLiveKitCredentials(
          url: 'wss://livekit.invalid',
          token: 'not-used',
        ),
      ),
      localUserId: 10,
      audioPublishingAllowed: true,
      refreshCredentials: () async =>
          const VoiceLiveKitCredentials(url: '', token: ''),
      correlationId: 'livekit-call',
    );

    expect(media.shouldPublishMicrophone, isTrue);

    await media.setMuted(true);

    expect(media.shouldPublishMicrophone, isFalse);

    await media.setAudioPublishingAllowed(true);
    expect(media.shouldPublishMicrophone, isFalse);

    await media.setMuted(false);
    expect(media.shouldPublishMicrophone, isTrue);
    await media.dispose();
  });

  test('deafening is remembered, not applied once', () async {
    final meshJoin = _meshJoin(localUserId: 10, remoteUserId: 20);
    final media = LiveKitVoiceMediaSession(
      join: VoiceJoinResponse(
        transport: VoiceTransport.livekit,
        ice: meshJoin.ice,
        room: meshJoin.room,
        livekit: const VoiceLiveKitCredentials(
          url: 'wss://livekit.invalid',
          token: 'not-used',
        ),
      ),
      localUserId: 10,
      audioPublishingAllowed: true,
      refreshCredentials: () async =>
          const VoiceLiveKitCredentials(url: '', token: ''),
      correlationId: 'livekit-call',
    );

    expect(media.deafened, isFalse);

    await media.setDeafened(true);
    expect(media.deafened, isTrue);

    await media.setDeafened(false);
    expect(media.deafened, isFalse);

    expect(media.cameraEnabled, isFalse);
    await media.setCameraEnabled(true);
    expect(media.cameraEnabled, isTrue);
    await media.setCameraEnabled(false);
    expect(media.cameraEnabled, isFalse);
    await media.dispose();
  });

  test('records typed LiveKit room and reconnect events', () {
    final diagnostics = _DiagnosticsRecorder()..captureEnabled = true;
    final meshJoin = _meshJoin(localUserId: 10, remoteUserId: 20);
    final media = LiveKitVoiceMediaSession(
      join: VoiceJoinResponse(
        transport: VoiceTransport.livekit,
        ice: meshJoin.ice,
        room: meshJoin.room,
        livekit: const VoiceLiveKitCredentials(
          url: 'wss://livekit.invalid',
          token: 'not-used',
        ),
      ),
      localUserId: 10,
      audioPublishingAllowed: true,
      refreshCredentials: () async =>
          const VoiceLiveKitCredentials(url: '', token: ''),
      diagnostics: diagnostics,
      correlationId: 'livekit-call',
    );

    media.recordRoomEventForTesting(
      lk.RoomDisconnectedEvent(
        reason: lk.DisconnectReason.signalingConnectionFailure,
      ),
    );
    media.recordRoomEventForTesting(
      const lk.RoomAttemptReconnectEvent(
        attempt: 2,
        maxAttemptsRetry: 5,
        nextRetryDelaysInMs: 1000,
      ),
    );
    media.recordRoomEventForTesting(const lk.RoomReconnectedEvent());

    expect(diagnostics.records.map((record) => record.event), [
      'livekit.room.disconnected',
      'livekit.room.reconnect_attempt',
      'livekit.room.reconnected',
    ]);
    expect(
      diagnostics.records.every(
        (record) => record.correlationId == 'livekit-call',
      ),
      isTrue,
    );
    expect(
      diagnostics.records.first.data['reason'],
      'signalingConnectionFailure',
    );
    expect(media.rawStatsInterval, const Duration(seconds: 5));
  });

  test(
    'does not forward a reconnect cause through capture-off Flutter errors',
    () async {
      const privateCause =
          'participant-alice device-private 203.0.113.88 track-private';
      final diagnostics = _DiagnosticsRecorder();
      final meshJoin = _meshJoin(localUserId: 10, remoteUserId: 20);
      final media = LiveKitVoiceMediaSession(
        join: VoiceJoinResponse(
          transport: VoiceTransport.livekit,
          ice: meshJoin.ice,
          room: meshJoin.room,
          livekit: const VoiceLiveKitCredentials(
            url: 'wss://livekit.invalid',
            token: 'not-used',
          ),
        ),
        localUserId: 10,
        audioPublishingAllowed: true,
        refreshCredentials: () async =>
            const VoiceLiveKitCredentials(url: '', token: ''),
        diagnostics: diagnostics,
        correlationId: 'livekit-private-failure',
      );
      addTearDown(media.dispose);
      final reported = <FlutterErrorDetails>[];
      final previousHandler = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousHandler);

      media.reportUnexpectedReconnectFailureForTesting(
        StateError(privateCause),
        StackTrace.current,
      );

      expect(reported, hasLength(1));
      expect(
        reported.single.exception.toString(),
        contains('livekit.reconnect'),
      );
      expect(
        reported.single.exception.toString(),
        isNot(contains(privateCause)),
      );
      final ordinaryExport = jsonEncode([
        for (final record in diagnostics.records)
          {'event': record.event, 'data': record.data},
      ]);
      expect(ordinaryExport, isNot(contains(privateCause)));
      expect(diagnostics.rawRecords, isEmpty);
    },
  );

  test('samples raw LiveKit track stats only during deep capture', () async {
    final diagnostics = _DiagnosticsRecorder();
    final timers = <_ManualPeriodicTimer>[];
    final meshJoin = _meshJoin(localUserId: 10, remoteUserId: 20);
    var collectionCount = 0;
    var enumerationCount = 0;
    final media = LiveKitVoiceMediaSession(
      join: VoiceJoinResponse(
        transport: VoiceTransport.livekit,
        ice: meshJoin.ice,
        room: meshJoin.room,
        livekit: const VoiceLiveKitCredentials(
          url: 'wss://livekit.invalid',
          token: 'not-used',
        ),
      ),
      localUserId: 10,
      audioPublishingAllowed: true,
      refreshCredentials: () async =>
          const VoiceLiveKitCredentials(url: '', token: ''),
      diagnostics: diagnostics,
      correlationId: 'livekit-stats-call',
      rawStatsInterval: const Duration(milliseconds: 5),
      enumerateDevices: () async {
        enumerationCount++;
        return [
          rtc.MediaDeviceInfo(
            deviceId: 'speaker-1',
            groupId: 'headset-1',
            kind: 'audiooutput',
            label: 'USB headset',
          ),
        ];
      },
      collectRawStats: (_) async {
        collectionCount++;
        return [
          {
            'participantIdentity': 'remote-user',
            'trackSid': 'track-1',
            'direction': 'receiver',
            'reports': [
              {
                'id': 'inbound-1',
                'type': 'inbound-rtp',
                'timestamp': 1234,
                'values': {'packetsLost': 2, 'jitter': 0.03},
              },
            ],
          },
        ];
      },
    );
    await runZoned(
      () async {
        media.startRawStatsTimerForTesting();

        final statsTimer = timers.singleWhere(
          (timer) => timer.delay == const Duration(milliseconds: 5),
        );
        statsTimer.fire();
        await _pumpEventQueue();
        expect(collectionCount, 0);
        expect(enumerationCount, 0);
        expect(diagnostics.rawRecords, isEmpty);

        diagnostics.captureEnabled = true;
        statsTimer.fire();
        await _pumpEventQueue();
        expect(collectionCount, 1);
        expect(enumerationCount, 1);
        expect(
          diagnostics.rawRecords.map((record) => record.event),
          containsAll({'media.devices.enumerated', 'livekit.track.stats'}),
        );
        final stats = diagnostics.rawRecords.firstWhere(
          (record) => record.event == 'livekit.track.stats',
        );
        expect(stats.correlationId, 'livekit-stats-call');
        expect(stats.data['participantIdentity'], 'remote-user');
        expect(stats.data['direction'], 'receiver');
        expect(stats.data['reports'], isNotEmpty);
        await media.dispose();
      },
      zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          final timer = _ManualPeriodicTimer(
            duration,
            (timer) => zone.runUnaryGuarded(callback, timer),
          );
          timers.add(timer);
          return timer;
        },
      ),
    );
  });

  group('LiveKitVoiceMediaSession', () {
    test(
      'coalesces repeated disposal and releases every owned resource',
      () async {
        final adapter = _FakeLiveKitRoomAdapter();
        final media = _liveKitSession(adapter);
        await media.connect();

        final first = media.dispose();
        final second = media.dispose();

        expect(identical(first, second), isTrue);
        await Future.wait([first, second]);
        expect(adapter.calls, [
          'listen',
          'connect',
          'cancel-listener',
          'disconnect',
          'dispose-room',
        ]);
        expect(adapter.endpoint, 'wss://localhost:3000');
        expect(adapter.token, 'local-test-token');
        expect(() => media.addListener(() {}), throwsFlutterError);
      },
    );

    for (final failingStage in [
      'cancel-listener',
      'disconnect',
      'dispose-room',
    ]) {
      test('continues cleanup when $failingStage throws', () async {
        final adapter = _FakeLiveKitRoomAdapter(failingStage: failingStage);
        final media = _liveKitSession(adapter);
        await media.connect();

        final first = media.dispose();
        final second = media.dispose();

        expect(identical(first, second), isTrue);
        await expectLater(
          first,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              '$failingStage failed',
            ),
          ),
        );
        await expectLater(second, throwsStateError);
        expect(adapter.calls, [
          'listen',
          'connect',
          'cancel-listener',
          'disconnect',
          'dispose-room',
        ]);
        expect(() => media.addListener(() {}), throwsFlutterError);
      });
    }

    test(
      'disconnect settles an in-flight connection before disposal',
      () async {
        final connection = Completer<void>();
        final adapter = _FakeLiveKitRoomAdapter(
          connection: connection,
          cancelConnectionOnDisconnect: true,
        );
        final media = _liveKitSession(adapter);
        final connecting = media.connect();
        final connectionResult = expectLater(connecting, throwsStateError);
        await adapter.connectStarted.future;

        await media.dispose();
        await connectionResult;

        expect(connection.isCompleted, isTrue);
        expect(adapter.calls, [
          'listen',
          'connect',
          'cancel-listener',
          'disconnect',
          'dispose-room',
        ]);
      },
    );

    test('disposal closes the connection boundary synchronously', () async {
      final adapter = _FakeLiveKitRoomAdapter();
      final media = _liveKitSession(adapter);

      final disposing = media.dispose();
      await media.connect();
      await disposing;

      expect(adapter.calls, ['cancel-listener', 'disconnect', 'dispose-room']);
    });
  });

  group('VoiceReconnectCoordinator', () {
    test('rejects an unusable retry schedule in release builds', () {
      VoiceReconnectCoordinator create(List<Duration> schedule) =>
          VoiceReconnectCoordinator(
            attempt: () async {},
            onStateChanged: (_) {},
            schedule: schedule,
          );

      expect(() => create(const []), throwsArgumentError);
      expect(
        () => create(const [Duration(milliseconds: -1)]),
        throwsArgumentError,
      );
    });

    test('retries on its schedule and reports recovery', () async {
      var attempts = 0;
      final states = <VoiceMediaConnectionState>[];
      final timers = <_ManualTimer>[];
      final coordinator = VoiceReconnectCoordinator(
        attempt: () async {
          attempts++;
          if (attempts == 1) throw StateError('expired token');
        },
        onStateChanged: states.add,
        schedule: const [Duration.zero, Duration(seconds: 3)],
        timerFactory: (delay, callback) {
          final timer = _ManualTimer(delay, callback);
          timers.add(timer);
          return timer;
        },
      );

      final reconnect = coordinator.reconnect();
      await _pumpEventQueue();

      expect(attempts, 1);
      expect(timers, hasLength(1));
      expect(timers.single.delay, const Duration(seconds: 3));
      expect(
        coordinator.connectionState,
        VoiceMediaConnectionState.reconnecting,
      );

      timers.single.fire();
      await reconnect;

      expect(attempts, 2);
      expect(coordinator.connectionState, VoiceMediaConnectionState.connected);
      expect(states, [
        VoiceMediaConnectionState.reconnecting,
        VoiceMediaConnectionState.connected,
      ]);
    });

    test('coalesces concurrent disconnect events into one attempt', () async {
      final attemptStarted = Completer<void>();
      final finishAttempt = Completer<void>();
      var attempts = 0;
      final coordinator = VoiceReconnectCoordinator(
        attempt: () async {
          attempts++;
          attemptStarted.complete();
          await finishAttempt.future;
        },
        onStateChanged: (_) {},
        schedule: const [Duration.zero],
      );

      final first = coordinator.reconnect();
      final second = coordinator.reconnect();
      expect(identical(first, second), isTrue);
      await attemptStarted.future;

      expect(attempts, 1);
      finishAttempt.complete();
      await Future.wait([first, second]);
      expect(coordinator.connectionState, VoiceMediaConnectionState.connected);
    });

    test('exhaustion becomes failed without leaking attempt errors', () async {
      var attempts = 0;
      final states = <VoiceMediaConnectionState>[];
      final coordinator = VoiceReconnectCoordinator(
        attempt: () async {
          attempts++;
          throw StateError('still offline');
        },
        onStateChanged: states.add,
        schedule: const [Duration.zero, Duration.zero, Duration.zero],
      );

      await coordinator.reconnect();

      expect(attempts, 3);
      expect(coordinator.connectionState, VoiceMediaConnectionState.failed);
      expect(states, [
        VoiceMediaConnectionState.reconnecting,
        VoiceMediaConnectionState.failed,
      ]);
    });

    test('reports retry attempt causes to diagnostic observers', () async {
      final started = <(int, Duration)>[];
      final failures = <(int, Object)>[];
      var exhausted = 0;
      final coordinator = VoiceReconnectCoordinator(
        attempt: () async => throw StateError('expired token'),
        onStateChanged: (_) {},
        onAttemptStarted: (attempt, delay) => started.add((attempt, delay)),
        onAttemptFailed: (attempt, error, _) => failures.add((attempt, error)),
        onExhausted: (attemptCount) => exhausted = attemptCount,
        schedule: const [Duration.zero],
      );

      await coordinator.reconnect();

      expect(started, [(1, Duration.zero)]);
      expect(failures.single.$1, 1);
      expect(failures.single.$2, isA<StateError>());
      expect(exhausted, 1);
    });

    test('cancel releases backoff and prevents later attempts', () async {
      var attempts = 0;
      final states = <VoiceMediaConnectionState>[];
      final timers = <_ManualTimer>[];
      final coordinator = VoiceReconnectCoordinator(
        attempt: () async {
          attempts++;
          throw StateError('offline');
        },
        onStateChanged: states.add,
        schedule: const [Duration.zero, Duration(seconds: 4)],
        timerFactory: (delay, callback) {
          final timer = _ManualTimer(delay, callback);
          timers.add(timer);
          return timer;
        },
      );

      final reconnect = coordinator.reconnect();
      await _pumpEventQueue();
      expect(timers, hasLength(1));

      coordinator.cancel();
      await reconnect;
      timers.single.fire();
      await coordinator.reconnect();

      expect(timers.single.isActive, isFalse);
      expect(attempts, 1);
      expect(
        coordinator.connectionState,
        VoiceMediaConnectionState.reconnecting,
      );
      expect(states, [VoiceMediaConnectionState.reconnecting]);
    });

    test('cancel before the immediate rung prevents its attempt', () async {
      var attempts = 0;
      final coordinator = VoiceReconnectCoordinator(
        attempt: () async {
          attempts++;
        },
        onStateChanged: (_) {},
        schedule: const [Duration.zero],
      );

      final reconnect = coordinator.reconnect();
      coordinator.cancel();
      await reconnect;

      expect(attempts, 0);
      expect(
        coordinator.connectionState,
        VoiceMediaConnectionState.reconnecting,
      );
    });

    test('cancel suppresses success from an in-flight attempt', () async {
      final attemptStarted = Completer<void>();
      final finishAttempt = Completer<void>();
      final states = <VoiceMediaConnectionState>[];
      final coordinator = VoiceReconnectCoordinator(
        attempt: () async {
          attemptStarted.complete();
          await finishAttempt.future;
        },
        onStateChanged: states.add,
        schedule: const [Duration.zero],
      );

      final reconnect = coordinator.reconnect();
      await attemptStarted.future;
      coordinator.cancel();
      finishAttempt.complete();
      await reconnect;

      expect(
        coordinator.connectionState,
        VoiceMediaConnectionState.reconnecting,
      );
      expect(states, [VoiceMediaConnectionState.reconnecting]);
    });
  });
}

MeshVoiceMediaSession _meshSession({
  required _FakePeerConnection peer,
  required bool audioPublishingAllowed,
  int localUserId = 10,
  int remoteUserId = 20,
  String localUsername = 'local',
  String remoteUsername = 'remote',
  VoiceUserMediaGetter? getUserMedia,
  VoiceUserMediaGetter? getDisplayMedia,
  VoiceDiagnosticsRecorder diagnostics = const NoopVoiceDiagnosticsRecorder(),
  String correlationId = 'uncorrelated',
  Duration rawStatsInterval = const Duration(seconds: 5),
  VoiceMediaDeviceEnumerator? enumerateDevices,
  VoiceSignalSender? sendSignal,
  VoiceTrackVolumeSetter? setTrackVolume,
}) => MeshVoiceMediaSession(
  join: _meshJoin(
    localUserId: localUserId,
    remoteUserId: remoteUserId,
    localUsername: localUsername,
    remoteUsername: remoteUsername,
  ),
  localUserId: localUserId,
  sendSignal: sendSignal ?? ((_, _) async {}),
  audioPublishingAllowed: audioPublishingAllowed,
  diagnostics: diagnostics,
  correlationId: correlationId,
  rawStatsInterval: rawStatsInterval,
  createPeerConnection: (_) async => peer,
  getUserMedia: getUserMedia,
  getDisplayMedia: getDisplayMedia,
  enumerateDevices: enumerateDevices,
  setTrackVolume: setTrackVolume,
);

LiveKitVoiceMediaSession _liveKitSession(VoiceLiveKitRoomAdapter adapter) =>
    LiveKitVoiceMediaSession(
      join: const VoiceJoinResponse(
        transport: VoiceTransport.livekit,
        ice: VoiceIceConfiguration(servers: [], relayOnly: false),
        room: VoiceRoom(
          id: 1,
          name: 'Room',
          slug: 'room',
          isPublic: true,
          ephemeral: false,
          type: VoiceRoomType.open,
          participants: [
            VoiceParticipant(
              id: 10,
              username: 'local',
              role: VoiceRole.participant,
            ),
          ],
        ),
        livekit: VoiceLiveKitCredentials(
          url: 'wss://localhost:3000',
          token: 'local-test-token',
        ),
      ),
      localUserId: 10,
      audioPublishingAllowed: false,
      refreshCredentials: () async => const VoiceLiveKitCredentials(
        url: 'wss://localhost:3000',
        token: 'refreshed-local-test-token',
      ),
      roomAdapter: adapter,
    );

VoiceJoinResponse _meshJoin({
  required int localUserId,
  required int remoteUserId,
  String localUsername = 'local',
  String remoteUsername = 'remote',
  VoiceRoomType roomType = VoiceRoomType.open,
  VoiceRole localRole = VoiceRole.participant,
  VoiceRole remoteRole = VoiceRole.participant,
  bool videoAllowed = true,
}) => VoiceJoinResponse(
  transport: VoiceTransport.mesh,
  ice: const VoiceIceConfiguration(servers: [], relayOnly: false),
  room: VoiceRoom(
    id: 1,
    name: 'Room',
    slug: 'room',
    isPublic: true,
    ephemeral: false,
    type: roomType,
    participants: [
      VoiceParticipant(
        id: localUserId,
        username: localUsername,
        role: localRole,
      ),
      VoiceParticipant(
        id: remoteUserId,
        username: remoteUsername,
        role: remoteRole,
      ),
    ],
    videoAllowed: videoAllowed,
  ),
);

final class _FakePeerConnection implements rtc.RTCPeerConnection {
  _FakePeerConnection({
    List<String>? events,
    this.failClose = false,
    this.exposeNullCachedSignalingState = false,
  }) : events = events ?? <String>[];

  final List<String> events;
  final bool failClose;
  final bool exposeNullCachedSignalingState;
  final List<String> mediaPlan = [];
  final List<rtc.MediaStreamTrack> addedTracks = [];
  final List<_FakeSender> addedTrackSenders = [];
  final List<rtc.RTCIceCandidate> addedCandidates = [];
  final List<_FakeTransceiver> createdTransceivers = [];
  List<_FakeTransceiver> _associated = [];
  rtc.RTCSessionDescription? _localDescription;
  rtc.RTCSessionDescription? _remoteDescription;
  bool _offerApplied = false;
  rtc.RTCSignalingState _signalingState =
      rtc.RTCSignalingState.RTCSignalingStateStable;
  int createdAnswers = 0;
  int rollbackCount = 0;
  bool closed = false;

  @override
  void Function(rtc.RTCIceCandidate candidate)? onIceCandidate;
  @override
  void Function(rtc.RTCTrackEvent event)? onTrack;
  @override
  void Function(rtc.RTCPeerConnectionState state)? onConnectionState;
  @override
  void Function(rtc.RTCIceConnectionState state)? onIceConnectionState;
  @override
  void Function(rtc.RTCIceGatheringState state)? onIceGatheringState;
  @override
  void Function(rtc.RTCSignalingState state)? onSignalingState;

  @override
  rtc.RTCSignalingState? get signalingState =>
      exposeNullCachedSignalingState ? null : _signalingState;

  @override
  Future<rtc.RTCSignalingState?> getSignalingState() async => _signalingState;

  @override
  Future<rtc.RTCRtpSender> addTrack(
    rtc.MediaStreamTrack track, [
    rtc.MediaStream? stream,
  ]) async {
    addedTracks.add(track);
    mediaPlan.add('track:${track.kind}');
    final sender = _FakeSender('microphone', track, events);
    addedTrackSenders.add(sender);
    return sender;
  }

  @override
  Future<rtc.RTCRtpTransceiver> addTransceiver({
    rtc.MediaStreamTrack? track,
    rtc.RTCRtpMediaType? kind,
    rtc.RTCRtpTransceiverInit? init,
  }) async {
    final mediaKind = switch (kind) {
      rtc.RTCRtpMediaType.RTCRtpMediaTypeVideo => 'video',
      _ => 'audio',
    };
    mediaPlan.add('transceiver:$mediaKind');
    final label = mediaKind == 'video' ? 'video' : 'screen-audio';
    final sender = _FakeSender(label, track, events);
    final transceiver = _FakeTransceiver(
      mid: '',
      sender: sender,
      receiver: _FakeReceiver(_FakeTrack('receiver-$label', mediaKind)),
      direction: init?.direction ?? rtc.TransceiverDirection.SendRecv,
    );
    createdTransceivers.add(transceiver);
    return transceiver;
  }

  List<_FakeTransceiver> prepareAssociatedTransceivers() {
    _associated = [
      _associatedTransceiver('0', 'microphone', 'audio'),
      _associatedTransceiver('1', 'video', 'video'),
      _associatedTransceiver('2', 'screen-audio', 'audio'),
    ];
    return _associated;
  }

  _FakeTransceiver _associatedTransceiver(
    String mid,
    String label,
    String kind,
  ) => _FakeTransceiver(
    mid: mid,
    sender: _FakeSender('associated-$label', null, events),
    receiver: _FakeReceiver(_FakeTrack('receiver-$label', kind)),
    direction: rtc.TransceiverDirection.RecvOnly,
  );

  @override
  Future<List<rtc.RTCRtpTransceiver>> getTransceivers() async =>
      _offerApplied && _associated.isNotEmpty
      ? _associated
      : createdTransceivers;

  @override
  Future<List<rtc.RTCRtpSender>> getSenders() async => [
    ...addedTrackSenders,
    for (final transceiver in createdTransceivers) transceiver.sender,
    if (_offerApplied)
      for (final transceiver in _associated) transceiver.sender,
  ];

  @override
  Future<rtc.RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async => rtc.RTCSessionDescription('local-offer', 'offer');

  @override
  Future<rtc.RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async {
    createdAnswers++;
    return rtc.RTCSessionDescription('local-answer', 'answer');
  }

  @override
  Future<void> setLocalDescription(
    rtc.RTCSessionDescription description,
  ) async {
    _localDescription = description;
    _signalingState = switch (description.type) {
      'offer' => rtc.RTCSignalingState.RTCSignalingStateHaveLocalOffer,
      'rollback' => rtc.RTCSignalingState.RTCSignalingStateStable,
      _ => rtc.RTCSignalingState.RTCSignalingStateStable,
    };
    if (description.type == 'rollback') rollbackCount++;
  }

  @override
  Future<void> setRemoteDescription(
    rtc.RTCSessionDescription description,
  ) async {
    _remoteDescription = description;
    _offerApplied = description.type == 'offer';
    _signalingState = switch (description.type) {
      'offer' => rtc.RTCSignalingState.RTCSignalingStateHaveRemoteOffer,
      _ => rtc.RTCSignalingState.RTCSignalingStateStable,
    };
  }

  @override
  Future<rtc.RTCSessionDescription?> getLocalDescription() async =>
      _localDescription;

  @override
  Future<rtc.RTCSessionDescription?> getRemoteDescription() async =>
      _remoteDescription;

  @override
  Future<void> addCandidate(rtc.RTCIceCandidate candidate) async {
    addedCandidates.add(candidate);
  }

  List<rtc.StatsReport> stats = const [];

  @override
  Future<List<rtc.StatsReport>> getStats([rtc.MediaStreamTrack? track]) async =>
      stats;

  @override
  Future<void> restartIce() async {}

  @override
  Future<void> close() async {
    closed = true;
    if (failClose) throw StateError('close failed');
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeLiveKitRoomAdapter implements VoiceLiveKitRoomAdapter {
  _FakeLiveKitRoomAdapter({
    this.failingStage,
    this.connection,
    this.cancelConnectionOnDisconnect = false,
  });

  final String? failingStage;
  final Completer<void>? connection;
  final bool cancelConnectionOnDisconnect;
  final Completer<void> connectStarted = Completer<void>();
  final List<String> calls = [];
  @override
  final lk.Room room = lk.Room();
  String? endpoint;
  String? token;

  @override
  void listen({
    required void Function() onChanged,
    required void Function() onDisconnected,
  }) {
    calls.add('listen');
  }

  @override
  Future<void> connect(String endpoint, String token) {
    calls.add('connect');
    this.endpoint = endpoint;
    this.token = token;
    if (!connectStarted.isCompleted) connectStarted.complete();
    return connection?.future ?? Future<void>.value();
  }

  @override
  Future<void> cancelListener() => _finish('cancel-listener');

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    if (cancelConnectionOnDisconnect &&
        connection != null &&
        !connection!.isCompleted) {
      connection!.completeError(StateError('connection cancelled'));
    }
    if (failingStage == 'disconnect') {
      throw StateError('disconnect failed');
    }
  }

  @override
  Future<void> disposeRoom() async {
    calls.add('dispose-room');
    await room.dispose();
    if (failingStage == 'dispose-room') {
      throw StateError('dispose-room failed');
    }
  }

  Future<void> _finish(String stage) async {
    calls.add(stage);
    if (failingStage == stage) throw StateError('$stage failed');
  }
}

final class _FakeTransceiver implements rtc.RTCRtpTransceiver {
  _FakeTransceiver({
    required this.mid,
    required this.sender,
    required this.receiver,
    required this.direction,
  });

  @override
  final String mid;
  @override
  final _FakeSender sender;
  @override
  final _FakeReceiver receiver;
  rtc.TransceiverDirection direction;

  @override
  Future<void> setDirection(rtc.TransceiverDirection value) async {
    direction = value;
  }

  @override
  String get transceiverId => mid;

  @override
  bool get stoped => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeSender implements rtc.RTCRtpSender {
  _FakeSender(this.senderId, this._track, this.events);

  @override
  final String senderId;
  rtc.MediaStreamTrack? _track;
  final List<String> events;
  final List<rtc.MediaStream> streams = [];

  @override
  rtc.MediaStreamTrack? get track => _track;

  @override
  rtc.RTCRtpParameters get parameters =>
      rtc.RTCRtpParameters(encodings: [rtc.RTCRtpEncoding()]);

  @override
  Future<void> replaceTrack(rtc.MediaStreamTrack? value) async {
    events.add('replace:$senderId:${value?.id ?? 'none'}');
    _track = value;
  }

  @override
  Future<bool> setParameters(rtc.RTCRtpParameters parameters) async => true;

  @override
  Future<void> setStreams(List<rtc.MediaStream> value) async {
    streams
      ..clear()
      ..addAll(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeReceiver implements rtc.RTCRtpReceiver {
  _FakeReceiver(this.track);

  @override
  final rtc.MediaStreamTrack? track;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeTrack implements rtc.MediaStreamTrack {
  _FakeTrack(this.id, this.kind, [List<String>? events])
    : events = events ?? <String>[];

  @override
  final String id;
  @override
  final String kind;
  final List<String> events;
  bool stopped = false;
  bool _enabled = true;

  @override
  rtc.StreamTrackCallback? onEnded;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) => _enabled = value;

  @override
  Future<void> stop() async {
    events.add('stop:$id');
    stopped = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeStream extends rtc.MediaStream {
  _FakeStream(String id, List<rtc.MediaStreamTrack> tracks)
    : _tracks = List.of(tracks),
      super(id, 'test');

  final List<rtc.MediaStreamTrack> _tracks;
  bool disposed = false;

  @override
  bool get active => !disposed;

  @override
  Future<void> getMediaTracks() async {}

  @override
  Future<void> addTrack(
    rtc.MediaStreamTrack track, {
    bool addToNative = true,
  }) async {
    _tracks.add(track);
  }

  @override
  Future<void> removeTrack(
    rtc.MediaStreamTrack track, {
    bool removeFromNative = true,
  }) async {
    _tracks.removeWhere((value) => value.id == track.id);
  }

  @override
  List<rtc.MediaStreamTrack> getTracks() => List.of(_tracks);

  @override
  List<rtc.MediaStreamTrack> getAudioTracks() =>
      _tracks.where((track) => track.kind == 'audio').toList();

  @override
  List<rtc.MediaStreamTrack> getVideoTracks() =>
      _tracks.where((track) => track.kind == 'video').toList();

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

Future<void> _pumpEventQueue() => Future<void>.delayed(Duration.zero);

final class _ManualTimer implements Timer {
  _ManualTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}

final class _ManualPeriodicTimer implements Timer {
  _ManualPeriodicTimer(this.delay, this._callback);

  final Duration delay;
  final void Function(Timer) _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _tick += 1;
    _callback(this);
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}
