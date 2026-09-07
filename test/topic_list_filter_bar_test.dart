import 'dart:async';

import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/anchored_picker.dart';
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
    List<TopicCategory>? categories,
    int? selectedCategoryId,
    String? selectedTagName,
    List<String>? selectedTagNames,
    TopicListTagSearch? searchTags,
    ValueChanged<TopicCategory?>? onCategorySelected,
    ValueChanged<String?>? onTagSelected,
    ValueChanged<List<String>>? onTagsSelected,
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
              siteUrl: 'https://example.com',
              categories: categories ?? const [parent, child, other],
              knownTags: knownTags,
              selectedCategoryId: selectedCategoryId,
              selectedTagName: selectedTagName,
              selectedTagNames: selectedTagNames,
              taggingEnabled: true,
              searchTags:
                  searchTags ??
                  (term) async => term == 'design'
                      ? const [TopicFilterLookupValue(name: 'design-system')]
                      : const [],
              onCategorySelected: onCategorySelected ?? (_) {},
              onTagSelected: onTagSelected ?? (_) {},
              onTagsSelected: onTagsSelected,
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

    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('All categories'), findsNothing);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('All tags'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('topic-list-category-filter')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('choice-menu-surface')), findsOneWidget);
    expect(find.text('All categories'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
  });

  testWidgets('sizes short selected filters to their content', (tester) async {
    const bug = TopicCategory(
      id: 99,
      name: 'Bug',
      color: 'E45735',
      slug: 'bug',
    );
    await pumpBar(
      tester,
      categories: const [bug],
      selectedCategoryId: bug.id,
      platform: TargetPlatform.macOS,
    );

    final selectedWidth = tester
        .getSize(find.byKey(const ValueKey('topic-list-category-filter')))
        .width;
    expect(find.text('Bug'), findsOneWidget);
    expect(selectedWidth, lessThan(112));

    await pumpBar(
      tester,
      categories: const [bug],
      platform: TargetPlatform.macOS,
    );
    final unselectedWidth = tester
        .getSize(find.byKey(const ValueKey('topic-list-category-filter')))
        .width;
    expect(selectedWidth, lessThan(unselectedWidth));
    expect(tester.takeException(), isNull);
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

  testWidgets('uses configured icons in the selected filter and menu', (
    tester,
  ) async {
    const iconCategory = TopicCategory(
      id: 4,
      name: 'General',
      color: '3498DB',
      styleType: 'icon',
      icon: 'folder-open',
    );
    await pumpBar(
      tester,
      categories: const [iconCategory],
      selectedCategoryId: iconCategory.id,
      platform: TargetPlatform.macOS,
    );

    Finder configuredIcon(Finder ancestor) => find.descendant(
      of: ancestor,
      matching: find.byWidgetPredicate(
        (widget) => widget is DIcon && widget.icon == DIcons.folderOpen,
      ),
    );

    final filter = find.byKey(const ValueKey('topic-list-category-filter'));
    expect(configuredIcon(filter), findsOneWidget);

    await tester.tap(filter);
    await tester.pumpAndSettle();

    expect(
      configuredIcon(
        find.byKey(const ValueKey(('topic-list-category-indicator', 4))),
      ),
      findsOneWidget,
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

  for (final failOldSearch in [false, true]) {
    testWidgets(
      'ignores stale tag ${failOldSearch ? 'errors' : 'results'} during debounce',
      (tester) async {
        final alpha = Completer<List<TopicFilterLookupValue>>();
        final beta = Completer<List<TopicFilterLookupValue>>();
        final started = <String>[];
        final selected = <String?>[];
        await pumpBar(
          tester,
          platform: TargetPlatform.macOS,
          onTagSelected: selected.add,
          searchTags: (term) {
            started.add(term);
            return switch (term) {
              'alpha' => alpha.future,
              'beta' => beta.future,
              _ => Future.value(const []),
            };
          },
        );
        await tester.tap(find.byKey(const ValueKey('topic-list-tag-filter')));
        await tester.pumpAndSettle();
        final query = find.byKey(const ValueKey('topic-list-tag-filter-query'));

        await tester.enterText(query, 'alpha');
        await tester.pump(const Duration(milliseconds: 250));
        expect(started, ['', 'alpha']);

        await tester.enterText(query, 'beta');
        if (failOldSearch) {
          alpha.completeError(StateError('stale search failed'));
        } else {
          alpha.complete(const [TopicFilterLookupValue(name: 'alpha-tag')]);
        }
        await tester.pump();

        expect(find.text('alpha-tag'), findsNothing);
        expect(find.byType(AnchoredPickerProgress), findsOneWidget);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(selected, isEmpty);
        expect(query, findsOneWidget);

        await tester.pump(const Duration(milliseconds: 249));
        expect(started, ['', 'alpha']);
        await tester.pump(const Duration(milliseconds: 1));
        expect(started, ['', 'alpha', 'beta']);
        beta.complete(const [TopicFilterLookupValue(name: 'beta-tag')]);
        await tester.pumpAndSettle();
        expect(find.text('beta-tag'), findsOneWidget);

        await tester.showKeyboard(query);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(selected, ['beta-tag']);
        expect(query, findsNothing);
      },
    );
  }

  for (final duringRequest in [false, true]) {
    testWidgets(
      'Enter ignores previous tag results ${duringRequest ? 'during search' : 'before debounce'}',
      (tester) async {
        final beta = Completer<List<TopicFilterLookupValue>>();
        final selected = <String?>[];
        final started = <String>[];
        await pumpBar(
          tester,
          platform: TargetPlatform.macOS,
          onTagSelected: selected.add,
          searchTags: (term) {
            started.add(term);
            return term == 'beta'
                ? beta.future
                : Future.value(const [
                    TopicFilterLookupValue(name: 'alpha-tag'),
                  ]);
          },
        );
        await tester.tap(find.byKey(const ValueKey('topic-list-tag-filter')));
        await tester.pumpAndSettle();
        final query = find.byKey(const ValueKey('topic-list-tag-filter-query'));
        await tester.enterText(query, 'alpha');
        await tester.pumpAndSettle(const Duration(milliseconds: 250));
        expect(find.text('alpha-tag'), findsOneWidget);

        await tester.enterText(query, 'beta');
        await tester.pump(
          duringRequest ? const Duration(milliseconds: 250) : Duration.zero,
        );
        expect(started, ['', 'alpha', if (duringRequest) 'beta']);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(selected, isEmpty);
        expect(query, findsOneWidget);
        expect(find.text('alpha-tag'), findsNothing);
        expect(find.byType(AnchoredPickerProgress), findsOneWidget);
        if (!duringRequest) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        beta.complete(const [TopicFilterLookupValue(name: 'beta-tag')]);
        await tester.pumpAndSettle();
        await tester.showKeyboard(query);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(selected, ['beta-tag']);
      },
    );
  }

  testWidgets('drops superseded queued tag searches and keeps lookups serial', (
    tester,
  ) async {
    final alpha = Completer<List<TopicFilterLookupValue>>();
    final delta = Completer<List<TopicFilterLookupValue>>();
    final started = <String>[];
    await pumpBar(
      tester,
      platform: TargetPlatform.macOS,
      searchTags: (term) {
        started.add(term);
        return switch (term) {
          'alpha' => alpha.future,
          'delta' => delta.future,
          _ => Future.value(const []),
        };
      },
    );
    await tester.tap(find.byKey(const ValueKey('topic-list-tag-filter')));
    await tester.pumpAndSettle();
    final query = find.byKey(const ValueKey('topic-list-tag-filter-query'));

    await tester.enterText(query, 'alpha');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(query, 'beta');
    await tester.pump(const Duration(milliseconds: 250));
    expect(started, ['', 'alpha']);

    await tester.enterText(query, 'gamma');
    alpha.complete(const [TopicFilterLookupValue(name: 'alpha-tag')]);
    await tester.pump();
    expect(started, ['', 'alpha']);
    expect(find.byType(AnchoredPickerProgress), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(query, 'delta');
    await tester.pump(const Duration(milliseconds: 249));
    expect(started, ['', 'alpha']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(started, ['', 'alpha', 'delta']);
    delta.complete(const [TopicFilterLookupValue(name: 'delta-tag')]);
    await tester.pumpAndSettle();
    expect(find.text('delta-tag'), findsOneWidget);
    expect(find.text('alpha-tag'), findsNothing);
  });

  for (final multiple in [false, true]) {
    testWidgets(
      'preserves known tag fallback and All tags in ${multiple ? 'multiple' : 'single'} selection mode',
      (tester) async {
        final selected = <String?>[];
        final selections = <List<String>>[];
        final pending = Completer<List<TopicFilterLookupValue>>();
        await pumpBar(
          tester,
          platform: TargetPlatform.macOS,
          selectedTagName: multiple ? 'Native' : 'native',
          selectedTagNames: multiple
              ? const ['Native', 'User experience']
              : null,
          onTagSelected: selected.add,
          onTagsSelected: multiple ? selections.add : null,
          searchTags: (term) => term == 'pending'
              ? pending.future
              : Future.error(StateError('search unavailable')),
        );
        final anchor = find.byKey(const ValueKey('topic-list-tag-filter'));
        final query = find.byKey(const ValueKey('topic-list-tag-filter-query'));
        await tester.tap(anchor);
        await tester.pumpAndSettle();
        await tester.enterText(query, ' UX ');
        await tester.pumpAndSettle(const Duration(milliseconds: 250));

        final known = find.byKey(
          ValueKey((
            'topic-list-tag-filter-option',
            multiple ? 'User experience' : 'ux',
          )),
        );
        expect(known, findsOneWidget);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        if (multiple) {
          expect(selections, [
            <String>['Native'],
          ]);
          expect(selected, isEmpty);
        } else {
          expect(selected, ['ux']);
        }

        await tester.tap(anchor);
        await tester.pumpAndSettle();
        await tester.enterText(query, 'pending');
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(
          find.byKey(const ValueKey('topic-list-tag-filter-all')),
        );
        await tester.pumpAndSettle();
        expect(query, findsNothing);
        if (multiple) {
          expect(selections.last, isEmpty);
        } else {
          expect(selected, ['ux', null]);
        }
        pending.complete(const [TopicFilterLookupValue(name: 'late-tag')]);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

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

  testWidgets('keeps selected filters compact in a narrow viewport', (
    tester,
  ) async {
    await pumpBar(
      tester,
      selectedCategoryId: child.id,
      selectedTagName: 'ux',
      size: const Size(320, 700),
    );

    expect(find.text('Discourse Native App'), findsOneWidget);
    expect(find.text('Design'), findsOneWidget);
    expect(find.text('User experience'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-list-filter-reset')), findsNothing);
    final categoryHeight = tester
        .getSize(find.byKey(const ValueKey('topic-list-category-filter')))
        .height;
    expect(
      categoryHeight,
      tester
          .getSize(find.byKey(const ValueKey('topic-list-tag-filter')))
          .height,
    );
    expect(tester.takeException(), isNull);
  });
}
