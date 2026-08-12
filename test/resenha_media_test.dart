import 'dart:async';

import 'package:discourse_native/src/plugins/resenha/resenha_media.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_models.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_reconnect.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

ResenhaJoinResponse join({
  required ResenhaRoomType roomType,
  required ResenhaRole role,
}) => ResenhaJoinResponse(
  transport: ResenhaTransport.mesh,
  ice: const ResenhaIceConfiguration(servers: [], relayOnly: false),
  room: ResenhaRoom(
    id: 1,
    name: 'Room',
    slug: 'room',
    isPublic: true,
    ephemeral: false,
    type: roomType,
    participants: [ResenhaParticipant(id: 10, username: 'sam', role: role)],
  ),
);

void main() {
  test('stage listeners do not acquire an outgoing audio publication', () {
    final media = const NativeResenhaMediaFactory().create(
      join: join(
        roomType: ResenhaRoomType.stage,
        role: ResenhaRole.participant,
      ),
      localUserId: 10,
      sendSignal: (_, _) async {},
      refreshLiveKitCredentials: () async =>
          const ResenhaLiveKitCredentials(url: '', token: ''),
    );

    expect((media as MeshResenhaMediaSession).audioPublishingAllowed, isFalse);
  });

  test('stage speakers and open-room participants may publish audio', () {
    for (final response in [
      join(roomType: ResenhaRoomType.stage, role: ResenhaRole.speaker),
      join(roomType: ResenhaRoomType.open, role: ResenhaRole.participant),
    ]) {
      final media = const NativeResenhaMediaFactory().create(
        join: response,
        localUserId: 10,
        sendSignal: (_, _) async {},
        refreshLiveKitCredentials: () async =>
            const ResenhaLiveKitCredentials(url: '', token: ''),
      );

      expect((media as MeshResenhaMediaSession).audioPublishingAllowed, isTrue);
    }
  });

  group('MeshResenhaMediaSession', () {
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
          everyElement(rtc.TransceiverDirection.SendRecv),
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
        final media = MeshResenhaMediaSession(
          join: _meshJoin(
            localUserId: 10,
            remoteUserId: 20,
            roomType: ResenhaRoomType.stage,
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
            roomType: ResenhaRoomType.stage,
            remoteRole: ResenhaRole.speaker,
          ).room.participants,
        );
        expect(peerCreations, 1);

        await media.syncParticipants(
          _meshJoin(
            localUserId: 10,
            remoteUserId: 20,
            roomType: ResenhaRoomType.stage,
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
        final media = MeshResenhaMediaSession(
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
      final media = MeshResenhaMediaSession(
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
      final media = MeshResenhaMediaSession(
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

    test(
      'ignores signals from self and participants outside the roster',
      () async {
        final peer = _FakePeerConnection();
        var peerCreations = 0;
        final response = _meshJoin(localUserId: 10, remoteUserId: 20);
        final media = MeshResenhaMediaSession(
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

    test('the lower-id peer rolls back a fallback-offer collision', () async {
      final peer = _FakePeerConnection();
      final media = _meshSession(peer: peer, audioPublishingAllowed: false);
      await media.connect();
      peer.prepareAssociatedTransceivers();

      await media.handleSignal(20, {'type': 'offer', 'sdp': 'fallback-offer'});

      expect(peer.rollbackCount, 1);
      expect(peer.createdAnswers, 1);
      await media.dispose();
    });

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
  });

  group('LiveKitResenhaMediaSession', () {
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

  group('ResenhaReconnectCoordinator', () {
    test('rejects an unusable retry schedule in release builds', () {
      ResenhaReconnectCoordinator create(List<Duration> schedule) =>
          ResenhaReconnectCoordinator(
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
      final states = <ResenhaMediaConnectionState>[];
      final timers = <_ManualTimer>[];
      final coordinator = ResenhaReconnectCoordinator(
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
        ResenhaMediaConnectionState.reconnecting,
      );

      timers.single.fire();
      await reconnect;

      expect(attempts, 2);
      expect(
        coordinator.connectionState,
        ResenhaMediaConnectionState.connected,
      );
      expect(states, [
        ResenhaMediaConnectionState.reconnecting,
        ResenhaMediaConnectionState.connected,
      ]);
    });

    test('coalesces concurrent disconnect events into one attempt', () async {
      final attemptStarted = Completer<void>();
      final finishAttempt = Completer<void>();
      var attempts = 0;
      final coordinator = ResenhaReconnectCoordinator(
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
      expect(
        coordinator.connectionState,
        ResenhaMediaConnectionState.connected,
      );
    });

    test('exhaustion becomes failed without leaking attempt errors', () async {
      var attempts = 0;
      final states = <ResenhaMediaConnectionState>[];
      final coordinator = ResenhaReconnectCoordinator(
        attempt: () async {
          attempts++;
          throw StateError('still offline');
        },
        onStateChanged: states.add,
        schedule: const [Duration.zero, Duration.zero, Duration.zero],
      );

      await coordinator.reconnect();

      expect(attempts, 3);
      expect(coordinator.connectionState, ResenhaMediaConnectionState.failed);
      expect(states, [
        ResenhaMediaConnectionState.reconnecting,
        ResenhaMediaConnectionState.failed,
      ]);
    });

    test('cancel releases backoff and prevents later attempts', () async {
      var attempts = 0;
      final states = <ResenhaMediaConnectionState>[];
      final timers = <_ManualTimer>[];
      final coordinator = ResenhaReconnectCoordinator(
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
        ResenhaMediaConnectionState.reconnecting,
      );
      expect(states, [ResenhaMediaConnectionState.reconnecting]);
    });

    test('cancel before the immediate rung prevents its attempt', () async {
      var attempts = 0;
      final coordinator = ResenhaReconnectCoordinator(
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
        ResenhaMediaConnectionState.reconnecting,
      );
    });

    test('cancel suppresses success from an in-flight attempt', () async {
      final attemptStarted = Completer<void>();
      final finishAttempt = Completer<void>();
      final states = <ResenhaMediaConnectionState>[];
      final coordinator = ResenhaReconnectCoordinator(
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
        ResenhaMediaConnectionState.reconnecting,
      );
      expect(states, [ResenhaMediaConnectionState.reconnecting]);
    });
  });
}

MeshResenhaMediaSession _meshSession({
  required _FakePeerConnection peer,
  required bool audioPublishingAllowed,
  int localUserId = 10,
  int remoteUserId = 20,
  ResenhaUserMediaGetter? getUserMedia,
  ResenhaUserMediaGetter? getDisplayMedia,
}) => MeshResenhaMediaSession(
  join: _meshJoin(localUserId: localUserId, remoteUserId: remoteUserId),
  localUserId: localUserId,
  sendSignal: (_, _) async {},
  audioPublishingAllowed: audioPublishingAllowed,
  createPeerConnection: (_) async => peer,
  getUserMedia: getUserMedia,
  getDisplayMedia: getDisplayMedia,
);

LiveKitResenhaMediaSession _liveKitSession(ResenhaLiveKitRoomAdapter adapter) =>
    LiveKitResenhaMediaSession(
      join: ResenhaJoinResponse(
        transport: ResenhaTransport.livekit,
        ice: const ResenhaIceConfiguration(servers: [], relayOnly: false),
        room: const ResenhaRoom(
          id: 1,
          name: 'Room',
          slug: 'room',
          isPublic: true,
          ephemeral: false,
          type: ResenhaRoomType.open,
          participants: [
            ResenhaParticipant(
              id: 10,
              username: 'local',
              role: ResenhaRole.participant,
            ),
          ],
        ),
        livekit: const ResenhaLiveKitCredentials(
          url: 'wss://localhost:3000',
          token: 'local-test-token',
        ),
      ),
      localUserId: 10,
      audioPublishingAllowed: false,
      refreshCredentials: () async => const ResenhaLiveKitCredentials(
        url: 'wss://localhost:3000',
        token: 'refreshed-local-test-token',
      ),
      roomAdapter: adapter,
    );

ResenhaJoinResponse _meshJoin({
  required int localUserId,
  required int remoteUserId,
  ResenhaRoomType roomType = ResenhaRoomType.open,
  ResenhaRole localRole = ResenhaRole.participant,
  ResenhaRole remoteRole = ResenhaRole.participant,
}) => ResenhaJoinResponse(
  transport: ResenhaTransport.mesh,
  ice: const ResenhaIceConfiguration(servers: [], relayOnly: false),
  room: ResenhaRoom(
    id: 1,
    name: 'Room',
    slug: 'room',
    isPublic: true,
    ephemeral: false,
    type: roomType,
    participants: [
      ResenhaParticipant(id: localUserId, username: 'local', role: localRole),
      ResenhaParticipant(
        id: remoteUserId,
        username: 'remote',
        role: remoteRole,
      ),
    ],
    videoAllowed: true,
  ),
);

final class _FakePeerConnection implements rtc.RTCPeerConnection {
  _FakePeerConnection({List<String>? events, this.failClose = false})
    : events = events ?? <String>[];

  final List<String> events;
  final bool failClose;
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
  rtc.RTCSignalingState? get signalingState => _signalingState;

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

  @override
  Future<List<rtc.StatsReport>> getStats([rtc.MediaStreamTrack? track]) async =>
      const [];

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

final class _FakeLiveKitRoomAdapter implements ResenhaLiveKitRoomAdapter {
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
