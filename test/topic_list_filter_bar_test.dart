import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/topic_list_filter_bar.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
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

  testWidgets('selects a category and one of its subcategories', (
    tester,
  ) async {
    final selected = <TopicCategory?>[];
    await pumpBar(tester, onCategorySelected: selected.add);

    await tester.tap(find.byKey(const ValueKey('topic-list-category-filter')));
    await tester.pumpAndSettle();
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
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(
      find.byKey(const ValueKey('topic-list-filter-reset')),
    );
    await tester.tap(find.byKey(const ValueKey('topic-list-filter-reset')));
    expect(reset, isTrue);
  });
}
