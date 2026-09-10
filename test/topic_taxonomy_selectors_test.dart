import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const support = TopicCategory(id: 1, name: 'Support', color: '0088CC');
  const designCategory = TopicCategory(id: 2, name: 'Design', color: '663399');
  const design = TopicTag(id: 1, name: 'design');
  const mobile = TopicTag(id: 2, name: 'mobile');
  const accessibility = TopicTag(id: 3, name: 'accessibility');
  const staff = TopicTag(
    id: 4,
    name: 'staff',
    disabled: true,
    disabledReason: 'Only staff can use this tag.',
  );

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );

  Future<void> open(WidgetTester tester, Type selector) async {
    await tester.tap(
      find.descendant(
        of: find.byType(selector),
        matching: find.byType(DButton),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder tagOption(String name) =>
      find.byKey(ValueKey(('tag-selector-option', name)));

  testWidgets(
    'category search retires the old result as soon as the query changes',
    (tester) async {
      final first = Completer<List<TopicCategory>>();
      final next = Completer<List<TopicCategory>>();
      final selected = <TopicCategory?>[];
      await pump(
        tester,
        TopicCategorySelector(
          siteUrl: 'https://example.invalid',
          categories: const [support],
          selected: null,
          search: (query) => query.isEmpty ? first.future : next.future,
          onSelected: selected.add,
        ),
      );
      await open(tester, TopicCategorySelector);
      await tester.enterText(
        find.byKey(const ValueKey('category-selector-query')),
        'des',
      );
      await tester.pump(const Duration(milliseconds: 300));
      first.complete(const [support]);
      await tester.pump();
      expect(find.text('Support'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selected, isEmpty);
      next.complete(const [designCategory]);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, [designCategory]);
      expect(find.byType(DComboboxContent), findsNothing);
    },
  );

  testWidgets('category lookup failure can be retried by reopening', (
    tester,
  ) async {
    var attempts = 0;
    await pump(
      tester,
      TopicCategorySelector(
        siteUrl: 'https://example.invalid',
        categories: const [],
        selected: null,
        search: (_) async {
          if (attempts++ == 0) throw StateError('Unavailable');
          return const [support];
        },
        onSelected: (_) {},
      ),
    );
    await open(tester, TopicCategorySelector);
    expect(find.text("Couldn't load categories."), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await open(tester, TopicCategorySelector);
    expect(find.text('Support'), findsOneWidget);
    expect(find.text("Couldn't load categories."), findsNothing);
  });

  testWidgets('custom category trigger keeps an empty removal menu compact', (
    tester,
  ) async {
    final selected = <TopicCategory?>[];
    await pump(
      tester,
      TopicCategorySelector(
        siteUrl: 'https://example.invalid',
        categories: const [],
        selected: support,
        clearSelectionLabel: 'Remove subcategory',
        search: (_) async => const [],
        onSelected: selected.add,
        triggerBuilder: (context, trigger) => DButton(
          key: const ValueKey('custom-category-trigger'),
          label: const Text('Edit category'),
          onPressed: trigger.toggle,
          focusNode: trigger.focusNode,
          expanded: trigger.open,
          hasPopup: true,
        ),
      ),
    );
    await open(tester, TopicCategorySelector);
    expect(find.text('Remove subcategory'), findsOneWidget);
    expect(find.text('No matching categories.'), findsOneWidget);
    expect(tester.getSize(find.byType(DComboboxContent)).height, lessThan(200));

    // An empty search must not implicitly highlight removal.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, [null]);
    expect(find.byType(DComboboxContent), findsNothing);
    expect(
      tester
          .widget<DButton>(
            find.byKey(const ValueKey('custom-category-trigger')),
          )
          .focusNode!
          .hasFocus,
      isTrue,
    );
  });

  testWidgets(
    'tag limits block additions while selected tags remain removable',
    (tester) async {
      var selected = const [design, mobile];
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => TopicTagSelector(
            selectedTags: selected,
            search: (_) async => const TopicTagSearch(
              tags: [design, mobile, accessibility, staff],
            ),
            capabilities: const TopicComposerCapabilities(
              canTagTopics: true,
              maxTagsPerTopic: 2,
            ),
            onChanged: (value) => setState(() => selected = value),
          ),
        ),
      );
      await open(tester, TopicTagSelector);
      await tester.tap(tagOption('accessibility'));
      await tester.pump();
      expect(selected, [design, mobile]);
      expect(find.text('Only staff can use this tag.'), findsOneWidget);
      await tester.tap(tagOption('design'));
      await tester.pumpAndSettle();
      expect(selected, [mobile]);
      await open(tester, TopicTagSelector);
      await tester.tap(tagOption('staff'));
      await tester.pump();
      expect(selected, [mobile]);
      await tester.tap(tagOption('accessibility'));
      await tester.pumpAndSettle();
      expect(selected, [mobile, accessibility]);
      expect(find.text('Tags · 2'), findsOneWidget);
    },
  );

  testWidgets(
    'tag creation waits for permission results and enforces naming rules',
    (tester) async {
      final restricted = Completer<TopicTagSearch>();
      var selected = <TopicTag>[];
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => TopicTagSelector(
            selectedTags: selected,
            search: (query) => query == 'restricted'
                ? restricted.future
                : Future.value(const TopicTagSearch()),
            capabilities: const TopicComposerCapabilities(
              canTagTopics: true,
              canCreateTag: true,
              maxTagLength: 12,
              tagsFilterRegexp: r'[^a-z0-9-]',
            ),
            onChanged: (value) => setState(() => selected = value),
          ),
        ),
      );
      await open(tester, TopicTagSelector);
      final input = find.byKey(const ValueKey('tag-selector-query'));
      final create = find.byKey(const ValueKey('tag-selector-create'));
      await tester.enterText(input, 'restricted');
      await tester.pump(const Duration(milliseconds: 300));
      expect(create, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selected, isEmpty);
      restricted.complete(const TopicTagSearch(forbidden: true));
      await tester.pumpAndSettle();
      expect(find.text('Tags are not allowed here.'), findsOneWidget);
      expect(create, findsNothing);
      for (final name in ['invalid tag', 'too-long-to-create']) {
        await tester.enterText(input, name);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(create, findsNothing);
      }
      await tester.enterText(input, 'new-tag');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(create, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, const [TopicTag(name: 'new-tag')]);
      expect(find.byType(DComboboxContent), findsNothing);
    },
  );

  testWidgets('a replaced category scope ignores pending tag results', (
    tester,
  ) async {
    final pending = Completer<TopicTagSearch>();
    final changes = <List<TopicTag>>[];
    await pump(
      tester,
      TopicTagSelector(
        key: const ValueKey(1),
        selectedTags: const [],
        search: (_) => pending.future,
        onChanged: changes.add,
      ),
    );
    await open(tester, TopicTagSelector);
    await pump(
      tester,
      TopicTagSelector(
        key: const ValueKey(2),
        selectedTags: const [],
        search: (_) async => const TopicTagSearch(tags: [mobile]),
        onChanged: changes.add,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DComboboxContent), findsNothing);
    pending.complete(const TopicTagSearch(tags: [design]));
    await tester.pumpAndSettle();
    await open(tester, TopicTagSelector);
    expect(tagOption('design'), findsNothing);
    await tester.tap(tagOption('mobile'));
    await tester.pumpAndSettle();
    expect(changes, [
      [mobile],
    ]);
    expect(tester.takeException(), isNull);
  });
}
