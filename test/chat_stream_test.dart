import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream.dart';
import 'package:flutter_test/flutter_test.dart';

/// A message built from what the grouping rules actually read, rather than from
/// a wire payload: every one of them is about time, authorship or state.
ChatMessage at(
  int id, {
  int author = 2,
  int minute = 0,
  int day = 5,
  bool deleted = false,
  bool webhook = false,
  bool pinned = false,
  int? replyToId,
}) => ChatMessage(
  id: id,
  channelId: 9,
  cooked: '<p>$id</p>',
  author: ChatMessageAuthor(id: author, username: 'u$author'),
  // Local, because the day separators are the reader's days.
  createdAt: DateTime(2026, 5, day, 10, minute),
  deletedAt: deleted ? DateTime(2026, 5, day, 11) : null,
  pinned: pinned,
  isWebhook: webhook,
  replyTo: replyToId == null
      ? null
      : ChatReplyTo(id: replyToId, userId: 2, excerpt: '', username: 'u'),
);

/// Just the message rows, so a test about chaining is not also a test about
/// separators.
List<ChatStreamMessage> messagesOf(List<ChatStreamItem> items) =>
    items.whereType<ChatStreamMessage>().toList();

bool chainedAt(List<ChatStreamItem> items, int id) =>
    messagesOf(items).firstWhere((m) => m.id == id).chained;

