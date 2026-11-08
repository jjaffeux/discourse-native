import 'package:discourse_native/src/models/topic_reading_policy.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/shell/unread_topic_feed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/topic_reading_policy_fixture.dart';

void main() {
  test('sparse activity metadata cannot establish catch-up', () {
    const models = DiscourseModelCodec.core();
    final topic = models
        .topicSummary({
          'id': 1,
          'title': 'Activity conversation',
          'slug': 'activity',
          'highest_post_number': 8,
          'last_read_post_number': 3,
        }, 'https://forum.example')
        .copyWith(plugins: activityTopicData(TopicActivityState.unknown));
    expect(
      UnreadTopicFeed.isRead(
        topic: topic,
        tracking: null,
        localReadPostNumber: 8,
      ),
      isFalse,
    );
    expect(
      UnreadTopicFeed.isRead(
        topic: topic.copyWith(markRead: true),
        tracking: null,
        localReadPostNumber: null,
      ),
      isTrue,
    );
  });

  test('authoritative activity state can settle a list row', () {
    const models = DiscourseModelCodec.core();
    final row = models
        .topicList({
          'topic_list': {
            'topics': [
              {'id': 1, 'title': 'Activity conversation', 'slug': 'activity'},
            ],
          },
        }, 'https://forum.example')
        .topics
        .single
        .copyWith(plugins: activityTopicData(TopicActivityState.caughtUp));
    expect(
      UnreadTopicFeed.isRead(
        topic: row,
        tracking: null,
        localReadPostNumber: null,
      ),
      isTrue,
    );
  });
}
