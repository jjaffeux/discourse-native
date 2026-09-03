import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/list_link.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContentRoute category identity', () {
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

    test('does not identify category or ordinary feeds as tags', () {
      expect(
        ContentRoute.list(ListLink.parse('/c/support/5')!).tagName,
        isNull,
      );
      expect(ContentRoute.topicList(TopicListMode.latest).tagName, isNull);
      expect(ContentRoute.list(ListLink.parse('/tag/41')!).tagName, isNull);
    });

    test('recognizes only recent, category, and tag lists as filters', () {
      expect(
        ContentRoute.topicList(TopicListMode.latest).isTopicListFilter,
        isTrue,
      );
      expect(
        ContentRoute.topicList(TopicListMode.topWeekly).isTopicListFilter,
        isFalse,
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
