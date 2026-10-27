import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/topic_filter_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sidebar_filter_parity_test.dart' as fixture;
import 'support/shell_test_harness.dart' show phone;

const vocabulary = fixture.filterMenuOptions;

TopicFilterSuggestions engine({
  String? field,
  List<TopicFilterOption> options = vocabulary,
  bool calendar = false,
}) => TopicFilterSuggestions(
  options: options,
  allOptions: true,
  menuField: field,
  menuDateSelected: calendar,
  categories: const [],
  categoryLookup: (_) async => [],
  tags: (_) async => const [
    TopicFilterLookupValue(name: 'Alpha', description: '10'),
  ],
  tagGroups: (_) async => const [TopicFilterLookupValue(name: 'Design team')],
  users: (_) async => [],
  groups: (_) async => [],
);

void main() {
  test(
    'opening menu follows reference order and omits unsupported search filters',
    () async {
      final rows = await engine(
        options: [
          ...vocabulary,
          const TopicFilterOption(name: 'likes-min:', type: 'number'),
          const TopicFilterOption(name: 'latest-post-after:', type: 'date'),
        ],
      ).suggestions('');
      expect(rows.map((r) => r.displayName), [
        'Category',
        'Tags',
        'Topic',
        'Posted by',
        'Started by',
        'Author’s group',
        'Assigned to',
        'Status',
        'Post type',
        'Language',
        'Posted',
        'Replies',
        'Views',
        'Votes',
        'My activity',
        'Sort',
      ]);
      expect(rows.map((r) => r.menuGroup).toSet(), [
        'Where',
        'Who',
        'State',
        'Content',
        'Numbers & dates',
        'Mine',
        'Staff',
      ]);
      expect(
        rows.any(
          (r) =>
              r.name.contains('badge') ||
              r.name.contains('match:') ||
              r.name.contains('filetype') ||
              r.name.contains('with:'),
        ),
        isFalse,
      );
      expect(
        (await engine().suggestions('started')).single.name,
        'created-by:',
      );
      expect((await engine().suggestions('votes')).map((r) => r.menuField), [
        'votes',
        'order',
      ]);
    },
  );

  test('permissions and plugins follow the advertised vocabulary', () async {
    final limited = vocabulary
        .where(
          (o) =>
              !o.name.startsWith('assigned:') &&
              !o.name.startsWith('votes-') &&
              !o.name.startsWith('in:') &&
              !o.name.startsWith('order:votes'),
        )
        .toList();
    final rows = await engine(options: limited).suggestions('');
    expect(
      rows.any(
        (r) =>
            {'assigned', 'votes', 'activity', 'postType'}.contains(r.menuField),
      ),
      isFalse,
    );
    final status = await engine(field: 'status').suggestions('status:');
    expect(status.map((r) => r.name), [
      'status:open',
      'status:closed',
      'status:solved',
    ]);
    expect(
      (await engine(field: 'postType').suggestions('in:')).map((r) => r.name),
      ['in:pinned'],
    );
    expect(
      (await engine(field: 'activity').suggestions('in:')).map((r) => r.name),
      ['in:watching', 'in:bookmarked'],
    );
  });

  test(
    'reply comparisons account for the opening post and exact count uses both bounds',
    () async {
      final rows = await engine(field: 'replies').suggestions('posts-min:10');
      expect(rows.map((r) => r.displayName), [
        'At least 10',
        'At most 10',
        'Exactly 10',
      ]);
      expect(rows.map((r) => r.name), [
        'posts-min:11',
        'posts-max:11',
        'posts-min:11 posts-max:11',
      ]);
      expect(
        (await engine(
          field: 'views',
        ).suggestions('views-min:10')).map((r) => r.name),
        ['views-min:10', 'views-max:10'],
      );
      expect(
        (await engine(field: 'votes').suggestions('votes-min:10')).last.name,
        'votes-min:10 votes-max:10',
      );
    },
  );

  test(
    'date and tag choices use only supported clauses and real lookup values',
    () async {
      final dates = await engine(field: 'posted').suggestions('created-after:');
      expect(dates.map((r) => r.name), [
        'created-before:',
        'created-after:',
        'created-after:7',
        'created-after:30',
        'created-after:365',
      ]);
      expect(
        await engine(
          field: 'posted',
          calendar: true,
        ).suggestions('created-before:'),
        isEmpty,
      );
      final tags = await engine(field: 'tags').suggestions('tag:');
      expect(tags.map((r) => r.name), [
        'tag:Alpha',
        'tag-group:"Design team"',
        'in:untagged',
      ]);
      expect(tags.map((r) => r.menuGroup), ['Tags', 'Tag groups', 'Other']);
    },
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });

  setUpAll(() async {
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets(
      'named filters stage comparisons and apply native clauses on $platform',
      (tester) async {
        final data = await fixture.fixture(
          tester,
          size: phone,
          filterOptions: vocabulary,
        );
        await fixture.openFilters(tester);
        await fixture.capture(tester, 'filter-content-$platform-root');
        if (platform == TargetPlatform.iOS) {
          await tester.tap(find.byKey(const ValueKey('sheet-drag-handle')));
          await tester.pumpAndSettle();
        }
        await tester.enterText(fixture.field, 'replies');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Replies  How many replies a topic has'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('topic-filter-number-posts-min:')),
          '10',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Exactly 10'));
        await tester.pumpAndSettle();
        expect(find.text('Apply 1 filter'), findsOneWidget);
        await tester.tap(find.text('Apply 1 filter'));
        await tester.pumpAndSettle();
        expect(
          Uri.parse(
            data.shell.topicListContent!.feedPath!,
          ).queryParameters['q'],
          'posts-min:11 posts-max:11',
        );
        final filters = find.byKey(const ValueKey('topic-list-filter'));
        if (platform == TargetPlatform.iOS) {
          // A phone's row is short of room, so the pill shows its count
          // and keeps its full name for a screen reader.
          expect(
            find.descendant(of: filters, matching: find.text('1')),
            findsOneWidget,
          );
          expect(tester.widget<DButton>(filters).semanticLabel, 'Filters · 1');
        } else {
          expect(
            find.descendant(of: filters, matching: find.text('Filters · 1')),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('Posted stages a relation before showing the inline calendar', (
    tester,
  ) async {
    final data = await fixture.fixture(tester, filterOptions: vocabulary);
    await fixture.openFilters(tester);
    await tester.enterText(fixture.field, 'posted');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Posted  Before or after a day'));
    await tester.pumpAndSettle();
    expect(find.byType(DCalendar), findsNothing);
    await tester.tap(find.text('Before'));
    await tester.pumpAndSettle();
    expect(find.text('No results found'), findsNothing);
    tester.widget<DCalendar>(find.byType(DCalendar)).onSelectionChanged!(
      DCalendarSingleSelection(DCalendarDate(2026, 10, 14)),
      DCalendarSelectReason.press,
    );
    await tester.pumpAndSettle();
    expect(find.text('Apply 1 filter'), findsOneWidget);
    await tester.tap(find.text('Apply 1 filter'));
    await tester.pumpAndSettle();
    expect(
      Uri.parse(data.shell.topicListContent!.feedPath!).queryParameters['q'],
      'created-before:2026-10-14',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('tag choices stay staged while all four matching modes change', (
    tester,
  ) async {
    final data = await fixture.fixture(tester, filterOptions: vocabulary);
    await fixture.openFilters(tester);
    await tester.enterText(fixture.field, 'tags');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tags  Topics by their tags, or a tag group'));
    await tester.pumpAndSettle();
    final done = find.byKey(const ValueKey('topic-filter-done-tags'));
    expect(
      tester
          .widget<DCommandList<String>>(find.byType(DCommandList<String>))
          .children
          .whereType<DCommandItem<String>>()
          .firstWhere((row) => row.value == '@done-tags')
          .enabled,
      isFalse,
    );
    for (final tag in ['Alpha', 'Beta']) {
      await tester.tap(
        find.descendant(
          of: find.byType(DCommandList<String>),
          matching: find.text(tag),
        ),
      );
      await tester.pumpAndSettle();
    }
    for (final (label, chip) in [
      ('All', 'All Alpha, Beta'),
      ('None', 'None Alpha, Beta'),
      ('Any', 'Any Alpha, Beta'),
      ('Not all', 'Not all Alpha, Beta'),
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text('Tags: $chip'), findsOneWidget);
    }
    Focus.of(tester.element(find.text('Any'))).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Tags: Any Alpha, Beta'), findsOneWidget);
    await tester.tap(find.text('Not all'));
    await tester.pumpAndSettle();
    expect(
      data.shell.topicListContent?.topicFilterQuery,
      isNot(contains('Alpha')),
    );
    await tester.tap(done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply 1 filter'));
    await tester.pumpAndSettle();
    expect(
      Uri.parse(data.shell.topicListContent!.feedPath!).queryParameters['q'],
      '-tag:Alpha+Beta',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
