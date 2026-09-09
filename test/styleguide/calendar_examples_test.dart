import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/calendar_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Calendar registers the complete frozen example matrix', () {
    expect(componentExamples['calendar'], same(calendarExamples));
    expect(calendarExamples.examples.map((example) => example.title), [
      'Basic',
      'Range',
      'Month and Year Selector',
      'Presets',
      'Date and Time',
      'Booked Dates',
      'Custom Cell Size',
      'Week Numbers',
      'RTL',
      'Timezone boundary',
    ]);
  });

  for (final brightness in Brightness.values) {
    testWidgets('Calendar examples fit narrow 200% ${brightness.name}', (
      tester,
    ) async {
      final theme = brightness == Brightness.dark
          ? AppTheme.dark
          : AppTheme.light;
      for (final example in calendarExamples.examples) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SizedBox(
                  width: 360,
                  height: 900,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Builder(
                        key: ValueKey(example.title),
                        builder: example.builder,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(DCalendar), findsAtLeastNWidgets(1));
        expect(tester.takeException(), isNull, reason: example.title);
      }
    });
  }

  testWidgets('preset and date-time examples keep real shared primitives', (
    tester,
  ) async {
    final preset = calendarExamples.examples.singleWhere(
      (example) => example.title == 'Presets',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(child: Builder(builder: preset.builder)),
        ),
      ),
    );
    await tester.ensureVisible(find.text('In a week'));
    await tester.tap(find.text('In a week'));
    await tester.pump();
    expect(find.byType(DCard), findsOneWidget);

    final dateTime = calendarExamples.examples.singleWhere(
      (example) => example.title == 'Date and Time',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Builder(builder: dateTime.builder),
          ),
        ),
      ),
    );
    expect(find.byType(DField), findsNWidgets(2));
    expect(find.byType(DInputGroup), findsNWidgets(2));
    expect(find.byType(DInputGroupInput), findsNWidgets(2));
  });

  testWidgets('custom cells announce the actual month and price', (
    tester,
  ) async {
    final custom = calendarExamples.examples.singleWhere(
      (example) => example.title == 'Custom Cell Size',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Builder(builder: custom.builder)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('August 30, 2026, \$120'), findsOneWidget);
    expect(find.bySemanticsLabel('October 1, 2026, \$100'), findsOneWidget);
  });

  testWidgets('RTL outside days announce their actual Arabic month', (
    tester,
  ) async {
    final rtl = calendarExamples.examples.singleWhere(
      (example) => example.title == 'RTL',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Builder(builder: rtl.builder)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('٣٠ أغسطس ٢٠٢٦'), findsOneWidget);
    expect(find.bySemanticsLabel('١ أكتوبر ٢٠٢٦'), findsOneWidget);
  });
}
