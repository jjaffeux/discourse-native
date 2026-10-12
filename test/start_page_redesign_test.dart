import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/badge_route.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/models/user_summary.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/shell/badges_page.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/groups_controller.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/new_tab_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/button_surface.dart';
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
  bool visitTopics = true,
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
  for (final topic in visitTopics ? _topics : const <Topic>[]) {
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

FakeDiscourseApi _api({
  List<Topic> topics = _topics,
  List<UserDraft> drafts = const [],
  Map<int, ChatThreadPage> threads = const {},
  UserSummary? summary,
  List<UserActivityItem> activity = const [],
  Map<String, Map<String, dynamic>> responses = const {},
}) => FakeDiscourseApi(
  summary: summary,
  userActivityItems: activity,
  pluginResponses: responses,
  userDraftList: drafts,
  chatChannelThreadPagesByKey: {
    for (final entry in threads.entries)
      FakeDiscourseApi.chatChannelThreadPageKey(entry.key, 0): entry.value,
  },
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
  feeds: {'/latest.json': topics},
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
          threadingEnabled: true,
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

  _test('Start keeps only Filters on its header bar at every width', (
    tester,
  ) async {
    final shell = await _start(tester, desktop);
    await shell.appSettings.setLimitContentSize(false);
    for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
      await shell.forumSettings.setThemeMode(_site, mode);
      for (final width in [2400.0, 1000.0, 2400.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        final filter = _onPage(find.byKey(const ValueKey('topic-list-filter')));
        final tokens = DTokens.of(tester.element(filter));
        final button = tester.widget<DButton>(filter);
        final surface = buttonSurface(tester, of: filter);
        expect(button.variant, DButtonVariant.secondary);
        expect(button.backgroundColor, tokens.buttonTheme.outline.hover);
        expect(surface.borderColor, tokens.buttonTheme.outline.border);
        expect(surface.strokeWidth, 1);
        expect(
          _onPage(find.byKey(const ValueKey('start-page-more'))),
          findsNothing,
        );
        expect(
          _onPage(find.byKey(const ValueKey('start-page-shortcuts'))),
          findsNothing,
        );
        expect(_section('Groups'), findsOneWidget);
        expect(_section('Settings'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
  });

  _test(
    'Start pins Topics above the alphabet with preferences and settings at the end',
    (tester) async {
      final shell = await _start(tester, const Size(1000, 900));
      expect(
        tester.getRect(_section('Topics')).bottom,
        lessThan(tester.getRect(_section('Activity')).top),
      );
      final titles = [
        'Activity',
        'Badges',
        'Bookmarks',
        'Categories',
        'Channels',
        'Chat',
        'Drafts',
        'Groups',
        'Messages',
        'Summary',
        'Threads',
        'Users',
        'Preferences',
        'Settings',
      ];
      for (var i = 1; i < titles.length; i++) {
        final previous = tester.getRect(_section(titles[i - 1]));
        final next = tester.getRect(_section(titles[i]));
        expect(previous.left, next.left);
        expect(previous.right, next.right);
        expect(previous.bottom, closeTo(next.top, .01));
      }
      tester.view.physicalSize = const Size(2400, 1000);
      await shell.appSettings.setLimitContentSize(false);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_section('Bookmarks')).left,
        tester.getRect(_section('Categories')).left,
      );
      for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
        await shell.forumSettings.setThemeMode(_site, mode);
        await tester.pumpAndSettle();
        await _capture(tester, 'desktop-${mode.name}');
      }
      final heading = _onPage(
        find.byKey(const ValueKey('start-page-section-link-Categories')),
      );
      await Scrollable.ensureVisible(tester.element(heading), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tapAt(
        Offset(
          tester.getRect(heading).right - 40,
          tester.getCenter(heading).dy,
        ),
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, 'all-categories');
      expect(tester.takeException(), isNull);
    },
  );

  _test(
    'Topics previews follow the cached forum list, including unvisited topics',
    (tester) async {
      final api = _api();
      final shell = await _start(tester, desktop, api: api, visitTopics: false);
      final requests = api.feedPaths.toList();
      expect(shell.recentTopicsFor(_site), isEmpty);
      for (var i = 0; i < _topics.length; i++) {
        final row = _onPage(
          find.byKey(ValueKey('start-page-recent-topic-${_topics[i].id}')),
        );
        expect(row, findsOneWidget);
        if (i > 0) {
          expect(
            tester.getRect(row).top,
            greaterThan(
              tester
                  .getRect(
                    _onPage(
                      find.byKey(
                        ValueKey(
                          'start-page-recent-topic-${_topics[i - 1].id}',
                        ),
                      ),
                    ),
                  )
                  .top,
            ),
          );
        }
      }
      shell.pushContent(
        ContentRoute.topic(
          topicId: 4,
          slug: 'meet',
          title: 'Where shall we meet?',
        ),
      );
      shell.pushContent(
        ContentRoute.topic(
          topicId: 99,
          slug: 'outside',
          title: 'Viewed outside Latest',
        ),
      );
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();
      expect(_onPage(find.text('Viewed outside Latest')), findsNothing);
      expect(_section('Recent topics'), findsNothing);
      expect(_section('Recently viewed'), findsNothing);
      final index = tester.widget<DAlphabetIndex<String>>(
        _onPage(find.byType(DAlphabetIndex<String>)),
      );
      expect(
        index.entries.map((entry) => entry.value),
        isNot(contains('recent-topics')),
      );
      expect(index.entries.first.value, 'topics');
      expect(api.feedPaths, requests);
      await tester.tap(
        _onPage(find.byKey(const ValueKey('start-page-recent-topic-1'))),
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 1);
      expect(
        shell.activeTab?.contentStack.any((route) => route.isNewTab),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  _test(
    'empty Topics stays a pinned destination without fetching or visit placeholders',
    (tester) async {
      final api = FakeDiscourseApi(feeds: const {'/latest.json': []});
      final shell = await _start(tester, desktop, api: api);
      final requests = api.feedPaths.toList();
      expect(_section('Topics'), findsOneWidget);
      expect(
        _onPage(find.byKey(const ValueKey('start-page-pinned-topics'))),
        findsOneWidget,
      );
      expect(_section('Recent topics'), findsNothing);
      expect(_section('Recently viewed'), findsNothing);
      expect(_onPage(find.text('Welcome to the community')), findsNothing);
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();
      expect(api.feedPaths, requests);
      await tester.tap(
        _onPage(find.byKey(const ValueKey('start-page-section-link-Topics'))),
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, 'latest');
      expect(tester.takeException(), isNull);
    },
  );

  _test(
    'Recently closed leads after repinning and Topics unpins independently',
    (tester) async {
      final shell = await _start(tester, desktop);
      shell.createTab(panel: ForumPanel.secondary);
      shell.pushContent(
        ContentRoute.topic(
          topicId: 1,
          slug: 'welcome',
          title: 'Welcome to the community',
        ),
      );
      shell.closeTab(shell.activeTabId!);
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();
      Future<void> pin(String id) async {
        final control = _onPage(find.byKey(ValueKey('start-page-pin-$id')));
        await Scrollable.ensureVisible(tester.element(control), alignment: .5);
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: tester.getCenter(control));
        await mouse.moveTo(tester.getCenter(control));
        await tester.pumpAndSettle();
        await tester.tap(control);
        await tester.pumpAndSettle();
        await mouse.removePointer();
        expect(shell.currentContent?.isNewTab, isTrue);
      }

      await pin('recently-closed');
      await pin('categories');
      await pin('recently-closed');
      expect(shell.startPage.pinsFor(_site), [
        'recently-closed',
        'topics',
        'categories',
      ]);
      expect(
        tester.getRect(_section('Recently closed')).top,
        lessThan(tester.getRect(_section('Topics')).top),
      );
      expect(
        tester.getRect(_section('Topics')).top,
        lessThan(tester.getRect(_section('Categories')).top),
      );
      final index = tester.widget<DAlphabetIndex<String>>(
        _onPage(find.byType(DAlphabetIndex<String>)),
      );
      expect(index.entries.first.value, 'recently-closed');
      await _capture(tester, 'repinned-closed');
      await pin('topics');
      expect(shell.startPage.pinsFor(_site), ['recently-closed', 'categories']);
      expect(
        tester.getRect(_section('Threads')).top,
        lessThan(tester.getRect(_section('Topics')).top),
      );
      expect(
        tester.getRect(_section('Topics')).top,
        lessThan(tester.getRect(_section('Users')).top),
      );
      await pin('topics');
      expect(shell.startPage.pinsFor(_site), [
        'recently-closed',
        'categories',
        'topics',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  _test('account retirement clears cached Topics and restores default pins', (
    tester,
  ) async {
    final api = _api();
    final shell = await _start(tester, desktop, api: api);
    expect(_onPage(find.text('Welcome to the community')), findsOneWidget);
    shell.startPage.togglePin(_site, 'topics');
    shell.startPage.togglePin(_site, 'categories');
    await tester.pumpAndSettle();
    // The anonymous account's latest response does not contain the old data.
    api.feeds['/latest.json'] = const [];
    await shell.disconnectCurrentInstance();
    await tester.pumpAndSettle();
    expect(shell.currentInstance?.user, isNull);
    expect(shell.cachedLatestTopicsFor(_site), isEmpty);
    expect(_onPage(find.text('Welcome to the community')), findsNothing);
    expect(shell.startPage.pinsFor(_site), ['recently-closed', 'topics']);
    expect(
      _onPage(find.byKey(const ValueKey('start-page-pinned-topics'))),
      findsOneWidget,
    );
    expect(_section('Drafts'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _test('pinning moves a section into a card and survives reopening Start', (
    tester,
  ) async {
    final shell = await _start(tester, desktop);
    final pin = _onPage(
      find.byKey(const ValueKey('start-page-pin-categories')),
    );
    await Scrollable.ensureVisible(tester.element(pin), alignment: .5);
    await tester.pumpAndSettle();
    // A touch platform keeps the independent pin action visible.
    await tester.tap(pin);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.isNewTab, isTrue);
    expect(shell.startPage.pinsFor(_site), contains('categories'));
    expect(
      _onPage(find.byKey(const ValueKey('start-page-pinned-categories'))),
      findsOneWidget,
    );
    expect(
      tester.getRect(_section('Categories')).top,
      lessThan(tester.getRect(_section('Activity')).top),
    );
    shell.openUserSummary(_site);
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(
      _onPage(find.byKey(const ValueKey('start-page-pinned-categories'))),
      findsOneWidget,
    );
    final unpin = _onPage(
      find.byKey(const ValueKey('start-page-pin-categories')),
    );
    await Scrollable.ensureVisible(tester.element(unpin), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(unpin);
    await tester.pumpAndSettle();
    expect(shell.startPage.pinsFor(_site), isNot(contains('categories')));
    expect(
      tester.getRect(_section('Bookmarks')).top,
      lessThan(tester.getRect(_section('Categories')).top),
    );
    expect(tester.takeException(), isNull);
  }, platform: TargetPlatform.iOS);

  _test(
    'cached Start filtering matches titles, excerpts and tags with no network search',
    (tester) async {
      final api = _api();
      final shell = await _start(tester, desktop, api: api);
      final feedRequests = api.feedPaths.toList();
      final pluginRequests = api.pluginReadPaths.toList();
      final tab = shell.activeTabId!;
      for (final (query, title) in [
        ('keyboard', 'A useful keyboard shortcut'),
        ('design', 'A quieter start page'),
        ('garden', 'Where shall we meet?'),
      ]) {
        shell.search.setStartPageQuery(_site, tab, query);
        await tester.pumpAndSettle();
        expect(_onPage(find.text(title)), findsOneWidget);
        expect(_onPage(find.textContaining('1 result for')), findsOneWidget);
        expect(_section('Bookmarks'), findsNothing);
        expect(find.byKey(ForumSearch.panelKey), findsNothing);
      }
      shell.search.setStartPageQuery(_site, tab, 'does not exist');
      await tester.pumpAndSettle();
      expect(
        _onPage(find.text('Nothing matches “does not exist”')),
        findsOneWidget,
      );
      expect(_section('Topics'), findsNothing);
      expect(shell.globalSearch.query, isEmpty);
      expect(api.searchesRequested, isEmpty);
      expect(api.feedPaths, feedRequests);
      expect(api.pluginReadPaths, pluginRequests);
      shell.search.setStartPageQuery(_site, tab, '');
      await tester.pumpAndSettle();
      expect(_section('Topics'), findsOneWidget);
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
    final shell = await _start(tester, desktop, api: api);
    expect(_onPage(find.text('Hidden bookmark')), findsNothing);
    final requests = api.pluginReadPaths.toList();
    shell.search.setStartPageQuery(
      _site,
      shell.activeTabId!,
      'Hidden bookmark',
    );
    await tester.pumpAndSettle();
    expect(_onPage(find.text('Hidden bookmark')), findsOneWidget);
    expect(_onPage(find.textContaining('1 result for')), findsOneWidget);
    expect(api.searchesRequested, isEmpty);
    expect(api.pluginReadPaths, requests);
    expect(tester.takeException(), isNull);
  });

  _test('topic search finds cached matches beyond the four preview rows', (
    tester,
  ) async {
    final api = _api(
      topics: [
        ..._topics,
        const Topic(id: 99, title: 'Another forum topic', slug: 'another'),
      ],
    );
    final shell = await _start(tester, desktop, api: api);
    expect(_onPage(find.text('Another forum topic')), findsNothing);
    final requests = api.feedPaths.toList();
    final pluginRequests = api.pluginReadPaths.toList();
    shell.search.setStartPageQuery(_site, shell.activeTabId!, 'Another');
    await tester.pumpAndSettle();
    expect(_onPage(find.text('Another forum topic')), findsOneWidget);
    expect(_onPage(find.textContaining('1 result for')), findsOneWidget);
    expect(api.feedPaths, requests);
    expect(api.searchesRequested, isEmpty);
    expect(api.pluginReadPaths, pluginRequests);
    expect(tester.takeException(), isNull);
  });

  _test(
    'cached Start queries stay tab-local while chrome search is global on every page',
    (tester) async {
      final api = _api();
      final shell = await _start(tester, desktop, api: api);
      final first = shell.activeTabId!;
      final input = find.byKey(ForumSearch.inputKey).first;
      shell.search.setStartPageQuery(_site, first, 'garden');
      await tester.pumpAndSettle();
      shell.createTab();
      final second = shell.activeTabId!;
      await tester.pumpAndSettle();
      expect(shell.search.startPageQueryFor(_site, second), isEmpty);
      expect(_section('Bookmarks'), findsOneWidget);
      shell.search.setStartPageQuery(_site, second, 'design');
      await tester.pumpAndSettle();
      shell.selectTab(first);
      await tester.pumpAndSettle();
      expect(_onPage(find.text('Where shall we meet?')), findsOneWidget);
      expect(_onPage(find.text('A quieter start page')), findsNothing);
      // Chrome search now opens the shared global surface on Start as well.
      await tester.tap(input);
      await tester.pumpAndSettle();
      await tester.enterText(input, 'global query');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(shell.globalSearch.query, 'global query');
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      expect(shell.search.startPageQueryFor(_site, first), 'garden');
      expect(_onPage(find.text('Where shall we meet?')), findsOneWidget);
      expect(
        api.pluginReadPaths.any((path) {
          final uri = Uri.parse(path);
          return uri.path == '/search/query.json' &&
              uri.queryParameters['term'] == 'global query';
        }),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsNothing);
      shell.pushContent(
        ContentRoute.topic(
          topicId: 1,
          title: 'Welcome to the community',
          slug: 'welcome',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(input);
      await tester.pumpAndSettle();
      await tester.enterText(input, 'server query');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(shell.globalSearch.query, 'server query');
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsNothing);
      expect(shell.search.startPageQueryFor(_site, first), 'garden');
      expect(shell.search.startPageQueryFor(_site, second), 'design');
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

  _test('Start shows cached drafts and threads without fetching on entry', (
    tester,
  ) async {
    final api = _api(
      drafts: const [
        UserDraft(
          key: 'new_topic',
          sequence: 1,
          data: ComposerDraft(
            reply: 'A draft body',
            title: 'An unfinished announcement',
            action: 'createTopic',
          ),
        ),
      ],
      threads: const {
        9: ChatThreadPage(
          threads: [
            ChatThread(
              id: 71,
              channelId: 9,
              status: 'open',
              lastMessageId: 78,
              replyCount: 3,
              title: 'A cached thread',
            ),
          ],
        ),
      },
    );
    final shell = await _start(tester, desktop, api: api);
    expect(api.userDraftRequests, isEmpty);
    expect(api.chatThreadPagesRequested, isEmpty);
    await shell.draftList.load(shell.currentInstance!);
    shell.pushContent(
      const ContentRoute(
        id: 'chat-c-9-threads',
        title: 'Threads',
        icon: DIcons.comments,
      ),
    );
    await tester.pumpAndSettle();
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(_onPage(find.text('An unfinished announcement')), findsOneWidget);
    expect(_onPage(find.text('A cached thread')), findsOneWidget);
    expect(api.userDraftRequests, hasLength(1));
    expect(api.chatChannelThreadPagesRequested, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  _test(
    'Start previews use cached membership, earned badges, connections and activity',
    (tester) async {
      final api = _api(
        summary: const UserSummary(
          mostRepliedToUsers: [
            UserSummaryUser(id: 1, username: 'sam', name: 'Sam', count: 2),
          ],
          mostLikedByUsers: [
            UserSummaryUser(id: 2, username: 'alex', name: 'Alex', count: 3),
          ],
          mostLikedUsers: [
            UserSummaryUser(id: 1, username: 'sam', name: 'Sam', count: 4),
          ],
        ),
        activity: const [
          UserActivityItem(
            actionType: 5,
            topicId: 1,
            postNumber: 7,
            title: 'A recent reply',
            slug: 'recent',
            username: 'reader',
            excerpt: 'Searchable answer',
          ),
        ],
        responses: const {
          'GET /groups.json?asc=true': {
            'groups': [
              {'id': 1, 'name': 'sailors', 'is_group_user': true},
              {'id': 2, 'name': 'staff'},
            ],
          },
          'GET /badges.json?only_listable=true': {
            'badges': [
              {
                'id': 1,
                'name': 'First Like',
                'has_badge': true,
                'badge_type_id': 3,
              },
              {
                'id': 2,
                'name': 'Unseen badge',
                'has_badge': false,
                'badge_type_id': 1,
              },
            ],
          },
        },
      );
      final shell = await _start(tester, desktop, api: api);
      final site = shell.currentInstance!;
      await shell.userSummary.load(site);
      await shell.accountActivity.loadUserActivity(site);
      await shell.groups.loadDirectory(site, const GroupDirectoryQuery());
      await shell.badges.load(site, const BadgeRoute.directory());
      await tester.pumpAndSettle();
      expect(_onPage(find.text('A recent reply')), findsOneWidget);
      expect(_onPage(find.text('sailors')), findsOneWidget);
      expect(_onPage(find.text('staff')), findsNothing);
      expect(_onPage(find.text('First Like')), findsOneWidget);
      expect(_onPage(find.text('Unseen badge')), findsNothing);
      expect(_onPage(find.byType(BadgeMedal)), findsOneWidget);
      expect(
        tester.getTopLeft(_onPage(find.text('Sam'))).dy,
        lessThan(tester.getTopLeft(_onPage(find.text('Alex'))).dy),
      );
      final channels = find.descendant(
        of: _section('Channels'),
        matching: find.text('General'),
      );
      expect(channels, findsOneWidget);
      final calls = api.pluginReadPaths.length;
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();
      expect(api.pluginReadPaths, hasLength(calls));
      final activity = _onPage(find.text('A recent reply'));
      await Scrollable.ensureVisible(tester.element(activity), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(activity);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 1);
      expect(shell.currentContent?.postNumber, 7);
      expect(tester.takeException(), isNull);
    },
  );

  _test('alphabet press and drag land below the header without opening rows', (
    tester,
  ) async {
    final shell = await _start(tester, phone);
    final index = _onPage(find.byType(DAlphabetIndex<String>));
    final u = find.descendant(of: index, matching: find.text('U'));
    await tester.tap(u);
    await tester.pumpAndSettle();
    final filter = _onPage(find.byKey(const ValueKey('topic-list-filter')));
    final users = _section('Users');
    expect(
      tester.getRect(users).top,
      greaterThan(tester.getRect(filter).bottom),
    );
    expect(users.hitTestable(), findsOneWidget);
    expect(shell.currentContent?.isNewTab, isTrue);
    final b = find.descendant(of: index, matching: find.text('B'));
    final gesture = await tester.startGesture(tester.getCenter(u));
    await gesture.moveTo(tester.getCenter(b));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_section('Badges').hitTestable(), findsOneWidget);
    expect(shell.currentContent?.isNewTab, isTrue);
    await tester.tapAt(tester.getTopLeft(index) + const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(_section('Activity').hitTestable(), findsOneWidget);
    expect(shell.currentContent?.isNewTab, isTrue);
    expect(tester.takeException(), isNull);
  }, platform: TargetPlatform.iOS);

  for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
    _test('native Start list fits phone and large text in $mode', (
      tester,
    ) async {
      final shell = await _start(tester, phone);
      await shell.forumSettings.setThemeMode(_site, mode);
      await tester.pumpAndSettle();
      await _capture(tester, 'phone-${mode.name}');
      expect(
        _onPage(find.byKey(const ValueKey('start-page-more'))),
        findsNothing,
      );
      final settings = _onPage(
        find.byKey(const ValueKey('start-page-section-link-Settings')),
      );
      await Scrollable.ensureVisible(tester.element(settings), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, 'appearance');
      shell.pushContent(ContentRoute.newTab());
      tester.view.physicalSize = const Size(320, 1000);
      await shell.appSettings.setTextScale(AppTextScale.percent200);
      await tester.pumpAndSettle();
      expect(_section('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'large-text-${mode.name}');
    }, platform: TargetPlatform.iOS);
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
