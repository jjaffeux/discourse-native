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
