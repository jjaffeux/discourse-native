import 'package:discourse_native/src/models/category_directory.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses only server-listed roots and accessible descendants in order', () {
    final entries = categoryDirectoryEntries(
      rootCategoryIds: [2, 1, 999],
      categories: const [
        TopicCategory(
          id: 1,
          name: 'Private read-only',
          color: '111111',
          readRestricted: true,
          permission: 2,
        ),
        TopicCategory(id: 2, name: 'Parent', color: '222222'),
        TopicCategory(
          id: 3,
          name: 'Child',
          color: '333333',
          parentCategoryId: 2,
          topicCount: 8,
        ),
        TopicCategory(
          id: 4,
          name: 'Grandchild',
          color: '444444',
          parentCategoryId: 3,
          topicCount: 2,
        ),
        TopicCategory(
          id: 5,
          name: 'Sidebar-only root',
          color: '555555',
          topicCount: 9,
        ),
      ],
      unreadTopicCounts: {4: 2, 999: 7},
    );
    expect(entries.map((entry) => entry.category.id), [2, 1]);
    expect(entries.first.subcategories.map((category) => category.id), [3, 4]);
    expect(entries.first.topicCount, 10);
    expect(entries.first.unreadTopicCount, 2);
    expect(entries.first.matches(CategoryDirectoryScope.withTopics), isTrue);
    expect(entries.first.matches(CategoryDirectoryScope.unread), isTrue);
    expect(entries.last.matches(CategoryDirectoryScope.unread), isFalse);
  });

  test('selects latest reported activity instead of an older pinned topic', () {
    final old = CategoryFeaturedTopic.fromJson(const {
      'id': 1,
      'title': 'Pinned',
      'pinned': true,
      'bumped_at': '2020-01-01T00:00:00Z',
    });
    final recent = CategoryFeaturedTopic.fromJson(const {
      'id': 2,
      'title': 'Recent',
      'last_posted_at': '2026-09-29T00:00:00Z',
    });
    final entry = categoryDirectoryEntries(
      rootCategoryIds: [1],
      categories: [
        TopicCategory(
          id: 1,
          name: 'General',
          color: '111111',
          featuredTopics: [old, recent],
        ),
      ],
      unreadTopicCounts: {},
    ).single;
    expect(entry.latestTopic, recent);
    expect(entry.matches(CategoryDirectoryScope.withTopics), isTrue);
    expect(old.activityAt, DateTime.utc(2020));
    expect(recent.activityAt, DateTime.utc(2026, 9, 29));
    expect(
      recent,
      isNot(
        CategoryFeaturedTopic(
          id: recent.id,
          title: recent.title,
          slug: recent.slug,
        ),
      ),
    );
  });

  test('muting suppresses activity without hiding categories with topics', () {
    final entries = categoryDirectoryEntries(
      rootCategoryIds: [1, 2],
      categories: const [
        TopicCategory(
          id: 1,
          name: 'Muted',
          color: '111111',
          notificationLevel: CategoryNotificationLevel.muted,
          featuredTopics: [
            CategoryFeaturedTopic(id: 10, title: 'Quiet', slug: 'quiet'),
          ],
        ),
        TopicCategory(id: 2, name: 'Parent', color: '222222'),
        TopicCategory(
          id: 3,
          name: 'Indirectly muted',
          color: '333333',
          parentCategoryId: 2,
          topicCount: 3,
        ),
      ],
      unreadTopicCounts: {1: 1, 3: 2},
      mutedCategoryIds: {3},
    );
    expect(
      entries.every(
        (entry) => entry.matches(CategoryDirectoryScope.withTopics),
      ),
      isTrue,
    );
    expect(
      entries.every((entry) => !entry.matches(CategoryDirectoryScope.unread)),
      isTrue,
    );
    expect(entries.first.latestTopic, isNull);
    expect(entries.last.subcategories.single.id, 3);
  });

  test('ignores cyclic parent references without repeating counts', () {
    final entry = categoryDirectoryEntries(
      rootCategoryIds: [1],
      categories: const [
        TopicCategory(
          id: 1,
          name: 'One',
          color: '111111',
          parentCategoryId: 2,
          topicCount: 1,
        ),
        TopicCategory(
          id: 2,
          name: 'Two',
          color: '222222',
          parentCategoryId: 1,
          topicCount: 2,
        ),
      ],
      unreadTopicCounts: {},
    ).single;
    expect(entry.subcategories.map((category) => category.id), [2]);
    expect(entry.topicCount, 3);
  });
}
