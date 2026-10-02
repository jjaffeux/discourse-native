import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/new_tab_page.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_filter_input.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
  });

  testStartPage(
    'start-page filter builder navigates to applied topic filters',
    (tester) async {
      await pumpShell(tester, desktop);
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-list-filter')).first);
      await tester.pumpAndSettle();
      expect(find.byType(TopicFilterInput), findsOneWidget);
      await tester.tap(find.widgetWithText(DToggle, 'Open topics'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DButton, 'Apply filter'));
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.topicFilterQuery, 'status:open');
      expect(
        find.descendant(
          of: find.byType(MainContent).first,
          matching: find.byType(NewTabPage),
        ),
        findsNothing,
      );
    },
  );

  testStartPage('domain opens the forum base in the external browser', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final launched = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') {
        launched.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await pumpShell(tester, desktop);
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('start-page-forum-website')).first,
    );
    await tester.pumpAndSettle();
    expect(launched, [shell.currentInstance!.url]);
    expect(
      find.descendant(
        of: find.byType(MainContent).first,
        matching: find.byType(NewTabPage),
      ),
      findsOneWidget,
    );
  });

  testStartPage(
    'comfortable previews fill one row and compact previews show four',
    (tester) async {
      await pumpShell(
        tester,
        const Size(2400, 1000),
        api: FakeDiscourseApi(
          feeds: {
            '/latest.json': [
              for (var i = 1; i <= 8; i++)
                Topic(id: i, title: 'Topic $i', slug: 'topic-$i'),
            ],
          },
        ),
      );
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      await shell.appSettings.setLimitContentSize(false);
      shell.createTab(panel: ForumPanel.secondary);
      await tester.pumpAndSettle();
      final cards = find.byWidgetPredicate(
        (widget) =>
            widget is DItem &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'start-page-recent-topic-',
            ),
      );
      expect(cards, findsNWidgets(4));
      await tester.tap(find.byTooltip('Comfortable'));
      await tester.pumpAndSettle();
      final wideCount = cards.evaluate().length;
      expect(wideCount, greaterThan(4));
      expect(wideCount, lessThanOrEqualTo(8));
      expect({
        for (var i = 0; i < wideCount; i++) tester.getTopLeft(cards.at(i)).dy,
      }, hasLength(1));
      tester.view.physicalSize = const Size(800, 1000);
      await tester.pumpAndSettle();
      final narrowCount = cards.evaluate().length;
      expect(narrowCount, lessThan(wideCount));
      expect({
        for (var i = 0; i < narrowCount; i++) tester.getTopLeft(cards.at(i)).dy,
      }, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testStartPage('category history cannot reintroduce unavailable categories', (
    tester,
  ) async {
    await pumpShell(
      tester,
      desktop,
      api: FakeDiscourseApi(
        categoryList: const [
          TopicCategory(
            id: 1,
            name: 'Visible category',
            slug: 'visible',
            color: '0088cc',
          ),
        ],
      ),
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    expect(shell.recentCategoriesFor(shell.currentInstance!.url), isEmpty);
    shell.openListUrl('/c/removed/99', title: 'Removed category');
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    final page = find.byType(NewTabPage).first;
    expect(
      find.descendant(of: page, matching: find.text('Visible category')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: page, matching: find.text('Removed category')),
      findsNothing,
    );
  });

  testStartPage('compact closed chips size naturally, wrap, drag and restore', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1400, 1000));
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    final closed = <String>[];
    for (final (id, title) in [
      (41, 'Short'),
      (42, 'A longer closed topic'),
      (43, 'Third topic'),
      (44, 'Fourth topic'),
      (45, 'Fifth topic'),
    ]) {
      shell.createTab(panel: ForumPanel.secondary);
      shell.pushContent(
        ContentRoute.topic(topicId: id, slug: 'topic-$id', title: title),
      );
      closed.add(shell.activeTabId!);
      shell.closeTab(shell.activeTabId!);
    }
    shell.createTab(panel: ForumPanel.secondary);
    await tester.pumpAndSettle();
    Finder chip(int index) =>
        find.byKey(ValueKey('start-page-recent-closed-${closed[index]}'));
    expect(
      closed.map(
        (id) => find
            .byKey(ValueKey('start-page-recent-closed-$id'))
            .evaluate()
            .length,
      ),
      everyElement(1),
    );
    final short = tester.getRect(chip(0));
    final longer = tester.getRect(chip(1));
    expect(short.width, lessThan(longer.width));
    expect(longer.width, lessThanOrEqualTo(280));
    expect(tester.widget<DItem>(chip(0)).fitContent, isTrue);
    expect(
      {
        for (var i = 0; i < closed.length; i++) tester.getTopLeft(chip(i)).dy,
      }.length,
      greaterThan(1),
    );
    final active = shell.activeTabId;
    await tester.tapAt(Offset(short.right + 2, short.center.dy));
    await tester.pumpAndSettle();
    expect(shell.activeTabId, active);
    final before = shell.tabsForCurrentForum.length;
    final existingIds = shell.tabsForCurrentForum.map((tab) => tab.id).toSet();
    final gesture = await tester.startGesture(
      tester.getCenter(chip(0)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, -16));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('start-page-drag-feedback')),
      findsOneWidget,
    );
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('forum-tabs-add')).last),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(shell.tabsForCurrentForum.length, before + 1);
    expect(
      shell.tabsForCurrentForum
          .singleWhere((tab) => !existingIds.contains(tab.id))
          .currentContent
          .topicId,
      41,
    );
    shell.selectTab(active!);
    await tester.pumpAndSettle();
    await tester.tap(chip(1));
    await tester.pumpAndSettle();
    expect(shell.activeTabId, closed[1]);
    expect(shell.currentContent?.topicId, 42);
  });

  testStartPage(
    'closed topic, category and DM previews retain cached details',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'discourse_native.panel_tutorial_dismissed': true,
        'discourse_native.start_page_compact': false,
      });
      const site = 'https://one.example';
      const user = DiscourseUser(username: 'reader');
      const topic = Topic(
        id: 10,
        title: 'Closed topic',
        slug: 'closed',
        excerpt: 'Topic excerpt',
      );
      await pumpShell(
        tester,
        const Size(1800, 1000),
        instances: [instance('one.example').copyWith(user: user)],
        authenticator: FakeAuthenticator()..keys[site] = 'key',
        api: FakeDiscourseApi(
          user: user,
          totals: chatNotificationTotals(available: true),
          feeds: const {
            '/latest.json': [topic],
            '/filter.json?per_page=30': [],
          },
          categoryList: const [
            TopicCategory(
              id: 12,
              name: 'Support',
              slug: 'support',
              color: '0088cc',
              descriptionExcerpt: 'Category details',
            ),
          ],
          chatChannelsBySite: {
            site: const ChatChannels(
              direct: [
                ChatChannel(
                  id: 5,
                  title: 'Alex',
                  kind: ChatChannelKind.directMessage,
                  membership: ChatMembership(following: true),
                  users: [
                    ChatUser(
                      id: 3,
                      username: 'alex',
                      avatarUrl: '$site/alex.png',
                    ),
                  ],
                  lastMessagePreview: 'DM excerpt',
                ),
              ],
            ),
          },
        ),
      );
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.selectInstance(0);
      await tester.pumpAndSettle();
      await shell.appSettings.setLimitContentSize(false);
      final closed = <String>[];
      for (final route in [
        ContentRoute.topic(topicId: 10, slug: 'closed', title: 'Closed topic'),
        const ContentRoute(id: 'chat-c-5', title: 'Alex', icon: DIcons.user),
      ]) {
        shell.createTab(panel: ForumPanel.secondary);
        shell.pushContent(route);
        closed.add(shell.activeTabId!);
        shell.closeTab(shell.activeTabId!);
      }
      shell.createTab(panel: ForumPanel.secondary);
      shell.openListUrl('/c/support/12', title: 'Support');
      closed.add(shell.activeTabId!);
      shell.closeTab(shell.activeTabId!);
      shell.createTab(panel: ForumPanel.secondary);
      await tester.pumpAndSettle();
      for (final (index, excerpt) in [
        (0, 'Topic excerpt'),
        (1, 'DM excerpt'),
        (2, 'Category details'),
      ]) {
        final card = find.byKey(
          ValueKey('start-page-recent-closed-${closed[index]}'),
        );
        expect(
          find.descendant(of: card, matching: find.text(excerpt)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: find.byKey(ValueKey('start-page-recent-closed-${closed[1]}')),
          matching: find.byType(DAvatar),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(ValueKey('start-page-recent-closed-${closed[0]}')),
      );
      await tester.pumpAndSettle();
      expect(shell.activeTabId, closed[0]);
      expect(shell.currentContent?.topicId, 10);
    },
  );
}

void testStartPage(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(
    description,
    body,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
