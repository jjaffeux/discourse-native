import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
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
    double textScale = 1,
    TextDirection direction = TextDirection.ltr,
    bool wrap = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
            alignment: Alignment.topLeft,
            child: TopicListFilterBar(
              wrap: wrap,
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

    expect(
      find.byKey(const ValueKey('topic-list-category-popover')),
      findsOneWidget,
    );
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

  testWidgets(
    'keeps All categories available without matching results and resets search on reopen',
    (tester) async {
      final selected = <TopicCategory?>[];
      await pumpBar(
        tester,
        selectedCategoryId: parent.id,
        onCategorySelected: selected.add,
      );
      final anchor = find.byKey(const ValueKey('topic-list-category-filter'));
      final query = find.byKey(const ValueKey('topic-list-category-query'));
      await tester.tap(anchor);
      await tester.pumpAndSettle();
      await tester.enterText(query, 'missing');
      await tester.pumpAndSettle();
      expect(find.text('No matching categories.'), findsOneWidget);
      expect(find.text('All categories'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, isEmpty);
      await tester.tap(find.text('All categories'));
      await tester.pumpAndSettle();
      expect(selected, [null]);
      await tester.tap(anchor);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: query, matching: find.byType(TextField)),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('Support'), findsOneWidget);
    },
  );

  testWidgets(
    'multi-tag choices use names, reflect selected values and clear together',
    (tester) async {
      final selections = <List<String>>[];
      await pumpBar(
        tester,
        selectedTagNames: const [],
        onTagsSelected: selections.add,
      );
      final anchor = find.byKey(const ValueKey('topic-list-tag-filter'));
      await tester.tap(anchor);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey(('topic-list-tag-filter-option', 'Native'))),
      );
      await tester.pumpAndSettle();
      expect(selections.single, ['Native']);
      expect(find.byType(DComboboxContent), findsNothing);

      await pumpBar(
        tester,
        selectedTagNames: const ['Native', 'User experience'],
        onTagsSelected: selections.add,
      );
      expect(find.text('Tags · 2'), findsOneWidget);
      await tester.tap(anchor);
      await tester.pumpAndSettle();
      final combobox = tester.widget<DCombobox<TopicTag>>(
        find.byType(DCombobox<TopicTag>),
      );
      expect(combobox.controlledValues.map((tag) => tag.name), [
        'Native',
        'User experience',
      ]);
      await tester.tap(
        find.byKey(const ValueKey(('topic-list-tag-filter-option', 'Native'))),
      );
      await tester.pumpAndSettle();
      expect(selections.last, ['User experience']);
      await tester.tap(anchor);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-list-tag-filter-all')));
      await tester.pumpAndSettle();
      expect(selections.last, isEmpty);
    },
  );

  testWidgets(
    'tag lookup starts on open and discards results after dismissal',
    (tester) async {
      final searches = <String>[];
      final pending = Completer<List<TopicFilterLookupValue>>();
      await pumpBar(
        tester,
        platform: TargetPlatform.macOS,
        searchTags: (query) {
          searches.add(query);
          return query == 'old' ? pending.future : Future.value(const []);
        },
      );
      expect(searches, isEmpty);
      final anchor = find.byKey(const ValueKey('topic-list-tag-filter'));
      await tester.tap(anchor);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('topic-list-tag-filter-query')),
        'old',
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(searches, ['', 'old']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      pending.complete(const [TopicFilterLookupValue(name: 'retired-tag')]);
      await tester.pumpAndSettle();
      expect(find.byType(DComboboxContent), findsNothing);
      await tester.tap(anchor);
      await tester.pumpAndSettle();
      expect(searches, ['', 'old', '']);
      expect(find.text('retired-tag'), findsNothing);
      expect(find.text('User experience'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets('filter popups fit 320px with large text in $direction', (
      tester,
    ) async {
      await pumpBar(
        tester,
        selectedCategoryId: child.id,
        size: const Size(320, 700),
        textScale: 2,
        direction: direction,
        wrap: true,
      );
      for (final kind in ['category', 'subcategory', 'tag']) {
        await tester.tap(find.byKey(ValueKey('topic-list-$kind-filter')));
        await tester.pumpAndSettle();
        final popup = tester.getRect(find.byType(DComboboxContent));
        expect(popup.left, greaterThanOrEqualTo(0));
        expect(popup.right, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets(
    'uses kit rows and preserves category indicators across filters',
    (tester) async {
      await pumpBar(
        tester,
        platform: TargetPlatform.macOS,
        selectedCategoryId: parent.id,
      );
      for (final kind in ['category', 'subcategory', 'tag']) {
        await tester.ensureVisible(
          find.byKey(ValueKey('topic-list-$kind-filter')),
        );
        await tester.tap(find.byKey(ValueKey('topic-list-$kind-filter')));
        await tester.pumpAndSettle();
        expect(find.byType(DComboboxContent), findsOneWidget);
        expect(find.byType(ListTile), findsNothing);
        final row = find.byKey(switch (kind) {
          'category' => const ValueKey(('topic-list-category-option', 3)),
          'subcategory' => const ValueKey(('topic-list-subcategory-option', 2)),
          _ => const ValueKey(('topic-list-tag-filter-option', 'ux')),
        });
        expect(tester.getSize(row).height, 28);
        if (kind != 'tag') {
          final indicator = find.byKey(
            ValueKey(('category-selector-icon', kind == 'category' ? 3 : 2)),
          );
          final swatch = tester.widget<Container>(
            find.descendant(of: indicator, matching: find.byType(Container)),
          );
          expect(
            (swatch.decoration! as BoxDecoration).color,
            kind == 'category'
                ? const Color(0xFF3BBF7B)
                : const Color(0xFF3188CC),
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(DComboboxContent), findsNothing);
        final button = tester.widget<DButton>(
          find.descendant(
            of: find.byKey(ValueKey('topic-list-$kind-filter')),
            matching: find.byType(DButton),
          ),
        );
        expect(button.focusNode!.hasFocus, isTrue);
      }
    },
  );

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
      configuredIcon(find.byKey(const ValueKey(('category-selector-icon', 4)))),
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
    await tester.tap(
      find.byKey(const ValueKey(('topic-list-category-option', 1))),
    );
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
    await tester.tap(
      find.byKey(const ValueKey(('topic-list-subcategory-option', 2))),
    );
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
        expect(find.byType(DSpinner), findsOneWidget);
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
        expect(find.byType(DSpinner), findsOneWidget);
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
    expect(find.byType(DSpinner), findsOneWidget);

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

    final filter = find.byKey(const ValueKey('topic-list-subcategory-query'));
    expect(filter, findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: filter, matching: find.byType(TextField)),
          )
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await tester.enterText(filter, 'design');
    await tester.pump();

    expect(
      find.byKey(const ValueKey(('topic-list-subcategory-option', 2))),
      findsOneWidget,
    );
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
