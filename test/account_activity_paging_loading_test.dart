import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_activity.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');

enum _Page { activity, bookmarks }

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('activity backscroll restores an evicted first page', (
    tester,
  ) async {
    final site = instance('meta.discourse.org').copyWith(user: _user);
    final api = FakeDiscourseApi(
      user: _user,
      userActivityItems: [
        for (var i = 0; i < 390; i++)
          UserActivityItem(
            actionType: 4,
            topicId: i + 1,
            postNumber: 1,
            title: 'Activity $i',
            slug: 'activity',
            username: 'reader',
            excerpt: '',
          ),
      ],
    );
    await pumpShell(
      tester,
      phone,
      instances: [site],
      api: api,
      authenticator: FakeAuthenticator()..keys[_site] = 'key',
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    shell.openUserActivity(_site);
    await tester.pumpAndSettle();
    for (var i = 1; i < 11; i++) {
      await shell.accountActivity.loadUserActivity(site, loadMore: true);
    }
    await tester.pumpAndSettle();
    expect(shell.accountActivity.userActivityFor(_site).firstOffset, 30);
    final view = find.byType(UserActivityView);
    final scrollable = find
        .descendant(of: view, matching: find.byType(Scrollable))
        .last;
    tester.state<ScrollableState>(scrollable).position.jumpTo(2000);
    await tester.pumpAndSettle();
    expect(shell.accountActivity.userActivityFor(_site).firstOffset, 30);
    await tester.dragFrom(tester.getCenter(scrollable), const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(
      api.userActivityRequests.last.offset,
      0,
      reason:
          'scroll=${tester.state<ScrollableState>(scrollable).position.pixels}, '
          'requests=${api.userActivityRequests.map((request) => request.offset).toList()}',
    );
    expect(shell.accountActivity.userActivityFor(_site).firstOffset, 0);
    await tester.scrollUntilVisible(
      find.text('Activity 0'),
      -200,
      scrollable: scrollable,
    );
    expect(find.text('Activity 0').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'a single oversized activity page is read before the next replaces it',
    (tester) async {
      final site = instance('meta.discourse.org').copyWith(user: _user);
      final largeAvatar = 'x' * 75000;
      final api = FakeDiscourseApi(
        user: _user,
        userActivityItems: [
          for (var i = 0; i < 60; i++)
            UserActivityItem(
              actionType: 4,
              topicId: i + 1,
              postNumber: 1,
              title: 'Activity $i',
              slug: 'activity',
              username: 'reader',
              excerpt: '',
              avatarUrl: '$largeAvatar/$i',
            ),
        ],
      );
      await pumpShell(
        tester,
        phone,
        instances: [site],
        api: api,
        authenticator: FakeAuthenticator()..keys[_site] = 'key',
      );
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.openUserActivity(_site);
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byType(UserActivityView),
            matching: find.byType(Scrollable),
          )
          .last;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.maxScrollExtent - 500);
      await tester.pumpAndSettle();
      expect(api.userActivityRequests, hasLength(1));
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(api.userActivityRequests.map((request) => request.offset), [
        0,
        30,
      ]);
      expect(shell.accountActivity.userActivityFor(_site).retainedPageCount, 1);
      expect(find.text('Activity 30').hitTestable(), findsOneWidget);
      await tester.drag(scrollable, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(api.userActivityRequests.map((request) => request.offset), [
        0,
        30,
        0,
      ]);
      expect(
        find.text('Activity 29').hitTestable(),
        findsOneWidget,
        reason:
            'previous=${shell.accountActivity.userActivityFor(_site).window.lastPageWasPrevious} '
            'pixels=${position.pixels} max=${position.maxScrollExtent} '
            'row29=${find.text('Activity 29').evaluate().isEmpty ? 'absent' : tester.getRect(find.text('Activity 29'))}',
      );
      await tester.drag(scrollable, const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(api.userActivityRequests, hasLength(3));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('Activity filters retain pagination and open the exact reply', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      user: _user,
      userActivityItems: [
        for (var i = 1; i <= 30; i++)
          UserActivityItem(
            actionType: 4,
            topicId: i,
            postNumber: 1,
            title: 'Started $i',
            slug: 'started',
            username: 'reader',
            excerpt: '',
          ),
        const UserActivityItem(
          actionType: 5,
          topicId: 50,
          postNumber: 8,
          title: 'A later reply',
          slug: 'later',
          username: 'reader',
          excerpt: 'Answer',
        ),
      ],
    );
    await pumpShell(
      tester,
      phone,
      instances: [instance('meta.discourse.org').copyWith(user: _user)],
      api: api,
      authenticator: FakeAuthenticator()..keys[_site] = 'key',
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    shell.openUserActivity(_site);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-kind-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replies').last);
    await tester.pumpAndSettle();
    expect(find.text('Started 1'), findsNothing);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('A later reply'), findsOneWidget);
    expect(find.text('Replied'), findsOneWidget);
    await tester.tap(find.text('A later reply'));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, 50);
    expect(shell.currentContent?.postNumber, 8);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  for (final page in _Page.values) {
    testWidgets(
      'mobile ${page.name} retains rows with a visible next-page skeleton',
      (tester) async {
        final completion = Completer<void>();
        addTearDown(() {
          if (!completion.isCompleted) completion.complete();
        });
        final site = instance('meta.discourse.org').copyWith(user: _user);
        final api = _PagingApi(completion);
        await pumpShell(
          tester,
          phone,
          instances: [site],
          api: api,
          authenticator: FakeAuthenticator()..keys[_site] = 'key',
        );
        final shell = ShellScope.read(
          tester.element(find.byType(MainContent, skipOffstage: false).first),
        );
        if (page == _Page.activity) {
          shell.openUserActivity(_site);
        } else {
          shell.selectDestination(
            const SidebarDestination(
              id: 'user-bookmarks',
              label: 'Bookmarks',
              icon: DIcons.bookmark,
            ),
          );
        }
        await tester.pumpAndSettle();
        final view = find.byType(
          page == _Page.activity ? UserActivityView : BookmarkSection,
        );
        expect(view, findsOneWidget);
        final scrollable = find
            .descendant(of: view, matching: find.byType(Scrollable))
            .last;
        final pageSize = page == _Page.activity ? 30 : 20;
        final prefix = page == _Page.activity ? 'Activity' : 'Bookmark';
        await tester.scrollUntilVisible(
          find.text('$prefix $pageSize'),
          400,
          scrollable: scrollable,
        );
        await tester.drag(scrollable, const Offset(0, -250));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        if (page == _Page.activity) {
          expect(api.userActivityRequests.map((request) => request.offset), [
            0,
            30,
          ]);
          expect(shell.accountActivity.userActivityFor(_site).loading, isTrue);
          expect(
            shell.accountActivity.userActivityFor(_site).items,
            hasLength(30),
          );
        } else {
          expect(api.bookmarkListRequests.map((request) => request.page), [
            0,
            1,
          ]);
          expect(shell.accountActivity.bookmarkListFor(_site).loading, isTrue);
          expect(
            shell.accountActivity.bookmarkListFor(_site).bookmarks,
            hasLength(20),
          );
        }
        expect(find.text('$prefix $pageSize'), findsOneWidget);
        final skeleton = find.byType(DSkeletonRegion);
        expect(skeleton, findsOneWidget);
        expect(find.byType(DSkeleton), findsWidgets);
        expect(find.byType(DSpinner), findsNothing);
        final bounds = tester.getRect(skeleton);
        final viewport = tester.getRect(scrollable);
        expect(bounds.height, greaterThan(60));
        expect(bounds.top, lessThan(viewport.bottom));
        expect(bounds.bottom, greaterThan(viewport.top));
        expect(tester.takeException(), isNull);
        final semantics = tester.ensureSemantics();
        try {
          await tester.pump();
          expect(
            tester.getSemantics(skeleton),
            isSemantics(
              label: page == _Page.activity
                  ? 'Loading more activity'
                  : 'Loading more bookmarks',
              isLiveRegion: true,
            ),
          );
        } finally {
          semantics.dispose();
        }

        completion.complete();
        await tester.pumpAndSettle();
        expect(find.byType(DSkeletonRegion), findsNothing);
        await tester.scrollUntilVisible(
          find.text('$prefix ${pageSize + 1}'),
          200,
          scrollable: scrollable,
        );
        expect(find.text('$prefix ${pageSize + 1}'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }
}

class _PagingApi extends FakeDiscourseApi {
  _PagingApi(this.completion)
    : super(
        user: _user,
        feeds: const {'/latest.json': []},
        userActivityItems: [
          for (var id = 1; id <= 31; id++)
            UserActivityItem(
              actionType: 4,
              topicId: id,
              postNumber: 1,
              title: 'Activity $id',
              slug: 'activity-$id',
              username: 'reader',
              excerpt: '',
            ),
        ],
        bookmarkList: [
          for (var id = 1; id <= 21; id++)
            Bookmark(
              id: id,
              bookmarkableType: 'Topic',
              title: 'Bookmark $id',
              path: '/t/bookmark-$id/$id',
            ),
        ],
      );
  final Completer<void> completion;

  @override
  Future<UserActivityPage> userActivity({
    required String siteUrl,
    required String apiKey,
    required String username,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    final page = await super.userActivity(
      siteUrl: siteUrl,
      apiKey: apiKey,
      username: username,
      offset: offset,
      limit: limit,
      clientId: clientId,
    );
    if (offset > 0) await completion.future;
    return page;
  }

  @override
  Future<BookmarkListPage> bookmarkListPage({
    required String siteUrl,
    required String apiKey,
    required String username,
    int page = 0,
    String? clientId,
  }) async {
    final result = await super.bookmarkListPage(
      siteUrl: siteUrl,
      apiKey: apiKey,
      username: username,
      page: page,
      clientId: clientId,
    );
    if (page > 0) await completion.future;
    return result;
  }
}
