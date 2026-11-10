import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart'
    show
        NotificationPresentation,
        PluginDescriptor,
        PluginId,
        PluginInstaller,
        PluginManifest,
        PluginModule,
        PluginNotificationPresentationContext,
        PluginNotificationPresentationStrategy,
        PluginRegistrar,
        PluginSessionContribution,
        PluginSessionLifecycle,
        ResolvedNotification;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/skeleton_expectations.dart';

const _site = 'https://meta.example';
const _user = DiscourseUser(username: 'reader');
const _longTitle = 'Anyone else using Obsidian for grocery lists? No? Just me?';
const _bookmarks = [
  Bookmark(
    id: 1,
    bookmarkableType: 'Post',
    postNumber: 2,
    categoryId: 1,
    title: 'Show & tell: houseplant shelfie thread 🌿',
    author: 'alice',
    path: '/t/plants/7/2',
  ),
  Bookmark(
    id: 2,
    bookmarkableType: 'Post',
    postNumber: 4,
    categoryId: 2,
    title: _longTitle,
    path: '/t/obsidian/8/4',
  ),
  Bookmark(
    id: 3,
    bookmarkableType: 'Chat::Message',
    title: 'travel',
    author: 'flourpower',
    path: '/chat/c/travel/9/123',
  ),
  Bookmark(
    id: 4,
    bookmarkableType: 'Topic',
    categoryId: 1,
    title: 'Best cities for remote work in Europe right now?',
    path: '/t/remote/10',
  ),
  Bookmark(
    id: 5,
    bookmarkableType: 'ChatMessage',
    title: 'general',
    author: 'reader',
    path: '/chat/c/general/11/124',
  ),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('reminder scopes narrow the rows and accent expired ones', (
    tester,
  ) async {
    final now = DateTime.now();
    final shell = await _shell(
      bookmarks: [
        _bookmarks[0].copyWith(
          reminderAt: now.subtract(const Duration(days: 1)),
        ),
        _bookmarks[1].copyWith(reminderAt: now.add(const Duration(days: 1))),
        _bookmarks[3].copyWith(
          reminderAt: now.subtract(const Duration(minutes: 1)),
        ),
        _bookmarks[2],
      ],
    );
    addTearDown(shell.dispose);
    await _pumpPage(tester, shell, size: const Size(320, 844), scale: 1.5);
    final expired = _pageItem(tester, 'bookmark-row-1');
    expect(expired.selected, isTrue);
    expect(expired.selectionStyle, DItemSelectionStyle.leadingAccent);
    expect(expired.showSelectionIndicator, isFalse);
    expect(expired.semanticLabel, contains('Reminder expired'));
    expect(_pageItem(tester, 'bookmark-row-2').selected, isFalse);
    await _reminderFilter(tester, 'Reminders');
    expect(find.byType(BookmarkRow), findsNWidgets(3));
    await _reminderFilter(tester, 'Expired');
    expect(find.byType(BookmarkRow), findsNWidgets(2));
    expect(find.text('flourpower in #travel'), findsNothing);
    await _reminderFilter(tester, 'All bookmarks');
    expect(find.text('flourpower in #travel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired filter reads pages until a matching reminder is found', (
    tester,
  ) async {
    final bookmarks = _numbered(45);
    bookmarks[44] = bookmarks[44].copyWith(reminderAt: DateTime.utc(2000));
    final api = FakeDiscourseApi(user: _user, bookmarkList: bookmarks);
    final shell = await _shell(api: api);
    addTearDown(shell.dispose);
    await _pumpPage(tester, shell);
    await _reminderFilter(tester, 'Expired');
    expect(find.byType(BookmarkRow), findsOneWidget);
    expect(find.byKey(const ValueKey('bookmark-row-45')), findsOneWidget);
    expect(api.bookmarkListRequests.map((request) => request.page), [0, 1, 2]);
  });

  testWidgets(
    'empty filters pause automatic scans and retain explicit continuation',
    (tester) async {
      final api = FakeDiscourseApi(user: _user, bookmarkList: _numbered(1000));
      final shell = await _shell(api: api);
      addTearDown(shell.dispose);
      await _pumpPage(tester, shell);
      await _reminderFilter(tester, 'Expired');
      final count = api.bookmarkListRequests.length;
      expect(count, lessThanOrEqualTo(4));
      expect(find.text('Nothing bookmarked here.'), findsNothing);
      expect(find.text('Load more').hitTestable(), findsOneWidget);
      await tester.pumpAndSettle();
      expect(api.bookmarkListRequests, hasLength(count));
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(api.bookmarkListRequests.length, greaterThan(count));
      expect(api.bookmarkListRequests.length, lessThanOrEqualTo(count + 4));
      expect(find.text('Load more').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing a filter after eviction restores earlier matches', (
    tester,
  ) async {
    final bookmarks = _numbered(400);
    bookmarks[0] = bookmarks[0].copyWith(reminderAt: DateTime.utc(2000));
    final api = FakeDiscourseApi(user: _user, bookmarkList: bookmarks);
    final shell = await _shell(api: api);
    addTearDown(shell.dispose);
    await _pumpPage(tester, shell);
    for (var page = 1; page < 14; page++) {
      await shell.loadBookmarkList(_site, loadMore: true);
    }
    await tester.pumpAndSettle();
    expect(shell.accountActivity.bookmarkListFor(_site).hasPrevious, isTrue);
    await _reminderFilter(tester, 'Expired');
    expect(api.bookmarkListRequests.last.page, lessThan(4));
    expect(find.byKey(const ValueKey('bookmark-row-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(1440, 1200)]) {
    testWidgets('bookmark skeleton fills the page at $size', (tester) async {
      final api = _DelayedBookmarksApi();
      final shell = await _shell(api: api);
      addTearDown(shell.dispose);
      final semantics = tester.ensureSemantics();
      await _pumpPage(tester, shell, size: size, settle: false);

      expectSkeletonFillsViewport(
        tester,
        label: 'Loading bookmarks',
        bottom: size.height,
      );
      expect(find.bySemanticsLabel('Loading bookmarks'), findsOneWidget);
      expect(find.text('Bookmarks'), findsOneWidget);
      expect(find.byType(DSelect<BookmarkReminderFilter>), findsOneWidget);

      api.bookmarksGate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(DSkeletonRegion), findsNothing);
      expect(find.byType(BookmarkRow), findsNWidgets(_bookmarks.length));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  for (final size in [const Size(390, 844), const Size(1080, 810)]) {
    testWidgets(
      'bookmark page heads its rows with one scope at ${size.width}px',
      (tester) async {
        final shell = await _shell();
        addTearDown(shell.dispose);
        await _pumpPage(
          tester,
          shell,
          size: size,
          scale: size.width < 600 ? 1.2 : 1,
        );

        expect(find.text('Bookmarks'), findsOneWidget);
        expect(find.text('Post #2 · plants'), findsOneWidget);
        expect(find.text('Post #4 · pkm'), findsOneWidget);
        expect(find.text('flourpower in #travel'), findsOneWidget);
        expect(find.text('Chat · travel'), findsOneWidget);
        expect(find.text('you in #general'), findsOneWidget);
        expect(find.byType(BookmarkRow), findsNWidgets(5));
        expect(find.byWidgetPredicate((widget) => widget is DSelect), findsOne);
        final titleRect = tester.getRect(find.text('Bookmarks'));
        final selectRect = tester.getRect(
          find.byType(DSelect<BookmarkReminderFilter>),
        );
        expect(titleRect.bottom, lessThan(selectRect.top));
        expect(selectRect.width, lessThan(size.width / 2));
        expect(
          tester
              .getRect(find.byKey(const Key('d-select-trigger-visual')).first)
              .left,
          titleRect.left,
        );
        expect(
          selectRect.bottom,
          lessThan(tester.getRect(find.byType(BookmarkRow).first).top),
        );

        await tester.tap(find.byKey(const ValueKey('bookmark-row-1')));
        await tester.pumpAndSettle();
        expect(shell.currentContent?.topicId, 7);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final limited in [true, false]) {
    testWidgets('rows follow the content width setting (limited: $limited)', (
      tester,
    ) async {
      final shell = await _shell(
        bookmarks: [
          _bookmarks[0].copyWith(
            reminderAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
          _bookmarks[1].copyWith(name: 'Try this with the weekly meal plan'),
        ],
      );
      addTearDown(shell.dispose);
      await _pumpPage(
        tester,
        shell,
        size: const Size(1440, 900),
        limitContentSize: limited,
      );

      final title = tester.getRect(find.text('Bookmarks'));
      final row = tester.getRect(find.byKey(const ValueKey('bookmark-row-1')));
      final media = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('bookmark-row-1')),
          matching: find.byType(DItemMedia),
        ),
      );
      expect(row.width, (limited ? DPageReadingLane.maxWidth : 1440) - 32);
      expect(row.center.dx, 720);
      expect(row.left, title.left);
      expect(media.left, row.left + 3);
      expect(
        find.text('Try this with the weekly meal plan · Post #4 · pkm'),
        findsOneWidget,
      );
      expect(find.byType(DTooltip), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a bookmark in the open topic moves the reader to its post', (
    tester,
  ) async {
    final shell = await _shell();
    addTearDown(shell.dispose);
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'plants', title: 'Plants'),
    );
    final stackLength = shell.contentStack.length;
    final revision = shell.topicNavigationRevision;
    var opened = 0;
    await _pumpPage(tester, shell, onOpened: () => opened++);

    await tester.tap(find.byKey(const ValueKey('bookmark-row-1')));
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(shell.currentContent?.topicId, 7);
    expect(shell.currentContent?.postNumber, 2);
    expect(shell.contentStack, hasLength(stackLength));
    expect(shell.topicNavigationRevision, revision + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text and RTL keep the complete bookmark title', (
    tester,
  ) async {
    final shell = await _shell();
    addTearDown(shell.dispose);
    await _pumpPage(
      tester,
      shell,
      size: const Size(320, 844),
      scale: 2,
      rtl: true,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(_longTitle));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text(_longTitle),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.width, lessThanOrEqualTo(320));
  });

  testWidgets('a phone row sets its disc beside a title of two lines', (
    tester,
  ) async {
    final shell = await _shell(
      bookmarks: [
        _bookmarks[1].copyWith(
          name: 'Plan',
          reminderAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ],
    );
    addTearDown(shell.dispose);
    await _pumpPage(tester, shell, size: const Size(390, 844));

    final row = find.byKey(const ValueKey('bookmark-row-2'));
    final rowRect = tester.getRect(row);
    final disc = tester.getRect(
      find.descendant(of: row, matching: find.byType(DItemMedia)),
    );
    final glyph = tester.getRect(
      find.descendant(of: row, matching: find.byType(DIcon)),
    );
    final title = tester.getRect(find.text(_longTitle));
    final details = find.text('Plan · Post #4 · pkm');
    final detailsRect = tester.getRect(details);

    expect(disc.size, const Size.square(34));
    expect(glyph.size, const Size.square(14));
    expect(glyph.center, disc.center);
    expect(disc.left, rowRect.left + 3);
    expect(title.left, disc.right + 10);
    expect(title.top, rowRect.top + 12);
    expect(
      tester.renderObject<RenderParagraph>(find.text(_longTitle)).maxLines,
      2,
    );
    // The test engine sets each line on a whole pixel.
    expect(title.height, moreOrLessEquals(2 * 14.5 * 1.35, epsilon: 1));
    expect(detailsRect.top, title.bottom);
    expect(detailsRect.height, moreOrLessEquals(12.5 * 1.5, epsilon: 1));
    expect(rowRect.bottom, moreOrLessEquals(detailsRect.bottom + 14));
    expect(
      disc.center.dy,
      moreOrLessEquals(title.top / 2 + detailsRect.bottom / 2),
    );
    expect(find.text('Reminder expired'), findsNothing);
    expect(
      _pageItem(tester, 'bookmark-row-2').semanticLabel,
      contains('Reminder expired'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a scope with nothing in it says so and can return to all', (
    tester,
  ) async {
    final shell = await _shell(bookmarks: [_bookmarks.first]);
    addTearDown(shell.dispose);
    await _pumpPage(tester, shell, size: const Size(390, 844));
    final heading = tester.getRect(find.text('Bookmarks'));
    await _reminderFilter(tester, 'Reminders');

    final message = find.text('Nothing bookmarked here.');
    final paragraph = tester.renderObject<RenderParagraph>(message);
    expect(tester.getRect(message).left, heading.left);
    expect(paragraph.text.style?.fontSize, 13.5);
    expect(
      tester.getRect(message).height,
      moreOrLessEquals(13.5 * 1.5, epsilon: 1),
    );
    await _reminderFilter(tester, 'All bookmarks');
    expect(find.byType(BookmarkRow), findsOneWidget);
  });

  testWidgets('empty and failed feeds retain the page heading and filter', (
    tester,
  ) async {
    for (final bookmarks in [<Bookmark>[], null]) {
      final shell = await _shell(bookmarks: bookmarks);
      await _pumpPage(tester, shell);
      expect(find.text('Bookmarks'), findsOneWidget);
      expect(find.byType(DSelect<BookmarkReminderFilter>), findsOneWidget);
      expect(
        find.text(bookmarks == null ? 'Retry' : 'Nothing bookmarked here.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      shell.dispose();
    }
  });

  testWidgets('the page scrolls through every bookmark, past the menu route', (
    tester,
  ) async {
    final api = FakeDiscourseApi(user: _user, bookmarkList: _numbered(60));
    final shell = await _shell(api: api);
    addTearDown(shell.dispose);
    await _pumpPage(tester, shell);

    // One core page fills the window, so nothing more is read until the
    // reader scrolls toward the end.
    expect(api.bookmarkListRequests.map((request) => request.page), [0]);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('bookmark-row-60')),
      400,
      scrollable: _pageScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('bookmark-row-60')), findsOneWidget);
    expect(api.bookmarkListRequests, [
      (username: 'reader', page: 0),
      (username: 'reader', page: 1),
      (username: 'reader', page: 2),
    ]);
    // The menu's twenty-row route is not what the page reads.
    expect(api.bookmarksRequested, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a filter reads on through pages holding none of its rows', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      user: _user,
      bookmarkList: _numbered(45, reminders: {41, 42, 43, 44, 45}),
    );
    final shell = await _shell(api: api);
    addTearDown(shell.dispose);
    await _pumpPage(tester, shell);
    expect(api.bookmarkListRequests.map((request) => request.page), [0]);

    await _reminderFilter(tester, 'Reminders');

    expect(find.text('Nothing bookmarked here.'), findsNothing);
    expect(find.byType(BookmarkRow), findsNWidgets(5));
    expect(find.byKey(const ValueKey('bookmark-row-41')), findsOneWidget);
    expect(api.bookmarkListRequests.map((request) => request.page), [0, 1, 2]);

    await _reminderFilter(tester, 'All bookmarks');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('bookmark-row-40')),
      400,
      scrollable: _pageScrollable,
    );
    expect(find.byKey(const ValueKey('bookmark-row-40')), findsOneWidget);
    expect(api.bookmarkListRequests, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed page keeps its rows and is retried from its row', (
    tester,
  ) async {
    final api = _FailingPageApi(bookmarkList: _numbered(30));
    final shell = await _shell(api: api);
    addTearDown(shell.dispose);
    await _pumpPage(tester, shell);

    await tester.scrollUntilVisible(
      find.text('Retry'),
      400,
      scrollable: _pageScrollable,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't reach"), findsOneWidget);
    expect(find.byKey(const ValueKey('bookmark-row-20')), findsOneWidget);

    // Reaching the end again does not resend a failed page by itself.
    await tester.drag(_pageScrollable, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(api.bookmarkListRequests.map((request) => request.page), [0, 1]);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('bookmark-row-30')),
      400,
      scrollable: _pageScrollable,
    );

    expect(find.text('Retry'), findsNothing);
    expect(api.bookmarkListRequests.map((request) => request.page), [0, 1, 1]);
    expect(tester.takeException(), isNull);
  });

  test(
    'chat presentation uses the bookmark site and handles unknown channels',
    () async {
      final shell = await _shell();
      addTearDown(shell.dispose);
      final presenter = shell.pluginSession
          .capabilities<PluginBookmarkPresenter>()
          .single;
      expect(presenter.presentBookmark(_site, _bookmarks.first), isNull);
      expect(
        presenter.presentBookmark(_site, _bookmarks[2])?.color,
        const Color(0xff8f63b8),
      );
      expect(
        presenter.presentBookmark(_site, _bookmarks.last)?.title,
        'you in #general',
      );
      expect(
        presenter
            .presentBookmark('https://other.example', _bookmarks.last)
            ?.title,
        'reader in #general',
      );
      expect(
        presenter.presentBookmark(_site, _bookmarks.last)?.icon,
        DIcons.comment,
      );
    },
  );
  group('without a feed change the open page', () {
    testWidgets('shows and drops a place bookmarked elsewhere', (tester) async {
      const place = ContentRoute(
        destination: PageDestination(CorePage.preferences),
        title: 'Preferences',
        icon: DIcons.gear,
      );
      final shell = await _shell();
      addTearDown(shell.dispose);
      await _pumpPage(tester, shell);
      expect(find.text('Preferences'), findsNothing);

      await tester.runAsync(
        () => shell.accountDestinationBookmarks
            .actionFor(place, siteUrl: _site)!
            .invoke(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Preferences'), findsOneWidget);

      await tester.runAsync(
        () => shell.accountDestinationBookmarks
            .actionFor(place, siteUrl: _site)!
            .invoke(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Preferences'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('names a renamed category on its rows', (tester) async {
      final categories = [
        const TopicCategory(id: 1, name: 'plants', color: '0088CC'),
        const TopicCategory(id: 2, name: 'pkm', color: 'BB7733'),
      ];
      final api = FakeDiscourseApi(
        user: _user,
        bookmarkList: _bookmarks,
        categoryList: categories,
      );
      final shell = await _shell(api: api);
      addTearDown(shell.dispose);
      await _pumpPage(tester, shell);
      expect(find.text('Post #2 · plants'), findsOneWidget);

      categories[0] = const TopicCategory(
        id: 1,
        name: 'indoor plants',
        color: '0088CC',
      );
      await tester.runAsync(() => shell.loadCategories(_site, force: true));
      await tester.pumpAndSettle();

      expect(find.text('Post #2 · indoor plants'), findsOneWidget);
      expect(find.text('Post #2 · plants'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('names a renamed channel on its chat rows', (tester) async {
      final shell = await _shell();
      addTearDown(shell.dispose);
      await _pumpPage(tester, shell);
      expect(find.text('flourpower in #travel'), findsOneWidget);

      shell.pluginSession
          .require(chatShellService)
          .store
          .put(
            _site,
            const ChatChannel(
              id: 9,
              title: 'journeys',
              kind: ChatChannelKind.category,
              categoryColor: Color(0xff8f63b8),
            ),
          );
      shell.notifyPluginStateChanged();
      await tester.pumpAndSettle();

      expect(find.text('flourpower in #journeys'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reloads and clears its filters for a new account', (
      tester,
    ) async {
      final api = FakeDiscourseApi(user: _user, bookmarkList: _bookmarks);
      final shell = await _shell(api: api);
      addTearDown(shell.dispose);
      await _pumpPage(tester, shell);
      await _reminderFilter(tester, 'Reminders');
      expect(find.byType(BookmarkRow), findsNothing);
      expect(api.bookmarkListRequests, hasLength(1));

      shell.lifecycle.invalidate(_site);
      shell.notifyPluginStateChanged();
      await tester.pumpAndSettle();

      expect(api.bookmarkListRequests, hasLength(2));
      expect(find.byType(BookmarkRow), findsNWidgets(_bookmarks.length));
      expect(tester.takeException(), isNull);
    });

    testWidgets('pages on when its window grows', (tester) async {
      final api = FakeDiscourseApi(user: _user, bookmarkList: _numbered(45));
      final shell = await _shell(api: api);
      addTearDown(shell.dispose);
      await _pumpPage(tester, shell, size: const Size(1080, 400));
      expect(api.bookmarkListRequests.map((request) => request.page), [0]);

      tester.view.physicalSize = const Size(1080, 9000);
      await tester.pumpAndSettle();

      expect(api.bookmarkListRequests.map((request) => request.page), [
        0,
        1,
        2,
      ]);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a bookmark saved elsewhere reaches the open page', (
    tester,
  ) async {
    final bookmarks = [..._bookmarks];
    final api = FakeDiscourseApi(user: _user, bookmarkList: bookmarks);
    final shell = await _shell(api: api);
    addTearDown(shell.dispose);
    await _pumpPage(tester, shell);
    expect(find.text('Saved from a topic'), findsNothing);

    bookmarks.insert(
      0,
      const Bookmark(
        id: 90,
        bookmarkableId: 77,
        bookmarkableType: 'Topic',
        title: 'Saved from a topic',
        path: '/t/saved/77',
      ),
    );
    await tester.runAsync(() => shell.loadBookmarkList(_site, refresh: true));
    await tester.pumpAndSettle();

    expect(find.text('Saved from a topic'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('the open tab', () {
    testWidgets('shows a place bookmarked elsewhere', (tester) async {
      const place = ContentRoute(
        destination: PageDestination(CorePage.preferences),
        title: 'Preferences',
        icon: DIcons.gear,
      );
      final shell = await _shell();
      addTearDown(shell.dispose);
      await _pumpTab(tester, shell);
      expect(find.text('Preferences'), findsNothing);

      await tester.runAsync(
        () => shell.accountDestinationBookmarks
            .actionFor(place, siteUrl: _site)!
            .invoke(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Preferences'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('redraws a reminder a plugin presents anew', (tester) async {
      final strategy = _ReminderStrategy();
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.example').copyWith(user: _user),
        ]),
        api: FakeDiscourseApi(
          user: _user,
          bookmarkList: const [],
          reminderList: const [
            DiscourseNotification.test(
              id: 41,
              typeId: NotificationTypeId(24),
              title: 'Better image handling',
              topicId: 7,
              slug: 'better-image-handling',
            ),
          ],
        ),
        authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        plugins: PluginInstaller.install(
          PluginManifest([_ReminderModule(strategy)]),
        ),
      );
      addTearDown(shell.dispose);
      await shell.load();
      await _pumpTab(tester, shell);
      expect(find.textContaining('Noted by a plugin'), findsNothing);

      strategy.enabled = true;
      shell.notifyPluginStateChanged();
      await tester.pumpAndSettle();

      expect(find.textContaining('Noted by a plugin'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('accents a reminder that falls due at the next notification', (
      tester,
    ) async {
      final due = DateTime.now().add(const Duration(seconds: 2));
      final shell = await _shell(
        bookmarks: [_bookmarks[0].copyWith(reminderAt: due)],
      );
      addTearDown(shell.dispose);
      await _pumpTab(tester, shell);
      DItem row() =>
          tester.widget<DItem>(find.byKey(const ValueKey('bookmark-row-1')));
      expect(row().selected, isFalse);

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2100)),
      );
      shell.notifyPluginStateChanged();
      await tester.pumpAndSettle();

      expect(row().selected, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}

final _pageScrollable = find.descendant(
  of: find.byType(CustomScrollView),
  matching: find.byType(Scrollable),
);

final class _ReminderModule implements PluginModule {
  const _ReminderModule(this.strategy);

  final _ReminderStrategy strategy;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('reminder-presentation'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession(
      (_, _) => PluginSessionContribution(
        lifecycle: _ReminderLifecycle(),
        capabilities: [strategy],
      ),
    );
  }
}

final class _ReminderLifecycle extends PluginSessionLifecycle {}

final class _ReminderStrategy
    implements PluginNotificationPresentationStrategy {
  bool enabled = false;

  @override
  ResolvedNotification? resolveNotification(
    PluginNotificationPresentationContext context,
  ) => enabled
      ? ResolvedNotification(
          presentation: NotificationPresentation(
            icon: context.fallback.presentation.icon,
            phrase: 'Noted by a plugin',
            subject: 'Noted by a plugin',
          ),
          path: context.fallback.path,
        )
      : null;
}

/// Post bookmarks, except for the [topics] ids.
List<Bookmark> _numbered(int count, {Set<int> reminders = const {}}) => [
  for (var id = 1; id <= count; id++)
    Bookmark(
      id: id,
      bookmarkableType: 'Post',
      postNumber: 2,
      categoryId: 1,
      title: 'Bookmark $id',
      path: '/t/bookmark-$id/$id',
      reminderAt: reminders.contains(id) ? DateTime.utc(2100) : null,
    ),
];

/// Answers the first request for a second page as an unreachable site.
final class _FailingPageApi extends FakeDiscourseApi {
  _FailingPageApi({super.bookmarkList}) : super(user: _user);

  var _failed = false;

  @override
  Future<BookmarkListPage> bookmarkListPage({
    required String siteUrl,
    required String apiKey,
    required String username,
    int page = 0,
    String? clientId,
  }) {
    if (page == 0 || _failed) {
      return super.bookmarkListPage(
        siteUrl: siteUrl,
        apiKey: apiKey,
        username: username,
        page: page,
        clientId: clientId,
      );
    }
    _failed = true;
    bookmarkListRequests.add((username: username, page: page));
    return Future.error(
      SiteLookupException(SiteLookupFailure.unreachable, siteUrl),
    );
  }
}

final class _DelayedBookmarksApi extends FakeDiscourseApi {
  _DelayedBookmarksApi() : super(user: _user, bookmarkList: _bookmarks);

  final bookmarksGate = Completer<void>();

  @override
  Future<BookmarkListPage> bookmarkListPage({
    required String siteUrl,
    required String apiKey,
    required String username,
    int page = 0,
    String? clientId,
  }) async {
    await bookmarksGate.future;
    return super.bookmarkListPage(
      siteUrl: siteUrl,
      apiKey: apiKey,
      username: username,
      page: page,
      clientId: clientId,
    );
  }
}

Future<ShellController> _shell({
  List<Bookmark>? bookmarks = _bookmarks,
  FakeDiscourseApi? api,
}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: _user),
    ]),
    api: api ?? FakeDiscourseApi(user: _user, bookmarkList: bookmarks),
    authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
  );
  await shell.load();
  shell.store.put(
    _site,
    const TopicCategory(id: 1, name: 'plants', color: '0088CC'),
  );
  shell.store.put(
    _site,
    const TopicCategory(id: 2, name: 'pkm', color: 'BB7733'),
  );
  shell.pluginSession
      .require(chatShellService)
      .store
      .put(
        _site,
        const ChatChannel(
          id: 9,
          title: 'travel',
          kind: ChatChannelKind.category,
          categoryColor: Color(0xff8f63b8),
        ),
      );
  return shell;
}

Future<void> _pumpPage(
  WidgetTester tester,
  ShellController shell, {
  Size size = const Size(1080, 810),
  double scale = 1,
  bool rtl = false,
  bool settle = true,
  bool limitContentSize = false,
  VoidCallback? onOpened,
}) async {
  final settings = AppSettingsController(
    store: AppSettingsStore(persistence: MemoryAppSettingsPersistence()),
  );
  addTearDown(settings.dispose);
  await settings.setLimitContentSize(limitContentSize);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.dark.copyWith(
          platform: size.width < 600
              ? TargetPlatform.iOS
              : TargetPlatform.macOS,
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: ContentSettingsScope(
              controller: settings,
              child: DPageContentSettings(
                limitContentSize: limitContentSize,
                child: Scaffold(
                  body: BookmarkSection(
                    siteUrl: _site,
                    page: true,
                    onOpened: onOpened ?? () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _pumpTab(WidgetTester tester, ShellController shell) async {
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: BookmarkSection(siteUrl: _site, onOpened: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The item a Bookmarks page row draws, which carries its accent and label.
DItem _pageItem(WidgetTester tester, String key) => tester.widget<DItem>(
  find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(DItem)),
);

Future<void> _reminderFilter(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DSelect<BookmarkReminderFilter>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
