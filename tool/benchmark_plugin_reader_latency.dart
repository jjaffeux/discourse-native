import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:flutter/widgets.dart';

import '../test/plugins/gamification/gamification_fixture.dart';
import '../test/support/fakes.dart';
import '../test/support/voice_call_fakes.dart';
import '../test/support/voice_fake_chat_conversations.dart';

const _latency = Duration(milliseconds: 30);
const _site = 'https://forum.example';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    stdout.writeln(
      jsonEncode({
        'reopen_presented_chat_thread': await _median(_chatThread),
        'refresh_enabled_gamification_admin': await _median(_gamification),
        'join_voice_room_initially_muted': await _median(_joinMuted),
      }),
    );
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}

Future<int> _median(Future<int> Function() action) async {
  final times = <int>[];
  for (var i = 0; i < 7; i++) {
    final time = await action();
    if (i >= 2) times.add(time);
  }
  times.sort();
  return times[2];
}

Future<int> _chatThread() async {
  final api = _ThreadApi();
  final chat = ChatController(
    api: api,
    requests: PluginTestRequestHost(apiKeys: {_site: 'key'}),
    store: Store(),
    currentUserFor: (_) => _ThreadApi.reader,
  );
  const target = ChatThreadTarget(channelId: 9, threadId: 3);
  final reader = chat.acquireReader(_site, target, readerId: 'visible-reader');
  try {
    await reader.open();
    api.reloading = true;
    final watch = Stopwatch()..start();
    await reader.open(force: true);
    watch.stop();
    if (chat.thread(_site, 3)?.title != 'Latest title' ||
        reader.messages.single.cooked != '<p>Updated message</p>' ||
        reader.stream.loading ||
        api.threadReads != 2 ||
        api.messageReads != 2) {
      throw StateError('Thread and messages did not refresh');
    }
    return watch.elapsedMicroseconds;
  } finally {
    reader.dispose();
    chat.dispose();
  }
}

final class _ThreadApi extends FakeDiscourseApi {
  _ThreadApi() : super(user: reader);
  static const reader = DiscourseUser(id: 1, username: 'reader');
  bool reloading = false;
  int threadReads = 0;
  int messageReads = 0;

  @override
  Future<ChatThread> chatThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
    String? apiKey,
    String? clientId,
  }) async {
    threadReads++;
    if (reloading) await Future<void>.delayed(_latency);
    return ChatThread(
      id: 3,
      channelId: 9,
      status: 'open',
      replyCount: 1,
      title: reloading ? 'Latest title' : 'Initial title',
    );
  }

  @override
  Future<ChatMessagePage> chatThreadMessages({
    required String siteUrl,
    required int channelId,
    required int threadId,
    int? before,
    int? after,
    int? targetMessageId,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  }) async {
    messageReads++;
    if (reloading) await Future<void>.delayed(_latency);
    return (
      messages: [
        ChatMessage(
          id: 14,
          channelId: 9,
          threadId: 3,
          cooked: reloading
              ? '<p>Updated message</p>'
              : '<p>Initial message</p>',
          author: const ChatMessageAuthor(id: 1, username: 'reader'),
        ),
      ],
      canLoadMorePast: false,
      canLoadMoreFuture: false,
      targetMessageId: null,
    );
  }
}

Future<int> _gamification() async {
  final fixture = GamificationFixture();
  final admin = fixture.controller.acquireAdmin(gameSite);
  const paths = [
    'GET /admin/site_settings.json?plugin=discourse-gamification',
    'GET /admin/plugins/discourse-gamification/leaderboards.json',
  ];
  final reads = <String>[];
  for (final path in paths) {
    final read = fixture.transport.responders[path]!;
    fixture.transport.responders[path] = (request) async {
      reads.add(path);
      await Future<void>.delayed(_latency);
      return read(request);
    };
  }
  try {
    final watch = Stopwatch()..start();
    await admin.refresh();
    watch.stop();
    if (admin.settings?.enabled != true ||
        admin.index?.boards.single.board.name != 'Community champions' ||
        admin.loading ||
        admin.error != null ||
        reads.length != 2 ||
        reads.toSet().length != 2) {
      throw StateError('Settings and leaderboard list did not load');
    }
    return watch.elapsedMicroseconds;
  } finally {
    admin.release();
    fixture.dispose();
  }
}

Map<String, dynamic> _voiceFixture(String name) =>
    jsonDecode(File('test/fixtures/voice/$name.json').readAsStringSync())
        as Map<String, dynamic>;

Future<int> _joinMuted() async {
  final payload = _voiceFixture('join_mesh');
  (payload['room'] as Map<String, dynamic>)['room_type'] = 'stage';
  int states = 0;
  final transport = RecordingPluginTransport(
    responses: {
      'POST /voice/rooms/7/join.json': payload,
      'DELETE /voice/rooms/7/leave.json': {},
    },
    responders: {
      'POST /voice/rooms/7/state.json': (request) async {
        if (request.body['muted'] != true) {
          throw StateError('Joined as an unmuted listener');
        }
        await Future<void>.delayed(_latency);
        states++;
        return {};
      },
    },
  );
  final media = FakeVoiceMediaFactory();
  final system = _DelayedSystemCall();
  final controller = VoiceController(
    api: VoiceApi(transport, namespaceFor: (_) => VoiceNamespace.voice),
    requests: PluginTestRequestHost(apiKeys: {_site: 'key'}),
    trackerFor: (_) => null,
    chatConversations: FakeChatConversationCapability(),
    userIdFor: (_) => 1,
    onCallSiteChanged: () {},
    mediaFactory: media,
    systemCall: system,
    preferences: FakeVoicePreferences(),
  );
  try {
    final watch = Stopwatch()..start();
    await controller.join(
      siteUrl: _site,
      siteName: 'Forum',
      room: VoiceRoom.fromJson(payload['room'] as Map<String, dynamic>),
    );
    watch.stop();
    if (controller.call?.status != VoiceCallStatus.connected ||
        controller.call?.muted != true ||
        !media.sessions.single.muted ||
        system.systemMuted != true ||
        system.muteCalls != 1 ||
        system.connectedCalls != 1 ||
        states != 1) {
      throw StateError('Voice join did not settle both muted states');
    }
    return watch.elapsedMicroseconds;
  } finally {
    await controller.close();
  }
}

final class _DelayedSystemCall extends FakeVoiceSystemCall {
  int muteCalls = 0;

  @override
  Future<void> setMuted(bool muted) async {
    muteCalls++;
    await Future<void>.delayed(_latency);
    await super.setMuted(muted);
  }
}
