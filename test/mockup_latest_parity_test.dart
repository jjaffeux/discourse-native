import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/fakes.dart';
import 'support/media_pipeline.dart';
import 'support/topic_post_list.dart';

const _barTitle = ValueKey('mobile-page-title');

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('captureMockupParity')) return;
  await tester.runAsync(() async {
    final builder = ui.SceneBuilder();
    tester.binding.renderViews.first.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(390, 844);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/private/tmp/native-mockup-$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    scene.dispose();
  });
}

Future<void> _verifySearchLabelAndCapture(
  WidgetTester tester,
  String state,
  String label,
) async {
  if (!const bool.fromEnvironment('captureMockupParity')) return;
  final finder = find.text(label);
  final text = tester.renderObject<RenderBox>(finder);
  final baseline = text.localToGlobal(
    Offset(
      0,
      text.getDryBaseline(
        BoxConstraints.tight(text.size),
        TextBaseline.alphabetic,
      )!,
    ),
  );
  final sheet = tester.getRect(find.byType(DSheetContent));
  // The rendered 390 × 844 mockup puts every empty label's alphabetic
  // baseline 116.98 points below the top of the sheet.
  expect(baseline.dy - sheet.top, closeTo(116.98, .75), reason: state);
  expect(tester.getRect(finder).left - sheet.left, closeTo(22.06, .25));
  await _capture(tester, 'search-label-$state');
}

