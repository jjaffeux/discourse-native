import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/shell/open_link.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart' show watchBrowser;

void main() {
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
}

Future<ShellController> _pumpLink(
  WidgetTester tester, {
  String url = '/t/a-topic/42',
  bool tabsEnabled = true,
}) async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore([instance('one.example')]),
    api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    forumTabsEnabled: tabsEnabled,
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
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
