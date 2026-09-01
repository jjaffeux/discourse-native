import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _legacyTotals = NotificationTotals(
  topicTrackingNew: 1054,
  topicTrackingUnread: 5,
);

const _unifiedTotals = NotificationTotals(topicTrackingNew: 1059);

const _user = DiscourseUser(id: 7, username: 'sam', unifiedNewEnabled: true);

const _latestTopic = Topic(id: 1, title: 'Latest topic', slug: 'latest-topic');

const _allNewTopic = Topic(
  id: 2,
  title: 'All new activity',
  slug: 'all-new-activity',
);

const _newTopic = Topic(id: 3, title: 'New topic only', slug: 'new-topic-only');

const _newReply = Topic(id: 4, title: 'New reply only', slug: 'new-reply-only');

const _unreadTopic = Topic(id: 5, title: 'Unread topic', slug: 'unread-topic');

const _topYearTopic = Topic(id: 6, title: 'Top this year', slug: 'top-year');

const _topWeekTopic = Topic(id: 7, title: 'Top this week', slug: 'top-week');

const _popularTopic = Topic(id: 8, title: 'Popular topic', slug: 'popular');

void main() {
  test('keeps New out of the connected sidebar', () {
    final site = instance('meta.discourse.org').copyWith(user: _user);
    final destinationIds = [
      for (final section in site.sections) ...[
        for (final destination in section.destinations) destination.id,
        for (final destination in section.moreDestinations) destination.id,
      ],
    ];

    expect(destinationIds, isNot(contains('new')));
  });

  test('topic-list routes round trip with the Discourse subset paths', () {
    const expectations = {
      TopicListMode.latest: (id: 'latest', path: null),
      TopicListMode.newActivity: (id: 'new', path: '/new.json'),
      TopicListMode.newTopics: (
        id: 'new-topics',
        path: '/new.json?subset=topics',
      ),
      TopicListMode.newReplies: (
        id: 'new-replies',
        path: '/new.json?subset=replies',
      ),
      TopicListMode.unread: (id: 'unread', path: '/unread.json'),
      TopicListMode.topAll: (id: 'top-all', path: '/top.json?period=all'),
      TopicListMode.topYearly: (
        id: 'top-yearly',
        path: '/top.json?period=yearly',
      ),
      TopicListMode.topQuarterly: (
        id: 'top-quarterly',
        path: '/top.json?period=quarterly',
      ),
      TopicListMode.topMonthly: (
        id: 'top-monthly',
        path: '/top.json?period=monthly',
      ),
      TopicListMode.topWeekly: (
        id: 'top-weekly',
        path: '/top.json?period=weekly',
      ),
      TopicListMode.topDaily: (id: 'top-daily', path: '/top.json?period=daily'),
      TopicListMode.popular: (id: 'hot', path: '/hot.json'),
    };

    for (final entry in expectations.entries) {
      final route = ContentRoute.topicList(entry.key);
      final restored = ContentRoute.fromJson(route.toJson());

      expect(route.id, entry.value.id);
      expect(route.feedPath, entry.value.path);
      expect(restored.id, entry.value.id);
      expect(restored.feedPath, entry.value.path);
      expect(TopicListMode.fromRoute(restored), entry.key);
    }
  });

  testWidgets(
    'waits for the unified tracking snapshot before splitting counts',
    (tester) async {
      final trackingStateGate = Completer<void>();
      final setup = await _controller(trackingStateGate: trackingStateGate);
      final controller = setup.controller;
      addTearDown(controller.dispose);
      await tester.pump();

      expect(setup.api.topicTrackingRequests, ['https://meta.discourse.org']);

      FakeSiteTracker.built.single.deliverTopicTracking(const {
        'topic_id': 4000,
        'message_type': 'unread',
        'payload': {'highest_post_number': 2, 'notification_level': 2},
      });

      expect(controller.topicListNewCounts, (all: 1059, topics: 0, replies: 0));

      trackingStateGate.complete();
      await tester.pumpAndSettle();

      expect(controller.topicListNewCounts, (
        all: 1060,
        topics: 1054,
        replies: 6,
      ));
    },
  );

  testWidgets('switches every web discovery list inside Topics', (
    tester,
  ) async {
    final setup = await _controller();
    final controller = setup.controller;
    final api = setup.api;
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: MainContent(layout: ShellLayout.compact)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('topic-list-navigation')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-list-latest')), findsOneWidget);
    expect(find.text('New (1059)'), findsOneWidget);
    expect(find.text('Unread (5)'), findsOneWidget);
    expect(find.text('Top'), findsOneWidget);
    expect(find.text('Popular'), findsOneWidget);
    expect(find.text('Latest topic'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-list-new-all')), findsNothing);
    expect(controller.sidebarBadgeFor('latest').count, 1059);

    final latestText = _tabText(tester, 'topic-list-latest');
    final newText = _tabText(tester, 'topic-list-new');
    expect(latestText.style?.fontSize, newText.style?.fontSize);
    expect(latestText.style?.fontWeight, newText.style?.fontWeight);
    expect(latestText.overflow, TextOverflow.visible);
    expect(newText.overflow, TextOverflow.visible);

    await tester.ensureVisible(find.byKey(const ValueKey('topic-list-unread')));
    await tester.tap(find.byKey(const ValueKey('topic-list-unread')));
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.unread);
    expect(find.text('Unread topic'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('topic-list-new')));

    await tester.tap(find.byKey(const ValueKey('topic-list-new')));
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.newActivity);
    expect(controller.activeTab?.rootDestinationId, 'latest');
    expect(controller.contentStack, hasLength(1));
    expect(find.text('All (1059)'), findsOneWidget);
    expect(find.text('Topics (1054)'), findsOneWidget);
    expect(find.text('Replies (5)'), findsOneWidget);
    expect(find.text('All new activity'), findsOneWidget);

    final allText = _tabText(tester, 'topic-list-new-all');
    final topicsText = _tabText(tester, 'topic-list-new-topics');
    final repliesText = _tabText(tester, 'topic-list-new-replies');
    expect(allText.style?.fontWeight, FontWeight.w400);
    expect(topicsText.style?.fontWeight, allText.style?.fontWeight);
    expect(repliesText.style?.fontWeight, allText.style?.fontWeight);
    expect(
      allText.style?.fontSize,
      lessThan(_tabText(tester, 'topic-list-new').style!.fontSize!),
    );
    expect(allText.overflow, TextOverflow.visible);
    expect(topicsText.overflow, TextOverflow.visible);
    expect(repliesText.overflow, TextOverflow.visible);

    FakeSiteTracker.built.single.deliverTopicTracking(const {
      'topic_id': 4000,
      'message_type': 'unread',
      'payload': {'highest_post_number': 2, 'notification_level': 2},
    });
    await tester.pump();

    expect(find.text('New (1060)'), findsOneWidget);
    expect(find.text('Unread (6)'), findsOneWidget);
    expect(find.text('All (1060)'), findsOneWidget);
    expect(find.text('Topics (1054)'), findsOneWidget);
    expect(find.text('Replies (6)'), findsOneWidget);
    expect(controller.sidebarBadgeFor('latest').count, 1060);

    await tester.tap(find.byKey(const ValueKey('topic-list-new-topics')));
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.newTopics);
    expect(find.text('New topic only'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('topic-list-new-replies')));
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.newReplies);
    expect(find.text('New reply only'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('topic-list-top')));
    await tester.tap(find.byKey(const ValueKey('topic-list-top')));
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.topYearly);
    expect(find.text('Top this year'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-list-top-period')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('topic-list-top-period')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.topWeekly);
    expect(find.text('Top this week'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('topic-list-popular')),
    );
    await tester.tap(find.byKey(const ValueKey('topic-list-popular')));
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.popular);
    expect(find.text('Popular topic'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-list-top-period')), findsNothing);
    expect(
      api.feedPaths,
      containsAllInOrder(const [
        '/latest.json',
        '/unread.json',
        '/new.json',
        '/new.json?subset=topics',
        '/new.json?subset=replies',
        '/top.json?period=yearly',
        '/top.json?period=weekly',
        '/hot.json',
      ]),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('topic-list-latest')));
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.latest);
    expect(find.byKey(const ValueKey('topic-list-new-all')), findsNothing);
  });

  testWidgets('primary tabs are compact, centered, and grouped on the left', (
    tester,
  ) async {
    final setup = await _controller();
    addTearDown(setup.controller.dispose);

    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ShellScope(
        controller: setup.controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: MainContent(layout: ShellLayout.expanded)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = tester.getRect(
      find.byKey(const ValueKey('topic-list-primary-row')),
    );
    final recent = tester.getRect(
      find.byKey(const ValueKey('topic-list-latest')),
    );
    final newTopics = tester.getRect(
      find.byKey(const ValueKey('topic-list-new')),
    );
    final popular = tester.getRect(
      find.byKey(const ValueKey('topic-list-popular')),
    );
    final unread = tester.getRect(
      find.byKey(const ValueKey('topic-list-unread')),
    );
    final top = tester.getRect(find.byKey(const ValueKey('topic-list-top')));
    final recentLabel = tester.getRect(find.text('Recent'));
    final newLabel = tester.getRect(find.text('New (1059)'));
    final unreadLabel = tester.getRect(find.text('Unread (5)'));
    final topLabel = tester.getRect(find.text('Top'));
    final popularLabel = tester.getRect(find.text('Popular'));

    expect(row.left, 0);
    expect(row.right, 800);
    expect(recent.left, 8);
    expect(newTopics.left, recent.right);
    expect(unread.left, newTopics.right);
    expect(top.left, unread.right);
    expect(popular.left, top.right);
    expect(popular.right, lessThan(row.right - 76));
    final tabs = [recent, newTopics, unread, top, popular];
    final labels = [recentLabel, newLabel, unreadLabel, topLabel, popularLabel];
    for (var index = 0; index < tabs.length; index++) {
      expect(tabs[index].center.dx, closeTo(labels[index].center.dx, 0.1));
      expect(tabs[index].width, lessThanOrEqualTo(labels[index].width + 24));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide shell divides the sidebar from main content', (
    tester,
  ) async {
    final setup = await _controller();
    final controller = setup.controller;
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(theme: AppTheme.dark, home: const AdaptiveShell()),
      ),
    );
    await tester.pumpAndSettle();

    final divider = find.descendant(
      of: find.byKey(const ValueKey('sidebar-resize-handle')),
      matching: find.byType(ColoredBox),
    );
    expect(divider, findsOneWidget);
    expect(tester.getSize(divider).width, 1);
    final dividerColor = tester.widget<ColoredBox>(divider).color;
    expect(dividerColor, Theme.of(tester.element(divider)).shell.divider);
    expect(tester.takeException(), isNull);
  });

  test('legacy New has no reply subset and counts only new topics', () async {
    const user = DiscourseUser(id: 8, username: 'lee');
    final setup = await _controller(user: user);
    final controller = setup.controller;
    addTearDown(controller.dispose);

    expect(controller.newActivityCount, 1054);
    expect(controller.sidebarBadgeFor('latest').count, 5);

    await controller.selectTopicListMode(TopicListMode.newReplies);

    expect(controller.currentTopicListMode, TopicListMode.latest);
    expect(setup.api.feedPaths, isNot(contains('/new.json?subset=replies')));

    await controller.selectTopicListMode(TopicListMode.newActivity);

    expect(controller.currentTopicListMode, TopicListMode.newActivity);
    expect(setup.api.feedPaths, contains('/new.json'));
  });

  test('uses the forum-configured default period when entering Top', () async {
    final setup = await _controller(
      config: const SiteConfig(topPageDefaultPeriod: 'monthly'),
    );
    addTearDown(setup.controller.dispose);

    expect(setup.controller.defaultTopTopicListMode, TopicListMode.topMonthly);
  });
}

