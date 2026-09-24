import 'package:discourse_native/src/data/aggregate_preferences_store.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/topic.dart';
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
