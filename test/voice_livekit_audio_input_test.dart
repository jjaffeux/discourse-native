import 'dart:async';

import 'package:discourse_native/src/plugins/voice/voice_media.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:livekit_client/src/core/engine.dart' as lk_engine;
import 'package:livekit_client/src/proto/livekit_models.pb.dart' as lk_models;
import 'package:livekit_client/src/proto/livekit_rtc.pb.dart' as lk_rtc;

const _captureOptions = lk.AudioCaptureOptions(
  deviceId: 'original-input',
  noiseSuppression: false,
  echoCancellation: false,
  autoGainControl: false,
  highPassFilter: true,
  voiceIsolation: false,
  typingNoiseDetection: false,
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const methodChannel = MethodChannel('FlutterWebRTC.Method');
  const eventChannel = EventChannel('FlutterWebRTC.Event');
  final messenger = binding.defaultBinaryMessenger;
  late List<MethodCall> nativeCalls;
  late _RoomAdapter adapter;
  late LiveKitVoiceMediaSession media;
  PlatformException? selectionError;
  Completer<void>? selectionGate;
  Completer<void>? selectionStarted;

  List<MethodCall> callsTo(String method) =>
      nativeCalls.where((call) => call.method == method).toList();

  void expectSelectedInput(String deviceId) {
    expect(callsTo('selectAudioInput').map((call) => call.arguments), [
      {'deviceId': deviceId},
    ]);
    expect(
      adapter.room.roomOptions.defaultAudioCaptureOptions
          .toMediaConstraintsMap(),
      _captureOptions.copyWith(deviceId: deviceId).toMediaConstraintsMap(),
    );
  }

  void expectCaptureFrom(String deviceId) {
    expect(callsTo('getUserMedia').single.arguments, {
      'constraints': {
        'audio': _captureOptions
            .copyWith(deviceId: deviceId)
            .toMediaConstraintsMap(),
        'video': false,
      },
    });
  }

  void expectOnlyDeviceSelection() {
    expect(
      nativeCalls.map((call) => call.method),
      everyElement(isIn(['selectAudioInput', 'initialize', 'getSources'])),
    );
  }

  setUp(() {
    nativeCalls = [];
    selectionError = null;
    selectionGate = null;
    selectionStarted = null;
    var streamNumber = 0;
    rtc.WebRTC.initialized = false;
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      nativeCalls.add(call);
      if (call.method == 'selectAudioInput') {
        selectionStarted?.complete();
        await selectionGate?.future;
        if (selectionError case final error?) throw error;
        return null;
      }
      if (call.method == 'getUserMedia') {
        streamNumber++;
        return <String, Object?>{
          'streamId': 'microphone-stream-$streamNumber',
          'audioTracks': [
            <String, Object?>{
              'id': 'microphone-track-$streamNumber',
              'label': 'Test microphone',
              'kind': 'audio',
              'enabled': true,
              'settings': <String, Object?>{},
            },
          ],
          'videoTracks': <Object?>[],
        };
      }
      return switch (call.method) {
        'getSources' => <String, Object?>{'sources': <Object?>[]},
        'initialize' ||
        'trackDispose' ||
        'streamDispose' ||
        'mediaStreamTrackSetEnable' => null,
        _ => throw UnsupportedError('Unexpected WebRTC call: ${call.method}'),
      };
    });
    adapter = _RoomAdapter();
    media = _session(adapter);
  });

  tearDown(() async {
    await media.dispose();
    rtc.WebRTC.initialized = false;
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(eventChannel, null);
  });

  test(
    'switches native input without toggling the published microphone',
    () async {
      await media.connect();
      final publication = adapter.microphone;
      final track = publication.track!;
      final nativeTrack = track.mediaStreamTrack;
      adapter.attachSender();
      nativeCalls.clear();

      await media.selectAudioInput('selected-input');

      expectSelectedInput('selected-input');
      expectOnlyDeviceSelection();
      expect(adapter.microphone, same(publication));
      expect(track.mediaStreamTrack, same(nativeTrack));
      expect(track.muted, isFalse);
      expect(media.shouldPublishMicrophone, isTrue);
      expect(
        track.currentOptions.toMediaConstraintsMap(),
        _captureOptions
            .copyWith(deviceId: 'selected-input')
            .toMediaConstraintsMap(),
      );

      await media.setMuted(true);
      nativeCalls.clear();
      await media.setMuted(false);

      expectCaptureFrom('selected-input');
      expect(adapter.sender.replacements, [track.mediaStreamTrack]);
      expect(track.muted, isFalse);
    },
  );

  for (final restriction in ['muted', 'stage listener']) {
    test('retains input on an existing $restriction publication', () async {
      await media.connect();
      final track = adapter.microphone.track!;
      adapter.attachSender();
      if (restriction == 'muted') {
        await media.setMuted(true);
      } else {
        await media.setAudioPublishingAllowed(false);
      }
      nativeCalls.clear();

      await media.selectAudioInput('selected-input');

      expectSelectedInput('selected-input');
      expectOnlyDeviceSelection();
      expect(track.currentOptions.deviceId, 'selected-input');
      expect(track.muted, isTrue);
      expect(track.isActive, isFalse);
      expect(media.shouldPublishMicrophone, isFalse);

      nativeCalls.clear();
      if (restriction == 'muted') {
        await media.setMuted(false);
      } else {
        await media.setMuted(false);
        expect(track.muted, isTrue);
        expect(callsTo('getUserMedia'), isEmpty);
        await media.setAudioPublishingAllowed(true);
      }

      expectCaptureFrom('selected-input');
      expect(track.muted, isFalse);
      expect(adapter.sender.replacements, [track.mediaStreamTrack]);
    });
  }

  for (final muted in [false, true]) {
    test(
      'stage selection waits for publishing permission and mute=$muted',
      () async {
        await media.dispose();
        adapter = _RoomAdapter();
        media = _session(adapter, audioPublishingAllowed: false);
        await media.connect();
        await media.setMuted(muted);
        nativeCalls.clear();

        await media.selectAudioInput('selected-input');

        expectSelectedInput('selected-input');
        expectOnlyDeviceSelection();
        expect(adapter.room.localParticipant!.audioTrackPublications, isEmpty);
        expect(media.shouldPublishMicrophone, isFalse);

        nativeCalls.clear();
        await media.setAudioPublishingAllowed(true);
        if (muted) {
          expect(
            adapter.room.localParticipant!.audioTrackPublications,
            isEmpty,
          );
          expect(callsTo('getUserMedia'), isEmpty);
          await media.setMuted(false);
        }

        expectCaptureFrom('selected-input');
        expect(
          adapter.microphone.track!.currentOptions.deviceId,
          'selected-input',
        );
        expect(adapter.microphone.muted, isFalse);
      },
    );
  }

  test('retains selection before a local participant exists', () async {
    expect(adapter.room.localParticipant, isNull);

    await media.selectAudioInput('selected-input');

    expectSelectedInput('selected-input');
    expectOnlyDeviceSelection();
    nativeCalls.clear();
    await media.connect();

    expectCaptureFrom('selected-input');
    expect(adapter.microphone.track!.currentOptions.deviceId, 'selected-input');
  });

  test(
    'keeps screen-sharing audio options when selecting a microphone',
    () async {
      await media.connect();
      adapter.attachSender();
      final stream = await rtc.navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      const options = lk.AudioCaptureOptions(deviceId: 'screen-audio');
      // Construct the other audio source with the same mocked native boundary.
      // ignore: invalid_use_of_internal_member
      final screenAudio = lk.LocalAudioTrack(
        lk.TrackSource.screenShareAudio,
        stream,
        stream.getAudioTracks().single,
        options,
      );
      await adapter.room.localParticipant!.publishAudioTrack(screenAudio);
      nativeCalls.clear();

      await media.selectAudioInput('selected-input');

      expectSelectedInput('selected-input');
      expectOnlyDeviceSelection();
      expect(
        adapter.microphone.track!.currentOptions.deviceId,
        'selected-input',
      );
      expect(screenAudio.currentOptions, same(options));
      expect(screenAudio.mediaStream, same(stream));
      expect(screenAudio.muted, isFalse);
    },
  );

  test(
    'propagates native selection failure without changing capture or mute',
    () async {
      await media.connect();
      final track = adapter.microphone.track!;
      adapter.attachSender();
      final options = track.currentOptions;
      final defaults = adapter.room.roomOptions.defaultAudioCaptureOptions;
      var notifications = 0;
      media.addListener(() => notifications++);
      nativeCalls.clear();
      selectionError = PlatformException(
        code: 'input-unavailable',
        message: 'The selected microphone was disconnected',
        details: 'native selection failure',
      );

      await expectLater(
        media.selectAudioInput('missing-input'),
        throwsA(
          isA<PlatformException>()
              .having((error) => error.code, 'code', selectionError!.code)
              .having(
                (error) => error.message,
                'message',
                selectionError!.message,
              )
              .having(
                (error) => error.details,
                'details',
                selectionError!.details,
              ),
        ),
      );

      expect(callsTo('selectAudioInput').single.arguments, {
        'deviceId': 'missing-input',
      });
      expectOnlyDeviceSelection();
      expect(track.currentOptions, same(options));
      expect(
        adapter.room.roomOptions.defaultAudioCaptureOptions,
        same(defaults),
      );
      expect(track.muted, isFalse);
      expect(media.shouldPublishMicrophone, isTrue);
      expect(notifications, 0);
    },
  );

  test(
    'does not update a track when selection finishes during teardown',
    () async {
      await media.connect();
      final track = adapter.microphone.track!;
      final options = track.currentOptions;
      var notifications = 0;
      media.addListener(() => notifications++);
      final cleanup = Completer<void>();
      adapter.cleanup = cleanup;
      selectionGate = Completer<void>();
      selectionStarted = Completer<void>();
      final selecting = media.selectAudioInput('selected-input');
      await selectionStarted!.future;

      final disposing = media.dispose();
      try {
        selectionGate!.complete();
        await selecting;

        expect(track.currentOptions, same(options));
        expect(notifications, 0);
      } finally {
        cleanup.complete();
        await disposing;
      }
    },
  );

  test(
    'ignores selection as soon as teardown starts and after it finishes',
    () async {
      await media.connect();
      adapter.attachSender();
      nativeCalls.clear();
      final cleanup = Completer<void>();
      adapter.cleanup = cleanup;
      final defaults = adapter.room.roomOptions.defaultAudioCaptureOptions;
      final disposing = media.dispose();
      try {
        await media.selectAudioInput('during-teardown');

        expect(nativeCalls, isEmpty);
        expect(
          adapter.room.roomOptions.defaultAudioCaptureOptions,
          same(defaults),
        );
      } finally {
        cleanup.complete();
        await disposing;
      }

      nativeCalls.clear();
      await media.selectAudioInput('after-teardown');

      expect(nativeCalls, isEmpty);
      expect(
        adapter.room.roomOptions.defaultAudioCaptureOptions,
        same(defaults),
      );
    },
  );
}

