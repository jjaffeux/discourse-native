import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/user_summary.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/shell_search_controller.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/shell/user_summary.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show Semantics, Size, SizedBox, ValueKey, PageStorageKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/page_scrollbar.dart';

const _siteUrl = 'https://meta.discourse.org';
const _topTopic = UserSummaryTopic(
  id: 11,
  title: 'Top native topic',
  slug: 'top-native-topic',
  likeCount: 5,
);
const _replyTopic = UserSummaryTopic(
  id: 12,
  title: 'Top native reply',
  slug: 'top-native-reply',
);
const _person = UserSummaryUser(
  id: 21,
  username: 'sam',
  name: 'Sam Example',
  count: 4,
);
const _summary = UserSummary(
  canSeeSummaryStats: true,
  canSeeUserActions: true,
  likesGiven: 7,
  likesReceived: 8,
  topicsEntered: 9,
  postsReadCount: 10,
  daysVisited: 11,
  topicCount: 2,
  postCount: 3,
  timeRead: 100000,
  recentTimeRead: 1000,
  bookmarkCount: 1,
  topics: [_topTopic],
  replies: [UserSummaryReply(topic: _replyTopic, postNumber: 4, likeCount: 3)],
  links: [
    UserSummaryLink(
      topic: _topTopic,
      url: 'https://example.com/helpful',
      title: 'Helpful',
      clicks: 14,
      postNumber: 2,
    ),
  ],
  mostRepliedToUsers: [_person],
  mostLikedByUsers: [_person],
  mostLikedUsers: [_person],
  topCategories: [
    UserSummaryCategory(
      id: 5,
      name: 'Support',
      slug: 'support',
      color: '0088CC',
      topicCount: 2,
      postCount: 7,
    ),
  ],
  badges: [
    UserSummaryBadge(
      id: 3,
      name: 'Helpful',
      description: 'Shared something useful',
      icon: 'heart',
      count: 2,
    ),
  ],
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('duration formatting', () {
    test('matches the web summary units', () {
      expect(summaryDuration(100000), (short: '1d', long: '1 day'));
      expect(summaryDuration(1000), (short: '17m', long: '17 mins'));
      expect(summaryDuration(0), (short: '<1m', long: 'less than 1 min'));
      expect(summaryDuration(2700), (short: '1h', long: 'about 1 hour'));
      expect(summaryDuration(7776000), (short: '3mon', long: '3 months'));
    });
  });

  group('route lifecycle', () {
    for (final layout in [
      (name: 'compact', size: const Size(390, 844)),
      (name: 'wide', size: const Size(1440, 900)),
    ]) {
      testWidgets(
        'opens and closes from the profile row in ${layout.name} layout',
        (tester) async {
          final fixture = await _pump(tester, size: layout.size);
          final semantics = tester.ensureSemantics();
          try {
            await _openSummaryFromMenu(tester);

            expect(find.byType(UserMenuPanel), findsNothing);
            expect(find.byType(UserSummaryView), findsOneWidget);
            expect(fixture.api.userSummaryRequests, [
              (siteUrl: _siteUrl, username: 'reader'),
            ]);
            expect(fixture.controller.currentContent?.id, 'summary');
            expect(fixture.controller.contentStack.map((route) => route.id), [
              'latest',
              'summary',
            ]);

            await tester.tap(find.byTooltip('Back'));
            await tester.pumpAndSettle();
            expect(find.byType(UserSummaryView), findsNothing);
            expect(fixture.controller.currentContent?.id, 'latest');
            if (layout.name == 'compact') {
              expect(fixture.controller.mobilePane, MobilePane.content);
              await tester.tap(find.byTooltip('Back'));
              await tester.pumpAndSettle();
              expect(fixture.controller.mobilePane, MobilePane.sidebar);
            }
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets('loads the native destination for a restored route', (
      tester,
    ) async {
      final workspace = ForumWorkspace(
        siteUrl: _siteUrl,
        accountIdentity: 'user:reader',
        tabs: [
          ForumTab(
            id: 'restored-summary',
            rootDestinationId: 'latest',
            contentStack: const [
              ContentRoute(
                id: 'latest',
                title: 'Topics',
                icon: DIcons.layerGroup,
              ),
              ContentRoute(id: 'summary', title: 'Summary', icon: DIcons.user),
            ],
          ),
        ],
        activeTabId: 'restored-summary',
      );

      final fixture = await _pump(
        tester,
        forumTabs: FakeForumTabStore([workspace]),
      );

      expect(find.byType(UserSummaryView), findsOneWidget);
      expect(fixture.controller.currentContent?.id, 'summary');
      expect(fixture.api.userSummaryRequests, [
        (siteUrl: _siteUrl, username: 'reader'),
      ]);
    });

    testWidgets('reloads a mounted view after the account generation rotates', (
      tester,
    ) async {
      final fixture = await _pump(tester);
      await _openSummaryFromMenu(tester);

      fixture.controller.lifecycle.invalidate(_siteUrl);
      fixture.controller.userSummary.forget(_siteUrl);
      await tester.pumpAndSettle();

      expect(find.byType(UserSummaryView), findsOneWidget);
      expect(fixture.api.userSummaryRequests, [
        (siteUrl: _siteUrl, username: 'reader'),
        (siteUrl: _siteUrl, username: 'reader'),
      ]);
    });
  });

  group('native destinations', () {
    testWidgets('post rows navigate to the exact post and back', (
      tester,
    ) async {
      final fixture = await _pump(tester);
      await _openSummaryFromMenu(tester);

      await tester.tap(find.bySemanticsLabel('Open Top native reply, 3 likes'));
      await tester.pump();

      expect(fixture.controller.currentContent?.topicId, 12);
      expect(fixture.controller.currentContent?.postNumber, 4);
      expect(fixture.api.topicsOpened, [12]);
      expect(fixture.api.topicPostNumbersOpened, [4]);

      fixture.controller.handleBack(canReturnToSidebar: false);
      await tester.pumpAndSettle();
      expect(find.byType(UserSummaryView), findsOneWidget);
      expect(
        fixture.api.userSummaryRequests,
        hasLength(1),
        reason: 'the account-scoped summary stays cached when returning',
      );
    });

    testWidgets('category counts enter the web-equivalent search filters', (
      tester,
    ) async {
      final fixture = await _pump(tester);
      await _openSummaryFromMenu(tester);

      await _selectSummaryTab(tester, 'Reading');
      await tester.tap(
        find.bySemanticsLabel('Search 2 topics by @reader in Support'),
      );
      await tester.pump();

      expect(fixture.controller.search.query, '@reader #support in:first');
      expect(fixture.controller.search.mode, SearchMode.topics);
    });
  });

  group('content states', () {
    testWidgets('scrollbar stays at the page edge for each content alignment', (
      tester,
    ) async {
      final fixture = await _pump(tester, size: const Size(2200, 650));
      await _openSummaryFromMenu(tester);
      await _selectSummaryTab(tester, 'Reading');
      final page = find.byType(UserSummaryView);
      final viewport = find.byKey(const PageStorageKey('user-summary-scroll'));
      final profile = find.byKey(const ValueKey('user-summary-profile'));
      final table = find.byType(DTable);
      for (final alignment in ContentAlignment.values) {
        await fixture.controller.appSettings.setContentAlignment(alignment);
        await tester.pumpAndSettle();
        final pageBounds = tester.getRect(page);
        final left = switch (alignment) {
          ContentAlignment.left => pageBounds.left + 16,
          ContentAlignment.center => pageBounds.center.dx - 568,
          ContentAlignment.right => pageBounds.right - 16 - 1136,
        };
        expect(tester.getRect(profile).left, closeTo(left + 1, 0.001));
        expect(tester.getSize(table).width, 822);
        await expectPageEdgeScrolling(
          tester,
          viewport: viewport,
          right: pageBounds.right,
        );
      }
    }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

    testWidgets('exposes meaningful button and value semantics', (
      tester,
    ) async {
      await _pump(tester);
      final semantics = tester.ensureSemantics();
      try {
        await _openSummaryFromMenu(tester);

        expect(
          find.bySemanticsLabel('read time: 1 day, all time'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Open Top native topic, 5 likes'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Helpful'));
        await tester.pump();
        expect(
          find.bySemanticsLabel('Helpful, earned 2 times'),
          findsOneWidget,
        );
        await _selectSummaryTab(tester, 'Connections');
        expect(
          find.bySemanticsLabel('View profile for Sam Example, 4 replies'),
          findsOneWidget,
        );
        await _selectSummaryTab(tester, 'Reading');
        expect(
          find.bySemanticsLabel(
            'recent read time: 17 mins, in the last 60 days',
          ),
          findsOneWidget,
        );
        final count = tester.getSemantics(
          find.bySemanticsLabel('Search 2 topics by @reader in Support'),
        );
        expect(count.label, 'Search 2 topics by @reader in Support');
        expect(count.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('announces loading and supports retry after failure', (
      tester,
    ) async {
      final gate = Completer<void>();
      final loading = await _pump(tester, summaryGate: gate);
      final semantics = tester.ensureSemantics();
      try {
        await _openSummaryFromMenu(tester, settle: false);
        await tester.pump();

        final loadingSemantics = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Loading summary',
        );
        expect(loadingSemantics, findsOneWidget);
        final loadingWidget = tester.widget<Semantics>(loadingSemantics);
        expect(loadingWidget.container, isTrue);
        expect(loadingWidget.properties.liveRegion, isTrue);
        gate.complete();
        await tester.pumpAndSettle();
        expect(find.byType(UserSummaryView), findsOneWidget);
        expect(loading.api.userSummaryRequests, hasLength(1));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        final failed = await _pump(tester, summary: null);
        await _openSummaryFromMenu(tester);
        expect(
          find.text("Couldn't load your summary from meta.discourse.org."),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            "Couldn't load your summary from meta.discourse.org.",
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(failed.api.userSummaryRequests, hasLength(2));
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('shows a focused empty state in each summary tab', (
      tester,
    ) async {
      await _pump(tester, summary: const UserSummary(canSeeSummaryStats: true));
      await _openSummaryFromMenu(tester);

      expect(find.text('<1m'), findsOneWidget);
      expect(
        find.text('Your story starts with a conversation.'),
        findsOneWidget,
      );
      expect(find.text('No replies yet.'), findsNothing);
      expect(find.text('No topics yet.'), findsNothing);
      await _selectSummaryTab(tester, 'Connections');
      expect(find.text('No connections yet.'), findsOneWidget);
      await _selectSummaryTab(tester, 'Reading');
      expect(find.text('No links yet.'), findsOneWidget);
      expect(find.text('recent read time'), findsNothing);
      expect(find.text('Bookmarks'), findsNothing);
    });

    testWidgets('keeps contribution lists when account stats are unavailable', (
      tester,
    ) async {
      await _pump(
        tester,
        badgesEnabled: false,
        summary: UserSummary(
          topics: const [_topTopic],
          badges: _summary.badges,
        ),
      );
      await _openSummaryFromMenu(tester);
      expect(find.text('Top native topic'), findsOneWidget);
      expect(find.text('Likes received'), findsNothing);
      expect(find.text('Days visited'), findsNothing);
      expect(find.text('Your milestones'), findsNothing);
      await _selectSummaryTab(tester, 'Reading');
      expect(find.text('Time well spent'), findsNothing);
      expect(find.text('No links yet.'), findsOneWidget);
    });

    testWidgets(
      'retains the selected tab through refresh and window resizing',
      (tester) async {
        final fixture = await _pump(tester);
        await _openSummaryFromMenu(tester);
        await _selectSummaryTab(tester, 'Reading');
        await fixture.controller.userSummary.load(
          fixture.controller.currentInstance!,
          refresh: true,
        );
        await tester.pumpAndSettle();
        expect(find.text('Time well spent'), findsOneWidget);
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();
        expect(find.text('Time well spent'), findsOneWidget);
        expect(find.text('Top native reply'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    for (final size in [const Size(320, 844), const Size(768, 900)]) {
      testWidgets('fits ${size.width}px and exposes each tab at large text', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(tester, size: size);
        await _openSummaryFromMenu(tester);
        for (final tab in ['Connections', 'Reading', 'Highlights']) {
          await _selectSummaryTab(tester, tab);
          if (tab == 'Reading') {
            final category = find.descendant(
              of: find.byType(DTable),
              matching: find.text('Support'),
            );
            expect(
              tester.getSize(category).height,
              lessThan(80),
              reason: 'Category names must not wrap one character per line.',
            );
          }
          expect(tester.takeException(), isNull);
        }
        expect(find.text('Your summary'), findsNothing);
        expect(
          find.text('A little perspective on your participation.'),
          findsNothing,
        );
        expect(find.text('Your activity in this community.'), findsNothing);
        expect(find.text('All time, in one place.'), findsNothing);
        expect(find.text('Ideas you started'), findsNothing);
      });
    }

    testWidgets('returns to Reading after opening a linked topic', (
      tester,
    ) async {
      final fixture = await _pump(tester);
      await _openSummaryFromMenu(tester);
      await _selectSummaryTab(tester, 'Reading');
      final sourceTopic = find.bySemanticsLabel('Open Top native topic');
      await tester.ensureVisible(sourceTopic);
      await tester.tap(sourceTopic);
      await tester.pumpAndSettle();
      expect(fixture.controller.currentContent?.topicId, 11);
      expect(fixture.controller.currentContent?.postNumber, 2);
      fixture.controller.handleBack(canReturnToSidebar: false);
      await tester.pumpAndSettle();
      expect(find.text('Time well spent'), findsOneWidget);
      expect(fixture.api.userSummaryRequests, hasLength(1));
    });
  });
}

typedef _Fixture = ({FakeDiscourseApi api, ShellController controller});

Future<_Fixture> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  UserSummary? summary = _summary,
  Completer<void>? summaryGate,
  FakeForumTabStore? forumTabs,
  bool badgesEnabled = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final site = instance('meta.discourse.org').copyWith(
    user: const DiscourseUser(
      id: 7,
      username: 'reader',
      name: 'Reader Example',
    ),
    config: SiteConfig(badgesEnabled: badgesEnabled),
  );
  final api = FakeDiscourseApi(
    user: site.user,
    totals: const NotificationTotals(),
    summary: summary,
    userSummaryGate: summaryGate,
    feeds: const {'/latest.json': []},
  );
  final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
  await tester.pumpWidget(
    DiscourseApp(
      store: FakeInstanceStore([site]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      forumTabs: forumTabs ?? FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
    ),
  );
  await tester.pumpAndSettle();
  final controller = ShellScope.read(
    tester.element(find.byKey(UserMenuButton.avatarKey)),
  );
  return (api: api, controller: controller);
}

Future<void> _openSummaryFromMenu(
  WidgetTester tester, {
  bool settle = true,
}) async {
  await tester.tap(find.byKey(UserMenuButton.avatarKey));
  await tester.pumpAndSettle();
  final summaryRow = find.byKey(const ValueKey('user-menu-row-summary'));
  expect(summaryRow, findsOneWidget);
  expect(find.bySemanticsLabel('Summary'), findsOneWidget);
  await tester.tap(summaryRow);
  if (settle) {
    await tester.pumpAndSettle();
  }
}

Future<void> _selectSummaryTab(WidgetTester tester, String tab) async {
  final target = find.text(tab);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}
