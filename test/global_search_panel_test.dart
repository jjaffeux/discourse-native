import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/shell/global_search_api.dart';
import 'package:discourse_native/src/shell/global_search_controller.dart';
import 'package:discourse_native/src/shell/global_search_models.dart';
import 'package:discourse_native/src/shell/global_search_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/media_pipeline.dart';

void main() {
  for (final query in ['fixed laughing', 'in:first']) {
    testWidgets('result emoji render with query "$query"', (tester) async {
      installTestMediaPipeline(
        client: MockClient((_) async => http.Response('', 404)),
      );
      const result = GlobalSearchResult(
        id: 'emoji',
        scope: GlobalSearchScope.forum,
        title: 'Fixed :partyparrot:',
        excerpt: 'This is fixed :laughing: :wave:t3: :unknown: at 10:30:45.',
        path: '/t/fixed/1',
      );
      final controller = await _pump(tester, results: [result], width: 300);
      controller.setQuery(query);
      await tester.pumpAndSettle();

      final row = _key('global-search-result-emoji');
      final images = tester.widgetList<SiteEmojiImage>(
        find.descendant(of: row, matching: find.byType(SiteEmojiImage)),
      );
      expect(images.map((image) => image.name), [
        'partyparrot',
        'laughing',
        'wave:t3',
      ]);
      expect(
        images.every((image) => image.siteUrl == 'https://example.com'),
        isTrue,
      );

      final description = find.descendant(
        of: row,
        matching: find.byType(DItemDescription),
      );
      RichText excerpt() => tester.widget<RichText>(
        find.descendant(of: description, matching: find.byType(RichText)).first,
      );
      expect(
        excerpt().text.toPlainText(includePlaceholders: false),
        'This is fixed   :unknown: at 10:30:45.',
      );
      if (query == 'fixed laughing') {
        final highlights = <String>[];
        excerpt().text.visitChildren((span) {
          if (span is TextSpan && span.style?.fontWeight == FontWeight.w600) {
            highlights.add(span.text!);
          }
          return true;
        });
        expect(highlights, ['fixed']);
      }
      expect(excerpt().maxLines, 2);
      expect(excerpt().overflow, TextOverflow.ellipsis);
      controller.setCompact(true);
      await tester.pumpAndSettle();
      expect(excerpt().maxLines, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('numeric conditions validate, apply and edit their operator', (
    tester,
  ) async {
    final controller = await _pump(tester);
    await _filter(tester, 'postCount');
    await tester.enterText(_key('global-search-filter-value'), '-1');
    await tester.tap(_key('global-search-filter-apply'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid whole number.'), findsOneWidget);
    expect(controller.conditions, isEmpty);

    await tester.enterText(_key('global-search-filter-value'), '12');
    await tester.tap(_key('global-search-filter-apply'));
    await tester.pumpAndSettle();
    expect(controller.scope, GlobalSearchScope.forum);
    expect(controller.conditions.single.value, ['12']);
    expect(controller.conditions.single.operator, 'gte');
    await tester.tap(_key('global-search-condition-0'));
    await tester.pumpAndSettle();
    await tester.tap(_key('global-search-filter-operator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('at most'));
    await tester.pumpAndSettle();
    await tester.tap(_key('global-search-filter-apply'));
    await tester.pumpAndSettle();
    expect(controller.conditions.single.operator, 'lte');
    expect(controller.conditions.single.value, ['12']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple category choices become one editable condition', (
    tester,
  ) async {
    final controller = await _pump(tester);
    await _filter(tester, 'category');
    await tester.tap(find.text('Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Development'));
    await tester.pumpAndSettle();
    await tester.tap(_key('global-search-filter-apply'));
    await tester.pumpAndSettle();
    expect(controller.conditions.single.value, ['1', '2']);
    expect(controller.conditions.single.operator, 'any');
    expect(find.text('Support, Development'), findsOneWidget);

    await tester.tap(_key('global-search-condition-0'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Remove Support'));
    await tester.pumpAndSettle();
    await tester.tap(_key('global-search-filter-apply'));
    await tester.pumpAndSettle();
    expect(controller.conditions.single.value, ['2']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('many conditions fit a narrow panel and remain removable', (
    tester,
  ) async {
    final controller = await _pump(tester, width: 300, height: 180);
    for (var count = 0; count < 10; count++) {
      controller.addCondition(
        GlobalSearchCondition(
          filterId: 'postCount',
          operator: 'gte',
          value: ['${count + 1}'],
        ),
      );
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_key('global-search-condition-0'), findsOneWidget);
    final clear = _key('global-search-clear-conditions');
    await tester.ensureVisible(clear);
    await tester.pumpAndSettle();
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(controller.conditions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'category search keeps selections, clears stale rows and retries',
    (tester) async {
      final api = _PanelApi();
      final controller = await _pump(tester, api: api);
      await _filter(tester, 'category');
      expect(
        tester.widget<DButton>(_key('global-search-filter-apply')).onPressed,
        isNull,
      );
      await tester.tap(find.text('Support'));
      await tester.pumpAndSettle();
      api.categoryGate = Completer<GlobalSearchCategoryPage>();
      await tester.enterText(_key('global-search-filter-value'), 'missing');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(DCheckbox), findsNothing);
      expect(find.bySemanticsLabel('Remove Support'), findsOneWidget);
      api.categoryGate!.complete(const GlobalSearchCategoryPage());
      await tester.pumpAndSettle();
      expect(find.text('No matching categories.'), findsOneWidget);
      expect(find.text('Use “missing”'), findsNothing);
      api.categoryGate = null;
      api.failCategories = true;
      await tester.tap(find.text('Show all categories'));
      await tester.pumpAndSettle();
      expect(find.text('Categories couldn’t load.'), findsOneWidget);
      api.failCategories = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byType(DCheckbox), findsNWidgets(2));
      await tester.tap(find.text('Include subcategories'));
      await tester.tap(_key('global-search-filter-apply'));
      await tester.pumpAndSettle();
      expect(controller.conditions.single.value, ['1']);
      expect(controller.conditions.single.operator, 'exactCategory');
      await tester.tap(_key('global-search-condition-0'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('global-search-category-clear'));
      await tester.pumpAndSettle();
      await tester.tap(_key('global-search-category-clear'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DButton>(_key('global-search-filter-apply')).onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.conditions.single.value, ['1']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'category pages append and an older query cannot replace new results',
    (tester) async {
      final api = _PanelApi()..moreCategories = true;
      await _pump(tester, api: api);
      await _filter(tester, 'category');
      expect(find.text('2 of 3 categories'), findsOneWidget);
      await tester.tap(find.text('Load more categories'));
      await tester.pumpAndSettle();
      expect(find.text('Beyond the preload'), findsOneWidget);
      expect(find.text('All categories · 3'), findsOneWidget);
      expect(api.categoryPages, [1, 2]);
      final stale = api.categoryGate = Completer<GlobalSearchCategoryPage>();
      await tester.enterText(_key('global-search-filter-value'), 'old');
      await tester.pump(const Duration(milliseconds: 200));
      api.categoryGate = null;
      await tester.enterText(_key('global-search-filter-value'), 'new');
      await tester.pumpAndSettle();
      stale.complete(
        const GlobalSearchCategoryPage(
          choices: [
            GlobalSearchFilterChoice(value: '99', label: 'Stale category'),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Stale category'), findsNothing);
      expect(find.text('Support'), findsOneWidget);
    },
  );

  for (final dark in [true, false]) {
    testWidgets(
      'category checklist fits narrow ${dark ? 'dark' : 'light'} with large text',
      (tester) async {
        await _pump(
          tester,
          width: 320,
          dark: dark,
          textScale: 2,
          screenSize: const Size(360, 800),
        );
        await _filter(tester, 'category');
        await tester.ensureVisible(find.text('Support'));
        await tester.tap(find.text('Support'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(_key('global-search-filter-apply'));
        await tester.pumpAndSettle();
        expect(find.text('Matches any selected category.'), findsNothing);
        expect(
          find.text('Also search within their subcategories.'),
          findsNothing,
        );
        expect(find.text('A–Z'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('category checklist supports keyboard selection', (tester) async {
    final controller = await _pump(tester);
    await _filter(tester, 'category');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(_key('global-search-filter-apply'));
    await tester.pumpAndSettle();
    expect(controller.conditions.single.value, ['1']);
  });

  testWidgets(
    'category draft resets when the same forum gets a new account session',
    (tester) async {
      final lifecycle = SiteLifecycle();
      final api = _PanelApi();
      final controller = await _pump(tester, api: api, lifecycle: lifecycle);
      await _filter(tester, 'category');
      await tester.tap(find.text('Support'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Remove Support'), findsOneWidget);
      lifecycle.invalidate('https://example.com');
      controller.configure(
        siteUrl: 'https://example.com',
        capabilities: controller.capabilities,
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Remove Support'), findsNothing);
      expect(find.text('0 selected'), findsOneWidget);
      expect(api.categoryPages, [1, 1]);
      expect(controller.conditions, isEmpty);
    },
  );

  testWidgets(
    'display changes compact rows and only exposes relevant properties',
    (tester) async {
      final controller = await _pump(tester);
      controller.setScope(GlobalSearchScope.chat);
      await tester.pumpAndSettle();
      await tester.tap(_key('global-search-display-trigger'));
      await tester.pumpAndSettle();
      expect(find.text('Excerpt'), findsOneWidget);
      expect(find.text('Likes'), findsOneWidget);
      expect(find.text('Category'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Compact results'));
      await tester.pumpAndSettle();
      expect(controller.compact, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(GlobalSearchPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _filter(WidgetTester tester, String id) async {
  await tester.tap(_key('global-search-filter-trigger'));
  await tester.pumpAndSettle();
  final row = _key('global-search-filter-$id');
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<GlobalSearchController> _pump(
  WidgetTester tester, {
  double width = 432,
  double height = 500,
  List<GlobalSearchResult> results = const [],
  _PanelApi? api,
  bool dark = true,
  double textScale = 1,
  Size screenSize = const Size(1000, 800),
  SiteLifecycle? lifecycle,
}) async {
  tester.view.physicalSize = screenSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller =
      GlobalSearchController(
        api: api ?? _PanelApi(results: results),
        credentials: FakeApiCredentialReader(),
        lifecycle: lifecycle ?? SiteLifecycle(),
        debounceDuration: Duration.zero,
      )..configure(
        siteUrl: 'https://example.com',
        capabilities: const GlobalSearchCapabilities(
          authenticated: true,
          chat: true,
        ),
      );
  addTearDown(controller.dispose);
  final shell = ShellController(
    instanceStore: FakeInstanceStore([instance('example.com')]),
    api: FakeDiscourseApi(
      emojisBySite: {
        'https://example.com': const [
          SiteEmoji(name: 'laughing', url: '/images/emoji/laughing.png'),
          SiteEmoji(name: 'partyparrot', url: '/uploads/partyparrot.png'),
          SiteEmoji(name: 'wave', url: '/images/emoji/wave.png', tonable: true),
        ],
      },
    ),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
          platform: TargetPlatform.macOS,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: height,
            child: GlobalSearchPanel(controller: controller, onOpen: (_) {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

class _PanelApi extends GlobalSearchApi {
  _PanelApi({this.results = const []}) : super(transport: FakeDiscourseApi());
  final List<GlobalSearchResult> results;
  Completer<GlobalSearchCategoryPage>? categoryGate;
  bool failCategories = false, moreCategories = false;
  final categoryPages = <int>[];

  @override
  Future<GlobalSearchCategoryPage> lookupCategoryChoices({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
    required String term,
    int page = 1,
  }) async {
    categoryPages.add(page);
    if (failCategories) throw StateError('offline');
    if (categoryGate != null) return categoryGate!.future;
    return GlobalSearchCategoryPage(
      choices: page == 1
          ? const [
              GlobalSearchFilterChoice(value: '1', label: 'Support'),
              GlobalSearchFilterChoice(value: '2', label: 'Development'),
            ]
          : const [
              GlobalSearchFilterChoice(value: '3', label: 'Beyond the preload'),
            ],
      total: moreCategories ? 3 : 2,
      hasMore: moreCategories && page == 1,
    );
  }

  @override
  Future<GlobalSearchCapabilities> capabilities({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
    required GlobalSearchCapabilities base,
  }) async => base;
  @override
  Future<GlobalSearchPage> search({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
    required GlobalSearchRequest request,
  }) async => GlobalSearchPage(
    sections: [
      GlobalSearchSection(scope: GlobalSearchScope.forum, results: results),
    ],
  );
  @override
  Future<List<GlobalSearchFilterChoice>> lookupChoices({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
    required GlobalSearchFilter filter,
    required String term,
  }) async => filter.id == 'category'
      ? const [
          GlobalSearchFilterChoice(value: '1', label: 'Support'),
          GlobalSearchFilterChoice(value: '2', label: 'Development'),
        ]
      : filter.choices;
}
