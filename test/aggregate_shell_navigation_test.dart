import 'dart:async';

import 'package:discourse_native/src/data/aggregate_preferences_store.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/aggregate_feed_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('disconnect clears private aggregate rows in every tab', () async {
    const topic = Topic(id: 42, title: 'Private topic', slug: 'private-topic');
    final authenticator = FakeAuthenticator()..keys[_site.url] = 'key';
    final controller = ShellController(
      instanceStore: FakeInstanceStore(const [_site]),
      api: FakeDiscourseApi(
        feeds: const {
          '/latest.json': [],
          '/filter.json?per_page=30': [topic],
        },
      ),
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      aggregatePreferences: AggregatePreferencesStore.memory(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await controller.aggregate.refresh(controller.instances);
    final firstTab = controller.activeAggregateTabId;
    controller.aggregate.createTab();
    await controller.aggregate.refresh(controller.instances);
    expect(controller.aggregate.state.topics, hasLength(1));

    expect(await controller.disconnectInstance(_site.url), isTrue);

    expect(controller.aggregate.state.topics, isEmpty);
    controller.aggregate.selectTab(firstTab);
    expect(controller.aggregate.state.topics, isEmpty);
  });

  test(
    'signing out a forum while Aggregate loads shows the other forum',
    () async {
      const twoForumPage = '/filter.json?per_page=15';
      const oneForumPage = '/filter.json?per_page=30';
      final api = _SiteFeedsApi();
      api.replies['${_site.url}|$twoForumPage'] = TopicList(
        topics: [_bumped(1, 10)],
      );
      api.replies['${_site.url}|$oneForumPage'] = TopicList(
        topics: [_bumped(1, 10)],
      );
      final held = api.holds['${_second.url}|$twoForumPage'] =
          Completer<void>();
      final controller = _aggregateController(api);
      addTearDown(controller.dispose);
      await controller.load();
      await pumpEventQueue();
      expect(controller.aggregate.state.loading, isTrue);

      expect(await controller.disconnectInstance(_second.url), isTrue);
      held.complete();
      await pumpEventQueue();

      final state = controller.aggregate.state;
      expect(controller.rootMode, ShellRootMode.aggregate);
      expect(state.loading, isFalse);
      expect(state.loaded, isTrue);
      expect(state.topics, [AggregateTopicRef(siteUrl: _site.url, topicId: 1)]);
      expect(api.filterRequests, [
        '${_site.url}|$twoForumPage',
        '${_second.url}|$twoForumPage',
        '${_site.url}|$oneForumPage',
      ]);
    },
  );

  test(
    'removing a forum while Aggregate is shown keeps paging the other',
    () async {
      const twoForumPage = '/filter.json?per_page=15';
      const oneForumPage = '/filter.json?per_page=30';
      const nextPage = '/filter.json?page=1&per_page=30';
      final api = _SiteFeedsApi();
      api.replies['${_site.url}|$twoForumPage'] = TopicList(
        topics: [for (var id = 1; id <= 15; id++) _bumped(id, 30 - id)],
        moreTopicsUrl: '/filter?page=1&per_page=15',
      );
      api.replies['${_second.url}|$twoForumPage'] = TopicList(
        topics: [for (var id = 1; id <= 15; id++) _bumped(id, 59 - id)],
      );
      api.replies['${_site.url}|$oneForumPage'] = TopicList(
        topics: [for (var id = 1; id <= 30; id++) _bumped(id, 59 - id)],
        moreTopicsUrl: '/filter?page=1&per_page=30',
      );
      api.replies['${_site.url}|$nextPage'] = TopicList(
        topics: [_bumped(31, 0)],
      );
      final controller = _aggregateController(api);
      addTearDown(controller.dispose);
      await controller.load();
      await pumpEventQueue();
      expect(controller.aggregate.state.topics, hasLength(30));

      expect(
        await controller.removeInstance(
          controller.instances.singleWhere((i) => i.url == _second.url),
        ),
        isTrue,
      );
      await pumpEventQueue();
      await controller.aggregate.loadMore();

      final state = controller.aggregate.state;
      expect(controller.rootMode, ShellRootMode.aggregate);
      expect(state.topics, [
        for (var id = 1; id <= 31; id++)
          AggregateTopicRef(siteUrl: _site.url, topicId: id),
      ]);
      expect(api.filterRequests, [
        '${_site.url}|$twoForumPage',
        '${_second.url}|$twoForumPage',
        '${_site.url}|$oneForumPage',
        '${_site.url}|$nextPage',
      ]);
    },
  );

  test('adding a forum leaves narrowed aggregate tabs narrowed', () async {
    const added = DiscourseInstance(
      url: 'https://added.example',
      title: 'Added',
      user: DiscourseUser(username: 'sam'),
    );
    final controller = _controller(store: Store());
    addTearDown(controller.dispose);
    await controller.load();
    final followingTab = controller.activeAggregateTabId;
    controller.createAggregateTab();
    await controller.setAggregateForumFilters(
      includedForums: {_site.url},
      queries: {_site.url: 'tag:workflows'},
    );

    expect(await controller.addInstance(added), isTrue);
    await pumpEventQueue();

    expect(controller.aggregate.includes(added), isFalse);
    controller.selectAggregateTab(followingTab);
    expect(controller.aggregate.includes(added), isTrue);
  });

  test('aggregate topic opens in the current forum tab', () async {
    final store = Store();
    final api = FakeDiscourseApi(feeds: const {'/latest.json': []});
    final controller = _controller(store: store, api: api);
    addTearDown(controller.dispose);
    await controller.load();
    const topic = Topic(
      id: 42,
      title: 'Aggregate topic',
      slug: 'aggregate-topic',
      seen: false,
      unreadPosts: 2,
      highestPostNumber: 8,
      lastReadPostNumber: 5,
    );
    store.put(_site.url, topic);

    controller.selectAggregate();
    final first = controller.openAggregateTopic(_site.url, topic.id);

    expect(first, AggregateTopicOpenResult.opened);
    expect(controller.rootMode, ShellRootMode.forum);
    expect(controller.currentContent?.topicId, topic.id);
    expect(controller.currentContent?.postNumber, 6);
    expect(controller.tabsForCurrentForum, hasLength(1));
    final topicTabId = controller.activeTabId;

    await Future<void>.delayed(Duration.zero);
    expect(controller.currentContent?.topicId, topic.id);
    expect(controller.currentContent?.postNumber, 6);
    expect(api.topicsOpened, contains(topic.id));

    controller.selectAggregate();
    final second = controller.openAggregateTopic(_site.url, topic.id);

    expect(second, AggregateTopicOpenResult.opened);
    expect(controller.tabsForCurrentForum, hasLength(1));
    expect(controller.activeTabId, topicTabId);
  });

  test(
    'desktop aggregate topics use the current panel across destinations',
    () async {
      final store = Store();
      final controller = _controller(store: store);
      addTearDown(controller.dispose);
      await controller.load();
      controller.desktopTopicTabs = true;
      final mainId = controller.activeTabId;
      const first = Topic(id: 42, title: 'First', slug: 'first');
      const second = Topic(id: 43, title: 'Second', slug: 'second');
      store.put(_site.url, first);
      store.put(_site.url, second);
      controller.selectAggregate();

      expect(
        controller.openAggregateTopic(_site.url, first.id),
        AggregateTopicOpenResult.opened,
      );
      final readerId = controller.activeTabId;
      expect(controller.rootMode, ShellRootMode.forum);
      expect(controller.activeTab?.panel, ForumPanel.main);
      expect(controller.selectedTabIn(ForumPanel.main)?.id, mainId);
      expect(controller.tabsForCurrentForum, hasLength(1));

      controller.selectAggregate();
      expect(
        controller.openAggregateTopic(_site.url, second.id),
        AggregateTopicOpenResult.opened,
      );
      expect(controller.rootMode, ShellRootMode.forum);
      expect(controller.activeTabId, readerId);
      expect(controller.currentContent?.topicId, second.id);
      expect(controller.tabsForCurrentForum, hasLength(1));
    },
  );

  test(
    'aggregate topic can open in the current tab at the tab limit',
    () async {
      final store = Store();
      final controller = _controller(store: store);
      addTearDown(controller.dispose);
      await controller.load();
      while (controller.tabsForCurrentForum.length <
          ForumWorkspace.maximumTabs) {
        controller.createTab();
      }
      const topic = Topic(id: 7, title: 'Overflow', slug: 'overflow');
      store.put(_site.url, topic);
      controller.selectAggregate();

      final result = controller.openAggregateTopic(_site.url, topic.id);

      expect(result, AggregateTopicOpenResult.opened);
      expect(controller.rootMode, ShellRootMode.forum);
      expect(controller.currentContent?.topicId, topic.id);
      expect(
        controller.tabsForCurrentForum,
        hasLength(ForumWorkspace.maximumTabs),
      );
    },
  );

  test('aggregate topic survives hydration when switching forums', () async {
    const otherSite = DiscourseInstance(
      url: 'https://two.example',
      title: 'Two',
    );
    final store = Store();
    final api = FakeDiscourseApi(feeds: const {'/latest.json': []});
    final controller = _controller(
      store: store,
      api: api,
      instances: const [_site, otherSite],
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.desktopTopicTabs = true;
    const topic = Topic(id: 42, title: 'Other forum', slug: 'other-forum');
    store.put(otherSite.url, topic);
    controller.selectAggregate();

    expect(
      controller.openAggregateTopic(otherSite.url, topic.id),
      AggregateTopicOpenResult.opened,
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.rootMode, ShellRootMode.forum);
    expect(controller.currentInstance?.url, otherSite.url);
    expect(controller.currentContent?.topicId, topic.id);
    expect(api.topicsOpened, contains(topic.id));
  });

  test('mobile uses its one forum navigation context', () async {
    final store = Store();
    final controller = _controller(store: store, forumTabsEnabled: false);
    addTearDown(controller.dispose);
    await controller.load();
    const topic = Topic(id: 8, title: 'Mobile', slug: 'mobile');
    store.put(_site.url, topic);

    final result = controller.openAggregateTopic(_site.url, topic.id);

    expect(result, AggregateTopicOpenResult.opened);
    expect(controller.currentContent?.topicId, topic.id);
    expect(controller.tabsForCurrentForum, hasLength(1));
  });

  test('restored aggregate tabs load only when they are opened', () async {
    const firstTabId = 'aggregate-open';
    const secondTabId = 'aggregate-ux';
    const openPath = '/filter.json?per_page=30&q=status%3Aopen';
    const uxPath = '/filter.json?per_page=30&q=tag%3Aux';
    final preferences = AggregatePreferencesStore.memory();
    await preferences.save(
      tabs: [
        AggregateTabPreferences(
          id: firstTabId,
          queries: {_site.url: 'status:open'},
        ),
        AggregateTabPreferences(
          id: secondTabId,
          queries: {_site.url: 'tag:ux'},
        ),
      ],
      activeTabId: firstTabId,
    );
    final api = FakeDiscourseApi(
      feeds: const {
        '/latest.json': [],
        openPath: [Topic(id: 1, title: 'Open', slug: 'open')],
        uxPath: [Topic(id: 2, title: 'UX', slug: 'ux')],
      },
    );
    final authenticator = FakeAuthenticator()..keys[_site.url] = 'key';
    final controller = ShellController(
      instanceStore: FakeInstanceStore(const [_site]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      aggregatePreferences: preferences,
      trackers: FakeSiteTracker.reset(),
      initialRootMode: ShellRootMode.aggregate,
    );
    addTearDown(controller.dispose);

    await controller.load();
    await controller.aggregate.open(controller.instances);

    expect(controller.activeAggregateTabId, firstTabId);
    expect(api.feedPaths.where((path) => path.startsWith('/filter')), [
      openPath,
    ]);

    controller.selectAggregateTab(secondTabId);
    await controller.aggregate.open(controller.instances);

    expect(controller.aggregate.state.topics.single.topicId, 2);
    expect(api.feedPaths.where((path) => path.startsWith('/filter')), [
      openPath,
      uxPath,
    ]);

    controller.selectAggregateTab(firstTabId);
    await controller.aggregate.open(controller.instances);

    expect(controller.aggregate.state.topics.single.topicId, 1);
    expect(api.feedPaths.where((path) => path.startsWith('/filter')), [
      openPath,
      uxPath,
    ]);
  });
}

const _site = DiscourseInstance(
  url: 'https://one.example',
  title: 'One',
  user: DiscourseUser(username: 'sam'),
);

const _second = DiscourseInstance(
  url: 'https://two.example',
  title: 'Two',
  user: DiscourseUser(username: 'sam'),
);

Topic _bumped(int id, int minute) => Topic(
  id: id,
  title: 'Topic $id',
  slug: 'topic-$id',
  bumpedAt: DateTime.utc(2026, 1, 1, 0, minute),
);

/// Answers `/filter.json` per forum, so two forums can share a page path.
final class _SiteFeedsApi extends FakeDiscourseApi {
  _SiteFeedsApi() : super(feeds: const {'/latest.json': []});

  final Map<String, TopicList> replies = {};
  final Map<String, Completer<void>> holds = {};
  final List<String> filterRequests = [];

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    if (!path.startsWith('/filter')) {
      return super.topicList(
        siteUrl: siteUrl,
        path: path,
        apiKey: apiKey,
        clientId: clientId,
      );
    }
    final key = '$siteUrl|$path';
    filterRequests.add(key);
    await holds[key]?.future;
    return replies[key] ?? const TopicList(topics: []);
  }
}

/// Two signed-in forums, opened on Aggregate.
ShellController _aggregateController(FakeDiscourseApi api) => ShellController(
  instanceStore: FakeInstanceStore(const [_site, _second]),
  api: api,
  authenticator: FakeAuthenticator()
    ..keys[_site.url] = 'one'
    ..keys[_second.url] = 'two',
  drafts: FakeDraftStore(),
  forumTabs: FakeForumTabStore(),
  aggregatePreferences: AggregatePreferencesStore.memory(),
  trackers: FakeSiteTracker.reset(),
  initialRootMode: ShellRootMode.aggregate,
);

ShellController _controller({
  required Store store,
  bool forumTabsEnabled = true,
  FakeDiscourseApi? api,
  List<DiscourseInstance> instances = const [_site],
}) => ShellController(
  instanceStore: FakeInstanceStore(instances),
  api: api ?? FakeDiscourseApi(feeds: const {'/latest.json': []}),
  authenticator: FakeAuthenticator(),
  drafts: FakeDraftStore(),
  forumTabs: FakeForumTabStore(),
  forumTabsEnabled: forumTabsEnabled,
  store: store,
  aggregatePreferences: AggregatePreferencesStore.memory(),
  trackers: FakeSiteTracker.reset(),
);