Text _tabText(WidgetTester tester, String key) => tester.widget<Text>(
  find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)),
);

Future<({ShellController controller, FakeDiscourseApi api})> _controller({
  DiscourseUser user = _user,
  SiteConfig config = const SiteConfig.unknown(),
  Completer<void>? trackingStateGate,
}) async {
  final totals = user.unifiedNewEnabled ? _unifiedTotals : _legacyTotals;
  final site = instance(
    'meta.discourse.org',
    title: 'Discourse Meta',
  ).copyWith(user: user, notificationTotals: totals, config: config);
  final authenticator = FakeAuthenticator()..keys[site.url] = 'api-key';
  final api = FakeDiscourseApi(
    user: user,
    totals: totals,
    trackingStateGate: trackingStateGate,
    trackingState: TopicTrackingState([
      for (var index = 0; index < 1054; index++)
        TrackedTopicState(
          topicId: 1000 + index,
          highestPostNumber: 1,
          createdInNewPeriod: true,
        ),
      for (var index = 0; index < 5; index++)
        TrackedTopicState(
          topicId: 3000 + index,
          highestPostNumber: 2,
          lastReadPostNumber: 1,
          notificationLevel: 2,
        ),
    ]),
    feeds: const {
      '/latest.json': [_latestTopic],
      '/new.json': [_allNewTopic],
      '/new.json?subset=topics': [_newTopic],
      '/new.json?subset=replies': [_newReply],
      '/unread.json': [_unreadTopic],
      '/top.json?period=yearly': [_topYearTopic],
      '/top.json?period=weekly': [_topWeekTopic],
      '/hot.json': [_popularTopic],
    },
  );
  final controller = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    forumTabsEnabled: false,
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  await controller.load();
  return (controller: controller, api: api);
}