LiveKitVoiceMediaSession _session(
  _RoomAdapter adapter, {
  bool audioPublishingAllowed = true,
}) => LiveKitVoiceMediaSession(
  join: const VoiceJoinResponse(
    transport: VoiceTransport.livekit,
    ice: VoiceIceConfiguration(servers: [], relayOnly: false),
    room: VoiceRoom(
      id: 1,
      name: 'Room',
      slug: 'room',
      isPublic: true,
      ephemeral: false,
      type: VoiceRoomType.stage,
      participants: [],
    ),
    livekit: VoiceLiveKitCredentials(
      url: 'wss://localhost:3000',
      token: 'local-test-token',
    ),
  ),
  localUserId: 10,
  audioPublishingAllowed: audioPublishingAllowed,
  refreshCredentials: () async =>
      const VoiceLiveKitCredentials(url: '', token: ''),
  rawStatsInterval: Duration.zero,
  roomAdapter: adapter,
);

final class _RoomAdapter implements VoiceLiveKitRoomAdapter {
  @override
  final _Room room = _Room();
  final sender = _Sender();
  Completer<void>? cleanup;

  lk.LocalTrackPublication<lk.LocalAudioTrack> get microphone =>
      room.localParticipant!.audioTrackPublications.firstWhere(
        (publication) => publication.source == lk.TrackSource.microphone,
      );

