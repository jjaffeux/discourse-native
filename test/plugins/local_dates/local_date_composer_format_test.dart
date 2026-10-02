import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_editor.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_parser.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_sheet.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_plugin.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:intl/date_symbol_data_local.dart';

import '../../support/fake_composer_editor_host.dart';

void main() {
  final environment = LocalDateEnvironment.instance;
  const format = '''[It's "party" time] YYYY-MM-DD''';
  final policy = LocalDateComposerSyntaxPolicy(
    environment: environment,
    accountTimezone: 'Etc/UTC',
    settings: const LocalDatesSettings(enabled: true),
  );

  setUpAll(() async {
    environment.ensureDatabase();
    environment.setDeviceTimezone('Etc/UTC');
    await initializeDateFormatting('en');
  });

  test('new quote delimiters preserve format through actual cooking', () async {
    final cooking = OfflineCookingService();
    addTearDown(cooking.dispose);
    const cookedFormat = """YYYY-MM-DD '"'""";
    final draft = LocalDateComposerDraft.newDate(
      now: DateTime(2026, 8, 9),
      timezone: 'Etc/UTC',
      environment: environment,
    ).copyWith(format: cookedFormat);
    final result = await cooking.cook(
      CookingRequest(
        raw: draft.serialize(),
        configuration: CookingConfiguration(
          modules: [
            CookingModule(
              id: 'discourse-local-dates',
              owner: 'discourse-local-dates',
              version: '1',
            ),
          ],
        ),
        snapshot: CookingSnapshot(
          siteId: 'test-site',
          accountId: 'test-account',
          pluginContext: {
            'discourse-local-dates': {
              'settings': {'discourse_local_dates_enabled': true},
            },
          },
        ),
      ),
    );
    expect(result.failure, isNull);
    final date = html
        .parseFragment(result.html)
        .querySelector('span.discourse-local-date');
    expect(date, isNotNull, reason: result.html);
    expect(date!.text, """2026-08-09 '"'""");
  });

  test('all supported styles render safely and preserve untouched source', () {
    for (final (open, close) in [
      ('"', '"'),
      ("'", "'"),
      ('“', '”'),
      ('‘', '’'),
    ]) {
      final source =
          '[DaTe=2026-08-09 timezone = UTC format = ${open}LL$close  ]';
      final block = parseLocalDateComposerBlocks(
        source,
        environment: environment,
      ).single;
      final unchanged = LocalDateComposerDraft.fromBlock(block);
      expect(unchanged.serialize(), source);
      expect(unchanged.validate().isValid, isTrue);
      for (final value in [format, '''[It's "party" ”time”] YYYY-MM-DD''']) {
        for (final range in [false, true]) {
          final edited = unchanged.copyWith(
            format: value,
            endDate: range ? '2026-08-10' : null,
          );
          expect(edited.validate().isValid, isTrue);
          final serialized = edited.serialize();
          final result = parseLocalDateComposerBlocks(
            serialized,
            environment: environment,
          ).single;
          expect(result.attribute('format'), value);
          if (!range) {
            expect(
              serialized,
              startsWith('[DaTe=2026-08-09 timezone = UTC format = '),
            );
            expect(serialized, endsWith('  ]'));
          }
        }
      }
      final simple = unchanged.copyWith(format: 'YYYY');
      expect(
        simple.serialize(),
        source.replaceFirst('${open}LL$close', '${open}YYYY$close'),
      );
    }
  });

  test('validation rejects new formats that cannot be represented safely', () {
    final draft = LocalDateComposerDraft.newDate(
      now: DateTime(2026, 8, 9),
      timezone: 'Etc/UTC',
      environment: environment,
    );
    for (final value in [
      '''[It's "party" ”time” ’now’]''',
      'YYYY\nMM',
      'YYYY\rMM',
    ]) {
      expect(draft.copyWith(format: value).validate().isValid, isFalse);
    }
  });

  for (final editing in [false, true]) {
    testWidgets('invalid format stays editable before apply: edit=$editing', (
      tester,
    ) async {
      const original = '[date=2026-08-09 timezone=UTC format="LL"]';
      final editor = FakeComposerEditorHost(
        TextEditingValue(
          text: editing ? original : '',
          selection: const TextSelection.collapsed(offset: 0),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
          home: const Scaffold(),
        ),
      );
      final pending = openLocalDateComposer(
        tester.element(find.byType(Scaffold)),
        editor,
        policy,
        block: editing
            ? parseLocalDateComposerBlocks(
                original,
                environment: environment,
              ).single
            : null,
      );
      await tester.pumpAndSettle();
      final options = find.text('Display options');
      await tester.ensureVisible(options);
      await tester.tap(options);
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is DInput && widget.labelText == 'Moment format (optional)',
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, '''[It's "party" ”time” ’now’]''');
      final apply = find.widgetWithText(DButton, 'Apply');
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();

      expect(find.byType(LocalDateComposerSheet), findsOneWidget);
      final error = tester.widget<Text>(
        find.byKey(const ValueKey('local-date-sheet-error')),
      );
      expect(
        error.data,
        'Remove line breaks or at least one quotation mark type from the format.',
      );
      expect(editor.commitCalls, 0);
      expect(editor.value.text, editing ? original : '');
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(field);
      await tester.enterText(field, format);
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      await pending;
      expect(editor.commitCalls, 1);
      expect(
        parseLocalDateComposerBlocks(
          editor.value.text,
          environment: environment,
        ).single.attribute('format'),
        format,
      );
    });

    testWidgets('applies both quote types from the real sheet: edit=$editing', (
      tester,
    ) async {
      const original = '[DaTe=2026-08-09 timezone=UTC format="LL"  ]';
      final editor = FakeComposerEditorHost(
        TextEditingValue(
          text: editing ? 'Before $original after' : 'Before after',
          selection: const TextSelection.collapsed(offset: 7),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
          home: const Scaffold(),
        ),
      );
      final context = tester.element(find.byType(Scaffold));
      Object? failure;
      final pending = openLocalDateComposer(
        context,
        editor,
        policy,
        block: editing
            ? parseLocalDateComposerBlocks(
                editor.value.text,
                environment: environment,
              ).single
            : null,
      ).catchError((Object error) => failure = error);
      await tester.pumpAndSettle();
      final options = find.text('Display options');
      await tester.ensureVisible(options);
      await tester.tap(options);
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is DInput && widget.labelText == 'Moment format (optional)',
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, format);
      final apply = find.widgetWithText(DButton, 'Apply');
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      await pending;

      expect(failure, isNull);
      expect(editor.commitCalls, 1);
      expect(editor.focusRequested, isTrue);
      expect(find.byType(LocalDateComposerSheet), findsNothing);
      final block = parseLocalDateComposerBlocks(
        editor.value.text,
        environment: environment,
      ).single;
      expect(block.attribute('format'), format);
      if (editing) {
        expect(block.tagName, 'DaTe');
        expect(block.trailingWhitespace, '  ');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('applying untouched quoted markup preserves the document', (
    tester,
  ) async {
    const original =
        '''[DaTe=2026-08-09 timezone = UTC format = “[It's "party" time] YYYY-MM-DD” future = “keep ] me”  ]''';
    final editor = FakeComposerEditorHost(
      const TextEditingValue(text: 'Before $original after'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
        home: const Scaffold(),
      ),
    );
    final pending = openLocalDateComposer(
      tester.element(find.byType(Scaffold)),
      editor,
      policy,
      block: parseLocalDateComposerBlocks(
        editor.value.text,
        environment: environment,
      ).single,
    );
    await tester.pumpAndSettle();
    final apply = find.widgetWithText(DButton, 'Apply');
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    await pending;
    expect(editor.commitCalls, 0);
    expect(editor.value.text, 'Before $original after');
    expect(editor.focusRequested, isTrue);
    expect(find.byType(LocalDateComposerSheet), findsNothing);
  });
}
