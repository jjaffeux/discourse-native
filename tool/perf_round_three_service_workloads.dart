import 'dart:convert';

import 'package:discourse_native/src/data/destination_bookmarks_store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/emoji_preferences.dart';
import 'package:discourse_native/src/models/emoji_usage.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/shell/emoji_picker_controller.dart';
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
  for (final count in [20, 4000]) {
    final fixture = RoundThreeEmojiFixture(count);
    final controller = fixture.controller();
    try {
      await fixture.prepare(controller);
      await measure('emoji_picker_search_$count', 300, () async {
        fixture.checkQueries(controller);
      });
    } finally {
      controller.dispose();
    }
    await measure('emoji_picker_cold_prefix_$count', 300, () async {
      final cold = fixture.controller();
      try {
        await cold.load();
        cold.updateQuery('emoji');
        fixture.check(cold, 'emoji');
        await fixture.settleAliases(cold);
      } finally {
        cold.dispose();
      }
    });
  }
  return times;
}

final class RoundThreeEmojiFixture {
  RoundThreeEmojiFixture(int count, {String prefix = 'emoji'}) {
    final emojis = [
      for (var i = 0; i < count; i++)
        SiteEmoji(
          name:
              '${prefix}_${i.toString().padLeft(4, '0')}_${['smile', 'wave', 'heart', 'star'][i % 4]}',
          url: '/$i.png',
        ),
    ];
    catalog = SiteEmojiCatalog(
      groups: [SiteEmojiGroup(id: 'test', emojis: emojis)],
    );
    aliases = {
      for (var i = 0; i < emojis.length; i += 7)
        emojis[i].name: ['HAPPY', 'joy'],
    };
    for (final query in queries) {
      final found = <String>{};
      final ordered = <String>[];
      void take(bool Function(SiteEmoji) includes) {
        for (final emoji in catalog.alphabetical) {
          if (ordered.length == EmojiPickerController.maxSearchResults) break;
          if (!found.contains(emoji.name) && includes(emoji)) {
            found.add(emoji.name);
            ordered.add(emoji.name);
          }
        }
      }

      take((emoji) => emoji.name.toLowerCase().startsWith(query));
      take(
        (emoji) =>
            aliases[emoji.name]?.any(
              (alias) => alias.toLowerCase().startsWith(query),
            ) ??
            false,
      );
      take((emoji) => emoji.name.toLowerCase().indexOf(query) > 0);
      expected[query] = ordered;
    }
  }

  static const queries = [
    'emoji',
    'smile',
    'wave',
    'heart',
    'happy',
    'joy',
    'missing',
    'star',
    'emoji_0001',
    'emoji_00',
  ];
  late final SiteEmojiCatalog catalog;
  late final Map<String, List<String>> aliases;
  final expected = <String, List<String>>{};

  EmojiPickerController controller() => EmojiPickerController(
    siteUrl: 'https://emoji.example',
    context: CoreEmojiUsageContexts.topic,
    store: const RoundThreeEmojiPreferences(),
    loadCatalog: ({refresh = false}) async => catalog,
    loadSearchAliases: ({refresh = false}) async => aliases,
    searchDebounce: Duration.zero,
  );

  Future<void> prepare(EmojiPickerController controller) async {
    await controller.load();
    controller.updateQuery('warm-up');
    await settleAliases(controller);
  }

  Future<void> settleAliases(EmojiPickerController controller) async {
    for (var turn = 0; controller.aliasesLoading; turn++) {
      if (turn > 20) throw StateError('Emoji alias loading did not settle');
      await Future<void>.value();
    }
  }

  void checkQueries(EmojiPickerController controller) {
    for (final query in queries) {
      controller.updateQuery(query);
      check(controller, query);
    }
  }

  void check(EmojiPickerController controller, String query) {
    final actual = controller.searchResults;
    final wanted = expected[query]!;
    if (actual.length != wanted.length) {
      throw StateError('Emoji result count changed for $query');
    }
    for (var i = 0; i < wanted.length; i++) {
      if (actual[i].name != wanted[i]) {
        throw StateError('Emoji priority or order changed for $query');
      }
    }
  }
}

final class RoundThreeEmojiPreferences implements EmojiPreferenceStore {
  const RoundThreeEmojiPreferences();
  @override
  Future<EmojiSkinTone> readSkinTone({required String siteUrl}) async =>
      EmojiSkinTone.neutral;
  @override
  Future<List<String>> favoriteEmojiCodes({
    required String siteUrl,
    required EmojiUsageContext context,
    required SiteEmojiCatalog catalog,
  }) async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
