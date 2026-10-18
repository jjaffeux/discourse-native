import 'dart:convert';

import 'package:discourse_native/src/data/recent_destinations_store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example';
const _account = 'user:1';

const _fromSidebar = ContentRoute(
  destination: FeedDestination(
    key: 'category-12',
    sourcePath: '/c/discourse-native-app/12.json',
  ),
  title: 'Discourse Native App',
  icon: DIcons.folder,
);

const _fromLink = ContentRoute(
  destination: FeedDestination(
    key: 'list-/c/native/12.json',
    sourcePath: '/c/native/12.json',
  ),
  title: 'Discourse Native App',
  icon: DIcons.folder,
);

const _other = ContentRoute(
  destination: FeedDestination(
    key: 'category-13',
    sourcePath: '/c/support/13.json',
  ),
  title: 'Support',
  icon: DIcons.folder,
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
        destination: FeedDestination(
          key: 'list-/c/general.json',
          sourcePath: '/c/general.json',
        ),
        title: 'General',
        icon: DIcons.folder,
      );
      const second = ContentRoute(
        destination: FeedDestination(
          key: 'list-/c/support.json',
          sourcePath: '/c/support.json',
        ),
        title: 'Support',
        icon: DIcons.folder,
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

  group('RecentDestinationsStore forums', () {
    const otherSite = 'https://other.example';
    final message = ContentRoute.topic(
      topicId: 7,
      slug: 'contract-renewal',
      title: 'Contract renewal with Acme',
    );

    /// Two accounts' visits to [_site] and one to [otherSite], already saved.
    Future<(MemoryRecentDestinationsPersistence, RecentDestinationsStore)>
    visited() async {
      final persistence = MemoryRecentDestinationsPersistence();
      final store = RecentDestinationsStore(persistence: persistence)
        ..remember(_site, _account, message)
        ..remember(_site, 'anonymous', _other)
        ..remember(otherSite, _account, _fromSidebar);
      await store.save();
      expect(persistence.value, contains(message.title));
      return (persistence, store);
    }

    Future<void> expectOnlyOtherSite(
      MemoryRecentDestinationsPersistence persistence,
    ) async {
      final reloaded = RecentDestinationsStore(persistence: persistence);
      await reloaded.load();
      expect(reloaded.hasVisits(_site, _account), isFalse);
      expect(reloaded.hasVisits(_site, 'anonymous'), isFalse);
      expect(reloaded.categoriesFor(otherSite, _account), [_fromSidebar]);
      expect(persistence.value, isNot(contains(message.title)));
      expect(persistence.value, isNot(contains(_site)));
    }

    test(
      'forgetting a forum drops every account and keeps the others',
      () async {
        final (persistence, store) = await visited();

        expect(store.forgetSite(_site), isTrue);
        expect(store.forgetSite(_site), isFalse);
        await store.save();

        await expectOnlyOtherSite(persistence);
      },
    );

    test('retaining forums drops every account of the rest', () async {
      final (persistence, store) = await visited();

      expect(store.retainSites({otherSite}), isTrue);
      expect(store.retainSites({otherSite}), isFalse);
      await store.save();

      await expectOnlyOtherSite(persistence);
    });
  });
}
