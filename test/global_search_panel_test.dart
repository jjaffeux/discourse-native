import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/global_search_api.dart';
import 'package:discourse_native/src/shell/global_search_controller.dart';
import 'package:discourse_native/src/shell/global_search_models.dart';
import 'package:discourse_native/src/shell/global_search_panel.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
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
}) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller =
      GlobalSearchController(
        api: _PanelApi(),
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
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
      home: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          height: height,
          child: GlobalSearchPanel(controller: controller, onOpen: (_) {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

class _PanelApi extends GlobalSearchApi {
  _PanelApi() : super(transport: FakeDiscourseApi());
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
  }) async => const GlobalSearchPage();
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
