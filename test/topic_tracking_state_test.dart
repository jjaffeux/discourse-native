import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