void main() {
  group('chaining a message to the one above', () {
    test(
      'chains a second message from the same person within five minutes',
      () {
        final items = buildChatStream([at(1), at(2, minute: 4)]);

        expect(chainedAt(items, 1), isFalse);
        expect(chainedAt(items, 2), isTrue);
      },
    );

    test('breaks the chain when somebody else speaks', () {
      final items = buildChatStream([at(1), at(2, author: 3, minute: 1)]);

      expect(chainedAt(items, 2), isFalse);
    });

    test('breaks the chain after five minutes of silence', () {
      // Exactly five is still one burst; a second past it is a new thought.
      expect(chainedAt(buildChatStream([at(1), at(2, minute: 5)]), 2), isTrue);
      expect(chainedAt(buildChatStream([at(1), at(2, minute: 6)]), 2), isFalse);
    });

    test(
      'breaks the chain for a webhook message, which is not really anyone',
      () {
        final items = buildChatStream([
          at(1, webhook: true),
          at(2, minute: 1, webhook: true),
        ]);

        expect(chainedAt(items, 2), isFalse);
      },
    );

    test('breaks the chain around a message that was deleted', () {
      // The deleted one becomes a "1 message deleted" row, which is another
      // voice between the two — so the one below it starts fresh.
      final items = buildChatStream([
        at(1),
        at(2, minute: 1, deleted: true),
        at(3, minute: 2),
      ]);

      expect(chainedAt(items, 3), isFalse);
    });

    test('gives a pinned message its own speaker header', () {
      final items = buildChatStream([
        at(1),
        at(2, minute: 1, pinned: true),
        at(3, minute: 2),
      ]);

      expect(chainedAt(items, 2), isFalse);
      // Core only forces the pinned row itself to show a header.
      expect(chainedAt(items, 3), isTrue);
    });

    test('chains a reply only when it is replying to the message above it', () {
      expect(
        chainedAt(buildChatStream([at(1), at(2, minute: 1, replyToId: 1)]), 2),
        isTrue,
      );
      expect(
        chainedAt(buildChatStream([at(1), at(2, minute: 1, replyToId: 99)]), 2),
        isFalse,
      );
    });

    test('never chains the first message, having nothing above it', () {
      expect(chainedAt(buildChatStream([at(1)]), 1), isFalse);
    });

    test(
      'breaks the chain across a day boundary, where the separator already does',
      () {
        final items = buildChatStream([at(1, day: 5), at(2, day: 6)]);

        expect(chainedAt(items, 2), isFalse);
      },
    );

    test(
      'leaves the page it was assembled from no mark, contiguity being the invariant',
      () {
        // Discourse breaks the chain at the first message of the latest fetched
        // page. Here the stream is contiguous by construction, so a page boundary
        // would be a seam with no cause the reader could see.
        final older = [at(1), at(2, minute: 1)];
        final newer = [at(3, minute: 2), at(4, minute: 3)];

        expect(chainedAt(buildChatStream([...older, ...newer]), 3), isTrue);
      },
    );
  });

  group('day separators', () {
    test('puts one before the first message of each day', () {
      final items = buildChatStream([
        at(1, day: 5),
        at(2, day: 5, minute: 1),
        at(3, day: 6),
      ]);

      expect(items.whereType<ChatStreamDay>().map((d) => d.day), [
        DateTime(2026, 5, 5),
        DateTime(2026, 5, 6),
      ]);
    });

    test('puts one above the very first message, which starts a day too', () {
      expect(buildChatStream([at(1)]).first, isA<ChatStreamDay>());
    });

    test('puts none in a stream with no messages in it', () {
      expect(buildChatStream(const []), isEmpty);
    });
  });

  group('long time gaps', () {
    test(
      'puts one before a message after more than the default seven days',
      () {
        final items = buildChatStream([at(1, day: 5), at(2, day: 13)]);
        final gap = items.whereType<ChatStreamTimeGap>().single;

        expect(gap, const ChatStreamTimeGap(messageId: 2, daysSince: 8));
        expect(items[items.indexOf(gap) + 1], isA<ChatStreamMessage>());
        expect(chainedAt(items, 2), isFalse);
      },
    );

    test('uses a strict, site-configurable threshold', () {
      expect(
        buildChatStream([
          at(1, day: 5),
          at(2, day: 12),
        ]).whereType<ChatStreamTimeGap>(),
        isEmpty,
      );
      expect(
        buildChatStream([
          at(1, day: 5),
          at(2, day: 13),
        ], showTimeGapDays: 30).whereType<ChatStreamTimeGap>(),
        isEmpty,
      );
    });
  });

  group('runs of deleted messages', () {
    test('collapses consecutive deleted messages into one row', () {
      final items = buildChatStream([
        at(1),
        at(2, minute: 1, deleted: true),
        at(3, minute: 2, deleted: true),
        at(4, minute: 3, deleted: true),
        at(5, minute: 4),
      ]);

      expect(items.whereType<ChatStreamDeleted>().single.count, 3);
      expect(items.whereType<ChatStreamDeleted>().single.messageIds, [2, 3, 4]);
      expect(messagesOf(items).map((m) => m.id), [1, 5]);
    });

    test('counts two separated runs separately', () {
      final items = buildChatStream([
        at(1, deleted: true),
        at(2, minute: 1),
        at(3, minute: 2, deleted: true),
        at(4, minute: 3, deleted: true),
      ]);

      expect(items.whereType<ChatStreamDeleted>().map((d) => d.count), [1, 2]);
    });

    test('does not carry a run across a day boundary it did not happen on', () {
      final items = buildChatStream([
        at(1, day: 5, deleted: true),
        at(2, day: 6, deleted: true),
      ]);

      expect(items.whereType<ChatStreamDeleted>().map((d) => d.count), [1, 1]);
    });

    test('closes a run that reaches the end of the stream', () {
      final items = buildChatStream([at(1), at(2, minute: 1, deleted: true)]);

      expect(items.whereType<ChatStreamDeleted>().single.count, 1);
    });
  });

  group('where the unread messages begin', () {
    test('divides before the first message the reader has not seen', () {
      final items = buildChatStream([
        at(1),
        at(2, minute: 1),
        at(3, minute: 2),
      ], lastReadMessageId: 1);

      final index = items.indexWhere((i) => i is ChatStreamNewDivider);
      expect(index, greaterThan(0));
      expect(items[index + 1], const ChatStreamMessage(id: 2, chained: false));
    });

    test('draws nothing when everything has been read', () {
      final items = buildChatStream([
        at(1),
        at(2, minute: 1),
      ], lastReadMessageId: 2);

      expect(items.whereType<ChatStreamNewDivider>(), isEmpty);
    });

    test('draws nothing when the only unread message is the newest one', () {
      // A divider immediately above the last row separates nothing from
      // nothing, which is the rule Discourse's own newestMessage follows.
      final items = buildChatStream([
        at(1),
        at(2, minute: 1),
      ], lastReadMessageId: 1);

      expect(items.whereType<ChatStreamNewDivider>(), isEmpty);
    });

    test('draws nothing for a reader the site gave no last-read message', () {
      final items = buildChatStream([at(1), at(2, minute: 1)]);

      expect(items.whereType<ChatStreamNewDivider>(), isEmpty);
    });

    test('breaks the chain at the divider, which is a row between the two', () {
      final items = buildChatStream([
        at(1),
        at(2, minute: 1),
        at(3, minute: 2),
      ], lastReadMessageId: 1);

      expect(chainedAt(items, 2), isFalse);
      expect(chainedAt(items, 3), isTrue);
    });
  });

  group('prepending a projected page', () {
    test('discovers a long gap across the newly joined page seam', () {
      final older = [at(1, day: 1)];
      final held = [at(2, day: 10)];

      final incremental = prependChatStream(
        existingItems: buildChatStream(held),
        prepended: older,
        existingLeading: held,
        newestMessageId: held.last.id,
      );

      expect(incremental, buildChatStream([...older, ...held]));
      expect(incremental!.whereType<ChatStreamTimeGap>(), hasLength(1));
    });

    test('matches a full projection across a chained page seam', () {
      final older = [at(1), at(2, minute: 1)];
      final held = [at(3, minute: 2), at(4, minute: 3)];

      final incremental = prependChatStream(
        existingItems: buildChatStream(held),
        prepended: older,
        existingLeading: [held.first],
        newestMessageId: held.last.id,
      );

      expect(incremental, buildChatStream([...older, ...held]));
    });

    test('joins a deleted run that crosses the page seam', () {
      final older = [at(1, deleted: true)];
      final held = [
        at(2, minute: 1, deleted: true),
        at(3, minute: 2),
        at(4, minute: 3),
      ];

      final incremental = prependChatStream(
        existingItems: buildChatStream(held),
        prepended: older,
        existingLeading: held.take(2).toList(),
        newestMessageId: held.last.id,
      );

      expect(incremental, buildChatStream([...older, ...held]));
    });

    test('moves the unread divider into the older page', () {
      final older = [at(2), at(3, minute: 1)];
      final held = [at(4, minute: 2), at(5, minute: 3)];

      final incremental = prependChatStream(
        existingItems: buildChatStream(held, lastReadMessageId: 1),
        prepended: older,
        existingLeading: [held.first],
        lastReadMessageId: 1,
        newestMessageId: held.last.id,
      );

      expect(
        incremental,
        buildChatStream([...older, ...held], lastReadMessageId: 1),
      );
    });
  });
}
