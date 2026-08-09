import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

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
          theme: AppTheme.light,
          home: Scaffold(
            body: Row(
              children: [
                const SizedBox(width: 240, child: InstanceSidebar()),
                const UserMenuButton(),
                const SizedBox(
                  width: 400,
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
    final sidebarSelector = _onlyChild(sidebar);
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
        child: MaterialApp(theme: AppTheme.light, home: const AdaptiveShell()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A real topic'), findsOneWidget);

    final rail = tester.element(find.byType(InstanceRail));
    final content = tester.element(find.byType(MainContent));
    final list = tester.element(find.byType(TopicListView));
    final rowTitle = tester.element(find.text('A real topic'));
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

    // On a wide layout, selecting the already-current site changes no visible
    // shell state. It still emits a shell notification because the same action
    // returns compact layouts to their sidebar.
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
            theme: AppTheme.light,
            home: const AdaptiveShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inactiveTabId = controller.activeTabId!;
      controller.createTab();
      await tester.pumpAndSettle();

      final activeTabId = controller.activeTabId!;
      expect(activeTabId, isNot(inactiveTabId));
      expect(
        tester
            .widget<ForumTabsBar>(find.byType(ForumTabsBar))
            .items
            .map((item) => item.id),
        [inactiveTabId, activeTabId],
      );

      final bar = tester.element(find.byType(ForumTabsBar));
      final viewport = tester.element(find.byType(TopicListView));
      final viewportSelector = _onlyChild(viewport);
      final rowTitle = tester.element(find.text('A real topic'));
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
        tester
            .widget<ForumTabsBar>(find.byType(ForumTabsBar))
            .items
            .map((item) => item.id),
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
        child: MaterialApp(theme: AppTheme.light, home: const AdaptiveShell()),
      ),
    );
    await tester.pumpAndSettle();

    final firstTabId = controller.activeTabId!;
    final firstViewport = tester.element(find.byType(TopicListView));

    controller.createTab();
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
}

void _noop() {}

Element _onlyChild(Element parent) {
  final children = <Element>[];
  parent.visitChildren(children.add);
  expect(children, hasLength(1));
  return children.single;
}
