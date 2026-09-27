import 'dart:convert';

import 'package:discourse_native/src/models/incoming_topics.dart';
import 'package:flutter_test/flutter_test.dart';

/// `TopicTrackingState.publish_new`, which lists tags by id while tagging is
/// enabled.
Map<String, Object?> newTopic(
  int topicId, {
  int? categoryId = 5,
  List<int>? tagIds,
}) => {
  'topic_id': topicId,
  'message_type': 'new_topic',
  'payload': {
    'last_read_post_number': null,
    'highest_post_number': 1,
    'created_at': '2026-08-06T09:00:00.000Z',
    'category_id': categoryId,
    'archetype': 'regular',
    'created_in_new_period': true,
    if (tagIds != null)
      'tags': [
        for (final id in tagIds) {'id': id},
      ],
  },
};

Map<String, Object?> bumped(
  int topicId, {
  int? categoryId = 5,
  List<int>? tagIds,
}) => {
  'topic_id': topicId,
  'message_type': 'latest',
  'payload': {
    'bumped_at': '2026-08-06T09:00:00.000Z',
    'category_id': categoryId,
    'archetype': 'regular',
    if (tagIds != null)
      'tags': [
        for (final id in tagIds) {'id': id},
      ],
  },
};

/// Category 5 holds 6, which holds 7; 8 stands alone.
int? parentOf(int categoryId) => const {6: 5, 7: 6}[categoryId];