  void attachSender() {
    microphone.track!.transceiver = _Transceiver(sender);
  }

  @override
  void listen({
    required void Function() onChanged,
    required void Function() onDisconnected,
  }) {}

  @override
  Future<void> connect(String endpoint, String token) async {
    // Exercise the real participant's publication reuse and capture defaults.
    // Only the signaling connection is replaced by this adapter.
    // ignore: invalid_use_of_internal_member
    room.localParticipant = await lk.LocalParticipant.createFromInfo(
      room: room,
      info: lk_models.ParticipantInfo(sid: 'local', identity: '10'),
    );
  }

  @override
  Future<void> cancelListener() async => await cleanup?.future;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> disposeRoom() async {
    await room.dispose();
  }
}

final class _Room extends lk.Room {
  _Room() : super(engine: _Engine());

  @override
  lk.LocalParticipant? localParticipant;
}

final class _Engine extends lk_engine.Engine {
  _Engine()
    : super(
        connectOptions: const lk.ConnectOptions(),
        roomOptions: const lk.RoomOptions(
          defaultAudioCaptureOptions: _captureOptions,
        ),
      );

  // Acknowledge publication without a server or a native peer connection.
  // Capture, mute/unmute, and track replacement still run in the real SDK.
  @override
  Future<lk_models.TrackInfo> addTrack(lk_rtc.AddTrackRequest req) async =>
      lk_models.TrackInfo(
        sid: 'publication-${req.cid}',
        name: req.name,
        type: req.type,
        source: req.source,
      );
}

final class _Transceiver implements rtc.RTCRtpTransceiver {
  _Transceiver(this.sender);

  @override
  final _Sender sender;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Sender implements rtc.RTCRtpSender {
  final List<rtc.MediaStreamTrack?> replacements = [];

  @override
  Future<void> replaceTrack(rtc.MediaStreamTrack? track) async {
    replacements.add(track);
  }

  @override
  Future<List<rtc.StatsReport>> getStats() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
