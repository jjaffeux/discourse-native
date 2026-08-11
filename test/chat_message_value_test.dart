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
}
