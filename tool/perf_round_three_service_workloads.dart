import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/destination_bookmarks_store.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_model_codec.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/emoji_preferences.dart';
import 'package:discourse_native/src/models/emoji_usage.dart';
import 'package:discourse_native/src/models/incoming_topics.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/bookmark_transactions.dart';
import 'package:discourse_native/src/shell/emoji_picker_controller.dart';
import 'package:discourse_native/src/shell/topic_data_owner.dart';
import 'package:discourse_native/src/shell/topic_feed_controller.dart';
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
  for (final gap in [false, true]) {
    for (final removals in [0, 20, 1000]) {
      await measure(
        'topic_${gap ? 'gap' : 'mega'}_${removals}_removals',
        300,
        () async {
          await RoundThreeTopicPageFixture(
            gap: gap,
            removals: removals,
          ).check();
        },
      );
    }
  }
  for (final (count, overlap) in [(30, true), (300, true), (300, false)]) {
    final fixture = RoundThreeFeedFixture(count, overlap: overlap);
    try {
      await fixture.prepare();
      await measure(
        'feed_prepend_${count}_${overlap ? 'overlap' : 'new'}',
        overlap ? 1000 : 100,
        fixture.checkIncoming,
      );
    } finally {
      fixture.controller.dispose();
    }
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

final class RoundThreeTopicPageFixture {
  RoundThreeTopicPageFixture({
    required this.gap,
    required this.removals,
    this.removeOnPublish = false,
  }) {
    detail = TopicDetail(
      id: 7,
      title: 'Topic',
      stream: const [1],
      postsCount: 10000,
      isMegaTopic: !gap,
      lastPostId: 10000,
      gapsAfter: gap
          ? {
              1: [for (var i = 2; i <= 21; i++) i],
            }
          : const {},
    );
    store.put(site, detail);
    store.put(site, post(1));
    owner = TopicDataOwner(
      content: api,
      feeds: api,
      models: const DiscourseModelCodec.core(),
      store: store,
      credentials: const RoundThreeCredentials(),
      lifecycle: SiteLifecycle(),
      changed: () {},
      liveChanged: (_) {},
      published: (_, _) => false,
      prepareCategories: (_, _) async {},
      loadTimeout: const Duration(seconds: 5),
      bookmarkReads: (_, _) => const _RoundThreeBookmarks(),
    );
  }
  static const site = 'https://topic.example';
  final bool gap;
  final int removals;
  final bool removeOnPublish;
  final store = Store();
  final api = _RoundThreeTopicApi();
  late final TopicDetail detail;
  late final TopicDataOwner owner;

  static Post post(int id) => Post(
    id: id,
    postNumber: id,
    username: 'reader',
    cooked: '<p>Post $id</p>',
  );

  Future<void> check() async {
    try {
      final session = owner.forSite(site);
      if (removeOnPublish) {
        var removed = false;
        store.ref<Post>(site, 2).addListener(() {
          if (removed || store.read<Post>(site, 2) == null) return;
          removed = true;
          session.removePost(7, 2);
        });
      }
      for (var i = 1; i < removals; i++) {
        session.removePost(7, 20000 + i);
      }
      final loading = gap
          ? session.expandGap(7, anchorPostId: 1, before: false)
          : session.pageMega(detail, post(1), newer: true);
      await api.started.future;
      if (removals > 0) session.removePost(7, 20000);
      api.response.complete([for (var i = 2; i <= 21; i++) post(i)]);
      await loading;
      final merged = store.read<TopicDetail>(site, 7)!;
      final wanted = [1, for (var i = removeOnPublish ? 3 : 2; i <= 21; i++) i];
      if (api.calls != 1 || merged.stream.length != wanted.length) {
        throw StateError('Topic page was not completely published');
      }
      for (var i = 0; i < wanted.length; i++) {
        if (merged.stream[i] != wanted[i] ||
            store.read<Post>(site, wanted[i]) == null) {
          throw StateError('Topic page ordering or removal changed');
        }
      }
      if (removeOnPublish && store.read<Post>(site, 2) != null) {
        throw StateError('Synchronous post removal was undone');
      }
      if (gap && merged.gapsAfter.isNotEmpty) {
        throw StateError('Consumed topic gap was retained');
      }
    } finally {
      owner.dispose();
    }
  }
}

final class RoundThreeCredentials implements ApiCredentialReader {
  const RoundThreeCredentials();
  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'key';
  @override
  Future<String> clientId() async => '';
}

final class _RoundThreeTopicApi implements TopicContentApi, TopicFeedsApi {
  final started = Completer<void>();
  final response = Completer<List<Post>>();
  var calls = 0;
  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) {
    calls++;
    started.complete();
    return response.future;
  }

  @override
  Future<List<Post>> postsFromNumber({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    required bool ascending,
    String? apiKey,
    String? clientId,
  }) => posts(siteUrl: siteUrl, topicId: topicId, ids: const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RoundThreeBookmarks implements BookmarkReadProjection {
  const _RoundThreeBookmarks();
  @override
  int get epoch => 0;
  @override
  int revision(int topicId) => 0;
  @override
  bool Function() guard(int topicId) =>
      () => true;
  @override
  Post postFromRead(int topicId, int version, Post incoming) => incoming;
  @override
  Post preservePost(Post incoming) => incoming;
  @override
  TopicDetail detailFromRead(int version, TopicDetail incoming) => incoming;
  @override
  Topic prepareRow(Topic incoming, int? versionAtDispatch) => incoming;
  @override
  Topic projectTopicRow(Topic incoming) => incoming;
}

final class RoundThreeFeedFixture {
  RoundThreeFeedFixture(this.count, {required this.overlap}) {
    _api = _RoundThreeFeedApi(count);
    expected = [for (var id = 1; id <= count; id++) id];
    expectedRows = count;
    controller = TopicFeedController(
      api: _api,
      credentials: const RoundThreeCredentials(),
      lifecycle: SiteLifecycle(),
      store: Store(),
    );
  }
  static const site = DiscourseInstance(
    url: 'https://feed.example',
    title: 'Feed',
    user: DiscourseUser(username: 'reader'),
  );
  static const destination = 'latest';
  final int count;
  final bool overlap;
  late final _RoundThreeFeedApi _api;
  late final TopicFeedController controller;
  late List<int> expected;
  late int expectedRows;
  var turn = 0;

  Future<void> prepare() async {
    await controller.load(
      instance: site,
      destinationId: destination,
      path: '/latest.json',
      incoming: null,
    );
    for (
      var page = 0;
      controller.feedFor(site.url, destination)!.hasMore;
      page++
    ) {
      if (page > 20) throw StateError('Initial feed never finished loading');
      await controller.loadMore(instance: site, destinationId: destination);
    }
    _check();
  }

  Future<void> checkIncoming() async {
    final size = count == 30 ? 10 : 30;
    final start = overlap
        ? count - size * (turn.isEven ? 1 : 2) + 1
        : count + turn * size + 1;
    final arrivals = [for (var i = 0; i < size; i++) start + i];
    turn++;
    final present = arrivals.toSet();
    expectedRows += arrivals.length - expected.where(present.contains).length;
    expected = [...arrivals, ...expected.where((id) => !present.contains(id))];
    _api.arrivals = arrivals;
    final incoming = IncomingTopics();
    for (final id in arrivals) {
      incoming.notify({'message_type': 'new_topic', 'topic_id': id});
    }
    await controller.showIncoming(
      instance: site,
      destinationId: destination,
      path: '/latest.json',
      incoming: incoming,
    );
    if (incoming.count(destination) != 0) {
      throw StateError('Incoming topics were not consumed');
    }
    _check();
  }

  void _check() {
    final feed = controller.feedFor(site.url, destination)!;
    final retained = expected.length < 300 ? expected.length : 300;
    if (feed.error != null ||
        feed.rowCount != expectedRows ||
        feed.topicIds.length != retained) {
      throw StateError('Retained feed row count changed');
    }
    for (final row in feed.topicRows) {
      if (feed.topicIdAt(row) != expected[row]) {
        throw StateError(
          'Retained feed ordering changed at $row: expected ${expected[row]}, got ${feed.topicIdAt(row)}; count=$count overlap=$overlap turn=$turn rows=${feed.topicRows}',
        );
      }
    }
  }
}

final class _RoundThreeFeedApi implements TopicFeedsApi {
  _RoundThreeFeedApi(this.count);
  final int count;
  List<int> arrivals = const [];
  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    final uri = Uri.parse(path);
    final arriving = uri.queryParameters.containsKey('topic_ids');
    final start = uri.path == '/latest.json'
        ? 0
        : int.parse(uri.pathSegments.last.split('.').first);
    final end = start + 30 < count ? start + 30 : count;
    final ids = arriving ? arrivals : [for (var i = start; i < end; i++) i + 1];
    return TopicList(
      topics: [
        for (final id in ids)
          Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
      ],
      moreTopicsUrl: !arriving && end < count ? '/cursor/$end.json' : null,
    );
  }

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