void main() {
  group('notify', () {
    test('counts a new topic for Latest, New, New – topics and Unseen', () {
      final incoming = IncomingTopics();

      expect(incoming.notify(newTopic(42)), isTrue);

      expect(incoming.count('latest'), 1);
      expect(incoming.count('new'), 1);
      expect(incoming.count('new-topics'), 1);
      expect(incoming.count('unseen'), 1);
    });

    test('counts a bumped topic for the latest list only', () {
      final incoming = IncomingTopics();

      expect(incoming.notify(bumped(42)), isTrue);

      expect(incoming.count('latest'), 1);
      expect(incoming.count('new'), 0);
      expect(incoming.count('new-topics'), 0);
      expect(incoming.count('unseen'), 0);
    });

    test('counts nothing for the lists core does not track', () {
      final incoming = IncomingTopics()
        ..notify(newTopic(42))
        ..notify(bumped(43));

      expect(incoming.count('top'), 0);
      expect(incoming.count('messages'), 0);
      expect(incoming.count('unread'), 0);
      // The replies subset never returns a new topic.
      expect(incoming.count('new-replies'), 0);
      // A category list counts once it has loaded and been tracked.
      expect(incoming.count('category-5'), 0);
    });

    test('counts one topic once, however many messages it produces', () {
      final incoming = IncomingTopics();

      expect(incoming.notify(newTopic(42)), isTrue);
      expect(incoming.notify(bumped(42)), isFalse);
      expect(incoming.notify(newTopic(42)), isFalse);

      expect(incoming.count('latest'), 1);
    });

    test('ignores the messages that are not a topic arriving', () {
      final incoming = IncomingTopics();

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

    for (final messageType in ['new_topic', 'latest']) {
      test('ignores an overflowing JSON identifier in $messageType', () {
        final incoming = IncomingTopics();
        final message = jsonDecode(
          '{"topic_id":1e999,"message_type":"$messageType"}',
        );

        expect(incoming.notify(message), isFalse);
        expect(incoming.topicIds('latest'), isEmpty);
        expect(incoming.topicIds('new'), isEmpty);
        expect(incoming.notify(newTopic(42)), isTrue);
        expect(incoming.topicIds('latest'), [42]);
        expect(incoming.topicIds('new'), [42]);
      });

      test('rejects invalid numeric identifiers in $messageType', () {
        final incoming = IncomingTopics()..notify(newTopic(42));
        for (final id in <Object?>[
          double.infinity,
          double.negativeInfinity,
          double.nan,
          0,
          -1,
          -9223372036854775808,
          0.0,
          -0.0,
          -1.0,
          0.5,
          3.75,
          9223372036854775807.toDouble(),
          jsonDecode('9223372036854775808'),
          1e100,
          '43',
          true,
          null,
        ]) {
          expect(
            incoming.notify({'topic_id': id, 'message_type': messageType}),
            isFalse,
            reason: 'Invalid topic ID: $id',
          );
          expect(incoming.topicIds('latest'), [42]);
          expect(incoming.topicIds('new'), [42]);
        }

        expect(incoming.notify(newTopic(43)), isTrue);
        expect(incoming.notify(bumped(43)), isFalse);
        expect(incoming.topicIds('latest'), [42, 43]);
        expect(incoming.topicIds('new'), [42, 43]);
      });

      test('preserves supported integral identifiers in $messageType', () {
        final incoming = IncomingTopics();
        for (final id in [
          1,
          42.0,
          9223372036854774784.0,
          9223372036854775807,
        ]) {
          final message = {'topic_id': id, 'message_type': messageType};
          expect(incoming.notify(message), isTrue);
          expect(incoming.notify(message), isFalse);
        }

        expect(
          incoming.notify({'topic_id': 42, 'message_type': messageType}),
          isFalse,
        );
        const expected = [1, 42, 9223372036854774784, 9223372036854775807];
        expect(incoming.topicIds('latest'), expected);
        expect(
          incoming.topicIds('new'),
          messageType == 'new_topic' ? expected : const <int>[],
        );
      });
    }

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

    test('holds a bounded number of arrivals, forgetting the oldest', () {
      const arrivals = IncomingTopics.heldTopicCapacity + 2;
      final incoming = IncomingTopics();
      for (var id = 1; id <= arrivals; id++) {
        incoming.notify(newTopic(id));
      }

      expect(incoming.count('latest'), IncomingTopics.heldTopicCapacity);
      expect(incoming.topicIds('latest', limit: 1), [3]);

      incoming.restore('latest', [1, 2]);
      expect(incoming.count('latest'), IncomingTopics.heldTopicCapacity);
      expect(incoming.topicIds('latest').last, 2);
    });
  });

  group('track', () {
    test("a category list counts its own topics and its children's", () {
      final incoming = IncomingTopics()
        ..track({
          'category-5': const IncomingTopicsFilter.latest(categoryId: 5),
        }, parentCategoryOf: parentOf);

      expect(incoming.notify(newTopic(1, categoryId: 5)), isTrue);
      expect(incoming.notify(bumped(2, categoryId: 6)), isTrue);

      expect(incoming.topicIds('category-5'), [1, 2]);
    });

    test('a category list leaves out a grandchild and other categories', () {
      final incoming = IncomingTopics()
        ..track({
          'category-5': const IncomingTopicsFilter.latest(categoryId: 5),
        }, parentCategoryOf: parentOf);

      incoming
        ..notify(newTopic(1, categoryId: 7))
        ..notify(newTopic(2, categoryId: 8))
        ..notify(newTopic(3, categoryId: 99))
        ..notify(newTopic(4, categoryId: null));

      expect(incoming.count('category-5'), 0);
      // The site's own lists still hear of every one of them.
      expect(incoming.topicIds('latest'), [1, 2, 3, 4]);
    });

    test('a child counts only while its parent is known', () {
      final incoming = IncomingTopics()
        ..track({
          'category-5': const IncomingTopicsFilter.latest(categoryId: 5),
        });

      incoming.notify(newTopic(1, categoryId: 6));

      expect(incoming.count('category-5'), 0);
    });

    test('a subcategory list does not count its parent', () {
      final incoming = IncomingTopics()
        ..track({
          'category-6': const IncomingTopicsFilter.latest(categoryId: 6),
        }, parentCategoryOf: parentOf);

      incoming
        ..notify(newTopic(1, categoryId: 5))
        ..notify(newTopic(2, categoryId: 6))
        ..notify(newTopic(3, categoryId: 7));

      expect(incoming.topicIds('category-6'), [2, 3]);
    });

    test('a tag list counts only topics carrying its tag', () {
      final incoming = IncomingTopics()
        ..track({
          'tag-3': const IncomingTopicsFilter.latest(tagIds: {3}),
        });

      incoming
        ..notify(newTopic(1, tagIds: [3]))
        ..notify(bumped(2, tagIds: [4, 3]))
        ..notify(newTopic(3, tagIds: [4]))
        ..notify(newTopic(4, tagIds: []))
        ..notify(newTopic(5));

      expect(incoming.topicIds('tag-3'), [1, 2]);
    });

    test('a list of several tags counts only topics carrying them all', () {
      final incoming = IncomingTopics()
        ..track({
          'both': const IncomingTopicsFilter.latest(tagIds: {3, 4}),
        });

      incoming
        ..notify(newTopic(1, tagIds: [3]))
        ..notify(newTopic(2, tagIds: [4, 3]));

      expect(incoming.topicIds('both'), [2]);
    });

    test('ignores tags it cannot read', () {
      final incoming = IncomingTopics()
        ..track({
          'tag-3': const IncomingTopicsFilter.latest(tagIds: {3}),
        });

      for (final tags in <Object?>[
        'three',
        ['three'],
        [
          {'id': '3'},
        ],
        [
          {'name': 'three'},
        ],
        [
          {'id': -3},
        ],
        {'id': 3},
      ]) {
        incoming.notify({
          'topic_id': 1,
          'message_type': 'new_topic',
          'payload': {'category_id': 5, 'tags': tags},
        });
      }
      incoming.notify({
        'topic_id': 2,
        'message_type': 'new_topic',
        'payload': 'nonsense',
      });

      expect(incoming.count('tag-3'), 0);
      expect(incoming.topicIds('latest'), [1, 2]);
    });

    test('a category and tag list requires both', () {
      final incoming = IncomingTopics()
        ..track({
          'both': const IncomingTopicsFilter.latest(categoryId: 5, tagIds: {3}),
        }, parentCategoryOf: parentOf);

      incoming
        ..notify(newTopic(1, categoryId: 6, tagIds: [3]))
        ..notify(newTopic(2, categoryId: 8, tagIds: [3]))
        ..notify(newTopic(3, categoryId: 5, tagIds: [4]));

      expect(incoming.topicIds('both'), [1]);
    });

    test('a scoped New or Unseen list counts a new topic, not a bump', () {
      final incoming = IncomingTopics()
        ..track({
          'new-in-5': const IncomingTopicsFilter.created(categoryId: 5),
          'latest-in-5': const IncomingTopicsFilter.latest(categoryId: 5),
        });

      incoming
        ..notify(newTopic(1))
        ..notify(bumped(2));

      expect(incoming.topicIds('new-in-5'), [1]);
      expect(incoming.topicIds('latest-in-5'), [1, 2]);
    });

    test('a list no longer tracked stops counting and forgets its topics', () {
      final incoming = IncomingTopics()
        ..track({
          'category-5': const IncomingTopicsFilter.latest(categoryId: 5),
          'category-8': const IncomingTopicsFilter.latest(categoryId: 8),
        })
        ..notify(newTopic(1, categoryId: 5))
        ..notify(newTopic(2, categoryId: 8));

      incoming.track({
        'category-8': const IncomingTopicsFilter.latest(categoryId: 8),
      });
      incoming.notify(newTopic(3, categoryId: 5));

      expect(incoming.count('category-5'), 0);
      expect(incoming.topicIds('category-8'), [2]);
      expect(incoming.topicIds('latest'), [1, 2, 3]);
    });

    test("the site's own lists keep their filter", () {
      final incoming = IncomingTopics()
        ..track({
          'latest': const IncomingTopicsFilter.created(categoryId: 8),
          'new': const IncomingTopicsFilter.latest(),
        });

      incoming
        ..notify(newTopic(1))
        ..notify(bumped(2));

      expect(incoming.topicIds('latest'), [1, 2]);
      expect(incoming.topicIds('new'), [1]);
    });

    test('tracks only the most recently loaded lists', () {
      const lists = IncomingTopics.trackedListCapacity + 1;
      final incoming = IncomingTopics()
        ..track({
          for (var id = 1; id <= lists; id++)
            'category-$id': IncomingTopicsFilter.latest(categoryId: id),
        });

      for (var id = 1; id <= lists; id++) {
        incoming.notify(newTopic(id, categoryId: id));
      }

      expect(incoming.count('category-1'), 0);
      expect(incoming.topicIds('category-2'), [2]);
      expect(incoming.topicIds('category-$lists'), [lists]);
    });

    test('forgets every tracked list with the tracker', () {
      final incoming = IncomingTopics()
        ..track({
          'category-5': const IncomingTopicsFilter.latest(categoryId: 5),
        })
        ..notify(newTopic(1))
        ..resetAll();

      incoming.notify(newTopic(2));

      expect(incoming.count('category-5'), 0);
      expect(incoming.topicIds('latest'), [2]);
    });
  });

  group('clear', () {
    test('forgets every ID asked for, not only those that came back', () {
      final incoming = IncomingTopics()
        ..notify(newTopic(1))
        ..notify(newTopic(2));

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

  group('notifyDeleted', () {
    test('forgets a deleted topic on every list it was counted for', () {
      final incoming = IncomingTopics()
        ..track({
          'category-5': const IncomingTopicsFilter.latest(categoryId: 5),
        })
        ..notify(newTopic(1))
        ..notify(newTopic(2));

      expect(
        incoming.notifyDeleted({'topic_id': 1, 'message_type': 'delete'}),
        isTrue,
      );

      expect(incoming.topicIds('latest'), [2]);
      expect(incoming.topicIds('new'), [2]);
      expect(incoming.topicIds('category-5'), [2]);
    });

    test('reports no change for a topic it never counted', () {
      final incoming = IncomingTopics()..notify(newTopic(1));

      expect(
        incoming.notifyDeleted({'topic_id': 9, 'message_type': 'delete'}),
        isFalse,
      );
      expect(incoming.notifyDeleted(null), isFalse);
      expect(incoming.notifyDeleted(const {'topic_id': 'one'}), isFalse);
      expect(incoming.topicIds('latest'), [1]);
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
