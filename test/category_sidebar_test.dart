import 'package:discourse_native/src/models/category_sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a hostile deep category chain cannot exhaust the call stack', () {
    final categories = [
      for (var id = 1; id <= 10000; id++)
        TopicCategory(
          id: id,
          name: 'Category $id',
          color: '123456',
          slug: 'category-$id',
          parentCategoryId: id == 1 ? null : id - 1,
        ),
    ];

    final section = buildCategorySidebarSection(
      categories: categories,
      connected: true,
      preferredCategoryIds: const [1],
    );

    expect(section.destinations.map((entry) => entry.id), [
      'category-1',
      'all-categories',
    ]);
  });

  test('anonymous fallback keeps the five most active root categories', () {
    const categories = [
      TopicCategory(
        id: 1,
        name: 'Zulu',
        color: '111111',
        slug: 'zulu',
        topicCount: 90,
      ),
      TopicCategory(
        id: 2,
        name: 'Zulu child',
        color: '222222',
        slug: 'child',
        parentCategoryId: 1,
      ),
      TopicCategory(
        id: 3,
        name: 'Beta',
        color: '333333',
        slug: 'beta',
        topicCount: 80,
      ),
      TopicCategory(
        id: 4,
        name: 'Gamma',
        color: '444444',
        slug: 'gamma',
        topicCount: 70,
      ),
      TopicCategory(
        id: 5,
        name: 'Delta',
        color: '555555',
        slug: 'delta',
        topicCount: 60,
      ),
      TopicCategory(
        id: 6,
        name: 'Epsilon',
        color: '666666',
        slug: 'epsilon',
        topicCount: 50,
      ),
      TopicCategory(
        id: 7,
        name: 'Sixth',
        color: '777777',
        slug: 'sixth',
        topicCount: 100,
      ),
    ];

    final section = buildCategorySidebarSection(
      categories: categories,
      connected: false,
    );

    expect(section.title, 'Categories');
    expect(section.destinations.map((destination) => destination.label), [
      'Sixth',
      'Zulu',
      'Beta',
      'Gamma',
      'Delta',
      'All categories',
    ]);
    expect(section.destinations.last.icon, DIcons.list);
    expect(section.destinations.last.url, isNull);
  });

  test('connected fallback chooses by activity then displays by hierarchy', () {
    const categories = [
      TopicCategory(id: 1, name: 'Zulu', color: '111111', topicCount: 9),
      TopicCategory(id: 2, name: 'Beta', color: '222222', topicCount: 8),
      TopicCategory(id: 3, name: 'Gamma', color: '333333', topicCount: 7),
      TopicCategory(id: 4, name: 'Delta', color: '444444', topicCount: 6),
      TopicCategory(id: 5, name: 'Epsilon', color: '555555', topicCount: 5),
      TopicCategory(id: 6, name: 'Alpha', color: '666666', topicCount: 1),
    ];

    final section = buildCategorySidebarSection(
      categories: categories,
      connected: true,
    );

    expect(section.destinations.map((destination) => destination.label), [
      'Beta',
      'Delta',
      'Epsilon',
      'Gamma',
      'Zulu',
      'All categories',
    ]);
  });

  test('anonymous defaults follow fixed category positions', () {
    const categories = [
      TopicCategory(id: 1, name: 'Alpha', color: '111111', position: 20),
      TopicCategory(id: 2, name: 'Zulu', color: '222222', position: 10),
      TopicCategory(id: 3, name: 'Ignored', color: '333333', position: 1),
    ];

    final section = buildCategorySidebarSection(
      categories: categories,
      connected: false,
      defaultCategoryIds: const [1, 2],
      fixedCategoryPositions: true,
    );

    expect(section.destinations.map((destination) => destination.label), [
      'Zulu',
      'Alpha',
      'All categories',
    ]);
  });

  test('fixed positions place unknown positions last', () {
    const categories = [
      TopicCategory(id: 1, name: 'Unknown', color: '111111'),
      TopicCategory(id: 2, name: 'Second', color: '222222', position: 2),
      TopicCategory(id: 3, name: 'First', color: '333333', position: 1),
    ];

    final section = buildCategorySidebarSection(
      categories: categories,
      connected: false,
      fixedCategoryPositions: true,
    );

    expect(section.destinations.map((destination) => destination.label), [
      'First',
      'Second',
      'Unknown',
      'All categories',
    ]);
  });

  test('disabled Uncategorized is filtered from explicit choices', () {
    const categories = [
      TopicCategory(
        id: 1,
        name: 'Uncategorized',
        color: '888888',
        isUncategorized: true,
      ),
      TopicCategory(id: 2, name: 'Support', color: '222222'),
    ];

    final hidden = buildCategorySidebarSection(
      categories: categories,
      connected: true,
      preferredCategoryIds: const [1, 2],
    );
    final shown = buildCategorySidebarSection(
      categories: categories,
      connected: true,
      preferredCategoryIds: const [1],
      allowUncategorizedTopics: true,
    );

    expect(hidden.destinations.map((destination) => destination.label), [
      'Support',
      'All categories',
    ]);
    expect(shown.destinations.map((destination) => destination.label), [
      'Uncategorized',
      'All categories',
    ]);
  });

  test('preferred categories follow hierarchy and carry core styling', () {
    const categories = [
      TopicCategory(id: 1, name: 'Parent', color: '123', slug: 'parent'),
      TopicCategory(
        id: 2,
        name: 'Child',
        color: '456',
        slug: 'child',
        parentCategoryId: 1,
        readRestricted: true,
      ),
      TopicCategory(
        id: 3,
        name: 'Announcements',
        color: '778899',
        slug: 'announcements',
        styleType: 'icon',
        icon: 'fire',
      ),
      TopicCategory(
        id: 4,
        name: 'Emoji',
        color: 'AABBCC',
        slug: 'emoji',
        styleType: 'emoji',
        emoji: 'sparkles',
      ),
    ];

    final section = buildCategorySidebarSection(
      categories: categories,
      connected: true,
      preferredCategoryIds: const [2, 4, 3],
    );

    expect(section.destinations.map((destination) => destination.label), [
      'Announcements',
      'Emoji',
      'Child',
      'All categories',
    ]);

    final announcements = section.destinations[0];
    expect(announcements.icon, DIcons.fire);
    expect(announcements.color, isNull);
    expect(announcements.iconColor, const Color(0xFF778899));
    expect(announcements.routeColor, const Color(0xFF778899));

    final emoji = section.destinations[1];
    expect(emoji.emoji, 'sparkles');
    expect(emoji.color, isNull);
    expect(emoji.routeColor, const Color(0xFFAABBCC));

    final child = section.destinations[2];
    expect(child.color, const Color(0xFF445566));
    expect(child.parentColor, const Color(0xFF112233));
    expect(child.prefixBadgeIcon, DIcons.lock);
    expect(child.feedPath, '/c/parent/child/2.json');
  });
}
