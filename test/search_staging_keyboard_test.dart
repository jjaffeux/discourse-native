import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/plugin_api/global_search_models.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/global_search_panel.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/global_search_fixtures.dart';

void main() {
  for (final action in [
    'remember',
    'result',
    'apply',
    'section',
    'stale section',
  ]) {
    testWidgets(
      'history account replacement preserves successor search during $action',
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
        await tester.enterText(find.byKey(ForumSearch.inputKey), 'keyboard');
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        final panel = tester.widget<GlobalSearchPanel>(
          find.byType(GlobalSearchPanel),
        );
        final result = shell.globalSearch.results.first;
        final openSection = tester
            .widget<DItem>(find.byKey(const ValueKey('section:users:')))
            .onPressed!;
        var changed = false;
        shell.globalSearch.history.addListener(() {
          if (changed) return;
          changed = true;
          shell.selectInstance(1);
          shell.search.requestFocus();
          shell.globalSearch.setQuery('design');
        });
        switch (action) {
          case 'remember':
            shell.globalSearch.rememberSearch();
          case 'result':
            panel.onOpen(result);
          case 'apply':
            panel.onApply!();
          case 'section':
            openSection();
          case 'stale section':
            shell.globalSearch.rememberSearch();
            openSection();
        }
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        expect(changed, isTrue);
        expect(shell.currentInstance!.url, globalSearchFixtureOtherSite);
        expect(shell.currentContent?.isTopicList, isTrue);
        expect(shell.globalSearch.query, 'design');
        expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('directory loading publication preserves successor search', (
    tester,
  ) async {
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
    await tester.enterText(find.byKey(ForumSearch.inputKey), 'keyboard');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    final openSection = tester
        .widget<DItem>(find.byKey(const ValueKey('section:users:')))
        .onPressed!;
    var changed = false;
    shell.userDirectory.addListener(() {
      if (!shell.userDirectory
          .stateFor(globalSearchFixtureSite, shell.focusedTabContext.usersQuery)
          .loading) {
        return;
      }
      if (changed) return;
      changed = true;
      shell.selectInstance(1);
      shell.search.requestFocus();
      shell.globalSearch.setQuery('design');
    });
    openSection();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(changed, isTrue);
    expect(shell.currentInstance!.url, globalSearchFixtureOtherSite);
    expect(shell.currentContent?.isTopicList, isTrue);
    expect(shell.globalSearch.query, 'design');
    expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final action in ['result', 'apply', 'section']) {
    testWidgets('same-account history query change retains admitted $action', (
      tester,
    ) async {
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
      await tester.enterText(find.byKey(ForumSearch.inputKey), 'keyboard');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      final panel = tester.widget<GlobalSearchPanel>(
        find.byType(GlobalSearchPanel),
      );
      final result = shell.globalSearch.results.first;
      final openSection = tester
          .widget<DItem>(find.byKey(const ValueKey('section:users:')))
          .onPressed!;
      var changed = false;
      shell.globalSearch.history.addListener(() {
        if (changed) return;
        changed = true;
        shell.globalSearch.setQuery('design');
      });
      switch (action) {
        case 'result':
          panel.onOpen(result);
        case 'apply':
          panel.onApply!();
        case 'section':
          openSection();
      }
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(changed, isTrue);
      expect(shell.currentInstance!.url, globalSearchFixtureSite);
      switch (action) {
        case 'result':
          expect(shell.currentContent!.isTopic, isTrue);
          expect(shell.currentContent!.topicId, 1038);
          expect(
            shell.search.wordsFor(
              globalSearchFixtureSite,
              shell.activeTabId,
              shell.currentContent!.id,
            ),
            'keyboard',
          );
          await tester.pump(shell.topicLoadTimeout);
          await tester.pumpAndSettle();
        case 'apply':
          expect(shell.currentContent!.topicListSearch, 'design');
        case 'section':
          expect(shell.currentContent!.isUsers, isTrue);
          expect(
            shell.search.wordsFor(
              globalSearchFixtureSite,
              shell.activeTabId,
              shell.currentContent!.id,
            ),
            'keyboard',
          );
      }
      expect(find.byKey(ForumSearch.panelKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final action in ['apply', 'section']) {
    testWidgets('$action search from secondary hands off to primary pane', (
      tester,
    ) async {
      final shell = createGlobalSearchFixtureController(forumTabsEnabled: true);
      addTearDown(shell.dispose);
      await shell.load();
      shell.desktopTopicTabs = true;
      shell.pushContent(ContentRoute.topicList(TopicListMode.latest));
      final primary = shell.activeTabId;
      shell.openContentInPanel(
        ContentRoute.topic(topicId: 1038, slug: 'keyboard', title: 'Keyboard'),
        panel: ForumPanel.secondary,
      );
      expect(shell.activeTabId, isNot(primary));
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
      await tester.enterText(find.byKey(ForumSearch.inputKey), 'keyboard');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      if (action == 'apply') {
        tester
            .widget<GlobalSearchPanel>(find.byType(GlobalSearchPanel))
            .onApply!();
      } else {
        tester
            .widget<DItem>(find.byKey(const ValueKey('section:groups:')))
            .onPressed!();
      }
      await tester.pumpAndSettle();
      expect(shell.activeTabId, primary);
      expect(shell.currentContent!.isGroups, action == 'section');
      expect(
        shell.search.wordsFor(
          globalSearchFixtureSite,
          shell.activeTabId,
          shell.currentContent!.id,
        ),
        'keyboard',
      );
      expect(find.byKey(ForumSearch.panelKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('mobile keyboard Done keeps search results open on $platform', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final shell = createGlobalSearchFixtureController();
      addTearDown(shell.dispose);
      await shell.load();
      shell.pushContent(ContentRoute.topicList(TopicListMode.latest));
      final source = shell.currentContent;
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            home: const Scaffold(body: ForumSearch(fullScreen: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(ForumSearch.inputKey), 'keyboard');
      // Done can arrive before the live-search debounce has fired.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      expect(shell.currentContent, same(source));
      expect(shell.globalSearch.wordsQuery, 'keyboard');
      expect(shell.globalSearch.results, isNotEmpty);
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      expect(editor.textInputAction, TextInputAction.done);
      expect(editor.focusNode.hasFocus, isFalse);

      await tester.tap(find.byKey(ForumSearch.inputKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(ForumSearch.inputKey), 'design');
      // Also accept a Search action from a keyboard retaining its old layout.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      expect(shell.globalSearch.wordsQuery, 'design');
      expect(shell.currentContent, same(source));
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final scope in [
    GlobalSearchScope.users,
    GlobalSearchScope.groups,
    GlobalSearchScope.places,
  ]) {
    for (final term in ['l', 'l r f t club']) {
      testWidgets(
        '${scope.name} applies literal "$term" with unselected Enter',
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
          shell.globalSearch.setScope(scope);
          await tester.enterText(find.byKey(ForumSearch.inputKey), term);
          await tester.pump(const Duration(milliseconds: 450));
          await tester.pumpAndSettle();
          expect(shell.globalSearch.wordsQuery, term);
          expect(shell.globalSearch.error, isNull);
          expect(find.byType(GlobalSearchPanel), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(shell.globalSearch.error, isNull);
          expect(
            shell.search.wordsFor(
              globalSearchFixtureSite,
              shell.activeTabId,
              shell.currentContent!.id,
            ),
            term,
          );
          expect(find.byType(GlobalSearchPanel), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

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

  testWidgets('arrow keys select a result before Enter opens its topic', (
    tester,
  ) async {
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
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    final result = shell.globalSearch.results.first;
    final row = find.byKey(ValueKey('global-search-result-${result.id}'));
    expect(tester.widget<DItem>(row).selected, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(tester.widget<DItem>(row).selected, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(shell.currentContent!.isTopic, isTrue);
    expect(shell.currentContent!.topicId, 1038);
    expect(
      shell.search
          .wordsFor(
            globalSearchFixtureSite,
            shell.activeTabId,
            shell.currentContent!.id,
          )
          .trim(),
      'keyboard',
    );
    // This fixture has no topic reader to consume the pending post highlight.
    await tester.pump(shell.topicLoadTimeout);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

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
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('global-search-staged-2')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('global-search-staged-2')),
        findsNothing,
      );
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
