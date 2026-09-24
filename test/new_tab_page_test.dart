import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
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

  testWidgets('empty recent sections are hidden', (tester) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    await pumpShell(tester, desktop);
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();

    expect(find.text('Everything else'), findsOneWidget);
    final groups = tester.widget<DButton>(
      find.widgetWithText(DButton, 'Groups'),
    );
    expect(groups.variant, DButtonVariant.secondary);
    expect(groups.backgroundColor, isNot(Colors.transparent));
    expect(groups.borderColor, Colors.transparent);
    expect(find.text('Latest topics'), findsNothing);
    expect(find.text('Categories'), findsNothing);
    expect(find.text('Chat'), findsNothing);

    shell.openTopicUrl('/t/recent-topic/42');
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(find.text('Latest topics'), findsOneWidget);
    expect(find.text('Categories'), findsNothing);
    expect(find.text('Chat'), findsNothing);
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
              ),
            ],
          ),
        },
      ),
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    expect(await shell.openPluginUrl('$site/chat/c/-/9'), isTrue);
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();

    expect(shell.recentChannelsFor(site).single.id, 'chat-c-9');
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'chat-c-9');
  });
}
