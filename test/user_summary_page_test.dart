import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_summary.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/shell_search_controller.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/shell/user_summary_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _user = DiscourseUser(id: 7, username: 'reader', name: 'Reader Name');
const _topic = UserSummaryTopic(
  id: 42,
  title: 'A native summary topic',
  slug: 'a-native-summary-topic',
  categoryId: 7,
  likeCount: 8,
);
const _summary = UserSummary(
  canSeeSummaryStats: true,
  canSeeUserActions: true,
  likesGiven: 3,
  likesReceived: 9,
  topicsEntered: 21,
  postsRead: 84,
  daysVisited: 12,
  topicCount: 4,
  postCount: 18,
  timeRead: 8100,
  recentTimeRead: 3600,
  bookmarkCount: 2,
  topics: [_topic],
  replies: [UserSummaryReply(topic: _topic, postNumber: 4, likeCount: 2)],
  links: [
    UserSummaryLink(
      topic: _topic,
      url: 'https://example.com/useful/article',
      title: 'Useful article',
      clicks: 11,
      postNumber: 4,
    ),
  ],
  mostRepliedToUsers: [
    UserSummaryUser(username: 'alice', name: 'Alice', count: 6),
  ],
  mostLikedByUsers: [UserSummaryUser(username: 'bob', name: 'Bob', count: 5)],
  mostLikedUsers: [UserSummaryUser(username: 'carol', name: 'Carol', count: 4)],
  topCategories: [
    UserSummaryCategory(
      id: 7,
      name: 'Support',
      color: '0088CC',
      slug: 'support',
      topicCount: 3,
      postCount: 10,
    ),
  ],
  badges: [
    UserSummaryBadge(
      id: 5,
      name: 'Helpful',
      description: 'Shared a kind answer',
      icon: 'heart',
      count: 2,
    ),
  ],
);

typedef _Fixture = ({FakeDiscourseApi api, ShellController shell});

