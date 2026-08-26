import 'dart:async';

import 'package:discourse_native/src/data/aggregate_preferences_store.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/aggregate_feed_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _firstUrl = 'https://one.example';
const _secondUrl = 'https://two.example';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mixes the exact per-forum filter results', () async {
    final api = _AggregateApi(
      pages: {
        '$_firstUrl|${_AggregateApi.openPage}': [
          // A fully read topic remains because inclusion now belongs to the
          // explicit filter query rather than a native unread heuristic.
          _topic(1, minute: 10, seen: true),
          _topic(2, minute: 8, unreadPosts: 2),
        ],
        '$_secondUrl|${_AggregateApi.uxPage}': [
          _topic(5, minute: 11, seen: true),
        ],
      },
      filterOptions: const [TopicFilterOption(name: 'status:', priority: 1)],
    );
    final credentials = FakeApiCredentialReader()
      ..keys[_firstUrl] = 'one-key'
      ..keys[_secondUrl] = 'two-key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);
    final forums = [
      _connected(_firstUrl, 'One'),
      _connected(_secondUrl, 'Two'),
    ];

    await controller.setForumFilters(
      allForums: forums,
      includedConnectedForums: {_firstUrl, _secondUrl},
      queries: {_firstUrl: 'status:open', _secondUrl: 'tag:ux'},
    );
    await controller.refresh(forums);

    expect(controller.state.topics, const [
      AggregateTopicRef(siteUrl: _secondUrl, topicId: 5),
      AggregateTopicRef(siteUrl: _firstUrl, topicId: 1),
      AggregateTopicRef(siteUrl: _firstUrl, topicId: 2),
    ]);
    expect(controller.state.failures, isEmpty);
    expect(
      api.paths,
      containsAll([_AggregateApi.openPage, _AggregateApi.uxPage]),
    );
    expect(controller.queryFor(_firstUrl), 'status:open');
    expect(controller.queryFor(_secondUrl), 'tag:ux');
    expect(controller.filterOptionsFor(_firstUrl).single.name, 'status:');
  });

  test('persists exclusions and normalized queries', () async {
    final persistence = MemoryAggregatePreferencesPersistence();
    final store = AggregatePreferencesStore(persistence: persistence);

    await store.save(
      excludedForums: {_secondUrl},
      queries: {_firstUrl: '  status:open  ', _secondUrl: ''},
    );
    final restored = await AggregatePreferencesStore(
      persistence: persistence,
    ).load();

    expect(restored.excludedForums, {_secondUrl});
    expect(restored.queries, {_firstUrl: 'status:open'});
  });

  test('loads version one exclusions without inventing queries', () async {
    final persistence = MemoryAggregatePreferencesPersistence()
      ..value = '{"version":1,"excluded_forums":["https://two.example"]}';

    final restored = await AggregatePreferencesStore(
      persistence: persistence,
    ).load();

    expect(restored.excludedForums, {_secondUrl});
    expect(restored.queries, isEmpty);
  });

  test('migrates version two filters into the first aggregate tab', () async {
    final persistence = MemoryAggregatePreferencesPersistence()
      ..value =
          '{"version":2,"excluded_forums":["$_secondUrl"],'
          '"queries":{"$_firstUrl":"status:open"}}';

    final restored = await AggregatePreferencesStore(
      persistence: persistence,
    ).load();

    expect(restored.tabs, hasLength(1));
    expect(restored.excludedForums, {_secondUrl});
    expect(restored.queries, {_firstUrl: 'status:open'});
  });

  test('persists ordered aggregate tabs and their active selection', () async {
    final persistence = MemoryAggregatePreferencesPersistence();
    final store = AggregatePreferencesStore(persistence: persistence);

    await store.save(
      tabs: [
        AggregateTabPreferences(
          id: 'first',
          name: 'Open work',
          queries: {_firstUrl: 'status:open'},
        ),
        AggregateTabPreferences(
          id: 'second',
          excludedForums: {_firstUrl},
          queries: {_secondUrl: 'tag:ux'},
        ),
      ],
      activeTabId: 'second',
    );

    final restored = await store.load();

    expect(restored.tabs.map((tab) => tab.id), ['first', 'second']);
    expect(restored.tabs.map((tab) => tab.name), ['Open work', null]);
    expect(restored.activeTabId, 'second');
    expect(restored.tabs.first.queries, {_firstUrl: 'status:open'});
    expect(restored.tabs.last.excludedForums, {_firstUrl});
    expect(restored.tabs.last.queries, {_secondUrl: 'tag:ux'});
  });

  test('loads unnamed version three tabs', () async {
    final persistence = MemoryAggregatePreferencesPersistence()
      ..value =
          '{"version":3,"active_tab_id":"first","tabs":['
          '{"id":"first","excluded_forums":[],"queries":{}}]}';

    final restored = await AggregatePreferencesStore(persistence: persistence)
        .load();

    expect(restored.tabs.single.id, 'first');
    expect(restored.tabs.single.name, isNull);
  });

  test('forum selection and blank filters use only included forums', () async {
    final api = _AggregateApi(
      pages: {
        '$_firstUrl|${_AggregateApi.defaultOneForumPage}': [
          _topic(1, minute: 1),
        ],
      },
    );
    final credentials = FakeApiCredentialReader()
      ..keys[_firstUrl] = 'one-key'
      ..keys[_secondUrl] = 'two-key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);
    final forums = [
      _connected(_firstUrl, 'One'),
      _connected(_secondUrl, 'Two'),
      const DiscourseInstance(url: 'https://signed-out.example', title: 'Out'),
    ];

    await controller.setForumFilters(
      allForums: forums,
      includedConnectedForums: {_firstUrl},
      queries: const {},
    );
    await controller.refresh(forums);

    expect(controller.state.includedForums, 1);
    expect(controller.state.topics, const [
      AggregateTopicRef(siteUrl: _firstUrl, topicId: 1),
    ]);
    expect(api.sitePaths, ['$_firstUrl|${_AggregateApi.defaultOneForumPage}']);
  });

  test('a forced refresh cannot be overwritten by an older response', () async {
    final api = _RefreshRaceApi();
    final credentials = FakeApiCredentialReader()..keys[_firstUrl] = 'key';
    final controller = _controller(api, credentials);
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

  test('tabs keep independent filters and feed snapshots', () async {
    const openPath = '/filter.json?per_page=30&q=status%3Aopen';
    const uxPath = '/filter.json?per_page=30&q=tag%3Aux';
    final api = _AggregateApi(
      pages: {
        '$_firstUrl|$openPath': [_topic(1, minute: 1)],
        '$_firstUrl|$uxPath': [_topic(2, minute: 2)],
      },
    );
    final credentials = FakeApiCredentialReader()..keys[_firstUrl] = 'key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);
    final forum = _connected(_firstUrl, 'One');

    await controller.setForumFilters(
      allForums: [forum],
      includedConnectedForums: {_firstUrl},
      queries: {_firstUrl: 'status:open'},
    );
    await controller.refresh([forum]);
    final firstTabId = controller.activeTabId;

    final secondTabId = controller.createTab()!;
    await controller.setForumFilters(
      allForums: [forum],
      includedConnectedForums: {_firstUrl},
      queries: {_firstUrl: 'tag:ux'},
    );
    await controller.refresh([forum]);

    expect(controller.state.topics.single.topicId, 2);
    expect(controller.queryFor(_firstUrl), 'tag:ux');

    controller.selectTab(firstTabId);
    expect(controller.state.topics.single.topicId, 1);
    expect(controller.queryFor(_firstUrl), 'status:open');

    controller.selectTab(secondTabId);
    expect(controller.state.topics.single.topicId, 2);
    expect(api.paths, [openPath, uxPath]);
  });

  test('renames and persists an aggregate tab', () async {
    final persistence = MemoryAggregatePreferencesPersistence();
    final preferences = AggregatePreferencesStore(persistence: persistence);
    final controller = _controller(
      _AggregateApi(pages: const {}),
      FakeApiCredentialReader(),
      preferences: preferences,
    );
    addTearDown(controller.dispose);

    final id = controller.activeTabId;
    expect(controller.renameTab(id, '  Product   triage  '), isTrue);
    expect(controller.tabs.single.name, 'Product triage');
    expect(controller.renameTab(id, '   '), isFalse);

    final restored = await preferences.load();
    expect(restored.tabs.single.name, 'Product triage');
  });
}

AggregateFeedController _controller(
  DiscourseApi api,
  FakeApiCredentialReader credentials, {
  AggregatePreferencesStore? preferences,
}) => AggregateFeedController(
  api: api,
  credentials: credentials,
  lifecycle: SiteLifecycle(),
  store: Store(),
  preferences: preferences ?? AggregatePreferencesStore.memory(),
  readPersonalizationVersion: (_) => 0,
  prepareTopic: (_, topic, _) => topic,
);

DiscourseInstance _connected(String url, String title) => DiscourseInstance(
  url: url,
  title: title,
  user: const DiscourseUser(username: 'stored'),
);

Topic _topic(
  int id, {
  required int minute,
  bool seen = true,
  int unreadPosts = 0,
}) => Topic(
  id: id,
  title: 'Topic $id',
  slug: 'topic-$id',
  bumpedAt: DateTime.utc(2026, 1, 1, 0, minute),
  seen: seen,
  unreadPosts: unreadPosts,
);

final class _AggregateApi extends FakeDiscourseApi {
  _AggregateApi({required this.pages, this.filterOptions = const []});

  static const openPage = '/filter.json?per_page=15&q=status%3Aopen';
  static const uxPage = '/filter.json?per_page=15&q=tag%3Aux';
  static const defaultOneForumPage = '/filter.json?per_page=30';

  final Map<String, List<Topic>> pages;
  final List<TopicFilterOption> filterOptions;
  final List<String> paths = [];
  final List<String> sitePaths = [];

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    paths.add(path);
    sitePaths.add('$siteUrl|$path');
    return TopicList(
      topics: pages['$siteUrl|$path'] ?? const [],
      filterOptions: filterOptions,
    );
  }
}

final class _RefreshRaceApi extends FakeDiscourseApi {
  final Completer<void> firstStarted = Completer();
  final Completer<void> releaseFirst = Completer();
  int calls = 0;

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
      return TopicList(topics: [_topic(1, minute: 1)]);
    }
    return TopicList(topics: [_topic(2, minute: 2)]);
  }
}
