import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/open_tabs_section.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _compact = Size(390, 844);
const _medium = Size(1000, 800);
const _expanded = Size(1440, 900);

void main() {
  testWidgets(
    'maps current routes and delegates tab lifecycle actions',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
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
    }),
  );

  testWidgets(
    'shows only the selected forum workspace',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester, twoForums: true);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );

      controller.createTab();
      await tester.pump();
      final firstForumIds = [
        for (final item in _section(tester).items) item.id,
      ];
      expect(firstForumIds, hasLength(2));

      controller.selectInstance(1);
      await tester.pump();

      expect(_section(tester).items, hasLength(1));
      expect(firstForumIds, isNot(contains(_section(tester).items.single.id)));

      controller.selectInstance(0);
      await tester.pump();

      expect([
        for (final item in _section(tester).items) item.id,
      ], firstForumIds);
    }),
  );

  for (final platform in const [
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      '${platform.name} shows OPEN at narrow and expanded widths',
      (tester) => _withPlatform(platform, () async {
        for (final size in const [_compact, _expanded]) {
          await _pumpShell(
            tester,
            size: size,
            key: ValueKey('${platform.name}-${size.width}'),
          );

          expect(find.byType(InstanceSidebar), findsOneWidget);
          expect(
            find.byType(OpenTabsSection, skipOffstage: false),
            findsOneWidget,
          );
          expect(find.text('OPEN', skipOffstage: false), findsOneWidget);
          expect(
            find.byKey(const ValueKey('open-tabs-add'), skipOffstage: false),
            findsOneWidget,
          );
        }
      }),
    );
  }

  for (final platform in const [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      '${platform.name} omits the tab subtree at every width',
      (tester) => _withPlatform(platform, () async {
        for (final size in const [_compact, _medium, _expanded]) {
          await _pumpShell(
            tester,
            size: size,
            key: ValueKey('${platform.name}-${size.width}'),
          );

          expect(find.byType(InstanceSidebar), findsOneWidget);
          expect(
            find.byType(OpenTabsSection, skipOffstage: false),
            findsNothing,
          );
          expect(find.text('OPEN', skipOffstage: false), findsNothing);
          expect(
            find.byKey(const ValueKey('open-tabs-add'), skipOffstage: false),
            findsNothing,
          );
        }
      }),
    );
  }
}

OpenTabsSection _section(WidgetTester tester) =>
    tester.widget<OpenTabsSection>(find.byType(OpenTabsSection));

Future<void> _pumpShell(
  WidgetTester tester, {
  bool twoForums = false,
  Size size = _medium,
  Key? key,
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
