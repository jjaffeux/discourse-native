import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_reactions.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:discourse_plugin_api/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const _settings = VoiceReactionSettings(emojis: ['heart', 'clap']);

VoiceReactionSession _session({
  Future<void> Function(String)? send,
  bool Function()? isCurrent,
  VoiceReactionSettings settings = _settings,
}) => VoiceReactionSession(
  siteUrl: 'https://example.com',
  roomId: 7,
  userId: 1,
  username: 'sam',
  isCurrent: isCurrent ?? () => true,
  load: () async => settings,
  send: send ?? (_) async {},
);

void main() {
  test('site serializer controls offered reactions and arbitrary emoji', () {
    final settings = VoiceReactionSettings.fromJson({
      'live_reaction_emojis': ['heart', 'custom_party', 'heart', null, '../x'],
      'live_reactions_allow_any_emoji': true,
    });
    expect(settings.emojis, ['heart', 'custom_party']);
    expect(settings.allows('clap:t3'), isTrue);
    expect(settings.allows('custom_party'), isTrue);
    expect(settings.allows('../secret'), isFalse);
    expect(VoiceReactionSettings.fromJson({}).supported, isFalse);
    expect(_settings.allows('clap:t3'), isFalse);
  });

  test('reaction API uses active namespace and participant session', () async {
    final transport = RecordingPluginTransport(
      responses: {
        'GET /site.json': {
          'live_reaction_emojis': ['clap'],
          'live_reactions_allow_any_emoji': true,
        },
        'POST /live/rooms/7/reaction.json': {},
      },
    );
    final api = VoiceApi(transport, namespaceFor: (_) => VoiceNamespace.live);
    final settings = await api.reactionSettings(
      siteUrl: 'https://example.com',
      apiKey: 'key',
    );
    expect(settings.emojis, ['clap']);
    expect(settings.allowAnyEmoji, isTrue);
    await api.reaction(
      siteUrl: 'https://example.com',
      apiKey: 'key',
      clientId: 'device',
      roomId: 7,
      emoji: 'clap:t3',
      participantSessionId: 'joined-session',
    );
    final request = transport.requests.last;
    expect(request.method, 'POST');
    expect(request.path, '/live/rooms/7/reaction.json');
    expect(request.clientId, 'device');
    expect(request.body, {
      'emoji': 'clap:t3',
      'participant_session_id': 'joined-session',
    });
  });

  testWidgets('reactions expire in hidden views and own echoes are ignored', (
    tester,
  ) async {
    final session = _session();
    addTearDown(session.dispose);
    await session.load();
    await session.send('heart');
    session.receive({'user_id': 1, 'username': 'sam', 'emoji': 'heart'});
    session.receive({'user_id': 2, 'username': 'alex', 'emoji': 'clap'});
    expect(session.reactions.map((reaction) => reaction.username), [
      'sam',
      'alex',
    ]);
    await tester.pump(const Duration(seconds: 4));
    expect(session.reactions, isEmpty);
  });

  testWidgets(
    'transient settings failure recovers and retired calls stop retrying',
    (tester) async {
      var attempts = 0;
      var current = true;
      final session = VoiceReactionSession(
        siteUrl: 'https://example.com',
        roomId: 7,
        userId: 1,
        username: 'sam',
        isCurrent: () => current,
        load: () async {
          attempts++;
          if (attempts == 1) throw StateError('deploy');
          return _settings;
        },
        send: (_) async {},
      );
      addTearDown(session.dispose);
      await session.load();
      expect(session.canSend, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(attempts, 2);
      expect(session.canSend, isTrue);
      current = false;
      session.dispose();
      await tester.pump(const Duration(seconds: 20));
      expect(attempts, 2);
    },
  );

  testWidgets('retiring a call cancels a pending settings retry', (
    tester,
  ) async {
    var attempts = 0;
    final session = VoiceReactionSession(
      siteUrl: 'https://example.com',
      roomId: 7,
      userId: 1,
      username: 'sam',
      isCurrent: () => true,
      load: () async {
        attempts++;
        throw StateError('offline');
      },
      send: (_) async {},
    );
    await session.load();
    session.dispose();
    await tester.pump(const Duration(seconds: 20));
    expect(attempts, 1);
  });

  testWidgets('rate limiting rolls back optimistic reaction and holds picker', (
    tester,
  ) async {
    var attempts = 0;
    final session = _session(
      send: (_) async {
        attempts++;
        throw const WriteException(
          WriteFailure.rateLimited,
          statusCode: 429,
          retryAfter: Duration(seconds: 8),
        );
      },
    );
    addTearDown(session.dispose);
    await session.load();
    await session.send('clap');
    expect(session.reactions, isEmpty);
    expect(session.canSend, isFalse);
    await session.send('heart');
    expect(attempts, 1);
    await tester.pump(const Duration(seconds: 7));
    expect(session.canSend, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(session.canSend, isTrue);
  });

  test(
    'feed is bounded and rejects malformed or retired-call events',
    () async {
      var current = true;
      final session = _session(isCurrent: () => current);
      addTearDown(session.dispose);
      await session.load();
      for (var index = 0; index < 50; index++) {
        session.receive({
          'user_id': index + 2,
          'username': 'u$index',
          'emoji': 'heart',
        });
      }
      expect(session.reactions.length, 40);
      expect(session.reactions.first.username, 'u10');
      session.receive({'user_id': 2, 'username': 'alex', 'emoji': '../x'});
      expect(session.reactions.last.username, 'u49');
      current = false;
      await session.send('clap');
      session.receive({'user_id': 2, 'username': 'alex', 'emoji': 'clap'});
      expect(session.reactions.last.username, 'u49');
    },
  );

  test(
    'settings completing for a retired call cannot enable reactions',
    () async {
      var current = true;
      final gate = Completer<VoiceReactionSettings>();
      final session = VoiceReactionSession(
        siteUrl: 'https://example.com',
        roomId: 7,
        userId: 1,
        username: 'sam',
        isCurrent: () => current,
        load: () => gate.future,
        send: (_) async => fail('retired call must not send'),
      );
      addTearDown(session.dispose);
      final loading = session.load();
      current = false;
      gate.complete(_settings);
      await loading;
      expect(session.settings, isNull);
      expect(session.canSend, isFalse);
    },
  );
}
