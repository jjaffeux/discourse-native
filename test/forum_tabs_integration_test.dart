import 'dart:async';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _compact = Size(390, 844);
const _medium = Size(1000, 800);
const _expanded = Size(1440, 900);
const _tabShortcutKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

void main() {
  testWidgets(
    'number shortcuts map directly to the first nine ordered tabs',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      for (var index = 1; index < _tabShortcutKeys.length; index++) {
        controller.createTab();
      }
      await tester.pumpAndSettle();

      final tabIds = [for (final tab in controller.tabsForCurrentForum) tab.id];
      expect(tabIds, hasLength(_tabShortcutKeys.length));

      for (var index = 0; index < _tabShortcutKeys.length; index++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        expect(await tester.sendKeyEvent(_tabShortcutKeys[index]), isTrue);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        expect(controller.activeTabId, tabIds[index]);
        expect(_bar(tester).selectedId, tabIds[index]);
      }
    }),
  );

  for (final platform in const [
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      '${platform.name} switches to a numbered tab with its primary shortcut',
      (tester) => _withPlatform(platform, () async {
        await _pumpShell(tester);
        final controller = ShellScope.read(
          tester.element(find.byType(MainContent)),
        );
        controller.createTab();
        controller.createTab();
        await tester.pump();

        final tabIds = [
          for (final tab in controller.tabsForCurrentForum) tab.id,
        ];
        expect(controller.activeTabId, tabIds[2]);

        expect(await tester.sendKeyEvent(LogicalKeyboardKey.digit2), isFalse);
        expect(controller.activeTabId, tabIds[2]);

        final modifier = platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.digit2), isTrue);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();

        expect(controller.activeTabId, tabIds[1]);
        expect(_bar(tester).selectedId, tabIds[1]);

        await tester.sendKeyDownEvent(modifier);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.digit4), isFalse);
        await tester.sendKeyUpEvent(modifier);
        expect(controller.activeTabId, tabIds[1]);

        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.digit1), isFalse);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(modifier);
        expect(controller.activeTabId, tabIds[1]);
      }),
    );
  }

  testWidgets(
    'maps current routes and delegates tab lifecycle actions',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      final originalId = controller.activeTabId!;

      expect(find.byType(ForumTabsBar), findsOneWidget);
      expect(_bar(tester).forumName, 'One');
      expect(_bar(tester).items.single.title, 'Topics');
      expect(_bar(tester).selectedId, originalId);

      await tester.tap(find.byKey(const ValueKey('forum-tabs-add')));
      await tester.pumpAndSettle();

      final newId = controller.activeTabId!;
      expect(newId, isNot(originalId));
      expect(_bar(tester).items, hasLength(2));
      expect(_bar(tester).selectedId, newId);

      const color = Color(0xFF0088CC);
      controller.pushContent(
        ContentRoute.topic(
          topicId: 42,
          slug: 'native-tabs',
          title: 'Native tabs',
          color: color,
        ),
      );
      await tester.pumpAndSettle();

      final ForumTabItem routedItem = _bar(
        tester,
      ).items.singleWhere((item) => item.id == newId);
      expect(routedItem.title, 'Native tabs');
      expect(routedItem.icon, DIcons.comments);
      expect(routedItem.color, color);

      await tester.tap(find.byKey(ValueKey('forum-tab-$originalId')));
      await tester.pumpAndSettle();
      expect(controller.activeTabId, originalId);
      expect(_bar(tester).selectedId, originalId);

      await tester.tap(find.byKey(ValueKey('forum-tab-close-$originalId')));
      await tester.pumpAndSettle();
      expect(controller.tabsForCurrentForum.map((tab) => tab.id), [newId]);
      expect(_bar(tester).items.single.id, newId);
      expect(_bar(tester).selectedId, newId);
    }),
  );

  testWidgets(
    'shows only the selected forum workspace and restores each one',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester, twoForums: true);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );

      controller.createTab();
      await tester.pumpAndSettle();
      final firstForumIds = [for (final item in _bar(tester).items) item.id];
      final firstForumActive = _bar(tester).selectedId;
      expect(_bar(tester).forumName, 'One');
      expect(firstForumIds, hasLength(2));

      controller.selectInstance(1);
      await tester.pumpAndSettle();

      expect(_bar(tester).forumName, 'Two');
      expect(_bar(tester).items, hasLength(1));
      expect(firstForumIds, isNot(contains(_bar(tester).items.single.id)));

      controller.createTab();
      await tester.pumpAndSettle();
      final secondForumIds = [for (final item in _bar(tester).items) item.id];
      final secondForumActive = _bar(tester).selectedId;
      expect(secondForumIds, hasLength(2));
      expect(secondForumIds, everyElement(isNot(isIn(firstForumIds))));

      controller.selectInstance(0);
      await tester.pumpAndSettle();

      expect(_bar(tester).forumName, 'One');
      expect([for (final item in _bar(tester).items) item.id], firstForumIds);
      expect(_bar(tester).selectedId, firstForumActive);

      controller.selectInstance(1);
      await tester.pumpAndSettle();

      expect(_bar(tester).forumName, 'Two');
      expect([for (final item in _bar(tester).items) item.id], secondForumIds);
      expect(_bar(tester).selectedId, secondForumActive);
    }),
  );

  testWidgets(
    'activates and renders an existing tab before its feed finishes',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
      const siteUrl = 'https://one.example';
      const firstTabId = 'tab-latest';
      const slowTabId = 'tab-slow';
      const latestRoute = ContentRoute(
        id: 'latest',
        title: 'Topics',
        icon: DIcons.layerGroup,
      );
      const slowRoute = ContentRoute(
        id: 'slow-list',
        title: 'Slow destination',
        icon: DIcons.folder,
        feedPath: '/slow.json',
      );
      final workspace = ForumWorkspace(
        siteUrl: siteUrl,
        accountIdentity: 'anonymous',
        tabs: [
          ForumTab(
            id: firstTabId,
            rootDestinationId: latestRoute.id,
            contentStack: const [latestRoute],
          ),
          ForumTab(
            id: slowTabId,
            rootDestinationId: slowRoute.id,
            contentStack: const [slowRoute],
          ),
        ],
        activeTabId: firstTabId,
      );
      final releaseSlowFeed = Completer<void>();
      final slowFeedStarted = Completer<void>();
      addTearDown(() {
        if (!releaseSlowFeed.isCompleted) releaseSlowFeed.complete();
      });
      final api = _PathGatedApi(
        heldPath: slowRoute.feedPath!,
        release: releaseSlowFeed,
        started: slowFeedStarted,
        feeds: const {'/latest.json': [], '/slow.json': []},
      );
      final tabStore = FakeForumTabStore([workspace]);

      await _pumpShell(tester, api: api, forumTabs: tabStore);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      final originalViewportKey = ValueKey<(String?, String?, String, int?)>((
        siteUrl,
        firstTabId,
        latestRoute.id,
        null,
      ));
      final slowViewportKey = ValueKey<(String?, String?, String, int?)>((
        siteUrl,
        slowTabId,
        slowRoute.id,
        null,
      ));

      expect(controller.activeTabId, firstTabId);
      expect(find.byKey(originalViewportKey), findsOneWidget);
      expect(slowFeedStarted.isCompleted, isFalse);

      final savesBeforeRapidSwitch = tabStore.saveCount;
      controller.selectTab(slowTabId);
      controller.selectTab(firstTabId);
      expect(controller.activeTabId, firstTabId);
      await tester.pump();
      expect(tabStore.saveCount, savesBeforeRapidSwitch + 1);
      expect(slowFeedStarted.isCompleted, isFalse);

      final savesBeforeTap = tabStore.saveCount;
      var paintedBeforeBackgroundWork = false;
      tester.binding.addPostFrameCallback((_) {
        paintedBeforeBackgroundWork = true;
        expect(_bar(tester).selectedId, slowTabId);
        expect(
          find.byKey(const ValueKey('forum-tab-indicator-tab-slow')),
          findsOneWidget,
        );
        expect(find.byKey(originalViewportKey), findsNothing);
        expect(find.byKey(slowViewportKey), findsOneWidget);
        expect(slowFeedStarted.isCompleted, isFalse);
        expect(tabStore.saveCount, savesBeforeTap);
      });

      await tester.tap(find.byKey(const ValueKey('forum-tab-tab-slow')));

      // Gesture activation mutates navigation state synchronously. Neither a
      // frame nor the destination's response is required for this state move.
      expect(controller.activeTabId, slowTabId);
      expect(releaseSlowFeed.isCompleted, isFalse);
      expect(tabStore.saveCount, savesBeforeTap);

      // Paint the optimistic switch once. `pumpAndSettle` here would wait
      // through tab reveal and hide a regression tied to async hydration.
      await tester.pump();

      expect(paintedBeforeBackgroundWork, isTrue);
      expect(slowFeedStarted.isCompleted, isTrue);
      expect(releaseSlowFeed.isCompleted, isFalse);
      expect(tabStore.saveCount, savesBeforeTap + 1);
      expect(_bar(tester).selectedId, slowTabId);
      expect(
        find.byKey(const ValueKey('forum-tab-indicator-tab-slow')),
        findsOneWidget,
      );
      expect(find.byKey(originalViewportKey), findsNothing);
      expect(find.byKey(slowViewportKey), findsOneWidget);
      final slowContentText = _contentTextOutsideTabs('Slow destination');
      expect(slowContentText, findsWidgets);
      expect(
        tester.getCenter(slowContentText.first).dy,
        lessThan(tester.getTopLeft(find.byKey(slowViewportKey)).dy),
      );

      releaseSlowFeed.complete();
      await tester.pumpAndSettle();
    }),
  );

  testWidgets(
    'keeps tab presentation out of InstanceSidebar',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester);

      expect(_inSidebar(find.byType(ForumTabsBar)), findsNothing);
      expect(_inSidebar(find.text('OPEN')), findsNothing);
      expect(_inMainContent(find.byType(ForumTabsBar)), findsOneWidget);
    }),
  );

  for (final platform in const [
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      '${platform.name} shows forum tabs in main content at every width',
      (tester) => _withPlatform(platform, () async {
        for (final size in const [_compact, _medium, _expanded]) {
          await _pumpShell(
            tester,
            size: size,
            key: ValueKey('${platform.name}-${size.width}'),
          );

          expect(_inSidebar(find.byType(ForumTabsBar)), findsNothing);
          expect(_inSidebar(find.text('OPEN')), findsNothing);

          if (size == _compact) {
            expect(find.byType(MainContent), findsNothing);
            expect(find.byType(ForumTabsBar), findsNothing);

            await tester.tap(_sidebarText('Topics'));
            await tester.pumpAndSettle();

            expect(find.byType(InstanceSidebar), findsNothing);
            expect(find.byType(MainContent), findsOneWidget);
          }

          expect(_inMainContent(find.byType(ForumTabsBar)), findsOneWidget);
          expect(find.byType(CurrentForumTabsBar), findsOneWidget);
          expect(find.byKey(const ValueKey('forum-tabs-add')), findsOneWidget);
          expect(_bar(tester).items.single.title, 'Topics');
        }
      }),
    );
  }

  for (final platform in const [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      '${platform.name} omits the forum-tab subtree at every width',
      (tester) => _withPlatform(platform, () async {
        for (final size in const [_compact, _medium, _expanded]) {
          await _pumpShell(
            tester,
            size: size,
            key: ValueKey('${platform.name}-${size.width}'),
          );

          expect(_inSidebar(find.text('OPEN')), findsNothing);

          if (size == _compact) {
            expect(find.byType(MainContent), findsNothing);
            await tester.tap(_sidebarText('Topics'));
            await tester.pumpAndSettle();
            expect(find.byType(MainContent), findsOneWidget);
          }

          expect(
            find.byType(CurrentForumTabsBar, skipOffstage: false),
            findsNothing,
          );
          expect(find.byType(ForumTabsBar, skipOffstage: false), findsNothing);
          expect(
            find.byKey(const ValueKey('forum-tabs-add'), skipOffstage: false),
            findsNothing,
          );
        }
      }),
    );
  }
}