void main() {
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
    if (const bool.fromEnvironment('captureMockupParity')) {
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
    }
  });
  tearDownAll(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          null,
        ),
  );
  testWidgets('phone topic raises its sheet, yields its title and floats tools', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(
      tester,
      topic: topicPayload(
        id: 7,
        title: 'A closed community discussion',
        closed: true,
        posts: [
          for (var id = 1; id <= 30; id++)
            Post(
              id: id,
              postNumber: id,
              username: 'reader',
              createdAt: DateTime.utc(2026, 10, 29),
              cooked:
                  '<p>${List.filled(30, 'A community discussion.').join(' ')}</p>',
            ),
        ],
      ),
    );
    if (const bool.fromEnvironment('captureMockupParity')) {
      await shell.forumSettings.setShared(
        shell.forumSettings.shared.copyWith(
          font: ForumFont.lato,
          interfaceFont: ForumFont.lato,
        ),
      );
      await tester.pumpAndSettle();
    }
    expect(find.byKey(_barTitle).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('topic-card-7')));
    await tester.pumpAndSettle();
    final sheet = find.byType(DSheetContent);
    final handle = find.byKey(const ValueKey('sheet-drag-handle'));
    expect(tester.getRect(sheet).top, 8);
    expect(tester.getRect(handle).top, 16);
    expect(find.byKey(_barTitle).hitTestable(), findsNothing);
    expect(
      find.byKey(const ValueKey('topic-header-compact-layout')),
      findsNothing,
    );
    final tools = find.byKey(const ValueKey('topic-more-actions'));
    final progress = find.byKey(const ValueKey('topic-progress-button'));
    expect(tester.getSize(tools), const Size(40, 40));
    // Where you are is as tall as the dock's circle (540cbac).
    expect(
      tester.getSize(progress).height,
      DMobileDockGeometry.of(
        tester.element(find.byKey(const ValueKey('mobile-bottom-bar'))),
      ).circle,
    );
    expect(tester.getRect(tools).top, greaterThan(650));
    await _capture(tester, 'topic-open');
    final scroll = topicPostList(tester).controller!;
    final firstPost = find.byKey(const ValueKey(1));
    final firstTop = tester.getTopLeft(firstPost).dy;
    scroll.jumpTo(20);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(firstPost).dy, closeTo(firstTop - 20, .1));
    expect(tester.getRect(handle).top, 36);
    await _capture(tester, 'topic-partial');
    scroll.jumpTo(600);
    await tester.pumpAndSettle();
    await _capture(tester, 'topic-scrolled');
    expect(find.byKey(_barTitle).hitTestable(), findsOneWidget);
    expect(
      tester.getRect(handle).top,
      tester.getRect(find.byKey(const ValueKey('mobile-header'))).bottom + 14,
    );
    final pull = await tester.startGesture(tester.getCenter(handle));
    await pull.moveBy(const Offset(0, 20));
    await pull.moveBy(const Offset(0, 90));
    await tester.pump();
    final barContext = tester.element(find.byKey(_barTitle));
    expect(
      DSheetDragScope.dismissProgressOf(barContext)!.value,
      inExclusiveRange(0, 1),
    );
    expect(DPageHeaderHost.previousTitleOf(barContext)?.title, 'Latest topics');
    await _capture(tester, 'topic-pull');
    await pull.cancel();
    await tester.pumpAndSettle();
    expect(DSheetDragScope.dismissProgressOf(barContext)!.value, 0);
    await tester.tap(find.byKey(_barTitle));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(tester.getRect(handle).top, 16);
    scroll.jumpTo(600);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-home-button')));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'latest');
    expect(sheet, findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('forum mark clears filters and then scrolls Latest to its top', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(
      tester,
      topics: [
        for (var id = 1; id <= 60; id++)
          Topic(id: id, title: 'Discussion $id', slug: 'discussion-$id'),
      ],
    );
    shell.selectTopicListCategory(
      const TopicCategory(
        id: 5,
        name: 'Support',
        slug: 'support',
        color: '0088cc',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-home-button')));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'latest');
    expect(shell.currentContent?.topicFilterQuery, isEmpty);
    final list = find.byType(TopicListView);
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    final scroll = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(scroll.pixels, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('mobile-home-button')));
    await tester.pumpAndSettle();
    expect(scroll.pixels, 0);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  testWidgets('phone Search keeps the filtered empty footer in view', (
    tester,
  ) async {
    const tag = TopicTag(id: 1, name: 'sourdough');
    const topics = [
      Topic(
        id: 7,
        title: "What's everyone's sourdough hydration sweet spot? 🍞",
        excerpt:
            "I've been experimenting between 72% and 80% hydration. How do you find the right balance?",
        likeCount: 14,
        pinned: true,
        slug: 'sourdough-hydration',
        tags: [tag],
        postsCount: 35,
      ),
      Topic(
        id: 8,
        title:
            'Leeds starter swap and bake-off at The Crown, Saturday 24 October',
        slug: 'starter-swap',
        excerpt:
            'Meet us at the Crown on Saturday to swap starters, bake bread, and compare notes.',
        postsCount: 20,
        likeCount: 8,
        tags: [tag],
      ),
      Topic(
        id: 9,
        title:
            "Is it rude to bring your own sourdough to someone else's dinner?",
        slug: 'sourdough-dinner',
        excerpt:
            "A friend served a supermarket bloomer. I'd brought a loaf as a gift. How would you handle it?",
        postsCount: 27,
        likeCount: 10,
        tags: [tag],
      ),
    ];
    final shell = await pumpMobileShellFixture(
      tester,
      topics: topics,
      pluginResponses: {
        for (final (query, hasResults) in [
          ('zzzzzz tags:sourdough', false),
          ('tags:sourdough', true),
          ('zzzzzz order:latest', false),
          ('zzzzzz', false),
        ])
          'GET ${Uri(path: '/search.json', queryParameters: {'q': query, 'page': '1'})}':
              {
                'topics': [
                  if (hasResults)
                    for (final topic in topics)
                      {
                        'id': topic.id,
                        'title': topic.title,
                        'slug': topic.slug,
                        'posts_count': topic.postsCount,
                        'like_count': topic.likeCount,
                        'pinned': topic.pinned,
                      },
                ],
                'posts': [
                  if (hasResults)
                    for (final topic in topics)
                      {
                        'id': topic.id,
                        'topic_id': topic.id,
                        'post_number': 1,
                        'blurb': topic.excerpt,
                      },
                ],
                'grouped_search_result': {'more_full_page_results': false},
              },
        for (final params in [
          {'term': 'zzzzzz'},
          {'term': 'zzzzzz', 'type_filter': 'private_messages'},
        ])
          'GET ${Uri(path: '/search/query.json', queryParameters: params)}': {},
      },
      filterOptions: const [TopicFilterOption(name: 'tag:', type: 'tag')],
      onApi: (api) {
        api.feeds['/tag/sourdough/l/latest.json'] = topics;
        api.feeds['/latest.json?tags%5B%5D=sourdough'] = topics;
        api.feeds['/filter.json'] = const [];
        api.feeds['/filter.json?q=order%3Alatest-post'] = topics;
        for (final key in ['tag', 'tags']) {
          for (final (words, rows) in [('', topics), (' zzzzzz', <Topic>[])]) {
            final path = Uri(
              path: '/filter.json',
              queryParameters: {'q': '$key:sourdough$words'},
            );
            api.feeds[path.toString()] = rows;
          }
        }
      },
    );
    await shell.forumSettings.setShared(
      shell.forumSettings.shared.copyWith(interfaceFont: ForumFont.lato),
    );
    await shell.forumSettings.setThemes(
      shell.currentInstance!.url,
      ForumThemePreferences.preset('dracula'),
    );
    await shell.forumSettings.setThemeMode(
      shell.currentInstance!.url,
      AppThemeMode.dark,
    );
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('mobile-search-button'));
    final field = find.byKey(ForumSearch.inputKey);
    final surface = find.byType(DSheetContent);
    final footer = find.byKey(const ValueKey('global-search-phone-footer'));

    await tester.tap(search);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'tag:sourdough zzzzzz');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final filteredEmpty = tester.getRect(surface);
    final fieldGroup = find.ancestor(
      of: field,
      matching: find.byType(DInputGroup),
    );
    expect(filteredEmpty.bottom, closeTo(844, .1));
    expect(tester.getRect(fieldGroup).top - filteredEmpty.top, closeTo(24, .1));
    final emptyMessage = find.text('No results for “tag:sourdough zzzzzz”');
    final tagChip = find.descendant(
      of: footer,
      matching: find.byType(DFilterToken),
    );
    final scopes = find.byKey(const ValueKey('global-search-scope-all'));
    expect(emptyMessage, findsOneWidget);
    expect(find.text('Clear conditions'), findsNothing);
    expect(scopes, findsNothing);
    expect(tagChip, findsOneWidget);
    expect(tester.getRect(tagChip).bottom, closeTo(825, .1));
    expect(
      filteredEmpty.height,
      lessThan(tester.view.physicalSize.height * .4),
    );
    if (const bool.fromEnvironment('captureMockupParity')) {
      expect(filteredEmpty.height, closeTo(236, 2));
    }
    await _verifySearchLabelAndCapture(
      tester,
      'filtered',
      'No results for “tag:sourdough zzzzzz”',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(search);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'tag:sourdough ');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final filteredResults = tester.getRect(surface);
    expect(filteredResults.bottom, closeTo(filteredEmpty.bottom, .1));
    expect(filteredResults.height, greaterThan(filteredEmpty.height));
    if (const bool.fromEnvironment('captureMockupParity')) {
      expect(filteredResults.height, closeTo(560.84, 1));
    }
    expect(shell.globalSearch.results, hasLength(topics.length));
    await _capture(tester, 'search-filtered-results');
    await tester.enterText(field, 'zzzzzz');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(emptyMessage, findsOneWidget);
    expect(tester.getRect(surface).top, closeTo(filteredResults.top, .01));
    expect(tester.getRect(tagChip).bottom, closeTo(825, .1));
    await _verifySearchLabelAndCapture(
      tester,
      'filtered-retained',
      'No results for “tag:sourdough zzzzzz”',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(search);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'order:latest zzzzzz');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('No results for “order:latest zzzzzz”'), findsOneWidget);
    expect(scopes.hitTestable(), findsOneWidget);
    expect(tester.getRect(tagChip).left, closeTo(16, .1));
    expect(tester.getRect(tagChip).bottom, closeTo(825, .1));
    await _verifySearchLabelAndCapture(
      tester,
      'ordered',
      'No results for “order:latest zzzzzz”',
    );
    await tester.tap(find.byTooltip('Remove Ordering condition'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(tagChip, findsNothing);
    expect(find.text('No results for “zzzzzz”'), findsOneWidget);
    expect(scopes.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('phone Search shows artwork on an uncached topic', (
    tester,
  ) async {
    const response = {
      'topics': [
        {
          'id': 71,
          'title': "What's everyone's sourdough hydration sweet spot? 🍞",
          'slug': 'sourdough-hydration',
          'pinned': true,
          'bookmarked': true,
          'posts_count': 35,
        },
      ],
      'posts': [
        {
          'id': 171,
          'topic_id': 71,
          'post_number': 1,
          'username': 'felix',
          'like_count': 14,
          'blurb': "I've been experimenting between 72% and 82%.",
        },
      ],
      'grouped_search_result': {'more_full_page_results': false},
    };
    final shell = await pumpMobileShellFixture(
      tester,
      pluginResponses: {
        'GET /search/query.json?term=hydration': response,
        'GET /search/query.json?term=hydration&type_filter=private_messages':
            {},
        'GET /search.json?q=hydration&page=1': response,
      },
    );
    await shell.forumSettings.setShared(
      shell.forumSettings.shared.copyWith(interfaceFont: ForumFont.lato),
    );
    await shell.forumSettings.setThemes(
      shell.currentInstance!.url,
      ForumThemePreferences.preset('dracula'),
    );
    await shell.forumSettings.setThemeMode(
      shell.currentInstance!.url,
      AppThemeMode.dark,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(ForumSearch.inputKey), 'hydration');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final row = find.byKey(const ValueKey('search-row:forum:171'));
    expect(row, findsOneWidget);
    await _capture(tester, 'search-uncached-artwork');
    final icons = tester.widgetList<DIcon>(
      find.descendant(of: row, matching: find.byType(DIcon)),
    );
    expect(
      icons.map((icon) => icon.icon),
      containsAll([DIcons.thumbtack, DIcons.bookmark]),
    );
    expect(
      find.descendant(of: row, matching: find.byType(DAvatar)),
      findsOneWidget,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('phone Search shows topic posters and topic activity', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('captureMockupParity')) {
      await tester.runAsync(
        () => (FontLoader(
          'Lato',
        )..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))).load(),
      );
    }
    const title = "What's everyone's sourdough hydration sweet spot? 🍞";
    const excerpt =
        "I've been experimenting between 72% and 82% and keep landing back at 76%. "
        "Crumb is open enough without turning into a pancake. "
        "Curious if anyone's gone higher with good results on a home oven.";
    const posters = ['crumbcoat', 'verdant_vera', 'mossy_mo', 'flourpower'];
    final now = DateTime.now();
    final topic = {
      'id': 71,
      'title': title,
      'slug': 'sourdough-hydration',
      'pinned': true,
      'category_id': 6,
      'tags': ['sourdough'],
      'posts_count': 35,
      'unread_posts': 4,
      'highest_post_number': 35,
      'last_read_post_number': 31,
      'bumped_at': now.subtract(const Duration(minutes: 22)).toIso8601String(),
    };
    const term = 'hydration sweet spot';
    final searchResponse = {
      'topics': [topic],
      'posts': [
        {
          'id': 171,
          'topic_id': 71,
          'post_number': 1,
          'username': posters.first,
          'avatar_template': '/avatar/${posters.first}.png',
          'like_count': 2,
          'blurb': excerpt,
          'created_at': now.subtract(const Duration(days: 5)).toIso8601String(),
        },
      ],
      'grouped_search_result': {'more_full_page_results': false},
    };
    String get(String path, Map<String, String> query) =>
        'GET ${Uri(path: path, queryParameters: query)}';
    final metadata = Completer<void>();
    final metadataPath = Uri(
      path: '/filter.json',
      queryParameters: {'q': 'topic:71'},
    ).toString();
    final shell = await pumpMobileShellFixture(
      tester,
      onApi: (api) => api.pluginReadGates[metadataPath] = metadata,
      emojis: const [
        SiteEmoji(
          name: 'bread',
          url: 'https://meta.discourse.org/images/emoji/twitter/bread.png',
        ),
      ],
      sidebarCategories: const [
        TopicCategory(id: 6, name: 'baking', slug: 'baking', color: 'f2a800'),
      ],
      pluginResponses: {
        get('/search/query.json', {'term': term}): searchResponse,
        get('/search/query.json', {'term': 'zzzzzz'}): {},
        get('/search/query.json', {
          'term': 'zzzzzz',
          'type_filter': 'private_messages',
        }): {},
        get('/search/query.json', {
          'term': term,
          'type_filter': 'private_messages',
        }): {},
        'GET $metadataPath': {
          'users': [
            for (final (index, username) in posters.indexed)
              {
                'id': index + 1,
                'username': username,
                'avatar_template': '/avatar/$username.png',
              },
          ],
          'topic_list': {
            'topics': [
              {
                ...topic,
                'like_count': 14,
                'posters': [
                  for (final (index, _) in posters.indexed)
                    {
                      'user_id': index + 1,
                      'extras': index == posters.length - 1 ? 'latest' : null,
                    },
                ],
              },
            ],
          },
        },
      },
    );
    if (const bool.fromEnvironment('captureMockupParity')) {
      final bread = File('/private/tmp/native-search-row-emoji-bread.png');
      final images = {
        if (bread.existsSync())
          '/images/emoji/twitter/bread.png': bread.readAsBytesSync(),
        for (final username in posters)
          if (File(
            '/private/tmp/native-search-row-avatar-$username.png',
          ).existsSync())
            '/avatar/$username.png': File(
              '/private/tmp/native-search-row-avatar-$username.png',
            ).readAsBytesSync(),
      };
      installTestMediaPipeline(
        client: MockClient((request) async {
          final bytes = images[request.url.path];
          return bytes == null
              ? http.Response('', 404)
              : http.Response.bytes(
                  bytes,
                  200,
                  headers: {'content-type': 'image/png'},
                );
        }),
      );
    }
    await shell.forumSettings.setShared(
      shell.forumSettings.shared.copyWith(interfaceFont: ForumFont.lato),
    );
    await shell.forumSettings.setThemes(
      shell.currentInstance!.url,
      ForumThemePreferences.preset('dracula'),
    );
    await shell.forumSettings.setThemeMode(
      shell.currentInstance!.url,
      AppThemeMode.dark,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
    await tester.pumpAndSettle();
    final sheet = find.byType(DSheetContent);
    final restingHeight = tester.getSize(sheet).height;
    await _verifySearchLabelAndCapture(
      tester,
      'history',
      'Nothing searched for lately.',
    );
    await tester.enterText(find.byKey(ForumSearch.inputKey), term);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    final row = find.byKey(const ValueKey('search-row:forum:171'));
    expect(row, findsOneWidget);
    final result = shell.globalSearch.results.single;
    expect(find.descendant(of: row, matching: find.text('2')), findsOneWidget);
    metadata.complete();
    await tester.pumpAndSettle();
    if (const bool.fromEnvironment('captureMockupParity')) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }
    final resultHeight = tester.getSize(sheet).height;
    final visibleExcerpt = tester
        .widgetList<RichText>(
          find.descendant(of: row, matching: find.byType(RichText)),
        )
        .map((richText) => richText.text.toPlainText())
        .singleWhere((text) => text.startsWith("I've been experimenting"));
    await _capture(tester, 'search-height-topic');

    expect(shell.globalSearch.results.single, same(result));
    expect(
      find.descendant(of: row, matching: find.byType(SiteEmojiImage)),
      findsOneWidget,
    );
    final faces = tester.widgetList<DAvatar>(
      find.descendant(of: row, matching: find.byType(DAvatar)),
    );
    expect(faces.map((avatar) => avatar.semanticLabel), posters);
    expect(
      faces.where((avatar) => avatar.ring).single.semanticLabel,
      posters.last,
    );
    for (final text in ['baking', '#sourdough', '34', '14', '22m', '4']) {
      expect(
        find.descendant(of: row, matching: find.text(text)),
        findsOneWidget,
      );
    }
    await tester.enterText(find.byKey(ForumSearch.inputKey), 'zzzzzz');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('No results for “zzzzzz”'), findsOneWidget);
    expect(tester.getSize(sheet).height, closeTo(resultHeight, .01));
    await _verifySearchLabelAndCapture(
      tester,
      'retained',
      'No results for “zzzzzz”',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(ForumSearch.inputKey), 'zzzzzz');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await _verifySearchLabelAndCapture(
      tester,
      'plain',
      'No results for “zzzzzz”',
    );
    if (const bool.fromEnvironment('captureMockupParity')) {
      expect(tester.getSize(sheet).height, closeTo(restingHeight, 1));
      expect(restingHeight, closeTo(235.84, 1.25));
      expect(resultHeight, closeTo(289.84, 1.25));
      expect(visibleExcerpt, endsWith('turning into a…'));
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('phone Search enriches an uncached private conversation', (
    tester,
  ) async {
    const topic = {
      'id': 172,
      'slug': 'bread-team-hub',
      'title': 'Bread team hub',
      'archetype': 'private_message',
      'posts_count': 4,
      'highest_post_number': 4,
      'last_read_post_number': 4,
    };
    const people = [
      {
        'id': 19,
        'username': 'priya_raman',
        'avatar_template': '/avatar/priya_raman.png',
      },
      {
        'id': 20,
        'username': 'bartholomew_beans',
        'avatar_template': '/avatar/bartholomew_beans.png',
      },
    ];
    final metadata = Completer<void>();
    final shell = await pumpMobileShellFixture(
      tester,
      onApi: (api) => api.pluginReadGates['/t/172.json'] = metadata,
      pluginResponses: {
        'GET /search/query.json?term=team+hub': {},
        'GET /search/query.json?term=team+hub&type_filter=private_messages': {
          'topics': [topic],
          'posts': [
            {
              'topic_id': 172,
              'post_number': 1,
              ...people.first,
              'id': 195,
              'like_count': 0,
              'blurb':
                  "This topic is the hub for the bread team's scope, goals and shared focus areas. "
                  "It is separate from individual project work: it captures what we are doing together.",
            },
          ],
        },
        'GET /t/172.json': {
          ...topic,
          'like_count': 1,
          'last_posted_at': DateTime.now()
              .subtract(const Duration(days: 32))
              .toIso8601String(),
          'details': {
            'created_by': people.first,
            'last_poster': people.last,
            'participants': people.reversed.toList(),
          },
        },
      },
    );
    if (const bool.fromEnvironment('captureMockupParity')) {
      final images = {
        for (final (fileName, username) in [
          ('Priya Raman', 'priya_raman'),
          ('bartholomew_beans', 'bartholomew_beans'),
        ])
          if (File(
            '/private/tmp/native-search-pm-avatar-$fileName.png',
          ).existsSync())
            '/avatar/$username.png': File(
              '/private/tmp/native-search-pm-avatar-$fileName.png',
            ).readAsBytesSync(),
      };
      installTestMediaPipeline(
        client: MockClient((request) async {
          final bytes = images[request.url.path];
          return bytes == null
              ? http.Response('', 404)
              : http.Response.bytes(
                  bytes,
                  200,
                  headers: {'content-type': 'image/png'},
                );
        }),
      );
    }
    await shell.forumSettings.setShared(
      shell.forumSettings.shared.copyWith(interfaceFont: ForumFont.lato),
    );
    await shell.forumSettings.setThemes(
      shell.currentInstance!.url,
      ForumThemePreferences.preset('dracula'),
    );
    await shell.forumSettings.setThemeMode(
      shell.currentInstance!.url,
      AppThemeMode.dark,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
    await tester.pumpAndSettle();
    final sheet = find.byType(DSheetContent);
    final restingHeight = tester.getSize(sheet).height;
    await _capture(tester, 'search-height-message-start');
    await tester.enterText(find.byKey(ForumSearch.inputKey), 'team hub');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final row = find.byKey(const ValueKey('search-row:forum:195'));
    final avatars = find.descendant(of: row, matching: find.byType(DAvatar));
    expect(avatars, findsOneWidget);
    final result = shell.globalSearch.results.single;
    metadata.complete();
    await tester.pumpAndSettle();
    if (const bool.fromEnvironment('captureMockupParity')) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }
    final resultHeight = tester.getSize(sheet).height;
    final visibleExcerpt = tester
        .widgetList<RichText>(
          find.descendant(of: row, matching: find.byType(RichText)),
        )
        .map((richText) => richText.text.toPlainText())
        .singleWhere((text) => text.startsWith("This topic is the hub"));
    await _capture(tester, 'search-height-message');

    expect(shell.globalSearch.results.single, same(result));
    expect(
      tester.widgetList<DAvatar>(avatars).map((avatar) => avatar.semanticLabel),
      ['priya_raman', 'bartholomew_beans'],
    );
    expect(tester.widgetList<DAvatar>(avatars).last.ring, isTrue);
    expect(
      find.descendant(of: row, matching: find.text('Private conversation')),
      findsOneWidget,
    );
    expect(find.descendant(of: row, matching: find.text('1')), findsOneWidget);
    if (const bool.fromEnvironment('captureMockupParity')) {
      expect(restingHeight, closeTo(235.84, 1.25));
      expect(resultHeight, closeTo(314.84, 1.25));
      expect(visibleExcerpt, endsWith('project work: it…'));
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('phone search edits the exact query of its source feed', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(
      tester,
      onApi: (api) {
        api.feeds['/filter.json'] = const [];
        for (final (query, id, title) in [
          ('posts-min:17', 7, 'Seventeen posts about the keyboard'),
          ('posts-min:20', 8, 'Twenty posts or more'),
          ('posts-min:20 keyboard', 8, 'Twenty posts about the keyboard'),
          ('keyboard', 9, 'One post about the keyboard'),
        ]) {
          final path = Uri(path: '/filter.json', queryParameters: {'q': query});
          api.feeds[path.toString()] = [
            Topic(id: id, title: title, slug: 'keyboard'),
          ];
        }
      },
      filterOptions: const [
        TopicFilterOption(name: 'posts-min:', type: 'number'),
        TopicFilterOption(name: 'status:'),
        TopicFilterOption(name: 'status:closed'),
      ],
    );
    await shell.forumSettings.setShared(
      shell.forumSettings.shared.copyWith(interfaceFont: ForumFont.lato),
    );
    await shell.applyTopicListFilterQuery('posts-min:17');
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicFilterQuery, 'posts-min:17');
    expect(find.byKey(const ValueKey('topic-list-filter')), findsNothing);
    await _capture(tester, 'feed-filters-after-feed');
    await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
    await tester.pumpAndSettle();
    final input = find.byKey(ForumSearch.inputKey);
    const applied = ValueKey('search-edit-feed-clause:posts-min:17');
    expect(input, findsOneWidget);
    expect(find.byKey(applied), findsOneWidget);
    await _capture(tester, 'search-single-field-entry');
    await _capture(tester, 'feed-filters-after-search');

    await tester.tap(find.byKey(const ValueKey('search-filters-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topic-filter-input')), findsOneWidget);
    expect(input, findsNothing);
    expect(find.text('Apply 1 filter'), findsNothing);
    final sheet = find.byType(DSheetContent);
    expect(tester.getRect(sheet).top, 8);
    await _capture(tester, 'feed-filters-after-picker');
    await tester.tap(find.byKey(const ValueKey('search-back-to-results')));
    await tester.pumpAndSettle();
    expect(find.byKey(applied), findsOneWidget);
    final original = tester.widget<DInputGroupInput>(input).controller;
    await tester.tap(find.byKey(applied));
    await tester.pumpAndSettle();
    expect(tester.widget<DInputGroupInput>(input).controller, same(original));
    expect(original!.text, 'posts-min:17');
    await tester.enterText(input, 'posts-m');
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    final suggestion = find.byKey(const ValueKey('feed-filter:posts-min:'));
    expect(suggestion, findsOneWidget);
    await _capture(tester, 'search-single-field-editor');
    await tester.tap(suggestion);
    await tester.pumpAndSettle();
    expect(original.text, 'posts-min:');
    await tester.enterText(input, 'posts-min:20 keyboard');
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('search-apply-feed-filters')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('search-edit-feed-clause:posts-min:20')),
      findsOneWidget,
    );
    expect(original.text, 'keyboard');
    expect(
      shell
          .mobileNavigation
          .previousLocation
          ?.contentStack
          .last
          .topicFilterQuery,
      'posts-min:20',
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(
      find.byKey(const ValueKey('global-search-result-filter-topic:8')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('global-search-result-filter-topic:7')),
      findsNothing,
    );
    await _capture(tester, 'search-single-field-ready');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicFilterQuery, 'posts-min:20 keyboard');
    expect(find.byKey(ForumSearch.inputKey), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('search-remove-feed-clause:posts-min:20')),
    );
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicFilterQuery, 'keyboard');
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing a topic filter reopens a visited list at its top', (
    tester,
  ) async {
    const support = TopicCategory(
      id: 5,
      name: 'Support',
      slug: 'support',
      color: '0088cc',
    );
    final shell = await pumpMobileShellFixture(
      tester,
      sidebarCategories: const [support],
      topics: [
        for (var id = 1; id <= 60; id++)
          Topic(
            id: id,
            title: 'Discussion $id',
            slug: 'discussion-$id',
            excerpt: id == 1 ? 'A short topic excerpt' : null,
          ),
      ],
    );
    final row = find.byKey(const ValueKey('topic-card-1'));
    for (final (label, size) in [
      ('Discussion 1', 16.0),
      ('A short topic excerpt', 14.0),
      ('—', 13.0),
    ]) {
      final match = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) => widget is RichText && widget.text.toPlainText() == label,
        ),
      );
      final text = tester.widget<RichText>(match);
      expect(text.textScaler.scale(text.text.style!.fontSize!), size);
    }
    final list = find.byType(TopicListView);
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(position().pixels, greaterThan(0));

    shell.selectTopicListCategory(support);
    await tester.pumpAndSettle();
    expect(shell.topicListContent?.categoryId, 5);
    shell.clearTopicListFilters();
    await tester.pumpAndSettle();
    expect(shell.topicListContent?.id, 'latest');
    await _capture(tester, 'list-after-filter-reset');
    expect(position().pixels, 0);
    expect(
      find.byKey(const ValueKey('topic-list-feed-menu')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
