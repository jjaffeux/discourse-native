import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

const siteUrl = 'https://meta.discourse.org';

ChatMessage message({
  String cooked = '<p>Hello</p>',
  List<ChatReaction> reactions = const [
    ChatReaction(emoji: 'heart', count: 2, reacted: true),
  ],
}) => ChatMessage(
  id: 7,
  channelId: 3,
  cooked: cooked,
  author: const ChatMessageAuthor(
    id: 1,
    username: 'sam',
    name: 'Sam',
    avatarUrl: 'https://meta.discourse.org/avatar.png',
    isStaff: true,
  ),
  createdAt: DateTime.utc(2026, 8, 8, 10),
  edited: true,
  replyTo: const ChatReplyTo(
    id: 6,
    userId: 3,
    excerpt: 'Earlier',
    username: 'alex',
  ),
  reactions: reactions,
);

void main() {
  test('an unchanged overlapping message retains its stored record', () {
    final store = Store();
    final first = store.put(siteUrl, message());
    final ref = store.ref<ChatMessage>(siteUrl, first.id);
    var changes = 0;
    ref.addListener(() => changes++);

    final merged = store.put(siteUrl, message());

    expect(merged, same(first));
    expect(changes, 0);
  });

  test('message content and reaction changes still replace the record', () {
    final store = Store();
    store.put(siteUrl, message());
    final ref = store.ref<ChatMessage>(siteUrl, 7);
    var changes = 0;
    ref.addListener(() => changes++);

    store.put(siteUrl, message(cooked: '<p>Edited</p>'));
    store.put(
      siteUrl,
      message(
        cooked: '<p>Edited</p>',
        reactions: const [ChatReaction(emoji: 'heart', count: 3)],
      ),
    );

    expect(changes, 2);
    expect(ref.value?.cooked, '<p>Edited</p>');
    expect(ref.value?.reactions.single.count, 3);
  });

  test(
    'optimistic identity and send-state changes replace the local record',
    () {
      final store = Store();
      final createdAt = DateTime.utc(2026, 8, 8, 11);
      final optimistic = ChatMessage.optimistic(
        id: -1,
        channelId: 3,
        raw: '**Hello**',
        stagedId: 'native-1',
        author: const ChatMessageAuthor(id: 1, username: 'sam'),
        createdAt: createdAt,
      );
      store.put(siteUrl, optimistic);
      final ref = store.ref<ChatMessage>(siteUrl, -1);
      var changes = 0;
      ref.addListener(() => changes++);

      store.put(
        siteUrl,
        optimistic.withSendState(
          delivery: ChatMessageDelivery.failed,
          error: "Couldn't reach the site.",
          deliveryUncertain: true,
        ),
      );

      expect(changes, 1);
      expect(ref.value?.id, -1);
      expect(ref.value?.optimisticRaw, '**Hello**');
      expect(ref.value?.stagedId, 'native-1');
      expect(ref.value?.delivery, ChatMessageDelivery.failed);
      expect(ref.value?.sendError, "Couldn't reach the site.");
      expect(ref.value?.deliveryUncertain, isTrue);

      store.put(siteUrl, ref.value!.withCanonical(message()));

      expect(changes, 2);
      expect(ref.value?.id, -1);
      expect(ref.value?.serverId, 7);
      expect(ref.value?.cooked, '<p>Hello</p>');
      expect(ref.value?.delivery, ChatMessageDelivery.sent);
      expect(ref.value?.sendError, isNull);
      expect(ref.value?.deliveryUncertain, isFalse);
    },
  );

  test('raw text and staged correlation participate in message equality', () {
    final createdAt = DateTime.utc(2026, 8, 8, 11);
    ChatMessage optimistic({
      String raw = 'Hello',
      String stagedId = 'native-1',
    }) => ChatMessage.optimistic(
      id: -1,
      channelId: 3,
      raw: raw,
      stagedId: stagedId,
      author: const ChatMessageAuthor(id: 1, username: 'sam'),
      createdAt: createdAt,
    );

    expect(optimistic(), optimistic());
    expect(optimistic(), isNot(optimistic(raw: 'Edited')));
    expect(optimistic(), isNot(optimistic(stagedId: 'native-2')));
  });
}
