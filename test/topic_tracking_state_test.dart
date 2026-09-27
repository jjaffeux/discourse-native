import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'local reading updates cached counts without losing tracking metadata',
    () {
      final tracking = TopicTrackingState([
        const TrackedTopicState(
          topicId: 1,
          highestPostNumber: 10,
          lastReadPostNumber: 4,
          notificationLevel: 2,
          categoryId: 5,
          tagIds: {9},
        ),
      ]);
      expect(tracking.newActivityCounts.newReplies, 1);
      expect(
        tracking.tagBadge(tagId: 9, unifiedNew: true, showCount: true),
        const SidebarBadge.count(1),
      );
      expect(tracking.markRead(1, 8), isTrue);
      expect(tracking.newActivityCounts.newReplies, 1);
      expect(tracking.markRead(1, 10), isTrue);
      expect(tracking.newActivityCounts.newReplies, 0);
      expect(
        tracking.tagBadge(tagId: 9, unifiedNew: true, showCount: true),
        SidebarBadge.none,
      );
      expect(tracking.topic(1)!.categoryId, 5);
      expect(tracking.topic(1)!.notificationLevel, 2);
      expect(tracking.topic(1)!.highestPostNumber, 10);
      expect(tracking.markRead(1, 8), isFalse);
      expect(tracking.markRead(1, 10), isFalse);
      expect(tracking.markRead(2, 10), isFalse);
      expect(tracking.topics, hasLength(1));
    },
  );

  test(
    'notification changes patch existing rows without creating read state',
    () {
      final tracking = TopicTrackingState.fromJson(const [
        {
          'topic_id': 7,
          'highest_post_number': 100,
          'last_read_post_number': null,
          'notification_level': 0,
          'category_id': 5,
          'created_in_new_period': true,
          'tags': [
            {'id': 9},
          ],
        },
      ]);
      expect(tracking.newActivityCounts, (newTopics: 0, newReplies: 0));
      expect(
        tracking.tagBadge(tagId: 9, unifiedNew: true, showCount: true),
        SidebarBadge.none,
      );
      const event = {
        'topic_id': 7,
        'message_type': 'notification_level_change',
        'payload': {'notification_level': 2},
      };
      expect(tracking.applyMessage({...event, 'topic_id': 8}), isFalse);
      expect(tracking.topics, hasLength(1));
      expect(tracking.applyMessage(event), isTrue);
      expect(tracking.applyMessage(event), isFalse);
      expect(tracking.topics.single.lastReadPostNumber, isNull);
      expect(tracking.topics.single.highestPostNumber, 100);
      expect(tracking.topics.single.categoryId, 5);
      expect(tracking.topics.single.tagIds, {9});
      expect(tracking.newActivityCounts, (newTopics: 1, newReplies: 0));
      expect(
        tracking.tagBadge(tagId: 9, unifiedNew: true, showCount: true),
        const SidebarBadge.count(1),
      );
      tracking.applyMessage(const {'topic_id': 7, 'message_type': 'delete'});
      tracking.applyMessage({
        ...event,
        'payload': {'notification_level': 3},
      });
      expect(tracking.topics.single.deleted, isTrue);
      expect(tracking.newActivityCounts, (newTopics: 0, newReplies: 0));
    },
  );

  test('invalid notification levels leave the tracking row unchanged', () {
    const topic = TrackedTopicState(topicId: 7, notificationLevel: 2);
    final tracking = TopicTrackingState([topic]);
    for (final level in <Object?>[null, -1, 4, 1.5, '0', true]) {
      expect(
        tracking.applyMessage({
          'topic_id': 7,
          'message_type': 'notification_level_change',
          'payload': {'notification_level': level},
        }),
        isFalse,
      );
    }
    expect(tracking.topics.single, same(topic));
  });

  const categories = [
    TopicCategory(id: 1, name: 'Parent', color: '111111'),
    TopicCategory(id: 2, name: 'Child', color: '222222', parentCategoryId: 1),
  ];

  TopicTrackingState state() => TopicTrackingState.fromJson(const [
    {
      'topic_id': 10,
      'highest_post_number': 5,
      'last_read_post_number': 3,
      'category_id': 2,
      'notification_level': 2,
      'tags': [
        {'id': 7},
      ],
    },
    {
      'topic_id': 11,
      'highest_post_number': 1,
      'last_read_post_number': null,
      'category_id': 1,
      'created_in_new_period': true,
      'tags': [
        {'id': 7},
      ],
    },
    {
      'topic_id': 12,
      'highest_post_number': 2,
      'last_read_post_number': 1,
      'category_id': 2,
      'is_category_topic': true,
      'notification_level': 2,
      'tags': [
        {'id': 7},
      ],
    },
  ]);

  test('matches core category recursion and unread-before-new priority', () {
    final tracking = state();

    expect(
      tracking.categoryBadge(
        categoryId: 1,
        categories: categories,
        unifiedNew: false,
        showCount: true,
      ),
      const SidebarBadge.count(1),
    );
    expect(
      tracking.categoryBadge(
        categoryId: 1,
        categories: categories,
        unifiedNew: true,
        showCount: true,
      ),
      const SidebarBadge.count(2),
    );
    expect(
      tracking.categoryBadge(
        categoryId: 2,
        categories: categories,
        unifiedNew: false,
        showCount: true,
      ),
      const SidebarBadge.count(2),
    );
  });

  test('splits unified New activity into topics and replies', () {
    expect(state().newActivityCounts, (newTopics: 1, newReplies: 2));
  });

  test('New counts include descendants but not their category topics', () {
    final tracking = state();
    const nestedCategories = [
      ...categories,
      TopicCategory(
        id: 3,
        name: 'Grandchild',
        color: '333333',
        parentCategoryId: 2,
      ),
    ];
    tracking.applyMessage(const {
      'topic_id': 13,
      'message_type': 'new_topic',
      'payload': {'category_id': 3, 'created_in_new_period': true},
    });

    expect(
      tracking.newActivityCountsFor(
        categoryId: 1,
        categories: nestedCategories,
      ),
      (newTopics: 2, newReplies: 1),
    );
    expect(
      tracking.newActivityCountsFor(
        categoryId: 2,
        categories: nestedCategories,
      ),
      (newTopics: 1, newReplies: 2),
    );
    expect(
      tracking.newActivityCountsFor(categoryId: 1, categories: categories),
      (newTopics: 1, newReplies: 1),
    );
    expect(
      tracking.newActivityCountsFor(
        categoryId: 99,
        categories: nestedCategories,
      ),
      (newTopics: 0, newReplies: 0),
    );
  });

  test('New counts intersect the category with every selected tag', () {
    final tracking = state();
    tracking.applyMessage(const {
      'topic_id': 13,
      'message_type': 'new_topic',
      'payload': {
        'category_id': 2,
        'created_in_new_period': true,
        'tags': [
          {'id': 7},
          {'id': 8},
        ],
      },
    });

    expect(tracking.newActivityCountsFor(tagIds: {7}), (
      newTopics: 2,
      newReplies: 2,
    ));
    expect(
      tracking.newActivityCountsFor(
        categoryId: 1,
        categories: categories,
        tagIds: {7, 8},
      ),
      (newTopics: 1, newReplies: 0),
    );
    expect(tracking.newActivityCountsFor(tagIds: {99}), (
      newTopics: 0,
      newReplies: 0,
    ));
  });

  test('scoped New counts follow moves, tag changes, reads and dismissals', () {
    final tracking = state();
    ({int newTopics, int newReplies}) counts() => tracking.newActivityCountsFor(
      categoryId: 1,
      categories: categories,
      tagIds: {7},
    );
    expect(counts(), (newTopics: 1, newReplies: 1));

    tracking.applyMessage(const {
      'topic_id': 10,
      'message_type': 'unread',
      'payload': {'category_id': 99},
    });
    expect(counts(), (newTopics: 1, newReplies: 0));

    tracking.applyMessage(const {
      'topic_id': 10,
      'message_type': 'unread',
      'payload': {
        'category_id': 1,
        'tags': [
          {'id': 8},
        ],
      },
    });
    expect(counts(), (newTopics: 1, newReplies: 0));

    tracking.applyMessage(const {
      'topic_id': 10,
      'message_type': 'unread',
      'payload': {
        'tags': [
          {'id': 7},
        ],
      },
    });
    expect(counts(), (newTopics: 1, newReplies: 1));

    tracking.applyMessage(const {
      'topic_id': 10,
      'message_type': 'read',
      'payload': {'last_read_post_number': 5},
    });
    tracking.applyMessage(const {
      'message_type': 'dismiss_new',
      'payload': {
        'topic_ids': [11],
      },
    });
    expect(counts(), (newTopics: 0, newReplies: 0));
  });

  test('matches core tag counts and the count-versus-dot preference', () {
    final tracking = state();

    expect(
      tracking.tagBadge(tagId: 7, unifiedNew: false, showCount: true),
      const SidebarBadge.count(2),
    );
    expect(
      tracking.tagBadge(tagId: 7, unifiedNew: true, showCount: true),
      const SidebarBadge.count(3),
    );
    expect(
      tracking.tagBadge(tagId: 7, unifiedNew: true, showCount: false),
      const SidebarBadge.dot(),
    );
  });

  test(
    'new activity counts follow events applied after they were computed',
    () {
      final state = TopicTrackingState(const [
        TrackedTopicState(
          topicId: 1,
          highestPostNumber: 3,
          lastReadPostNumber: 1,
          notificationLevel: 2,
        ),
        TrackedTopicState(
          topicId: 2,
          highestPostNumber: 1,
          createdInNewPeriod: true,
        ),
      ]);
      expect(state.newActivityCounts, (newTopics: 1, newReplies: 1));

      expect(
        state.applyMessage({
          'topic_id': 1,
          'message_type': 'read',
          'payload': {'last_read_post_number': 3, 'highest_post_number': 3},
        }),
        isTrue,
      );

      expect(state.newActivityCounts, (newTopics: 1, newReplies: 0));
    },
  );

  test('badges follow events applied after they were computed', () {
    final tracking = state();
    SidebarBadge category() => tracking.categoryBadge(
      categoryId: 2,
      categories: categories,
      unifiedNew: true,
      showCount: true,
    );
    SidebarBadge tag() =>
        tracking.tagBadge(tagId: 7, unifiedNew: true, showCount: true);
    expect(category(), const SidebarBadge.count(2));
    expect(tag(), const SidebarBadge.count(3));

    tracking.applyMessage(const {
      'topic_id': 13,
      'message_type': 'new_topic',
      'payload': {
        'highest_post_number': 1,
        'category_id': 2,
        'created_in_new_period': true,
        'tags': [
          {'id': 7},
        ],
      },
    });
    expect(category(), const SidebarBadge.count(3));
    expect(tag(), const SidebarBadge.count(4));

    tracking.applyMessage(const {'topic_id': 13, 'message_type': 'destroy'});
    expect(category(), const SidebarBadge.count(2));
    expect(tag(), const SidebarBadge.count(3));
  });

  test('descendant counts follow a replaced category list', () {
    final tracking = state();
    const detached = [
      TopicCategory(id: 1, name: 'Parent', color: '111111'),
      TopicCategory(id: 2, name: 'Child', color: '222222'),
    ];

    expect(
      tracking.categoryBadge(
        categoryId: 1,
        categories: categories,
        unifiedNew: true,
        showCount: true,
      ),
      const SidebarBadge.count(2),
    );
    expect(
      tracking.categoryBadge(
        categoryId: 1,
        categories: detached,
        unifiedNew: true,
        showCount: true,
      ),
      const SidebarBadge.count(1),
    );
  });

  test('a badge costs its own topics, not every tracked topic', () {
    Duration timeBadges(int unrelatedTopics) {
      final tracking = TopicTrackingState([
        for (var id = 1; id <= 20; id++)
          TrackedTopicState(
            topicId: id,
            highestPostNumber: 2,
            lastReadPostNumber: 1,
            categoryId: 2,
            notificationLevel: 2,
            tagIds: const {7},
          ),
        for (var id = 100; id < 100 + unrelatedTopics; id++)
          TrackedTopicState(
            topicId: id,
            highestPostNumber: 2,
            lastReadPostNumber: 1,
            categoryId: 99,
            notificationLevel: 2,
            tagIds: const {9},
          ),
      ]);
      SidebarBadge badges() {
        final category = tracking.categoryBadge(
          categoryId: 1,
          categories: categories,
          unifiedNew: true,
          showCount: true,
        );
        expect(category, const SidebarBadge.count(20));
        return tracking.tagBadge(tagId: 7, unifiedNew: true, showCount: true);
      }

      expect(badges(), const SidebarBadge.count(20));
      var best = const Duration(days: 1);
      for (var round = 0; round < 5; round++) {
        final stopwatch = Stopwatch()..start();
        for (var call = 0; call < 200; call++) {
          badges();
        }
        stopwatch.stop();
        if (stopwatch.elapsed < best) best = stopwatch.elapsed;
      }
      return best;
    }

    final small = timeBadges(2000);
    final large = timeBadges(16000);

    expect(
      large.inMicroseconds,
      lessThan(small.inMicroseconds * 4 + 2000),
      reason: 'eight times the unrelated topics: $small became $large',
    );
  });

  test('folds read, unread, dismissal, deletion, and destruction events', () {
    final tracking = TopicTrackingState();
    const badgeArgs = (tagId: 7, unifiedNew: false, showCount: true);
    SidebarBadge badge() => tracking.tagBadge(
      tagId: badgeArgs.tagId,
      unifiedNew: badgeArgs.unifiedNew,
      showCount: badgeArgs.showCount,
    );

    expect(
      tracking.applyMessage(const {
        'topic_id': 20,
        'message_type': 'new_topic',
        'payload': {
          'highest_post_number': 1,
          'category_id': 1,
          'created_in_new_period': true,
          'tags': [
            {'id': 7},
          ],
        },
      }),
      isTrue,
    );
    expect(badge(), const SidebarBadge.count(1));

    tracking.applyMessage(const {
      'message_type': 'dismiss_new',
      'payload': {
        'topic_ids': [20],
      },
    });
    expect(badge(), SidebarBadge.none);

    tracking.applyMessage(const {
      'topic_id': 20,
      'message_type': 'unread',
      'payload': {'highest_post_number': 2},
    });
    expect(badge(), const SidebarBadge.count(1));

    tracking.applyMessage(const {
      'topic_id': 20,
      'message_type': 'read',
      'payload': {'highest_post_number': 2, 'last_read_post_number': 2},
    });
    expect(badge(), SidebarBadge.none);

    tracking.applyMessage(const {
      'topic_id': 20,
      'message_type': 'unread',
      'payload': {'highest_post_number': 3},
    });
    tracking.applyMessage(const {'topic_id': 20, 'message_type': 'delete'});
    expect(badge(), SidebarBadge.none);
    tracking.applyMessage(const {'topic_id': 20, 'message_type': 'recover'});
    expect(badge(), const SidebarBadge.count(1));
    tracking.applyMessage(const {'topic_id': 20, 'message_type': 'destroy'});
    expect(badge(), SidebarBadge.none);
  });

  test('a message the row has already passed leaves it unchanged', () {
    const held = TrackedTopicState(
      topicId: 20,
      highestPostNumber: 12,
      lastReadPostNumber: 10,
      categoryId: 1,
      notificationLevel: 2,
    );
    final tracking = TopicTrackingState([held]);
    Map<String, Object?> message(String type, Map<String, Object?> payload) => {
      'topic_id': 20,
      'message_type': type,
      'payload': payload,
    };

    for (final stale in [
      message('read', {
        'last_read_post_number': 4,
        'highest_post_number': 5,
        'notification_level': 2,
      }),
      message('read', {
        'last_read_post_number': 10,
        'highest_post_number': 10,
        'notification_level': 2,
      }),
      message('unread', {'highest_post_number': 11}),
      message('new_topic', {
        'last_read_post_number': null,
        'highest_post_number': 1,
        'created_in_new_period': true,
      }),
    ]) {
      expect(tracking.applyMessage(stale), isFalse, reason: '$stale');
      expect(tracking.topic(20), same(held));
    }

    expect(
      tracking.applyMessage(message('unread', {'highest_post_number': 13})),
      isTrue,
    );
    expect(tracking.topic(20)?.highestPostNumber, 13);

    // Deleting post 13 lowered the highest post, yet a read that got further
    // than the row is newer than it.
    expect(
      tracking.applyMessage(
        message('read', {
          'last_read_post_number': 12,
          'highest_post_number': 12,
          'notification_level': 2,
        }),
      ),
      isTrue,
    );
    expect(tracking.topic(20)?.lastReadPostNumber, 12);
    expect(tracking.topic(20)?.highestPostNumber, 12);
  });

  Map<String, Object?> newTopicMessage(int topicId) => {
    'topic_id': topicId,
    'message_type': 'new_topic',
    'payload': {
      'last_read_post_number': null,
      'highest_post_number': 1,
      'category_id': 1,
      'created_in_new_period': true,
      'tags': [
        {'id': 7},
      ],
    },
  };

  Map<String, Object?> readMessage(int topicId, {int postNumber = 1}) => {
    'topic_id': topicId,
    'message_type': 'read',
    'payload': {
      'last_read_post_number': postNumber,
      'highest_post_number': postNumber,
      'notification_level': 2,
    },
  };

  Iterable<TrackedTopicState> settled(TopicTrackingState tracking) =>
      tracking.topics.where((topic) => !topic.isNew && !topic.isUnread);

  const settledTopicCap = 1024;

  test('keeps only the most recently changed settled rows', () {
    final tracking = TopicTrackingState();
    for (var id = 1; id <= 2000; id++) {
      // Changing an old settled row keeps it among the recent ones.
      if (id == 1000) tracking.applyMessage(readMessage(1, postNumber: 2));
      tracking.applyMessage(newTopicMessage(id));
      // Every tenth topic stays new and every tenth gains an unread reply.
      if (id % 10 == 0) continue;
      tracking.applyMessage(readMessage(id));
      if (id % 10 == 5) {
        tracking.applyMessage({
          'topic_id': id,
          'message_type': 'unread',
          'payload': {'highest_post_number': 2},
        });
      }
    }

    expect(settled(tracking), hasLength(settledTopicCap));
    expect(tracking.topics, hasLength(settledTopicCap + 400));
    expect(tracking.topic(2), isNull);
    expect(tracking.topic(1)?.lastReadPostNumber, 2);
    expect(tracking.topic(1999)?.lastReadPostNumber, 1);

    expect(tracking.newActivityCounts, (newTopics: 200, newReplies: 200));
    expect(
      tracking.newActivityCountsFor(
        categoryId: 1,
        categories: categories,
        tagIds: {7},
      ),
      (newTopics: 200, newReplies: 200),
    );
    expect(
      tracking.tagBadge(tagId: 7, unifiedNew: true, showCount: true),
      const SidebarBadge.count(400),
    );
    expect(
      tracking.categoryBadge(
        categoryId: 1,
        categories: categories,
        unifiedNew: false,
        showCount: true,
      ),
      const SidebarBadge.count(200),
    );
  });

  test('countable rows are never dropped to make room', () {
    final tracking = TopicTrackingState([
      for (var id = 1; id <= 3000; id++)
        TrackedTopicState(
          topicId: id,
          highestPostNumber: 1,
          categoryId: 1,
          createdInNewPeriod: true,
        ),
    ]);
    for (var id = 5001; id <= 8000; id++) {
      tracking.applyMessage(readMessage(id));
    }

    expect(settled(tracking), hasLength(settledTopicCap));
    expect(tracking.newActivityCounts, (newTopics: 3000, newReplies: 0));
    for (var id = 1; id <= 3000; id++) {
      expect(tracking.topic(id)?.isNew, isTrue, reason: 'topic $id');
    }

    // Rows leaving the countable set join the settled ones as the newest.
    tracking.applyMessage({
      'message_type': 'dismiss_new',
      'payload': {
        'topic_ids': [for (var id = 1; id <= 3000; id++) id],
      },
    });
    expect(tracking.topics, hasLength(settledTopicCap));
    expect(tracking.topic(3000)?.isSeen, isTrue);
    expect(tracking.topic(8000), isNull);
    expect(tracking.newActivityCounts, (newTopics: 0, newReplies: 0));
  });

  test('a live message costs the same however long the session has run', () {
    Duration timeMessages(int sessionTopics) {
      final tracking = TopicTrackingState();
      for (var id = 1; id <= sessionTopics; id++) {
        tracking.applyMessage(newTopicMessage(id));
        tracking.applyMessage(readMessage(id));
      }
      var next = sessionTopics;
      var counted = 0;
      var best = const Duration(days: 1);
      for (var round = 0; round < 5; round++) {
        final stopwatch = Stopwatch()..start();
        for (var message = 0; message < 100; message++) {
          next++;
          tracking.applyMessage(newTopicMessage(next));
          counted += tracking.newActivityCounts.newTopics;
          counted += tracking
              .tagBadge(tagId: 7, unifiedNew: true, showCount: true)
              .count;
          tracking.applyMessage(readMessage(next));
          counted += tracking.newActivityCounts.newTopics;
        }
        stopwatch.stop();
        if (stopwatch.elapsed < best) best = stopwatch.elapsed;
      }
      expect(counted, 1000);
      return best;
    }

    final small = timeMessages(2000);
    final large = timeMessages(16000);

    expect(
      large.inMicroseconds,
      lessThan(small.inMicroseconds * 4 + 2000),
      reason: 'eight times the session length: $small became $large',
    );
  });
}
