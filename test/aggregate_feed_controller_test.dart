import 'dart:async';

import 'package:discourse_native/src/data/aggregate_preferences_store.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/aggregate_feed_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _firstUrl = 'https://one.example';
const _secondUrl = 'https://two.example';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mixes only unseen activity from followed category trees', () async {
    final api = _AggregateApi(
      users: const {
        _firstUrl: DiscourseUser(
          username: 'one',
          trackedCategoryIds: [1],
          watchedCategoryIds: [],
          watchedFirstPostCategoryIds: [],
        ),
        _secondUrl: DiscourseUser(
          username: 'two',
          trackedCategoryIds: [],
          watchedCategoryIds: [10],
          watchedFirstPostCategoryIds: [],
        ),
      },
      categoriesBySite: const {
        _firstUrl: [
          TopicCategory(id: 1, name: 'Tracked', color: '0088CC'),
          TopicCategory(id: 2, name: 'Normal', color: '888888'),
          TopicCategory(
            id: 3,
            name: 'Tracked child',
            color: '00AA00',
            parentCategoryId: 1,
          ),
        ],
        _secondUrl: [TopicCategory(id: 10, name: 'Watched', color: 'CC0000')],
      },
      pages: {
        '$_firstUrl|${_AggregateApi.firstPage}': [
          _topic(1, categoryId: 1, minute: 10, seen: false),
          _topic(2, categoryId: 3, minute: 8, unreadPosts: 2),
          _topic(3, categoryId: 1, minute: 7),
          // `/unseen?f=tracked` can also admit a topic through a followed tag.
          // The local category check must reject that leak.
          _topic(4, categoryId: 2, minute: 9, seen: false),
        ],
        '$_secondUrl|${_AggregateApi.firstPage}': [
          _topic(5, categoryId: 10, minute: 11, seen: false),
          _topic(
            6,
            categoryId: 10,
            minute: 6,
            isNestedView: true,
            hasNewReplies: true,
          ),
          _topic(7, categoryId: 10, minute: 12, isNestedView: true),
        ],
      },
    );
    final credentials = FakeApiCredentialReader()
      ..keys[_firstUrl] = 'one-key'
      ..keys[_secondUrl] = 'two-key';
    final categories = <String, List<TopicCategory>>{};
    final store = Store();
    final controller = AggregateFeedController(
      api: api,
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      store: store,
      preferences: AggregatePreferencesStore.memory(),
      readCategories: (siteUrl) => categories[siteUrl] ?? const [],
      writeCategories: (siteUrl, incoming) {
        categories[siteUrl] = [...categories[siteUrl] ?? const [], ...incoming];
      },
      writeUser: (_, _) {},
      readPersonalizationVersion: (_) => 0,
      prepareTopic: (_, topic, _) => topic,
    );
    addTearDown(controller.dispose);

    final forums = [
      _connected(_firstUrl, 'One'),
      _connected(_secondUrl, 'Two'),
    ];
    await controller.refresh(forums);

    expect(controller.state.topics, const [
      AggregateTopicRef(siteUrl: _secondUrl, topicId: 5),
      AggregateTopicRef(siteUrl: _firstUrl, topicId: 1),
      AggregateTopicRef(siteUrl: _firstUrl, topicId: 2),
      AggregateTopicRef(siteUrl: _secondUrl, topicId: 6),
    ]);
    expect(controller.state.failures, isEmpty);
    expect(controller.state.hasMore, isFalse);
    expect(store.read<Topic>(_firstUrl, 3), isNull);
    expect(store.read<Topic>(_firstUrl, 4), isNull);
    expect(api.paths, everyElement(contains('/unseen.json?f=tracked')));
  });

  test(
    'persists exclusions so newly connected forums remain included',
    () async {
      final persistence = MemoryAggregatePreferencesPersistence();
      final store = AggregatePreferencesStore(persistence: persistence);

      await store.save({_secondUrl});
      final restored = await AggregatePreferencesStore(
        persistence: persistence,
      ).load();

      expect(restored, {_secondUrl});
      expect(restored, isNot(contains(_firstUrl)));
    },
  );

  test('forum selection refreshes only connected included forums', () async {
    final api = _AggregateApi(
      users: const {
        _firstUrl: DiscourseUser(
          username: 'one',
          trackedCategoryIds: [1],
          watchedCategoryIds: [],
          watchedFirstPostCategoryIds: [],
        ),
        _secondUrl: DiscourseUser(
          username: 'two',
          trackedCategoryIds: [1],
          watchedCategoryIds: [],
          watchedFirstPostCategoryIds: [],
        ),
      },
      categoriesBySite: const {
        _firstUrl: [TopicCategory(id: 1, name: 'One', color: '0088CC')],
        _secondUrl: [TopicCategory(id: 1, name: 'Two', color: 'CC0000')],
      },
      pages: {
        '$_firstUrl|${_AggregateApi.oneForumPage}': [
          _topic(1, categoryId: 1, minute: 1, seen: false),
        ],
        '$_secondUrl|${_AggregateApi.firstPage}': [
          _topic(2, categoryId: 1, minute: 2, seen: false),
        ],
      },
    );
    final credentials = FakeApiCredentialReader()
      ..keys[_firstUrl] = 'one-key'
      ..keys[_secondUrl] = 'two-key';
    final identityStore = Store();
    final controller = AggregateFeedController(
      api: api,
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      store: identityStore,
      preferences: AggregatePreferencesStore.memory(),
      readCategories: (_) => const [],
      writeCategories: (_, _) {},
      writeUser: (_, _) {},
      readPersonalizationVersion: (_) => 0,
      prepareTopic: (_, topic, _) => topic,
    );
    addTearDown(controller.dispose);
    final forums = [
      _connected(_firstUrl, 'One'),
      _connected(_secondUrl, 'Two'),
      const DiscourseInstance(url: 'https://signed-out.example', title: 'Out'),
    ];

    await controller.setIncludedForums(
      allForums: forums,
      includedConnectedForums: {_firstUrl},
    );
    await controller.refresh(forums);

    expect(controller.state.includedForums, 1);
    expect(controller.state.topics, const [
      AggregateTopicRef(siteUrl: _firstUrl, topicId: 1),
    ]);
    expect(api.paths, hasLength(1));
    expect(api.paths.single, startsWith('$_firstUrl|'));

    identityStore.update<Topic>(
      _firstUrl,
      1,
      (topic) => topic.copyWith(markRead: true),
    );
    controller.reconcileTopic(_firstUrl, 1);
    expect(controller.state.topics, isEmpty);
  });

  test('a forced refresh cannot be overwritten by an older response', () async {
    final api = _RefreshRaceApi();
    final credentials = FakeApiCredentialReader()..keys[_firstUrl] = 'key';
    final controller = AggregateFeedController(
      api: api,
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      store: Store(),
      preferences: AggregatePreferencesStore.memory(),
      readCategories: (_) => const [
        TopicCategory(id: 1, name: 'Followed', color: '0088CC'),
      ],
      writeCategories: (_, _) {},
      writeUser: (_, _) {},
      readPersonalizationVersion: (_) => 0,
      prepareTopic: (_, topic, _) => topic,
    );
    addTearDown(controller.dispose);
    final forum = _connected(_firstUrl, 'One');

    final older = controller.refresh([forum]);
    await api.firstStarted.future;
    final newer = controller.refresh([forum], force: true);
    await newer;
    api.releaseFirst.complete();
    await older;

    expect(controller.state.topics, const [
      AggregateTopicRef(siteUrl: _firstUrl, topicId: 2),
    ]);
  });
}

