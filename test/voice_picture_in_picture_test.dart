import 'dart:async';

import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_media.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_picture_in_picture.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'preview follows remote speakers and falls back without stopping tracks',
    () {
      final local = Object(), first = Object(), second = Object();
      final media = _PreviewMedia(
        local: local,
        tracks: {1: local, 2: first, 3: second},
      );
      final call = VoiceCallSnapshot(
        siteUrl: 'https://voice.example.com',
        siteName: 'Voice',
        status: VoiceCallStatus.connected,
        media: media,
        room: const VoiceRoom(
          id: 7,
          name: 'Room',
          slug: 'room',
          isPublic: true,
          ephemeral: false,
          type: VoiceRoomType.open,
          participants: [
            VoiceParticipant(
              id: 1,
              username: 'me',
              role: VoiceRole.participant,
            ),
            VoiceParticipant(
              id: 2,
              username: 'lee',
              role: VoiceRole.participant,
            ),
            VoiceParticipant(
              id: 3,
              username: 'sam',
              role: VoiceRole.participant,
            ),
          ],
        ),
      );
      expect(voiceCallPreviewTrack(call), same(first));
      media.speaking = {3};
      expect(voiceCallPreviewTrack(call), same(second));
      media.tracks.remove(3);
      expect(voiceCallPreviewTrack(call), same(first));
      media.tracks.remove(2);
      expect(voiceCallPreviewTrack(call), same(local));
      media.local = null;
      media.tracks.clear();
      expect(voiceCallPreviewTrack(call), isNull);
      expect(
        voiceCallPreviewTrack(call.copyWith(status: VoiceCallStatus.leaving)),
        isNull,
      );
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/voice_pip');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final commands = <MethodCall>[];
  setUp(() {
    commands.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      commands.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> configure(NativeVoicePictureInPicture pip, String id) =>
      pip.configure(
        sessionId: id,
        roomName: 'Watercooler',
        track: null,
        cameraEnabled: false,
        recording: false,
        recordingLabel: 'Recording',
      );
  Future<void> event(String method, String id, {bool? active}) async {
    final done = Completer<void>();
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, {'sessionId': id, 'active': ?active}),
      ),
      (_) => done.complete(),
    );
    await done.future;
  }

  test(
    'native restore and active callbacks are scoped to the current call',
    () async {
      var restored = 0;
      final pip = NativeVoicePictureInPicture(
        enabled: true,
        onRestore: () => restored++,
      );
      await configure(pip, 'old');
      await configure(pip, 'current');
      await event('activeChanged', 'old', active: true);
      await event('restore', 'old');
      expect(pip.active, isFalse);
      expect(restored, 0);
      await event('activeChanged', 'current', active: true);
      await event('restore', 'current');
      expect(pip.active, isTrue);
      expect(restored, 1);
      await configure(pip, 'replacement');
      expect(pip.active, isFalse);
      await event('activeChanged', 'current', active: true);
      expect(pip.active, isFalse);
      await pip.close();
    },
  );

  test(
    'closing drains configure before clearing and prevents resurrection',
    () async {
      final gate = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        commands.add(call);
        if (call.method == 'configure') await gate.future;
        return null;
      });
      final pip = NativeVoicePictureInPicture(enabled: true, onRestore: () {});
      unawaited(configure(pip, 'call'));
      await pumpEventQueue();
      final closing = pip.close();
      gate.complete();
      await closing;
      await configure(pip, 'late');
      expect(commands.map((c) => c.method), ['configure', 'clear']);
    },
  );

  test(
    'identical presentations do not enqueue duplicate native work',
    () async {
      final pip = NativeVoicePictureInPicture(enabled: true, onRestore: () {});
      await configure(pip, 'call');
      await configure(pip, 'call');
      expect(commands.length, 1);
      await pip.close();
    },
  );

  test(
    'closing an old adapter does not clear its replacement handler',
    () async {
      final old = NativeVoicePictureInPicture(enabled: true, onRestore: () {});
      var restored = 0;
      final current = NativeVoicePictureInPicture(
        enabled: true,
        onRestore: () => restored++,
      );
      await configure(current, 'current');
      await old.close();
      await event('restore', 'current');
      expect(restored, 1);
      expect(commands.map((c) => c.method), ['configure']);
      await current.close();
    },
  );
}

class _PreviewMedia extends Fake implements VoiceMediaSession {
  _PreviewMedia({required this.local, required this.tracks});
  Object? local;
  final Map<int, Object> tracks;
  Set<int> speaking = {};
  @override
  Object? get localVideoTrack => local;
  @override
  Object? videoTrackFor(int id) => tracks[id];
  @override
  Set<int> get speakingParticipantIds => speaking;
}
