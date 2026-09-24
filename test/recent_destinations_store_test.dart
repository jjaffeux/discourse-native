import 'dart:convert';

import 'package:discourse_native/src/data/recent_destinations_store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example';
const _account = 'user:1';

const _fromSidebar = ContentRoute(
  id: 'category-12',
  title: 'Discourse Native App',
  icon: DIcons.folder,
  feedPath: '/c/discourse-native-app/12.json',
);

const _fromLink = ContentRoute(
  id: 'list-/c/native/12.json',
  title: 'Discourse Native App',
  icon: DIcons.folder,
  feedPath: '/c/native/12.json',
);

const _other = ContentRoute(
  id: 'category-13',
  title: 'Support',
  icon: DIcons.folder,
  feedPath: '/c/support/13.json',
);

void main() {
  group('RecentDestinationsStore categories', () {
    test('a category opened from the sidebar and from a link is one visit', () {
      final store = RecentDestinationsStore.memory();

      store.remember(_site, _account, _fromSidebar);
      store.remember(_site, _account, _other);
      expect(store.remember(_site, _account, _fromLink), isTrue);

      expect(store.categoriesFor(_site, _account).map((route) => route.id), [
        _fromLink.id,
        _other.id,
      ]);
    });

    test('distinct slug-only links stay distinct', () {
      final store = RecentDestinationsStore.memory();
      const first = ContentRoute(
        id: 'list-/c/general.json',
        title: 'General',
        icon: DIcons.folder,
        feedPath: '/c/general.json',
      );
      const second = ContentRoute(
        id: 'list-/c/support.json',
        title: 'Support',
        icon: DIcons.folder,
        feedPath: '/c/support.json',
      );

      store.remember(_site, _account, first);
      store.remember(_site, _account, second);

      expect(store.categoriesFor(_site, _account).map((route) => route.id), [
        second.id,
        first.id,
      ]);
    });

    test('duplicates saved by an earlier build collapse on load', () async {
      final persistence = MemoryRecentDestinationsPersistence()
        ..value = jsonEncode({
          'version': RecentDestinationsStore.formatVersion,
          'entries': [
            {
              'site_url': _site,
              'account_identity': _account,
              'categories': [
                _fromLink.toJson(),
                _fromSidebar.toJson(),
                _other.toJson(),
              ],
              'channels': const <Object>[],
              'topics': const <Object>[],
            },
          ],
        });
      final store = RecentDestinationsStore(persistence: persistence);

      await store.load();

      expect(store.categoriesFor(_site, _account).map((route) => route.id), [
        _fromLink.id,
        _other.id,
      ]);
    });
  });
}
