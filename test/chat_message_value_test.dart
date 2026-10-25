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
  test('action and page metadata survive local message updates', () {
    final plain = ChatMessage.fromJson(const {'id': 7}, siteUrl);
    final action = ChatMessage.fromJson(const {
      'id': 7,
      'is_action': true,
      'first_of_results': true,
      'thread': {'id': 3, 'force': true, 'reply_count': 1},
    }, siteUrl);
    expect(action, isNot(plain));
    expect(action.isAction, isTrue);
    expect(action.firstOfResults, isTrue);
    expect(action.thread!.force, isTrue);
    final updated = action
        .withReaction('heart', reacted: true)
        .withPinned(true)
        .withDeletedAt(DateTime.utc(2026))
        .withDeletedAt(null)
        .withReactions([])
        .withBookmark(null)
        .withUserFlagStatus(1)
        .withReviewableId(4)
        .withSendState(delivery: ChatMessageDelivery.sent)
        .withBookmarkOf(plain)
        .withPersonalizedStateOf(plain, currentUserId: 1);
    expect(updated.isAction, isTrue);
    expect(updated.firstOfResults, isTrue);
    expect(updated.thread!.force, isTrue);
    expect(plain.withCanonical(action).isAction, isTrue);
    expect(action.withCanonical(plain).isAction, isFalse);
  });

  group('Store<ChatMessage>', () {
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

    test('bookmark changes replace the stored record', () {
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
      expect(message(), isNot(message(bookmark: bookmark)));
    });

    test('only a report of participants replaces the held ones', () {
      const participants = [ChatMessageAuthor(id: 3, username: 'kris')];
      ChatMessage rootOf(int threadId, {int? count, bool users = false}) =>
          message().withThreadPreview(
            ChatThreadPreview(
              threadId: threadId,
              replyCount: 1,
              participantCount: count,
              participantUsers: users ? participants : const [],
            ),
          );
      final store = Store()..put(siteUrl, rootOf(3, count: 1, users: true));
      final ref = store.ref<ChatMessage>(siteUrl, 7);
      var changes = 0;
      ref.addListener(() => changes++);

      store.put(siteUrl, rootOf(3));
      expect(changes, 0);
      expect(ref.value?.thread?.participantCount, 1);
      expect(ref.value?.thread?.participantUsers, participants);

      store.put(siteUrl, rootOf(3, count: 0));
      expect(ref.value?.thread?.participantCount, 0);
      expect(ref.value?.thread?.participantUsers, isEmpty);

      store
        ..put(siteUrl, rootOf(3, count: 1, users: true))
        ..put(siteUrl, rootOf(4));
      expect(ref.value?.thread?.participantCount, isNull);
      expect(ref.value?.thread?.participantUsers, isEmpty);
    });

    test('mutation helpers preserve a bookmark until explicitly cleared', () {
      const bookmark = Bookmark(
        id: 81,
        bookmarkableId: 7,
        bookmarkableType: 'Chat::Message',
        name: 'Later',
      );
      final held = message(bookmark: bookmark);

      expect(held.withReaction('clap', reacted: true).bookmark, bookmark);
      expect(
        held.withDeletedAt(DateTime.utc(2026, 8, 8, 12)).bookmark,
        bookmark,
      );
      expect(held.withBookmark(null).bookmark, isNull);
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
  });

  group('ChatMessage value semantics', () {
    test('messages mentioning a user with a status hash by value', () {
      ChatMessage parse() => ChatMessage.fromJson(const {
        'id': 7,
        'chat_channel_id': 3,
        'cooked': '<p>Hi @alex</p>',
        'user': {'id': 1, 'username': 'sam'},
        'mentioned_users': [
          {
            'id': 3,
            'username': 'alex',
            'status': {'description': 'Travelling', 'emoji': 'airplane'},
          },
        ],
      }, siteUrl);
      final first = parse();
      final second = parse();

      expect(first.mentionedUserStatuses, isNotEmpty);
      expect(second, first);
      expect(second.hashCode, first.hashCode);
    });

    test(
      'local HTML updates notify rows without changing canonical content',
      () {
        final original = message();
        final pending = original.withPendingEdit(
          '**Local**',
          const SourceFallback(
            '**Local**',
            ChatPreviewFallbackReason.unsupportedSyntax,
          ),
        );
        final store = Store()..put(siteUrl, pending);
        final ref = store.ref<ChatMessage>(siteUrl, pending.id);
        var changes = 0;
        ref.addListener(() => changes++);
        final local = pending.withProvisionalCooked(
          '<p><strong>Local</strong></p>',
        );

        store.put(siteUrl, local);
        store.put(
          siteUrl,
          local.withProvisionalCooked(local.provisionalCooked!),
        );

        expect(changes, 1);
        expect(local.cooked, original.cooked);
        expect(local.raw, '**Local**');
        expect(local.canonicalReceived, isFalse);
        expect(local, isNot(pending));
        expect(
          local.hashCode,
          pending.withProvisionalCooked(local.provisionalCooked!).hashCode,
        );
        expect(
          local.withProvisionalCooked(local.provisionalCooked!),
          same(local),
        );

        final empty = local.withProvisionalCooked('');
        store.put(siteUrl, empty);
        expect(changes, 2);
        expect(empty.provisionalCooked, '');
        expect(empty, isNot(pending));
      },
    );

    test('unrelated message updates retain the locally cooked body', () {
      const html = '<p>Local</p>';
      const bookmark = Bookmark(
        id: 81,
        bookmarkableId: 7,
        bookmarkableType: 'Chat::Message',
      );
      final pending = ChatMessage.optimistic(
        id: -1,
        channelId: 3,
        raw: 'Local',
        stagedId: 'native-1',
        preview: const SourceFallback(
          'Local',
          ChatPreviewFallbackReason.unsupportedSyntax,
        ),
        provisionalCooked: html,
        author: const ChatMessageAuthor(id: 1, username: 'sam'),
        createdAt: DateTime.utc(2026, 9, 19),
      );
      final updated = pending
          .withReaction('heart', reacted: true, userId: 1)
          .withReactions(const [ChatReaction(emoji: 'heart', count: 2)])
          .withBookmark(bookmark)
          .withPinned(true)
          .withThreadPreview(
            const ChatThreadPreview(threadId: 3, replyCount: 1),
          )
          .withDeletedAt(DateTime.utc(2026, 9, 20))
          .withDeletedAt(null, clearDeletedById: true)
          .withUserFlagStatus(1)
          .withReviewableId(4)
          .withSendState(delivery: ChatMessageDelivery.failed, error: 'Offline')
          .withPersonalizedStateOf(pending, currentUserId: 1);

      expect(updated.provisionalCooked, html);
      expect(updated.id, pending.id);
      expect(updated.stagedId, pending.stagedId);
      expect(updated.canonicalReceived, isFalse);
      expect(updated.delivery, ChatMessageDelivery.failed);
      expect(updated.withBookmarkOf(message()).provisionalCooked, html);
    });

    test('new edits and canonical arrivals retire earlier local HTML', () {
      const fallback = SourceFallback(
        'Local',
        ChatPreviewFallbackReason.unsupportedSyntax,
      );
      final original = message();
      final first = original
          .withPendingEdit('Local', fallback)
          .withProvisionalCooked('<p>Local</p>');
      final second = first.withPendingEdit('Changed', fallback);
      expect(second.provisionalCooked, isNull);
      expect(second.canonicalReceived, isFalse);
      expect(second.withContentOf(first).provisionalCooked, '<p>Local</p>');
      final rolledBack = second.withPinned(true).withContentOf(original);
      expect(rolledBack.provisionalCooked, isNull);
      expect(rolledBack.canonicalReceived, isTrue);
      expect(rolledBack.pinned, isTrue);

      for (final cooked in ['', '<p>Canonical</p>']) {
        final canonical = first.withCanonical(message(cooked: cooked));
        expect(canonical.provisionalCooked, isNull);
        expect(canonical.cooked, cooked);
        expect(canonical.canonicalReceived, isTrue);
        expect(canonical.withProvisionalCooked('<p>Late</p>'), same(canonical));
      }
    });

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
  });

  group('OutgoingChatMessage preview trust', () {
    test('ordinary text never infers trusted preview metadata', () {
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

    for (final (label, url, title, width, height) in [
      ('unsupported scheme', 'ftp://media.example/cat.gif', 'cat', 320, 180),
      ('script URL', 'javascript:alert(1)', 'cat', 320, 180),
      ('relative URL', '/cat.gif', 'cat', 320, 180),
      ('missing host', 'https:/cat.gif', 'cat', 320, 180),
      ('malformed URL', 'https://[invalid', 'cat', 320, 180),
      ('fragment', 'https://media.example/cat.gif#part', 'cat', 320, 180),
      ('empty title', 'https://media.example/cat.gif', '', 320, 180),
      ('blank title', 'https://media.example/cat.gif', ' \t ', 320, 180),
      ('zero width', 'https://media.example/cat.gif', 'cat', 0, 180),
      ('negative width', 'https://media.example/cat.gif', 'cat', -1, 180),
      ('zero height', 'https://media.example/cat.gif', 'cat', 320, 0),
      ('negative height', 'https://media.example/cat.gif', 'cat', 320, -1),
      ('excessive width', 'https://media.example/cat.gif', 'cat', 10001, 180),
      ('excessive height', 'https://media.example/cat.gif', 'cat', 320, 10001),
    ]) {
      test('trusted GIF input rejects $label', () {
        expect(
          () => OutgoingChatMessage.trustedGif(
            raw: 'image',
            url: url,
            title: title,
            width: width,
            height: height,
          ),
          throwsArgumentError,
        );
      });
    }

    for (final scheme in ['http', 'https']) {
      for (final (width, height) in [(1, 10000), (10000, 1)]) {
        test('trusted GIF input accepts $scheme at ${width}x$height', () {
          final outgoing = OutgoingChatMessage.trustedGif(
            raw: 'image',
            url: '$scheme://media.example/cat.gif',
            title: 'cat',
            width: width,
            height: height,
          );
          final seed = outgoing.trustedPreviewSeed as TrustedGifPreviewSeed;
          expect(seed.url, Uri.parse('$scheme://media.example/cat.gif'));
          expect(seed.width, width);
          expect(seed.height, height);
        });
      }
    }
  });
}
