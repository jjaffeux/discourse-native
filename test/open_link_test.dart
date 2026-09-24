import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
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

    await tester.tap(
      find.text('Open link'),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await tester.pumpAndSettle();

    expect(controller.activeTabId, original);
    expect(controller.tabsForCurrentForum.last.panel, ForumPanel.main);
    expect(controller.selectedTabIn(ForumPanel.secondary), isNull);
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
    expect(controller.tabsForCurrentForum, hasLength(2));
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
  bool tabsEnabled = true,
  bool desktopPanels = false,
  FakeDiscourseApi? api,
}) async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore([instance('one.example')]),
    api: api ?? FakeDiscourseApi(feeds: const {'/latest.json': []}),
    authenticator: FakeAuthenticator(),
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
