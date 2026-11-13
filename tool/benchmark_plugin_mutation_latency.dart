import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread_directory.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_models.dart';
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
        'save_gamification_leaderboard': await _median(_saveLeaderboard),
        'browse_all_chat_threads': await _median(_browseThreads),
        'report_voice_participant': await _median(_reportParticipant),
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

Future<int> _saveLeaderboard() async {
  final fixture = GamificationFixture();
  final admin = fixture.controller.acquireAdmin(gameSite);
  try {
    await admin.refresh();
    final priorReads = fixture.transport.reads.length;
    var confirmed = false;
    const put = 'PUT /admin/plugins/gamification/leaderboard/1.json';
    const detail =
        'GET /admin/plugins/discourse-gamification/leaderboards/1.json';
    const index = 'GET /admin/plugins/discourse-gamification/leaderboards.json';
    final write = fixture.transport.responders[put]!;
    fixture.transport.responders[put] = (request) async {
      await Future<void>.delayed(_latency);
      final result = write(request);
      confirmed = true;
      return result;
    };
    for (final path in [detail, index]) {
      final read = fixture.transport.responders[path]!;
      fixture.transport.responders[path] = (request) async {
        if (!confirmed) throw StateError('Verification read preceded save');
        await Future<void>.delayed(_latency);
        return read(request);
      };
    }
    final watch = Stopwatch()..start();
    final result = await admin.saveBoard(
      1,
      GamificationBoardDraft(name: 'Quarterly winners'),
    );
    watch.stop();
    if (result.status.name != 'saved' ||
        admin.index?.boards.single.board.name != 'Quarterly winners' ||
        fixture.transport.writes.length != 1 ||
        fixture.transport.reads.length != priorReads + 2 ||
        fixture.transport.reads
            .skip(priorReads)
            .map((read) => 'GET ${read.path}')
            .toSet()
            .difference({detail, index})
            .isNotEmpty) {
      throw StateError('Leaderboard save did not verify and publish');
    }
    return watch.elapsedMicroseconds;
  } finally {
    admin.release();
    fixture.dispose();
  }
}

Future<int> _browseThreads() async {
  final api = _ThreadApi();
  final chat = ChatController(
    api: api,
    requests: PluginTestRequestHost(apiKeys: {_site: 'key'}),
    store: Store(),
    currentUserFor: (_) => _ThreadApi.reader,
  );
  final directory = ChatThreadDirectory(chat, _site);
  try {
    final watch = Stopwatch()..start();
    await directory.load();
    watch.stop();
    if (!directory.loaded ||
        directory.error(null) != null ||
        directory.hasMore(null) ||
        directory.threads.map((thread) => thread.channelId).join(',') !=
            '1,2,3,4' ||
        api.browseReads != 1 ||
        api.threadReads.length != 4 ||
        api.threadReads.toSet().length != 4) {
      throw StateError('Directory did not publish all four channels in order');
    }
    return watch.elapsedMicroseconds;
  } finally {
    directory.dispose();
    chat.dispose();
  }
}

final class _ThreadApi extends FakeDiscourseApi {
  _ThreadApi() : super(user: reader);
  static const reader = DiscourseUser(id: 1, username: 'reader');
  int browseReads = 0;
  final threadReads = <int>[];

  @override
  Future<ChatChannelBrowsePage> browseChatChannels({
    required String siteUrl,
    required String apiKey,
    String filter = '',
    ChatChannelBrowseStatus status = ChatChannelBrowseStatus.all,
    int offset = 0,
    int limit = ChatChannelBrowsePage.pageSize,
    String? clientId,
  }) async {
    browseReads++;
    await Future<void>.delayed(_latency);
    return ChatChannelBrowsePage(
      channels: [
        for (var id = 1; id <= 4; id++)
          ChatChannel(
            id: id,
            title: 'Channel $id',
            kind: ChatChannelKind.category,
            threadingEnabled: true,
          ),
      ],
    );
  }

  @override
  Future<ChatThreadPage> chatChannelThreads({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    int offset = 0,
    int limit = ChatThreadPage.pageSize,
    String? clientId,
  }) async {
    threadReads.add(channelId);
    await Future<void>.delayed(_latency);
    return ChatThreadPage(
      threads: [
        ChatThread(
          id: channelId,
          channelId: channelId,
          status: 'open',
          replyCount: 1,
          lastMessageId: channelId * 10 + 1,
          originalMessage: ChatThreadOriginalMessage(
            id: channelId * 10,
            channelId: channelId,
            author: const ChatMessageAuthor(id: 2, username: 'sam'),
            excerpt: 'Original message',
          ),
          title: 'Thread $channelId',
        ),
      ],
    );
  }
}

Map<String, dynamic> _voiceFixture(String name) =>
    jsonDecode(File('test/fixtures/voice/$name.json').readAsStringSync())
        as Map<String, dynamic>;

Future<int> _reportParticipant() async {
  final transport = RecordingPluginTransport(
    responses: {
      'POST /voice/rooms/7/join.json': _voiceFixture('join_mesh'),
      'POST /voice/rooms/7/state.json': {},
      'DELETE /voice/rooms/7/leave.json': {},
    },
    responders: {
      'GET /site.json': (_) async {
        await Future<void>.delayed(_latency);
        return {
          'post_action_types': [
            {'name_key': 'notify_moderators', 'id': 7},
          ],
        };
      },
      'POST /voice/rooms/7/flag.json': (_) async {
        await Future<void>.delayed(_latency);
        return {};
      },
    },
  );
  final args = <Symbol, Object?>{
    #api: VoiceApi(transport, namespaceFor: (_) => VoiceNamespace.voice),
    #requests: PluginTestRequestHost(apiKeys: {_site: 'key'}),
    #trackerFor: (String _) => null,
    #chatConversations: FakeChatConversationCapability(),
    #userIdFor: (String _) => 1,
    #onCallSiteChanged: () {},
    #mediaFactory: FakeVoiceMediaFactory(),
    #systemCall: FakeVoiceSystemCall(),
    #preferences: FakeVoicePreferences(),
  };
  List<PostFlagType> catalog(String site) => [
    if (site == _site)
      const PostFlagType(
        id: 7,
        nameKey: 'notify_moderators',
        name: 'Something Else',
        description: 'Notify the moderators',
      ),
  ];
  // Older baselines construct the same controller without the catalog port.
  VoiceController controller;
  try {
    controller =
        Function.apply(VoiceController.new, [], {
              ...args,
              #postFlagCatalog: catalog,
            })
            as VoiceController;
  } on NoSuchMethodError {
    controller =
        Function.apply(VoiceController.new, [], args) as VoiceController;
  }
  try {
    await controller.join(
      siteUrl: _site,
      siteName: 'Forum',
      room: VoiceRoom.fromJson(_voiceFixture('room')),
    );
    final watch = Stopwatch()..start();
    final reported = await controller.flagParticipant(2, 'Please review');
    watch.stop();
    final report = transport.writes
        .where((request) => request.path == '/voice/rooms/7/flag.json')
        .single;
    if (!reported ||
        report.body['user_id'] != 2 ||
        report.body['flag_type_id'] != 7 ||
        report.body['message'] != 'Please review') {
      throw StateError('Participant report did not reach the server');
    }
    return watch.elapsedMicroseconds;
  } finally {
    await controller.close();
  }
}
