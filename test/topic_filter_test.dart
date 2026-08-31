import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_filter_controller.dart';
import 'package:discourse_native/src/shell/topic_filter_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
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

  testWidgets(
    'the sidebar Filter destination submits and clears a native feed',
    (tester) async {
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
          matching: find.text('More'),
        ),
        findsOneWidget,
      );
      await _openFilter(tester);

      expect(find.byType(TopicFilterPage), findsOneWidget);
      expect(api.feedPaths, contains('/filter.json'));
      expect(find.text('Every topic'), findsOneWidget);

      final field = find.byKey(const ValueKey('topic-filter-input'));
      await tester.enterText(field, 'status:open');
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        api.feedPaths.where((path) => path.startsWith('/filter.json')),
        hasLength(1),
        reason: 'typing only updates suggestions',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(api.feedPaths, contains('/filter.json?q=status%3Aopen'));
      expect(find.text('Only open topics'), findsOneWidget);

      await tester.tap(find.text('Topics'));
      await tester.pumpAndSettle();
      await _openFilter(tester);
      expect(
        tester.widget<TextField>(field).controller!.text,
        'status:open',
        reason: 'the submitted query belongs to this site and destination',
      );

      await tester.tap(find.byKey(const ValueKey('clear-topic-filter')));
      await tester.pumpAndSettle();
      expect(
        api.feedPaths.where((path) => path == '/filter.json'),
        hasLength(2),
      );
      expect(find.text('Every topic'), findsOneWidget);
    },
  );

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

    final field = find.byKey(const ValueKey('topic-filter-input'));
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
    expect(tester.widget<TextField>(field).controller!.text, 'tag:bug');
    expect(api.feedPaths, ['/latest.json', '/filter.json']);
  });

  testWidgets('the filter page keeps its field over a topic-row skeleton', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/filter.json': []},
      feedGates: {'/filter.json': gate},
    );

    await _pump(tester, api);
    final semantics = tester.ensureSemantics();
    await _openFilter(tester, settle: false);

    expect(find.byKey(const ValueKey('topic-filter-input')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-list-loading-skeleton')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Loading filtered topics'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('topic-list-loading-skeleton')),
      findsNothing,
    );
    semantics.dispose();
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

        final field = find.byKey(const ValueKey('topic-filter-input'));
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
        _expectSelectedRow(tester, secondRow);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller!.text, 'tag:');
        expect(api.feedPaths, ['/latest.json', '/filter.json']);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('enter accepts the first filter suggestion', (tester) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/filter.json': []},
      filterOptionsByPath: const {
        '/filter.json': [_tagOption],
      },
    );
    await _pump(tester, api);
    await _openFilter(tester);

    final field = find.byKey(const ValueKey('topic-filter-input'));
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(field).controller!.text, 'tag:');
    expect(api.feedPaths, ['/latest.json', '/filter.json']);
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

    final field = find.byKey(const ValueKey('topic-filter-input'));
    await tester.tap(field);
    await tester.enterText(field, 'category:feat');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Feature requests'), findsOneWidget);
    final badge = tester.widget<CategorySquare>(find.byType(CategorySquare));
    expect(badge.color, const Color(0xFF0088CC));
    expect(badge.parentColor, const Color(0xFFFF0000));
  });
}

void _expectSelectedRow(WidgetTester tester, Finder row) {
  final theme = Theme.of(tester.element(row));
  final decoration = tester.widget<Container>(row).decoration! as BoxDecoration;
  final border = decoration.border! as Border;
  expect(decoration.color, theme.shell.selected);
  expect(border.left.color, theme.colorScheme.primary);
  expect(border.left.width, 3);
}

void _expectSuggestionSemantics(
  WidgetTester tester,
  Finder row, {
  required String label,
  required bool selected,
}) {
  expect(
    tester.getSemantics(row),
    isSemantics(
      label: label,
      isButton: true,
      hasSelectedState: true,
      isSelected: selected,
      hasTapAction: true,
    ),
  );
}

Future<void> _pump(WidgetTester tester, FakeDiscourseApi api) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    DiscourseApp(
      store: FakeInstanceStore([instance('meta.discourse.org')]),
      api: api,
      authenticator: FakeAuthenticator(),
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
  await tester.tap(find.text('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Filter'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (
      var attempt = 0;
      attempt < 10 &&
          find.byKey(const ValueKey('topic-filter-input')).evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}
