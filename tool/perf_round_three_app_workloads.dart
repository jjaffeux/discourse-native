import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';

import '../test/support/fakes.dart';

const roundThreeSite = 'https://meta.discourse.org';

Future<({ChatController chat, Store store})> roundThreeChatFixture({
  int messages = 300,
}) async {
  final store = Store();
  final api = FakeDiscourseApi(
    chatChannelsBySite: {
      roundThreeSite: ChatChannels(
        public: [
          for (var i = 1; i <= 10; i++)
            ChatChannel(
              id: i,
              title: 'Channel $i',
              kind: ChatChannelKind.category,
            ),
        ],
      ),
    },
  );
  final chat = ChatController(
    api: api,
    requests: FakePluginRequestHost(
      credentials: FakeApiCredentialReader()..keys[roundThreeSite] = 'key',
    ),
    store: store,
  );
  await chat.loadChannels(roundThreeSite);
  store.putAll(roundThreeSite, [
    for (var i = 0; i < messages; i++)
      ChatMessage(
        id: i + 1,
        channelId: i % 10 + 1,
        cooked:
            '<p>Release &amp; keyboard <strong>focus</strong> '
            '<img class="emoji" alt=":wave:" src="/wave.png"></p>',
        author: const ChatMessageAuthor(id: 1, username: 'reader'),
      ),
  ]);
  return (chat: chat, store: store);
}

Future<Map<String, int>> measureRoundThreeAppPerformance() async {
  final results = <String, int>{};
  for (final count in [30, 300]) {
    final fixture = await roundThreeChatFixture(messages: count);
    try {
      var query = 0;
      void search() {
        final mode = query++ % 3;
        final word = ['keyboard', 'release focus', 'absentneedle'][mode];
        fixture.chat.inboxFilters.setSidebarQuery(roundThreeSite, word);
        final selected = fixture.chat.sidebarConversations(roundThreeSite);
        final expected = mode == 2 ? 0 : 10;
        if (selected.length != expected ||
            selected.map((channel) => channel.id).toSet().length != expected) {
          throw StateError('Chat search results changed');
        }
      }

      for (var i = 0; i < 10; i++) {
        search();
      }
      final watch = Stopwatch()..start();
      for (var i = 0; i < 300; i++) {
        search();
      }
      results['chat_sidebar_search_$count'] = watch.elapsedMicroseconds;
    } finally {
      fixture.chat.dispose();
    }
  }
  final cold = await roundThreeChatFixture(messages: 0);
  try {
    void searchCold() {
      cold.store.putAll(roundThreeSite, [
        for (var i = 0; i < 30; i++)
          ChatMessage(
            id: i + 1,
            channelId: i % 10 + 1,
            cooked: '<p>Fresh <strong>keyboard</strong> focus &amp; notes</p>',
            author: const ChatMessageAuthor(id: 1, username: 'reader'),
          ),
      ]);
      cold.chat.inboxFilters.setSidebarQuery(roundThreeSite, 'keyboard');
      if (cold.chat.sidebarConversations(roundThreeSite).length != 10) {
        throw StateError('Cold chat search changed');
      }
    }

    for (var i = 0; i < 10; i++) {
      searchCold();
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < 300; i++) {
      searchCold();
    }
    results['chat_sidebar_search_cold'] = watch.elapsedMicroseconds;
  } finally {
    cold.chat.dispose();
  }
  return results;
}
