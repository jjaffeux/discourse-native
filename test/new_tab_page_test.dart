import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/new_tab_page.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kMiddleMouseButton, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

void main() {
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
      await pumpShell(tester, desktop);
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
        find.byKey(ValueKey('start-page-recent-${category.id}')),
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
        find.widgetWithText(DButton, 'Groups'),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await tester.pumpAndSettle();
      expect(shell.tabsForCurrentForum.last.panel, ForumPanel.main);
      expect(shell.tabsForCurrentForum.last.currentContent.id, 'groups');
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('recent topics support middle, Shift, and right click', (
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
      shell.openTopicUrl('/t/recent-topic/42');
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('start-page-recent-topic-42'));
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

  testWidgets('Start page search opens the top bar search on focus and Cmd+F', (
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

      final prompt = find.byKey(const ValueKey('start-page-search-prompt'));
      expect(prompt, findsOneWidget);
      expect(find.byType(ForumSearch), findsOneWidget);
      final promptField = tester.widget<DInputGroupInput>(prompt);
      expect(promptField.readOnly, isTrue);

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

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(prompt);
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      expect(promptField.focusNode!.hasFocus, isFalse);
      expect(
        tester
            .widget<DInputGroupInput>(find.byKey(ForumSearch.inputKey))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(
        tester
            .getRect(find.byType(ShellTitleBar))
            .contains(tester.getCenter(find.byKey(ForumSearch.inputKey))),
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      promptField.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      expect(promptField.focusNode!.hasFocus, isFalse);
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

  testWidgets('outside click dismisses Start page search without reopening', (
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

      final prompt = find.byKey(const ValueKey('start-page-search-prompt'));
      final promptFocus = tester.widget<DInputGroupInput>(prompt).focusNode!;
      final content = tester.getRect(find.byType(MainContent).first);

      Future<void> dismissOutside() async {
        await tester.tapAt(content.bottomCenter - const Offset(0, 20));
        await tester.pumpAndSettle();
        expect(find.byKey(ForumSearch.panelKey), findsNothing);
        expect(shell.search.panelOpen, isFalse);
        expect(promptFocus.hasFocus, isFalse);
      }

      await tester.tap(prompt);
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      await dismissOutside();

      promptFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      await dismissOutside();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      await dismissOutside();

      await tester.tap(prompt);
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('panel guide keeps its close action at the top right', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(560, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: NewTabPage(onBrowseTopics: () {})),
      ),
    );
    await tester.pumpAndSettle();

    final dismiss = tester.getRect(
      find.byKey(const ValueKey('dismiss-panel-tutorial')),
    );
    final title = tester.getRect(find.text('Work with two panels'));
    expect(dismiss.top, lessThan(title.bottom));
    expect(dismiss.right, greaterThan(title.right - 48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel tutorial appears on new tabs until dismissed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var opened = 0;

    Widget page(Key key) => MaterialApp(
      home: Scaffold(
        body: NewTabPage(key: key, onBrowseTopics: () => opened++),
      ),
    );

    await tester.pumpWidget(page(const ValueKey('first-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Work with two panels'), findsOneWidget);
    expect(find.text('Opens a new tab in main panel'), findsOneWidget);
    expect(find.text('Open in secondary panel'), findsOneWidget);
    expect(find.text('Open in a new tab in secondary panel'), findsOneWidget);
    expect(find.byType(DSkeleton), findsNWidgets(6));
    expect(find.text('This page'), findsNothing);
    expect(find.text('Opened link'), findsNothing);
    expect(find.text("Don't show again"), findsNothing);
    expect(find.text('Got it'), findsNothing);
    expect(find.text('Read side by side'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('dismiss-panel-tutorial')));
    await tester.pumpAndSettle();
    expect(find.text('Work with two panels'), findsNothing);

    await tester.pumpWidget(page(const ValueKey('next-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Work with two panels'), findsNothing);
    await tester.tap(find.text('Browse latest topics'));
    expect(opened, 1);
  });

  testWidgets('empty recent sections become Everything else shortcuts', (
    tester,
  ) async {
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

    expect(find.text('Everything else'), findsOneWidget);
    final groups = tester.widget<DButton>(shortcut('Groups'));
    expect(groups.variant, DButtonVariant.secondary);
    expect(groups.backgroundColor, isNot(Colors.transparent));
    expect(groups.borderColor, Colors.transparent);
    for (final label in ['Latest topics', 'Categories']) {
      expect(
        tester.widget<DButton>(shortcut(label)).variant,
        DButtonVariant.secondary,
        reason: label,
      );
    }
    expect(find.text('Chat'), findsNothing);

    shell.openTopicUrl('/t/recent-topic/42');
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('start-page-recent-topic-42')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DButton>(find.widgetWithText(DButton, 'Latest topics'))
          .variant,
      DButtonVariant.secondary,
    );
    expect(find.text('Recently visited'), findsOneWidget);
    expect(find.widgetWithText(DButton, 'Latest topics'), findsOneWidget);
    expect(shortcut('Categories'), findsOneWidget);

    await tester.tap(shortcut('Categories'));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'all-categories');
  });

  testWidgets('an opened chat channel appears on the start page', (
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
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    final chatShortcut = find.descendant(
      of: find.byKey(const ValueKey('start-page-shortcuts')),
      matching: find.widgetWithText(DButton, 'Chat'),
    );
    expect(chatShortcut, findsOneWidget);
    await tester.tap(chatShortcut);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'chat-channels');

    expect(await shell.openPluginUrl('$site/chat/c/-/9'), isTrue);
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();

    expect(shell.recentChannelsFor(site).single.id, 'chat-c-9');
    expect(find.text('Chat'), findsOneWidget);
    expect(chatShortcut, findsNothing);
    expect(find.text('General'), findsOneWidget);
    await tester.tap(find.byTooltip('Comfortable'));
    await tester.pumpAndSettle();
    final channelCard = find.byKey(
      const ValueKey('start-page-recent-chat-c-9'),
    );
    expect(
      find.descendant(of: channelCard, matching: find.text('7')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: channelCard, matching: find.text('Back later.')),
      findsOneWidget,
    );
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'chat-c-9');
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
    final beforeFeeds = api.feedPaths.length;
    final beforeBookmarks = api.bookmarksRequested.length;
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();

    expect(find.text('Saved topic'), findsOneWidget);
    expect(find.text('Latest from the forum'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(api.feedPaths, hasLength(beforeFeeds));
    expect(api.bookmarksRequested, hasLength(beforeBookmarks));
    await tester.tap(find.byTooltip('Comfortable'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2030'), findsOneWidget);
    expect(find.text('Post #2'), findsOneWidget);
  });

  testWidgets('density control switches between compact and comfortable rows', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    await pumpShell(tester, desktop);
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    shell.openTopicUrl('/t/recent-topic/42');
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('start-page-recent-topic-42'));
    expect(tester.widget<DItem>(row).size, DItemSize.xs);
    await tester.tap(find.byTooltip('Comfortable'));
    await tester.pumpAndSettle();
    expect(tester.widget<DItem>(row).size, DItemSize.standard);
    await tester.tap(find.byTooltip('Compact'));
    await tester.pumpAndSettle();
    expect(tester.widget<DItem>(row).size, DItemSize.xs);
  });

  testWidgets('comfortable mode shows four cards across a full-width section', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    await pumpShell(tester, const Size(1800, 900));
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    for (final (id, title) in [
      (1, 'Baking'),
      (2, 'Plants'),
      (3, 'Keyboards'),
      (4, 'Travel'),
    ]) {
      shell.openListUrl('/c/${title.toLowerCase()}/$id', title: title);
    }
    shell.pushContent(ContentRoute.newTab());
    await shell.appSettings.setLimitContentSize(false);
    await tester.pumpAndSettle();

    final cards = [
      for (final route in shell.recentCategoriesFor(shell.currentInstance!.url))
        find.byKey(ValueKey('start-page-recent-${route.id}')),
    ];
    expect(cards, hasLength(4));
    await tester.tap(find.byTooltip('Comfortable'));
    await tester.pumpAndSettle();

    final rects = [for (final card in cards) tester.getRect(card)];
    expect(rects.map((rect) => rect.top).toSet(), hasLength(1));
    expect(rects.map((rect) => rect.left).toSet(), hasLength(4));
    expect(rects.every((rect) => rect.width > 280), isTrue);
    expect(rects.every((rect) => rect.height >= 160), isTrue);
    expect(tester.widget<DItem>(cards.first).shape, DItemShape.card);
  });

  testWidgets('cached direct messages join recent chat channels', (
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
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    await tester.tap(find.byTooltip('Comfortable'));
    await tester.pumpAndSettle();
    final directCard = find.byKey(
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
      findsOneWidget,
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
      findsOneWidget,
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

      expect(find.text('Recently closed'), findsOneWidget);
      expect(
        find.byKey(ValueKey('start-page-recent-closed-$closedId')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(ValueKey('start-page-recent-closed-$closedId')),
      );
      await tester.pumpAndSettle();
      expect(shell.activeTabId, closedId);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('dragging a Start page row onto tabs opens a new tab', (
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
      shell.openTopicUrl('/t/recent-topic/42');
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();
      final before = shell.tabsForCurrentForum.length;
      final existingIds = shell.tabsForCurrentForum
          .map((tab) => tab.id)
          .toSet();
      final source = find.byKey(const ValueKey('start-page-recent-topic-42'));
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

  testWidgets('releasing a Start page link below the tab bar opens no tab', (
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
      shell.openTopicUrl('/t/recent-topic/42');
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();
      final before = shell.tabsForCurrentForum.length;
      final source = find.byKey(const ValueKey('start-page-recent-topic-42'));
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
