import 'dart:math';

import 'package:discourse_native/src/models/category_directory.dart';
import 'package:discourse_native/src/models/category_sidebar.dart';
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

  test('directory preserves overlapping root and family order', () {
    const topicA = CategoryFeaturedTopic(id: 20, title: 'A', slug: 'a');
    const topicB = CategoryFeaturedTopic(id: 30, title: 'B', slug: 'b');
    final directory = CategoryDirectory(
      rootCategoryIds: [3, 1],
      categories: const [
        TopicCategory(id: 1, name: 'Parent', color: '111111'),
        TopicCategory(
          id: 2,
          name: 'A',
          color: '222222',
          parentCategoryId: 1,
          featuredTopics: [topicA],
        ),
        TopicCategory(
          id: 3,
          name: 'B',
          color: '333333',
          parentCategoryId: 1,
          featuredTopics: [topicB],
        ),
      ],
    );
    expect(directory.accessibleCategories.map((category) => category.id), [
      3,
      1,
      2,
    ]);
    final entries = directory.entries(unreadTopicCounts: {});
    expect(entries.map((entry) => entry.category.id), [3, 1]);
    expect(entries.last.subcategories.map((category) => category.id), [3, 2]);
    expect(entries.last.latestTopic, topicB);
    expect(
      directory
          .visibleCategories(parentCategoryId: 1)
          .map((category) => category.id),
      [3, 2],
    );
    expect(
      directory
          .visibleCategories(searching: true)
          .map((category) => category.id),
      [3, 1, 2],
    );
  });

  test('directory keeps full route ancestry outside accessible entries', () {
    final directory = CategoryDirectory(
      rootCategoryIds: [2, 999],
      categories: const [
        TopicCategory(
          id: 1,
          name: 'Sidebar parent',
          slug: 'parent',
          color: '111111',
        ),
        TopicCategory(
          id: 2,
          name: 'Listed child',
          slug: 'child',
          color: '222222',
          parentCategoryId: 1,
        ),
        TopicCategory(id: 3, name: 'Sidebar only', color: '333333'),
      ],
    );
    expect(directory.containsCategory(1), isFalse);
    expect(directory.containsCategory(3), isFalse);
    expect(directory.accessibleCategories.map((category) => category.id), [2]);
    expect(
      directory
          .visibleCategories(parentCategoryId: 1)
          .map((category) => category.id),
      [2],
    );
    final destination = buildCategoryDestination(
      directory.accessibleCategories.single,
      categoriesById: directory.categoriesById,
    );
    expect(destination.feedPath, '/c/parent/child/2.json');
  });

  test('directory preserves listed duplicates and last taxonomy value', () {
    final directory = CategoryDirectory(
      rootCategoryIds: [2, 1, 2, 999],
      categories: const [
        TopicCategory(id: 1, name: 'Parent', color: '111111'),
        TopicCategory(
          id: 2,
          name: 'Old child',
          color: '222222',
          parentCategoryId: 1,
        ),
        TopicCategory(
          id: 2,
          name: 'New child',
          color: '333333',
          parentCategoryId: 1,
        ),
      ],
    );
    final entries = directory.entries(unreadTopicCounts: {});
    expect(entries.map((entry) => entry.category.id), [2, 1, 2]);
    expect(entries.first.category.name, 'New child');
    expect(entries[1].subcategories.single.name, 'New child');
    expect(directory.accessibleCategories.map((category) => category.id), [
      2,
      1,
    ]);
  });

  test('directory cycles exclude each root and count each relative once', () {
    final directory = CategoryDirectory(
      rootCategoryIds: [1, 2],
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
    );
    final entries = directory.entries(unreadTopicCounts: {1: 4, 2: 5});
    expect(entries.first.subcategories.map((category) => category.id), [2]);
    expect(entries.last.subcategories.map((category) => category.id), [1]);
    expect(entries.map((entry) => entry.topicCount), [3, 3]);
    expect(entries.map((entry) => entry.unreadTopicCount), [9, 9]);
    expect(directory.accessibleCategories.map((category) => category.id), [
      1,
      2,
    ]);
  });

  test('directory projections read current unread and mute inputs', () {
    final directory = CategoryDirectory(
      rootCategoryIds: [1],
      categories: const [
        TopicCategory(id: 1, name: 'Parent', color: '111111'),
        TopicCategory(
          id: 2,
          name: 'Child',
          color: '222222',
          parentCategoryId: 1,
          topicCount: 7,
          featuredTopics: [
            CategoryFeaturedTopic(id: 20, title: 'Recent', slug: 'recent'),
          ],
        ),
      ],
    );
    final counts = {2: 2};
    final muted = <int>{};
    CategoryDirectoryEntry project() => directory
        .entries(unreadTopicCounts: counts, mutedCategoryIds: muted)
        .single;
    expect(project().unreadTopicCount, 2);
    counts[2] = 5;
    expect(project().unreadTopicCount, 5);
    muted.add(2);
    final mutedChild = project();
    expect(mutedChild.unreadTopicCount, 0);
    expect(mutedChild.latestTopic, isNull);
    expect(mutedChild.topicCount, 7);
    expect(mutedChild.matches(CategoryDirectoryScope.withTopics), isTrue);
    muted.clear();
    expect(project().latestTopic?.id, 20);
    muted.add(1);
    expect(project().muted, isTrue);
    expect(project().unreadTopicCount, 0);
    expect(project().latestTopic, isNull);
    muted.clear();
    expect(project().unreadTopicCount, 5);
  });

  test('directory candidate filtering preserves matched family and scope', () {
    final directory = CategoryDirectory(
      rootCategoryIds: [1],
      categories: const [
        TopicCategory(id: 1, name: 'Match', color: '111111'),
        TopicCategory(
          id: 2,
          name: 'Child',
          color: '222222',
          parentCategoryId: 1,
          topicCount: 7,
        ),
      ],
    );
    final entries = directory.entries(
      searching: true,
      matchesCategory: (category) => category.name == 'Match',
      scope: CategoryDirectoryScope.unread,
      unreadTopicCounts: {2: 3},
    );
    expect(entries.single.category.id, 1);
    expect(entries.single.subcategories.single.id, 2);
    expect(entries.single.unreadTopicCount, 3);
    expect(entries.single.topicCount, 7);
    expect(
      directory.entries(
        searching: true,
        matchesCategory: (category) => category.name == 'Match',
        scope: CategoryDirectoryScope.unread,
        unreadTopicCounts: {},
      ),
      isEmpty,
    );
  });

  test('scoped searches match text only for included families', () {
    final directory = CategoryDirectory(
      rootCategoryIds: [1, 3, 4],
      categories: const [
        TopicCategory(id: 1, name: 'Unread parent', color: '111111'),
        TopicCategory(
          id: 2,
          name: 'Unread child',
          color: '222222',
          parentCategoryId: 1,
          topicCount: 7,
        ),
        TopicCategory(id: 3, name: 'Empty', color: '333333'),
        TopicCategory(
          id: 4,
          name: 'Read topics',
          color: '444444',
          topicCount: 5,
        ),
      ],
    );
    for (final (scope, includedIds) in [
      (CategoryDirectoryScope.unread, [1, 2]),
      (CategoryDirectoryScope.withTopics, [1, 2, 4]),
      (CategoryDirectoryScope.all, [1, 2, 3, 4]),
    ]) {
      final matchedIds = <int>[];
      final entries = directory.entries(
        searching: true,
        scope: scope,
        matchesCategory: (category) {
          matchedIds.add(category.id);
          return true;
        },
        unreadTopicCounts: {2: 3},
      );
      expect(matchedIds, includedIds, reason: '$scope text matching');
      expect(entries.map((entry) => entry.category.id), includedIds);
    }
  });

  test(
    'directory matches two-pass preparation across seeded parent graphs',
    () {
      final random = Random(0xCA7E60);
      for (var sample = 0; sample < 80; sample++) {
        final categoryCount = random.nextInt(15);
        TopicCategory category(int id, int version) => TopicCategory(
          id: id,
          name: 'Category $id version $version',
          color: '123456',
          parentCategoryId: switch (random.nextInt(categoryCount + 3)) {
            0 => null,
            final parent => parent,
          },
          topicCount: random.nextInt(5),
          notificationLevel: random.nextBool()
              ? CategoryNotificationLevel.normal
              : CategoryNotificationLevel.muted,
          featuredTopics: [
            for (var index = 0; index < 2; index++)
              if (random.nextBool())
                CategoryFeaturedTopic(
                  id: id * 100 + version * 10 + index,
                  title: 'Topic $id $version $index',
                  slug: 'topic-$id-$version-$index',
                  activityAt: random.nextBool()
                      ? null
                      : DateTime.utc(2026, 10, 1 + random.nextInt(3)),
                ),
          ],
        );
        final categories = [
          for (var id = 1; id <= categoryCount; id++) category(id, 0),
        ]..shuffle(random);
        if (categoryCount > 0) {
          categories.add(category(1 + random.nextInt(categoryCount), 1));
        }
        final rootIds = [
          for (var index = 0; index < categoryCount + 2; index++)
            1 + random.nextInt(categoryCount + 2),
        ];
        if (rootIds.isNotEmpty) rootIds.add(rootIds.first);
        final directory = CategoryDirectory(
          rootCategoryIds: rootIds,
          categories: categories,
        );
        final counts = <int, int>{};
        final muted = <int>{};
        for (var revision = 0; revision < 2; revision++) {
          counts.clear();
          muted.clear();
          for (var id = 1; id <= categoryCount; id++) {
            counts[id] = random.nextInt(4);
            if (random.nextBool()) muted.add(id);
          }
          final roots = categoryDirectoryEntries(
            rootCategoryIds: rootIds,
            categories: categories,
            unreadTopicCounts: counts,
            mutedCategoryIds: muted,
          );
          final accessible = {
            for (final entry in roots)
              for (final category in [entry.category, ...entry.subcategories])
                category.id: category,
          };
          expect(
            directory.accessibleCategories,
            orderedEquals(accessible.values),
            reason: 'Accessible sample $sample revision $revision',
          );
          final views = <(bool, int?)>[
            (false, null),
            (true, null),
            (false, 999),
            for (final id in accessible.keys) (false, id),
          ];
          for (final (searching, requestedParent) in views) {
            final parentId = accessible.containsKey(requestedParent)
                ? requestedParent
                : null;
            final visibleIds = searching
                ? accessible.keys.toList()
                : parentId == null
                ? rootIds
                : [
                    for (final category in accessible.values)
                      if (category.parentCategoryId == parentId) category.id,
                  ];
            bool matches(TopicCategory category) =>
                sample.isEven || category.id % 3 == sample % 3;
            for (final scope in CategoryDirectoryScope.values) {
              final expected =
                  categoryDirectoryEntries(
                    rootCategoryIds: visibleIds,
                    categories: accessible.values,
                    unreadTopicCounts: counts,
                    mutedCategoryIds: muted,
                  ).where(
                    (entry) =>
                        entry.matches(scope) &&
                        (!searching || matches(entry.category)),
                  );
              final actual = directory.entries(
                parentCategoryId: requestedParent,
                searching: searching,
                scope: scope,
                matchesCategory: searching ? matches : null,
                unreadTopicCounts: counts,
                mutedCategoryIds: muted,
              );
              expect(
                actual.map(_entrySignature).toList(),
                expected.map(_entrySignature).toList(),
                reason:
                    'Sample $sample revision $revision view '
                    '$searching/$requestedParent scope $scope',
              );
            }
          }
        }
      }
    },
  );
}

List<Object?> _entrySignature(CategoryDirectoryEntry entry) => [
  entry.category,
  entry.subcategories,
  entry.muted,
  entry.unreadTopicCount,
  entry.topicCount,
  entry.latestTopic,
];
