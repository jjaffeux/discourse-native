import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/forum_icon.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/new_tab_page.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kMiddleMouseButton, kSecondaryMouseButton;
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
  for (final (platform, size) in [(TargetPlatform.macOS, desktop)]) {
    testWidgets(
      'forum header aligns its logo, title and compact website on $platform',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'discourse_native.panel_tutorial_dismissed': true,
        });
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
        final logo = tester.getRect(
          find.descendant(of: page, matching: find.byType(ForumIcon)),
        );
        final title = tester.getRect(startPageText('Discourse Dev'));
        final website = startPageItem(
          const ValueKey('start-page-forum-website'),
        );
        final address = tester.getRect(
          find.descendant(
            of: website,
            matching: find.text('dev.discourse.org'),
          ),
        );
        final websiteRect = tester.getRect(website);
        expect(logo.width, 28);
        expect(title.left - logo.right, closeTo(10, .01));
        expect(address.left, greaterThan(title.right));
        expect(title.center.dy, closeTo(logo.center.dy, .01));
        expect(websiteRect.center.dy, closeTo(logo.center.dy, .01));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'mobile Start heading contains only a static logo on $platform',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await pumpShell(
          tester,
          phone,
          instances: [instance('dev.discourse.org', title: 'Discourse Dev')],
        );
        final shell = ShellScope.read(
          tester.element(find.byType(MainContent).first),
        );
        shell.pushContent(ContentRoute.newTab());
        await tester.pumpAndSettle();
        final heading = startPageItem(const ValueKey('start-page-heading'));
        final logo = find.descendant(
          of: heading,
          matching: find.byType(ForumIcon),
        );
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        for (final width in [320.0, 390.0, 1024.0]) {
          tester.view.physicalSize = Size(width, 844);
          for (final scale in [1.0, 2.0]) {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            await tester.pumpAndSettle();
            expect(logo, findsOneWidget);
            expect(tester.getSize(logo), const Size.square(28));
            expect(
              find.descendant(of: heading, matching: find.byType(DButton)),
              findsNothing,
            );
            expect(
              find.descendant(
                of: heading,
                matching: find.byType(DDropdownMenu),
              ),
              findsNothing,
            );
            expect(startPageText('Discourse Dev'), findsNothing);
            expect(startPageText('dev.discourse.org'), findsNothing);
            expect(
              startPageItem(const ValueKey('start-page-forum-options')),
              findsNothing,
            );
            expect(
              startPageItem(const ValueKey('start-page-forum-website')),
              findsNothing,
            );
            final content = shell.currentContent;
            await tester.tap(logo);
            await tester.pumpAndSettle();
            expect(shell.currentContent, same(content));
            expect(find.text('Open forum in browser'), findsNothing);
            expect(find.text('Remove forum'), findsNothing);
            expect(tester.takeException(), isNull);
          }
        }
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('the app width setting applies to tab content', (tester) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
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

  testWidgets('recent categories and Start page links expose panel actions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpShell(
        tester,
        desktop,
        api: FakeDiscourseApi(
          categoryList: const [
            TopicCategory(
              id: 12,
              name: 'Support',
              slug: 'support',
              color: '0088cc',
            ),
          ],
        ),
      );
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.openListUrl('/c/support/12', title: 'Support');
      final category = shell
          .recentCategoriesFor(shell.currentInstance!.url)
          .single;
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();

      await tester.tap(
        startPageItem(ValueKey('start-page-recent-${category.id}')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Open in new secondary tab'), findsOneWidget);
      await tester.tap(find.text('Open in new secondary tab'));
      await tester.pumpAndSettle();
      expect(shell.tabsForCurrentForum.last.panel, ForumPanel.secondary);
      expect(shell.tabsForCurrentForum.last.currentContent.title, 'Support');

      await tester.tap(
        find.widgetWithText(DButton, 'Groups').first,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await tester.pumpAndSettle();
      expect(shell.tabsForCurrentForum.last.currentContent.id, 'groups');
      expect(
        shell.tabsForCurrentForum.where(
          (tab) => tab.currentContent.categoryId == 12,
        ),
        hasLength(1),
      );
      expect(shell.currentContent?.id, 'new-tab');
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('Start page links to upcoming events when the site offers them', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
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
      matching: find.widgetWithText(DButton, 'Upcoming events'),
    );

    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    if (events.evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('start-page-more')).first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DDropdownMenuItem, 'Upcoming events'),
      );
    } else {
      await tester.tap(events);
    }
    await tester.pumpAndSettle();
    expect(shell.destinationId, 'events-upcoming');

    shell.selectInstance(1);
    await tester.pumpAndSettle();
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(shortcuts, findsOneWidget);
    expect(events, findsNothing);
  });

  testWidgets('recent category activity updates without another request', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    const site = 'https://meta.discourse.org';
    const user = DiscourseUser(id: 7, username: 'reader');
    final api = FakeDiscourseApi(
      user: user,
      categoryList: [
        TopicCategory.fromJson(const {
          'id': 12,
          'name': 'Plants',
          'slug': 'plants',
          'color': '00aa44',
          'description_excerpt': 'Growing things :seedling:',
        }),
      ],
      trackingState: TopicTrackingState.fromJson(const [
        {
          'topic_id': 41,
          'category_id': 12,
          'highest_post_number': 1,
          'created_in_new_period': true,
        },
      ]),
      feeds: const {'/latest.json': []},
    );
    await pumpShell(
      tester,
      desktop,
      instances: [instance('meta.discourse.org').copyWith(user: user)],
      authenticator: FakeAuthenticator()..keys[site] = 'key',
      api: api,
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    expect(shell.recentCategoriesFor(site), isEmpty);
    final categoryRequests = api.categoryRequests.length;
    final trackingRequests = api.topicTrackingRequests.length;
    shell.openListUrl('/c/plants/12', title: 'Plants');
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();

    final card = startPageItem(
      const ValueKey('start-page-recent-list-/c/plants/12.json'),
    );
    expect(
      find.descendant(of: card, matching: find.text('Plants')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('Growing things :seedling:'),
      ),
      findsNothing,
    );
    expect(find.descendant(of: card, matching: find.text('1')), findsOneWidget);
    expect(api.categoryRequests, hasLength(categoryRequests));
    expect(api.topicTrackingRequests, hasLength(trackingRequests));

    FakeSiteTracker.built.single.deliver({
      'topic_id': 42,
      'message_type': 'new_topic',
      'payload': {
        'category_id': 12,
        'highest_post_number': 1,
        'created_in_new_period': true,
      },
    });
    await tester.pumpAndSettle();
    expect(find.descendant(of: card, matching: find.text('2')), findsOneWidget);
    expect(api.categoryRequests, hasLength(categoryRequests));
    expect(api.topicTrackingRequests, hasLength(trackingRequests));
  });

  testWidgets('Latest topics support middle, Shift, and right click', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpShell(tester, desktop, api: _apiWithLatestTopic());
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.openTopicUrl('/t/recent-topic/42');
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();

      final row = startPageItem(const ValueKey('start-page-recent-topic-42'));
      expect(row, findsOneWidget);
      expect(shell.desktopPanelsEnabled, isTrue);
      final startTabId = shell.activeTabId;

      await tester.tap(
        row,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await tester.pumpAndSettle();
      expect(shell.activeTabId, startTabId);
      expect(shell.tabsForCurrentForum.last.panel, ForumPanel.main);
      expect(shell.tabsForCurrentForum.last.currentContent.topicId, 42);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.tapAt(
        tester.getCenter(row),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(shell.activeTabId, startTabId);
      expect(shell.tabsForCurrentForum.last.panel, ForumPanel.secondary);
      expect(shell.tabsForCurrentForum.last.currentContent.topicId, 42);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.tapAt(tester.getCenter(row), kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(shell.activeTab?.panel, ForumPanel.secondary);
      expect(shell.currentContent?.topicId, 42);

      await tester.tap(
        row,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Open in new main tab'), findsOneWidget);
      final tabCount = shell.tabsForCurrentForum.length;
      await tester.tap(find.text('Open in new main tab'));
      await tester.pumpAndSettle();
      expect(shell.tabsForCurrentForum, hasLength(tabCount + 1));
      expect(shell.tabsForCurrentForum.last.panel, ForumPanel.main);
      expect(shell.tabsForCurrentForum.last.currentContent.topicId, 42);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('Start page uses chrome search and Cmd+F focuses it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpShell(tester, desktop);
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('start-page-search-prompt')),
        findsNothing,
      );
      expect(find.byType(ForumSearch), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyF), isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsNothing);
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

  testWidgets(
    'mobile Start page hides panel keyboard instructions',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NewTabPage(onBrowseTopics: () {})),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Work with two panels'), findsNothing);
      expect(find.byType(DKbd), findsNothing);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

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
      expect(find.text('Work with two panels'), findsNothing);
      expect(find.byKey(const ValueKey('start-page-density')), findsNothing);
      await tester.tap(find.text('Browse latest topics'));
    }
    expect(opened, 2);
  });

  testWidgets('empty recent sections become header shortcuts', (tester) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    await pumpShell(tester, desktop);
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();

    Finder shortcut(String label) => find.descendant(
      of: find.byKey(const ValueKey('start-page-shortcuts')),
      matching: find.widgetWithText(DButton, label),
    );

    expect(find.text('Everything else'), findsNothing);
    final categories = tester.widget<DButton>(shortcut('Categories').first);
    expect(categories.variant, DButtonVariant.secondary);
    expect(
      categories.backgroundColor,
      DTokens.of(
        tester.element(shortcut('Categories').first),
      ).buttonTheme.outline.hover,
    );
    expect(categories.borderColor, isNull);
    expect(
      tester.widget<DButton>(shortcut('Recent topics').first).variant,
      DButtonVariant.secondary,
    );
    await tester.tap(startPageItem(const ValueKey('start-page-more')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(DDropdownMenuItem, 'Groups'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(startPageText('Chat'), findsNothing);

    shell.openTopicUrl('/t/recent-topic/42');
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(
      startPageItem(const ValueKey('start-page-recent-topic-42')),
      findsOneWidget,
    );
    expect(find.text('Recently visited'), findsNothing);
    expect(startPageText('Recent topics'), findsOneWidget);
    expect(shortcut('Categories'), findsOneWidget);

    await tester.tap(shortcut('Categories'));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'all-categories');
  });

  testWidgets('Start page shows recent visits without fetching Latest', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = _apiWithLatestTopic();
    await pumpShell(tester, desktop, api: api);
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    shell.openTopicUrl('/t/recent-topic/42');
    await tester.pumpAndSettle();
    final before = api.feedPaths.length;
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(api.feedPaths, hasLength(before));
    expect(startPageText('Recent topics'), findsOneWidget);
    expect(
      startPageItem(const ValueKey('start-page-recent-topic-42')),
      findsOneWidget,
    );
  });

  testWidgets('Latest topics opens its feed from a new start page tab', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpShell(tester, desktop, api: _apiWithLatestTopic());
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.openTopicUrl('/t/recent-topic/42');
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
      await tester.tap(startPageText('Recent topics'));
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

  testWidgets('an unread chat channel opens from the start page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    const site = 'https://meta.discourse.org';
    const user = DiscourseUser(username: 'reader');
    await pumpShell(
      tester,
      desktop,
      instances: [instance('meta.discourse.org').copyWith(user: user)],
      authenticator: FakeAuthenticator()..keys[site] = 'key',
      api: FakeDiscourseApi(
        user: user,
        totals: chatNotificationTotals(available: true),
        feeds: const {'/latest.json': []},
        chatChannelsBySite: {
          site: const ChatChannels(
            public: [
              ChatChannel(
                id: 9,
                title: 'General',
                kind: ChatChannelKind.category,
                membership: ChatMembership(following: true),
                tracking: ChatTracking(unreadCount: 7),
                lastMessagePreview: 'Back later.',
              ),
            ],
          ),
        },
      ),
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    shell.pushContent(
      const ContentRoute(
        id: 'chat-c-9',
        title: 'General',
        icon: DIcons.comment,
      ),
    );
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(startPageText('Chat'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    final channelCard = startPageItem(
      const ValueKey('start-page-recent-chat-c-9'),
    );
    expect(
      find.descendant(of: channelCard, matching: find.text('7')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: channelCard, matching: find.text('Back later.')),
      findsNothing,
    );
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'chat-c-9');
  });

  testWidgets('Chat previews follow visit order regardless of unread counts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    const site = 'https://meta.discourse.org';
    const user = DiscourseUser(username: 'reader');
    final api = FakeDiscourseApi(
      user: user,
      totals: chatNotificationTotals(available: true),
      feeds: const {'/latest.json': []},
      chatChannelsBySite: {
        site: ChatChannels(
          public: [
            ChatChannel(
              id: 1,
              title: 'Read channel',
              kind: ChatChannelKind.category,
              membership: const ChatMembership(following: true),
              lastMessageAt: DateTime.utc(2026, 9, 25, 12),
            ),
            ChatChannel(
              id: 2,
              title: 'Older unread',
              kind: ChatChannelKind.category,
              membership: const ChatMembership(following: true),
              tracking: const ChatTracking(unreadCount: 2),
              lastMessageAt: DateTime.utc(2026, 9, 25, 10),
              lastMessagePreview: 'Earlier message',
            ),
          ],
          direct: [
            ChatChannel(
              id: 3,
              title: 'Newest unread',
              kind: ChatChannelKind.directMessage,
              membership: const ChatMembership(following: true),
              tracking: const ChatTracking(unreadCount: 4),
              lastMessageAt: DateTime.utc(2026, 9, 25, 11),
              lastMessagePreview: 'Latest message',
            ),
          ],
        ),
      },
    );
    await pumpShell(
      tester,
      desktop,
      instances: [instance('meta.discourse.org').copyWith(user: user)],
      authenticator: FakeAuthenticator()..keys[site] = 'key',
      api: api,
    );
    final requestsBefore = api.chatChannelsRequested.length;
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    for (final (id, title) in [
      (3, 'Newest unread'),
      (2, 'Older unread'),
      (1, 'Read channel'),
    ]) {
      shell.pushContent(
        ContentRoute(id: 'chat-c-$id', title: title, icon: DIcons.comment),
      );
    }
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();

    final newest = startPageItem(const ValueKey('start-page-recent-chat-c-3'));
    final older = startPageItem(const ValueKey('start-page-recent-chat-c-2'));
    expect(newest, findsOneWidget);
    expect(older, findsOneWidget);
    expect(
      startPageItem(const ValueKey('start-page-recent-chat-c-1')),
      findsOneWidget,
    );
    expect(tester.getTopLeft(older).dy, lessThan(tester.getTopLeft(newest).dy));
    expect(api.chatChannelsRequested, hasLength(requestsBefore));
    expect(
      find.descendant(of: newest, matching: find.text('4')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: newest, matching: find.text('Latest message')),
      findsNothing,
    );
  });

  testWidgets('cached bookmarks and Latest appear without extra requests', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    const site = 'https://meta.discourse.org';
    const user = DiscourseUser(username: 'reader');
    final api = FakeDiscourseApi(
      user: user,
      bookmarkList: [
        Bookmark(
          id: 18,
          title: 'Saved topic',
          path: '/t/saved-topic/18',
          bookmarkableType: 'Post',
          postNumber: 2,
          reminderAt: DateTime(2030, 1, 2, 8),
        ),
      ],
      feeds: const {
        '/latest.json': [
          Topic(
            id: 42,
            title: 'Latest from the forum',
            slug: 'latest-from-the-forum',
            unreadPosts: 3,
          ),
        ],
      },
    );
    await pumpShell(
      tester,
      desktop,
      instances: [instance('meta.discourse.org').copyWith(user: user)],
      authenticator: FakeAuthenticator()..keys[site] = 'key',
      api: api,
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    await shell.loadBookmarks(site);
    await tester.pumpAndSettle();
    shell.openTopicUrl('/t/latest-from-the-forum/42');
    await tester.pumpAndSettle();
    final beforeFeeds = api.feedPaths.length;
    final beforeBookmarks = api.bookmarksRequested.length;
    shell.pushContent(
      ContentRoute.topic(
        topicId: 42,
        title: 'Latest from the forum',
        slug: 'latest-from-the-forum',
      ),
    );
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();

    expect(find.text('Saved topic'), findsOneWidget);
    expect(find.text('Latest from the forum'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(api.feedPaths, hasLength(beforeFeeds));
    expect(api.bookmarksRequested, hasLength(beforeBookmarks));
    expect(find.text('Reminder'), findsOneWidget);
    expect(find.text('Post #2'), findsNothing);
  });

  testWidgets('bookmark rows show reminder metadata in the single layout', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
      'discourse_native.start_page_compact': false,
    });
    const site = 'https://meta.discourse.org';
    // UTC+5:45 all year, so no other device zone renders this wall time.
    const user = DiscourseUser(username: 'reader', timezone: 'Asia/Kathmandu');
    final api = FakeDiscourseApi(
      user: user,
      bookmarkList: [
        Bookmark(
          id: 18,
          title: 'Saved topic',
          path: '/t/saved-topic/18',
          bookmarkableType: 'Post',
          postNumber: 2,
          reminderAt: DateTime.utc(2030, 1, 2, 20),
        ),
      ],
    );
    await pumpShell(
      tester,
      desktop,
      instances: [instance('meta.discourse.org').copyWith(user: user)],
      authenticator: FakeAuthenticator()..keys[site] = 'key',
      api: api,
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    await shell.loadBookmarks(site);
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: startPageItem(const ValueKey('start-page-recent-bookmark-18')),
        matching: find.text('Reminder'),
      ),
      findsOneWidget,
    );
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

  testWidgets('Start page renders emoji in single-line titles', (tester) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    const site = 'https://meta.discourse.org';
    const user = DiscourseUser(username: 'reader');
    final api = FakeDiscourseApi(
      user: user,
      categoryList: const [
        TopicCategory(
          id: 12,
          name: 'Plants :tada:',
          slug: 'plants',
          color: '0088cc',
        ),
      ],
      totals: chatNotificationTotals(available: true),
      bookmarkList: const [
        Bookmark(
          id: 18,
          title: 'Saved :tada:',
          name: 'Remember :sparkles:',
          path: '/t/saved/18',
        ),
      ],
      feeds: const {
        '/latest.json': [
          Topic(
            id: 42,
            title: 'Trip to :spain:',
            excerpt: 'Hello :wave:',
            slug: 'trip-to-spain',
          ),
        ],
      },
      chatChannelsBySite: {
        site: const ChatChannels(
          direct: [
            ChatChannel(
              id: 11,
              title: 'Alex :wave:',
              kind: ChatChannelKind.directMessage,
              membership: ChatMembership(following: true),
              tracking: ChatTracking(unreadCount: 1),
              lastMessagePreview: 'No worries! :slight_smile:',
            ),
          ],
        ),
      },
      emojisBySite: {
        site: const [
          SiteEmoji(name: 'tada', url: '/emoji/tada.png'),
          SiteEmoji(name: 'sparkles', url: '/emoji/sparkles.png'),
          SiteEmoji(name: 'spain', url: '/emoji/spain.png'),
          SiteEmoji(name: 'wave', url: '/emoji/wave.png'),
          SiteEmoji(name: 'slight_smile', url: '/emoji/slight_smile.png'),
        ],
      },
    );
    await pumpShell(
      tester,
      desktop,
      instances: [
        instance(
          'meta.discourse.org',
          title: 'Meta :sparkles:',
        ).copyWith(user: user),
      ],
      authenticator: FakeAuthenticator()..keys[site] = 'key',
      api: api,
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    await shell.loadBookmarks(site);
    shell.openListUrl('/c/plants/12', title: 'Plants :tada:');
    shell.pushContent(
      ContentRoute.topic(
        topicId: 42,
        title: 'Trip to :spain:',
        slug: 'trip-to-spain',
      ),
    );
    shell.pushContent(
      const ContentRoute(
        id: 'chat-c-11',
        title: 'Alex :wave:',
        icon: DIcons.user,
      ),
    );
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();

    List<String> emojiIn(String id) => tester
        .widgetList<SiteEmojiImage>(
          find.descendant(
            of: startPageItem(ValueKey('start-page-recent-$id')),
            matching: find.byType(SiteEmojiImage),
          ),
        )
        .map((emoji) => emoji.name)
        .toList();

    expect(emojiIn('bookmark-18'), ['tada']);
    expect(emojiIn('topic-42'), ['spain']);
    expect(emojiIn('chat-c-11'), ['wave']);
    expect(emojiIn(shell.recentCategoriesFor(site).single.id), ['tada']);
    expect(
      tester
          .widget<ForumIcon>(
            find.descendant(
              of: find.byType(NewTabPage).first,
              matching: find.byType(ForumIcon),
            ),
          )
          .forum
          .title,
      'Meta :sparkles:',
    );

    expect(find.text('Remember :sparkles:'), findsNothing);
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
    shell.openTopicUrl('/t/recent-topic/42');
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DItem>(
            startPageItem(const ValueKey('start-page-recent-topic-42')),
          )
          .size,
      DItemSize.xs,
    );
    expect(find.byTooltip('Comfortable'), findsNothing);
    expect(find.byTooltip('Compact'), findsNothing);
    expect(find.byKey(const ValueKey('start-page-density')), findsNothing);
  });

  testWidgets('cached unread direct messages update on the Start page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    const site = 'https://meta.discourse.org';
    const user = DiscourseUser(username: 'reader');
    final channelsBySite = <String, ChatChannels>{
      site: const ChatChannels(
        direct: [
          ChatChannel(
            id: 11,
            title: 'Alex',
            users: [
              ChatUser(
                id: 8,
                username: 'alex',
                avatarUrl: 'https://meta.discourse.org/avatar/alex.png',
              ),
            ],
            kind: ChatChannelKind.directMessage,
            membership: ChatMembership(following: true),
            tracking: ChatTracking(unreadCount: 3),
            lastMessagePreview: 'Thanks for looking.',
          ),
        ],
      ),
    };
    final api = FakeDiscourseApi(
      user: user,
      totals: chatNotificationTotals(available: true),
      feeds: const {'/latest.json': []},
      chatChannelsBySite: channelsBySite,
    );
    await pumpShell(
      tester,
      desktop,
      instances: [instance('meta.discourse.org').copyWith(user: user)],
      authenticator: FakeAuthenticator()..keys[site] = 'key',
      api: api,
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    shell.pushContent(
      const ContentRoute(id: 'chat-c-11', title: 'Alex', icon: DIcons.user),
    );
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    expect(
      find.descendant(
        of: startPageItem(const ValueKey('start-page-recent-chat-c-11')),
        matching: find.byType(DAvatar),
      ),
      findsOneWidget,
    );
    expect(startPageText('Chat'), findsOneWidget);
    final directCard = startPageItem(
      const ValueKey('start-page-recent-chat-c-11'),
    );
    expect(
      find.descendant(of: directCard, matching: find.text('3')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: directCard,
        matching: find.text('Thanks for looking.'),
      ),
      findsNothing,
    );

    channelsBySite[site] = const ChatChannels(
      direct: [
        ChatChannel(
          id: 11,
          title: 'Alex',
          kind: ChatChannelKind.directMessage,
          membership: ChatMembership(following: true),
          tracking: ChatTracking(unreadCount: 5),
          lastMessagePreview: 'See you tomorrow.',
        ),
      ],
    );
    final chat = PluginUiScope.require(
      PluginUiScope.contextFor(tester.element(directCard), chatPluginId),
      chatControllerService,
    );
    await chat.loadChannels(site, force: true);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: directCard, matching: find.text('5')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: directCard, matching: find.text('See you tomorrow.')),
      findsNothing,
    );

    channelsBySite[site] = const ChatChannels(
      direct: [
        ChatChannel(
          id: 11,
          title: 'Alex',
          kind: ChatChannelKind.directMessage,
          membership: ChatMembership(following: true),
        ),
      ],
    );
    await chat.loadChannels(site, force: true);
    await tester.pumpAndSettle();
    expect(directCard, findsOneWidget);
    expect(
      find.descendant(of: directCard, matching: find.byType(DBadge)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('start-page-shortcuts')),
        matching: find.widgetWithText(DButton, 'Chat'),
      ),
      findsNothing,
    );
  });

  testWidgets('recently closed tabs appear and reopen from Start page', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      SharedPreferences.setMockInitialValues({
        'discourse_native.panel_tutorial_dismissed': true,
      });
      await pumpShell(tester, desktop);
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.selectInstance(0);
      shell.pushContent(ContentRoute.newTab());
      final closedId = shell.activeTabId!;
      shell.closeTab(closedId);
      expect(
        shell.recentlyClosedTabsForCurrentForum.map((tab) => tab.id),
        contains(closedId),
      );
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();

      expect(startPageText('Recently closed'), findsOneWidget);
      expect(
        startPageItem(ValueKey('start-page-recent-closed-$closedId')),
        findsOneWidget,
      );
      await tester.tap(
        startPageItem(ValueKey('start-page-recent-closed-$closedId')),
      );
      await tester.pumpAndSettle();
      expect(shell.activeTabId, closedId);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final compact in [true, false]) {
      testWidgets(
        '${platform.name} Start page links do not drag in '
        '${compact ? 'compact' : 'comfortable'} layout but still open on tap',
        (tester) async {
          final previousPlatform = debugDefaultTargetPlatformOverride;
          debugDefaultTargetPlatformOverride = platform;
          try {
            SharedPreferences.setMockInitialValues({
              'discourse_native.panel_tutorial_dismissed': true,
              'discourse_native.start_page_compact': compact,
            });
            await pumpShell(tester, phone, api: _apiWithLatestTopic());
            final shell = ShellScope.read(
              tester.element(find.byType(MainContent).first),
            );
            shell.openTopicUrl('/t/recent-topic/42');
            shell.pushContent(ContentRoute.newTab());
            await tester.pumpAndSettle();

            final source = startPageItem(
              const ValueKey('start-page-recent-topic-42'),
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
            expect(shell.currentContent?.topicId, 42);
          } finally {
            debugDefaultTargetPlatformOverride = previousPlatform;
          }
        },
      );
    }
  }

  for (final compact in [true, false]) {
    testWidgets(
      'dragging a ${compact ? 'compact' : 'comfortable'} Start page row onto tabs opens a new tab',
      (tester) async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          SharedPreferences.setMockInitialValues({
            'discourse_native.panel_tutorial_dismissed': true,
            'discourse_native.start_page_compact': compact,
          });
          await pumpShell(tester, desktop, api: _apiWithLatestTopic());
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent).first),
          );
          shell.selectInstance(0);
          shell.openTopicUrl('/t/recent-topic/42');
          shell.pushContent(ContentRoute.newTab());
          await tester.pumpAndSettle();
          final before = shell.tabsForCurrentForum.length;
          final existingIds = shell.tabsForCurrentForum
              .map((tab) => tab.id)
              .toSet();
          final source = startPageItem(
            const ValueKey('start-page-recent-topic-42'),
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
          expect(
            existingIds,
            isNot(contains(shell.tabsForCurrentForum.first.id)),
          );
          expect(shell.tabsForCurrentForum.first.currentContent.topicId, 42);
        } finally {
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      },
    );
  }

  testWidgets('releasing a Start page link below the tab bar opens no tab', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      SharedPreferences.setMockInitialValues({
        'discourse_native.panel_tutorial_dismissed': true,
      });
      await pumpShell(tester, desktop, api: _apiWithLatestTopic());
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.selectInstance(0);
      shell.openTopicUrl('/t/recent-topic/42');
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();
      final before = shell.tabsForCurrentForum.length;
      final source = startPageItem(
        const ValueKey('start-page-recent-topic-42'),
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
