import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_media.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/voice_fake_chat_conversations.dart';
import 'voice_controller_test.dart'
    show
        FakeVoiceMediaFactory,
        FakeVoiceMediaSession,
        FakeVoicePreferences,
        FakeVoiceSystemCall;

const _site = 'https://voice.example.com';

final class _Requests implements PluginRequestHost {
  final delegate = PluginTestRequestHost(apiKeys: {_site: 'key'});
  Completer<void>? gate;
  Completer<void>? started;

  @override
  PluginSiteLease capture(String siteUrl) => delegate.capture(siteUrl);

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) =>
      delegate.credentialsFor(siteUrl);

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async {
    started?.complete();
    started = null;
    await gate?.future;
    return delegate.writeCredentialFor(siteUrl);
  }
}

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/voice/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  late RecordingPluginTransport transport;
  late RecordingPluginLiveChannels channels;
  late _Requests requests;
  late VoiceController controller;

  setUp(() async {
    transport = RecordingPluginTransport(
      responses: {
        'GET /voice/rooms.json': _fixture('directory'),
        'POST /voice/rooms/7/join.json': _fixture('join_mesh'),
        'GET /site.json': {
          'voice_reaction_emojis': ['heart', 'clap'],
        },
        'POST /voice/rooms/7/reaction.json': {},
      },
    );
    channels = RecordingPluginLiveChannels();
    requests = _Requests();
    controller = VoiceController(
      api: VoiceApi(transport, namespaceFor: (_) => VoiceNamespace.voice),
      chatConversations: FakeChatConversationCapability(),
      requests: requests,
      trackerFor: (_) => channels,
      userIdFor: (_) => 1,
      onCallSiteChanged: () {},
      mediaFactory: FakeVoiceMediaFactory(),
      systemCall: FakeVoiceSystemCall(),
      preferences: FakeVoicePreferences(),
      heartbeatInterval: const Duration(days: 1),
    );
    await controller.ensureLoaded(_site);
    await controller.join(
      siteUrl: _site,
      siteName: 'Example',
      room: VoiceRoom.fromJson(_fixture('room')),
    );
  });

  tearDown(() => controller.close());

  test(
    'reconnecting retires pending settings and recovery loads a fresh reaction session',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      transport.responders['GET /site.json'] = (_) {
        started.complete();
        return pending.future;
      };
      final previous = controller.callReactions!;
      final loading = previous.load();
      await started.future;
      final media = controller.call!.media as FakeVoiceMediaSession;
      media.connectionState = VoiceMediaConnectionState.reconnecting;
      media.notifyListeners();
      expect(controller.callReactions, isNull);
      expect(previous.isCurrent, isFalse);
      transport.responders.remove('GET /site.json');
      media.connectionState = VoiceMediaConnectionState.connected;
      media.notifyListeners();
      final recovered = controller.callReactions!;
      await recovered.load();
      expect(recovered, isNot(same(previous)));
      expect(recovered.canSend, isTrue);
      pending.complete({
        'voice_reaction_emojis': ['stale_emoji'],
      });
      await loading;
      expect(previous.settings, isNull);
      expect(recovered.settings!.emojis, ['heart', 'clap']);
    },
  );

  test('a different room or site cannot display the active call reactions', () {
    expect(controller.reactionsForCall(_site, 8), isNull);
    expect(controller.reactionsForCall('https://another.example', 7), isNull);
    expect(controller.reactionsForCall(_site, 7), isNotNull);
  });

  test(
    'active call sends its session and receives each remote reaction once',
    () async {
      final reactions = controller.callReactions!;
      await reactions.load();
      await reactions.send('heart');
      final request = transport.writes.singleWhere(
        (request) => request.path.endsWith('/reaction.json'),
      );
      expect(request.body, {
        'emoji': 'heart',
        'participant_session_id': 'mesh-participant-session',
      });
      channels.deliver('/voice/rooms/7', {
        'type': 'reaction',
        'user_id': 1,
        'username': 'sam',
        'emoji': 'heart',
      });
      channels.deliver('/voice/rooms/7', {
        'type': 'reaction',
        'user_id': 2,
        'username': 'alex',
        'emoji': 'clap',
      });
      expect(reactions.reactions.map((reaction) => reaction.emoji), [
        'heart',
        'clap',
      ]);
      await controller.leave();
      expect(controller.callReactions, isNull);
      expect(reactions.isCurrent, isFalse);
      expect(reactions.reactions, isEmpty);
    },
  );

  test(
    'account replacement while credentials wait cannot send to old call',
    () async {
      final reactions = controller.callReactions!;
      await reactions.load();
      requests.gate = Completer<void>();
      final started = Completer<void>();
      requests.started = started;
      final pending = reactions.send('clap');
      await started.future;
      requests.delegate.forget(_site);
      controller.forget(_site);
      requests.gate!.complete();
      await pending;
      expect(
        transport.writes.where(
          (request) => request.path.endsWith('/reaction.json'),
        ),
        isEmpty,
      );
      expect(reactions.isCurrent, isFalse);
    },
  );
}
