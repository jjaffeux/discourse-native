import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_filter_controller.dart';
import 'package:discourse_native/src/shell/topic_list_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

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

    expect(find.byType(TopicListFilterMenu), findsOneWidget);
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

    await tester.tap(find.text('Apply filter'));
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
  });

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

    expect(find.text('tag:bug'), findsOneWidget);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('tag:bug')),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_filterQuery(tester), 'tag:bug');
    expect(find.text('tag: bug'), findsOneWidget);
    expect(api.feedPaths, ['/latest.json', '/filter.json']);
  });

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
  });

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
    await tester.tap(find.text('Unanswered'));
    await tester.pump();
    expect(_filterQuery(tester), 'status:noreplies');
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(DProgress), findsNothing);
  });

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
          const ValueKey('topic-filter-suggestion-0'),
        );
        final secondRow = find.byKey(
          const ValueKey('topic-filter-suggestion-1'),
        );
        expect(tester.getSize(firstRow).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(secondRow).height, greaterThanOrEqualTo(44));
        expect(
          find.descendant(of: firstRow, matching: find.byType(DIcon)),
          findsNothing,
        );
        expect(
          find.descendant(of: secondRow, matching: find.byType(DIcon)),
          findsNothing,
        );
        _expectSelectedRow(tester, firstRow);
        _expectSuggestionSemantics(
          tester,
          firstRow,
          label: 'status:',
          selected: true,
        );
        _expectSuggestionSemantics(
          tester,
          secondRow,
          label: 'tag:\nTopics carrying a tag',
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
          label: 'status:',
          selected: true,
        );
        _expectSuggestionSemantics(
          tester,
          secondRow,
          label: 'tag:\nTopics carrying a tag',
          selected: false,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        _expectSelectedRow(tester, secondRow);
        _expectSuggestionSemantics(
          tester,
          firstRow,
          label: 'status:',
          selected: false,
        );
        _expectSuggestionSemantics(
          tester,
          secondRow,
          label: 'tag:\nTopics carrying a tag',
          selected: true,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        _expectSelectedRow(tester, firstRow);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        _expectSelectedRow(tester, firstRow);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        _expectSelectedRow(tester, secondRow);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller!.text, 'tag:');
        expect(api.feedPaths, ['/latest.json', '/filter.json']);
      } finally {
        semantics.dispose();
      }
    },
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
    final shell = ShellScope.read(
      tester.element(find.byType(TopicListFilterMenu)),
    );
    final apply = tester
        .widget<DButton>(
          find.ancestor(
            of: find.text('Apply filter'),
            matching: find.byType(DButton),
          ),
        )
        .onPressed!;
    unawaited(shell.selectTopicListMode(TopicListMode.topWeekly));
    final replacement = shell.topicListContent;
    apply();
    await tester.pumpAndSettle();
    expect(shell.topicListContent, replacement);
    expect(find.text('Apply filter'), findsNothing);
  });

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

    expect(tester.widget<TextField>(field).controller!.text, 'tag:');
    expect(api.feedPaths, ['/latest.json', '/filter.json']);
  });

  testWidgets('multiline filter keeps editing separate from submission', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/filter.json': []},
    );
    await _pump(tester, api);
    await _openFilter(tester);
    final textarea = find.byType(DInputGroupTextarea);
    final field = find.descendant(
      of: textarea,
      matching: find.byType(TextField),
    );
    expect(
      tester.widget<TextField>(field).textInputAction,
      TextInputAction.newline,
    );
    expect(tester.widget<TextField>(field).minLines, 3);
    await tester.enterText(field, 'status:open\ntag:feedback');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Apply filter'), findsOneWidget);
    expect(api.feedPaths, ['/latest.json', '/filter.json']);
    expect(_filterQuery(tester), 'status:open tag:feedback');
    final apply = tester.getRect(
      find.ancestor(
        of: find.text('Apply filter'),
        matching: find.byType(DButton),
      ),
    );
    expect(apply.right, closeTo(tester.getRect(textarea).right, 1));
    expect(
      apply.top,
      greaterThan(tester.getRect(find.text('Tracking')).bottom),
    );
    final expectedClauses = ['status:open', 'tag:feedback'];
    for (final (label, query) in [
      ('New topics', 'in:new-topics'),
      ('Unseen', 'in:unseen'),
      ('Watching', 'in:watching'),
      ('Tracking', 'in:tracking'),
      ('Closed topics', 'status:closed'),
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expectedClauses.add(query);
      expect(_filterQuery(tester), expectedClauses.join(' '));
      expect(api.feedPaths, ['/latest.json', '/filter.json']);
    }
    final chips = find.byType(DBadge);
    final first = tester.getRect(chips.first);
    final last = tester.getRect(chips.last);
    expect(last.top, greaterThan(first.top));
    final surface = tester.getRect(
      find.ancestor(of: textarea, matching: find.byType(DInputGroup)),
    );
    expect(surface.contains(first.topLeft), isTrue);
    expect(surface.contains(last.bottomRight), isTrue);
    await tester.ensureVisible(find.text('Apply filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filter'));
    await tester.pumpAndSettle();
    expect(
      api.feedPaths,
      contains(
        '/filter.json?q=${Uri.encodeQueryComponent(expectedClauses.join(' '))}',
      ),
    );
  });

  testWidgets('quick filters toggle exact clauses and follow manual edits', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/filter.json': []},
    );
    await _pump(tester, api);
    await _openFilter(tester);
    final textarea = find.byType(DInputGroupTextarea);
    DToggle toggle(String label) => tester.widget<DToggle>(
      find.ancestor(of: find.text(label), matching: find.byType(DToggle)),
    );
    String draft() => _filterQuery(tester);

    await tester.enterText(
      textarea,
      'tag:"customer feedback"\n"status:open"\n-status:open',
    );
    await tester.pumpAndSettle();
    expect(toggle('Open topics').pressed, isFalse);
    await tester.tap(find.text('Open topics'));
    await tester.pumpAndSettle();
    expect(toggle('Open topics').pressed, isTrue);
    expect(
      draft(),
      'tag:"customer feedback" "status:open" -status:open status:open',
    );
    await tester.tap(find.text('Bookmarked'));
    await tester.pumpAndSettle();
    expect(toggle('Open topics').pressed, isTrue);
    expect(toggle('Bookmarked').pressed, isTrue);
    expect(
      find.descendant(
        of: find.widgetWithText(DToggle, 'Bookmarked'),
        matching: find.byType(DIcon),
      ),
      findsOneWidget,
    );
    expect(draft(), endsWith('status:open in:bookmarked'));
    await tester.tap(find.text('Open topics'));
    await tester.pumpAndSettle();
    expect(toggle('Open topics').pressed, isFalse);
    expect(toggle('Bookmarked').pressed, isTrue);
    expect(
      find.descendant(
        of: find.widgetWithText(DToggle, 'Bookmarked'),
        matching: find.byType(DIcon),
      ),
      findsOneWidget,
    );
    expect(
      draft(),
      'tag:"customer feedback" "status:open" -status:open in:bookmarked',
    );

    for (var i = 0; i < 4; i++) {
      await tester.tap(
        find.byKey(const ValueKey('topic-filter-token-remove-0')),
      );
      await tester.pumpAndSettle();
    }
    expect(toggle('Bookmarked').pressed, isFalse);
    await tester.enterText(textarea, 'status:open status:open tag:feedback');
    await tester.pumpAndSettle();
    expect(toggle('Open topics').pressed, isTrue);
    expect(toggle('Bookmarked').pressed, isFalse);
    await tester.tap(find.text('Open topics'));
    await tester.pumpAndSettle();
    expect(draft(), 'tag:feedback');
    expect(toggle('Open topics').pressed, isFalse);
    expect(api.feedPaths, ['/latest.json', '/filter.json']);
    await tester.tap(find.text('Bookmarked'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filter'));
    await tester.pumpAndSettle();
    expect(
      api.feedPaths,
      contains('/filter.json?q=tag%3Afeedback+in%3Abookmarked'),
    );
  });

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
      await tester.enterText(find.byType(DInputGroupTextarea), 'tag');
      await tester.pumpAndSettle();
      expect(find.text('tag:'), findsOneWidget);
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(api.feedPaths, contains('/filter.json?q=tag'));
      expect(find.byType(DInputGroupTextarea), findsNothing);
    });
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
    await tester.tap(find.byType(DInputGroupTextarea));
    await tester.pumpAndSettle();
    final rows = find.byType(DComboboxItem<TopicFilterSuggestion>);
    final count = rows.evaluate().length;
    expect(count, greaterThan(8));
    for (var i = 1; i < count; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    final last = find.byKey(ValueKey('topic-filter-suggestion-${count - 1}'));
    _expectSelectedRow(tester, last);
    final popup = tester.getRect(find.byType(DComboboxContent));
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(popup.bottom));
  });

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
    final badge = tester.widget<CategorySquare>(find.byType(CategorySquare));
    expect(badge.color, const Color(0xFF0088CC));
    expect(badge.parentColor, const Color(0xFFFF0000));
  });
}

