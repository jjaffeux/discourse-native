import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

const String site = 'https://meta.discourse.org';

/// A message as `Chat::MessageSerializer` writes one.
Map<String, dynamic> message({
  int id = 1,
  int channelId = 9,
  String cooked = '<p>Hi</p>',
  String createdAt = '2026-05-05T10:00:00.000Z',
  Map<String, dynamic>? user,
  bool? edited,
  String? deletedAt,
  Map<String, dynamic>? inReplyTo,
  Map<String, dynamic>? webhook,
  int? threadId,
  Map<String, dynamic>? thread,
  List<Map<String, dynamic>>? reactions,
  List<Map<String, dynamic>>? uploads,
}) => {
  'id': id,
  'chat_channel_id': channelId,
  'cooked': cooked,
  'created_at': createdAt,
  'excerpt': 'Hi',
  'user':
      user ??
      {
        'id': 2,
        'username': 'sam',
        'name': 'Sam',
        'avatar_template': '/user_avatar/s/{size}.png',
      },
  // Written only when true, and dropped otherwise.
  'edited': ?edited,
  'deleted_at': ?deletedAt,
  'in_reply_to': ?inReplyTo,
  'chat_webhook_event': ?webhook,
  'thread_id': ?threadId,
  'thread': ?thread,
  'reactions': ?reactions,
  'uploads': ?uploads,
};

Map<String, dynamic> page(
  List<Map<String, dynamic>> messages, {
  Object? canLoadMorePast,
  int? targetMessageId,
}) => {
  'messages': messages,
  'tracking': {
    'channel_tracking': <String, dynamic>{},
    'thread_tracking': <String, dynamic>{},
  },
  'meta': {
    'target_message_id': targetMessageId,
    'can_load_more_past': canLoadMorePast,
    'can_load_more_future': null,
  },
};

ChatMessage messageFrom(Map<String, dynamic> json) =>
    ChatMessage.fromJson(json, site);

