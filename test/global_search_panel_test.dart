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
    'tags show suggestions first and preserve selections while searching',
    (tester) async {
      final api = _PanelApi();
      final controller = await _pump(tester, api: api);
      await _filter(tester, 'tags');
      expect(api.tagTerms, ['']);
      expect(find.text('Available tags · 3'), findsOneWidget);
      expect(find.text('1,248'), findsOneWidget);
      expect(
        find.text('Match any tag, every tag, or exclude selected tags.'),
        findsNothing,
      );
      expect(find.text('Choose at least one tag'), findsNothing);
      expect(
        tester.widget<DButton>(_key('global-search-filter-apply')).onPressed,
        isNull,
      );
      expect(
        tester.getTopLeft(_key('global-search-filter-value')).dy,
        lessThan(tester.getTopLeft(_key('global-search-filter-operator')).dy),
      );

      await tester.enterText(_key('global-search-filter-value'), 'a');
      await tester.pumpAndSettle();
      expect(find.text('Matching tags · 2'), findsOneWidget);
      expect(find.text('Use “a”'), findsNothing);
      await tester.tap(find.text('api', findRichText: true));
      await tester.pumpAndSettle();
      await tester.enterText(_key('global-search-filter-value'), 'bug');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Remove api'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Selected · 2'), findsOneWidget);
      await tester.tap(_key('global-search-filter-apply'));
      await tester.pumpAndSettle();
      expect(controller.conditions.single.value, ['api', 'bug']);

      await tester.tap(_key('global-search-condition-0'));
      await tester.pumpAndSettle();
      expect(find.text('Apply changes'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Remove api'));
      await tester.pumpAndSettle();
      for (final label in [
        'Include every selected tag',
        'Exclude any selected tag',
        'Exclude this combination',
      ]) {
        await tester.tap(_key('global-search-filter-operator'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }
      await tester.tap(_key('global-search-filter-apply'));
      await tester.pumpAndSettle();
      expect(controller.conditions.single.operator, 'notAll');
      expect(controller.conditions.single.value, ['bug']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tag lookups show loading and ignore results for retired queries',
    (tester) async {
      final api = _PanelApi();
      await _pump(tester, api: api);
      await _filter(tester, 'tags');
      final first = Completer<List<GlobalSearchFilterChoice>>();
      final second = Completer<List<GlobalSearchFilterChoice>>();
      api.tagLookup = (term) => term == 'a' ? first.future : second.future;
      await tester.enterText(_key('global-search-filter-value'), 'a');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('Finding tags…'), findsOneWidget);
      expect(find.text('bug'), findsNothing);
      expect(find.text('Use “a”'), findsNothing);
      await tester.enterText(_key('global-search-filter-value'), 'ap');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      second.complete(const [
        GlobalSearchFilterChoice(value: 'api', label: 'api'),
      ]);
      await tester.pumpAndSettle();
      first.complete(const [
        GlobalSearchFilterChoice(
          value: 'announcements',
          label: 'announcements',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('api', findRichText: true), findsOneWidget);
      expect(find.text('announcements', findRichText: true), findsNothing);
      expect(find.text('Finding tags…'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed tag refresh filters saved tags and keeps selections removable',
    (tester) async {
      final api = _PanelApi();
      await _pump(tester, api: api);
      await _filter(tester, 'tags');
      await tester.tap(find.text('api'));
      await tester.pumpAndSettle();
      api.tagLookup = (_) async => throw StateError('Offline');
      await tester.enterText(_key('global-search-filter-value'), 'a');
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t refresh tags'), findsOneWidget);
      expect(find.text('Saved tags · 2'), findsOneWidget);
      expect(find.text('bug'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Remove api'));
      await tester.pumpAndSettle();
      expect(find.text('Selected · 1'), findsNothing);
      await tester.enterText(_key('global-search-filter-value'), 'unknown-tag');
      await tester.pumpAndSettle();
      expect(find.text('No saved tags match “unknown-tag”'), findsOneWidget);
      expect(find.text('Use “unknown-tag”'), findsNothing);
      api.tagLookup = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No tags match “unknown-tag”'), findsOneWidget);
      await tester.tap(find.text('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Available tags · 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'initial tag lookup failure can retry without accepting arbitrary text',
    (tester) async {
      final api = _PanelApi()
        ..tagLookup = (_) async => throw StateError('Offline');
      await _pump(tester, api: api);
      await _filter(tester, 'tags');
      expect(find.text('Couldn’t load tags'), findsOneWidget);
      await tester.enterText(_key('global-search-filter-value'), 'a');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Use “a”'), findsNothing);
      expect(
        tester.widget<DButton>(_key('global-search-filter-apply')).onPressed,
        isNull,
      );
      api.tagLookup = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Matching tags · 2'), findsOneWidget);
      expect(find.text('Couldn’t load tags'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'tag picker fits a narrow ${dark ? 'dark' : 'light'} viewport at 200% text',
      (tester) async {
        await _pump(
          tester,
          width: 320,
          viewport: const Size(360, 1000),
          textScale: 2,
          dark: dark,
        );
        await _filter(tester, 'tags');
        await tester.tap(find.text('api'));
        await tester.pumpAndSettle();
        expect(find.text('Selected · 1'), findsOneWidget);
        await tester.tap(find.text('Clear selection'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<DButton>(_key('global-search-filter-apply')).onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      'display properties fit narrow ${dark ? 'dark' : 'light'} layouts at 200% text',
      (tester) async {
        await _pump(
          tester,
          width: 320,
          viewport: const Size(360, 1000),
          textScale: 2,
          dark: dark,
        );
        await tester.tap(_key('global-search-display-trigger'));
        await tester.pumpAndSettle();
        expect(find.byType(DCheckbox), findsNWidgets(6));
        await tester.tap(find.text('Replies'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DCheckbox>(_key('global-search-property-replies'))
              .value,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('display uses checkboxes and only exposes relevant properties', (
    tester,
  ) async {
    final controller = await _pump(tester);
    controller.setScope(GlobalSearchScope.chat);
    controller.setDisplayProperty(GlobalSearchDisplayProperty.likes, false);
    await tester.pumpAndSettle();
    await tester.tap(_key('global-search-display-trigger'));
    await tester.pumpAndSettle();
    expect(find.text('Excerpt'), findsOneWidget);
    expect(find.text('Likes'), findsOneWidget);
    expect(find.text('Category'), findsNothing);
    expect(find.text('Compact rows'), findsNothing);
    expect(find.bySemanticsLabel('Compact results'), findsNothing);
    final excerpt = _key('global-search-property-excerpt');
    final likes = _key('global-search-property-likes');
    expect(tester.widget<DCheckbox>(excerpt).value, isTrue);
    expect(tester.widget<DCheckbox>(likes).value, isFalse);
    await tester.tap(find.text('Excerpt'));
    await tester.pumpAndSettle();
    expect(tester.widget<DCheckbox>(excerpt).value, isFalse);
    expect(
      controller.properties,
      isNot(contains(GlobalSearchDisplayProperty.excerpt)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(tester.widget<DCheckbox>(excerpt).value, isTrue);
    expect(
      controller.properties,
      contains(GlobalSearchDisplayProperty.excerpt),
    );
    await tester.tap(find.text('Likes'));
    await tester.pumpAndSettle();
    expect(tester.widget<DCheckbox>(likes).value, isTrue);
    expect(controller.properties, contains(GlobalSearchDisplayProperty.likes));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(GlobalSearchPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
  Size viewport = const Size(1000, 800),
  double textScale = 1,
  bool dark = true,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller =
      GlobalSearchController(
        api: api ?? _PanelApi(results: results),
        credentials: FakeApiCredentialReader(),
        lifecycle: SiteLifecycle(),
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
  final tagTerms = <String>[];
  Future<List<GlobalSearchFilterChoice>> Function(String)? tagLookup;
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
  }) async {
    if (filter.id == 'tags') {
      tagTerms.add(term);
      if (tagLookup case final lookup?) return lookup(term);
      return const [
        GlobalSearchFilterChoice(value: 'api', label: 'api', topicCount: 1248),
        GlobalSearchFilterChoice(
          value: 'announcements',
          label: 'announcements',
          topicCount: 86,
        ),
        GlobalSearchFilterChoice(value: 'bug', label: 'bug', topicCount: 2834),
      ].where((choice) => choice.value.contains(term.toLowerCase())).toList();
    }
    return filter.id == 'category'
        ? const [
            GlobalSearchFilterChoice(value: '1', label: 'Support'),
            GlobalSearchFilterChoice(value: '2', label: 'Development'),
          ]
        : filter.choices;
  }
}
