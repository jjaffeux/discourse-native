import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
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
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/new_tab_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
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
    const ContentRoute(
      destination: ExtensionDestination('chat-c-9'),
      title: 'General',
      icon: DIcons.comment,
    ),
  );
  shell.pushContent(
    const ContentRoute(
      destination: ExtensionDestination('chat-c-10'),
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

  Finder shortcut(String label) =>
      _onPage(find.byKey(ValueKey('start-page-section-link-$label')));
  Finder launchers() => _onPage(
    find.byWidgetPredicate(
      (widget) =>
          widget is DButton && widget.variant == DButtonVariant.launcher,
    ),
  );

  testWidgets(
    'scrolling reuses start-page artwork without a page header',
    (tester) async {
      await _start(tester, const Size(390, 400));
      final content = tester.renderObject<RenderObject>(
        _onPage(find.byKey(const ValueKey('start-page-content'))),
      );
      final artwork = <RenderObject>{};
      void collect(RenderObject object) {
        artwork.add(object);
        object.visitChildren(collect);
      }

      collect(content);
      final position = tester
          .state<ScrollableState>(_onPage(find.byType(Scrollable)))
          .position;
      expect(position.maxScrollExtent, greaterThan(200));
      final viewport = position.viewportDimension;
      final extent = position.maxScrollExtent;
      final header = DPageSurface.headerGeometryOf(
        tester.element(
          _onPage(find.byKey(const ValueKey('start-page-content'))),
        ),
        insideViewport: true,
      );
      expect(header, isNull);
      var paints = 0;
      final previous = debugOnProfilePaint;
      debugOnProfilePaint = (object) {
        previous?.call(object);
        if (artwork.contains(object)) paints++;
      };
      try {
        for (final delta in [120.0, 120.0, -120.0, -120.0]) {
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

  _test('Start is an alphabetical square launcher with settings last', (
    tester,
  ) async {
    await _start(tester, const Size(1800, 1000));
    final buttons = tester.widgetList<DButton>(launchers()).toList();
    final names = buttons.map((b) => (b.label as Text).data!).toList();
    expect(
      names.take(names.length - 2),
      orderedEquals([...names.take(names.length - 2)]..sort()),
    );
    expect(names.sublist(names.length - 2), ['Preferences', 'Settings']);
    expect(
      names,
      containsAll([
        'Activity',
        'Badges',
        'Bookmarks',
        'Categories',
        'Channels',
        'Chat',
        'Groups',
        'Messages',
        'Summary',
        'Threads',
        'Topics',
        'Users',
      ]),
    );
    for (final button in launchers().evaluate()) {
      final rect = tester.getRect(find.byWidget(button.widget));
      expect(rect.width, closeTo(rect.height, .01));
    }
    expect(_onPage(find.byType(DAlphabetIndex<String>)), findsNothing);
    expect(_onPage(find.byType(DToggle)), findsNothing);
    expect(_onPage(find.text('Welcome to the community')), findsNothing);
    expect(_onPage(find.text('General')), findsNothing);
    expect(_onPage(find.text('A discussion worth keeping')), findsNothing);
    expect(_onPage(find.text('Support')), findsNothing);
    await _capture(tester, 'desktop-launcher');
  });

  for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
    _test('Start launcher hover uses the flat mockup tint in $mode', (
      tester,
    ) async {
      final shell = await _start(tester, desktop);
      await shell.forumSettings.setThemeMode(_site, mode);
      await tester.pumpAndSettle();
      final activity = shortcut('Activity');
      final bounds = tester.getRect(activity);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(bounds.center);
      await tester.pumpAndSettle();
      final surface = buttonSurface(tester, of: activity);
      expect(
        surface.color,
        (mode == AppThemeMode.dark ? Colors.white : Colors.black).withValues(
          alpha: mode == AppThemeMode.dark ? .055 : .045,
        ),
      );
      expect(surface.borderColor.a, 0);
      expect(tester.getRect(activity), bounds);
      await _capture(tester, 'desktop-launcher-hover-${mode.name}');
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(buttonSurface(tester, of: activity).color.a, 0);
      expect(tester.takeException(), isNull);
    });
  }

  _test('Recently closed is a bare list above the shortcut grid', (
    tester,
  ) async {
    final shell = await _start(tester, desktop);
    final closed = <String>[];
    for (final topic in _topics.take(2)) {
      shell.createTab(panel: ForumPanel.main);
      shell.pushContent(
        ContentRoute.topic(
          topicId: topic.id,
          slug: topic.slug,
          title: topic.title,
        ),
      );
      closed.add(shell.activeTabId!);
      shell.closeTab(shell.activeTabId!);
    }
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    final section = _section('Recently closed');
    expect(section, findsOneWidget);
    expect(
      find.descendant(of: section, matching: find.byType(DCard)),
      findsNothing,
    );
    final rows = [
      for (final id in closed)
        _onPage(find.byKey(ValueKey('start-page-recent-closed-$id'))),
    ];
    expect(tester.getRect(rows.first).width, tester.getRect(rows.last).width);
    expect(
      tester.getTopLeft(rows.last).dy,
      lessThan(tester.getTopLeft(rows.first).dy),
    );
    expect(
      tester.getBottomLeft(section).dy,
      lessThan(tester.getTopLeft(launchers().first).dy),
    );
    await _capture(tester, 'desktop-closed-launcher');
  });

  _test('Start omits Filters and opening a shortcut navigates to its page', (
    tester,
  ) async {
    final api = _api();
    final shell = await _start(tester, desktop, api: api);
    final requests = [...api.feedPaths];
    expect(_onPage(find.text('Filters')), findsNothing);
    await tester.tap(shortcut('Topics'));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'latest');
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(api.feedPaths, requests);
    final settings = shortcut('Settings');
    await Scrollable.ensureVisible(tester.element(settings), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'appearance');
  });

  _test(
    'search counts only closed matches and never removes launcher destinations',
    (tester) async {
      final shell = await _start(tester, desktop);
      shell.createTab(panel: ForumPanel.main);
      shell.pushContent(
        ContentRoute.topic(
          topicId: 1,
          title: _topics.first.title,
          slug: 'welcome',
        ),
      );
      final closed = shell.activeTabId!;
      shell.closeTab(closed);
      shell.createTab(panel: ForumPanel.main);
      await tester.pumpAndSettle();
      final count = launchers().evaluate().length;
      shell.search.setStartPageQuery(_site, shell.activeTabId!, 'community');
      await tester.pumpAndSettle();
      expect(
        _onPage(find.byKey(ValueKey('start-page-recent-closed-$closed'))),
        findsOneWidget,
      );
      expect(_onPage(find.text('1 result for “community”')), findsOneWidget);
      expect(launchers().evaluate().length, count);
      shell.search.setStartPageQuery(
        _site,
        shell.activeTabId!,
        'nothing matches',
      );
      await tester.pumpAndSettle();
      expect(_section('Recently closed'), findsNothing);
      expect(
        _onPage(find.text('Nothing matches “nothing matches”')),
        findsOneWidget,
      );
      expect(launchers().evaluate().length, count);
      expect(shortcut('Topics'), findsOneWidget);
    },
  );

  _test('Drafts appears only when there is a resumable cached draft', (
    tester,
  ) async {
    final api = _api(
      drafts: [
        const UserDraft(
          key: 'new_topic',
          sequence: 1,
          title: 'Unfinished topic',
          data: ComposerDraft(
            reply: 'A reply',
            action: 'createTopic',
            title: 'Unfinished topic',
          ),
        ),
      ],
    );
    final shell = await _start(tester, desktop, api: api);
    expect(shortcut('Drafts'), findsNothing);
    await shell.draftList.load(shell.currentInstance!);
    await tester.pumpAndSettle();
    expect(shortcut('Drafts'), findsOneWidget);
    expect(_onPage(find.text('Unfinished topic')), findsNothing);
    await tester.tap(shortcut('Drafts'));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'drafts');
  });

  _test('anonymous Start exposes only permitted destinations', (tester) async {
    await pumpShell(
      tester,
      desktop,
      instances: [instance('meta.discourse.org')],
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    for (final name in [
      'Activity',
      'Bookmarks',
      'Drafts',
      'Messages',
      'Preferences',
      'Summary',
    ]) {
      expect(shortcut(name), findsNothing);
    }
    expect(shortcut('Topics'), findsOneWidget);
    expect(shortcut('Settings'), findsOneWidget);
  });

  for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
    _test('launcher fits phone and large text in $mode', (tester) async {
      final shell = await _start(tester, phone);
      await shell.forumSettings.setThemeMode(_site, mode);
      await tester.pumpAndSettle();
      await _capture(tester, 'phone-${mode.name}');
      tester.view.physicalSize = const Size(320, 1000);
      await shell.appSettings.setTextScale(AppTextScale.percent200);
      await tester.pumpAndSettle();
      final grid = _onPage(find.byKey(const ValueKey('start-page-shortcuts')));
      final bounds = tester.getRect(grid);
      for (final button in launchers().evaluate()) {
        final rect = tester.getRect(find.byWidget(button.widget));
        expect(rect.left, greaterThanOrEqualTo(bounds.left));
        expect(rect.right, lessThanOrEqualTo(bounds.right + .01));
        expect(rect.width, closeTo(rect.height, .01));
      }
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
