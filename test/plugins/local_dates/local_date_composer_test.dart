import 'package:discourse_native/src/plugins/local_dates/local_date_composer_editor.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_pill.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_plugin.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_pill.dart';
import 'package:discourse_native/src/plugins/poll/poll_plugin.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  final environment = LocalDateEnvironment.instance;

  setUpAll(() async {
    environment.ensureDatabase();
    environment.setDeviceTimezone('Etc/UTC');
    await initializeDateFormatting('en');
  });

  group('lossless codec', () {
    test('retains quoted unknown attributes, source ranges, and order', () {
      const source =
          'before [DaTe=2026-08-09  future = “two ] words” '
          "timezone = 'UTC' format=\"YYYY [at] HH:mm\"   ] after";
      final block = parseLocalDateComposerBlocks(
        source,
        environment: environment,
      ).single;

      expect(block.start, source.indexOf('[DaTe'));
      expect(block.source, source.substring(block.start, block.end));
      expect(block.attribute('future'), 'two ] words');
      expect(block.attribute('TIMEZONE'), 'UTC');
      expect(block.attributes.map((attribute) => attribute.name), [
        'date',
        'future',
        'timezone',
        'format',
      ]);
      expect(LocalDateComposerDraft.fromBlock(block).serialize(), block.source);
    });

    test('finds multiple inline dates but excludes inline and fenced code', () {
      const source =
          '[date=2026-01-01] `x [date=2026-02-02]` '
          '[date-range from=2026-03-01T09:00:00 to=2026-03-01T10:00:00]\n'
          '```\n[date=2026-04-04]\n```';
      final blocks = parseLocalDateComposerBlocks(
        source,
        environment: environment,
      );

      expect(blocks, hasLength(2));
      expect(blocks.first.kind, LocalDateComposerKind.date);
      expect(blocks.last.kind, LocalDateComposerKind.range);
    });

    test('scans many interleaved code ranges in one forward pass', () {
      const count = 2500;
      const visible = '[date=2026-01-01 timezone=UTC]';
      final source = StringBuffer();
      for (var index = 0; index < count; index++) {
        source
          ..write('`[date=2025-12-31]` ')
          ..write(visible)
          ..writeln();
      }
      final document = source.toString();

      final blocks = parseLocalDateComposerBlocks(
        document,
        environment: environment,
      );

      expect(blocks, hasLength(count));
      expect(blocks.every((block) => block.source == visible), isTrue);
      expect(
        blocks.map((block) => document.substring(block.start, block.end)),
        everyElement(visible),
      );
    });

    test('leaves malformed timezone markup raw', () {
      const source =
          '[date=2026-01-01 timezone=Future/Mars] '
          '[date=2026-01-02 displayedTimezone=Invalid/Zone]';

      expect(
        parseLocalDateComposerBlocks(source, environment: environment),
        isEmpty,
      );
    });

    test('accepts the ASCII attribute-name and recurrence grammar', () {
      const source = '[date=2024-02-29 _future-2=value recurring=12.quarters]';

      final block = parseLocalDateComposerBlocks(
        source,
        environment: environment,
      ).single;

      expect(block.attribute('_future-2'), 'value');
      expect(block.attribute('recurring'), '12.quarters');
    });

    test('rejects invalid attribute names, dates, times, and recurrences', () {
      const invalid = [
        '[date=2026-01-01 2future=value]',
        '[date=2026-01-01 -future=value]',
        '[date=2026-01-01 füture=value]',
        '[date=2023-02-29]',
        '[date=2026-01-01 recurring=0.days]',
        '[date=2026-01-01 recurring=1.century]',
        '[date-range from=2026-01-01T24:00 to=2026-01-02T01:00]',
        '[date-range from=2026-01-01T23:60 to=2026-01-02T01:00]',
        '[date-range from=2026-01-01T23:59:60 to=2026-01-02T01:00]',
      ];

      for (final source in invalid) {
        expect(
          parseLocalDateComposerBlocks(source, environment: environment),
          isEmpty,
          reason: source,
        );
      }
    });

    test('an edit preserves unknown syntax and changes only known values', () {
      const source =
          '[date=2026-08-09 future = “keep ] me” timezone = \'UTC\'   ]';
      final draft = LocalDateComposerDraft.fromBlock(
        parseLocalDateComposerBlocks(source, environment: environment).single,
      ).copyWith(countdown: true);

      expect(
        draft.serialize(),
        '[date=2026-08-09 future = “keep ] me” timezone = \'UTC\' '
        'countdown=true   ]',
      );
    });

    test('creates canonical single dates and ranges', () {
      final single = LocalDateComposerDraft.newDate(
        now: DateTime(2026, 8, 9),
        timezone: 'Europe/Paris',
        environment: environment,
      ).copyWith(startTime: '09:30:00');
      final range = single.copyWith(endDate: '2026-08-09', endTime: '10:30:00');

      expect(
        single.serialize(),
        '[date=2026-08-09 time=09:30:00 timezone=Europe/Paris]',
      );
      expect(
        range.serialize(),
        '[date-range from=2026-08-09T09:30:00 '
        'to=2026-08-09T10:30:00 timezone=Europe/Paris]',
      );
    });

    test('validates DST gaps and range ordering in the source zone', () {
      final base = LocalDateComposerDraft.newDate(
        now: DateTime(2024, 3, 10),
        timezone: 'America/New_York',
        environment: environment,
      ).copyWith(startTime: '02:30:00');
      expect(base.validate().firstError, contains('does not exist'));

      final backwards = base.copyWith(
        startTime: '04:00:00',
        endDate: '2024-03-10',
        endTime: '03:00:00',
      );
      expect(
        backwards.validate().errors,
        contains('The end must be after the start.'),
      );
    });

    test('stale replacement and removal abort without moving the caret', () {
      const source = 'A [date=2026-08-09 timezone=UTC] B';
      final block = parseLocalDateComposerBlocks(
        source,
        environment: environment,
      ).single;
      const changed = TextEditingValue(
        text: '$source!',
        selection: TextSelection.collapsed(offset: 1),
      );

      final replace = replaceVerifiedLocalDate(
        current: changed,
        expectedDocument: source,
        expectedBlock: block,
        replacement: '[date=2027-01-01 timezone=UTC]',
      );
      final remove = removeVerifiedLocalDate(
        current: changed,
        expectedDocument: source,
        expectedBlock: block,
      );
      expect(replace.applied, isFalse);
      expect(remove.applied, isFalse);
      expect(replace.value, changed);
      expect(remove.value, changed);
    });

    test('verified insertion replaces selection and preserves caret', () {
      const current = TextEditingValue(
        text: 'before after',
        selection: TextSelection(baseOffset: 7, extentOffset: 12),
      );
      const markup = '[date=2026-08-09 timezone=UTC]';
      final result = insertVerifiedLocalDate(
        current: current,
        expectedDocument: current.text,
        expectedSelection: current.selection,
        markup: markup,
      );

      expect(result.value.text, 'before $markup');
      expect(result.value.selection.extentOffset, 7 + markup.length);
    });
  });

  group('pill projection', () {
    const date = '[date=2026-08-09 time=09:00:00 timezone=UTC calendar=off]';

    testWidgets('retains exact projected length and reveals for caret or IME', (
      tester,
    ) async {
      final controller = MarkdownEditingController(
        text: date,
        syntaxPolicies: [
          LocalDateComposerSyntaxPolicy(environment: environment),
          const PollComposerSyntaxPolicy(),
        ],
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: TextField(controller: controller)),
        ),
      );

      expect(find.byType(LocalDateComposerPill), findsOneWidget);
      final span = controller.buildTextSpan(
        context: tester.element(find.byType(TextField)),
        style: const TextStyle(fontSize: 15),
        withComposing: true,
      );
      expect(
        span.toPlainText(includeSemanticsLabels: false).length,
        date.length,
      );
      expect(controller.text, date);

      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(find.byType(LocalDateComposerPill), findsOneWidget);
      expect(
        tester
            .widget<LocalDateComposerPill>(find.byType(LocalDateComposerPill))
            .highlighted,
        isFalse,
      );

      controller.selectPillForKeyboard(controller.syntaxBlocks.single);
      await tester.pump();
      expect(
        tester
            .widget<LocalDateComposerPill>(find.byType(LocalDateComposerPill))
            .highlighted,
        isTrue,
      );
      controller.clearKeyboardPillSelection();

      controller.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();
      expect(find.byType(LocalDateComposerPill), findsNothing);

      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: date.length),
        composing: const TextRange(start: 2, end: 8),
      );
      await tester.pump();
      expect(find.byType(LocalDateComposerPill), findsNothing);
    });

    testWidgets('date and Poll pills coexist without changing source', (
      tester,
    ) async {
      const poll = '[poll]\n* A\n* B\n[/poll]';
      const source = '$date\n\n$poll';
      final controller = MarkdownEditingController(
        text: source,
        syntaxPolicies: [
          LocalDateComposerSyntaxPolicy(environment: environment),
          const PollComposerSyntaxPolicy(),
        ],
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: TextField(controller: controller, maxLines: null),
          ),
        ),
      );

      expect(find.byType(LocalDateComposerPill), findsOneWidget);
      expect(find.byType(PollComposerPill), findsOneWidget);
      expect(controller.text, source);

      final projected = controller.localDateBlocks.single;
      expect(
        controller.collapsedLocalDateAtOffset(projected.end - 1),
        same(projected),
      );
      expect(controller.collapsedLocalDateAtOffset(projected.start), isNull);
      expect(controller.collapsedLocalDateAtOffset(projected.end), isNull);
    });
  });
}
