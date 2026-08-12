import 'package:discourse_native/src/models/incoming_topics.dart';
import 'package:flutter_test/flutter_test.dart';

/// A `/new` message, shaped as `TopicTrackingState.publish_new` sends it.
Map<String, Object?> newTopic(int topicId, {int? categoryId = 5}) => {
  'topic_id': topicId,
  'message_type': 'new_topic',
  'payload': {
    'last_read_post_number': null,
    'highest_post_number': 1,
    'created_at': '2026-08-06T09:00:00.000Z',
    'category_id': categoryId,
    'archetype': 'regular',
    'created_in_new_period': true,
  },
};

/// A `/latest` message, shaped as `TopicTrackingState.publish_latest` sends it.
/// Published when a post bumps a topic, not when one is created.
Map<String, Object?> bumped(int topicId, {int? categoryId = 5}) => {
  'topic_id': topicId,
  'message_type': 'latest',
  'payload': {
    'bumped_at': '2026-08-06T09:00:00.000Z',
    'category_id': categoryId,
    'archetype': 'regular',
  },
};

void main() {
  group('notify', () {
    test('counts a new topic for both the latest and the new lists', () {
      final incoming = IncomingTopics();

      expect(incoming.notify(newTopic(42)), isTrue);

      expect(incoming.count('latest'), 1);
      expect(incoming.count('new'), 1);
    });

    test('counts a bumped topic for the latest list only', () {
      final incoming = IncomingTopics();

      expect(incoming.notify(bumped(42)), isTrue);

      expect(incoming.count('latest'), 1);
      expect(incoming.count('new'), 0);
    });

    test('counts nothing for the lists core does not track', () {
      final incoming = IncomingTopics()
        ..notify(newTopic(42))
        ..notify(bumped(43));

      // Top is ordered by score rather than by arrival, and messages have a
      // tracker of their own server side.
      expect(incoming.count('top'), 0);
      expect(incoming.count('messages'), 0);
    });

    test('counts one topic once, however many messages it produces', () {
      final incoming = IncomingTopics();

      expect(incoming.notify(newTopic(42)), isTrue);
      // A reply lands on the topic that was just created, and a reconnect can
      // replay either message.
      expect(incoming.notify(bumped(42)), isFalse);
      expect(incoming.notify(newTopic(42)), isFalse);

      expect(incoming.count('latest'), 1);
    });

    test('ignores the messages that are not a topic arriving', () {
      final incoming = IncomingTopics();

      // Both are published to /latest and carry no payload: they say a topic
      // left or joined the reader's lists, not that one turned up.
      expect(incoming.notify({'topic_id': 42, 'message_type': 'muted'}), false);
      expect(
        incoming.notify({'topic_id': 42, 'message_type': 'unmuted'}),
        isFalse,
      );
      expect(incoming.count('latest'), 0);
    });

    test('ignores anything it cannot read', () {
      final incoming = IncomingTopics();

      expect(incoming.notify(null), isFalse);
      expect(incoming.notify('nonsense'), isFalse);
      expect(incoming.notify(const {'message_type': 'new_topic'}), isFalse);
      expect(
        incoming.notify(const {'topic_id': 'seven', 'message_type': 'latest'}),
        isFalse,
      );
      expect(incoming.count('latest'), 0);
    });

    test('keeps arrival order, so the oldest is asked for first', () {
      final incoming = IncomingTopics()
        ..notify(newTopic(3))
        ..notify(newTopic(1))
        ..notify(newTopic(2));

      expect(incoming.topicIds('latest'), [3, 1, 2]);
    });

    test('returns a bounded view without consuming later arrivals', () {
      final incoming = IncomingTopics();
      for (var id = 1; id <= 32; id++) {
        incoming.notify(newTopic(id));
      }

      expect(incoming.topicIds('latest', limit: 30), [
        for (var id = 1; id <= 30; id++) id,
      ]);
      expect(incoming.count('latest'), 32);
      expect(incoming.topicIds('latest'), [
        for (var id = 1; id <= 32; id++) id,
      ]);
    });
  });

  group('clear', () {
    test('forgets every id asked for, not only those that came back', () {
      final incoming = IncomingTopics()
        ..notify(newTopic(1))
        ..notify(newTopic(2));

      // Topic 2 was muted, or deleted, or past the page the site serves: it
      // was requested and produced nothing, and must not sit in the count
      // behind a banner that can never clear it.
      expect(incoming.clear('latest', [1, 2]), isTrue);
      expect(incoming.count('latest'), 0);
    });

    test('leaves what arrived while the fetch was in flight', () {
      final incoming = IncomingTopics()..notify(newTopic(1));

      incoming.notify(newTopic(2));
      incoming.clear('latest', [1]);

      expect(incoming.topicIds('latest'), [2]);
    });

    test('leaves the other lists alone', () {
      final incoming = IncomingTopics()..notify(newTopic(1));

      incoming.clear('latest', [1]);

      expect(incoming.count('latest'), 0);
      expect(incoming.count('new'), 1);
    });
  });

  group('reset', () {
    test('drops one list, for a list that has just been refetched', () {
      final incoming = IncomingTopics()..notify(newTopic(1));

      expect(incoming.reset('latest'), isTrue);
      expect(incoming.reset('latest'), isFalse);

      expect(incoming.count('latest'), 0);
      expect(incoming.count('new'), 1);
    });
  });
}
