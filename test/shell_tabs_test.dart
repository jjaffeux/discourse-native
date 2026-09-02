import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final forums = [
    instance('one.example', title: 'One'),
    instance('two.example', title: 'Two'),
  ];

  late ShellController controller;
  late FakeForumTabStore forumTabs;

  group('ShellController tabs', () {
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

    group('creation', () {
      test('opens a topic in the background with its requested post', () {
        controller.openTopicUrl('/t/another-topic/42/3');
        final original = controller.activeTab;

        expect(
          controller.openLinkInNewTab('/t/another-topic/42/8'),
          TabOpenResult.opened,
        );

        expect(controller.activeTab, original);
        expect(controller.tabsForCurrentForum, hasLength(2));
        final opened = controller.tabsForCurrentForum.last;
        expect(opened.currentContent.topicId, 42);
        expect(opened.currentContent.postNumber, 8);

        controller.selectTab(opened.id);
        expect(controller.currentContent?.topicId, 42);
        expect(controller.currentContent?.postNumber, 8);
      });

      test(
        'opens another forum’s link without switching the current forum',
        () {
          final original = controller.activeTab;

          expect(
            controller.openLinkInNewTab('https://two.example/tag/flutter'),
            TabOpenResult.opened,
          );

          expect(controller.currentInstance?.url, forums.first.url);
          expect(controller.activeTab, original);
          expect(controller.tabsForCurrentForum, hasLength(1));

          controller.selectInstance(1);
          expect(controller.tabsForCurrentForum, hasLength(2));
          expect(
            controller.tabsForCurrentForum.last.currentContent.feedPath,
            '/tag/flutter.json',
          );
        },
      );

      test(
        'opens category and group links without changing the active tab',
        () {
          final original = controller.activeTab;

          expect(
            controller.openLinkInNewTab('/c/support/12', title: 'Support'),
            TabOpenResult.opened,
          );
          expect(
            controller.tabsForCurrentForum.last.currentContent.title,
            'Support',
          );
          expect(
            controller.tabsForCurrentForum.last.currentContent.feedPath,
            '/c/support/12.json',
          );
          expect(controller.openLinkInNewTab('/g/staff'), TabOpenResult.opened);
          expect(
            controller
                .tabsForCurrentForum
                .last
                .currentContent
                .groupRoute
                ?.groupName,
            'staff',
          );
          expect(controller.activeTab, original);
        },
      );

      test('declines unsupported links without creating empty tabs', () {
        final original = controller.activeTab;
        for (final url in [
          'https://other.example/t/topic/42',
          '/about',
          'https://name:password@one.example/t/topic/42',
          '/c/support/12/l/top',
        ]) {
          expect(controller.openLinkInNewTab(url), TabOpenResult.unsupported);
        }
        expect(controller.tabsForCurrentForum, hasLength(1));
        expect(controller.activeTab, original);
      });

      test('adds and activates a fresh Topics tab', () {
        final originalTabId = controller.activeTabId;

        expect(originalTabId, isNotNull);
        expect(controller.tabsForCurrentForum, hasLength(1));

        controller.createTab();

        expect(controller.tabsForCurrentForum, hasLength(2));
        expect(controller.activeTabId, isNot(originalTabId));
        _expectTopicsRoot(controller);
      });

      test('stops at the bounded eager workspace capacity', () {
        for (var count = 1; count < ForumWorkspace.maximumTabs; count++) {
          expect(
            controller.canCreateTab,
            isTrue,
            reason: 'A workspace with $count tabs should still accept another.',
          );
          controller.createTab();
          expect(controller.tabsForCurrentForum, hasLength(count + 1));
        }
        final active = controller.activeTabId;

        expect(
          controller.tabsForCurrentForum,
          hasLength(ForumWorkspace.maximumTabs),
        );
        expect(controller.canCreateTab, isFalse);

        controller.createTab();
        expect(
          controller.tabsForCurrentForum,
          hasLength(ForumWorkspace.maximumTabs),
        );
        expect(controller.activeTabId, active);
        final content = controller.currentContent;
        expect(
          controller.openLinkInNewTab('/t/full-workspace/42'),
          TabOpenResult.limitReached,
        );
        expect(controller.activeTabId, active);
        expect(controller.currentContent, content);
      });
    });

    group('forum-scoped navigation', () {
      test('bounds content history while preserving its root', () {
        for (var id = 1; id <= ForumTab.maximumContentRoutes + 5; id++) {
          controller.pushContent(_topic(id, 'Topic $id'));
        }

        expect(
          controller.contentStack,
          hasLength(ForumTab.maximumContentRoutes),
        );
        expect(controller.contentStack.first.id, 'latest');
        expect(controller.contentStack[1].topicId, 7);
        expect(controller.contentStack.last.topicId, 69);
      });

      test('moves backward and forward through content history', () {
        controller.pushContent(_topic(101, 'First topic'));
        controller.pushContent(_topic(202, 'Second topic'));

        expect(controller.canForwardContent, isFalse);
        expect(controller.handleBack(canReturnToSidebar: false), isTrue);
        expect(_routeIds(controller), ['latest', 'topic-101']);
        expect(controller.canForwardContent, isTrue);

        expect(controller.handleForward(), isTrue);
        expect(_routeIds(controller), ['latest', 'topic-101', 'topic-202']);
        expect(controller.canForwardContent, isFalse);
      });

      test('a new push after Back clears forward history', () {
        controller.pushContent(_topic(101, 'First topic'));
        controller.pushContent(_topic(202, 'Second topic'));
        controller.handleBack(canReturnToSidebar: false);

        expect(controller.canForwardContent, isTrue);

        controller.pushContent(_topic(303, 'Replacement topic'));

        expect(_routeIds(controller), ['latest', 'topic-101', 'topic-303']);
        expect(controller.canForwardContent, isFalse);
        expect(controller.handleForward(), isFalse);
      });

      test('Forward is a no-op without forward history', () {
        final content = controller.currentContent;
        final stack = controller.contentStack;

        expect(controller.canForwardContent, isFalse);
        expect(controller.handleForward(), isFalse);
        expect(controller.currentContent, same(content));
        expect(controller.contentStack, same(stack));
      });

      test('hydrates a restored route when moving Forward', () async {
        final latest = ContentRoute.fromDestination(
          _destination(forums.first, 'latest'),
        );
        final futureTopic = _topic(202, 'Restored future topic');
        final restoredTabs = FakeForumTabStore([
          ForumWorkspace(
            siteUrl: forums.first.url,
            accountIdentity: 'anonymous',
            tabs: [
              ForumTab(
                id: 'restored-history',
                rootDestinationId: 'latest',
                contentStack: [latest],
                forwardStack: [futureTopic],
              ),
            ],
            activeTabId: 'restored-history',
          ),
        ]);
        final api = FakeDiscourseApi(
          feeds: const {'/latest.json': []},
          topics: {202: topicPayload(id: 202, title: 'Restored future topic')},
        );
        final restored = ShellController(
          instanceStore: FakeInstanceStore(forums),
          api: api,
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          forumTabs: restoredTabs,
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(restored.dispose);
        await restored.load();

        expect(api.topicsOpened, isEmpty);

        expect(restored.handleForward(), isTrue);
        await Future<void>.delayed(Duration.zero);

        expect(api.topicsOpened, [202]);
      });

      test('keeps forward history isolated per tab', () {
        final firstTabId = controller.activeTabId!;
        controller.pushContent(_topic(101, 'First topic'));
        controller.pushContent(_topic(202, 'Second topic'));
        controller.handleBack(canReturnToSidebar: false);

        expect(controller.canForwardContent, isTrue);

        controller.createTab();
        final secondTabId = controller.activeTabId!;

        expect(controller.canForwardContent, isFalse);
        expect(controller.handleForward(), isFalse);

        controller.selectTab(firstTabId);

        expect(controller.canForwardContent, isTrue);
        expect(controller.handleForward(), isTrue);
        expect(controller.currentContent?.topicId, 202);

        controller.selectTab(secondTabId);

        expect(controller.canForwardContent, isFalse);
        _expectTopicsRoot(controller);
      });

      test('keeps independent active content stacks per forum', () {
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

      test("restores each forum's last active tab", () {
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
    });

    group('tab lifecycle', () {
      test(
        'selects the nearest surviving neighbour after an active tab closes',
        () {
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
        },
      );

      test('replaces the final closed tab with a fresh Topics tab', () {
        final closedTabId = controller.activeTabId!;

        controller.closeTab(closedTabId);

        expect(controller.tabsForCurrentForum, hasLength(1));
        expect(controller.activeTabId, isNotNull);
        expect(controller.activeTabId, isNot(closedTabId));
        _expectTopicsRoot(controller);
      });

      test('preserves the active tab and persists reordered tabs', () {
        final firstTabId = controller.activeTabId!;
        controller.createTab();
        final secondTabId = controller.activeTabId!;
        controller.createTab();
        final thirdTabId = controller.activeTabId!;
        final savesBeforeMove = forumTabs.saveCount;

        controller.moveTab(firstTabId, 2);

        expect(controller.tabsForCurrentForum.map((tab) => tab.id), [
          secondTabId,
          thirdTabId,
          firstTabId,
        ]);
        expect(controller.activeTabId, thirdTabId);
        expect(forumTabs.saveCount, savesBeforeMove + 1);
        expect(forumTabs.workspaces.single.tabs.map((tab) => tab.id), [
          secondTabId,
          thirdTabId,
          firstTabId,
        ]);
      });

      test('keeps and activates the requested tab when closing others', () {
        final firstTabId = controller.activeTabId!;
        controller.pushContent(_topic(303, 'Kept topic'));
        controller.createTab();
        controller.createTab();

        controller.closeOtherTabs(firstTabId);

        expect(controller.tabsForCurrentForum.map((tab) => tab.id), [
          firstTabId,
        ]);
        expect(controller.activeTabId, firstTabId);
        expect(_routeIds(controller), ['latest', 'topic-303']);
      });

      test('reopens tabs closed by close others in their original order', () {
        final firstTabId = controller.activeTabId!;
        controller.createTab();
        final secondTabId = controller.activeTabId!;
        controller.createTab();
        final thirdTabId = controller.activeTabId!;

        controller.closeOtherTabs(secondTabId);

        expect(controller.reopenClosedTab(), isTrue);
        expect(controller.tabsForCurrentForum.map((tab) => tab.id), [
          firstTabId,
          secondTabId,
        ]);
        expect(controller.activeTabId, firstTabId);

        expect(controller.reopenClosedTab(), isTrue);
        expect(controller.tabsForCurrentForum.map((tab) => tab.id), [
          firstTabId,
          secondTabId,
          thirdTabId,
        ]);
        expect(controller.activeTabId, thirdTabId);

        expect(controller.reopenClosedTab(), isFalse);
      });
    });

    group('per-tab state', () {
      test('limits ordinary destination changes to the active tab', () {
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

      test('restores feed rows independently', () {
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

      test('restores topic posts independently', () {
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
    });

    group('anchor persistence', () {
      test('coalesces rapid saves into one trailing write', () async {
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

      test('flushes a pending write on disposal', () async {
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

      test('flushes a pending write on backgrounding', () async {
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
    });

    group('workspace persistence', () {
      test(
        'restores tab order, active stack, and anchors after restart',
        () async {
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
        },
      );

      test('flushes a tab selection awaiting paint on disposal', () async {
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
    });

    group('disabled mode', () {
      test('ignores tab lifecycle commands', () async {
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
        disabled.moveTab(tabId, 3);
        disabled.closeOtherTabs(tabId);

        expect(disabled.tabsForCurrentForum, hasLength(1));
        expect(disabled.activeTabId, tabId);
        expect(_routeIds(disabled), ['latest', 'topic-505']);
        expect(disabledTabs.saveCount, saveCount);
      });

      test('migrates to the prior active tab', () async {
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
    });
  });
}

ContentRoute _topic(int id, String title) =>
    ContentRoute.topic(topicId: id, slug: 'topic-$id', title: title);

SidebarDestination _destination(DiscourseInstance forum, String id) => forum
    .sections
    .expand((section) => [...section.destinations, ...section.moreDestinations])
    .singleWhere((destination) => destination.id == id);

List<String> _routeIds(ShellController controller) => [
  for (final route in controller.contentStack) route.id,
];

void _expectTopicsRoot(ShellController controller) {
  expect(controller.destinationId, 'latest');
  expect(_routeIds(controller), ['latest']);
  expect(controller.currentContent?.title, 'Topics');
}
