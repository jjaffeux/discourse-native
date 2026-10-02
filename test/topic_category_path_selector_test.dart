import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _categories = [
  TopicCategory(id: 1, name: 'Support', color: '0088CC'),
  TopicCategory(id: 2, name: 'Bugs', color: 'CC8800', parentCategoryId: 1),
  TopicCategory(id: 3, name: 'Mobile', color: '663399', parentCategoryId: 2),
  TopicCategory(id: 4, name: 'iOS', color: 'BB3344', parentCategoryId: 3),
  TopicCategory(id: 5, name: 'Desktop', color: '33BB44', parentCategoryId: 2),
  TopicCategory(id: 6, name: 'Community', color: '8833CC'),
  TopicCategory(id: 7, name: 'Events', color: 'CC3388', parentCategoryId: 6),
];

String _prefix(int level) => switch (level) {
  0 => 'category-path-category',
  1 => 'category-path-subcategory',
  _ => 'category-path-subcategory-$level',
};

Finder _segment(int level) => find.byKey(ValueKey('${_prefix(level)}-filter'));
Finder _option(int level, int id) =>
    find.byKey(ValueKey(('${_prefix(level)}-option', id)));

Future<void> _open(WidgetTester tester, int level) async {
  await tester.ensureVisible(_segment(level));
  await tester.tap(_segment(level));
  await tester.pumpAndSettle();
}

