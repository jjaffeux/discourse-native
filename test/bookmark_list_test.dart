import 'package:discourse_native/discourse_ui.dart';
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

const _site = 'https://meta.example';
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
        tester.getRect(find.byKey(const Key('d-select-trigger-visual'))).left,
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
      await _filter(tester, 'All bookmarks');
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
    await _filter(tester, 'All bookmarks');
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

Future<ShellController> _shell({List<Bookmark>? bookmarks = _bookmarks}) async {
  const user = DiscourseUser(username: 'reader');
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
    ]),
    api: FakeDiscourseApi(user: user, bookmarkList: bookmarks),
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
              body: SingleChildScrollView(
                child: BookmarkSection(
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
  );
  await tester.pumpAndSettle();
}
