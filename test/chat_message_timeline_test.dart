import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage message(
  int id, {
  int minute = 0,
  int second = 0,
  bool withoutDate = false,
}) => ChatMessage(
  id: id,
  channelId: 9,
  cooked: '<p>$id</p>',
  author: const ChatMessageAuthor(id: 2, username: 'sam'),
  createdAt: withoutDate ? null : DateTime.utc(2026, 5, 5, 10, minute, second),
);

ChatTimelineSnapshot snapshot(
  List<int> ids,
  Iterable<ChatMessage> messages, {
  void Function(int id)? onRead,
}) {
  final byId = {for (final message in messages) message.id: message};
  return ChatTimelineSnapshot(
    ids: ids,
    messageById: (id) {
      onRead?.call(id);
      return byId[id];
    },
  );
}

void main() {
  group('merging canonical messages', () {
    test('orders a replacement window by wire date and then ID', () {
      final ids = ChatMessageTimeline.merge(
        held: snapshot(const [], const []),
        arrived: [
          message(7, second: 30),
          message(6, second: 30),
          message(8, second: 31),
        ],
        mode: ChatTimelineMergeMode.sortedUnion,
      );

      // Wire timestamps can be equal and Dart's sort is unstable, so the id
      // tiebreak is part of the timeline rather than presentation polish.
      expect(ids, [6, 7, 8]);
    });

    test('deduplicates overlap and repeated arrivals by message ID', () {
      final held = [5];
      final ids = ChatMessageTimeline.merge(
        held: snapshot(held, [message(5, minute: 5)]),
        arrived: [
          message(4, minute: 4),
          message(3, minute: 3),
          message(5, minute: 5),
          message(3, minute: 3),
        ],
        mode: ChatTimelineMergeMode.prependPage,
      );

      expect(ids, [3, 4, 5]);
    });

    test('keeps a directional page on the edge named by the cursor', () {
      final held = [2];
      final current = snapshot(held, [message(2, minute: 5)]);
      final surprisingPage = [message(30, minute: 1)];

      expect(
        ChatMessageTimeline.merge(
          held: current,
          arrived: surprisingPage,
          mode: ChatTimelineMergeMode.prependPage,
        ),
        [30, 2],
      );
      expect(
        ChatMessageTimeline.merge(
          held: current,
          arrived: surprisingPage,
          mode: ChatTimelineMergeMode.appendPage,
        ),
        [2, 30],
      );
    });

    test('returns the exact held list when a page brings nothing new', () {
      final held = [5];

      final ids = ChatMessageTimeline.merge(
        held: snapshot(held, [message(5, minute: 5)]),
        arrived: [message(5, minute: 5), message(5, minute: 6)],
        mode: ChatTimelineMergeMode.appendPage,
      );

      expect(ids, same(held));
    });

    test('puts undated records first and still orders them by ID', () {
      final ids = ChatMessageTimeline.merge(
        held: snapshot(const [], const []),
        arrived: [
          message(3),
          message(2, withoutDate: true),
          message(1, withoutDate: true),
        ],
        mode: ChatTimelineMergeMode.sortedUnion,
      );

      expect(ids, [1, 2, 3]);
    });
  });

  group('admitting a live message', () {
    test('appends an ordinary arrival after reading only the newest row', () {
      final reads = <int>[];
      final ids = ChatMessageTimeline.admitLive(
        held: snapshot(
          [1, 3],
          [message(1), message(3, minute: 2)],
          onRead: reads.add,
        ),
        message: message(4, minute: 3),
      );

      expect(ids, [1, 3, 4]);
      expect(reads, [3]);
    });

    test('derives the full position for an adopted earlier timestamp', () {
      final ids = ChatMessageTimeline.admitLive(
        held: snapshot([1, 3], [message(1), message(3, minute: 2)]),
        message: message(4, minute: 1),
      );

      expect(ids, [1, 4, 3]);
    });

    test('uses the ID tiebreak when a live timestamp equals the newest', () {
      final ids = ChatMessageTimeline.admitLive(
        held: snapshot([1, 3], [message(1), message(3, minute: 2)]),
        message: message(2, minute: 2),
      );

      expect(ids, [1, 2, 3]);
    });

    test('preserves a missing held record on the fast append path', () {
      final ids = ChatMessageTimeline.admitLive(
        held: snapshot([1, 99], [message(1)]),
        message: message(4, minute: 1),
      );

      expect(ids, [1, 99, 4]);
    });

    test('drops missing held records when the slow path re-derives order', () {
      final ids = ChatMessageTimeline.admitLive(
        held: snapshot([1, 99, 3], [message(1), message(3, minute: 2)]),
        message: message(2, minute: 1),
      );

      expect(ids, [1, 2, 3]);
    });
  });

  group('closing the live seam', () {
    test('admits only pending records strictly beyond the newest held', () {
      final pending = [
        message(4, minute: 4),
        message(7, minute: 5),
        message(6, minute: 6),
      ];

      final seam = ChatMessageTimeline.closeSeam(
        held: snapshot([5], [message(5, minute: 5)]),
        pending: pending,
      );

      expect(seam.ids, [5, 7, 6]);
      expect(seam.admittedPending.map((message) => message.id), [7, 6]);
    });

    test('admits every extant pending record into an empty window', () {
      final seam = ChatMessageTimeline.closeSeam(
        held: snapshot(const [], const []),
        pending: [message(2, minute: 2), message(1, minute: 1)],
      );

      expect(seam.ids, [1, 2]);
      expect(seam.admittedPending.map((message) => message.id), [2, 1]);
    });

    test('returns the exact held list when every pending record is older', () {
      final held = [5];

      final seam = ChatMessageTimeline.closeSeam(
        held: snapshot(held, [message(5, minute: 5)]),
        pending: [message(4, minute: 4)],
      );

      expect(seam.ids, same(held));
      expect(seam.admittedPending, isEmpty);
    });

    test('uses the epoch boundary then drops a missing newest record', () {
      final seam = ChatMessageTimeline.closeSeam(
        held: snapshot([5, 99], [message(5, minute: 5)]),
        pending: [message(6, minute: 6)],
      );

      expect(seam.ids, [5, 6]);
      expect(seam.admittedPending.map((message) => message.id), [6]);
    });
  });
}
