import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/global_search_models.dart';
import 'package:discourse_native/src/shell/global_search_panel.dart';
import 'package:discourse_native/src/shell/search_words.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

import 'support/global_search_fixtures.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment['SEARCH_CAPTURE'] == '1') {
      await (FontLoader('Lato')
            ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
          .load();
    }
  });
  test('all words match prose, while scope values are not words', () {
    expect(searchWords('Design keyboard category:support @sam'), [
      'keyboard',
      'Design',
    ]);
    expect(
      searchWordsMatch('design keyboard', [
        'Keyboard access',
        'Design the flow',
      ]),
      isTrue,
    );
    expect(searchWordsMatch('design keyboard', ['Design the flow']), isFalse);
    expect(
      searchSnippet('${'lead ' * 30}keyboard match', 'keyboard'),
      startsWith('…'),
    );
    expect(searchWordPattern('c++ [x]')!.allMatches('C++ and [x]').length, 2);
  });

  test('HTML markers preserve links, escaping, code and interactive markup', () {
    final output = highlightSearchHtml(
      '<p>Design &amp; keyboard <a href="/design">design</a><code>design</code></p>',
      'design keyboard',
    );
    final fragment = html_parser.parseFragment(output);
    expect(fragment.querySelectorAll('mark').length, 3);
    expect(fragment.querySelector('a')!.attributes['href'], '/design');
    expect(fragment.querySelector('code')!.innerHtml, 'design');
    expect(fragment.text, 'Design & keyboard designdesign');
  });

  testWidgets('remote in-topic posts precede globally ordered result kinds', (
    tester,
  ) async {
    final wire = _SearchWireApi();
    final shell = createGlobalSearchFixtureController(api: wire);
    addTearDown(shell.dispose);
    await shell.load();
    final controller = shell.globalSearch;
    controller.configure(
      siteUrl: globalSearchFixtureSite,
      capabilities: const GlobalSearchCapabilities(authenticated: true),
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    controller.setPageContext(
      preferredScope: GlobalSearchScope.users,
      topicId: 1038,
      topicTitle: 'Current topic',
    );
    controller.setQuery('design keyboard');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(controller.sections.first.topicId, 1038);
    expect(controller.sections.first.topicTitle, 'Current topic');
    expect(
      (controller.sections.first.results.single.source as SearchPostHit)
          .postNumber,
      7,
    );
    expect(controller.sections[1].scope, GlobalSearchScope.users);
    expect(
      controller.results.map((row) => row.scope),
      containsAll([
        GlobalSearchScope.forum,
        GlobalSearchScope.categories,
        GlobalSearchScope.tags,
        GlobalSearchScope.messages,
      ]),
    );
    expect(
      controller.results.map((row) => row.id).toSet().length,
      controller.results.length,
    );
    expect(
      wire.requests.any(
        (request) =>
            request.uri.queryParameters['search_context[id]'] == '1038',
      ),
      isTrue,
    );
    expect(
      wire.requests.any(
        (request) => request.uri.queryParameters['term'] == 'design keyboard',
      ),
      isTrue,
    );
  });

  testWidgets(
    'staged filters keep words, replace the same key and retain word history',
    (tester) async {
      final shell = createGlobalSearchFixtureController();
      addTearDown(shell.dispose);
      await shell.load();
      final search = shell.globalSearch;
      search.configure(
        siteUrl: globalSearchFixtureSite,
        capabilities: const GlobalSearchCapabilities(authenticated: true),
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      search.setQuery('keyboard author:');
      expect(search.wordsQuery, 'keyboard');
      expect(search.stagedFilter?.id, 'author');
      search.completeFilter(
        const GlobalSearchCondition(filterId: 'author', value: ['sam']),
      );
      search.setQuery('keyboard Author:mira ');
      expect(search.conditions.single.text, 'mira');
      expect(search.query, 'keyboard ');
      search.submit();
      expect(search.recentSearches.first, 'keyboard @mira in:all-posts');
      search.removeRecentSearch(search.recentSearches.first);
      expect(search.recentSearches, isEmpty);
      search.setQuery('');
      search.submit();
      expect(search.recentSearches, isEmpty);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Enter applies words to the focused list and closes the one sheet',
    (tester) async {
      final shell = createGlobalSearchFixtureController();
      addTearDown(shell.dispose);
      await shell.load();
      shell.pushContent(ContentRoute.topicList(TopicListMode.unread));
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: SizedBox(
                width: 600,
                child: ForumSearch(showNavigationControls: false),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ForumSearch.inputKey));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ForumSearch.inputKey),
        'design keyboard',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsNothing);
      expect(shell.currentContent!.topicListSearch, 'design keyboard');
      expect(
        TopicListMode.fromRoute(shell.currentContent),
        TopicListMode.unread,
      );
      expect(
        shell.search.wordsFor(
          globalSearchFixtureSite,
          shell.activeTabId,
          shell.currentContent!.id,
        ),
        'design keyboard',
      );
      await tester.tap(find.byKey(ForumSearch.inputKey));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(shell.globalSearch.query.trim(), 'design keyboard');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'word highlights belong to their page and tab and retire with the account',
    (tester) async {
      final shell = createGlobalSearchFixtureController();
      addTearDown(shell.dispose);
      await shell.load();
      final search = shell.search;
      search.setPageWords(
        globalSearchFixtureSite,
        'left',
        'topic-1038',
        'design',
      );
      expect(
        search.wordsFor(globalSearchFixtureSite, 'left', 'topic-1038'),
        'design',
      );
      expect(
        search.wordsFor(globalSearchFixtureSite, 'right', 'topic-1038'),
        isEmpty,
      );
      expect(
        search.wordsFor(globalSearchFixtureSite, 'left', 'topic-1037'),
        isEmpty,
      );
      search.forget(globalSearchFixtureSite);
      expect(
        search.wordsFor(globalSearchFixtureSite, 'left', 'topic-1038'),
        isEmpty,
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
    },
  );

  for (final (width, dark, scale) in [
    (1440.0, false, 1.0),
    (1440.0, true, 1.0),
    (390.0, false, 1.0),
    (390.0, true, 2.0),
  ]) {
    testWidgets('search sheet render $width dark=$dark scale=$scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final shell = createGlobalSearchFixtureController(api: _SearchWireApi());
      addTearDown(shell.dispose);
      await shell.load();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
                textTheme: (dark ? AppTheme.dark : AppTheme.light).textTheme
                    .apply(fontFamily: "Lato"),
                platform: width < 700
                    ? TargetPlatform.iOS
                    : TargetPlatform.macOS,
              ),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 900),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: width < 700 ? width - 16 : 600,
                      child: const ForumSearch(showNavigationControls: false),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ForumSearch.inputKey));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ForumSearch.inputKey),
        'design keyboard',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.byType(GlobalSearchPanel), findsOneWidget);
      expect(
        tester.getRect(find.byKey(ForumSearch.panelKey)).right,
        lessThanOrEqualTo(width),
      );
      expect(tester.takeException(), isNull);
      if (Platform.environment['SEARCH_CAPTURE'] == '1') {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/private/tmp/search-$width-$dark-$scale.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

class _SearchWireApi extends GlobalSearchFixtureApi {
  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final uri = Uri.parse(path);
    if (uri.path != '/search/query.json' && uri.path != '/search.json') {
      return super.pluginGetJson(
        siteUrl: siteUrl,
        path: path,
        apiKey: apiKey,
        clientId: clientId,
      );
    }
    requests.add((siteUrl: siteUrl, uri: uri));
    final personal =
        (uri.queryParameters['term'] ?? uri.queryParameters['q'] ?? '')
            .contains('in:personal') ||
        uri.queryParameters['type_filter'] == 'private_messages';
    final inTopic = uri.queryParameters.containsKey('search_context[id]');
    return {
      'posts': [
        {
          'id': inTopic
              ? 77
              : personal
              ? 88
              : 99,
          'topic_id': personal ? 1040 : 1038,
          'post_number': inTopic ? 7 : 1,
          'username': 'sam',
          'blurb': 'Design a keyboard flow.',
        },
      ],
      'topics': [
        {
          'id': personal ? 1040 : 1038,
          'title': personal
              ? 'Design keyboard message'
              : 'Design keyboard topic',
          'slug': 'design',
          'archetype': personal ? 'private_message' : 'regular',
          'posts_count': 12,
        },
      ],
      if (!personal && !inTopic)
        'users': [
          {'id': 7, 'username': 'design_keyboard', 'name': 'Design Keyboard'},
        ],
      if (!personal && !inTopic)
        'categories': [
          {
            'id': 1,
            'name': 'Design keyboard',
            'slug': 'design',
            'color': 'A787CB',
          },
        ],
      if (!personal && !inTopic)
        'tags': [
          {'id': 3, 'name': 'design-keyboard'},
        ],
      'grouped_search_result': {'more_full_page_results': false},
    };
  }
}
