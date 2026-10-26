import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/user_summary.dart';
import 'package:discourse_native/src/shell/content_navigation_controls.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/global_search_filters.dart';
import 'package:discourse_native/src/shell/global_search_models.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/shell/user_summary.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show
        AxisDirection,
        Offset,
        Semantics,
        Size,
        SizedBox,
        ValueKey,
        PageStorageKey,
        RepaintBoundary,
        Scrollable,
        ScrollableState;
import 'package:flutter/rendering.dart'
    show RenderBox, RenderObject, RenderRepaintBoundary, debugOnProfilePaint;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
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
  setUpAll(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final tab in ['Highlights', 'Connections', 'Reading']) {
    testWidgets(
      'scrolling $tab reuses the summary artwork',
      (tester) async {
        await _pump(tester, size: const Size(390, 400));
        await _openSummaryFromMenu(tester);
        await _selectSummaryTab(tester, tab);
        final artwork = <RenderObject>{};
        void collect(RenderObject object) {
          artwork.add(object);
          object.visitChildren(collect);
        }

        for (final panel
            in find
                .descendant(
                  of: find.byType(UserSummaryView),
                  matching: find.byWidgetPredicate(
                    (widget) => widget is DTabPanel,
                  ),
                )
                .evaluate()) {
          collect(panel.findRenderObject()!);
        }
        expect(artwork, isNotEmpty);
        final scroll = find.descendant(
          of: find.byKey(const PageStorageKey('user-summary-scroll')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );
        final position = tester.state<ScrollableState>(scroll).position;
        expect(position.maxScrollExtent, greaterThan(80));
        final viewport = position.viewportDimension;
        final extent = position.maxScrollExtent;
        var paints = 0;
        final previous = debugOnProfilePaint;
        debugOnProfilePaint = (object) {
          previous?.call(object);
          if (artwork.contains(object)) paints++;
        };
        try {
          for (final delta in [40.0, 40.0, -40.0, -40.0]) {
            await tester.pump(const Duration(milliseconds: 450));
            final before = position.pixels;
            position.pointerScroll(delta);
            for (var frame = 0; frame < 20; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(position.pixels, closeTo(before + delta, .01));
            expect(position.viewportDimension, viewport);
            expect(position.maxScrollExtent, extent);
          }
        } finally {
          debugOnProfilePaint = previous;
        }
        expect(paints, 0, reason: 'Scrolling should composite cached artwork.');
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets('each tab scrolls its end clear of the phone dock', (
    tester,
  ) async {
    await _pump(tester, size: const Size(390, 600));
    await _openSummaryFromMenu(tester);
    for (final tab in ['Highlights', 'Connections', 'Reading']) {
      await _selectSummaryTab(tester, tab);
      final scroll = find.descendant(
        of: find.byKey(const PageStorageKey('user-summary-scroll')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      final position = tester.state<ScrollableState>(scroll).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final panel = find
          .descendant(
            of: find.byType(UserSummaryView),
            matching: find.byWidgetPredicate((widget) => widget is DTabPanel),
          )
          .evaluate()
          .map((element) => element.renderObject! as RenderBox)
          .singleWhere((box) => box.size.height > 0);
      final dock = DScrollChrome.bottomInsetOf(tester.element(scroll.first));
      expect(dock, greaterThan(0), reason: 'The phone dock floats.');
      final end = panel.localToGlobal(Offset(0, panel.size.height)).dy;
      final viewport = tester.getRect(scroll.first).bottom;
      expect(end, lessThanOrEqualTo(viewport - dock), reason: tab);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

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

            await tester.tap(
              layout.name == 'compact'
                  ? find.byTooltip('Back')
                  : find.byKey(ContentNavigationControls.backKey),
            );
            await tester.pumpAndSettle();
            expect(find.byType(UserSummaryView), findsNothing);
            // Mobile navigation keeps its content root rather than falling
            // back to the sidebar pane.
            expect(fixture.controller.currentContent?.id, 'latest');
            if (layout.name == 'compact') {
              expect(fixture.controller.mobilePane, MobilePane.content);
            }
          } finally {
            semantics.dispose();
          }
        },
        variant: TargetPlatformVariant.only(
          layout.name == 'compact'
              ? TargetPlatform.android
              : TargetPlatform.linux,
        ),
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
                destination: FeedDestination(
                  key: 'latest',
                  mode: TopicListMode.latest,
                ),
                title: 'Topics',
                icon: DIcons.layerGroup,
              ),
              ContentRoute(
                destination: PageDestination(CorePage.summary),
                title: 'Summary',
                icon: DIcons.user,
              ),
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
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  group('native destinations', () {
    testWidgets('post rows navigate to the exact post and back', (
      tester,
    ) async {
      final fixture = await _pump(tester);
      await _openSummaryFromMenu(tester);

      final reply = find.bySemanticsLabel('Open Top native reply, 3 likes');
      await tester.ensureVisible(reply);
      await tester.pumpAndSettle();
      await tester.tap(reply);
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
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    for (final layout in [
      (name: 'compact', size: const Size(390, 844)),
      (name: 'wide', size: const Size(1440, 900)),
    ]) {
      for (final count in [
        (label: 'Search 2 topics by @reader in Support', firstPosts: true),
        (label: 'Search 7 replies by @reader in Support', firstPosts: false),
      ]) {
        testWidgets(
          'category ${count.firstPosts ? 'topic' : 'reply'} counts open the '
          'web full-page search filters in ${layout.name} layout',
          (tester) async {
            final fixture = await _pump(tester, size: layout.size);
            await _openSummaryFromMenu(tester);
            await _selectSummaryTab(tester, 'Reading');
            fixture.api.pluginReadPaths.clear();

            final link = find.bySemanticsLabel(count.label);
            await tester.ensureVisible(link);
            await tester.pumpAndSettle();
            await tester.tap(link);
            await tester.pump();
            // Run past both controllers' typing debounce, so a search that is
            // only scheduled still reaches the fake API before the assertions.
            await tester.pump(const Duration(seconds: 1));
            await tester.pumpAndSettle();

            final global = fixture.controller.globalSearch;
            final expected = [
              '@reader',
              '#support',
              if (count.firstPosts) 'in:first',
            ];
            expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
            expect(global.scope, GlobalSearchScope.forum);
            expect(global.query, isEmpty);
            expect(
              global.conditions.map(
                (condition) => globalSearchConditionToken(
                  condition,
                  capabilities: global.capabilities,
                ),
              ),
              expected,
            );
            expect(
              fixture.api.pluginReadPaths
                  .map(Uri.parse)
                  .where((uri) => uri.path.startsWith('/search'))
                  .map((uri) => (uri.path, uri.queryParameters['q'])),
              [
                (
                  '/search.json',
                  [
                    ...expected,
                    // Author searches return every matching post unless the
                    // opening-post filter explicitly narrows the request.
                    if (!count.firstPosts) 'in:all-posts',
                  ].join(' '),
                ),
              ],
            );
            expect(
              fixture.api.searchesRequested,
              isEmpty,
              reason: 'nothing renders the legacy search session',
            );
          },
          variant: TargetPlatformVariant.only(TargetPlatform.linux),
        );
      }
    }

    testWidgets(
      'category counts are plain numbers for a reader who cannot search',
      (tester) async {
        final fixture = await _pump(tester);
        await _openSummaryFromMenu(tester);
        await _selectSummaryTab(tester, 'Reading');
        final link = find.bySemanticsLabel(
          'Search 2 topics by @reader in Support',
        );
        expect(link, findsOneWidget);

        // Core's `can_search` for an anonymous reader on a site with
        // `allow_anonymous_search` disabled.
        fixture.controller.search
          ..selectSite(_siteUrl, authenticated: false)
          ..allowAnonymousSearch(_siteUrl, false);
        await tester.pumpAndSettle();

        expect(link, findsNothing);
        expect(find.text('2'), findsWidgets);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  });

  group('content states', () {
    testWidgets(
      'scrollbar stays at the page edge with and without the content size limit',
      (tester) async {
        final fixture = await _pump(tester, size: const Size(2200, 480));
        // The main panel is a list column beside the secondary one; the page
        // gets the window's width once the main panel has it to itself.
        await tester.tap(
          find.byKey(const ValueKey('panel-split-view-secondary')),
        );
        await tester.pumpAndSettle();
        await _openSummaryFromMenu(tester);
        await _selectSummaryTab(tester, 'Reading');
        final page = find.byType(UserSummaryView);
        final viewport = find.byKey(
          const PageStorageKey('user-summary-scroll'),
        );
        final profile = find.byKey(const ValueKey('user-summary-profile'));
        final table = find.byType(DTable).first;
        for (final alignment in [false, true]) {
          await fixture.controller.appSettings.setLimitContentSize(alignment);
          await tester.pumpAndSettle();
          final pageBounds = tester.getRect(page);
          final contentWidth = alignment ? 825.0 : pageBounds.width - 32;
          final left = pageBounds.center.dx - contentWidth / 2;
          expect(tester.getRect(profile).left, closeTo(left, 0.001));
          expect(
            tester.getSize(table).width,
            closeTo(contentWidth - 32, 0.001),
          );
          await expectPageEdgeScrolling(
            tester,
            viewport: viewport,
            right: pageBounds.right,
            topInset: () => DPageSurface.headerGeometryOf(
              tester.element(viewport),
            )!.visibleExtent,
          );
        }
      },
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    );

    testWidgets('exposes meaningful button and value semantics', (
      tester,
    ) async {
      await _pump(tester);
      final semantics = tester.ensureSemantics();
      try {
        await _openSummaryFromMenu(tester);

        expect(find.text('Likes received'), findsOneWidget);
        expect(find.text('Likes given'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Open Top native topic, 5 likes'),
          findsOneWidget,
        );
        final milestone = find.bySemanticsLabel('Helpful, earned 2 times');
        await tester.ensureVisible(milestone);
        await tester.pump();
        expect(milestone, findsOneWidget);
        await _captureReview(tester, 'highlights');
        await _selectSummaryTab(tester, 'Connections');
        await _captureReview(tester, 'connections');
        expect(
          find.bySemanticsLabel('View profile for Sam Example, 4 replies'),
          findsOneWidget,
        );
        await _selectSummaryTab(tester, 'Reading');
        await _captureReview(tester, 'reading');
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
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('profile facts give way a whole fact at a time', (
      tester,
    ) async {
      await _pump(tester, size: const Size(2200, 600));
      await tester.tap(
        find.byKey(const ValueKey('panel-split-view-secondary')),
      );
      await tester.pumpAndSettle();
      await _openSummaryFromMenu(tester);
      final profile = find.byKey(const ValueKey('user-summary-profile'));
      Finder fact(String text) =>
          find.descendant(of: profile, matching: find.text(text));
      final handle = fact('@reader');
      final forum = fact('meta.discourse.org');
      final visits = fact('11 days visited');

      final wide = tester.getRect(profile);
      for (final shown in [handle, forum, visits]) {
        final bounds = tester.getRect(shown);
        expect(bounds.right, lessThanOrEqualTo(wide.right + .01));
        expect(bounds.center.dy, closeTo(wide.center.dy, 1));
      }

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      final narrow = tester.getRect(profile);
      final kept = tester.getRect(handle);
      expect(kept.right, lessThanOrEqualTo(narrow.right + .01));
      expect(kept.center.dy, closeTo(narrow.center.dy, 1));
      expect(
        tester.getRect(visits).top,
        greaterThanOrEqualTo(narrow.bottom),
        reason: 'a fact that no longer fits leaves the line whole',
      );
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('shows a focused empty state in each summary tab', (
      tester,
    ) async {
      await _pump(tester, summary: const UserSummary(canSeeSummaryStats: true));
      await _openSummaryFromMenu(tester);

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
      expect(find.text('<1m'), findsOneWidget);
      expect(find.text('recent read time'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(UserSummaryView),
          matching: find.text('Bookmarks'),
        ),
        findsOneWidget,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      expect(find.text('<1m'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
          if (tab == 'Connections') {
            final person = find
                .descendant(
                  of: find.byType(UserSummaryView),
                  // The handle shares the name's line, as in a table row.
                  matching: find.textContaining('Sam Example'),
                )
                .first;
            expect(
              tester.getSize(person).height,
              lessThan(80),
              reason: 'Person names must not wrap one character per line.',
            );
          }
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
          await _captureReview(tester, 'large-${size.width}-$tab');
        }
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
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
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });
}

typedef _Fixture = ({FakeDiscourseApi api, ShellController controller});

Future<void> _captureReview(WidgetTester tester, String name) async {
  final directory = Platform.environment['SUMMARY_REVIEW_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find
        .ancestor(
          of: find.byType(UserSummaryView),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

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
      hidePresence: false,
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
    tester.element(find.byType(UserMenuButton).first),
  );
  await controller.forumSettings.setShared(
    const SharedAppearance(
      font: ForumFont.openSans,
      interfaceFont: ForumFont.openSans,
    ),
  );
  await tester.pumpAndSettle();
  return (api: api, controller: controller);
}

Future<void> _openSummaryFromMenu(
  WidgetTester tester, {
  bool settle = true,
}) async {
  if (find.byKey(UserMenuButton.avatarKey).evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(UserMenuButton.avatarKey));
  await tester.pumpAndSettle();
  final summaryRow = find.byKey(const ValueKey('user-menu-row-summary'));
  expect(summaryRow, findsOneWidget);
  expect(
    find.descendant(of: summaryRow, matching: find.bySemanticsLabel('Summary')),
    findsWidgets,
  );
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
