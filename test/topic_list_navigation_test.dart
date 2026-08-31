import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _totals = NotificationTotals(topicTrackingNew: 9, topicTrackingUnread: 5);

const _user = DiscourseUser(id: 7, username: 'sam', unifiedNewEnabled: true);

const _latestTopic = Topic(id: 1, title: 'Latest topic', slug: 'latest-topic');

const _allNewTopic = Topic(
  id: 2,
  title: 'All new activity',
  slug: 'all-new-activity',
);

const _newTopic = Topic(id: 3, title: 'New topic only', slug: 'new-topic-only');

const _newReply = Topic(id: 4, title: 'New reply only', slug: 'new-reply-only');

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

  testWidgets('switches Latest and unified New lists inside Topics', (
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
    expect(find.text('New (14)'), findsOneWidget);
    expect(find.text('Latest topic'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-list-new-all')), findsNothing);
    expect(controller.sidebarBadgeFor('latest').count, 14);

    await tester.tap(find.byKey(const ValueKey('topic-list-new')));
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.newActivity);
    expect(controller.activeTab?.rootDestinationId, 'latest');
    expect(controller.contentStack, hasLength(1));
    expect(find.text('All (14)'), findsOneWidget);
    expect(find.text('Topics (9)'), findsOneWidget);
    expect(find.text('Replies (5)'), findsOneWidget);
    expect(find.text('All new activity'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('topic-list-new-topics')));
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.newTopics);
    expect(find.text('New topic only'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('topic-list-new-replies')));
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.newReplies);
    expect(find.text('New reply only'), findsOneWidget);
    expect(
      api.feedPaths,
      containsAllInOrder(const [
        '/latest.json',
        '/new.json',
        '/new.json?subset=topics',
        '/new.json?subset=replies',
      ]),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('topic-list-latest')));
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.latest);
    expect(find.byKey(const ValueKey('topic-list-new-all')), findsNothing);
  });

  test('legacy New has no reply subset and counts only new topics', () async {
    const user = DiscourseUser(id: 8, username: 'lee');
    final setup = await _controller(user: user);
    final controller = setup.controller;
    addTearDown(controller.dispose);

    expect(controller.newActivityCount, 9);
    expect(controller.sidebarBadgeFor('latest').count, 5);

    await controller.selectTopicListMode(TopicListMode.newReplies);

    expect(controller.currentTopicListMode, TopicListMode.latest);
    expect(setup.api.feedPaths, isNot(contains('/new.json?subset=replies')));

    await controller.selectTopicListMode(TopicListMode.newActivity);

    expect(controller.currentTopicListMode, TopicListMode.newActivity);
    expect(setup.api.feedPaths, contains('/new.json'));
  });
}

Future<({ShellController controller, FakeDiscourseApi api})> _controller({
  DiscourseUser user = _user,
}) async {
  final site = instance(
    'meta.discourse.org',
    title: 'Discourse Meta',
  ).copyWith(user: user, notificationTotals: _totals);
  final authenticator = FakeAuthenticator()..keys[site.url] = 'api-key';
  final api = FakeDiscourseApi(
    user: user,
    totals: _totals,
    feeds: const {
      '/latest.json': [_latestTopic],
      '/new.json': [_allNewTopic],
      '/new.json?subset=topics': [_newTopic],
      '/new.json?subset=replies': [_newReply],
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