void main() {
  test('the summary content route is durable and recognizable', () {
    final encoded = jsonDecode(jsonEncode(ContentRoute.userSummary().toJson()));
    final restored = ContentRoute.fromJson(
      Map<String, dynamic>.from(encoded as Map),
    );

    expect(restored, ContentRoute.userSummary());
    expect(restored.isUserSummary, isTrue);
    expect(restored.title, 'Summary');
  });

  testWidgets(
    'the pointer Profile row opens native content and topic replies',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final semantics = tester.ensureSemantics();
      try {
        final fixture = await _pumpApp(tester);
        await _openSummaryFromMenu(tester, touch: false);

        expect(find.byType(UserMenuPanel), findsNothing);
        expect(find.byType(UserSummaryPage), findsOneWidget);
        expect(fixture.api.userSummariesRequested, [
          (siteUrl: _siteUrl, username: 'reader'),
        ]);
        expect(fixture.shell.currentContent?.isUserSummary, isTrue);
        expect(find.text('Reader Name'), findsOneWidget);
        expect(find.text('STATS'), findsOneWidget);
        expect(find.text('TOP REPLIES'), findsOneWidget);
        expect(find.text('TOP TOPICS'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('user-summary-topic-42-4')));
        await tester.pumpAndSettle();

        expect(fixture.shell.currentContent?.topicId, 42);
        expect(fixture.shell.currentContent?.postNumber, 4);
        expect(fixture.api.topicsOpened, [42]);
        expect(fixture.api.topicPostNumbersOpened, [4]);

        expect(fixture.shell.handleBack(canReturnToSidebar: false), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(UserSummaryPage), findsOneWidget);

        expect(fixture.shell.handleBack(canReturnToSidebar: false), isTrue);
        await tester.pumpAndSettle();
        expect(fixture.shell.currentContent?.isUserSummary, isFalse);
        expect(find.byType(UserSummaryPage), findsNothing);
      } finally {
        semantics.dispose();
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets('summary rows keep native and external interactions live', (
    tester,
  ) async {
    final launched = _watchBrowser(tester);
    final fixture = await _pumpApp(tester);
    fixture.shell.openUserSummary(_siteUrl);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('user-summary-external-42')),
    );
    await tester.tap(find.byKey(const ValueKey('user-summary-external-42')));
    await tester.pumpAndSettle();
    expect(launched, ['https://example.com/useful/article']);

    await tester.ensureVisible(
      find.bySemanticsLabel('Open post in A native summary topic'),
    );
    await tester.tap(
      find.bySemanticsLabel('Open post in A native summary topic'),
    );
    await tester.pumpAndSettle();
    expect(fixture.shell.currentContent?.postNumber, 4);
    fixture.shell.handleBack(canReturnToSidebar: false);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('user-summary-category-7')),
    );
    await tester.tap(find.byKey(const ValueKey('user-summary-category-7')));
    await tester.pumpAndSettle();
    expect(fixture.shell.currentContent?.id, 'category-7');
    expect(fixture.api.feedPaths.last, '/c/support/7.json');
    fixture.shell.handleBack(canReturnToSidebar: false);
    await tester.pumpAndSettle();

    final topicSearch = find.bySemanticsLabel(
      'Search 3 topics by @reader in Support',
    );
    await tester.ensureVisible(topicSearch);
    await tester.tap(topicSearch);
    await tester.pumpAndSettle();
    expect(fixture.shell.search.query, '@reader #support in:first');
    expect(fixture.shell.search.mode, SearchMode.topics);
    expect(fixture.shell.currentContent?.isUserSummary, isTrue);
  });

  testWidgets('the destination exposes named controls and responsive columns', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final semantics = tester.ensureSemantics();
    try {
      final fixture = await _pumpApp(tester);

      await tester.tap(find.byKey(UserMenuButton.avatarKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      final summaryRow = find.byKey(const ValueKey('user-menu-row-summary'));
      expect(tester.getSize(summaryRow).height, greaterThanOrEqualTo(44));
      expect(
        tester.getSemantics(summaryRow),
        isSemantics(label: 'Summary', isButton: true, hasTapAction: true),
      );
      await tester.tap(summaryRow);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.text('STATS')),
        isSemantics(label: 'STATS', isHeader: true),
      );
      expect(find.bySemanticsLabel('3 likes given'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Open reply in A native summary topic, 2 likes'),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('user-summary-topic-42-4')))
            .height,
        greaterThanOrEqualTo(44),
      );

      await tester.ensureVisible(
        find.bySemanticsLabel('View profile for @alice, 6 replies'),
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('View profile for @alice, 6 replies'),
        ),
        isSemantics(
          label: 'View profile for @alice, 6 replies',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await tester.ensureVisible(
        find.bySemanticsLabel('Helpful, earned 2 times, Shared a kind answer'),
      );
      expect(
        find.bySemanticsLabel('Helpful, earned 2 times, Shared a kind answer'),
        findsOneWidget,
      );

      // At this width the pair uses columns.
      await tester.dragUntilVisible(
        find.text('TOP REPLIES'),
        find.byType(ListView).last,
        const Offset(0, 300),
      );
      final wideReplies = tester.getTopLeft(find.text('TOP REPLIES'));
      final wideTopics = tester.getTopLeft(find.text('TOP TOPICS'));
      expect(wideReplies.dy, wideTopics.dy);

      tester.view.physicalSize = const Size(700, 900);
      await tester.pumpAndSettle();
      expect(fixture.shell.mobilePane, MobilePane.content);
      await tester.dragUntilVisible(
        find.text('TOP REPLIES'),
        find.byType(ListView).last,
        const Offset(0, 300),
      );
      final narrowReplies = tester.getTopLeft(find.text('TOP REPLIES'));
      final narrowTopics = tester.getTopLeft(find.text('TOP TOPICS'));
      expect(narrowTopics.dy, greaterThan(narrowReplies.dy));
    } finally {
      semantics.dispose();
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('touch sheets close before routing and compact Back unwinds', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final fixture = await _pumpApp(tester, size: const Size(500, 800));

      await _openSummaryFromMenu(tester, touch: true);

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(UserSummaryPage), findsOneWidget);
      expect(fixture.shell.mobilePane, MobilePane.content);

      expect(fixture.shell.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(fixture.shell.currentContent?.isUserSummary, isFalse);
      expect(fixture.shell.mobilePane, MobilePane.content);

      expect(fixture.shell.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(fixture.shell.mobilePane, MobilePane.sidebar);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('loading, error, retry, and empty states remain readable', (
    tester,
  ) async {
    final gate = Completer<void>();
    var fixture = await _pumpApp(tester, summaryGate: gate);
    fixture.shell.openUserSummary(_siteUrl);
    await tester.pump();
    expect(find.bySemanticsLabel('Loading summary'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('TOP TOPICS'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    fixture = await _pumpApp(tester, summary: null);
    fixture.shell.openUserSummary(_siteUrl);
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't load your summary"), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    fixture = await _pumpApp(tester, summary: const UserSummary());
    fixture.shell.openUserSummary(_siteUrl);
    await tester.pumpAndSettle();
    expect(find.text('STATS'), findsNothing);
    expect(find.text('No topics yet.'), findsOneWidget);
    expect(find.text('No links yet.'), findsOneWidget);
    expect(find.text('No badges yet.'), findsOneWidget);
  });

  testWidgets('a rebuilt page cannot display an obsolete controller response', (
    tester,
  ) async {
    final oldGate = Completer<void>();
    final newGate = Completer<void>();
    final oldController = await _standaloneController(
      user: const DiscourseUser(username: 'reader', name: 'Old Reader'),
      summary: const UserSummary(canSeeSummaryStats: true, likesGiven: 1),
      gate: oldGate,
    );
    final newController = await _standaloneController(
      user: const DiscourseUser(username: 'reader', name: 'New Reader'),
      summary: const UserSummary(canSeeSummaryStats: true, likesGiven: 2),
      gate: newGate,
    );
    addTearDown(oldController.dispose);
    addTearDown(newController.dispose);

    await _pumpStandalonePage(tester, oldController);
    expect(find.bySemanticsLabel('Loading summary'), findsOneWidget);

    await _pumpStandalonePage(tester, newController);
    newGate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('New Reader'), findsOneWidget);
    expect(find.bySemanticsLabel('2 likes given'), findsOneWidget);

    oldGate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Old Reader'), findsNothing);
    expect(find.bySemanticsLabel('1 likes given'), findsNothing);
  });
}

Future<_Fixture> _pumpApp(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  UserSummary? summary = _summary,
  Completer<void>? summaryGate,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final site = instance(
    'meta.example',
    title: 'Discourse Meta',
  ).copyWith(user: _user);
  final api = FakeDiscourseApi(
    user: _user,
    totals: const NotificationTotals(),
    userSummaryValue: summary,
    userSummaryGate: summaryGate,
    categoryList: const [
      TopicCategory(id: 7, name: 'Support', color: '0088CC', slug: 'support'),
    ],
    feeds: const {'/latest.json': [], '/c/support/7.json': []},
    searchResults: const {'@reader #support in:first': SearchResults()},
    topics: {
      42: topicPayload(
        id: 42,
        title: 'A native summary topic',
        posts: const [
          Post(
            id: 4204,
            postNumber: 4,
            username: 'reader',
            cooked: '<p>A reply from the summary.</p>',
          ),
        ],
      ),
    },
  );
  await tester.pumpWidget(
    DiscourseApp(
      store: FakeInstanceStore([site]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
    ),
  );
  await tester.pumpAndSettle();
  final shell = ShellScope.read(tester.element(find.byType(AdaptiveShell)));
  return (api: api, shell: shell);
}

Future<void> _openSummaryFromMenu(
  WidgetTester tester, {
  required bool touch,
}) async {
  await tester.tap(find.byKey(UserMenuButton.avatarKey));
  await tester.pumpAndSettle();
  final profileTab = find.byTooltip('Profile');
  await tester.tap(
    touch || profileTab.evaluate().isEmpty
        ? find.text('Profile').last
        : profileTab,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('user-menu-row-summary')));
  await tester.pumpAndSettle();
}

List<String> _watchBrowser(WidgetTester tester) {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'launch') {
      launched.add((call.arguments as Map)['url'] as String);
    }
    return true;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return launched;
}

Future<ShellController> _standaloneController({
  required DiscourseUser user,
  required UserSummary summary,
  required Completer<void> gate,
}) async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      totals: const NotificationTotals(),
      userSummaryValue: summary,
      userSummaryGate: gate,
      feeds: const {'/latest.json': []},
    ),
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  await controller.load();
  return controller;
}

Future<void> _pumpStandalonePage(
  WidgetTester tester,
  ShellController controller,
) => tester.pumpWidget(
  ShellScope(
    controller: controller,
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: UserSummaryPage(siteUrl: _siteUrl)),
    ),
  ),
);