DiscourseInstance _connected(String url, String title) => DiscourseInstance(
  url: url,
  title: title,
  user: const DiscourseUser(username: 'stored'),
);

Topic _topic(
  int id, {
  required int categoryId,
  required int minute,
  bool seen = true,
  int unreadPosts = 0,
  bool isNestedView = false,
  bool hasNewReplies = false,
}) => Topic(
  id: id,
  title: 'Topic $id',
  slug: 'topic-$id',
  categoryId: categoryId,
  bumpedAt: DateTime.utc(2026, 1, 1, 0, minute),
  seen: seen,
  unreadPosts: unreadPosts,
  isNestedView: isNestedView,
  hasNewReplies: hasNewReplies,
);

final class _AggregateApi extends FakeDiscourseApi {
  _AggregateApi({
    required this.users,
    required this.categoriesBySite,
    required this.pages,
  });

  static const firstPage =
      '/unseen.json?f=tracked&no_definitions=true&per_page=15';
  static const oneForumPage =
      '/unseen.json?f=tracked&no_definitions=true&per_page=30';

  final Map<String, DiscourseUser> users;
  final Map<String, List<TopicCategory>> categoriesBySite;
  final Map<String, List<Topic>> pages;
  final List<String> paths = [];

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => users[siteUrl]!;

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    paths.add('$siteUrl|$path');
    return TopicList(topics: pages['$siteUrl|$path'] ?? const []);
  }

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async => CategoryLoadResult(
    page == 1 ? categoriesBySite[siteUrl] ?? const [] : const [],
  );
}

final class _RefreshRaceApi extends FakeDiscourseApi {
  final Completer<void> firstStarted = Completer();
  final Completer<void> releaseFirst = Completer();
  int calls = 0;

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => const DiscourseUser(
    username: 'sam',
    trackedCategoryIds: [1],
    watchedCategoryIds: [],
    watchedFirstPostCategoryIds: [],
  );

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    calls++;
    if (calls == 1) {
      firstStarted.complete();
      await releaseFirst.future;
      return TopicList(
        topics: [_topic(1, categoryId: 1, minute: 1, seen: false)],
      );
    }
    return TopicList(
      topics: [_topic(2, categoryId: 1, minute: 2, seen: false)],
    );
  }
}
