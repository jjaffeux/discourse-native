import 'dart:isolate';

import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _categories = [
  TopicCategory(id: 1, name: 'Parent', color: '111111'),
  TopicCategory(id: 2, name: 'Child', color: '222222', parentCategoryId: 1),
  TopicCategory(
    id: 3,
    name: 'Grandchild',
    color: '333333',
    parentCategoryId: 2,
  ),
  TopicCategory(id: 4, name: 'Other', color: '444444'),
];

void _verify(
  TopicTrackingState tracking, {
  List<TopicCategory> categories = _categories,
}) {
  final fresh = TopicTrackingState(tracking.topics.toList());
  expect(tracking.newActivityCounts, fresh.newActivityCounts);
  for (final categoryId in <int?>[null, 1, 2, 3, 4, 99]) {
    for (final tagIds in <Set<int>>[
      {},
      {7},
      {8},
      {7, 8},
      {9},
    ]) {
      expect(
        tracking.newActivityCountsFor(
          categoryId: categoryId,
          categories: categories,
          tagIds: tagIds,
        ),
        fresh.newActivityCountsFor(
          categoryId: categoryId,
          categories: categories,
          tagIds: tagIds,
        ),
        reason: 'category $categoryId and tags $tagIds',
      );
    }
  }
}

Map<String, Object?> _message(
  int id,
  String type, [
  Map<String, Object?> payload = const {},
]) => {'topic_id': id, 'message_type': type, 'payload': payload};

