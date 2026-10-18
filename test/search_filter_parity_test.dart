import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/global_search_filters.dart';
import 'package:discourse_native/src/shell/global_search_models.dart';
import 'package:discourse_native/src/shell/global_search_panel.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sidebar_filter_parity_test.dart' as list_fixture;
import 'support/global_search_fixtures.dart';

const caps = GlobalSearchCapabilities(authenticated: true, username: 'joffrey');

void main() {
  setUpAll(() async {
    if (Platform.environment['SEARCH_FILTER_CAPTURE'] == '1') {
      await (FontLoader('Lato')
            ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
          .load();
    }
  });

  test(
    'message, directory and video syntax retain supported server tokens',
    () {
      final message = parseGlobalSearchExpression(
        '@sam group_messages:team after:2026-10-01 in:personal-direct',
        GlobalSearchScope.messages,
        caps,
      );
      expect(message.query, isEmpty);
      expect(message.conditions.map((c) => c.filterId), [
        'messageAuthor',
        'messageGroupInbox',
        'messagePostDate',
        'messageKind',
      ]);
      final users = parseGlobalSearchExpression(
        'group=team username=sam',
        GlobalSearchScope.users,
        caps,
      );
      expect(users.conditions.map((c) => c.filterId), [
        'userGroup',
        'userName',
      ]);
      final video = globalSearchFilter(
        'content',
      )!.choices.singleWhere((choice) => choice.value == 'video');
      expect(video.token, startsWith('filetypes:'));
      expect(
        parseGlobalSearchExpression(
          video.token!,
          GlobalSearchScope.forum,
          caps,
        ).conditions.single.value,
        ['video'],
      );
      expect(
        globalSearchFilterAvailable(
          globalSearchFilter('messageAuthor')!,
          const GlobalSearchCapabilities(),
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'completed syntax becomes chips while the next token stays editable',
    (tester) async {
      final shell = createGlobalSearchFixtureController();
      addTearDown(shell.dispose);
      await shell.load();
      final search = shell.globalSearch
        ..configure(siteUrl: globalSearchFixtureSite, capabilities: caps);
      search.setQuery('@sam tags:design+keyboard after:2026-10-01 next');
      expect(search.query, 'next');
      expect(search.conditions.map((c) => c.filterId), [
        'author',
        'tags',
        'postDate',
      ]);
      expect(search.conditions[1].operator, 'all');
      search.setQuery('status:invalid @john_doe words');
      expect(search.query, 'status:invalid words');
      expect(search.conditions.first.text, 'john_doe');
      search.setScope(GlobalSearchScope.messages);
      search.setQuery('@sam in:personal-direct ');
      expect(search.scope, GlobalSearchScope.messages);
      expect(search.conditions.map((c) => c.filterId), [
        'messageAuthor',
        'messageKind',
      ]);
      expect(search.conditionsFor(GlobalSearchScope.forum).length, 3);
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'message filters reach the private endpoint and person search asks for posts',
    (tester) async {
      final api = GlobalSearchFixtureApi();
      final shell = createGlobalSearchFixtureController(api: api);
      addTearDown(shell.dispose);
      await shell.load();
      final search = shell.globalSearch
        ..configure(siteUrl: globalSearchFixtureSite, capabilities: caps);
      search.setScope(GlobalSearchScope.messages);
      search.setQuery('@sam in:personal-direct ');
      await tester.pump(const Duration(seconds: 1));
      expect(
        api.requests.last.uri.queryParameters['q'],
        contains('@sam in:personal-direct in:personal'),
      );
      search.setScope(GlobalSearchScope.forum);
      search.setQuery('@sam ');
      await tester.pump(const Duration(seconds: 1));
      expect(api.requests.last.uri.queryParameters['q'], '@sam in:all-posts');
    },
  );

  for (final (width, scale, dark) in [
    (900.0, 1.0, false),
    (390.0, 2.0, true),
  ]) {
    testWidgets('search filter sheet renders and keyboard tags apply $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final shell = createGlobalSearchFixtureController();
      addTearDown(shell.dispose);
      await shell.load();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.forBrightness(
              dark ? Brightness.dark : Brightness.light,
              fontFamily: 'Lato',
            ).copyWith(platform: TargetPlatform.macOS),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 950),
                textScaler: TextScaler.linear(scale),
              ),
              child: RepaintBoundary(
                key: boundary,
                child: const Scaffold(
                  body: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: 600,
                      child: ForumSearch(showNavigationControls: false),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(ForumSearch.inputKey));
      await tester.pumpAndSettle();
      await _capture(tester, boundary, 'grouped-$width');
      await tester.enterText(find.byKey(ForumSearch.inputKey), 'tags:');
      await tester.pumpAndSettle();
      final rowTop = tester.getTopLeft(
        find.text('design', findRichText: true).last,
      );
      await tester.tap(find.text('design', findRichText: true).last);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('design', findRichText: true).last),
        rowTop,
      );
      await _capture(tester, boundary, 'tags-$width');
      await tester.ensureVisible(
        find.byKey(const ValueKey('global-search-filter-apply')),
      );
      await tester.tap(
        find.byKey(const ValueKey('global-search-filter-apply')),
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(shell.globalSearch.conditions.single.value, ['design']);
      expect(find.byType(SearchFilterChip), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'list pills share the filter sheet and category Backspace goes up a level',
    (tester) async {
      final fixture = await list_fixture.fixture(tester);
      fixture.shell.selectTopicListCategory(list_fixture.child);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topic-list-subcategory-filter')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('topic-list-category-filter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(list_fixture.field);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(
        find.text('Category: Product', findRichText: true),
        findsOneWidget,
      );
      expect(
        fixture.shell.topicListContent?.categoryId,
        list_fixture.parent.id,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-list-tag-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-filter-done-tags')));
      await tester.pumpAndSettle();
      expect(fixture.shell.topicListContent?.tagName, 'Alpha');
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['SEARCH_FILTER_CAPTURE'] != '1') return;
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final builder = ui.SceneBuilder();
    view.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(
      view.size.width.round(),
      view.size.height.round(),
    );
    scene.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/private/tmp/search-filter-$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