ForumTabsBar _bar(WidgetTester tester) =>
    tester.widget<ForumTabsBar>(find.byType(ForumTabsBar));

Finder _inSidebar(Finder matching) => find.descendant(
  of: find.byType(InstanceSidebar),
  matching: matching,
  skipOffstage: false,
);

Finder _inMainContent(Finder matching) => find.descendant(
  of: find.byType(MainContent),
  matching: matching,
  skipOffstage: false,
);

Finder _sidebarText(String text) => find.descendant(
  of: find.byType(InstanceSidebar),
  matching: find.text(text),
);

Finder _contentTextOutsideTabs(String label) =>
    find.byElementPredicate((element) {
      final widget = element.widget;
      if (widget is! Text || widget.data != label) return false;

      var inMainContent = false;
      var inTabBar = false;
      element.visitAncestorElements((ancestor) {
        inMainContent |= ancestor.widget is MainContent;
        inTabBar |= ancestor.widget is ForumTabsBar;
        return true;
      });
      return inMainContent && !inTabBar;
    }, description: 'main content text outside forum tabs labelled "$label"');

Future<void> _pumpShell(
  WidgetTester tester, {
  bool twoForums = false,
  Size size = _medium,
  Key? key,
  FakeDiscourseApi? api,
  FakeForumTabStore? forumTabs,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final instances = [
    instance('one.example', title: 'One'),
    if (twoForums) instance('two.example', title: 'Two'),
  ];
  await tester.pumpWidget(
    DiscourseApp(
      key: key,
      store: FakeInstanceStore(instances),
      api: api ?? FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: forumTabs ?? FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.byType(InstanceSidebar), findsOneWidget);
}

Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
}

final class _PathGatedApi extends FakeDiscourseApi {
  _PathGatedApi({
    required this.heldPath,
    required this.release,
    required this.started,
    required super.feeds,
  });

  final String heldPath;
  final Completer<void> release;
  final Completer<void> started;

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    if (path == heldPath) {
      if (!started.isCompleted) started.complete();
      await release.future;
    }
    return super.topicList(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
