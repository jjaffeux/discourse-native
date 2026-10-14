import 'dart:async';
import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_filter_controller.dart';
import 'package:discourse_native/src/shell/topic_list_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart' show primaryMainContent;

const _siteUrl = 'https://meta.discourse.org';
const _tagOption = TopicFilterOption(
  name: 'tag:',
  alias: 'tags:',
  description: 'Topics carrying a tag',
  priority: 1,
  type: 'tag',
  delimiters: [
    TopicFilterModifier(name: ',', description: 'Any tag'),
    TopicFilterModifier(name: '+', description: 'All tags'),
  ],
  prefixes: [TopicFilterModifier(name: '-', description: 'Exclude tag')],
);
const _groupOption = TopicFilterOption(
  name: 'group:',
  type: 'group',
  priority: 1,
);

void main() {
  test('topic lists defensively parse server-provided filter options', () {
    final list = TopicList.fromJson(const {
      'topic_list': {
        'topics': <Object?>[],
        'filter_option_info': [
          false,
          {'name': 4},
          {
            'name': 'tag:',
            'alias': 'tags:',
            'description': 'By tag',
            'priority': 1,
            'type': 'tag',
            'delimiters': [
              {'name': '+', 'description': 'All'},
              {'name': false},
            ],
            'prefixes': [
              {'name': '-', 'description': 'Exclude'},
            ],
            'extra_entries': [
              {'name': '*', 'description': 'Anyone'},
            ],
          },
        ],
      },
    }, _siteUrl);

    expect(list.filterOptions, hasLength(1));
    final option = list.filterOptions.single;
    expect(option.name, 'tag:');
    expect(option.alias, 'tags:');
    expect(option.delimiters.single.name, '+');
    expect(option.prefixes.single.description, 'Exclude');
    expect(option.extraEntries.single.name, '*');
  });

  group('core-like suggestions', () {
    TopicFilterSuggestions engine({
      List<TopicFilterOption> options = const [_tagOption],
      TopicFilterLookup? tags,
      TopicFilterLookup? tagGroups,
      TopicFilterLookup? users,
      TopicFilterLookup? groups,
      TopicFilterCategoryLookup? categoryLookup,
    }) => TopicFilterSuggestions(
      options: options,
      categories: const [
        TopicCategory(
          id: 2,
          name: 'Feature requests',
          slug: 'feature',
          color: '0088CC',
        ),
      ],
      categoryLookup: categoryLookup ?? (_) async => const [],
      tags: tags ?? (_) async => const [],
      tagGroups: tagGroups ?? (_) async => const [],
      users: users ?? (_) async => const [],
      groups: groups ?? (_) async => const [],
    );

    test('offers priority tips, aliases, and supported prefixes', () async {
      final subject = engine();

      expect((await subject.suggestions('')).map((item) => item.name), [
        'tag:',
      ]);
      expect((await subject.suggestions('ta')).map((item) => item.name), [
        'tag:',
        '-tag:',
      ]);
      expect((await subject.suggestions('-tags')).single.name, '-tag:');
    });

    test('starts a new suggestion segment after a line break', () async {
      final subject = engine();

      expect(
        (await subject.suggestions('status:open\n')).map((item) => item.name),
        ['tag:'],
      );
    });

    test('splits clauses without breaking quoted values', () {
      expect(
        splitTopicFilterQuery(
          'category:design status:open tag_group:"Design team"',
        ),
        ['category:design', 'status:open', 'tag_group:"Design team"'],
      );
      expect(
        topicFilterQueryEndsWithSeparator('tag_group:"Design team" '),
        isTrue,
      );
      expect(
        topicFilterQueryEndsWithSeparator('tag_group:"Design team '),
        isFalse,
      );
    });

    test('extracts editable keys without treating quoted text as a clause', () {
      for (final prefix in ['', '-', '=', '-=', '=-']) {
        expect(
          topicFilterClauseKey('${prefix}tag_group:"Design team"'),
          '${prefix}tag_group:',
        );
      }
      expect(topicFilterClauseKey('category:parent:child'), 'category:');
      expect(topicFilterClauseKey('"status:open"'), isNull);
      expect(topicFilterClauseKey('feedback'), isNull);
    });

    test('shortcuts replace their key and preserve unrelated clauses', () {
      expect(
        setTopicFilterShortcut(
          'tag:"customer feedback" status:open status:noreplies '
              'in:watching "status:open" -status:open',
          'status:closed',
          selected: true,
        ),
        'tag:"customer feedback" in:watching "status:open" '
        '-status:open status:closed',
      );
      expect(
        setTopicFilterShortcut(
          'status:open in:bookmarked in:watching',
          'in:unseen',
          selected: true,
        ),
        'status:open in:unseen',
      );
      expect(
        setTopicFilterShortcut(
          'STATUS:open tag:bug',
          'status:closed',
          selected: true,
        ),
        'tag:bug status:closed',
      );
    });

    test('deselecting a shortcut removes its duplicates only', () {
      expect(
        setTopicFilterShortcut(
          'status:open tag:bug status:closed status:open',
          'status:open',
          selected: false,
        ),
        'tag:bug status:closed',
      );
    });

    test(
      'completes multi-value tags and suppresses values already used',
      () async {
        final subject = engine(
          tags: (_) async => const [
            TopicFilterLookupValue(name: 'bug', description: '4'),
            TopicFilterLookupValue(name: 'support', description: '2'),
          ],
        );

        final first = await subject.suggestions('tag:bug');
        expect(first.map((item) => item.name), contains('tag:bug+'));
        expect(first.map((item) => item.name), contains('tag:bug,'));

        final next = await subject.suggestions('tag:bug+su');
        expect(next.map((item) => item.name), contains('tag:bug+support'));
        expect(next.map((item) => item.name), isNot(contains('tag:bug+bug')));
      },
    );

    test(
      'bounds oversized remote suggestions after delimiter actions',
      () async {
        final subject = engine(
          tags: (_) async => [
            const TopicFilterLookupValue(name: 'used'),
            const TopicFilterLookupValue(name: 'exact'),
            for (var index = 0; index < 20; index++)
              TopicFilterLookupValue(name: 'value-$index'),
          ],
        );

        final suggestions = await subject.suggestions('tag:used+exact');

        expect(suggestions, hasLength(TopicFilterSuggestions.maxResults));
        expect(suggestions.first.name, 'tag:used+exact');
        expect(suggestions.last.name, 'tag:used+value-18');
        expect(
          suggestions.map((suggestion) => suggestion.term),
          isNot(contains('used')),
        );
        final names = suggestions.map((suggestion) => suggestion.name);
        expect(names, isNot(contains('tag:used+value-19')));
        expect(names, isNot(contains('tag:used+exact,')));
        expect(names, isNot(contains('tag:used+exact+')));
      },
    );

    test('category suggestions stop at the result cap', () async {
      final subject = TopicFilterSuggestions(
        options: const [TopicFilterOption(name: 'category:', type: 'category')],
        categories: [
          for (var index = 0; index < 12; index++)
            TopicCategory(
              id: index + 1,
              name: 'Category $index',
              slug: 'category-$index',
              color: '0088CC',
            ),
        ],
        categoryLookup: (_) async => const [],
        tags: (_) async => const [],
        tagGroups: (_) async => const [],
        users: (_) async => const [],
        groups: (_) async => const [],
      );

      final all = await subject.suggestions('category:');
      expect(all, hasLength(10));
      expect(all.first.name, 'category:category-0');

      final one = await subject.suggestions('category:category-11');
      expect(one.single.name, 'category:category-11');
    });

    test(
      'loads missing categories and qualifies duplicate child slugs',
      () async {
        const design = TopicCategory(
          id: 1,
          name: 'Design',
          slug: 'design',
          color: 'AA00AA',
        );
        const designBugs = TopicCategory(
          id: 2,
          name: 'Bugs',
          slug: 'bugs',
          color: 'BB00BB',
          parentCategoryId: 1,
        );
        const nativeApp = TopicCategory(
          id: 3,
          name: 'Discourse Native App',
          slug: 'discourse-native-app',
          color: '0088CC',
        );
        const nativeBugs = TopicCategory(
          id: 4,
          name: 'Bugs',
          slug: 'bugs',
          color: '00AACC',
          parentCategoryId: 3,
        );
        final lookedUp = <String>[];
        final subject = TopicFilterSuggestions(
          options: const [
            TopicFilterOption(name: 'category:', type: 'category'),
          ],
          categories: const [design, designBugs],
          categoryLookup: (term) async {
            lookedUp.add(term);
            return const [nativeBugs, nativeApp];
          },
          tags: (_) async => const [],
          tagGroups: (_) async => const [],
          users: (_) async => const [],
          groups: (_) async => const [],
        );

        final suggestions = await subject.suggestions('category:bugs');

        expect(lookedUp, ['bugs']);
        expect(suggestions.map((item) => item.name), [
          'category:discourse-native-app:bugs',
          'category:design:bugs',
        ]);
        expect(suggestions.map((item) => item.description), [
          'Discourse Native App › Bugs',
          'Design › Bugs',
        ]);
        expect(suggestions.first.parentCategory, nativeApp);
      },
    );

    test(
      'quotes tag groups and provides local category, date, and number values',
      () async {
        final subject = engine(
          options: const [
            TopicFilterOption(name: 'category:', type: 'category'),
            TopicFilterOption(name: 'tag_group:', type: 'tag_group'),
            TopicFilterOption(name: 'created-after:', type: 'date'),
            TopicFilterOption(name: 'likes-min:', type: 'number'),
          ],
          tagGroups: (_) async => const [
            TopicFilterLookupValue(name: 'Cat & Dogs'),
          ],
        );

        expect(
          (await subject.suggestions('category:feat')).single.name,
          'category:feature',
        );
        expect(
          (await subject.suggestions('tag_group:cat')).single.name,
          'tag_group:"Cat & Dogs"',
        );
        expect(
          (await subject.suggestions(
            'created-after:last',
          )).map((item) => item.name),
          contains('created-after:7'),
        );
        expect(
          (await subject.suggestions('likes-min:1')).map((item) => item.name),
          containsAll(['likes-min:1', 'likes-min:10']),
        );
      },
    );

    test(
      'a newer lookup waits for the active request and owns the result',
      () async {
        final old = Completer<List<TopicFilterLookupValue>>();
        final current = Completer<List<TopicFilterLookupValue>>();
        final terms = <String>[];
        final controller = TopicFilterController(
          initialQuery: 'tag:a',
          submitQuery: (_) async {},
          engine: engine(
            tags: (term) {
              terms.add(term);
              return term == 'a' ? old.future : current.future;
            },
          ),
        );
        addTearDown(controller.dispose);

        final oldRequest = controller.refreshSuggestions();
        controller.text.text = 'tag:b';
        final currentRequest = controller.refreshSuggestions();
        await Future<void>.delayed(Duration.zero);

        expect(terms, ['a']);
        old.complete(const [TopicFilterLookupValue(name: 'alpha')]);
        await oldRequest;
        expect(terms, ['a', 'b']);
        current.complete(const [TopicFilterLookupValue(name: 'beta')]);
        await currentRequest;

        expect(controller.suggestions.single.name, 'tag:beta');
      },
    );

    test('selects the first visible suggestion while input changes', () async {
      final controller = TopicFilterController(
        initialQuery: 'tag:b',
        submitQuery: (_) async {},
        engine: engine(
          tags: (_) async => const [
            TopicFilterLookupValue(name: 'bug'),
            TopicFilterLookupValue(name: 'beta'),
          ],
        ),
      );
      addTearDown(controller.dispose);

      await controller.openSuggestions();
      expect(controller.selectedIndex, 0);
      expect(controller.selected?.name, 'tag:bug');

      controller.moveSelection(1);
      expect(controller.selectedIndex, 1);

      controller.text.text = 'tag:bu';
      controller.inputChanged('tag:bu');
      expect(controller.selectedIndex, 0);

      await controller.ensureFreshSuggestions();
      expect(controller.selectedIndex, 0);
      expect(controller.selected?.name, 'tag:bug');
    });

    test(
      'a failed lookup closes suggestions without failing the field',
      () async {
        final controller = TopicFilterController(
          initialQuery: 'tag:bug',
          submitQuery: (_) async {},
          engine: engine(tags: (_) => Future.error(StateError('offline'))),
        );
        addTearDown(controller.dispose);

        await controller.openSuggestions();

        expect(controller.suggestions, isEmpty);
        expect(controller.isOpen, isFalse);
      },
    );

    test('dismissed suggestions reopen for the same input', () async {
      final controller = TopicFilterController(
        initialQuery: 'tag:bu',
        submitQuery: (_) async {},
        engine: engine(
          tags: (_) async => const [TopicFilterLookupValue(name: 'bug')],
        ),
      );
      addTearDown(controller.dispose);

      await controller.openSuggestions();
      expect(controller.isOpen, isTrue);
      expect(
        controller.suggestions.map((item) => item.name),
        contains('tag:bug'),
      );

      controller.dismiss();
      expect(controller.isOpen, isFalse);
      expect(controller.suggestions, isEmpty);

      await controller.openSuggestions();

      expect(controller.isOpen, isTrue);
      expect(
        controller.suggestions.map((item) => item.name),
        contains('tag:bug'),
      );
    });

    test(
      'a lookup that threw is retried by the next ensureFreshSuggestions',
      () async {
        var lookups = 0;
        final controller = TopicFilterController(
          initialQuery: 'tag:bug',
          submitQuery: (_) async {},
          engine: engine(
            tags: (_) {
              lookups++;
              if (lookups == 1) return Future.error(StateError('offline'));
              return Future.value(const [TopicFilterLookupValue(name: 'bug')]);
            },
          ),
        );
        addTearDown(controller.dispose);

        await controller.openSuggestions();
        expect(lookups, 1);
        expect(controller.isOpen, isFalse);

        await controller.ensureFreshSuggestions();

        expect(lookups, 2);
        expect(controller.isOpen, isTrue);
        expect(
          controller.suggestions.map((item) => item.name),
          contains('tag:bug'),
        );
      },
    );

    test(
      'dispose settles the active lookup and ignores later refreshes',
      () async {
        final gate = Completer<List<TopicFilterLookupValue>>();
        var lookups = 0;
        final controller = TopicFilterController(
          initialQuery: 'tag:bug',
          submitQuery: (_) async {},
          engine: engine(
            tags: (_) {
              lookups++;
              return gate.future;
            },
          ),
        );

        final active = controller.refreshSuggestions();
        await pumpEventQueue();
        expect(lookups, 1);

        var activeSettled = false;
        unawaited(active.then<void>((_) => activeSettled = true));
        controller.dispose();

        var lateSettled = false;
        unawaited(
          controller.refreshSuggestions().then<void>((_) => lateSettled = true),
        );
        await pumpEventQueue();

        expect(activeSettled, isTrue);
        expect(lateSettled, isTrue);
        expect(lookups, 1);

        gate.complete(const []);
        await pumpEventQueue();
      },
    );
  });

  testWidgets('the Topics filter menu submits and clears a native feed', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {
        '/latest.json': [],
        '/filter.json': [
          Topic(id: 1, title: 'Every topic', slug: 'every-topic'),
        ],
        '/filter.json?q=status%3Aopen': [
          Topic(id: 2, title: 'Only open topics', slug: 'open-topic'),
        ],
      },
      filterOptionsByPath: const {
        '/filter.json': [_tagOption],
        '/filter.json?q=status%3Aopen': [_tagOption],
      },
    );
    await _pump(tester, api);

    expect(
      find.descendant(
        of: find.byType(InstanceSidebar),
        matching: find.text('Filter'),
      ),
      findsNothing,
    );
    await _openFilter(tester);

    expect(
      find.descendant(
        of: primaryMainContent,
        matching: find.byWidgetPredicate(
          (w) => w is TopicListFilterMenu && w.filterKey == null,
        ),
      ),
      findsOneWidget,
    );
    expect(api.feedPaths, contains('/filter.json'));

    final field = find.descendant(
      of: find.byKey(const ValueKey('topic-filter-input')),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'status:open');
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      api.feedPaths.where((path) => path.startsWith('/filter.json')),
      hasLength(1),
      reason: 'typing only updates suggestions',
    );

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(api.feedPaths, contains('/filter.json?q=status%3Aopen'));
    expect(find.text('Only open topics'), findsOneWidget);

    await _openFilter(tester);
    expect(
      _filterQuery(tester),
      'status:open',
      reason: 'the submitted query belongs to this site and destination',
    );

    await tester.tap(find.text('Clear filter'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topic-filter-input')), findsNothing);
    expect(find.text('Filtered'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('filter suggestions can be chosen without submitting the feed', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/filter.json': []},
      filterOptionsByPath: const {
        '/filter.json': [_tagOption],
      },
      filterTagSearches: const {
        'bu': [TopicFilterLookupValue(name: 'bug', description: '4')],
        'bug': [TopicFilterLookupValue(name: 'bug', description: '4')],
      },
    );
    await _pump(tester, api);
    await _openFilter(tester);

    final field = find.descendant(
      of: find.byKey(const ValueKey('topic-filter-input')),
      matching: find.byType(TextField),
    );
    await tester.tap(field);
    await tester.enterText(field, 'tag:bu');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('bug'), findsOneWidget);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('bug')),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_filterQuery(tester), 'tag:bug tag:');
    expect(find.text('tag: bug'), findsOneWidget);
    expect(api.feedPaths, ['/latest.json', '/filter.json']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('group suggestions show only the group name', (tester) async {
    const groupName = '2024-tokyo-dinner2-tuesday';
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/filter.json': []},
      filterOptionsByPath: const {
        '/filter.json': [_groupOption],
      },
      filterGroupSearches: const {
        'tokyo': [
          TopicFilterLookupValue(
            name: groupName,
            description: 'Tokyo dinner on Tuesday',
          ),
        ],
      },
    );
    await _pump(tester, api, authenticated: true);
    await _openFilter(tester);

    final field = find.descendant(
      of: find.byKey(const ValueKey('topic-filter-input')),
      matching: find.byType(TextField),
    );
    await tester.tap(field);
    await tester.enterText(field, 'group:tokyo');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    final row = find.byKey(const ValueKey('topic-filter-suggestion-0'));
    expect(find.descendant(of: row, matching: find.text(groupName)), findsOne);
    expect(
      find.descendant(of: row, matching: find.text('group:$groupName')),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.text('Tokyo dinner on Tuesday')),
      findsNothing,
    );
    _expectSelectedRow(tester, row);
    _expectSuggestionSemantics(tester, row, label: groupName, selected: true);

    await tester.tap(find.descendant(of: row, matching: find.text(groupName)));
    await tester.pumpAndSettle();
    expect(_filterQuery(tester), 'group:$groupName');
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('the filter menu remains usable while vocabulary loads', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/filter.json': []},
      feedGates: {'/filter.json': gate},
    );
    await _pump(tester, api);
    await _openFilter(tester, settle: false);
    expect(find.byKey(const ValueKey('topic-filter-input')), findsOneWidget);
    expect(find.byType(DProgress), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('topic-filter-input')),
      'status:noreplies',
    );
    await tester.pump();
    expect(_filterQuery(tester), 'status:noreplies');
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(DProgress), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'filter suggestions support keyboard selection and pointer hover',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final api = FakeDiscourseApi(
        feeds: const {'/latest.json': [], '/filter.json': []},
        filterOptionsByPath: const {
          '/filter.json': [
            TopicFilterOption(name: 'status:', priority: 1),
            _tagOption,
          ],
        },
      );
      try {
        await _pump(tester, api);
        await _openFilter(tester);

        final field = find.descendant(
          of: find.byKey(const ValueKey('topic-filter-input')),
          matching: find.byType(TextField),
        );
        await tester.tap(field);
        await tester.pumpAndSettle();

        final firstRow = find.byKey(
          const ValueKey('topic-filter-suggestion-2'),
        );
        final secondRow = find.byKey(
          const ValueKey('topic-filter-suggestion-1'),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(tester.getSize(firstRow).height, greaterThanOrEqualTo(32));
        expect(tester.getSize(secondRow).height, greaterThanOrEqualTo(32));
        expect(
          find.descendant(of: firstRow, matching: find.byType(DIcon)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: secondRow, matching: find.byType(DIcon)),
          findsOneWidget,
        );
        _expectSelectedRow(tester, firstRow);
        _expectSuggestionSemantics(
          tester,
          firstRow,
          label: 'Tag',
          selected: true,
        );
        _expectSuggestionSemantics(
          tester,
          secondRow,
          label: 'Status',
          selected: false,
        );

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer();
        await mouse.moveTo(tester.getCenter(firstRow));
        await tester.pump();
        _expectSelectedRow(tester, firstRow);
        _expectSuggestionSemantics(
          tester,
          firstRow,
          label: 'Tag',
          selected: true,
        );
        _expectSuggestionSemantics(
          tester,
          secondRow,
          label: 'Status',
          selected: false,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        _expectSelectedRow(tester, secondRow);
        _expectSuggestionSemantics(
          tester,
          firstRow,
          label: 'Tag',
          selected: false,
        );
        _expectSuggestionSemantics(
          tester,
          secondRow,
          label: 'Status',
          selected: true,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        _expectSelectedRow(tester, firstRow);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        _expectSelectedRow(
          tester,
          find.byKey(const ValueKey('topic-filter-suggestion-0')),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        _expectSelectedRow(tester, secondRow);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller!.text, 'status:');
        expect(api.feedPaths, ['/latest.json', '/filter.json']);
      } finally {
        semantics.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('a retired filter menu cannot change the replacement feed', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {
        '/latest.json': [],
        '/filter.json': [],
        '/top.json?period=weekly': [],
      },
    );
    await _pump(tester, api);
    await _openFilter(tester);
    await tester.enterText(
      find.byKey(const ValueKey('topic-filter-input')),
      'status:open',
    );
    await tester.pumpAndSettle();
    final shell = ShellScope.read(
      tester.element(
        find.descendant(
          of: primaryMainContent,
          matching: find.byWidgetPredicate(
            (w) => w is TopicListFilterMenu && w.filterKey == null,
          ),
        ),
      ),
    );
    final apply = tester
        .widget<DButton>(
          find.ancestor(of: find.text('Apply'), matching: find.byType(DButton)),
        )
        .onPressed!;
    unawaited(shell.selectTopicListMode(TopicListMode.topWeekly));
    final replacement = shell.topicListContent;
    apply();
    await tester.pumpAndSettle();
    expect(shell.topicListContent, replacement);
    expect(find.text('Apply'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('tab accepts the first filter suggestion', (tester) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/filter.json': []},
      filterOptionsByPath: const {
        '/filter.json': [_tagOption],
      },
    );
    await _pump(tester, api);
    await _openFilter(tester);

    final field = find.descendant(
      of: find.byKey(const ValueKey('topic-filter-input')),
      matching: find.byType(TextField),
    );
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(field).controller!.text, 'category:');
    expect(api.feedPaths, ['/latest.json', '/filter.json']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('editing a chip stages its key and applies the replacement', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/filter.json': []},
      filterOptionsByPath: const {
        '/filter.json': [
          TopicFilterOption(name: 'status:open'),
          TopicFilterOption(name: 'status:closed'),
        ],
      },
    );
    await _pump(tester, api);
    await _openFilter(tester);
    final textarea = find.byKey(const ValueKey('topic-filter-input'));
    final field = find.descendant(
      of: textarea,
      matching: find.byType(TextField),
    );
    await tester.enterText(textarea, 'tag:"customer feedback" status:open ');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('topic-filter-token-edit-1')));
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(field);
    expect(input.controller!.text, 'status:');
    expect(
      input.controller!.selection,
      const TextSelection.collapsed(offset: 7),
    );
    expect(input.focusNode!.hasFocus, isTrue);
    expect(_filterQuery(tester), 'tag:"customer feedback" status:');
    expect(find.text('status: open'), findsNothing);
    expect(find.text('Status: closed'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_filterQuery(tester), 'tag:"customer feedback" status:closed');
    expect(api.feedPaths, ['/latest.json', '/filter.json']);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(
      api.feedPaths,
      contains(
        '/filter.json?q=${Uri.encodeQueryComponent('status:closed tag:"customer feedback"')}',
      ),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Backspace dismantles a token through its staged key', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/filter.json': []},
    );
    await _pump(tester, api);
    await _openFilter(tester);
    final textarea = find.byKey(const ValueKey('topic-filter-input'));
    await tester.enterText(textarea, 'tag:bug -tag_group:"Design team" ');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(_filterQuery(tester), 'tag:bug -tag_group:');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(_filterQuery(tester), 'tag:bug');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(_filterQuery(tester), 'tag:');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(_filterQuery(tester), isEmpty);
    expect(api.feedPaths, ['/latest.json', '/filter.json']);

    await tester.enterText(textarea, '"status:open" ');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: textarea, matching: find.byType(TextField)),
          )
          .controller!
          .text,
      '"status:open"',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('chip editing and removal are separate keyboard actions', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/filter.json': []},
    );
    await _pump(tester, api);
    await _openFilter(tester);
    final textarea = find.byKey(const ValueKey('topic-filter-input'));
    await tester.enterText(textarea, 'category:parent:child status:open ');
    await tester.pumpAndSettle();
    final edit = find.byKey(const ValueKey('topic-filter-token-edit-0'));
    expect(
      tester.widget<DButton>(edit).semanticLabel,
      'Edit filter category: Parent › Child',
    );
    Focus.of(
      tester.element(
        find.descendant(of: edit, matching: find.byType(Text)).first,
      ),
    ).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_filterQuery(tester), 'status:open category:');
    await tester.tap(find.byKey(const ValueKey('topic-filter-token-remove-0')));
    await tester.pumpAndSettle();
    expect(_filterQuery(tester), 'category:');
    expect(find.text('status: open'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  for (final modifier in [
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.controlLeft,
  ]) {
    testWidgets('$modifier submits while suggestions are open', (tester) async {
      final api = FakeDiscourseApi(
        feeds: const {
          '/latest.json': [],
          '/filter.json': [],
          '/filter.json?q=tag': [],
        },
        filterOptionsByPath: const {
          '/filter.json': [_tagOption],
        },
      );
      await _pump(tester, api);
      await _openFilter(tester);
      await tester.enterText(
        find.byKey(const ValueKey('topic-filter-input')),
        'tag',
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(DCommandList<String>),
          matching: find.text('Tag  ${_tagOption.description}'),
        ),
        findsOneWidget,
      );
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(api.feedPaths, contains('/filter.json?q=tag'));
      expect(find.byKey(const ValueKey('topic-filter-input')), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets('keyboard navigation reveals suggestions below the fold', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/filter.json': []},
      filterOptionsByPath: {
        '/filter.json': [
          for (var i = 0; i < 15; i++)
            TopicFilterOption(name: 'option$i:', priority: 1),
        ],
      },
    );
    await _pump(tester, api);
    await _openFilter(tester);
    await tester.tap(find.byKey(const ValueKey('topic-filter-input')));
    await tester.pumpAndSettle();
    final rows = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith(
            'topic-filter-suggestion-',
          ),
    );
    final count = rows.evaluate().length;
    expect(count, greaterThan(8));
    for (var i = 1; i < count; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    final list = tester.widget<DCommandList<String>>(
      find.byType(DCommandList<String>),
    );
    final last = find.byKey(
      list.children.whereType<DCommandGroup<String>>().last.items.last.key!,
    );
    _expectSelectedRow(tester, last);
    final popup = tester.getRect(find.byType(DCommandList<String>));
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(popup.bottom));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('list number and date pickers retain server syntax', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/filter.json': []},
      filterOptionsByPath: const {
        '/filter.json': [
          TopicFilterOption(name: 'posts-min:', type: 'number'),
          TopicFilterOption(name: 'created-after:', type: 'date'),
        ],
      },
    );
    await _pump(tester, api);
    await _openFilter(tester);
    final input = find.byKey(const ValueKey('topic-filter-input'));
    await tester.enterText(input, 'posts-min:');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('topic-filter-number-posts-min:')),
      '15',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_filterQuery(tester), 'posts-min:15');
    await tester.enterText(input, 'created-after:');
    await tester.pumpAndSettle();
    tester.widget<DDatePicker>(find.byType(DDatePicker)).onChanged!(
      DCalendarDate(2026, 10, 9),
    );
    await tester.pumpAndSettle();
    expect(_filterQuery(tester), 'posts-min:15 created-after:2026-10-09');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('category suggestions use their category badges', (tester) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/filter.json': []},
      filterOptionsByPath: const {
        '/filter.json': [
          TopicFilterOption(name: 'category:', type: 'category', priority: 1),
        ],
      },
      categoryList: const [
        TopicCategory(id: 1, name: 'Product', slug: 'product', color: 'FF0000'),
        TopicCategory(
          id: 2,
          name: 'Feature requests',
          slug: 'feature',
          color: '0088CC',
          parentCategoryId: 1,
        ),
      ],
    );
    await _pump(tester, api);
    await _openFilter(tester);

    final field = find.descendant(
      of: find.byKey(const ValueKey('topic-filter-input')),
      matching: find.byType(TextField),
    );
    await tester.tap(field);
    await tester.enterText(field, 'category:feat');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Product › Feature requests'), findsOneWidget);
    // The category filter trigger carries its own swatch.
    final badge = tester.widget<CategorySquare>(
      find.descendant(
        of: find.byKey(const ValueKey('topic-filter-suggestion-0')),
        matching: find.byType(CategorySquare),
      ),
    );
    expect(badge.color, const Color(0xFF0088CC));
    expect(badge.parentColor, const Color(0xFFFF0000));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

void _expectSelectedRow(WidgetTester tester, Finder row) {
  final command = tester.widget<DCommand<String>>(
    find.byType(DCommand<String>),
  );
  final list = tester.widget<DCommandList<String>>(
    find.byType(DCommandList<String>),
  );
  final items = list.children.whereType<DCommandGroup<String>>().expand(
    (group) => group.items,
  );
  final item = items.singleWhere((item) => item.key == tester.widget(row).key);
  expect(command.value, item.value);
}

void _expectSuggestionSemantics(
  WidgetTester tester,
  Finder row, {
  required String label,
  required bool selected,
}) {
  final semantics = tester.getSemantics(row);
  expect(
    semantics.flagsCollection.isSelected,
    selected ? Tristate.isTrue : Tristate.isFalse,
  );
  final labels = <String>[];
  void visit(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(semantics);
  expect(labels, contains(anyOf(label, startsWith('$label  '))));
}

Future<void> _pump(
  WidgetTester tester,
  FakeDiscourseApi api, {
  bool authenticated = false,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final signedOut = instance('meta.discourse.org');
  final forum = authenticated
      ? signedOut.copyWith(user: const DiscourseUser(id: 7, username: 'reader'))
      : signedOut;
  final authenticator = FakeAuthenticator();
  if (authenticated) authenticator.keys[forum.url] = 'api-key';
  await tester.pumpWidget(
    DiscourseApp(
      store: FakeInstanceStore([forum]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openFilter(WidgetTester tester, {bool settle = true}) async {
  await tester.tap(
    find.descendant(
      of: primaryMainContent,
      matching: find.byKey(const ValueKey('topic-list-filter')),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (
      var attempt = 0;
      attempt < 10 &&
          find
              .descendant(
                of: find.byKey(const ValueKey('topic-filter-input')),
                matching: find.byType(TextField),
              )
              .evaluate()
              .isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

String _filterQuery(WidgetTester tester) {
  final tokens = tester
      .widgetList<DTooltip>(
        find.descendant(
          of: find.byKey(const ValueKey('topic-filter-token-field')),
          matching: find.byType(DTooltip),
        ),
      )
      .where((tooltip) => tooltip.child is Row)
      .map((tooltip) => tooltip.message);
  final draft = tester
      .widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('topic-filter-input')),
          matching: find.byType(TextField),
        ),
      )
      .controller!
      .text
      .trim();
  return [...tokens, if (draft.isNotEmpty) draft].join(' ');
}
