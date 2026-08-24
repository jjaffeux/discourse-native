import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview.dart';
import 'package:flutter_test/flutter_test.dart';

const siteUrl = 'https://meta.discourse.org';

ChatMessage message({
  String cooked = '<p>Hello</p>',
  List<ChatReaction> reactions = const [
    ChatReaction(emoji: 'heart', count: 2, reacted: true),
  ],
  Bookmark? bookmark,
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
  bookmark: bookmark,
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
    'bookmark changes replace the record and mutation helpers preserve it',
    () {
      const bookmark = Bookmark(
        id: 81,
        bookmarkableId: 7,
        bookmarkableType: 'Chat::Message',
        name: 'Later',
      );
      final store = Store()..put(siteUrl, message());
      final ref = store.ref<ChatMessage>(siteUrl, 7);
      var changes = 0;
      ref.addListener(() => changes++);

      store.put(siteUrl, message(bookmark: bookmark));
      final held = ref.value!;

      expect(changes, 1);
      expect(held.bookmark, bookmark);
      expect(held.withReaction('clap', reacted: true).bookmark, bookmark);
      expect(
        held.withDeletedAt(DateTime.utc(2026, 8, 8, 12)).bookmark,
        bookmark,
      );
      expect(held.withBookmark(null).bookmark, isNull);
      expect(message(), isNot(message(bookmark: bookmark)));
    },
  );

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
        preview: const SourceFallback(
          '**Hello**',
          ChatPreviewFallbackReason.unsupportedSyntax,
        ),
        author: const ChatMessageAuthor(id: 1, username: 'sam'),
        createdAt: createdAt,
      );
      store.put(siteUrl, optimistic);
      final ref = store.ref<ChatMessage>(siteUrl, -1);
      final preview = optimistic.preview;
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
      expect(ref.value?.preview, same(preview));
      expect(ref.value?.canonicalReceived, isFalse);

      store.put(siteUrl, ref.value!.withCanonical(message()));

      expect(changes, 2);
      expect(ref.value?.id, -1);
      expect(ref.value?.serverId, 7);
      expect(ref.value?.cooked, '<p>Hello</p>');
      expect(ref.value?.delivery, ChatMessageDelivery.sent);
      expect(ref.value?.sendError, isNull);
      expect(ref.value?.deliveryUncertain, isFalse);
      expect(ref.value?.preview, same(preview));
      expect(ref.value?.canonicalReceived, isTrue);
    },
  );

  test('an empty canonical body is still an authoritative arrival', () {
    final optimistic = ChatMessage.optimistic(
      id: -1,
      channelId: 3,
      raw: 'Hello',
      stagedId: 'native-1',
      preview: const SourceFallback(
        'Hello',
        ChatPreviewFallbackReason.unsupportedSyntax,
      ),
      author: const ChatMessageAuthor(id: 1, username: 'sam'),
      createdAt: DateTime.utc(2026, 8, 8, 11),
    );

    final reconciled = optimistic.withCanonical(message(cooked: ''));

    expect(optimistic.canonicalReceived, isFalse);
    expect(reconciled.cooked, isEmpty);
    expect(reconciled.canonicalReceived, isTrue);
    expect(reconciled.preview, same(optimistic.preview));
  });

  test('raw text and staged correlation participate in message equality', () {
    final createdAt = DateTime.utc(2026, 8, 8, 11);
    const preview = SourceFallback(
      'Hello',
      ChatPreviewFallbackReason.unsupportedSyntax,
    );
    ChatMessage optimistic({
      String raw = 'Hello',
      String stagedId = 'native-1',
    }) => ChatMessage.optimistic(
      id: -1,
      channelId: 3,
      raw: raw,
      stagedId: stagedId,
      preview: preview,
      author: const ChatMessageAuthor(id: 1, username: 'sam'),
      createdAt: createdAt,
    );

    expect(optimistic(), optimistic());
    expect(optimistic(), isNot(optimistic(raw: 'Edited')));
    expect(optimistic(), isNot(optimistic(stagedId: 'native-2')));
  });

  test('optimistic thread messages retain their thread identity', () {
    final optimistic = ChatMessage.optimistic(
      id: -1,
      channelId: 3,
      threadId: 22,
      raw: 'Hello',
      stagedId: 'native-1',
      preview: const SourceFallback(
        'Hello',
        ChatPreviewFallbackReason.unsupportedSyntax,
      ),
      author: const ChatMessageAuthor(id: 1, username: 'sam'),
      createdAt: DateTime.utc(2026, 8, 8, 11),
    );

    expect(optimistic.threadId, 22);
  });

  test(
    'thread preview and deletion helpers preserve unrelated message data',
    () {
      final original = message();
      const thread = ChatThreadPreview(threadId: 22, replyCount: 3);
      final deletedAt = DateTime.utc(2026, 8, 8, 12);

      final updated = original
          .withThreadPreview(thread)
          .withDeletedAt(deletedAt);

      expect(updated.thread, thread);
      expect(updated.deletedAt, deletedAt);
      expect(updated.cooked, original.cooked);
      expect(updated.author, original.author);
      expect(updated.reactions, original.reactions);
    },
  );

  test('outgoing text never infers trusted preview metadata', () {
    final outgoing = OutgoingChatMessage.text(
      '![cat](https://media.example/cat.gif)',
    );

    expect(outgoing.raw, '![cat](https://media.example/cat.gif)');
    expect(outgoing.trustedPreviewSeed, isNull);
  });

  test('trusted GIF input carries validated typed metadata', () {
    final outgoing = OutgoingChatMessage.trustedGif(
      raw: '![cat](https://media.example/cat.gif)',
      url: 'https://media.example/cat.gif',
      title: 'cat',
      width: 320,
      height: 180,
    );

    final seed = outgoing.trustedPreviewSeed as TrustedGifPreviewSeed;
    expect(seed.url, Uri.parse('https://media.example/cat.gif'));
    expect(seed.title, 'cat');
    expect(seed.width, 320);
    expect(seed.height, 180);
  });

  test('trusted GIF input rejects unsafe or incomplete metadata', () {
    expect(
      () => OutgoingChatMessage.trustedGif(
        raw: 'image',
        url: 'javascript:alert(1)',
        title: 'cat',
        width: 320,
        height: 180,
      ),
      throwsArgumentError,
    );
    expect(
      () => OutgoingChatMessage.trustedGif(
        raw: 'image',
        url: 'https://media.example/cat.gif',
        title: '',
        width: 0,
        height: 180,
      ),
      throwsArgumentError,
    );
  });
}
