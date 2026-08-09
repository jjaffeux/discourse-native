import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/open_tabs_section.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('maps current routes and delegates tab lifecycle actions', (
    tester,
  ) async {
    await _pumpShell(tester);
    final controller = ShellScope.read(
      tester.element(find.byType(MainContent)),
    );
    final originalId = controller.activeTabId!;

    expect(find.byType(OpenTabsSection), findsOneWidget);
    expect(_section(tester).items.single.title, 'Topics');

    await tester.tap(find.byKey(const ValueKey('open-tabs-add')));
    await tester.pump();

    final newId = controller.activeTabId!;
    expect(newId, isNot(originalId));
    expect(_section(tester).items, hasLength(2));
    expect(_section(tester).selectedId, newId);

    const color = Color(0xFF0088CC);
    controller.pushContent(
      ContentRoute.topic(
        topicId: 42,
        slug: 'native-tabs',
        title: 'Native tabs',
        color: color,
      ),
    );
    await tester.pump();

    final routedItem = _section(
      tester,
    ).items.singleWhere((item) => item.id == newId);
    expect(routedItem.title, 'Native tabs');
    expect(routedItem.icon, DIcons.comments);
    expect(routedItem.color, color);

    await tester.tap(find.byKey(ValueKey('open-tab-$originalId')));
    await tester.pump();
    expect(controller.activeTabId, originalId);

    await tester.tap(find.byKey(ValueKey('open-tab-close-$originalId')));
    await tester.pump();
    expect(controller.tabsForCurrentForum.map((tab) => tab.id), [newId]);
  });

  testWidgets('shows only the selected forum workspace', (tester) async {
    await _pumpShell(tester, twoForums: true);
    final controller = ShellScope.read(
      tester.element(find.byType(MainContent)),
    );

    controller.createTab();
    await tester.pump();
    final firstForumIds = [for (final item in _section(tester).items) item.id];
    expect(firstForumIds, hasLength(2));

    controller.selectInstance(1);
    await tester.pump();

    expect(_section(tester).items, hasLength(1));
    expect(firstForumIds, isNot(contains(_section(tester).items.single.id)));

    controller.selectInstance(0);
    await tester.pump();

    expect([for (final item in _section(tester).items) item.id], firstForumIds);
  });
}

OpenTabsSection _section(WidgetTester tester) =>
    tester.widget<OpenTabsSection>(find.byType(OpenTabsSection));

Future<void> _pumpShell(WidgetTester tester, {bool twoForums = false}) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final instances = [
    instance('one.example', title: 'One'),
    if (twoForums) instance('two.example', title: 'Two'),
  ];
  await tester.pumpWidget(
    DiscourseApp(
      store: FakeInstanceStore(instances),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.byType(InstanceSidebar), findsOneWidget);
}
