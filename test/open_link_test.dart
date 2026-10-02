import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/open_link.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart' show watchBrowser;

void main() {
  for (final post in [false, true]) {
    testWidgets(
      'shared menu bookmarks and removes the clicked ${post ? 'post' : 'topic'}',
      (tester) async {
        final api = _LinkBookmarkApi();
        final controller = await _pumpLink(
          tester,
          signedIn: true,
          api: api,
          url: '/t/clicked/42${post ? '/3' : ''}',
        );
        final before = controller.currentContent;
        await tester.tap(
          find.text('Open link'),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('Bookmark'), findsOneWidget);
        await tester.tap(find.text('Bookmark'));
        await tester.pumpAndSettle();
        expect(api.createdBookmarks.single.targetId, post ? 99 : 42);
        expect(
          api.createdBookmarks.single.targetType,
          post ? BookmarkTargetType.post : BookmarkTargetType.topic,
        );
        expect(controller.currentContent, before);
        await tester.tap(
          find.text('Open link'),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('Remove bookmark'), findsOneWidget);
        await tester.tap(find.text('Remove bookmark'));
        await tester.pumpAndSettle();
        expect(api.deletedBookmarks, [1000]);
        expect(controller.currentContent, before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('topic item bookmark identity ignores its navigation position', (
    tester,
  ) async {
    final api = _LinkBookmarkApi();
    await _pumpLink(
      tester,
      signedIn: true,
      api: api,
      url: '/t/clicked/42/3',
      bookmarkUrl: '/t/clicked/42',
    );
    await tester.tap(
      find.text('Open link'),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bookmark'));
    await tester.pumpAndSettle();
    expect(api.createdBookmarks.single.targetType, BookmarkTargetType.topic);
    expect(api.createdBookmarks.single.targetId, 42);
  });

  testWidgets('dismissed menu ignores a late bookmark lookup', (tester) async {
    final gate = Completer<void>();
    final api = FakeDiscourseApi(
      topics: {42: topicPayload(id: 42)},
      topicGate: gate,
    );
    await _pumpLink(tester, signedIn: true, api: api);
    await tester.tap(
      find.text('Open link'),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Bookmark'), findsNothing);
    expect(api.createdBookmarks, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final signedIn in [false, true]) {
    testWidgets(
      'shared menus omit unsupported targets (signed in: $signedIn)',
      (tester) async {
        await _pumpLink(
          tester,
          signedIn: signedIn,
          url: signedIn ? '/c/general/1' : '/t/topic/42',
          api: _LinkBookmarkApi(),
        );
        await tester.tap(
          find.text('Open link'),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('Open in main panel'), findsOneWidget);
        expect(find.text('Bookmark'), findsNothing);
        expect(find.text('Remove bookmark'), findsNothing);
      },
    );
  }

  for (final newTab in [false, true]) {
    testWidgets('opens the forum users URL natively (new tab: $newTab)', (
      tester,
    ) async {
      final launched = watchBrowser(tester);
      final controller = await _pumpLink(tester, url: 'https://one.example/u');
      controller.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('Open link'),
        kind: PointerDeviceKind.mouse,
        buttons: newTab ? kMiddleMouseButton : kPrimaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(launched, isEmpty);
      if (newTab) {
        expect(controller.tabsForCurrentForum, hasLength(2));
        controller.selectTab(controller.tabsForCurrentForum.last.id);
        await tester.pumpAndSettle();
      }
      expect(controller.currentContent?.id, 'users');
    });
  }

  for (final url in [
    'https://one.example/my/messages',
    'https://one.example/u/j.jaffeux/messages',
  ]) {
    for (final newTab in [false, true]) {
      testWidgets('opens $url natively (new tab: $newTab)', (tester) async {
        final launched = watchBrowser(tester);
        final controller = await _pumpLink(
          tester,
          url: url,
          signedIn: true,
          api: FakeDiscourseApi(
            feeds: const {
              '/latest.json': [],
              '/topics/private-messages/j.jaffeux.json': [],
            },
          ),
        );
        controller.pushContent(ContentRoute.newTab());
        await tester.pumpAndSettle();

        await tester.tap(
          find.text('Open link'),
          kind: PointerDeviceKind.mouse,
          buttons: newTab ? kMiddleMouseButton : kPrimaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(launched, isEmpty);
        if (newTab) {
          expect(controller.tabsForCurrentForum, hasLength(2));
          controller.selectTab(controller.tabsForCurrentForum.last.id);
          await tester.pumpAndSettle();
        }
        expect(controller.currentContent?.id, 'messages');
        expect(controller.currentFeedId, 'messages');
      });
    }
  }

  for (final (url, routeId, feedPath) in const [
    (
      'https://one.example/u/j.jaffeux/messages/group/team',
      'messages-group-team',
      '/topics/private-messages-group/j.jaffeux/team.json',
    ),
    (
      'https://one.example/my/messages/group/Team/archive',
      'messages-group-team/archive',
      '/topics/private-messages-group/j.jaffeux/team/archive.json',
    ),
    (
      'https://one.example/u/J.Jaffeux/messages/sent',
      'messages-sent',
      '/topics/private-messages-sent/j.jaffeux.json',
    ),
  ]) {
    for (final newTab in [false, true]) {
      testWidgets('opens $url natively (new tab: $newTab)', (tester) async {
        final launched = watchBrowser(tester);
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': const [], feedPath: const []},
        );
        final controller = await _pumpLink(
          tester,
          url: url,
          signedIn: true,
          messageGroupNames: const ['team'],
          api: api,
        );
        controller.pushContent(ContentRoute.newTab());
        await tester.pumpAndSettle();

        await tester.tap(
          find.text('Open link'),
          kind: PointerDeviceKind.mouse,
          buttons: newTab ? kMiddleMouseButton : kPrimaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(launched, isEmpty);
        if (newTab) {
          expect(controller.tabsForCurrentForum, hasLength(2));
          controller.selectTab(controller.tabsForCurrentForum.last.id);
          await tester.pumpAndSettle();
        }
        expect(controller.currentContent?.id, routeId);
        expect(controller.currentFeedId, routeId);
        expect(api.feedPaths, contains(feedPath));
      });
    }
  }

  for (final url in const [
    'https://one.example/u/another-user/messages',
    'https://one.example/u/another-user/messages/group/team',
    'https://one.example/u/j.jaffeux/messages/group/other',
  ]) {
    testWidgets('$url stays outside native messages', (tester) async {
      final launched = watchBrowser(tester);
      final controller = await _pumpLink(
        tester,
        url: url,
        signedIn: true,
        messageGroupNames: const ['team'],
      );
      await tester.tap(find.text('Open link'));
      await tester.pumpAndSettle();
      expect(controller.currentContent?.isMessages, isFalse);
      expect(launched, [url]);
    });
  }

  for (final newTab in [false, true]) {
    testWidgets('opens the forum latest URL natively (new tab: $newTab)', (
      tester,
    ) async {
      final launched = watchBrowser(tester);
      final controller = await _pumpLink(
        tester,
        url: 'https://one.example/latest',
      );
      controller.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('Open link'),
        kind: PointerDeviceKind.mouse,
        buttons: newTab ? kMiddleMouseButton : kPrimaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(launched, isEmpty);
      if (newTab) {
        expect(controller.tabsForCurrentForum, hasLength(2));
        controller.selectTab(controller.tabsForCurrentForum.last.id);
        await tester.pumpAndSettle();
      }
      expect(controller.currentContent?.id, 'latest');
      expect(controller.currentFeedId, 'latest');
    });
  }

  for (final (path, id, feed) in <(String, String, String?)>[
    ('/top?period=weekly', 'top-weekly', '/top.json?period=weekly'),
    ('/top', 'top-yearly', '/top.json?period=yearly'),
    ('/new', 'new', '/new.json'),
    // Only a reader on the unified New list can ask for part of it.
    ('/new?subset=topics', 'new', '/new.json'),
    ('/unread?page=2', 'unread', '/unread.json'),
    ('/hot', 'hot', '/hot.json'),
    (
      '/latest?order=views',
      'topic-list-filter-/latest.json?order=views',
      '/latest.json?order=views',
    ),
    (
      '/top?period=monthly&order=views',
      'topic-list-filter-/top.json?order=views&period=monthly',
      '/top.json?order=views&period=monthly',
    ),
    (
      '/filter?q=in:bookmarked',
      'topic-list-filter-/filter.json?q=in%3Abookmarked',
      '/filter.json?q=in%3Abookmarked',
    ),
    ('/tags', 'all-tags', null),
  ]) {
    for (final newTab in [false, true]) {
      testWidgets('opens the forum $path list natively (new tab: $newTab)', (
        tester,
      ) async {
        final launched = watchBrowser(tester);
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': const [], ?feed: const []},
        );
        final controller = await _pumpLink(
          tester,
          url: 'https://one.example$path',
          signedIn: true,
          api: api,
        );
        controller.pushContent(ContentRoute.newTab());
        await tester.pumpAndSettle();

        await tester.tap(
          find.text('Open link'),
          kind: PointerDeviceKind.mouse,
          buttons: newTab ? kMiddleMouseButton : kPrimaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(launched, isEmpty);
        if (newTab) {
          expect(controller.tabsForCurrentForum, hasLength(2));
          controller.selectTab(controller.tabsForCurrentForum.last.id);
          await tester.pumpAndSettle();
        }
        expect(controller.currentContent?.id, id);
        if (feed != null) {
          expect(controller.currentFeedId, id);
          expect(api.feedPaths, contains(feed));
          expect(controller.currentFeed?.loaded, isTrue);
          expect(controller.currentFeed?.error, isNull);
        }
      });
    }
  }

  for (final newTab in [false, true]) {
    testWidgets(
      'a signed-out /unread link opens the browser (new tab: $newTab)',
      (tester) async {
        final launched = watchBrowser(tester);
        final controller = await _pumpLink(
          tester,
          url: 'https://one.example/unread',
        );

        await tester.tap(
          find.text('Open link'),
          kind: PointerDeviceKind.mouse,
          buttons: newTab ? kMiddleMouseButton : kPrimaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(launched, ['https://one.example/unread']);
        expect(controller.tabsForCurrentForum, hasLength(1));
        expect(controller.currentContent?.id, isNot('unread'));
      },
    );
  }

  testWidgets('a link to the list on screen does not stack it again', (
    tester,
  ) async {
    final launched = watchBrowser(tester);
    final controller = await _pumpLink(
      tester,
      url: 'https://one.example/top?period=weekly',
      api: FakeDiscourseApi(
        feeds: const {'/latest.json': [], '/top.json?period=weekly': []},
      ),
    );
    await tester.tap(find.text('Open link'));
    await tester.pumpAndSettle();
    final stack = controller.contentStack;
    expect(stack.last.id, 'top-weekly');

    await tester.tap(find.text('Open link'));
    await tester.pumpAndSettle();

    expect(launched, isEmpty);
    expect(controller.contentStack, stack);
  });

  for (final newTab in [false, true]) {
    testWidgets('opens the forum categories URL natively (new tab: $newTab)', (
      tester,
    ) async {
      final launched = watchBrowser(tester);
      final controller = await _pumpLink(
        tester,
        url: 'https://one.example/categories',
      );
      controller.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('Open link'),
        kind: PointerDeviceKind.mouse,
        buttons: newTab ? kMiddleMouseButton : kPrimaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(launched, isEmpty);
      if (newTab) {
        expect(controller.tabsForCurrentForum, hasLength(2));
        controller.selectTab(controller.tabsForCurrentForum.last.id);
        await tester.pumpAndSettle();
      }
      expect(controller.currentContent?.id, 'all-categories');
      expect(controller.categoryFeedFor('https://one.example').loaded, isTrue);
    });
  }

  testWidgets('primary click keeps navigation in the active tab', (
    tester,
  ) async {
    final controller = await _pumpLink(tester);
    final originalId = controller.activeTabId;

    await tester.tap(find.text('Open link'));
    await tester.pumpAndSettle();

    expect(controller.activeTabId, originalId);
    expect(controller.tabsForCurrentForum, hasLength(1));
    expect(controller.currentContent?.topicId, 42);
  });

  for (final newTab in [false, true]) {
    testWidgets('opens filtered category links natively (new tab: $newTab)', (
      tester,
    ) async {
      const feedPath = '/c/todo.json?status=open&assigned=nobody';
      final api = FakeDiscourseApi(
        feeds: const {
          '/latest.json': [],
          feedPath: [Topic(id: 7, title: 'Open task', slug: 'open-task')],
        },
      );
      final launched = watchBrowser(tester);
      final controller = await _pumpLink(
        tester,
        url: '/c/todo?status=open&assigned=nobody',
        api: api,
      );
      final originalId = controller.activeTabId;

      await tester.tap(
        find.text('Open link'),
        kind: PointerDeviceKind.mouse,
        buttons: newTab ? kMiddleMouseButton : kPrimaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(launched, isEmpty);
      expect(controller.activeTabId, originalId);
      expect(controller.tabsForCurrentForum, hasLength(newTab ? 2 : 1));
      if (newTab) {
        controller.selectTab(controller.tabsForCurrentForum.last.id);
        await tester.pumpAndSettle();
      }
      expect(controller.currentContent?.feedPath, feedPath);
      expect(controller.currentFeed?.topicIds, [7]);
      expect(api.feedPaths, ['/latest.json', feedPath]);
    });
  }

  testWidgets('middle-click falls back to the browser for an external URL', (
    tester,
  ) async {
    final launched = watchBrowser(tester);
    final controller = await _pumpLink(
      tester,
      url: 'https://other.example/page',
    );
    final original = controller.activeTab;

    await tester.tap(
      find.text('Open link'),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await tester.pumpAndSettle();

    expect(launched, ['https://other.example/page']);
    expect(controller.activeTab, original);
    expect(controller.tabsForCurrentForum, hasLength(1));
  });

  testWidgets('middle-click reports a full workspace without navigating', (
    tester,
  ) async {
    final launched = watchBrowser(tester);
    final controller = await _pumpLink(tester);
    for (var i = 1; i < ForumWorkspace.maximumTabs; i++) {
      controller.createTab();
    }
    final original = controller.activeTab;

    await tester.tap(
      find.text('Open link'),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await tester.pumpAndSettle();

    expect(controller.activeTab, original);
    expect(
      controller.tabsForCurrentForum,
      hasLength(ForumWorkspace.maximumTabs),
    );
    expect(launched, isEmpty);
    expect(find.text('Close a tab before opening another.'), findsOneWidget);
  });

  testWidgets('middle-button drags and cancelled clicks do not open links', (
    tester,
  ) async {
    final controller = await _pumpLink(tester);
    final position = tester.getCenter(find.text('Open link'));
    final gesture = await tester.startGesture(
      position,
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await gesture.moveBy(const Offset(100, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    final cancelled = await tester.startGesture(
      position,
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await cancelled.cancel();
    await tester.pumpAndSettle();

    expect(controller.tabsForCurrentForum, hasLength(1));
    expect(controller.currentContent?.topicId, isNull);
  });

  testWidgets('middle-click uses ordinary navigation when tabs are disabled', (
    tester,
  ) async {
    final controller = await _pumpLink(tester, tabsEnabled: false);

    await tester.tap(
      find.text('Open link'),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await tester.pumpAndSettle();

    expect(controller.tabsForCurrentForum, hasLength(1));
    expect(controller.currentContent?.topicId, 42);
  });

  testWidgets('middle-click opens a new tab in the active panel', (
    tester,
  ) async {
    final controller = await _pumpLink(tester, desktopPanels: true);
    final original = controller.activeTabId;
    final secondary = controller.selectedTabIn(ForumPanel.secondary);

    await tester.tap(
      find.text('Open link'),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await tester.pumpAndSettle();

    expect(controller.activeTabId, original);
    expect(controller.tabsForCurrentForum.last.panel, ForumPanel.main);
    expect(controller.selectedTabIn(ForumPanel.secondary), same(secondary));
    expect(controller.tabsForCurrentForum.last.currentContent.topicId, 42);
  });

  testWidgets('Shift-click opens in the secondary panel', (tester) async {
    final controller = await _pumpLink(tester, desktopPanels: true);
    final original = controller.activeTabId;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Open link'), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(controller.selectedTabIn(ForumPanel.main)?.id, original);
    expect(controller.activeTab?.panel, ForumPanel.secondary);
    expect(controller.currentContent?.topicId, 42);
  });

  testWidgets('Shift-middle-click opens a new secondary tab', (tester) async {
    final controller = await _pumpLink(tester, desktopPanels: true);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(
      find.text('Open link'),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(controller.activeTab?.panel, ForumPanel.main);
    expect(controller.tabsForCurrentForum, hasLength(3));
    expect(controller.tabsForCurrentForum.last.panel, ForumPanel.secondary);
    expect(controller.tabsForCurrentForum.last.currentContent.topicId, 42);
  });

  testWidgets('right-click offers explicit panel destinations', (tester) async {
    final controller = await _pumpLink(tester, desktopPanels: true);

    await tester.tap(
      find.text('Open link'),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Open in main panel'), findsOneWidget);
    expect(find.text('Open in secondary panel'), findsOneWidget);

    await tester.tap(find.text('Open in secondary panel'));
    await tester.pumpAndSettle();
    expect(controller.activeTab?.panel, ForumPanel.secondary);
    expect(controller.currentContent?.topicId, 42);
  });

  testWidgets('right-clicking another link closes the previous menu', (
    tester,
  ) async {
    final chosen = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              LinkTarget.action(
                action: ({required newTab, panel}) => chosen.add('first'),
                child: const Text('First link'),
              ),
              const SizedBox(height: 300),
              LinkTarget.action(
                action: ({required newTab, panel}) => chosen.add('second'),
                child: const Text('Second link'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(
      find.text('First link'),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Open in main panel'), findsOneWidget);

    await tester.tap(
      find.text('Second link'),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Open in main panel'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(chosen, ['second']);
  });
}

Future<ShellController> _pumpLink(
  WidgetTester tester, {
  String url = '/t/a-topic/42',
  String? bookmarkUrl,
  bool tabsEnabled = true,
  bool desktopPanels = false,
  bool signedIn = false,
  List<String> messageGroupNames = const [],
  FakeDiscourseApi? api,
}) async {
  final instances = [
    instance('one.example').copyWith(
      user: signedIn
          ? DiscourseUser(
              username: 'j.jaffeux',
              messageGroupNames: messageGroupNames,
            )
          : null,
    ),
  ];
  final site = api ?? FakeDiscourseApi(feeds: const {'/latest.json': []});
  final controller = ShellController(
    instanceStore: FakeInstanceStore(instances),
    api: site,
    authenticator: FakeAuthenticator.signedIn(instances, site: site),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    forumTabsEnabled: tabsEnabled,
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  controller.desktopTopicTabs = desktopPanels;
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        builder: (context, child) => DToaster(child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: LinkTarget(
                url: url,
                bookmarkUrl: bookmarkUrl,
                child: TextButton(
                  onPressed: () => openLink(context, url),
                  child: const Text('Open link'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

final class _LinkBookmarkApi extends FakeDiscourseApi {
  _LinkBookmarkApi() : super(topics: {42: _payload()});

  static TopicPayload _payload([Bookmark? bookmark]) => topicPayload(
    id: 42,
    posts: [
      Post(
        id: 99,
        postNumber: 3,
        username: 'author',
        cooked: '<p>Clicked</p>',
        bookmark: bookmark?.coreTargetType == BookmarkTargetType.post
            ? bookmark
            : null,
      ),
    ],
    bookmarks: [?bookmark],
  );

  @override
  Future<int> createBookmark({
    required String siteUrl,
    required String apiKey,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
    String? clientId,
  }) async {
    final id = await super.createBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      targetType: targetType,
      targetId: targetId,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
      clientId: clientId,
    );
    topics[42] = _payload(
      Bookmark(
        id: id,
        bookmarkableId: targetId,
        bookmarkableType: targetType.wireName,
        postNumber: 3,
      ),
    );
    return id;
  }

  @override
  Future<bool?> deleteBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    required BookmarkTargetType targetType,
    String? clientId,
  }) async {
    await super.deleteBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      bookmarkId: bookmarkId,
      targetType: targetType,
      clientId: clientId,
    );
    topics[42] = _payload();
    return false;
  }
}
