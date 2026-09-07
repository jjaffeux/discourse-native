import 'package:discourse_native/src/plugins/voice/voice_media.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('native peer cleanup cancels events when close fails', () async {
    const methodChannel = MethodChannel('FlutterWebRTC.Method');
    const logChannel = EventChannel('FlutterWebRTC.Event');
    const peerChannel = EventChannel(
      'FlutterWebRTC/peerConnectionEventtest-peer',
    );
    final messenger = binding.defaultBinaryMessenger;
    final teardown = <String>[];
    var subscriptions = 0;
    final wasInitialized = rtc.WebRTC.initialized;
    rtc.WebRTC.initialized = false;
    messenger.setMockStreamHandler(
      logChannel,
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    messenger.setMockStreamHandler(
      peerChannel,
      MockStreamHandler.inline(
        onListen: (_, _) => subscriptions++,
        onCancel: (_) => teardown.add('cancel-events'),
      ),
    );
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return null;
        case 'createPeerConnection':
          return {'peerConnectionId': 'test-peer'};
        case 'addTransceiver':
          throw PlatformException(code: 'setup', message: 'setup failed');
        case 'peerConnectionClose':
          teardown.add('close');
          throw PlatformException(code: 'close', message: 'close failed');
        case 'peerConnectionDispose':
          teardown.add('dispose');
          return null;
        default:
          fail('Unexpected WebRTC call: ${call.method}');
      }
    });
    final media = MeshVoiceMediaSession(
      join: const VoiceJoinResponse(
        transport: VoiceTransport.mesh,
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
            VoiceParticipant(
              id: 20,
              username: 'remote',
              role: VoiceRole.participant,
            ),
          ],
        ),
      ),
      localUserId: 10,
      sendSignal: (_, _) async => fail('Failed setup must not signal'),
      audioPublishingAllowed: false,
    );
    addTearDown(() async {
      await media.dispose();
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockStreamHandler(peerChannel, null);
      messenger.setMockStreamHandler(logChannel, null);
      rtc.WebRTC.initialized = wasInitialized;
    });

    await expectLater(
      media.connect(),
      throwsA('Unable to RTCPeerConnection::addTransceiver: setup failed'),
    );

    expect(subscriptions, 1);
    expect(teardown, ['close', 'cancel-events', 'dispose']);
    await media.dispose();
    expect(teardown, ['close', 'cancel-events', 'dispose']);
  });
}