void main() {
  test(
    'worker-built tracking retains equivalent counts after transfer',
    () async {
      for (final warm in [false, true]) {
        final tracking = await Isolate.run(() {
          final state = TopicTrackingState.fromJson(const [
            {
              'topic_id': 1,
              'highest_post_number': 5,
              'last_read_post_number': 1,
              'notification_level': 2,
              'category_id': 3,
              'tags': [
                {'id': 7},
                {'id': 8},
              ],
            },
          ]);
          if (warm) {
            state.newActivityCounts;
            state.newActivityCountsFor(categoryId: 1, categories: _categories);
            state.newActivityCountsFor(tagIds: {7, 8});
          }
          return state;
        });
        _verify(tracking);
        expect(tracking.markRead(1, 5), isTrue);
        _verify(tracking);
        expect(tracking.newActivityCounts, (newTopics: 0, newReplies: 0));
      }
    },
  );
  test('warm counts follow live membership and count transitions', () {
    final tracking = TopicTrackingState([
      const TrackedTopicState(
        topicId: 1,
        highestPostNumber: 5,
        lastReadPostNumber: 1,
        notificationLevel: 2,
        categoryId: 3,
        tagIds: {7, 8},
      ),
      const TrackedTopicState(
        topicId: 2,
        highestPostNumber: 1,
        createdInNewPeriod: true,
        categoryId: 2,
        tagIds: {7},
      ),
      const TrackedTopicState(
        topicId: 3,
        highestPostNumber: 5,
        lastReadPostNumber: 1,
        notificationLevel: 2,
        categoryId: 2,
        isCategoryTopic: true,
        tagIds: {8},
      ),
    ]);
    _verify(tracking);
    final events = [
      _message(1, 'unread', {'highest_post_number': 6}),
      _message(1, 'read', {
        'category_id': 4,
        'tags': [
          {'id': 9},
        ],
      }),
      _message(3, 'read', {'is_category_topic': false}),
      _message(2, 'notification_level_change', {'notification_level': 0}),
      _message(2, 'notification_level_change', {'notification_level': 3}),
      _message(3, 'delete'),
      _message(3, 'recover'),
      _message(2, 'dismiss_new', {
        'topic_ids': [2],
      }),
      _message(1, 'dismiss_new_posts', {
        'topic_ids': [1, 3],
      }),
      _message(3, 'destroy'),
      _message(4, 'new_topic', {
        'category_id': 3,
        'created_in_new_period': true,
        'tags': [
          {'id': 7},
          {'id': 8},
        ],
      }),
      _message(4, 'unread', {
        'highest_post_number': 3,
        'last_read_post_number': 1,
      }),
      _message(4, 'read', {
        'category_id': 2,
        'is_category_topic': true,
        'tags': [
          {'id': 8},
        ],
      }),
    ];
    for (final event in events) {
      expect(tracking.applyMessage(event), isTrue, reason: '$event');
      _verify(tracking);
    }
    expect(tracking.markRead(4, 3), isTrue);
    _verify(tracking);
    tracking.markLastPostUnread(4, 2);
    _verify(tracking);
    expect(
      tracking.applyMessage(
        _message(4, 'unread', {
          'highest_post_number': 1,
          'last_read_post_number': 0,
        }),
      ),
      isFalse,
    );
    _verify(tracking);
    const detached = [
      TopicCategory(id: 1, name: 'Parent', color: '111111'),
      TopicCategory(id: 2, name: 'Child', color: '222222'),
      TopicCategory(
        id: 3,
        name: 'Grandchild',
        color: '333333',
        parentCategoryId: 2,
      ),
    ];
    _verify(tracking, categories: detached);
    expect(
      tracking.applyMessage(_message(4, 'read', {'is_category_topic': false})),
      isTrue,
    );
    _verify(tracking, categories: detached);
    _verify(tracking);
  });

  test('settled eviction removes indexed rows before a later scoped query', () {
    final tracking = TopicTrackingState([
      for (var id = 1; id <= 1024; id++)
        TrackedTopicState(
          topicId: id,
          highestPostNumber: 1,
          lastReadPostNumber: 1,
          notificationLevel: 2,
          categoryId: 2,
          tagIds: {7},
        ),
    ]);
    _verify(tracking);
    for (var id = 1025; id <= 1030; id++) {
      expect(
        tracking.applyMessage(
          _message(id, 'read', {
            'highest_post_number': 1,
            'last_read_post_number': 1,
            'category_id': 2,
            'notification_level': 2,
            'tags': [
              {'id': 7},
            ],
          }),
        ),
        isTrue,
      );
      _verify(tracking);
    }
    expect(tracking.topic(1), isNull);
    expect(tracking.topics, hasLength(1024));
    expect(
      tracking.applyMessage(
        _message(1, 'unread', {
          'highest_post_number': 2,
          'category_id': 4,
          'tags': [
            {'id': 9},
          ],
        }),
      ),
      isTrue,
    );
    _verify(tracking);
    expect(
      tracking.newActivityCountsFor(
        categoryId: 1,
        categories: _categories,
        tagIds: {7},
      ),
      (newTopics: 0, newReplies: 0),
    );
    expect(
      tracking.newActivityCountsFor(
        categoryId: 4,
        categories: _categories,
        tagIds: {9},
      ),
      (newTopics: 0, newReplies: 1),
    );
  });

  test(
    'warm reports reconcile omitted rows and retain their own settled recency',
    () {
      final previous = TopicTrackingState([
        for (var id = 1; id <= 1030; id++)
          TrackedTopicState(
            topicId: id,
            highestPostNumber: 3,
            lastReadPostNumber: id.isEven ? 1 : 3,
            notificationLevel: 2,
            categoryId: 2,
            tagIds: {7},
          ),
        const TrackedTopicState(
          topicId: 2000,
          highestPostNumber: 1,
          createdInNewPeriod: true,
          categoryId: 3,
          tagIds: {8},
        ),
      ]);
      for (final complete in [false, true]) {
        final report = TopicTrackingState([
          const TrackedTopicState(
            topicId: 3000,
            highestPostNumber: 2,
            lastReadPostNumber: 1,
            notificationLevel: 2,
            categoryId: 3,
            tagIds: {7, 8},
          ),
          const TrackedTopicState(
            topicId: 4000,
            highestPostNumber: 2,
            lastReadPostNumber: 2,
            notificationLevel: 2,
            categoryId: 4,
            tagIds: {9},
          ),
        ]);
        _verify(report);
        report.keepOmitted(previous, complete: complete);
        _verify(report);
        expect(report.newActivityCounts, (newTopics: 0, newReplies: 1));
        expect(report.topic(4000), isNotNull);
        expect(
          report.applyMessage(
            _message(2, 'unread', {
              'highest_post_number': 4,
              'last_read_post_number': 3,
              'category_id': 2,
              'notification_level': 2,
              'tags': [
                {'id': 7},
              ],
            }),
          ),
          isTrue,
        );
        _verify(report);
      }
    },
  );
}
