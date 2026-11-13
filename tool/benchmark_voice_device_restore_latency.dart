import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_preferences.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:flutter/widgets.dart';

import '../test/support/voice_call_fakes.dart';
import '../test/support/voice_fake_chat_conversations.dart';

const _site = 'https://forum.example';
const _input = 'saved-microphone';
const _output = 'saved-speaker';
const _platformLatency = Duration(milliseconds: 30);

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/voice/$name.json').readAsStringSync())
        as Map<String, dynamic>;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final room = VoiceRoom.fromJson(_fixture('room'));
  final join = _fixture('join_mesh');
  final samples = <int>[];
  for (var i = 0; i < 7; i++) {
    final elapsed = await _joinWithSavedDevices(room, join);
    if (i >= 2) samples.add(elapsed);
  }
  samples.sort();
  stdout.writeln(
    jsonEncode({'join_voice_with_saved_audio_devices': samples[2]}),
  );
  exit(0);
}

Future<int> _joinWithSavedDevices(
  VoiceRoom room,
  Map<String, dynamic> join,
) async {
  final transport = RecordingPluginTransport(
    responses: {
      'POST /voice/rooms/7/join.json': join,
      'POST /voice/rooms/7/state.json': {},
      'DELETE /voice/rooms/7/leave.json': {},
    },
  );
  final media = FakeVoiceMediaFactory();
  media.nextAudioInputSelection = (_) => Future<void>.delayed(_platformLatency);
  media.nextAudioOutputSelection = (_) =>
      Future<void>.delayed(_platformLatency);
  final system = FakeVoiceSystemCall();
  final controller = VoiceController(
    api: VoiceApi(transport, namespaceFor: (_) => VoiceNamespace.voice),
    requests: PluginTestRequestHost(apiKeys: {_site: 'key'}),
    trackerFor: (_) => null,
    chatConversations: FakeChatConversationCapability(),
    userIdFor: (_) => 1,
    onCallSiteChanged: () {},
    mediaFactory: media,
    systemCall: system,
    preferences: FakeVoicePreferences()
      ..devices = const VoiceDevicePreferences(
        audioInputDeviceId: _input,
        audioOutputDeviceId: _output,
      ),
  );
  try {
    final watch = Stopwatch()..start();
    await controller.join(siteUrl: _site, siteName: 'Forum', room: room);
    watch.stop();
    final session = media.sessions.single;
    if (controller.call?.status != VoiceCallStatus.connected ||
        session.selectedAudioInput != _input ||
        session.selectedAudioOutput != _output ||
        session.audioInputSelections.length != 1 ||
        session.audioOutputSelections.length != 1 ||
        system.connectedCalls != 1) {
      throw StateError('Voice did not connect with both saved devices');
    }
    return watch.elapsedMicroseconds;
  } finally {
    await controller.close();
  }
}
