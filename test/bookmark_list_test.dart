import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
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

  testWidgets('reminder scopes compose with types and accent expired rows', (
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
    final expired = tester.widget<DItem>(
      find.byKey(const ValueKey('bookmark-row-1')),
    );
    expect(expired.selected, isTrue);
    expect(expired.selectionStyle, DItemSelectionStyle.leadingAccent);
    expect(expired.showSelectionIndicator, isFalse);
    expect(expired.semanticLabel, contains('Reminder expired'));
    expect(
      tester
          .widget<DItem>(find.byKey(const ValueKey('bookmark-row-2')))
          .selected,
      isFalse,
    );
    await _reminderFilter(tester, 'Reminders');
    expect(find.byType(BookmarkRow), findsNWidgets(3));
    await _reminderFilter(tester, 'Expired');
    expect(find.byType(BookmarkRow), findsNWidgets(2));
    await _filter(tester, 'Posts');
    expect(find.byType(BookmarkRow), findsOneWidget);
    await _filter(tester, 'Chat');
    expect(find.text('No bookmarks in this filter.'), findsOneWidget);
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
      expect(find.byType(DSelect<String>), findsOneWidget);

      api.bookmarksGate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(DSkeletonRegion), findsNothing);
      expect(find.byType(BookmarkRow), findsNWidgets(_bookmarks.length));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  for (final size in [const Size(390, 844), const Size(1080, 810)]) {
    testWidgets('bookmark page wraps and filters at ${size.width}px', (
      tester,
    ) async {
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
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(_longTitle),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      if (size.width < 600) {
        expect(paragraph.size.height, greaterThan(30));
      }
      final titleRect = tester.getRect(find.text('Bookmarks'));
      final selectRect = tester.getRect(find.byType(DSelect<String>));
      expect(titleRect.bottom, lessThan(selectRect.top));
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

      await _filter(tester, 'Posts');
      expect(find.byType(BookmarkRow), findsNWidgets(2));
      expect(find.text('flourpower in #travel'), findsNothing);
      await _filter(tester, 'Topics');
      expect(find.byType(BookmarkRow), findsOneWidget);
      await _filter(tester, 'Chat');
      expect(find.byType(BookmarkRow), findsNWidgets(2));
      await _filter(tester, 'All types');
      expect(find.byType(BookmarkRow), findsNWidgets(5));
      await tester.tap(find.byKey(const ValueKey('bookmark-row-1')));
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 7);
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

  testWidgets('empty filters retain the selector and can return to all', (
    tester,
  ) async {
    final shell = await _shell(bookmarks: [_bookmarks.first]);
    addTearDown(shell.dispose);
    await _pumpPage(tester, shell);
    await _filter(tester, 'Topics');
    expect(find.text('No bookmarks in this filter.'), findsOneWidget);
    await _filter(tester, 'All types');
    expect(find.byType(BookmarkRow), findsOneWidget);
  });

  testWidgets('empty and failed feeds retain the page heading and filter', (
    tester,
  ) async {
    for (final bookmarks in [<Bookmark>[], null]) {
      final shell = await _shell(bookmarks: bookmarks);
      await _pumpPage(tester, shell);
      expect(find.text('Bookmarks'), findsOneWidget);
      expect(find.byType(DSelect<String>), findsOneWidget);
      expect(
        find.text(bookmarks == null ? 'Retry' : 'Nothing bookmarked yet.'),
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
      bookmarkList: _numbered(45, topics: {41, 42, 43, 44, 45}),
    );
    final shell = await _shell(api: api);
    addTearDown(shell.dispose);
    await _pumpPage(tester, shell);
    expect(api.bookmarkListRequests.map((request) => request.page), [0]);

    await _filter(tester, 'Topics');

    expect(find.text('No bookmarks in this filter.'), findsNothing);
    expect(find.byType(BookmarkRow), findsNWidgets(5));
    expect(find.byKey(const ValueKey('bookmark-row-41')), findsOneWidget);
    expect(api.bookmarkListRequests.map((request) => request.page), [0, 1, 2]);

    await _filter(tester, 'Posts');
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
}

Future<void> _filter(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DSelect<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

final _pageScrollable = find.descendant(
  of: find.byType(CustomScrollView),
  matching: find.byType(Scrollable),
);

/// Post bookmarks, except for the [topics] ids.
List<Bookmark> _numbered(int count, {Set<int> topics = const {}}) => [
  for (var id = 1; id <= count; id++)
    Bookmark(
      id: id,
      bookmarkableType: topics.contains(id) ? 'Topic' : 'Post',
      postNumber: topics.contains(id) ? null : 2,
      categoryId: 1,
      title: 'Bookmark $id',
      path: '/t/bookmark-$id/$id',
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
  VoidCallback? onOpened,
}) async {
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
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _reminderFilter(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DSelect<BookmarkReminderFilter>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
