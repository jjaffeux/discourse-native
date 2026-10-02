import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/new_tab_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _reader = DiscourseUser(username: 'reader');
const _topics = [
  Topic(
    id: 1,
    title: 'Welcome to the community',
    slug: 'welcome',
    categoryId: 12,
  ),
  Topic(
    id: 2,
    title: 'A useful keyboard shortcut',
    slug: 'keyboard',
    categoryId: 12,
  ),
  Topic(
    id: 3,
    title: 'A quieter start page',
    slug: 'start',
    tags: [TopicTag(name: 'design')],
  ),
  Topic(
    id: 4,
    title: 'Where shall we meet?',
    slug: 'meet',
    excerpt: 'A garden picnic',
  ),
];

Finder _page = find.byType(NewTabPage).first;
Finder _onPage(Finder finder) => find.descendant(of: _page, matching: finder);
Finder _section(String title) =>
    _onPage(find.byKey(ValueKey('start-page-section-$title')));

Future<ShellController> _start(
  WidgetTester tester,
  Size size, {
  FakeDiscourseApi? api,
}) async {
  const notifications = MethodChannel(
    'org.discourse.native/notification_opens',
  );
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    notifications,
    (_) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      notifications,
      null,
    ),
  );
  await pumpShell(
    tester,
    size,
    instances: [
      instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      ).copyWith(user: _reader),
    ],
    api: api ?? _api(),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
  );
  final shell = ShellScope.read(tester.element(find.byType(MainContent).first));
  await shell.forumSettings.setShared(
    const SharedAppearance(
      font: ForumFont.openSans,
      interfaceFont: ForumFont.openSans,
    ),
  );
  await shell.loadBookmarks(_site);
  shell.openListUrl('/c/support/12', title: 'Support');
  for (final topic in _topics) {
    shell.pushContent(
      ContentRoute.topic(
        topicId: topic.id,
        title: topic.title,
        slug: topic.slug,
      ),
    );
  }
  shell.pushContent(
    const ContentRoute(id: 'chat-c-9', title: 'General', icon: DIcons.comment),
  );
  shell.pushContent(
    const ContentRoute(
      id: 'chat-c-10',
      title: 'Announcements',
      icon: DIcons.comment,
    ),
  );
  shell.pushContent(ContentRoute.newTab());
  await tester.pumpAndSettle();
  return shell;
}

FakeDiscourseApi _api() => FakeDiscourseApi(
  user: _reader,
  totals: chatNotificationTotals(available: true),
  categoryList: const [
    TopicCategory(
      id: 12,
      name: 'Support',
      slug: 'support',
      color: '0088cc',
      icon: 'life-ring',
      descriptionExcerpt: 'Ask for help',
    ),
  ],
  feeds: const {'/latest.json': _topics},
  bookmarkList: [
    Bookmark(
      id: 18,
      title: 'A discussion worth keeping',
      path: '/t/saved/18',
      categoryId: 12,
      bookmarkableType: 'Topic',
      reminderAt: DateTime.utc(2030),
    ),
    const Bookmark(
      id: 19,
      title: 'A saved answer',
      path: '/t/answer/19',
      bookmarkableType: 'Post',
      postNumber: 2,
    ),
  ],
  chatChannelsBySite: {
    _site: const ChatChannels(
      public: [
        ChatChannel(
          id: 9,
          title: 'General',
          kind: ChatChannelKind.category,
          membership: ChatMembership(following: true),
          tracking: ChatTracking(unreadCount: 3),
        ),
        ChatChannel(
          id: 10,
          title: 'Announcements',
          kind: ChatChannelKind.category,
          membership: ChatMembership(following: true),
        ),
      ],
    ),
  },
);

