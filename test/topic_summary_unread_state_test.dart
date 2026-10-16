import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/shell/unread_topic_feed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a sparse nested topic response is not proof that the topic is read',
    () {
      const models = DiscourseModelCodec.core();
      final topic = models.topicSummary({
        'id': 1,
        'title': 'Nested conversation',
        'slug': 'nested',
        'is_nested_view': true,
        'highest_post_number': 8,
        'last_read_post_number': 3,
      }, 'https://forum.example');
      expect(
        UnreadTopicFeed.isRead(
          topic: topic,
          tracking: null,
          localReadPostNumber: null,
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
    },
  );

  test('list responses retain their authoritative nested read state', () {
    const models = DiscourseModelCodec.core();
    final list = models.topicList({
      'topic_list': {
        'topics': [
          {
            'id': 1,
            'title': 'Nested conversation',
            'slug': 'nested',
            'is_nested_view': true,
          },
        ],
      },
    }, 'https://forum.example');
    expect(
      UnreadTopicFeed.isRead(
        topic: list.topics.single,
        tracking: null,
        localReadPostNumber: null,
      ),
      isTrue,
    );
  });
}