Future<ValueNotifier<int?>> _pump(
  WidgetTester tester, {
  int? selected,
  TargetPlatform platform = TargetPlatform.macOS,
  TextDirection direction = TextDirection.ltr,
  double width = 800,
  double textScale = 1,
  int maxCategoryNesting = 4,
  ValueNotifier<int>? nestingSetting,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final value = ValueNotifier<int?>(selected);
  addTearDown(value.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: Scaffold(
        body: Align(
          alignment: AlignmentDirectional.topStart,
          child: ListenableBuilder(
            listenable: Listenable.merge([value, ?nestingSetting]),
            builder: (context, _) => TopicCategoryPathSelector(
              siteUrl: 'https://example.invalid',
              categories: _categories,
              selectedCategoryId: value.value,
              sheetOnMobile: true,
              maxCategoryNesting: nestingSetting?.value ?? maxCategoryNesting,
              onSelected: (category) => value.value = category?.id,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return value;
}

void main() {
  testWidgets(
    'a nesting setting refresh retires open menus and updates levels',
    (tester) async {
      final nesting = ValueNotifier(2);
      addTearDown(nesting.dispose);
      final selected = await _pump(
        tester,
        selected: 2,
        nestingSetting: nesting,
      );
      expect(_segment(2), findsNothing);
      await _open(tester, 1);
      nesting.value = 3;
      await tester.pumpAndSettle();
      expect(find.byType(DComboboxContent), findsNothing);
      expect(_segment(2), findsOneWidget);
      await _open(tester, 2);
      expect(_option(2, 3), findsOneWidget);
      nesting.value = 2;
      await tester.pumpAndSettle();
      expect(find.byType(DComboboxContent), findsNothing);
      expect(_segment(2), findsNothing);
      expect(selected.value, 2);
      expect(tester.takeException(), isNull);
    },
  );

  for (final limit in [2, 3]) {
    testWidgets(
      'site nesting limit $limit controls prompts and child indicators',
      (tester) async {
        final selected = await _pump(
          tester,
          selected: 2,
          maxCategoryNesting: limit,
        );
        expect(find.byType(TopicCategorySelector), findsNWidgets(limit));
        expect(
          find.text('Subcategory'),
          limit == 3 ? findsOneWidget : findsNothing,
        );
        await _open(tester, 1);
        expect(
          find.descendant(
            of: _option(1, 2),
            matching: find.byType(DBreadcrumbSeparator),
          ),
          limit == 3 ? findsOneWidget : findsNothing,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        if (limit == 3) {
          await _open(tester, 2);
          // Mobile has a child in the fixture, but the site allows only 3 levels.
          expect(
            find.descendant(
              of: _option(2, 3),
              matching: find.byType(DBreadcrumbSeparator),
            ),
            findsNothing,
          );
          await tester.tap(_option(2, 3));
          await tester.pumpAndSettle();
          expect(selected.value, 3);
          expect(find.byType(TopicCategorySelector), findsNWidgets(3));
          expect(find.text('Subcategory'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets(
      'selects four levels then replaces and clears ancestors on $platform',
      (tester) async {
        final selected = await _pump(tester, platform: platform);
        for (var level = 0; level < 4; level++) {
          await _open(tester, level);
          expect(_option(level, level + 1), findsOneWidget);
          if (level < 3) {
            expect(
              find.descendant(
                of: _option(level, level + 1),
                matching: find.byType(DBreadcrumbSeparator),
              ),
              findsOneWidget,
            );
          }
          // A level exposes only siblings, never unrelated branches.
          expect(_option(level, level == 0 ? 7 : 6), findsNothing);
          await tester.tap(_option(level, level + 1));
          await tester.pumpAndSettle();
          expect(selected.value, level + 1);
          expect(find.byType(DComboboxContent), findsNothing);
        }
        expect(find.byType(TopicCategorySelector), findsNWidgets(4));
        expect(find.text('Subcategory'), findsNothing);
        for (final name in ['Support', 'Bugs', 'Mobile', 'iOS']) {
          expect(find.text(name), findsOneWidget);
        }

        await _open(tester, 2);
        expect(find.text('All of Bugs'), findsOneWidget);
        await tester.tap(_option(2, 5));
        await tester.pumpAndSettle();
        expect(selected.value, 5);
        expect(find.text('Mobile'), findsNothing);
        expect(find.text('iOS'), findsNothing);
        expect(find.text('Desktop'), findsOneWidget);

        await _open(tester, 2);
        await tester.tap(_option(2, 0));
        await tester.pumpAndSettle();
        expect(selected.value, 2);
        expect(find.text('Subcategory'), findsOneWidget);

        await _open(tester, 0);
        await tester.tap(_option(0, 6));
        await tester.pumpAndSettle();
        expect(selected.value, 6);
        expect(find.text('Support'), findsNothing);
        expect(find.text('Bugs'), findsNothing);
        await _open(tester, 1);
        expect(_option(1, 7), findsOneWidget);
        expect(_option(1, 2), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        await _open(tester, 0);
        await tester.tap(_option(0, 0));
        await tester.pumpAndSettle();
        expect(selected.value, isNull);
        expect(find.text('Categories'), findsOneWidget);
        expect(find.byType(TopicCategorySelector), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('search and keyboard selection operate within a level', (
    tester,
  ) async {
    final selected = await _pump(tester, selected: 3);
    await _open(tester, 2);
    await tester.enterText(find.byKey(ValueKey('${_prefix(2)}-query')), 'desk');
    await tester.pumpAndSettle();
    expect(find.text('All of Bugs'), findsOneWidget);
    expect(_option(2, 3), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected.value, 5);
    expect(
      tester
          .widget<DButton>(
            find.descendant(of: _segment(2), matching: find.byType(DButton)),
          )
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await _open(tester, 2);
    expect(_option(2, 3), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(selected.value, 5);
  });

  testWidgets('an external ancestor change retires the open descendant menu', (
    tester,
  ) async {
    final selected = await _pump(tester, selected: 3);
    await _open(tester, 2);
    selected.value = 6;
    await tester.pumpAndSettle();
    expect(find.byType(DComboboxContent), findsNothing);
    await _open(tester, 1);
    expect(_option(1, 7), findsOneWidget);
    expect(_option(1, 3), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches directly between segment menus with one click', (
    tester,
  ) async {
    await _pump(tester, selected: 3);
    await _open(tester, 0);
    await _open(tester, 2);
    expect(find.byType(DComboboxContent), findsOneWidget);
    expect(find.byKey(ValueKey('${_prefix(0)}-query')), findsNothing);
    expect(find.byKey(ValueKey('${_prefix(2)}-query')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'deep paths remain reachable at 320px with large text on $platform $direction',
        (tester) async {
          await _pump(
            tester,
            selected: 4,
            platform: platform,
            direction: direction,
            width: 320,
            textScale: 2,
          );
          for (var level = 0; level < 4; level++) {
            await _open(tester, level);
            final popup = tester.getRect(find.byType(DComboboxContent));
            expect(popup.left, greaterThanOrEqualTo(0));
            expect(popup.right, lessThanOrEqualTo(320));
            expect(tester.takeException(), isNull);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
          }
        },
      );
    }
  }
}