void main() {
  setUpAll(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  _test(
    'four wells balance rows, stretch surfaces, and preserve the 18px grid gap',
    (tester) async {
      final shell = await _start(tester, const Size(1000, 900));
      final gridPage = find.byType(NewTabPage).last;
      Finder section(String title) => find.descendant(
        of: gridPage,
        matching: find.byKey(ValueKey('start-page-section-$title')),
      );
      final bookmarks = tester.getRect(section('Bookmarks'));
      final categories = tester.getRect(section('Categories'));
      final chat = tester.getRect(section('Chat'));
      final topics = tester.getRect(section('Recent topics'));
      expect(bookmarks.top, categories.top);
      expect(bookmarks.height, categories.height);
      expect(chat.top, topics.top);
      expect(chat.height, topics.height);
      expect(categories.left - bookmarks.right, closeTo(18, .01));
      expect(chat.top - bookmarks.bottom, closeTo(18, .01));
      tester.view.physicalSize = const Size(2400, 1000);
      await shell.appSettings.setLimitContentSize(false);
      await tester.pumpAndSettle();
      final wideWells = [
        for (final title in [
          'Bookmarks',
          'Categories',
          'Chat',
          'Recent topics',
        ])
          tester.getRect(section(title)),
      ];
      expect(wideWells.map((rect) => rect.top).toSet(), hasLength(1));
      expect(wideWells.map((rect) => rect.height).toSet(), hasLength(1));
      tester.view.physicalSize = desktop;
      for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
        await shell.forumSettings.setThemeMode(_site, mode);
        await tester.pumpAndSettle();
        await _capture(tester, 'desktop-${mode.name}');
      }
      final heading = find.descendant(
        of: gridPage,
        matching: find.byKey(
          const ValueKey('start-page-section-link-Categories'),
        ),
      );
      await tester.tapAt(
        Offset(tester.getRect(heading).right - 2, tester.getCenter(heading).dy),
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, 'all-categories');
      expect(tester.takeException(), isNull);
    },
  );

  _test(
    'chrome search filters cached titles, excerpts and tags with no network search',
    (tester) async {
      final api = _api();
      final shell = await _start(tester, desktop, api: api);
      final feedRequests = api.feedPaths.toList();
      final input = find.byKey(ForumSearch.inputKey).first;
      for (final (query, title) in [
        ('design', 'A quieter start page'),
        ('garden', 'Where shall we meet?'),
      ]) {
        await tester.enterText(input, query);
        await tester.pumpAndSettle();
        expect(_onPage(find.text(title)), findsOneWidget);
        expect(_onPage(find.textContaining('1 result for')), findsOneWidget);
        expect(_section('Bookmarks'), findsNothing);
        expect(find.byKey(ForumSearch.panelKey), findsNothing);
      }
      await tester.enterText(input, 'does not exist');
      await tester.pumpAndSettle();
      expect(
        _onPage(find.text('Nothing matches “does not exist”')),
        findsOneWidget,
      );
      expect(_section('Recent topics'), findsNothing);
      expect(shell.globalSearch.query, isEmpty);
      expect(api.searchesRequested, isEmpty);
      expect(api.feedPaths, feedRequests);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_section('Recent topics'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('start-page-search-results')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  _test('bookmark search finds cached matches beyond the four preview rows', (
    tester,
  ) async {
    final api = _api();
    api.bookmarkList!.addAll([
      for (var i = 20; i < 24; i++)
        Bookmark(id: i, title: 'Saved topic $i', path: '/t/saved/$i'),
      const Bookmark(id: 99, title: 'Hidden bookmark', path: '/t/hidden/99'),
    ]);
    await _start(tester, desktop, api: api);
    expect(_onPage(find.text('Hidden bookmark')), findsNothing);
    await tester.enterText(
      find.byKey(ForumSearch.inputKey).first,
      'Hidden bookmark',
    );
    await tester.pumpAndSettle();
    expect(_onPage(find.text('Hidden bookmark')), findsOneWidget);
    expect(_onPage(find.textContaining('1 result for')), findsOneWidget);
    expect(api.searchesRequested, isEmpty);
    expect(tester.takeException(), isNull);
  });

  _test(
    'search queries belong to their Start tab and global search stays available on other pages',
    (tester) async {
      final shell = await _start(tester, desktop);
      final first = shell.activeTabId!;
      final input = find.byKey(ForumSearch.inputKey).first;
      await tester.enterText(input, 'garden');
      await tester.pumpAndSettle();
      shell.createTab();
      final second = shell.activeTabId!;
      await tester.pumpAndSettle();
      expect(shell.search.startPageQueryFor(_site, second), isEmpty);
      expect(_section('Bookmarks'), findsOneWidget);
      await tester.enterText(input, 'design');
      await tester.pumpAndSettle();
      shell.selectTab(first);
      await tester.pumpAndSettle();
      expect(_onPage(find.text('Where shall we meet?')), findsOneWidget);
      expect(_onPage(find.text('A quieter start page')), findsNothing);
      shell.pushContent(
        ContentRoute.topic(
          topicId: 1,
          title: 'Welcome to the community',
          slug: 'welcome',
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(input, 'server query');
      await tester.pumpAndSettle();
      expect(shell.globalSearch.query, 'server query');
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsNothing);
      expect(shell.search.startPageQueryFor(_site, first), 'garden');
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    _test(
      'forum title menu keeps actions on one line and opens externally on $platform',
      (tester) async {
        final launched = watchBrowser(tester);
        final shell = await _start(
          tester,
          platform == TargetPlatform.iOS ? phone : desktop,
        );
        final options = _onPage(
          find.byKey(const ValueKey('start-page-forum-options')),
        );
        for (final scale in [
          AppTextScale.percent100,
          AppTextScale.percent200,
        ]) {
          await shell.appSettings.setTextScale(scale);
          await tester.pumpAndSettle();
          await tester.tap(options);
          await tester.pumpAndSettle();
          for (final label in ['Open forum in browser', 'Remove forum']) {
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.text(label),
                matching: find.byType(RichText),
              ),
            );
            expect(
              paragraph.getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: label.length),
              ),
              hasLength(1),
              reason: '$label should occupy one line at $scale',
            );
            if (scale == AppTextScale.percent100) {
              expect(paragraph.didExceedMaxLines, isFalse);
            }
          }
          final popup = tester.getRect(find.byType(DDropdownMenuContent));
          expect(popup.left, greaterThanOrEqualTo(0));
          expect(
            popup.right,
            lessThanOrEqualTo(tester.view.physicalSize.width),
          );
          await tester.tap(
            find.widgetWithText(DDropdownMenuItem, 'Open forum in browser'),
          );
          await tester.pumpAndSettle();
        }
        expect(launched, [_site, _site]);
        await tester.tap(options);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(DDropdownMenuItem, 'Remove forum'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Remove Discourse Meta?'), findsOneWidget);
        await tester.tap(find.widgetWithText(DButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(shell.currentInstance?.url, _site);
        expect(tester.takeException(), isNull);
      },
      platform: platform,
    );
  }

  for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
    _test(
      'native Start wells and shortcuts fit phone and large text in $mode',
      (tester) async {
        final shell = await _start(tester, phone);
        await shell.forumSettings.setThemeMode(_site, mode);
        await tester.pumpAndSettle();
        await _capture(tester, 'phone-${mode.name}');
        final more = _onPage(find.byKey(const ValueKey('start-page-more')));
        expect(more, findsOneWidget);
        await tester.tap(more);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(DDropdownMenuItem, 'Settings'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(DDropdownMenuItem, 'Settings'));
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, 'appearance');
        shell.pushContent(ContentRoute.newTab());
        tester.view.physicalSize = const Size(320, 1000);
        await shell.appSettings.setTextScale(AppTextScale.percent200);
        await tester.pumpAndSettle();
        expect(
          _onPage(find.byKey(const ValueKey('start-page-more'))),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, 'large-text-${mode.name}');
      },
      platform: TargetPlatform.iOS,
    );
  }
}

// Optional review exports use actual bundled fonts and the real shell fixture.
Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['START_PAGE_REVIEW_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.ancestor(of: _page, matching: find.byType(RepaintBoundary)).first,
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

void _test(
  String description,
  Future<void> Function(WidgetTester) body, {
  TargetPlatform platform = TargetPlatform.macOS,
}) {
  testWidgets(description, body, variant: TargetPlatformVariant.only(platform));
}
