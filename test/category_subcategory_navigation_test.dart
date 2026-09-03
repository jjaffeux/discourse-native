import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/category_subcategory_navigation.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parent = TopicCategory(
    id: 1,
    name: 'Discourse Native App',
    color: '563A93',
    slug: 'discourse-native-app',
  );
  const subcategories = [
    TopicCategory(
      id: 2,
      name: 'Bugs',
      color: 'C54F16',
      slug: 'bugs',
      parentCategoryId: 1,
      position: 1,
    ),
    TopicCategory(
      id: 3,
      name: 'Features',
      color: '3BBF7B',
      slug: 'features',
      parentCategoryId: 1,
      position: 2,
    ),
    TopicCategory(
      id: 4,
      name: 'UX',
      color: '3188CC',
      slug: 'ux',
      parentCategoryId: 1,
      position: 3,
    ),
    TopicCategory(
      id: 5,
      name: 'Android',
      color: '888888',
      slug: 'android',
      parentCategoryId: 1,
      position: 4,
    ),
    TopicCategory(
      id: 6,
      name: 'Accessibility',
      color: '777777',
      slug: 'accessibility',
      parentCategoryId: 1,
      position: 5,
    ),
  ];
  const categories = [parent, ...subcategories];

  Future<void> pumpNavigation(
    WidgetTester tester, {
    required int selectedCategoryId,
    required ValueChanged<TopicCategory> onSelected,
    Size size = const Size(390, 844),
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: platform),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: CategorySubcategoryNavigation(
              categories: categories,
              selectedCategoryId: selectedCategoryId,
              onSelected: onSelected,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('keeps the selected category visible and overflows the rest', (
    tester,
  ) async {
    final selections = <TopicCategory>[];
    await pumpNavigation(
      tester,
      selectedCategoryId: 6,
      onSelected: selections.add,
    );

    expect(
      find.byKey(const ValueKey('category-subcategory-navigation')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Subcategories of Discourse Native App'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey(('subcategory-navigation', 1))),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey(('subcategory-navigation', 2))),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey(('subcategory-navigation', 6))),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey(('subcategory-navigation', 3))),
      findsNothing,
    );
    expect(find.bySemanticsLabel('Accessibility, selected'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('subcategory-navigation-more')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey(('subcategory-navigation', 2))));
    await tester.pump();
    expect(selections.single.id, 2);
  });

  testWidgets('opens every subcategory from a touch overflow sheet', (
    tester,
  ) async {
    final selections = <TopicCategory>[];
    await pumpNavigation(
      tester,
      selectedCategoryId: 1,
      onSelected: selections.add,
    );

    await tester.tap(find.byKey(const ValueKey('subcategory-navigation-more')));
    await tester.pumpAndSettle();

    expect(find.text('Subcategories of Discourse Native App'), findsOneWidget);
    expect(find.text('Show every topic in Discourse Native App'), findsNothing);
    expect(find.text('Show topics in Bugs'), findsNothing);
    expect(
      find.byKey(const ValueKey(('choice-menu-option', 6))),
      findsOneWidget,
    );

    final accessibility = find.byKey(const ValueKey(('choice-menu-option', 6)));
    await tester.ensureVisible(accessibility);
    await tester.pumpAndSettle();
    await tester.tap(accessibility);
    await tester.pumpAndSettle();

    expect(selections.single.id, 6);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('filters subcategories in the touch overflow sheet', (
    tester,
  ) async {
    await pumpNavigation(
      tester,
      selectedCategoryId: 1,
      onSelected: _ignoreSelection,
    );

    await tester.tap(find.byKey(const ValueKey('subcategory-navigation-more')));
    await tester.pumpAndSettle();

    final filter = find.byKey(const ValueKey('choice-menu-filter'));
    expect(filter, findsOneWidget);
    final filterField = tester.widget<TextField>(filter);
    expect(filterField.autofocus, isTrue);
    expect(filterField.decoration?.border, isA<OutlineInputBorder>());
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: filter, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );

    await tester.enterText(filter, 'feat');
    await tester.pump();

    expect(
      find.byKey(const ValueKey(('choice-menu-option', 1))),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey(('choice-menu-option', 3))),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey(('choice-menu-option', 2))), findsNothing);

    await tester.enterText(filter, 'missing');
    await tester.pump();

    expect(find.text('No matching subcategories.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey(('choice-menu-option', 1))),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('choice-menu-filter-clear')));
    await tester.pump();

    expect(find.text('No matching subcategories.'), findsNothing);
    expect(
      find.byKey(const ValueKey(('choice-menu-option', 2))),
      findsOneWidget,
    );
  });

  testWidgets('opens overflow as a popover with desktop input', (tester) async {
    final selections = <TopicCategory>[];
    await pumpNavigation(
      tester,
      selectedCategoryId: 1,
      onSelected: selections.add,
      size: const Size(700, 800),
      platform: TargetPlatform.macOS,
    );

    await tester.tap(find.byKey(const ValueKey('subcategory-navigation-more')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('choice-menu-surface')), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    final filter = find.byKey(const ValueKey('choice-menu-filter'));
    expect(filter, findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: filter, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.enterText(filter, 'access');
    await tester.pump();

    expect(find.byKey(const ValueKey(('choice-menu-option', 2))), findsNothing);

    final accessibility = find.byKey(const ValueKey(('choice-menu-option', 6)));
    await tester.ensureVisible(accessibility);
    await tester.pumpAndSettle();
    await tester.tap(accessibility);
    await tester.pumpAndSettle();

    expect(selections.single.id, 6);
  });

  testWidgets('stays hidden for categories without children', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: CategorySubcategoryNavigation(
            categories: [parent],
            selectedCategoryId: 1,
            onSelected: _ignoreSelection,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('category-subcategory-navigation')),
      findsNothing,
    );
  });
}

void _ignoreSelection(TopicCategory category) {}
