import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/list_link.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('obsolete list search migration', () {
    test('restores list filters without their hidden search parameter', () {
      for (final source in [
        ContentRoute.topicList(TopicListMode.latest),
        ContentRoute.topicList(TopicListMode.newTopics),
        ContentRoute.topicList(TopicListMode.topWeekly),
        ContentRoute.list(ListLink.parse('/c/ux/42?status=open')!),
        ContentRoute.list(ListLink.parse('/tag/design?assigned=nobody')!),
        ContentRoute.filteredTopicList(
          TopicListMode.unread,
          categoryId: 42,
          tags: const ['design', 'mobile'],
        ),
      ]) {
        final legacy = source.withTopicListSearch('café & layout');
        final saved = {
          ...legacy.toJson(),
          'feed_path': '${legacy.feedPath}&page=3&custom[]=one&custom[]=two',
        };
        final restored = ContentRoute.fromJson(saved);
        final expectedQuery = {
          ...Uri.parse(saved['feed_path']! as String).queryParametersAll,
        }..remove('search');

        expect(restored.id, legacy.id);
        expect(restored.title, legacy.title);
        expect(restored.isTopicList, isTrue);
        expect(restored.categoryId, legacy.categoryId);
        expect(restored.tagNames, legacy.tagNames);
        expect(
          TopicListMode.fromRoute(restored),
          TopicListMode.fromRoute(legacy),
        );
        expect(restored.topicListSearch, isEmpty);
        expect(Uri.parse(restored.feedPath!).queryParametersAll, expectedQuery);
        expect(ContentRoute.fromJson(restored.toJson()), restored);
      }
    });

    test('removes a sole search parameter without leaving an empty query', () {
      final legacy = ContentRoute.topicList(
        TopicListMode.latest,
      ).withTopicListSearch('layout');
      expect(ContentRoute.fromJson(legacy.toJson()).feedPath, '/latest.json');
    });

    test(
      'preserves unrelated search parameters on topic and plugin routes',
      () {
        for (final source in const [
          ContentRoute(
            id: 'topic-42',
            title: 'Topic',
            icon: DIcons.comments,
            topicId: 42,
            feedPath: '/latest.json?search=layout',
          ),
          ContentRoute(
            id: 'plugin-custom',
            title: 'Plugin',
            icon: DIcons.magnifyingGlass,
            feedPath: '/plugin-custom.json?search=layout',
          ),
        ]) {
          final restored = ContentRoute.fromJson(source.toJson());
          expect(restored.feedPath, source.feedPath);
          expect(restored.id, source.id);
        }
      },
    );

    test('migrates back and forward routes without losing tab anchors', () {
      final past = ContentRoute.topicList(
        TopicListMode.latest,
      ).withTopicListSearch('layout');
      final future = ContentRoute.topicList(
        TopicListMode.unread,
      ).withTopicListSearch('design');
      final tab = ForumTab(
        id: 'saved-tab',
        rootDestinationId: 'latest',
        contentStack: [
          past,
          ContentRoute.topic(topicId: 42, slug: 'design', title: 'Design'),
        ],
        forwardStack: [future],
        anchors: {
          past.id: const ForumTabAnchor(kind: 'feed', itemId: 17),
          future.id: const ForumTabAnchor(kind: 'feed', itemId: 19),
        },
      );
      final restored = ForumTab.tryFromJson(tab.toJson())!;
      expect(restored.contentStack.first.feedPath, '/latest.json');
      expect(restored.forwardStack.single.feedPath, '/unread.json');
      expect(restored.currentContent.topicId, 42);
      expect(restored.anchors[past.id]?.itemId, 17);
      expect(restored.anchors[future.id]?.itemId, 19);
    });
  });

  test('restored routes reject feed components that cannot be decoded', () {
    final saved = ContentRoute.topicList(TopicListMode.topYearly).toJson();
    for (final path in [
      '/tag/%FF.json',
      '/top.json?period=%C3',
      '/latest.json?tags[]=%ED%A0%80',
    ]) {
      expect(
        () => ContentRoute.fromJson({...saved, 'feed_path': path}),
        throwsFormatException,
        reason: path,
      );
    }
  });

  group('ContentRoute category identity', () {
    test('restores slug-only category lists with distinct query filters', () {
      final open = ContentRoute.list(
        ListLink.parse('/c/todo?status=open&assigned=nobody')!,
      );
      final closed = ContentRoute.list(
        ListLink.parse('/c/todo?status=closed&assigned=nobody')!,
      );
      final restored = ContentRoute.fromJson(open.toJson());

      expect(restored.id, open.id);
      expect(restored.id, isNot(closed.id));
      expect(restored.feedPath, '/c/todo.json?status=open&assigned=nobody');
      expect(restored.isTopicList, isTrue);
      expect(restored.isTopicListFilter, isTrue);
      expect(restored.title, 'Todo');
    });

    test('resolves the root category while retaining the feed identity', () {
      final route = ContentRoute.list(
        ListLink.parse('/c/todo?status=open&assigned=nobody')!,
      );
      final resolved = route.resolveCategoryLink(const [
        TopicCategory(
          id: 9,
          name: 'Nested Todo',
          slug: 'todo',
          color: '112233',
          parentCategoryId: 3,
        ),
        TopicCategory(id: 5, name: 'Todo', slug: 'todo', color: '112233'),
      ]);

      expect(resolved.id, route.id);
      expect(resolved, isNot(route));
      expect(resolved.categoryId, 5);
      expect(resolved.feedPath, '/c/todo/5.json?status=open&assigned=nobody');
      expect(ContentRoute.fromJson(resolved.toJson()).categoryId, 5);
    });

    test('resolves encoded category slugs and leaves unknown slugs alone', () {
      final route = ContentRoute.list(ListLink.parse('/c/caf%C3%A9')!);
      expect(route.resolveCategoryLink(const []), same(route));
      final resolved = route.resolveCategoryLink(const [
        TopicCategory(id: 5, name: 'Café', slug: 'caf%C3%A9', color: '112233'),
      ]);

      expect(resolved.categoryId, 5);
      expect(resolved.feedPath, '/c/caf%C3%A9/5.json');
    });

    test('dropdown changes retain filters but replace selections and page', () {
      final source = ContentRoute.list(
        ListLink.parse(
          '/c/todo/5?status=open&assigned=nobody&category=5&tags[]=old'
          '&page=3&period=daily&subset=topics&custom[]=one&custom[]=two',
        )!,
      );
      final route = ContentRoute.filteredTopicList(
        TopicListMode.topWeekly,
        categoryId: 6,
        tags: const ['urgent'],
      ).withTopicListQueryFrom(source);

      expect(TopicListMode.fromRoute(route), TopicListMode.topWeekly);
      expect(Uri.parse(route.feedPath!).queryParametersAll, {
        'status': ['open'],
        'assigned': ['nobody'],
        'custom[]': ['one', 'two'],
        'period': ['weekly'],
        'category': ['6'],
        'tags[]': ['urgent'],
        'match_all_tags': ['true'],
      });
    });

    test('reads top-level and nested category feed paths', () {
      expect(ContentRoute.list(ListLink.parse('/c/support/5')!).categoryId, 5);
      expect(
        ContentRoute.list(ListLink.parse('/c/parent/support/12')!).categoryId,
        12,
      );
    });

    test('does not identify tag or ordinary feed routes as categories', () {
      expect(
        ContentRoute.list(ListLink.parse('/tag/support/5')!).categoryId,
        isNull,
      );
      expect(ContentRoute.topicList(TopicListMode.latest).categoryId, isNull);
    });

    test('reads a category from a combined category and tag route', () {
      const withoutTagId = ContentRoute(
        id: 'filtered',
        title: 'Native',
        icon: DIcons.folder,
        feedPath: '/tags/c/discourse-native/12/ux.json',
      );
      const withTagId = ContentRoute(
        id: 'filtered',
        title: 'Native',
        icon: DIcons.folder,
        feedPath: '/tags/c/meta/discourse-native/12/ux/41.json',
      );
      const idOnlyCategory = ContentRoute(
        id: 'filtered',
        title: 'Native',
        icon: DIcons.folder,
        feedPath: '/tags/c/12/ux.json',
      );

      expect(withoutTagId.categoryId, 12);
      expect(withTagId.categoryId, 12);
      expect(idOnlyCategory.categoryId, 12);
    });
  });

  group('ContentRoute tag identity', () {
    test('reads slug-only, identified, and category-scoped tag routes', () {
      expect(ContentRoute.list(ListLink.parse('/tag/ux')!).tagName, 'ux');
      expect(ContentRoute.list(ListLink.parse('/tag/ux/41')!).tagName, 'ux');
      expect(
        const ContentRoute(
          id: 'filtered',
          title: 'Native',
          icon: DIcons.folder,
          feedPath: '/tags/c/discourse-native/12/design-feedback.json',
        ).tagName,
        'design-feedback',
      );
      expect(
        const ContentRoute(
          id: 'filtered',
          title: 'Native',
          icon: DIcons.folder,
          feedPath: '/tags/c/discourse-native/12/design-feedback/41.json',
        ).tagName,
        'design-feedback',
      );
    });

    test('filtered modes round trip category, multiple tags, and period', () {
      for (final mode in TopicListMode.values) {
        final route = ContentRoute.filteredTopicList(
          mode,
          categoryId: 22,
          tags: const ['community', 'design-feedback'],
        );
        final restored = ContentRoute.fromJson(route.toJson());
        expect(TopicListMode.fromRoute(restored), mode);
        expect(restored.categoryId, 22);
        expect(restored.tagNames, ['community', 'design-feedback']);
        expect(restored.isTopicList, isTrue);
        final uri = Uri.parse(restored.feedPath!);
        expect(uri.queryParametersAll['tags[]'], [
          'community',
          'design-feedback',
        ]);
        expect(uri.queryParameters['match_all_tags'], 'true');
        if (mode.topPeriod case final period?) {
          expect(uri.queryParameters['period'], period.queryValue);
        }
      }
    });

    test('does not identify category or ordinary feeds as tags', () {
      expect(
        ContentRoute.list(ListLink.parse('/c/support/5')!).tagName,
        isNull,
      );
      expect(ContentRoute.topicList(TopicListMode.latest).tagName, isNull);
      expect(ContentRoute.list(ListLink.parse('/tag/41')!).tagName, isNull);
    });

    test('recognizes discovery modes, category, and tag lists as filters', () {
      expect(
        ContentRoute.topicList(TopicListMode.latest).isTopicListFilter,
        isTrue,
      );
      expect(
        ContentRoute.topicList(TopicListMode.topWeekly).isTopicListFilter,
        isTrue,
      );
      expect(
        ContentRoute.list(ListLink.parse('/c/support/5')!).isTopicListFilter,
        isTrue,
      );
      expect(
        ContentRoute.list(ListLink.parse('/tag/ux')!).isTopicListFilter,
        isTrue,
      );
    });
  });
}
