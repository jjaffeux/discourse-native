import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_conversation.dart';
import 'package:discourse_native/src/plugins/chat/chat_conversation_contract.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://chat.example.com';

final class _ConversationApi extends FakeDiscourseApi {
  _ConversationApi()
    : super(
        chatChannelsById: const {
          42: ChatChannel(
            id: 42,
            title: 'Room chat',
            kind: ChatChannelKind.category,
            membership: ChatMembership(following: true),
            threadingEnabled: true,
          ),
        },
        chatThreadsByKey: const {
          '42~99': ChatThread(
            id: 99,
            channelId: 42,
            status: 'open',
            replyCount: 2,
            messageBusLastId: 700,
            membership: ChatThreadMembership(
              threadId: 99,
              lastReadMessageId: 5,
            ),
          ),
        },
        chatMessagesByKey: {
          'thread-42-99': _page([10], canLoadMorePast: true),
          'thread-42-99~past~10': _page([5]),
        },
      );

  final List<({int channelId, int threadId, int messageId})> threadReads = [];

  @override
  Future<void> markChatThreadRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required int messageId,
    String? clientId,
  }) async {
    threadReads.add((
      channelId: channelId,
      threadId: threadId,
      messageId: messageId,
    ));
  }
}

ChatMessagePage _page(List<int> ids, {bool canLoadMorePast = false}) => (
  messages: [
    for (final id in ids)
      ChatMessage(
        id: id,
        channelId: 42,
        threadId: 99,
        cooked: '<p>Message $id</p>',
        author: const ChatMessageAuthor(id: 2, username: 'sam'),
      ),
  ],
  canLoadMorePast: canLoadMorePast,
  canLoadMoreFuture: false,
  targetMessageId: null,
);

void main() {
  group('ChatControllerConversationCapability', () {
    test('rejects non-positive channel and thread identities', () {
      final fixture = _createChat();
      final capability = ChatControllerConversationCapability(fixture.chat);

      expect(
        () => capability.openThread(
          siteUrl: _siteUrl,
          channelId: 0,
          threadId: 99,
        ),
        throwsArgumentError,
      );
      expect(
        () => capability.openThread(
          siteUrl: _siteUrl,
          channelId: 42,
          threadId: -1,
        ),
        throwsArgumentError,
      );
    });

    test(
      'refreshes the thread, resumes its cursor, and marks it read',
      () async {
        final fixture = _openConversation();

        await fixture.conversation.refresh();
        await pumpEventQueue();

        expect(
          fixture.conversation.value.messages.map((message) => message.id),
          [10],
        );
        expect(fixture.conversation.value.canLoadMorePast, isTrue);
        expect(fixture.api.chatChannelDetailsRequested, [42]);
        expect(fixture.api.chatThreadsRequested, [
          (channelId: 42, threadId: 99),
        ]);
        expect(fixture.api.threadReads, [
          (channelId: 42, threadId: 99, messageId: 10),
        ]);
        expect(fixture.tracker.pluginChannelLastIds['/chat/42/thread/99'], 700);
      },
    );

    test('prepends an older thread page to the held conversation', () async {
      final fixture = _openConversation();
      await fixture.conversation.refresh();

      await fixture.conversation.loadOlder();

      expect(fixture.conversation.value.messages.map((message) => message.id), [
        5,
        10,
      ]);
    });

    test('trims outgoing text and retains its thread identity', () async {
      final fixture = _openConversation();
      await fixture.conversation.refresh();

      await fixture.conversation.send('  hello room  ');

      expect(fixture.api.chatMessagesSent.single.message, 'hello room');
      expect(fixture.api.chatMessagesSent.single.threadId, 99);
    });

    test('closing releases only the conversation view subscription', () async {
      final fixture = _openConversation();
      await fixture.conversation.refresh();
      await fixture.conversation.send('hello room');
      expect(
        fixture.tracker.pluginChannelCallbacks['/chat/42/thread/99'],
        hasLength(2),
        reason: 'the view and optimistic-send reconciliation retain it',
      );

      fixture.conversation.close();

      expect(
        fixture.tracker.pluginChannelCallbacks['/chat/42/thread/99'],
        hasLength(1),
      );
    });
  });
}

({
  _ConversationApi api,
  ChatController chat,
  ChatConversation conversation,
  FakeSiteTracker tracker,
})
_openConversation() {
  final fixture = _createChat();
  final conversation = ChatControllerConversationCapability(
    fixture.chat,
  ).openThread(siteUrl: _siteUrl, channelId: 42, threadId: 99);
  addTearDown(conversation.close);
  return (
    api: fixture.api,
    chat: fixture.chat,
    conversation: conversation,
    tracker: fixture.tracker,
  );
}

({_ConversationApi api, ChatController chat, FakeSiteTracker tracker})
_createChat() {
  final api = _ConversationApi();
  final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
  final chat = ChatController(
    api: api,
    requests: FakePluginRequestHost(credentials: credentials),
    store: Store(),
    currentUserFor: (_) => const DiscourseUser(id: 7, username: 'reader'),
    minimumWindowRefreshInterval: Duration.zero,
  );
  addTearDown(chat.dispose);
  final tracker = FakeSiteTracker(
    siteUrl: _siteUrl,
    onIncomingTopics: () {},
    onNotifications: (_) {},
    onReviewableCounts: (_) {},
    userId: 7,
    apiKey: 'key',
  );
  chat.attachTracker(_siteUrl, tracker);
  return (api: api, chat: chat, tracker: tracker);
}
