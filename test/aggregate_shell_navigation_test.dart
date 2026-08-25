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

  test('aggregate topic gets a new forum tab and then reuses it', () async {
    final store = Store();
    final controller = _controller(store: store);
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
    expect(controller.tabsForCurrentForum, hasLength(2));
    final topicTabId = controller.activeTabId;

    controller.selectAggregate();
    final second = controller.openAggregateTopic(_site.url, topic.id);

    expect(second, AggregateTopicOpenResult.opened);
    expect(controller.tabsForCurrentForum, hasLength(2));
    expect(controller.activeTabId, topicTabId);
  });

  test('tab limit leaves the aggregate surface in place', () async {
    final store = Store();
    final controller = _controller(store: store);
    addTearDown(controller.dispose);
    await controller.load();
    while (controller.tabsForCurrentForum.length < ForumWorkspace.maximumTabs) {
      controller.createTab();
    }
    const topic = Topic(id: 7, title: 'Overflow', slug: 'overflow');
    store.put(_site.url, topic);
    controller.selectAggregate();

    final result = controller.openAggregateTopic(_site.url, topic.id);

    expect(result, AggregateTopicOpenResult.tabLimitReached);
    expect(controller.rootMode, ShellRootMode.aggregate);
    expect(
      controller.tabsForCurrentForum,
      hasLength(ForumWorkspace.maximumTabs),
    );
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
}

const _site = DiscourseInstance(
  url: 'https://one.example',
  title: 'One',
  user: DiscourseUser(username: 'sam'),
);

ShellController _controller({
  required Store store,
  bool forumTabsEnabled = true,
}) => ShellController(
  instanceStore: FakeInstanceStore(const [_site]),
  api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
  authenticator: FakeAuthenticator(),
  drafts: FakeDraftStore(),
  forumTabs: FakeForumTabStore(),
  forumTabsEnabled: forumTabsEnabled,
  store: store,
  aggregatePreferences: AggregatePreferencesStore.memory(),
  trackers: FakeSiteTracker.reset(),
);
