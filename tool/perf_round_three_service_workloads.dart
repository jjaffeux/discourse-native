import 'dart:convert';

import 'package:discourse_native/src/data/destination_bookmarks_store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/theme/d_icons.dart';

Future<Map<String, int>> measureRoundThreeServicePerformance() async {
  final times = <String, int>{};
  Future<void> measure(
    String name,
    int iterations,
    Future<void> Function() action,
  ) async {
    for (var i = 0; i < 10; i++) {
      await action();
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      await action();
    }
    times[name] = watch.elapsedMicroseconds;
  }

  for (final count in [20, 500]) {
    final fixture = RoundThreeBookmarkFixture(count);
    await measure('destination_bookmark_load_$count', 300, fixture.checkLoad);
  }
  return times;
}

final class RoundThreeBookmarkFixture {
  RoundThreeBookmarkFixture(this.count) {
    final routes = [
      for (var i = 1; i <= count; i++)
        ContentRoute(
          destination: FeedDestination(
            key: 'category-$i',
            sourcePath: '/c/category-$i/$i.json',
          ),
          title: 'Category $i',
          icon: DIcons.folder,
        ).toJson(),
    ];
    persistence.value = jsonEncode({
      'version': 1,
      'entries': [
        {
          'site_url': site,
          'account_identity': 'reader',
          'routes': [
            ...routes,
            routes.first,
            {'invalid': true},
          ],
        },
        {
          'site_url': site,
          'account_identity': 'reader',
          'routes': [routes.last, routes.first],
        },
        {
          'site_url': site,
          'account_identity': 'another',
          'routes': [routes.first],
        },
      ],
    });
    store = DestinationBookmarksStore(persistence: persistence);
  }

  static const site = 'https://bookmark.example';
  final int count;
  final persistence = MemoryDestinationBookmarksPersistence();
  late final DestinationBookmarksStore store;

  Future<void> checkLoad() async {
    await store.load();
    final entries = store.entriesFor(site, 'reader');
    if (entries.length != count ||
        store.entriesFor(site, 'another').single.identity != 'category:1') {
      throw StateError('Bookmark account ownership or deduplication changed');
    }
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].identity != 'category:${i + 1}' ||
          entries[i].route.title != 'Category ${i + 1}') {
        throw StateError('Bookmark order or first-record ownership changed');
      }
    }
  }
}
