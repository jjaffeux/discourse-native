import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/topic_list_filter_bar.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parent = TopicCategory(
    id: 1,
    name: 'Discourse Native App',
    color: '563A93',
    slug: 'discourse-native-app',
    position: 1,
  );
  const child = TopicCategory(
    id: 2,
    name: 'Design',
    color: '3188CC',
    slug: 'design',
    parentCategoryId: 1,
    position: 1,
  );
  const other = TopicCategory(
    id: 3,
    name: 'Support',
    color: '3BBF7B',
    slug: 'support',
    position: 2,
  );
  const knownTags = [
    SidebarTag(id: 10, name: 'User experience', slug: 'ux'),
    SidebarTag(id: 11, name: 'Native', slug: 'native'),
  ];

  Future<void> pumpBar(
    WidgetTester tester, {
    int? selectedCategoryId,
    String? selectedTagName,
    ValueChanged<TopicCategory?>? onCategorySelected,
    ValueChanged<String?>? onTagSelected,
    VoidCallback? onReset,
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
            child: TopicListFilterBar(
              categories: const [parent, child, other],
              knownTags: knownTags,
              selectedCategoryId: selectedCategoryId,
              selectedTagName: selectedTagName,
              taggingEnabled: true,
              searchTags: (term) async => term == 'design'
                  ? const [TopicFilterLookupValue(name: 'design-system')]
                  : const [],
              onCategorySelected: onCategorySelected ?? (_) {},
              onTagSelected: onTagSelected ?? (_) {},
              onReset: onReset ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows category and tag selectors without a result count', (
    tester,
  ) async {
    await pumpBar(tester);

    expect(find.byKey(const ValueKey('topic-list-filter-bar')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-list-category-filter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('topic-list-subcategory-filter')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('topic-list-tag-filter')), findsOneWidget);
    expect(find.textContaining('matching topics'), findsNothing);
    expect(find.byKey(const ValueKey('topic-list-filter-reset')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('labels and opens the unfiltered category selector', (
    tester,
  ) async {
    await pumpBar(tester, platform: TargetPlatform.macOS);

    expect(find.text('All categories'), findsOneWidget);
    expect(find.text('Categories'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('topic-list-category-filter')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('choice-menu-surface')), findsOneWidget);
    expect(find.text('All categories'), findsNWidgets(2));
    expect(find.text('Categories'), findsNothing);
  });

  testWidgets('uses compact, spaced rows and category indicators', (
    tester,
  ) async {
    await pumpBar(tester, platform: TargetPlatform.macOS);

    await tester.tap(find.byKey(const ValueKey('topic-list-category-filter')));
    await tester.pumpAndSettle();

    final parentIndicator = find.byKey(
      const ValueKey(('topic-list-category-indicator', 1)),
    );
    final otherIndicator = find.byKey(
      const ValueKey(('topic-list-category-indicator', 3)),
    );
    expect(parentIndicator, findsOneWidget);
    expect(otherIndicator, findsOneWidget);
    expect(
      tester
          .widget<Container>(
            find.descendant(
              of: parentIndicator,
              matching: find.byType(Container),
            ),
          )
          .decoration,
      isA<BoxDecoration>().having(
        (decoration) => decoration.color,
        'color',
        const Color(0xFF563A93),
      ),
    );
    expect(
      tester
          .widget<Container>(
            find.descendant(
              of: otherIndicator,
              matching: find.byType(Container),
            ),
          )
          .decoration,
      isA<BoxDecoration>().having(
        (decoration) => decoration.color,
        'color',
        const Color(0xFF3BBF7B),
      ),
    );

    final categorySurface = find.byKey(const ValueKey('choice-menu-surface'));
    expect(
      find.descendant(
        of: categorySurface,
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.folder,
        ),
      ),
      findsNothing,
    );

    final firstCategoryRow = find.byKey(
      const ValueKey(('choice-menu-option-background', 1)),
    );
    final secondCategoryRow = find.byKey(
      const ValueKey(('choice-menu-option-background', 3)),
    );
    final categorySingleRowHeight = tester.getSize(secondCategoryRow).height;
    expect(categorySingleRowHeight, 32);
    expect(
      tester.getTopLeft(secondCategoryRow).dy -
          tester.getBottomLeft(firstCategoryRow).dy,
      4,
    );

    final categoryTextStyle = tester.widget<Text>(find.text('Support')).style!;
    Navigator.of(tester.element(categorySurface)).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('topic-list-tag-filter')));
    await tester.pumpAndSettle();
    final tagTile = find.ancestor(
      of: find.text('User experience'),
      matching: find.byType(ListTile),
    );
    final tagTextStyle = tester.widget<ListTile>(tagTile).titleTextStyle!;
    final allTagsRow = find.byKey(const ValueKey('topic-list-tag-filter-all'));
    final firstTagRow = find.byKey(
      const ValueKey(('topic-list-tag-filter-option', 'ux')),
    );

    expect(categoryTextStyle.fontSize, tagTextStyle.fontSize);
    expect(categoryTextStyle.color, tagTextStyle.color);
    expect(categoryTextStyle.fontWeight, tagTextStyle.fontWeight);
    expect(categoryTextStyle.fontWeight, FontWeight.normal);
    expect(
      tester.getTopLeft(firstTagRow).dy - tester.getBottomLeft(allTagsRow).dy,
      4,
    );
    Navigator.of(
      tester.element(
        find.byKey(const ValueKey('topic-list-tag-filter-popover')),
      ),
    ).pop();
    await tester.pumpAndSettle();

    await pumpBar(
      tester,
      selectedCategoryId: parent.id,
      platform: TargetPlatform.macOS,
    );
    final subcategoryFilter = find.byKey(
      const ValueKey('topic-list-subcategory-filter'),
    );
    await tester.ensureVisible(subcategoryFilter);
    await tester.tap(subcategoryFilter);
    await tester.pumpAndSettle();

    expect(find.text('Subcategories of ${parent.name}'), findsNothing);
    final childIndicator = find.byKey(
      const ValueKey(('topic-list-category-indicator', 2)),
    );
    expect(childIndicator, findsOneWidget);
    expect(
      tester
          .widget<Container>(
            find.descendant(
              of: childIndicator,
              matching: find.byType(Container),
            ),
          )
          .decoration,
      isA<BoxDecoration>().having(
        (decoration) => decoration.color,
        'color',
        const Color(0xFF3188CC),
      ),
    );
    final subcategorySurface = find.byKey(
      const ValueKey('choice-menu-surface'),
    );
    expect(
      find.descendant(
        of: subcategorySurface,
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.folder,
        ),
      ),
      findsNothing,
    );
    final subcategoryTextStyle = tester
        .widget<Text>(find.text(child.name))
        .style!;
    expect(subcategoryTextStyle.fontSize, tagTextStyle.fontSize);
    expect(subcategoryTextStyle.color, tagTextStyle.color);
    expect(subcategoryTextStyle.fontWeight, tagTextStyle.fontWeight);
    final allSubcategoriesRow = find.byKey(
      const ValueKey(('choice-menu-option-background', 0)),
    );
    final childRow = find.byKey(
      const ValueKey(('choice-menu-option-background', 2)),
    );
    expect(tester.getSize(childRow).height, categorySingleRowHeight);
    expect(
      tester.getTopLeft(childRow).dy -
          tester.getBottomLeft(allSubcategoriesRow).dy,
      4,
    );
  });

  testWidgets('selects a category and one of its subcategories', (
    tester,
  ) async {
    final selected = <TopicCategory?>[];
    await pumpBar(tester, onCategorySelected: selected.add);

    await tester.tap(find.byKey(const ValueKey('topic-list-category-filter')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Show recent topics'), findsNothing);
    expect(find.textContaining('Show topics in'), findsNothing);
    await tester.tap(find.byKey(const ValueKey(('choice-menu-option', 1))));
    await tester.pumpAndSettle();

    expect(selected.single, parent);

    selected.clear();
    await pumpBar(
      tester,
      selectedCategoryId: parent.id,
      onCategorySelected: selected.add,
    );
    expect(
      find.byKey(const ValueKey('topic-list-subcategory-filter')),
      findsOneWidget,
    );

    final subcategoryFilter = find.byKey(
      const ValueKey('topic-list-subcategory-filter'),
    );
    await tester.ensureVisible(subcategoryFilter);
    await tester.tap(subcategoryFilter);
    await tester.pumpAndSettle();
    expect(find.textContaining('Include every topic'), findsNothing);
    expect(find.textContaining('Show topics in'), findsNothing);
    await tester.tap(find.byKey(const ValueKey(('choice-menu-option', 2))));
    await tester.pumpAndSettle();

    expect(selected.single, child);
  });

  testWidgets('searches tags and returns the selected route value', (
    tester,
  ) async {
    final selected = <String?>[];
    await pumpBar(tester, onTagSelected: selected.add);

    await tester.tap(find.byKey(const ValueKey('topic-list-tag-filter')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey(('topic-list-tag-filter-option', 'ux'))),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('topic-list-tag-filter-query')),
      'design',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final remote = find.byKey(
      const ValueKey(('topic-list-tag-filter-option', 'design-system')),
    );
    expect(remote, findsOneWidget);
    await tester.tap(remote);
    await tester.pumpAndSettle();

    expect(selected.single, 'design-system');
  });

  testWidgets('filters subcategories and accepts keyboard selection', (
    tester,
  ) async {
    final selected = <TopicCategory?>[];
    await pumpBar(
      tester,
      selectedCategoryId: parent.id,
      onCategorySelected: selected.add,
      size: const Size(700, 800),
      platform: TargetPlatform.macOS,
    );

    await tester.tap(
      find.byKey(const ValueKey('topic-list-subcategory-filter')),
    );
    await tester.pumpAndSettle();

    final filter = find.byKey(const ValueKey('choice-menu-filter'));
    expect(filter, findsOneWidget);
    expect(tester.widget<TextField>(filter).autofocus, isTrue);
    await tester.enterText(filter, 'design');
    await tester.pump();

    expect(
      find.byKey(const ValueKey(('choice-menu-option', 2))),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected.single, child);
  });

  testWidgets('keeps selected filters usable in a narrow viewport', (
    tester,
  ) async {
    var reset = false;
    await pumpBar(
      tester,
      selectedCategoryId: child.id,
      selectedTagName: 'ux',
      onReset: () => reset = true,
      size: const Size(320, 700),
    );

    expect(find.text('Discourse Native App'), findsOneWidget);
    expect(find.text('Design'), findsOneWidget);
    expect(find.text('User experience'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-list-filter-reset')),
      findsOneWidget,
    );
    final resetHeight = tester
        .getSize(find.byKey(const ValueKey('topic-list-filter-reset')))
        .height;
    expect(
      resetHeight,
      tester
          .getSize(find.byKey(const ValueKey('topic-list-category-filter')))
          .height,
    );
    expect(
      resetHeight,
      tester
          .getSize(find.byKey(const ValueKey('topic-list-tag-filter')))
          .height,
    );
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(
      find.byKey(const ValueKey('topic-list-filter-reset')),
    );
    await tester.tap(find.byKey(const ValueKey('topic-list-filter-reset')));
    expect(reset, isTrue);
  });
}