void _expectSelectedRow(WidgetTester tester, Finder row) {
  final combo = tester.widget<DCombobox<TopicFilterSuggestion>>(
    find.byType(DCombobox<TopicFilterSuggestion>),
  );
  final item = tester.widget<DComboboxItem<TopicFilterSuggestion>>(row);
  expect(combo.highlightedValue?.name, item.option.value.name);
}

void _expectSuggestionSemantics(
  WidgetTester tester,
  Finder row, {
  required String label,
  required bool selected,
}) {
  final combo = tester.widget<DCombobox<TopicFilterSuggestion>>(
    find.byType(DCombobox<TopicFilterSuggestion>),
  );
  final item = tester.widget<DComboboxItem<TopicFilterSuggestion>>(row);
  expect(combo.highlightedValue?.name == item.option.value.name, selected);
  expect(item.option.label, contains(label.split('\n').first));
}

Future<void> _pump(
  WidgetTester tester,
  FakeDiscourseApi api, {
  bool authenticated = false,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final forum = instance('meta.discourse.org');
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
  await tester.tap(find.byKey(const ValueKey('topic-list-filter')));
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
      .widgetList<DTooltip>(find.byType(DTooltip))
      .where((tooltip) => tooltip.child is DBadge)
      .map((tooltip) => tooltip.message);
  final draft = tester
      .widget<DTextarea>(find.byType(DInputGroupTextarea))
      .controller!
      .text
      .trim();
  return [...tokens, if (draft.isNotEmpty) draft].join(' ');
}
