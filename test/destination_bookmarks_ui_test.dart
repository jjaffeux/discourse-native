import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/destination_bookmarks_store.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/destination_bookmark_ui.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/new_tab_page.dart';
import 'package:discourse_native/src/shell/open_link.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://forum.example';
const _page = ContentRoute(
  destination: PageDestination(CorePage.preferences),
  title: 'Preferences',
  icon: DIcons.gear,
);
const _category = ContentRoute(
  destination: FeedDestination(
    key: 'category-12',
    sourcePath: '/c/support/12.json',
  ),
  title: 'Community support',
  icon: DIcons.folder,
);
const _chat = ContentRoute(
  destination: ExtensionDestination('chat-c-9'),
  title: 'Travel conversation',
  icon: DIcons.comment,
);
const _captureKey = ValueKey('destination-bookmarks-capture');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    if (Platform.environment['DESTINATION_BOOKMARK_CAPTURE_DIR'] == null) {
      return;
    }
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'long local bookmark page mounts only nearby rows at $scale text',
      (tester) async {
        final shell = await tester.runAsync(
          () => _shell(store: DestinationBookmarksStore.memory()),
        );
        addTearDown(shell!.dispose);
        await tester.runAsync(() async {
          for (var id = 1; id <= 200; id++) {
            final route = ContentRoute(
              destination: FeedDestination(
                key: 'category-$id',
                sourcePath: '/c/category/$id.json',
              ),
              title: 'Saved category $id',
              icon: DIcons.folder,
            );
            await shell.destinationBookmarkAction(route)!.invoke();
          }
        });
        await _pump(
          tester,
          shell,
          const BookmarkSection(siteUrl: _site, page: true, onOpened: _noop),
          size: const Size(390, 844),
          scale: scale,
        );
        final mounted = find
            .byType(DestinationBookmarkRow, skipOffstage: false)
            .evaluate()
            .length;
        debugPrint(
          'list-audit local-bookmarks mounted=$mounted total=200 scale=$scale',
        );
        expect(mounted, lessThan(40));
        final last = find.byKey(
          const ValueKey('destination-bookmark-row-category:1'),
        );
        expect(last, findsNothing);
        final scrollable = find.descendant(
          of: find.byType(BookmarkSection),
          matching: find.byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axis == Axis.vertical,
          ),
        );
        await tester.scrollUntilVisible(
          last,
          500,
          scrollable: scrollable,
          maxScrolls: 200,
        );
        await tester.pumpAndSettle();
        expect(last.hitTestable(), findsOneWidget);
        expect(
          find
              .byType(DestinationBookmarkRow, skipOffstage: false)
              .evaluate()
              .length,
          lessThan(40),
        );
        expect(
          find.byKey(const ValueKey('destination-bookmark-row-category:200')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'content contexts add and remove every local destination without server mutation',
    (tester) async {
      final api = FakeDiscourseApi(
        user: const DiscourseUser(username: 'reader'),
      );
      final shell = await tester.runAsync(() => _shell(api: api));
      addTearDown(shell!.dispose);
      for (final route in [_page, _category, _chat]) {
        await _pump(
          tester,
          shell,
          LinkTarget.content(
            content: route,
            child: DButton(label: Text(route.title), onPressed: () {}),
          ),
        );
        await tester.tap(
          find.text(route.title),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('Bookmark'), findsOneWidget);
        await tester.tap(find.text('Bookmark'));
        await tester.pumpAndSettle();
        expect(
          shell
              .destinationBookmarksFor(_site)
              .any((entry) => entry.route.id == route.id),
          isTrue,
        );
        await tester.tap(
          find.text(route.title),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('Remove bookmark'), findsOneWidget);
        await tester.tap(find.text('Remove bookmark'));
        await tester.pumpAndSettle();
        expect(shell.destinationBookmarksFor(_site), isEmpty);
      }
      const bookmarks = ContentRoute(
        destination: PageDestination(CorePage.bookmarks),
        title: 'Bookmarks',
        icon: DIcons.bookmark,
      );
      await _pump(
        tester,
        shell,
        LinkTarget.content(
          content: bookmarks,
          child: DButton(
            label: const Text('Saved destinations'),
            onPressed: () {},
          ),
        ),
      );
      await tester.tap(
        find.text('Saved destinations'),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Bookmark'), findsNothing);
      expect(find.text('Remove bookmark'), findsNothing);
      expect(api.createdBookmarks, isEmpty);
      expect(api.updatedBookmarks, isEmpty);
      expect(api.deletedBookmarks, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final route in [_page, _category, _chat]) {
    for (final contextMenu in [false, true]) {
      testWidgets(
        'typed content new-tab failures report workspace capacity for ${route.id} with menu $contextMenu',
        (tester) async {
          final shell = await tester.runAsync(() => _shell());
          addTearDown(shell!.dispose);
          shell.desktopTopicTabs = true;
          for (var i = 1; i < ForumWorkspace.maximumTabs; i++) {
            shell.createTab();
          }
          final original = shell.activeTab;
          await _pump(
            tester,
            shell,
            LinkTarget.content(
              content: route,
              child: DButton(label: Text(route.title), onPressed: () {}),
            ),
          );
          await tester.tap(
            find.text(route.title),
            kind: PointerDeviceKind.mouse,
            buttons: contextMenu ? kSecondaryMouseButton : kMiddleMouseButton,
          );
          await tester.pumpAndSettle();
          if (contextMenu) {
            await tester.tap(find.text('Open in new main tab'));
            await tester.pumpAndSettle();
          }
          expect(shell.activeTab, original);
          expect(
            shell.tabsForCurrentForum,
            hasLength(ForumWorkspace.maximumTabs),
          );
          expect(
            find.text('Close a tab before opening another.'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('typed chat context actions report an unavailable destination', (
    tester,
  ) async {
    final shell = await tester.runAsync(() => _shell());
    addTearDown(shell!.dispose);
    final original = shell.activeTab;
    await _pump(
      tester,
      shell,
      LinkTarget.content(
        content: _chat,
        child: DButton(label: Text(_chat.title), onPressed: () {}),
      ),
    );
    await tester.tap(
      find.text(_chat.title),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in main panel'));
    await tester.pumpAndSettle();
    expect(shell.activeTab, original);
    expect(
      find.text('This destination is currently unavailable.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (size, scale) in [
    (const Size(390, 844), 1.0),
    (const Size(390, 844), 1.8),
    (const Size(1080, 810), 1.0),
  ]) {
    testWidgets(
      'local rows precede server bookmarks and filter at ${size.width} with scale $scale',
      (tester) async {
        final shell = await tester.runAsync(() => _shell());
        addTearDown(shell!.dispose);
        await tester.runAsync(() async {
          for (final route in [_page, _category, _chat]) {
            await shell.destinationBookmarkAction(route)!.invoke();
          }
        });
        await _pump(
          tester,
          shell,
          const BookmarkSection(siteUrl: _site, page: true, onOpened: _noop),
          size: size,
          scale: scale,
        );
        expect(find.byType(DestinationBookmarkRow), findsNWidgets(3));
        final local = find.byKey(
          const ValueKey('destination-bookmark-row-chat:9'),
        );
        final server = find.byKey(const ValueKey('bookmark-row-73'));
        expect(tester.getTopLeft(local).dy, greaterThanOrEqualTo(47));
        final item = tester.widget<DItem>(
          find.byKey(
            const ValueKey('destination-bookmark-row-page:preferences'),
          ),
        );
        expect(item.semanticLabel, contains('Page'));
        final semantics = tester.ensureSemantics();
        expect(
          tester
              .getSemantics(
                find.byKey(
                  const ValueKey('destination-bookmark-row-page:preferences'),
                ),
              )
              .label,
          'Preferences, Page, Community forum',
        );
        semantics.dispose();
        expect(item.semanticLabel, contains('Community forum'));
        expect(find.text('Page · Community forum'), findsOneWidget);
        expect(find.text('Category · Community forum'), findsOneWidget);
        expect(find.text('Chat · Community forum'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, '${size.width.toInt()}-${scale}x-bookmarks');
        if (server.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            server,
            180,
            scrollable: find
                .descendant(
                  of: find.byType(BookmarkSection),
                  matching: find.byType(Scrollable),
                )
                .last,
          );
        }
        expect(
          tester.getTopLeft(local).dy,
          lessThan(tester.getTopLeft(server).dy),
        );
        await tester.tap(find.byType(DSelect<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Page').last);
        await tester.pumpAndSettle();
        expect(find.byType(DestinationBookmarkRow), findsOneWidget);
        expect(find.byType(BookmarkRow), findsNothing);
        expect(find.text('Nothing bookmarked yet'), findsNothing);
        expect(find.text('No bookmarks in this filter.'), findsNothing);
        await tester.tap(find.byType(DSelect<BookmarkReminderFilter>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reminders').last);
        await tester.pumpAndSettle();
        expect(find.byType(DestinationBookmarkRow), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('failed durable write reports after its menu has closed', (
    tester,
  ) async {
    final persistence = _GatedFailurePersistence();
    final shell = await tester.runAsync(
      () => _shell(store: DestinationBookmarksStore(persistence: persistence)),
    );
    addTearDown(shell!.dispose);
    await _pump(
      tester,
      shell,
      DDropdownMenu(
        content: const DDropdownMenuContent(
          children: [DestinationBookmarkMenuItem(route: _page, dropdown: true)],
        ),
        child: DDropdownMenuTrigger(
          builder: (context, menu) => DButton(
            label: const Text('Page actions'),
            onPressed: menu.toggle,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Page actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bookmark'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('destination-bookmark-preferences')),
      findsNothing,
    );
    persistence.gate.complete(false);
    await tester.pumpAndSettle();
    expect(shell.destinationBookmarksFor(_site), isEmpty);
    expect(find.text('Could not save changes.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local rows remain usable while server bookmarks fail', (
    tester,
  ) async {
    final shell = await tester.runAsync(
      () => _shell(api: _FailingBookmarkApi()),
    );
    addTearDown(shell!.dispose);
    await tester.runAsync(
      () => shell.destinationBookmarkAction(_page)!.invoke(),
    );
    await _pump(
      tester,
      shell,
      const BookmarkSection(siteUrl: _site, page: true, onOpened: _noop),
    );
    expect(find.byType(DestinationBookmarkRow), findsOneWidget);
    await tester.tap(find.text('Preferences'));
    await tester.pumpAndSettle();
    expect(shell.currentContent, _page);
  });

  testWidgets(
    'Start local bookmarks and generic recently closed pages expose context actions',
    (tester) async {
      final shell = await tester.runAsync(() => _shell());
      addTearDown(shell!.dispose);
      await tester.runAsync(
        () => shell.destinationBookmarkAction(_page)!.invoke(),
      );
      await shell.openDestinationRoute(ContentRoute.forumAbout(), newTab: true);
      final closed = shell.tabsForCurrentForum.last;
      shell.closeTab(closed.id);
      await _pump(tester, shell, NewTabPage(onBrowseTopics: () {}));
      final saved = find.byKey(
        const ValueKey('start-page-recent-bookmark-page:preferences'),
      );
      expect(saved, findsOneWidget);
      await _capture(tester, 'start-local-bookmarks');
      await tester.tap(saved);
      await tester.pumpAndSettle();
      expect(shell.currentContent, _page);
      await tester.tap(
        find.byKey(ValueKey('start-page-recent-closed-${closed.id}')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('destination-bookmark-forum-about')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop tab context menu bookmarks the tab page', (
    tester,
  ) async {
    await pumpShell(
      tester,
      desktop,
      instances: [
        instance(
          'forum.example',
          title: 'Community forum',
        ).copyWith(user: const DiscourseUser(username: 'reader')),
      ],
      api: FakeDiscourseApi(user: const DiscourseUser(username: 'reader')),
      authenticator: FakeAuthenticator()..keys[_site] = 'key',
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    await shell.openDestinationRoute(_category);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('forum-tab-pointer-${shell.activeTabId}')).first,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('destination-bookmark-category-12')),
      findsOneWidget,
    );
    await tester.tap(find.text('Bookmark'));
    await tester.pumpAndSettle();
    expect(shell.destinationBookmarksFor(_site).single.route, _category);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('the phone\'s panel lists places without a bookmark action', (
    tester,
  ) async {
    await pumpShell(
      tester,
      phone,
      instances: [
        instance(
          'forum.example',
          title: 'Community forum',
        ).copyWith(user: const DiscourseUser(username: 'reader')),
      ],
      api: FakeDiscourseApi(user: const DiscourseUser(username: 'reader')),
      authenticator: FakeAuthenticator()..keys[_site] = 'key',
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    await shell.openDestinationRoute(ContentRoute.allCategories());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(DMobileDock.moreKey));
    await tester.pumpAndSettle();
    expect(find.byKey(DMobileDock.panelKey), findsOneWidget);
    expect(
      find.byKey(const ValueKey('destination-bookmark-all-categories')),
      findsNothing,
    );
    expect(find.text('Bookmark'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}

void _noop() {}

Future<ShellController> _shell({
  FakeDiscourseApi? api,
  DestinationBookmarksStore? store,
}) async {
  const user = DiscourseUser(username: 'reader');
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('forum.example', title: 'Community forum').copyWith(user: user),
    ]),
    api:
        api ??
        FakeDiscourseApi(
          user: user,
          bookmarkList: const [
            Bookmark(
              id: 73,
              bookmarkableId: 7,
              bookmarkableType: 'Topic',
              title: 'Server topic',
              path: '/t/topic/7',
            ),
          ],
        ),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    destinationBookmarks: store,
    plugins: installedPlugins,
  );
  await shell.load();
  await pumpEventQueue();
  return shell;
}

Future<void> _pump(
  WidgetTester tester,
  ShellController shell,
  Widget child, {
  Size size = const Size(1080, 810),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        builder: (context, child) => DToaster(child: child!),
        theme: AppTheme.dark.copyWith(
          platform: size.width < 600
              ? TargetPlatform.iOS
              : TargetPlatform.macOS,
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 47, bottom: 34),
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            key: _captureKey,
            child: Scaffold(body: SafeArea(child: child)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['DESTINATION_BOOKMARK_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(_captureKey))
        .toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _FailingBookmarkApi extends FakeDiscourseApi {
  _FailingBookmarkApi() : super(user: const DiscourseUser(username: 'reader'));
  @override
  Future<BookmarkListPage> bookmarkListPage({
    required String siteUrl,
    required String username,
    int page = 0,
    required String apiKey,
    String? clientId,
  }) async => throw StateError('Offline');
}

class _GatedFailurePersistence implements DestinationBookmarksPersistence {
  final gate = Completer<bool>();
  @override
  Future<String?> read() async => null;
  @override
  Future<bool> write(String value) => gate.future;
}