void main() {
  group('changing this reader’s reactions', () {
    const author = ChatMessageAuthor(id: 2, username: 'sam');
    const message = ChatMessage(
      id: 1,
      channelId: 9,
      cooked: '<p>hello</p>',
      author: author,
      reactions: [
        ChatReaction(emoji: 'heart', count: 2, reacted: true),
        ChatReaction(emoji: 'clap', count: 1),
      ],
    );

    test('adds another reaction without replacing the one already held', () {
      final changed = message.withReaction('clap', reacted: true);

      expect(changed.reactions, const [
        ChatReaction(emoji: 'heart', count: 2, reacted: true),
        ChatReaction(emoji: 'clap', count: 2, reacted: true),
      ]);
    });

    test('removes only this reader and drops an empty reaction row', () {
      final decremented = message.withReaction('heart', reacted: false);
      final dropped = const ChatMessage(
        id: 1,
        channelId: 9,
        cooked: '<p>hello</p>',
        author: author,
        reactions: [ChatReaction(emoji: 'heart', count: 1, reacted: true)],
      ).withReaction('heart', reacted: false);

      expect(decremented.reactions, const [
        ChatReaction(emoji: 'heart', count: 1),
        ChatReaction(emoji: 'clap', count: 1),
      ]);
      expect(dropped.reactions, isEmpty);
    });

    test(
      'appends a reaction absent from the server record and is idempotent',
      () {
        final added = message.withReaction('tada', reacted: true);

        expect(
          added.reactions.last,
          const ChatReaction(emoji: 'tada', count: 1, reacted: true),
        );
        expect(
          identical(added.withReaction('tada', reacted: true), added),
          isTrue,
        );
      },
    );
  });

  group('reading a message', () {
    test('reads the author, the cooked body and when it was written', () {
      final read = messageFrom(message());

      expect(read.id, 1);
      expect(read.channelId, 9);
      expect(read.cooked, '<p>Hi</p>');
      expect(read.author.username, 'sam');
      expect(read.author.displayName, 'Sam');
      expect(read.author.avatarUrl, '$site/user_avatar/s/90.png');
      expect(read.createdAt, DateTime.parse('2026-05-05T10:00:00.000Z'));
    });

    test('falls back to the username where the site has no names', () {
      final read = messageFrom(
        message(user: const {'id': 2, 'username': 'sam'}),
      );

      expect(read.author.displayName, 'sam');
    });

    test('reads staff from any of the three flags the site writes', () {
      for (final flag in ['admin', 'moderator', 'staff']) {
        final read = messageFrom(
          message(user: {'id': 2, 'username': 'sam', flag: true}),
        );

        expect(read.author.isStaff, isTrue, reason: flag);
      }
      expect(messageFrom(message()).author.isStaff, isFalse);
    });

    test(
      'is edited only when the site said so, which it does by adding the key',
      () {
        expect(messageFrom(message()).edited, isFalse);
        expect(messageFrom(message(edited: true)).edited, isTrue);
      },
    );

    test('knows a deleted message, which only a moderator is ever sent', () {
      final read = messageFrom(message(deletedAt: '2026-05-05T11:00:00.000Z'));

      expect(read.isDeleted, isTrue);
      expect(messageFrom(message()).isDeleted, isFalse);
    });

    test(
      'remembers what a reply was replying to, because the chaining depends on it',
      () {
        final read = messageFrom(
          message(
            inReplyTo: const {
              'id': 7,
              'cooked': '<p>before</p>',
              'excerpt': 'before',
              'user': {
                'id': 3,
                'username': 'kris',
                'avatar_template': '/k/{size}.png',
              },
            },
          ),
        );

        expect(read.replyTo!.id, 7);
        expect(read.replyTo!.userId, 3);
        expect(read.replyTo!.excerpt, 'before');
        expect(read.replyTo!.username, 'kris');
        expect(read.replyTo!.avatarUrl, '$site/k/90.png');
      },
    );

    test('knows a webhook message by the event beside it', () {
      final read = messageFrom(
        message(webhook: const {'username': 'CI', 'emoji': ':robot:'}),
      );

      expect(read.isWebhook, isTrue);
      expect(messageFrom(message()).isWebhook, isFalse);
    });

    test(
      'reads reactions only when there are some, the key being dropped otherwise',
      () {
        expect(messageFrom(message()).reactions, isEmpty);

        final read = messageFrom(
          message(
            reactions: const [
              {
                'emoji': 'heart',
                'count': 3,
                'reacted': true,
                'users': [
                  {'id': 2, 'username': 'sam'},
                ],
              },
            ],
          ),
        );

        expect(read.reactions.single.emoji, 'heart');
        // Three gave it, and the site named at most five of them. The count is
        // the true total and the names are only ever a sample.
        expect(read.reactions.single.count, 3);
        expect(read.reactions.single.reacted, isTrue);
      },
    );

    test('reads uploads, which the cooked body does not carry', () {
      // Chat cooks the raw message rather than the markdown-with-uploads, so
      // unlike a post the attachments are only ever in this array.
      final read = messageFrom(
        message(
          cooked: '',
          uploads: const [
            {
              'id': 4,
              'url': '/uploads/default/original/1X/abc.png',
              'original_filename': 'shot.png',
              'extension': 'png',
              'width': 1200,
              'height': 600,
              'human_filesize': '234 KB',
              'dominant_color': 'C0FFEE',
              'thumbnail': {'url': '/uploads/default/optimized/1X/abc.png'},
            },
          ],
        ),
      );

      final upload = read.uploads.single;
      expect(upload.kind, ChatUploadKind.image);
      expect(upload.originalFilename, 'shot.png');
      expect(upload.thumbnailUrl, '/uploads/default/optimized/1X/abc.png');
      expect(upload.aspectRatio, 2);
      expect(upload.humanFilesize, '234 KB');
    });

    test('bounds per-message reactions and uploads in server order', () {
      final read = messageFrom(
        message(
          reactions: List.generate(
            ChatMessage.maximumReactionsPerMessage + 1,
            (index) => {
              'emoji': 'emoji-$index',
              'count': index + 1,
              'reacted': index.isEven,
            },
          ),
          uploads: List.generate(
            ChatMessage.maximumUploadsPerMessage + 1,
            (index) => {
              'url': '/uploads/image-$index.png',
              'original_filename': 'image-$index.png',
              'extension': 'png',
            },
          ),
        ),
      );

      expect(
        read.reactions.map((reaction) => reaction.emoji).toList(),
        List.generate(
          ChatMessage.maximumReactionsPerMessage,
          (index) => 'emoji-$index',
        ),
      );
      expect(
        read.uploads.map((upload) => upload.originalFilename).toList(),
        List.generate(
          ChatMessage.maximumUploadsPerMessage,
          (index) => 'image-$index.png',
        ),
      );
    });

    test('bounds hostile upload dimensions before chat layout', () {
      ChatUpload upload(int? width, int? height) => ChatUpload(
        url: '/uploads/image.png',
        originalFilename: 'image.png',
        kind: ChatUploadKind.image,
        width: width,
        height: height,
      );

      expect(upload(null, 1).aspectRatio, isNull);
      expect(upload(0, 1).aspectRatio, isNull);
      expect(upload(-1, 1).aspectRatio, isNull);
      expect(upload(1, 0).aspectRatio, isNull);
      expect(upload(1000000000, 1).aspectRatio, 4);
      expect(upload(1, 1000000000).aspectRatio, 0.25);
      expect(upload(16, 9).aspectRatio, closeTo(16 / 9, 0.0001));
    });

    test(
      'sorts an upload by its filename when the site named no extension',
      () {
        final read = messageFrom(
          message(
            uploads: const [
              {'url': '/u/clip.mp4', 'original_filename': 'clip.MP4'},
              {'url': '/u/notes.pdf', 'original_filename': 'notes.pdf'},
              {'url': '/u/take.m4a', 'original_filename': 'take.m4a'},
            ],
          ),
        );

        expect(read.uploads.map((u) => u.kind), [
          ChatUploadKind.video,
          ChatUploadKind.attachment,
          ChatUploadKind.audio,
        ]);
      },
    );

    test('reads a thread preview only on the message that started one', () {
      expect(messageFrom(message(threadId: 3)).thread, isNull);

      final read = messageFrom(
        message(
          threadId: 3,
          thread: const {
            'id': 3,
            'title': 'Deploy plan',
            'reply_count': 7,
            'preview': {
              'last_reply_created_at': '2026-05-05T12:00:00.000Z',
              'last_reply_excerpt': 'sounds good',
              'last_reply_id': 18,
              'last_reply_user': {
                'id': 3,
                'username': 'kris',
                'avatar_template': '/k/{size}.png',
              },
              'participant_count': 4,
              'participant_users': [
                {
                  'id': 3,
                  'username': 'kris',
                  'avatar_template': '/k/{size}.png',
                },
                {'id': 4, 'username': 'lee', 'name': 'Lee'},
              ],
            },
          },
        ),
      );

      expect(read.threadId, 3);
      expect(read.thread!.replyCount, 7);
      expect(read.thread!.title, 'Deploy plan');
      expect(read.thread!.lastReplyUsername, 'kris');
      expect(read.thread!.lastReplyExcerpt, 'sounds good');
      expect(read.thread!.lastReplyId, 18);
      expect(read.thread!.lastReplyUser?.id, 3);
      expect(read.thread!.participantCount, 4);
      expect(read.thread!.participantUsers.map((user) => user.displayName), [
        'kris',
        'Lee',
      ]);
    });

    test(
      'reads nothing it was not sent rather than inventing defaults it was',
      () {
        // Everything optional dropped at once, which is what a plain message in a
        // channel with threading off actually looks like.
        final read = messageFrom({'id': 1, 'chat_channel_id': 9});

        expect(read.cooked, '');
        expect(read.author.username, '');
        expect(read.createdAt, isNull);
        expect(read.threadId, isNull);
        expect(read.thread, isNull);
        expect(read.replyTo, isNull);
        expect(read.uploads, isEmpty);
        expect(read.reactions, isEmpty);
      },
    );
  });

  group('a page of messages', () {
    test('keeps the messages oldest first, as the site sent them', () {
      final read = ChatMessage.parsePage(
        page([message(id: 1), message(id: 2), message(id: 3)]),
        site,
      );

      expect(read.messages.map((m) => m.id), [1, 2, 3]);
    });

    test(
      'reads an unanswered can_load_more_past as no more rather than as yes',
      () {
        // Ruby leaves the local for the direction it did not paginate unassigned,
        // so it serialises as null. Defaulting a null to true would page forever.
        expect(
          ChatMessage.parsePage(
            page([], canLoadMorePast: null),
            site,
          ).canLoadMorePast,
          isFalse,
        );
        expect(
          ChatMessage.parsePage(
            page([], canLoadMorePast: true),
            site,
          ).canLoadMorePast,
          isTrue,
        );
        expect(
          ChatMessage.parsePage(
            page([], canLoadMorePast: false),
            site,
          ).canLoadMorePast,
          isFalse,
        );
      },
    );

    test('reads a channel with nothing in it as an empty page', () {
      expect(ChatMessage.parsePage(page([]), site).messages, isEmpty);
    });

    test('bounds oversized pages at the edge the caller is paging toward', () {
      final oversized = page([
        for (var id = 1; id <= 60; id++) message(id: id),
      ]);

      final newest = ChatMessage.parsePage(
        oversized,
        site,
        maximumMessages: 10,
      );
      expect(newest.messages.map((entry) => entry.id), [
        for (var id = 51; id <= 60; id++) id,
      ]);
      expect(newest.canLoadMorePast, isTrue);
      expect(newest.canLoadMoreFuture, isFalse);

      final oldest = ChatMessage.parsePage(
        oversized,
        site,
        window: ChatMessagePageWindow.retainOldest,
        maximumMessages: 10,
      );
      expect(oldest.messages.map((entry) => entry.id), [
        for (var id = 1; id <= 10; id++) id,
      ]);
      expect(oldest.canLoadMorePast, isFalse);
      expect(oldest.canLoadMoreFuture, isTrue);
    });

    test('centers an oversized last-read page on the server target', () {
      final read = ChatMessage.parsePage(
        page([
          for (var id = 1; id <= 80; id++) message(id: id),
        ], targetMessageId: 40),
        site,
        window: ChatMessagePageWindow.aroundTarget,
        maximumMessages: 10,
      );

      expect(read.messages.map((entry) => entry.id), [
        for (var id = 35; id <= 44; id++) id,
      ]);
      expect(read.canLoadMorePast, isTrue);
      expect(read.canLoadMoreFuture, isTrue);
      expect(read.targetMessageId, 40);
      expect(() => read.messages.clear(), throwsUnsupportedError);
    });

    test('rejects page limits outside the server contract', () {
      expect(
        () => ChatMessage.parsePage(page([]), site, maximumMessages: 0),
        throwsRangeError,
      );
      expect(
        () => ChatMessage.parsePage(
          page([]),
          site,
          maximumMessages: ChatMessage.maximumPageSize + 1,
        ),
        throwsRangeError,
      );
    });
  });
}
