import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

// Regression contract for desktop forum-scoped shell tabs and the mobile
// single-context fallback.
//
// These tests intentionally name the controller API before its production
// implementation exists. The contract assumes:
//
// * a forum starts with one active Topics tab;
// * createTab() appends and activates a fresh Topics tab;
// * activeTabId is an opaque, nullable id accepted by selectTab/closeTab;
// * tabsForCurrentForum is ordered, but its element type is otherwise private
//   to the implementation (these tests only observe its length);
// * closing the active tab selects its right neighbour, or its left neighbour
//   when there is no tab to the right;
// * closing the final tab replaces it with a fresh Topics tab; and
// * selectDestination/pushContent mutate only the active tab.
//
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final forums = [
    instance('one.example', title: 'One'),
    instance('two.example', title: 'Two'),
  ];

  late ShellController controller;
  late FakeForumTabStore forumTabs;

  setUp(() async {
    forumTabs = FakeForumTabStore();
    controller = ShellController(
      instanceStore: FakeInstanceStore(forums),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: forumTabs,
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
  });

  test('createTab adds and activates a fresh Topics tab', () {
    final originalTabId = controller.activeTabId;

    expect(originalTabId, isNotNull);
    expect(controller.tabsForCurrentForum, hasLength(1));

    controller.createTab();

    expect(controller.tabsForCurrentForum, hasLength(2));
    expect(controller.activeTabId, isNot(originalTabId));
    _expectTopicsRoot(controller);
  });

  test('tab creation stops at the bounded eager workspace capacity', () {
    expect(controller.canCreateTab, isTrue);
    while (controller.canCreateTab) {
      controller.createTab();
    }
    final active = controller.activeTabId;

    expect(
      controller.tabsForCurrentForum,
      hasLength(ForumWorkspace.maximumTabs),
    );
    expect(controller.canCreateTab, isFalse);

    controller.createTab();
    expect(controller.tabsForCurrentForum, hasLength(20));
    expect(controller.activeTabId, active);
  });

  test('content history keeps its root and most recent bounded routes', () {
    for (var id = 1; id <= ForumTab.maximumContentRoutes + 5; id++) {
      controller.pushContent(_topic(id, 'Topic $id'));
    }

    expect(controller.contentStack, hasLength(ForumTab.maximumContentRoutes));
    expect(controller.contentStack.first.id, 'latest');
    expect(controller.contentStack[1].topicId, 7);
    expect(controller.contentStack.last.topicId, 69);
  });

  test('each forum keeps an independent active content stack', () {
    final firstForumTabId = controller.activeTabId;
    controller.pushContent(_topic(101, 'First forum topic'));

    controller.selectInstance(1);
    final secondForumTabId = controller.activeTabId;
    controller.pushContent(_topic(202, 'Second forum topic'));

    expect(secondForumTabId, isNotNull);
    expect(_routeIds(controller), ['latest', 'topic-202']);

    controller.selectInstance(0);

    expect(controller.activeTabId, firstForumTabId);
    expect(_routeIds(controller), ['latest', 'topic-101']);

    controller.selectInstance(1);

    expect(controller.activeTabId, secondForumTabId);
    expect(_routeIds(controller), ['latest', 'topic-202']);
  });

  test('switching forums restores the last active tab in each forum', () {
    final firstForumInitialTabId = controller.activeTabId;
    controller.createTab();
    final firstForumLastTabId = controller.activeTabId;
    controller.selectDestination(_destination(forums[0], 'filter'));

    controller.selectInstance(1);
    controller.createTab();
    controller.createTab();
    final secondForumLastTabId = controller.activeTabId;
    controller.selectDestination(_destination(forums[1], 'filter'));

    expect(controller.tabsForCurrentForum, hasLength(3));
    expect(controller.currentContent?.id, 'filter');

    controller.selectInstance(0);

    expect(controller.tabsForCurrentForum, hasLength(2));
    expect(controller.activeTabId, firstForumLastTabId);
    expect(controller.activeTabId, isNot(firstForumInitialTabId));
    expect(controller.currentContent?.id, 'filter');

    controller.selectInstance(1);

    expect(controller.tabsForCurrentForum, hasLength(3));
    expect(controller.activeTabId, secondForumLastTabId);
    expect(controller.currentContent?.id, 'filter');
  });

  test('closing the active tab chooses the nearest surviving neighbour', () {
    final firstTabId = controller.activeTabId!;
    controller.createTab();
    final middleTabId = controller.activeTabId!;
    controller.createTab();
    final lastTabId = controller.activeTabId!;

    controller.selectTab(middleTabId);
    controller.closeTab(middleTabId);

    expect(controller.tabsForCurrentForum, hasLength(2));
    expect(controller.activeTabId, lastTabId);

    controller.closeTab(lastTabId);

    expect(controller.tabsForCurrentForum, hasLength(1));
    expect(controller.activeTabId, firstTabId);
  });

  test('closing the final tab falls back to a fresh Topics tab', () {
    final closedTabId = controller.activeTabId!;

    controller.closeTab(closedTabId);

    expect(controller.tabsForCurrentForum, hasLength(1));
    expect(controller.activeTabId, isNotNull);
    expect(controller.activeTabId, isNot(closedTabId));
    _expectTopicsRoot(controller);
  });

  test('closing other tabs keeps and activates the requested tab', () {
    final firstTabId = controller.activeTabId!;
    controller.pushContent(_topic(303, 'Kept topic'));
    controller.createTab();
    controller.createTab();

    controller.closeOtherTabs(firstTabId);

    expect(controller.tabsForCurrentForum.map((tab) => tab.id), [firstTabId]);
    expect(controller.activeTabId, firstTabId);
    expect(_routeIds(controller), ['latest', 'topic-303']);
  });

  test('ordinary destination changes affect only the active tab', () {
    final firstTabId = controller.activeTabId!;
    controller.pushContent(_topic(303, 'First tab topic'));

    controller.createTab();
    final secondTabId = controller.activeTabId!;
    controller.selectDestination(_destination(forums[0], 'filter'));

    expect(_routeIds(controller), ['filter']);

    controller.selectTab(firstTabId);

    expect(_routeIds(controller), ['latest', 'topic-303']);

    controller.selectTab(secondTabId);

    expect(_routeIds(controller), ['filter']);
  });

  test('each tab restores its own feed row', () {
    final firstTabId = controller.activeTabId!;
    controller.saveFeedScrollRow('latest', 12);

    controller.createTab();
    final secondTabId = controller.activeTabId!;
    expect(controller.feedScrollRow('latest'), 0);
    controller.saveFeedScrollRow('latest', 3);

    controller.selectTab(firstTabId);
    expect(controller.feedScrollRow('latest'), 12);

    controller.selectTab(secondTabId);
    expect(controller.feedScrollRow('latest'), 3);
  });

  test('each tab restores its own topic post', () {
    final firstTabId = controller.activeTabId!;
    controller.pushContent(_topic(303, 'Shared topic'));
    controller.saveTopicScrollPost(303, 18);

    controller.createTab();
    final secondTabId = controller.activeTabId!;
    controller.pushContent(_topic(303, 'Shared topic'));
    expect(controller.topicScrollPostNumber(303), isNull);
    controller.saveTopicScrollPost(303, 4);

    controller.selectTab(firstTabId);
    expect(controller.topicScrollPostNumber(303), 18);

    controller.selectTab(secondTabId);
    expect(controller.topicScrollPostNumber(303), 4);
  });

  test('rapid anchor saves coalesce into one trailing write', () async {
    final anchorTabs = FakeForumTabStore();
    final scrolling = ShellController(
      instanceStore: FakeInstanceStore(forums),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: anchorTabs,
      trackers: FakeSiteTracker.reset(),
      // Zero still defers to the next event-loop turn, so a synchronous
      // scroll burst shares one window without slowing the test down.
      anchorPersistDebounce: Duration.zero,
    );
    addTearDown(scrolling.dispose);
    await scrolling.load();
    scrolling.pushContent(_topic(303, 'Scrolled topic'));
    final savesBeforeScroll = anchorTabs.saveCount;

    scrolling.saveFeedScrollRow('latest', 4);
    scrolling.saveTopicScrollPost(303, 2);
    scrolling.saveTopicScrollPost(303, 9);
    scrolling.saveTopicScrollPost(303, 27, viewportOffset: -12);

    // The tab already carries the anchors; only the write waits.
    expect(scrolling.topicScrollPostNumber(303), 27);
    expect(anchorTabs.saveCount, savesBeforeScroll);

    await Future<void>.delayed(Duration.zero);

    expect(anchorTabs.saveCount, savesBeforeScroll + 1);
    final anchors = anchorTabs.workspaces.single.activeTab.anchors;
    expect(anchors['latest']?.itemId, 4);
    expect(anchors['topic-303']?.itemId, 27);
    expect(anchors['topic-303']?.offset, -12);

    await Future<void>.delayed(Duration.zero);
    expect(anchorTabs.saveCount, savesBeforeScroll + 1);
  });

  test('disposing flushes a pending anchor write', () async {
    final anchorTabs = FakeForumTabStore();
    final closing = ShellController(
      instanceStore: FakeInstanceStore(forums),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: anchorTabs,
      trackers: FakeSiteTracker.reset(),
    );
    await closing.load();
    closing.pushContent(_topic(606, 'Closed topic'));
    final savesBeforeScroll = anchorTabs.saveCount;
    closing.saveTopicScrollPost(606, 21);
    expect(anchorTabs.saveCount, savesBeforeScroll);

    closing.dispose();

    expect(anchorTabs.saveCount, savesBeforeScroll + 1);
    expect(
      anchorTabs.workspaces.single.activeTab.anchors['topic-606']?.itemId,
      21,
    );
  });

  test('backgrounding flushes a pending anchor write', () async {
    controller.pushContent(_topic(707, 'Background topic'));
    final savesBeforeScroll = forumTabs.saveCount;
    controller.saveTopicScrollPost(707, 12);
    expect(forumTabs.saveCount, savesBeforeScroll);

    controller.setForeground(false);

    expect(forumTabs.saveCount, savesBeforeScroll + 1);
    expect(
      forumTabs.workspaces.single.activeTab.anchors['topic-707']?.itemId,
      12,
    );
  });

  test('restores tab order, active stack, and anchors after restart', () async {
    final firstTabId = controller.activeTabId!;
    controller.saveFeedScrollRow('latest', 8);
    controller.pushContent(_topic(404, 'Persisted topic'));
    controller.saveTopicScrollPost(404, 16);
    controller.createTab();
    final activeTabId = controller.activeTabId!;
    controller.selectDestination(_destination(forums[0], 'filter'));
    await Future<void>.delayed(Duration.zero);

    controller = ShellController(
      instanceStore: FakeInstanceStore(forums),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: forumTabs,
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(controller.tabsForCurrentForum.map((tab) => tab.id), [
      firstTabId,
      activeTabId,
    ]);
    expect(controller.activeTabId, activeTabId);
    expect(_routeIds(controller), ['filter']);

    controller.selectTab(firstTabId);
    expect(_routeIds(controller), ['latest', 'topic-404']);
    expect(controller.feedScrollRow('latest'), 8);
    expect(controller.topicScrollPostNumber(404), 16);
  });

  test('disposing flushes a tab selection waiting for its paint', () async {
    final closingTabs = FakeForumTabStore();
    final closing = ShellController(
      instanceStore: FakeInstanceStore(forums),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: closingTabs,
      trackers: FakeSiteTracker.reset(),
    );
    await closing.load();
    final firstTabId = closing.activeTabId!;
    closing.createTab();
    final savesBeforeSelection = closingTabs.saveCount;

    // A listener makes selection use the paint-first path. No frame is pumped
    // before disposal, matching a window closed immediately after the click.
    closing.addListener(() {});
    closing.selectTab(firstTabId);
    expect(closingTabs.saveCount, savesBeforeSelection);

    closing.dispose();

    expect(closingTabs.saveCount, savesBeforeSelection + 1);
    expect(closingTabs.workspaces.single.activeTabId, firstTabId);
  });

  test('disabled mode ignores tab lifecycle commands', () async {
    final disabledTabs = FakeForumTabStore();
    final disabled = ShellController(
      instanceStore: FakeInstanceStore(forums),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: disabledTabs,
      forumTabsEnabled: false,
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(disabled.dispose);
    await disabled.load();

    final tabId = disabled.activeTabId!;
    disabled.pushContent(_topic(505, 'Kept topic'));
    final saveCount = disabledTabs.saveCount;

    disabled.createTab();
    disabled.selectTab(tabId);
    disabled.closeTab(tabId);
    disabled.closeOtherTabs(tabId);

    expect(disabled.tabsForCurrentForum, hasLength(1));
    expect(disabled.activeTabId, tabId);
    expect(_routeIds(disabled), ['latest', 'topic-505']);
    expect(disabledTabs.saveCount, saveCount);
  });

  test('disabled mode migrates to the prior active tab', () async {
    final latest = ContentRoute.fromDestination(
      _destination(forums.first, 'latest'),
    );
    final filter = ContentRoute.fromDestination(
      _destination(forums.first, 'filter'),
    );
    final inactive = ForumTab(
      id: 'inactive-tab',
      rootDestinationId: 'latest',
      contentStack: [latest],
    );
    final active = ForumTab(
      id: 'active-tab',
      rootDestinationId: 'latest',
      contentStack: [latest, filter],
      anchors: const {'latest': ForumTabAnchor(kind: 'feed', itemId: 27)},
    );
    final disabledTabs = FakeForumTabStore([
      ForumWorkspace(
        siteUrl: forums.first.url,
        accountIdentity: 'anonymous',
        tabs: [inactive, active],
        activeTabId: active.id,
      ),
    ]);
    final disabled = ShellController(
      instanceStore: FakeInstanceStore(forums),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: disabledTabs,
      forumTabsEnabled: false,
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(disabled.dispose);

    await disabled.load();

    expect(disabled.tabsForCurrentForum, [same(active)]);
    expect(disabled.activeTabId, active.id);
    expect(disabled.contentStack, active.contentStack);
    expect(disabled.activeTab?.anchors, active.anchors);
    expect(disabledTabs.saveCount, 1);
    expect(disabledTabs.workspaces.single.tabs, [same(active)]);
  });
}

ContentRoute _topic(int id, String title) =>
    ContentRoute.topic(topicId: id, slug: 'topic-$id', title: title);

SidebarDestination _destination(DiscourseInstance forum, String id) => forum
    .sections
    .expand((section) => section.destinations)
    .singleWhere((destination) => destination.id == id);

List<String> _routeIds(ShellController controller) => [
  for (final route in controller.contentStack) route.id,
];

void _expectTopicsRoot(ShellController controller) {
  expect(controller.destinationId, 'latest');
  expect(_routeIds(controller), ['latest']);
  expect(controller.currentContent?.title, 'Topics');
}
