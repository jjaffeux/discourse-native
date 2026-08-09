import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
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

            await tester.tap(_sidebarText('Messages'));
            await tester.pumpAndSettle();

            expect(find.byType(InstanceSidebar), findsNothing);
            expect(find.byType(MainContent), findsOneWidget);
          }

          expect(_inMainContent(find.byType(ForumTabsBar)), findsOneWidget);
          expect(find.byType(CurrentForumTabsBar), findsOneWidget);
          expect(find.byKey(const ValueKey('forum-tabs-add')), findsOneWidget);
          expect(
            _bar(tester).items.single.title,
            size == _compact ? 'Messages' : 'Topics',
          );
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
            await tester.tap(_sidebarText('Messages'));
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
