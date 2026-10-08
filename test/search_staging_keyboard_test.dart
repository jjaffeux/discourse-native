import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/global_search_panel.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/global_search_fixtures.dart';

void main() {
  testWidgets(
    'ordering is staged in the same sheet, applies remotely, and clears words independently',
    (tester) async {
      final shell = createGlobalSearchFixtureController();
      addTearDown(shell.dispose);
      await shell.load();
      shell.pushContent(ContentRoute.topicList(TopicListMode.latest));
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
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ForumSearch.inputKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ForumSearch.inputKey),
        'keyboard order:latest',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(shell.globalSearch.stagedFilter?.id, 'order');
      expect(find.byType(GlobalSearchPanel), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(shell.globalSearch.order, 'latest');
      expect(shell.globalSearch.wordsQuery.trim(), 'keyboard');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(shell.currentContent!.isSearchList, isTrue);
      expect(
        Uri.parse(shell.currentContent!.feedPath!).queryParameters['q'],
        'keyboard order:latest',
      );
      shell.clearSearchWords();
      await tester.pumpAndSettle();
      expect(
        Uri.parse(shell.currentContent!.feedPath!).queryParameters['q'],
        'order:latest',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nested categories use keyboard browsing and stable IDs without losing words',
    (tester) async {
      final shell = createGlobalSearchFixtureController(api: _TreeApi());
      addTearDown(shell.dispose);
      await shell.load();
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
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ForumSearch.inputKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(ForumSearch.inputKey), 'keyboard cat');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(shell.globalSearch.query, 'keyboard category:');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('global-search-staged-2')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(shell.globalSearch.conditions.single.filterId, 'category');
      expect(shell.globalSearch.conditions.single.value, ['2']);
      expect(shell.globalSearch.wordsQuery.trim(), 'keyboard');
      expect(tester.takeException(), isNull);
    },
  );
}

class _TreeApi extends GlobalSearchFixtureApi {
  @override
  Future<Map<String, dynamic>> pluginQueryJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) => path == '/categories/search.json'
      ? Future.value(tree)
      : super.pluginQueryJson(
          siteUrl: siteUrl,
          path: path,
          apiKey: apiKey,
          body: body,
          clientId: clientId,
        );
  Map<String, dynamic> get tree => {
    'categories': [
      {
        'id': 1,
        'name': 'Root',
        'slug': 'root',
        'color': 'ABCDEF',
        'topic_count': 12,
      },
      {
        'id': 2,
        'name': 'Child',
        'slug': 'child',
        'color': 'ABCDEF',
        'parent_category_id': 1,
        'topic_count': 3,
      },
    ],
    'categories_count': 2,
  };

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) => Uri.parse(path).path == '/categories/search.json'
      ? Future.value(tree)
      : super.pluginGetJson(
          siteUrl: siteUrl,
          path: path,
          apiKey: apiKey,
          clientId: clientId,
        );
}
