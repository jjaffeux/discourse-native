import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/shell/unread_topic_feed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps the open topic and restores a topic with another reply', () {
    const source = TopicFeed(
      topicIds: [1, 2, 3],
      loaded: true,
      nextPagePath: '/unread.json?page=1',
    );
    final queue = UnreadTopicFeed();
    final read = {1};
    expect(
      queue.project(source, selectedTopicId: 1, isRead: read.contains),
      same(source),
    );
    final moved = queue.project(
      source,
      selectedTopicId: 2,
      isRead: read.contains,
    );
    expect(moved.topicIds, [2, 3]);
    expect(moved.nextPagePath, source.nextPagePath);
    expect(source.topicIds, [1, 2, 3]);
    expect(
      queue.project(source, selectedTopicId: 2, isRead: read.contains),
      same(moved),
    );
    read.remove(1);
    expect(
      queue.project(source, selectedTopicId: 2, isRead: read.contains).topicIds,
      [1, 2, 3],
    );
  });

  test('requires read progress through the highest known reply', () {
    const row = Topic(
      id: 1,
      title: 'Topic',
      slug: 'topic',
      highestPostNumber: 10,
      lastReadPostNumber: 4,
      unreadPosts: 6,
    );
    bool isRead({
      Topic? topic = row,
      TrackedTopicState? tracking,
      int? local,
    }) => UnreadTopicFeed.isRead(
      topic: topic,
      tracking: tracking,
      localReadPostNumber: local,
    );
    expect(isRead(local: 9), isFalse);
    expect(isRead(local: 10), isTrue);
    expect(
      isRead(topic: row.copyWith(highestPostNumber: 11), local: 10),
      isFalse,
    );
    expect(
      isRead(
        local: 10,
        tracking: const TrackedTopicState(topicId: 1, highestPostNumber: 11),
      ),
      isFalse,
    );
    expect(
      isRead(
        tracking: const TrackedTopicState(
          topicId: 1,
          highestPostNumber: 10,
          lastReadPostNumber: 10,
        ),
      ),
      isTrue,
    );
    expect(isRead(topic: null, local: 10), isFalse);
    expect(
      isRead(
        topic: const Topic(id: 2, title: 'Sparse', slug: 'sparse'),
      ),
      isFalse,
    );
  });

  test('nested conversations use their reply flag', () {
    const row = Topic(
      id: 1,
      title: 'Nested',
      slug: 'nested',
      isNestedView: true,
      hasNewReplies: true,
      lastReadPostNumber: 10,
      highestPostNumber: 10,
    );
    expect(
      UnreadTopicFeed.isRead(
        topic: row,
        tracking: null,
        localReadPostNumber: 10,
      ),
      isFalse,
    );
    expect(
      UnreadTopicFeed.isRead(
        topic: row.copyWith(markRead: true),
        tracking: null,
        localReadPostNumber: 10,
      ),
      isTrue,
    );
  });
}
