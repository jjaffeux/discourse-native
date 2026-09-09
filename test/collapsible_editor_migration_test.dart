import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer_parser.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_editor.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_sheet.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is DInput && w.labelText == label),
  matching: find.byType(TextField),
);

void main() {
  setUpAll(() {
    LocalDateEnvironment.instance.ensureDatabase();
    LocalDateEnvironment.instance.setDeviceTimezone('Etc/UTC');
  });
  testWidgets(
    'event More options retains text selection and edits through collapse and preserves apply markup',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (_) => EventComposerSheet(
                      settings: const EventSettings(enabled: true),
                      timezone: 'Etc/UTC',
                      isCurrent: () => true,
                      block: parseEventBlocks(
                        '[event start="2026-09-09 12:00" timezone="Etc/UTC" max-attendees="20"]Description[/event]',
                      ).single,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('More options'));
      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();
      final maximum = field('Maximum attendees (optional)');
      expect(maximum, findsOneWidget);
      await tester.ensureVisible(maximum);
      await tester.enterText(maximum, '42');
      final controller = tester.widget<TextField>(maximum).controller!;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 1,
      );
      await tester.ensureVisible(find.text('More options'));
      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();
      expect(controller.text, '42');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 1),
      );
      await tester.ensureVisible(find.text('Apply'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(result, contains('max-attendees="42"'));
      expect(result, contains('Description'));
    },
  );

  testWidgets(
    'local date Display options retains recurrence and commits draft after collapse',
    (tester) async {
      LocalDateComposerSheetAction? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showLocalDateComposerSheet(
                    context: context,
                    draft: LocalDateComposerDraft.newDate(
                      now: DateTime(2026, 9, 9),
                      timezone: 'Etc/UTC',
                      environment: LocalDateEnvironment.instance,
                    ),
                    siteFormats: const [],
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Display options'));
      await tester.tap(find.text('Display options'));
      await tester.pumpAndSettle();
      final recurrence = field('Recurrence (optional)');
      await tester.ensureVisible(recurrence);
      await tester.enterText(recurrence, '1.weeks');
      await tester.ensureVisible(find.text('Display options'));
      await tester.tap(find.text('Display options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Display options'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(recurrence).controller!.text, '1.weeks');
      await tester.ensureVisible(find.text('Apply'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(result?.draft?.recurring, '1.weeks');
    },
  );
}
