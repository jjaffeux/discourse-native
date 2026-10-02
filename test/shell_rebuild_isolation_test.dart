import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/hover_panel.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/post_likes.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_create_button.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

void main() {
  testWidgets('navigation does not rebuild account and sidebar chrome', (
    tester,
  ) async {
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org', title: 'Meta'),
      ]),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    var broadBuilds = 0;
    const broadKey = ValueKey('broad-shell-dependent');
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Row(
              children: [
                const SizedBox(width: 240, child: InstanceSidebar()),
                const UserMenuButton(),
                const SizedBox(
                  width: 300,
                  height: 480,
                  child: UserMenuPanel(onDismiss: _noop),
                ),
                Builder(
                  key: broadKey,
                  builder: (context) {
                    ShellScope.of(context);
                    broadBuilds++;
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final sidebar = tester.element(find.byType(InstanceSidebar));
    final avatar = tester.element(find.byType(UserMenuButton));
    final panel = tester.element(find.byType(UserMenuPanel));
    final sidebarSelector = find
        .descendant(
          of: find.byType(InstanceSidebar),
          matching: find.byWidgetPredicate((widget) => widget is ShellSelector),
        )
        .evaluate()
        .first;
    final avatarSelector = _onlyChild(avatar);
    final panelSelector = _onlyChild(panel);
    final broadDependent = tester.element(find.byKey(broadKey));
    final rebuilt = <Element>{};
    final previousRebuildCallback = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      rebuilt.add(element);
      previousRebuildCallback?.call(element, builtOnce);
    };
    addTearDown(() {
      debugOnRebuildDirtyWidget = previousRebuildCallback;
    });

    controller.pushContent(
      const ContentRoute(
        id: 'unrelated',
        title: 'Unrelated route',
        icon: DIcons.comments,
      ),
    );
    await tester.pump();

    expect(rebuilt, contains(broadDependent));
    for (final isolated in [
      sidebar,
      sidebarSelector,
      avatar,
      avatarSelector,
      panel,
      panelSelector,
    ]) {
      expect(rebuilt, isNot(contains(isolated)));
    }
    expect(broadBuilds, 2);

    rebuilt.clear();
    await controller.addInstance(
      instance('discuss.example.com', title: 'Second site'),
    );
    await tester.pump();

    expect(
      rebuilt,
      containsAll([sidebarSelector, avatarSelector, panelSelector]),
    );
    expect(find.text('Second site'), findsOneWidget);
  });

  testWidgets('unrelated shell changes do not rebuild the topic viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org', title: 'Meta'),
      ]),
      api: FakeDiscourseApi(
        feeds: const {
          '/latest.json': [
            Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
          ],
        },
      ),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: const AdaptiveShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_realTopicTitle, findsOneWidget);

    final rail = tester.element(find.byType(InstanceRail));
    final content = tester.element(primaryMainContent);
    final list = tester.element(find.byType(TopicListView));
    final rowTitle = tester.element(_realTopicTitle);
    final railSelector = _onlyChild(rail);
    final contentSelector = _onlyChild(content);
    final listSelector = _onlyChild(list);
    final rebuilt = <Element>{};
    final previousRebuildCallback = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      rebuilt.add(element);
      previousRebuildCallback?.call(element, builtOnce);
    };
    addTearDown(() {
      debugOnRebuildDirtyWidget = previousRebuildCallback;
    });

    controller.selectInstance(0);
    await tester.pump();

    for (final isolated in [
      rail,
      railSelector,
      content,
      contentSelector,
      list,
      listSelector,
      rowTitle,
    ]) {
      expect(rebuilt, isNot(contains(isolated)));
    }
  });

  testWidgets(
    'pagination updates the feed without rebuilding unrelated shell chrome',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final site = instance('meta.discourse.org', title: 'Meta');
      final pageGate = Completer<void>();
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': _topics(1, 40),
          '/latest.json?page=1': _topics(41, 1),
        },
        nextPages: const {'/latest.json': '/latest?page=1'},
        creatableFeedPaths: const {'/latest.json'},
        feedGates: {'/latest.json?page=1': pageGate},
      );
      final controller = ShellController(
        instanceStore: FakeInstanceStore([site]),
        api: api,
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      for (
        var attempt = 0;
        attempt < 20 &&
            (controller.currentFeed?.loaded != true ||
                !controller.categoryFeedFor(site.url).loaded);
        attempt++
      ) {
        await tester.pump();
      }
      expect(controller.currentFeed?.loaded, isTrue);
      expect(controller.categoryFeedFor(site.url).loaded, isTrue);
      var shellNotifications = 0;
      void countShellNotification() => shellNotifications++;
      controller.addListener(countShellNotification);
      addTearDown(() => controller.removeListener(countShellNotification));

      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: const AdaptiveShell(),
          ),
        ),
      );

      // Finish initial layout before measuring the notifications caused by
      // pagination.
      await tester.pumpAndSettle();
      shellNotifications = 0;
      expect(find.byType(TopicCreateButton), findsOneWidget);

      final rail = tester.element(find.byType(InstanceRail));
      final sidebar = tester.element(find.byType(InstanceSidebar));
      final content = tester.element(primaryMainContent);
      final contentSelector = _onlyChild(content);
      final tabBar = tester.element(_forumTabsBar);
      final createAction = tester.element(find.byType(TopicCreateButton));
      final list = tester.element(find.byType(TopicListView));
      final rebuilds = <Element, int>{};
      final previousRebuildCallback = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        rebuilds.update(element, (count) => count + 1, ifAbsent: () => 1);
        previousRebuildCallback?.call(element, builtOnce);
      };
      addTearDown(() {
        debugOnRebuildDirtyWidget = previousRebuildCallback;
      });

      final paging = controller.currentFeed!.loadingMore
          ? null
          : controller.loadMoreFeed('latest');
      for (
        var attempt = 0;
        attempt < 20 && !api.feedPaths.contains('/latest.json?page=1');
        attempt++
      ) {
        await tester.pump();
      }
      await tester.pump();

      expect(api.feedPaths, contains('/latest.json?page=1'));
      expect(controller.currentFeed?.loadingMore, isTrue);
      expect(
        tester
            .widget<TopicListView>(find.byType(TopicListView))
            .feed
            .loadingMore,
        isTrue,
      );
      expect(shellNotifications, 0);
      for (final chrome in [
        rail,
        sidebar,
        content,
        contentSelector,
        tabBar,
        createAction,
      ]) {
        expect(rebuilds[chrome] ?? 0, 0, reason: chrome.toString());
      }
      expect(rebuilds[list] ?? 0, greaterThan(0));

      rebuilds.clear();
      pageGate.complete();
      await paging;
      for (
        var attempt = 0;
        attempt < 20 && controller.currentFeed?.loadingMore == true;
        attempt++
      ) {
        await tester.pump();
      }
      await tester.pump();

      expect(controller.currentFeed?.topicIds.last, 41);
      final renderedFeed = tester
          .widget<TopicListView>(find.byType(TopicListView))
          .feed;
      expect(renderedFeed.topicIds.last, 41);
      expect(renderedFeed.loadingMore, isFalse);
      expect(shellNotifications, 0);
      for (final chrome in [
        rail,
        sidebar,
        content,
        contentSelector,
        tabBar,
        createAction,
      ]) {
        expect(rebuilds[chrome] ?? 0, 0, reason: chrome.toString());
      }
      expect(rebuilds[list] ?? 0, greaterThan(0));
    },
  );

  testWidgets('reader bounds reports do not notify the shell facade', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org', title: 'Meta'),
      ]),
      api: FakeDiscourseApi(
        feeds: const {
          '/latest.json': [
            Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
          ],
        },
      ),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: const AdaptiveShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_realTopicTitle, findsOneWidget);

    var shellNotifications = 0;
    void countShellNotification() => shellNotifications++;
    controller.addListener(countShellNotification);
    addTearDown(() => controller.removeListener(countShellNotification));
    var boundsNotifications = 0;
    void countBoundsNotification() => boundsNotifications++;
    controller.readerContentBoundsListenable.addListener(
      countBoundsNotification,
    );
    addTearDown(
      () => controller.readerContentBoundsListenable.removeListener(
        countBoundsNotification,
      ),
    );

    // A docked composer's reader reports a new rect after every frame of a
    // dock drag, so each distinct report must stay off the facade.
    for (var frame = 1; frame <= 5; frame++) {
      final bounds = Rect.fromLTWH(0, 0, 800, 600 - frame * 10);
      controller.reportReaderContentBounds(bounds);
      await tester.pump();
      expect(controller.readerContentBounds, bounds);
    }
    expect(boundsNotifications, 5);
    expect(shellNotifications, 0);

    // A desktop window resize moves the reader through the mounted reporter.
    final beforeResize = controller.readerContentBounds;
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    await tester.pumpAndSettle();
    expect(controller.readerContentBounds, isNot(beforeResize));
    expect(boundsNotifications, greaterThan(5));
    expect(shellNotifications, 0);
  });

  testWidgets('sitewide user status events do not notify the shell facade', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const siteUrl = 'https://meta.discourse.org';
    const user = DiscourseUser(id: 7, username: 'reader');
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org', title: 'Meta').copyWith(
          user: user,
          config: const SiteConfig(userStatusEnabled: true),
        ),
      ]),
      api: FakeDiscourseApi(
        user: user,
        feeds: const {
          '/latest.json': [
            Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
          ],
        },
        siteConfigs: const {siteUrl: SiteConfig(userStatusEnabled: true)},
      ),
      authenticator: FakeAuthenticator()..keys[siteUrl] = 'key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: const AdaptiveShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_realTopicTitle, findsOneWidget);
    final tracker = FakeSiteTracker.built.single;
    expect(tracker.pluginChannelCallbacks['/user-status'], hasLength(1));

    var shellNotifications = 0;
    void countShellNotification() => shellNotifications++;
    controller.addListener(countShellNotification);
    addTearDown(() => controller.removeListener(countShellNotification));
    final rebuilt = <Element>{};
    final previousRebuildCallback = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      rebuilt.add(element);
      previousRebuildCallback?.call(element, builtOnce);
    };
    addTearDown(() {
      debugOnRebuildDirtyWidget = previousRebuildCallback;
    });

    // Every account on the site publishes here when it sets or clears a
    // status; none of these people is on screen.
    for (var userId = 100; userId < 110; userId++) {
      tracker.deliverPluginMessage('/user-status', {
        '$userId': {'description': 'Status $userId', 'emoji': 'house'},
      });
      await tester.pump();
    }
    tracker.deliverPluginMessage('/user-status', const {'100': null});
    await tester.pump();

    expect(
      controller.userStatuses.statusFor(
        siteUrl,
        100,
        const UserStatus(description: 'Snapshot', emoji: 'clock1'),
      ),
      isNull,
    );
    expect(
      controller.userStatuses.statusFor(siteUrl, 109, null)?.description,
      'Status 109',
    );
    expect(shellNotifications, 0);
    expect(rebuilt, isEmpty);
  });

  testWidgets('profile and likers previews do not notify the shell facade', (
    tester,
  ) async {
    const siteUrl = 'https://meta.discourse.org';
    final api = _PreviewApi();
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org', title: 'Meta'),
      ]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    var broadBuilds = 0;
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const UserCardTarget(
                    username: 'sam',
                    siteUrl: siteUrl,
                    child: Text('Open Sam'),
                  ),
                  const PostLikes(
                    siteUrl: siteUrl,
                    post: Post(
                      id: 1,
                      postNumber: 1,
                      username: 'author',
                      cooked: '<p>Post body</p>',
                      likeCount: 1,
                      canLike: false,
                      canUnlike: false,
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      ShellScope.of(context);
                      broadBuilds++;
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var shellNotifications = 0;
    void countShellNotification() => shellNotifications++;
    controller.addListener(countShellNotification);
    addTearDown(() => controller.removeListener(countShellNotification));
    final settledBuilds = broadBuilds;
    const away = Offset(700, 500);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: away);

    // Every hover-open of a like count fetches its likers again.
    for (final name in ['Alex Liker', 'Blair Liker']) {
      await mouse.moveTo(tester.getCenter(find.text('1')));
      await tester.pump(HoverPanel.openDelay);
      await tester.pump();
      api.likerResponses.last.complete(
        PostLikers(
          postId: 1,
          likers: [PostLiker(id: 2, username: 'liker', name: name)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(name), findsOneWidget);
      await mouse.moveTo(away);
      await tester.pump(HoverPanel.closeDelay);
      await tester.pumpAndSettle();
      expect(find.text(name), findsNothing);
    }
    expect(api.likerResponses, hasLength(2));

    // Each newly hovered name loads its card, and a failed one loads again on
    // the next hover.
    Future<void> hoverSam() async {
      await mouse.moveTo(tester.getCenter(find.text('Open Sam')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
    }

    await hoverSam();
    api.cardResponses.single.completeError(StateError('Unavailable'));
    await tester.pump();
    expect(find.text("Couldn't load @sam."), findsOneWidget);
    await mouse.moveTo(away);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load @sam."), findsNothing);

    await hoverSam();
    expect(find.text("Couldn't load @sam."), findsNothing);
    api.cardResponses.last.complete(
      const UserCard(username: 'sam', name: 'Sam Example'),
    );
    await tester.pump();
    expect(find.text('Sam Example'), findsOneWidget);
    expect(api.cardResponses, hasLength(2));
    expect(shellNotifications, 0);
    expect(broadBuilds, settledBuilds);

    // An open card redraws for its own user, not for unrelated shell changes.
    for (final open in [false, true]) {
      if (open) {
        await tester.tap(find.text('Open Sam'));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.byKey(const ValueKey('user-card-surface')), findsOneWidget);
      }
      final card = tester.element(find.text('Sam Example'));
      final rebuilt = <Element>{};
      final previousRebuildCallback = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        rebuilt.add(element);
        previousRebuildCallback?.call(element, builtOnce);
      };
      try {
        controller.pushContent(
          ContentRoute(
            id: 'unrelated-$open',
            title: 'Unrelated route',
            icon: DIcons.comments,
          ),
        );
        await tester.pump();
      } finally {
        debugOnRebuildDirtyWidget = previousRebuildCallback;
      }
      expect(broadBuilds, greaterThan(settledBuilds));
      expect(rebuilt, isNot(contains(card)));
    }
    expect(api.cardResponses, hasLength(2));
  });

  testWidgets(
    'closing an inactive tab updates the bar without rebuilding the viewport',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org', title: 'Meta'),
        ]),
        api: FakeDiscourseApi(
          feeds: const {
            '/latest.json': [
              Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
            ],
          },
        ),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: const AdaptiveShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inactiveTabId = controller.activeTabId!;
      _createTopicsTab(controller);
      await tester.pumpAndSettle();

      final activeTabId = controller.activeTabId!;
      expect(activeTabId, isNot(inactiveTabId));
      expect(
        tester.widget<ForumTabsBar>(_forumTabsBar).items.map((item) => item.id),
        [inactiveTabId, activeTabId],
      );

      final bar = tester.element(_forumTabsBar);
      final viewport = tester.element(find.byType(TopicListView));
      final viewportSelector = _onlyChild(viewport);
      final rowTitle = tester.element(_realTopicTitle);
      final rebuilt = <Element>{};
      final previousRebuildCallback = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        rebuilt.add(element);
        previousRebuildCallback?.call(element, builtOnce);
      };
      addTearDown(() {
        debugOnRebuildDirtyWidget = previousRebuildCallback;
      });

      controller.closeTab(inactiveTabId);
      await tester.pump();

      expect(controller.activeTabId, activeTabId);
      expect(
        tester.widget<ForumTabsBar>(_forumTabsBar).items.map((item) => item.id),
        [activeTabId],
      );
      expect(find.byKey(ValueKey('forum-tab-$inactiveTabId')), findsNothing);
      expect(rebuilt, contains(bar));
      for (final isolated in [viewport, viewportSelector, rowTitle]) {
        expect(rebuilt, isNot(contains(isolated)));
      }
      expect(tester.element(find.byType(TopicListView)), same(viewport));
    },
  );

  testWidgets('same-route tab switches remount only the active viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org', title: 'Meta'),
      ]),
      api: FakeDiscourseApi(
        feeds: const {
          '/latest.json': [
            Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
          ],
        },
      ),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: const AdaptiveShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstTabId = controller.activeTabId!;
    final firstViewport = tester.element(find.byType(TopicListView));

    _createTopicsTab(controller);
    await tester.pumpAndSettle();

    expect(find.byType(TopicListView), findsOneWidget);
    final secondViewport = tester.element(find.byType(TopicListView));
    expect(secondViewport, isNot(same(firstViewport)));

    controller.selectTab(firstTabId);
    await tester.pumpAndSettle();

    expect(find.byType(TopicListView), findsOneWidget);
    expect(
      tester.element(find.byType(TopicListView)),
      isNot(same(secondViewport)),
    );
  });

  group('a chat message in a followed channel', () {
    const site = 'https://meta.discourse.org';
    final chatTab = find.byKey(const ValueKey('sidebar-panel-switch-chat'));
    Finder inChatTab(String text) =>
        find.descendant(of: chatTab, matching: find.text(text));
    Finder row(int channelId) =>
        find.byKey(ValueKey('chat-inbox-channel-$channelId'));

    Future<void> pumpChatSidebar(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      const reader = DiscourseUser(id: 7, username: 'reader');
      final config = SiteConfig(
        plugins: PluginData.none.withValue(
          chatSettingsDataKey,
          const ChatSettings(chatEnabled: true, publicChannelsEnabled: true),
        ),
      );
      await pumpShell(
        tester,
        desktop,
        pluginManifest: PluginManifest([
          ChatModule(apiFactory: (transport) => transport as ChatApi),
        ]),
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Meta',
          ).copyWith(user: reader, config: config),
        ],
        authenticator: FakeAuthenticator()..keys[site] = 'key',
        api: FakeDiscourseApi(
          user: reader,
          totals: chatNotificationTotals(available: true),
          feeds: const {'/latest.json': []},
          siteConfigs: {site: config},
          chatChannelsBySite: {
            site: ChatChannels(
              public: [
                // Channel 3 has the latest activity, so it leads the inbox.
                for (var id = 1; id <= 3; id++)
                  ChatChannel(
                    id: id,
                    title: 'Channel $id',
                    kind: ChatChannelKind.category,
                    membership: const ChatMembership(following: true),
                    lastMessageId: id,
                    lastMessageAt: DateTime.utc(2026, 8, 1, 9, id),
                  ),
              ],
              newMessageBusLastIds: const {1: 1, 2: 1, 3: 1},
              newMentionMessageBusLastIds: const {1: 1, 2: 1, 3: 1},
            ),
          },
        ),
      );
      await ShellScope.read(
        tester.element(find.byType(InstanceSidebar)),
      ).pluginSession.require(chatControllerService).loadChannels(site);
      await tester.pumpAndSettle();
    }

    void deliver(String channel, Map<String, Object?> data, int messageId) =>
        FakeSiteTracker.built
            .lastWhere((tracker) => tracker.siteUrl == site)
            .deliverPluginMessage(channel, data, messageId: messageId);

    void message(int channelId, int messageId, {required int minute}) =>
        deliver('/chat/$channelId/new-messages', {
          'type': 'channel',
          'channel_id': channelId,
          'message': {
            'id': messageId,
            'chat_channel_id': channelId,
            'cooked': '<p>new</p>',
            'created_at': DateTime.utc(
              2026,
              8,
              1,
              10,
              minute,
            ).toIso8601String(),
            'user': {'id': 2, 'username': 'sam'},
          },
        }, messageId);

    // Each rebuilt element, and the inbox row it draws part of, read while
    // the element is still mounted.
    ({List<Element> elements, Set<int> rows}) recordRebuilds() {
      final rebuilt = (elements: <Element>[], rows: <int>{});
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        rebuilt.elements.add(element);
        if (element.widget case ChatInboxRow(:final channel)) {
          rebuilt.rows.add(channel.id);
          return;
        }
        element.visitAncestorElements((ancestor) {
          if (ancestor.widget case ChatInboxRow(:final channel)) {
            rebuilt.rows.add(channel.id);
            return false;
          }
          return true;
        });
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      return rebuilt;
    }

    testWidgets('redraws the Chat tab badge but not the Forum sections', (
      tester,
    ) async {
      await pumpChatSidebar(tester);
      expect(find.byType(SidebarDestinationTile), findsWidgets);
      expect(inChatTab('1'), findsNothing);
      final rebuilt = recordRebuilds();

      message(3, 101, minute: 0);
      await tester.pump();

      expect(inChatTab('1'), findsOneWidget);
      expect(
        rebuilt.elements.where(
          (element) => element.widget is SidebarDestinationTile,
        ),
        isEmpty,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('redraws only its own row in the Chat inbox', (tester) async {
      await pumpChatSidebar(tester);
      await tester.tap(chatTab);
      await tester.pumpAndSettle();
      List<double> tops(List<int> channelIds) => [
        for (final id in channelIds) tester.getTopLeft(row(id)).dy,
      ];
      final initial = tops([3, 2, 1]);
      expect(initial, orderedEquals([...initial]..sort()));
      final rebuilt = recordRebuilds();

      // Channel 3 already leads, so the order stands.
      message(3, 101, minute: 0);
      await tester.pump();
      expect(rebuilt.rows, {3});
      expect(inChatTab('1'), findsOneWidget);
      expect(
        find.descendant(of: row(3), matching: find.text('1 message')),
        findsOneWidget,
      );

      rebuilt.rows.clear();
      deliver('/chat/2/new-mentions', {'channel_id': 2, 'message_id': 2}, 2);
      await tester.pump();
      expect(rebuilt.rows, {2});
      expect(
        find.descendant(of: row(2), matching: find.text('1 new mention')),
        findsOneWidget,
      );

      rebuilt.rows.clear();
      message(1, 102, minute: 1);
      await tester.pump();
      expect(rebuilt.rows, {1});
      expect(inChatTab('2'), findsOneWidget);
      final reordered = tops([1, 3, 2]);
      expect(reordered, orderedEquals([...reordered]..sort()));
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });
}

void _noop() {}

// A new tab opens on the Start page; these tests compare two topic lists.
void _createTopicsTab(ShellController controller) {
  controller.createTab();
  controller.selectDestination(controller.currentInstance!.defaultDestination);
}

Element _onlyChild(Element parent) {
  final children = <Element>[];
  parent.visitChildren(children.add);
  expect(children, hasLength(1));
  return children.single;
}

final class _PreviewApi extends FakeDiscourseApi {
  final cardResponses = <Completer<UserCard>>[];
  final likerResponses = <Completer<PostLikers>>[];

  @override
  Future<UserCard> userCard({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  }) {
    final response = Completer<UserCard>();
    cardResponses.add(response);
    return response.future;
  }

  @override
  Future<PostLikers> postLikers({
    required String siteUrl,
    required int postId,
    int limit = 25,
    String? apiKey,
    String? clientId,
  }) {
    final response = Completer<PostLikers>();
    likerResponses.add(response);
    return response.future;
  }
}

List<Topic> _topics(int first, int count) => [
  for (var id = first; id < first + count; id++)
    Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
];

Finder get _realTopicTitle => find.descendant(
  of: find.byType(TopicListView),
  matching: find.text('A real topic'),
);

Finder get _forumTabsBar => find.descendant(
  of: find.byWidgetPredicate(
    (widget) =>
        widget is CurrentForumTabsBar && widget.panel != ForumPanel.secondary,
  ),
  matching: find.byType(ForumTabsBar),
);
