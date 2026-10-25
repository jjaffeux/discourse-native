import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/new_tab_page.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

// The mobile dock labels its Chat panel too; section headings are asserted
// on the Start page itself.
Finder startPageText(String text) => find.descendant(
  of: find.byType(NewTabPage).first,
  matching: find.text(text),
);

Finder startPageItem(Key key) => find.descendant(
  of: find.byType(NewTabPage).first,
  matching: find.byKey(key),
);

void main() {
  for (final (platform, size) in [
    (TargetPlatform.macOS, desktop),
    (TargetPlatform.iOS, phone),
  ]) {
    testWidgets(
      'Start begins with launchers and has no forum header or Filters on $platform',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await pumpShell(
          tester,
          size,
          instances: [instance('dev.discourse.org', title: 'Discourse Dev')],
        );
        final shell = ShellScope.read(
          tester.element(find.byType(MainContent).first),
        );
        shell.pushContent(ContentRoute.newTab());
        await tester.pumpAndSettle();

        final page = find.byType(NewTabPage).first;
        expect(startPageText('Discourse Dev'), findsNothing);
        expect(startPageText('dev.discourse.org'), findsNothing);
        expect(startPageText('Filters'), findsNothing);
        final content = startPageItem(const ValueKey('start-page-content'));
        expect(tester.getTopLeft(content).dy, tester.getTopLeft(page).dy);
        expect(
          tester
              .getTopLeft(startPageItem(const ValueKey('start-page-shortcuts')))
              .dy,
          closeTo(tester.getTopLeft(page).dy + 18, .01),
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('the app width setting applies to tab content', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpShell(tester, const Size(3000, 900));
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    shell.pushContent(ContentRoute.newTab());
    await shell.appSettings.setLimitContentSize(false);
    await tester.pumpAndSettle();

    final page = find.byType(NewTabPage).first;
    final content = find.byKey(const ValueKey('start-page-content'));
    final wideViewport = tester.getRect(page);
    final wide = tester.getRect(content);
    expect(wide.width, greaterThan(825));

    await shell.appSettings.setLimitContentSize(true);
    await tester.pumpAndSettle();
    final normal = tester.getRect(content);
    expect(tester.getRect(page), wideViewport);
    expect(normal.width, 825);
    expect(normal.center.dx, wide.center.dx);
  });

  testWidgets('Start page links to upcoming events when the site offers them', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SiteConfig config({required bool events}) =>
        installedPlugins.models.siteConfig({
          'discourse_events_enabled': events,
          'discourse_post_event_enabled': true,
          'sidebar_show_upcoming_events': true,
        }, 'https://forum.example');
    final sites = [
      instance('events.example').copyWith(config: config(events: true)),
      instance('plain.example').copyWith(config: config(events: false)),
    ];
    await pumpShell(
      tester,
      desktop,
      instances: sites,
      api: FakeDiscourseApi(
        siteConfigs: {for (final site in sites) site.url: site.config},
      ),
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    final shortcuts = find.byKey(const ValueKey('start-page-shortcuts'));
    final events = find.descendant(
      of: shortcuts,
      matching: find.widgetWithText(DButton, 'Events'),
    );

    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(events, findsOneWidget);
    await Scrollable.ensureVisible(tester.element(events), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(events);
    await tester.pumpAndSettle();
    expect(shell.destinationId, 'events-upcoming');

    shell.selectInstance(1);
    await tester.pumpAndSettle();
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(shortcuts, findsOneWidget);
    expect(events, findsNothing);
  });

  testWidgets('Start page uses chrome search and Cmd+F focuses it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpShell(tester, desktop);
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();

      expect(find.byType(ForumSearch), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyF), isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      expect(
        tester
            .widget<DInputGroupInput>(find.byKey(ForumSearch.inputKey))
            .focusNode!
            .hasFocus,
        isTrue,
      );
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('first and subsequent tabs have the same launcher', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var opened = 0;
    for (final key in ['first', 'second']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NewTabPage(
              key: ValueKey(key),
              onBrowseTopics: () => opened++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Browse latest topics'));
    }
    expect(opened, 2);
  });

  testWidgets('Topics opens its feed from a new start page tab', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpShell(tester, desktop, api: _apiWithLatestTopic());
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.createTab(panel: ForumPanel.main);
      shell.pushContent(
        ContentRoute.topic(
          topicId: 42,
          slug: 'recent-topic',
          title: 'Recent topic',
        ),
      );
      final closedId = shell.activeTabId!;
      shell.closeTab(closedId);
      shell.openContentInNewTab(ContentRoute.newTab(), select: true);
      await tester.pumpAndSettle();

      expect(shell.activeTab?.rootDestinationId, 'new-tab');
      expect(
        find.descendant(
          of: find.byType(MainContent).first,
          matching: find.text('Recent topic'),
        ),
        findsOneWidget,
      );
      await tester.tap(startPageText('Topics'));
      await tester.pumpAndSettle();

      expect(shell.currentContent?.id, 'latest');
      expect(shell.currentFeedId, 'latest');
      expect(shell.currentTopicListMode, TopicListMode.latest);
      expect(shell.currentFeed?.topicIds, [42]);
      expect(find.text('Not found'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(MainContent).first,
          matching: find.text('Recent topic'),
        ),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  test('reminder day names compare days in the reminder zone', () {
    final environment = TimezoneEnvironment.instance..ensureDatabase();
    final paris = environment.location('Europe/Paris')!;
    // 08:00 on Monday 28 September in Paris.
    final reminder = DateTime.utc(2026, 9, 28, 6);

    // 23:00 on Sunday in Paris, still Sunday in UTC.
    expect(
      reminderDateLabel(
        reminder,
        location: paris,
        now: DateTime.utc(2026, 9, 27, 21),
        use24HourClock: false,
      ),
      'Tomorrow at 8:00 AM',
    );
    // 00:30 on Monday in Paris, still Sunday in UTC.
    expect(
      reminderDateLabel(
        reminder,
        location: paris,
        now: DateTime.utc(2026, 9, 27, 22, 30),
        use24HourClock: false,
      ),
      'Today at 8:00 AM',
    );
    expect(
      reminderDateLabel(
        reminder,
        location: paris,
        now: DateTime.utc(2026, 9, 26, 12),
        use24HourClock: false,
      ),
      'Sep 28, 2026 at 8:00 AM',
    );
  });

  test('reminder times follow the reader clock', () {
    final environment = TimezoneEnvironment.instance..ensureDatabase();
    final paris = environment.location('Europe/Paris')!;
    // 20:00 on Monday 28 September in Paris.
    final reminder = DateTime.utc(2026, 9, 28, 18);

    String label({required bool use24HourClock}) => reminderDateLabel(
      reminder,
      location: paris,
      now: DateTime.utc(2026, 9, 26, 12),
      use24HourClock: use24HourClock,
    );

    expect(label(use24HourClock: false), 'Sep 28, 2026 at 8:00 PM');
    expect(label(use24HourClock: true), 'Sep 28, 2026 at 20:00');
  });

  testWidgets('legacy density preferences cannot bring back cards', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.start_page_compact': false,
    });
    await pumpShell(tester, desktop, api: _apiWithLatestTopic());
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DButton>(
            startPageItem(const ValueKey('start-page-section-link-Topics')),
          )
          .variant,
      DButtonVariant.launcher,
    );
    expect(find.byTooltip('Comfortable'), findsNothing);
    expect(find.byTooltip('Compact'), findsNothing);
  });

  testWidgets('recently closed tabs appear and reopen from Start page', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      SharedPreferences.setMockInitialValues({});
      await pumpShell(tester, desktop);
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.selectInstance(0);
      final closedId = shell.activeTabId!;
      shell.closeTab(closedId);
      shell.createTab(panel: ForumPanel.main);
      final startId = shell.activeTabId!;
      expect(shell.currentContent?.isNewTab, isTrue);
      shell.closeTab(startId);
      expect(shell.recentlyClosedTabsForCurrentForum.map((tab) => tab.id), [
        closedId,
      ]);
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();

      expect(startPageText('Recently closed'), findsOneWidget);
      expect(
        startPageItem(ValueKey('start-page-recent-closed-$closedId')),
        findsOneWidget,
      );
      expect(
        startPageItem(ValueKey('start-page-recent-closed-$startId')),
        findsNothing,
      );
      await tester.tap(
        startPageItem(ValueKey('start-page-recent-closed-$closedId')),
      );
      await tester.pumpAndSettle();
      expect(shell.activeTabId, closedId);
      expect(shell.currentContent?.isNewTab, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '${platform.name} Start page links do not drag but still open on tap',
      (tester) async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = platform;
        try {
          SharedPreferences.setMockInitialValues({});
          await pumpShell(tester, phone, api: _apiWithLatestTopic());
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent).first),
          );
          shell.pushContent(ContentRoute.newTab());
          await tester.pumpAndSettle();

          final source = startPageItem(
            const ValueKey('start-page-section-link-Topics'),
          );
          expect(source, findsOneWidget);
          final gesture = await tester.startGesture(tester.getCenter(source));
          await gesture.moveBy(const Offset(60, 0));
          await tester.pump();
          expect(
            find.byKey(const ValueKey('start-page-drag-feedback')),
            findsNothing,
          );
          await gesture.up();
          await tester.pumpAndSettle();
          expect(find.byType(NewTabPage), findsOneWidget);

          await tester.tap(source);
          await tester.pumpAndSettle();
          expect(shell.currentContent?.id, 'latest');
        } finally {
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      },
    );
  }

  testWidgets('dragging a Start page row onto tabs opens a new tab', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      SharedPreferences.setMockInitialValues({});
      await pumpShell(tester, desktop, api: _apiWithLatestTopic());
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.selectInstance(0);
      shell.createTab(panel: ForumPanel.main);
      shell.pushContent(
        ContentRoute.topic(
          topicId: 42,
          slug: 'recent-topic',
          title: 'Recent topic',
        ),
      );
      final closedId = shell.activeTabId!;
      shell.closeTab(closedId);
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();
      final before = shell.tabsForCurrentForum.length;
      final existingIds = shell.tabsForCurrentForum
          .map((tab) => tab.id)
          .toSet();
      final source = startPageItem(
        ValueKey('start-page-recent-closed-$closedId'),
      );
      expect(source, findsOneWidget);
      final target = find.byType(CurrentForumTabsBar).first;
      final gesture = await tester.startGesture(tester.getCenter(source));
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('start-page-drag-feedback')),
        findsOneWidget,
      );
      final placeholder = find.byKey(
        const ValueKey('forum-tab-drop-placeholder'),
      );
      expect(placeholder, findsOneWidget);
      final tabBar = tester.getRect(find.byType(ForumTabsBar).first);
      await gesture.moveTo(Offset(tabBar.left + 8, tabBar.center.dy));
      await tester.pump();
      final leftInsertion = tester.getRect(placeholder).left;
      await gesture.moveTo(Offset(tabBar.right - 8, tabBar.center.dy));
      await tester.pump();
      expect(tester.getRect(placeholder).left, greaterThan(leftInsertion));
      await gesture.moveTo(Offset(tabBar.left + 8, tabBar.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(shell.tabsForCurrentForum, hasLength(before + 1));
      expect(existingIds, isNot(contains(shell.tabsForCurrentForum.first.id)));
      expect(shell.tabsForCurrentForum.first.currentContent.topicId, 42);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('dragging a closed filtered category keeps its native route', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      SharedPreferences.setMockInitialValues({});
      const site = 'https://forum.example/forum';
      await pumpShell(
        tester,
        desktop,
        instances: [instance('forum.example/forum')],
        api: _apiWithLatestTopic(),
      );
      final launched = watchBrowser(tester);
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.createTab(panel: ForumPanel.main);
      expect(
        shell.openListUrl(
          '$site/c/support/12?status=open&tags[]=help%20wanted',
        ),
        isTrue,
      );
      final route = shell.currentContent!;
      final closedId = shell.activeTabId!;
      shell.closeTab(closedId);
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();
      final before = shell.tabsForCurrentForum.length;
      final existingIds = shell.tabsForCurrentForum
          .map((tab) => tab.id)
          .toSet();
      final source = startPageItem(
        ValueKey('start-page-recent-closed-$closedId'),
      );
      expect(source, findsOneWidget);
      final gesture = await tester.startGesture(tester.getCenter(source));
      await gesture.moveTo(
        tester.getCenter(find.byType(CurrentForumTabsBar).first),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('forum-tab-drop-placeholder')),
        findsOneWidget,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(launched, isEmpty);
      expect(shell.tabsForCurrentForum, hasLength(before + 1));
      final opened = shell.tabsForCurrentForum
          .singleWhere((tab) => !existingIds.contains(tab.id))
          .currentContent;
      expect(opened.feedPath, route.feedPath);
      expect(opened.categoryId, 12);
      expect(Uri.parse(opened.feedPath!).queryParametersAll, {
        'status': ['open'],
        'tags[]': ['help wanted'],
      });
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('releasing a Start page link below the tab bar opens no tab', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      SharedPreferences.setMockInitialValues({});
      await pumpShell(tester, desktop, api: _apiWithLatestTopic());
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.selectInstance(0);
      shell.createTab(panel: ForumPanel.main);
      shell.pushContent(
        ContentRoute.topic(
          topicId: 42,
          slug: 'recent-topic',
          title: 'Recent topic',
        ),
      );
      final closedId = shell.activeTabId!;
      shell.closeTab(closedId);
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();
      final before = shell.tabsForCurrentForum.length;
      final source = startPageItem(
        ValueKey('start-page-recent-closed-$closedId'),
      );
      final tabBar = tester.getRect(find.byType(ForumTabsBar).first);
      final gesture = await tester.startGesture(tester.getCenter(source));
      await gesture.moveTo(tabBar.center);
      await tester.pump();
      final placeholder = find.byKey(
        const ValueKey('forum-tab-drop-placeholder'),
      );
      expect(placeholder, findsOneWidget);
      await gesture.moveTo(Offset(tabBar.center.dx, tabBar.bottom + 80));
      await tester.pump();
      expect(placeholder, findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(shell.tabsForCurrentForum, hasLength(before));
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}

FakeDiscourseApi _apiWithLatestTopic() => FakeDiscourseApi(
  feeds: const {
    '/latest.json': [
      Topic(id: 42, title: 'Recent topic', slug: 'recent-topic'),
    ],
  },
);
