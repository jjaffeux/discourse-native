import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/shell/aggregate_feed_controller.dart';
import 'package:discourse_native/src/shell/forum_settings_page.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/new_tab_page.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_filter_input.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
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

  testStartPage('All forums launches Latest, Settings and Preferences', (
    tester,
  ) async {
    const user = DiscourseUser(username: 'reader');
    final forum = instance('one.example').copyWith(user: user);
    await pumpShell(
      tester,
      desktop,
      instances: [forum],
      authenticator: FakeAuthenticator()..keys[forum.url] = 'key',
      api: FakeDiscourseApi(
        user: user,
        feeds: const {
          '/latest.json': [],
          '/filter.json?per_page=30': [
            Topic(
              id: 10,
              title: 'Across forums',
              slug: 'across',
              excerpt: 'A real preview',
            ),
          ],
          '/filter.json?per_page=30&q=in%3Anew-replies': [],
        },
      ),
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    shell.selectAggregate();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('aggregate-start-page')), findsOneWidget);
    expect(find.text('All forums'), findsOneWidget);
    expect(find.text('1 forum'), findsOneWidget);
    expect(find.text('Across forums'), findsOneWidget);
    await tester.tap(find.byTooltip('Comfortable'));
    await tester.pumpAndSettle();
    expect(find.text('A real preview'), findsOneWidget);
    await tester.tap(find.widgetWithText(DButton, 'Preferences'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-settings-modal')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-settings-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DButton, 'Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(ForumSettingsPage), findsOneWidget);
    shell.closeAggregateSettings();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DButton, 'Latest topics'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('aggregate-start-page')), findsNothing);
    expect(find.byKey(const ValueKey('aggregate-feed-mode')), findsOneWidget);
    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();
    expect(shell.aggregate.mode, AggregateFeedMode.unread);
    expect(find.text('No matching topics'), findsOneWidget);
    await tester.tap(find.byTooltip('Start page'));
    await tester.pumpAndSettle();
    expect(find.text('Across forums'), findsOneWidget);
    expect(shell.aggregate.mode, AggregateFeedMode.latest);
    await tester.tap(find.text('Across forums'));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, 10);
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
      await tester.tap(find.byKey(const ValueKey('topic-list-filter')));
      await tester.pumpAndSettle();
      expect(find.byType(TopicFilterInput), findsOneWidget);
      await tester.tap(find.widgetWithText(DToggle, 'Open topics'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DButton, 'Apply filter'));
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.topicFilterQuery, 'status:open');
      expect(find.byType(NewTabPage), findsNothing);
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
    await tester.tap(find.byKey(const ValueKey('start-page-forum-website')));
    await tester.pumpAndSettle();
    expect(launched, [shell.currentInstance!.url]);
    expect(find.byType(NewTabPage), findsOneWidget);
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
    final page = find.byType(NewTabPage);
    expect(
      find.descendant(of: page, matching: find.text('Visible category')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: page, matching: find.text('Removed category')),
      findsNothing,
    );
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
