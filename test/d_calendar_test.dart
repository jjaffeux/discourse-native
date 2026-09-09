import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalender/kalender.dart' as kalender;
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(timezone_data.initializeTimeZones);
  final september = DCalendarDate(2026, 9, 1);

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(800, 700),
    double scale = 1,
    TextDirection direction = TextDirection.ltr,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Directionality(
              textDirection: direction,
              child: Align(alignment: Alignment.topLeft, child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('date-only conversion keeps timezone ownership explicit', () {
    final selected = DCalendarDate.fromInstant(
      DateTime.utc(2026, 9, 8, 23, 30),
      tz.getLocation('Etc/GMT-2'),
    );
    expect(selected, DCalendarDate(2026, 9, 9));
    expect(
      selected.atTime(tz.UTC, hour: 10, minute: 30),
      tz.TZDateTime.utc(2026, 9, 9, 10, 30),
    );
    expect(
      DCalendarDate(2024, 2, 29).addMonths(12),
      DCalendarDate(2025, 2, 28),
    );
  });

  testWidgets('uses kalender and selects a controlled single day', (
    tester,
  ) async {
    DCalendarSelection? next;
    await pump(
      tester,
      DCalendar(
        displayedMonth: september,
        selection: DCalendarSingleSelection(DCalendarDate(2026, 9, 8)),
        onSelectionChanged: (value, reason) => next = value,
        bordered: true,
        today: DCalendarDate(2026, 9, 9),
      ),
    );

    expect(find.byType(kalender.KalenderView), findsOneWidget);
    expect(find.text('September 2026'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Tuesday, September 8, 2026'))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    await tester.tap(find.bySemanticsLabel('Thursday, September 10, 2026'));
    await tester.pump();
    expect(next, DCalendarSingleSelection(DCalendarDate(2026, 9, 10)));
  });

  testWidgets(
    'multiple and range selection enforce disabled and length bounds',
    (tester) async {
      DCalendarSelection? multiple;
      await pump(
        tester,
        DCalendar(
          mode: DCalendarSelectionMode.multiple,
          initialDisplayedMonth: september,
          disabled: (date) => date == DCalendarDate(2026, 9, 9),
          onSelectionChanged: (value, _) => multiple = value,
        ),
      );
      await tester.tap(find.bySemanticsLabel('Tuesday, September 8, 2026'));
      await tester.pump();
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Thursday, September 10, 2026'))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      await tester.tap(find.bySemanticsLabel('Wednesday, September 9, 2026'));
      await tester.pump();
      expect((multiple! as DCalendarMultipleSelection).dates, [
        DCalendarDate(2026, 9, 8),
      ]);

      DCalendarSelection? range;
      await pump(
        tester,
        DCalendar(
          mode: DCalendarSelectionMode.range,
          initialDisplayedMonth: september,
          minRangeDays: 3,
          maxRangeDays: 5,
          onSelectionChanged: (value, _) => range = value,
        ),
      );
      await tester.tap(find.bySemanticsLabel('Tuesday, September 8, 2026'));
      await tester.pump();
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Thursday, September 10, 2026'))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      await tester.tap(find.bySemanticsLabel('Wednesday, September 9, 2026'));
      await tester.tap(find.bySemanticsLabel('Friday, September 11, 2026'));
      await tester.pump();
      expect(
        (range! as DCalendarRangeSelection).range,
        DCalendarRange(
          from: DCalendarDate(2026, 9, 8),
          to: DCalendarDate(2026, 9, 11),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Friday, September 11, 2026'));
      await tester.tap(find.bySemanticsLabel('Monday, September 7, 2026'));
      await tester.pump();
      expect(
        (range! as DCalendarRangeSelection).range,
        DCalendarRange(
          from: DCalendarDate(2026, 9, 7),
          to: DCalendarDate(2026, 9, 11),
        ),
      );
    },
  );

  testWidgets('controller updates selection and displayed month', (
    tester,
  ) async {
    final controller = DCalendarController();
    final changes = <DCalendarSelection>[];
    await pump(
      tester,
      DCalendar(
        controller: controller,
        initialDisplayedMonth: september,
        onSelectionChanged: (value, _) => changes.add(value),
      ),
    );
    controller.setSelection(
      DCalendarSingleSelection(DCalendarDate(2026, 9, 12)),
    );
    controller.showMonth(DCalendarDate(2026, 10, 1));
    await tester.pumpAndSettle();
    expect(changes.last, DCalendarSingleSelection(DCalendarDate(2026, 9, 12)));
    expect(find.text('October 2026'), findsOneWidget);
  });

  testWidgets('controlled displayed month updates caption and grid together', (
    tester,
  ) async {
    late StateSetter rebuild;
    var month = september;
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return DCalendar(
            displayedMonth: month,
            captionLayout: DCalendarCaptionLayout.dropdown,
          );
        },
      ),
    );

    rebuild(() => month = DCalendarDate(2026, 12, 1));
    await tester.pumpAndSettle();

    expect(find.text('Dec'), findsOneWidget);
    expect(find.bySemanticsLabel('Tuesday, December 1, 2026'), findsOneWidget);
    expect(find.bySemanticsLabel('Tuesday, September 1, 2026'), findsNothing);
  });

  testWidgets('controller clears selection and replacement adopts new state', (
    tester,
  ) async {
    final first = DCalendarController(
      selection: DCalendarSingleSelection(DCalendarDate(2026, 9, 8)),
      displayedMonth: september,
    );
    final second = DCalendarController(
      selection: DCalendarSingleSelection(DCalendarDate(2026, 10, 12)),
      displayedMonth: DCalendarDate(2026, 10, 1),
    );
    late StateSetter rebuild;
    var controller = first;
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return DCalendar(controller: controller);
        },
      ),
    );

    first.clear();
    await tester.pump();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Tuesday, September 8, 2026'))
          .flagsCollection
          .isSelected,
      Tristate.isFalse,
    );

    rebuild(() => controller = second);
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Monday, October 12, 2026'))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
  });

  testWidgets(
    'keyboard traversal enters one roving day and week numbers are named',
    (tester) async {
      final before = FocusNode(debugLabel: 'Before calendar');
      final after = FocusNode(debugLabel: 'After calendar');
      addTearDown(before.dispose);
      addTearDown(after.dispose);
      await pump(
        tester,
        Column(
          children: [
            TextButton(
              focusNode: before,
              autofocus: true,
              onPressed: () {},
              child: const Text('Before calendar'),
            ),
            DCalendar(
              initialDisplayedMonth: september,
              initialSelection: DCalendarSingleSelection(
                DCalendarDate(2026, 9, 8),
              ),
              showWeekNumbers: true,
              firstWeekday: DateTime.monday,
            ),
            TextButton(
              focusNode: after,
              onPressed: () {},
              child: const Text('After calendar'),
            ),
          ],
        ),
      );

      expect(FocusManager.instance.primaryFocus, before);
      // Previous and next month controls precede the single roving grid cell.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        contains('2026-09-08'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(FocusManager.instance.primaryFocus, after);
      expect(find.bySemanticsLabel(RegExp(r'^Week \d+$')), findsWidgets);
    },
  );

  testWidgets('start and end month bounds include their complete months', (
    tester,
  ) async {
    DCalendarSelection? selection;
    await pump(
      tester,
      DCalendar(
        displayedMonth: september,
        startMonth: DCalendarDate(2026, 9, 20),
        endMonth: DCalendarDate(2026, 9, 1),
        onSelectionChanged: (value, _) => selection = value,
      ),
    );

    await tester.tap(find.bySemanticsLabel('Tuesday, September 1, 2026'));
    await tester.pump();
    expect(
      (selection! as DCalendarSingleSelection).date,
      DCalendarDate(2026, 9, 1),
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Wednesday, September 30, 2026'))
          .flagsCollection
          .isEnabled,
      Tristate.isTrue,
    );
  });

  testWidgets('keyboard navigates days, months, years and logical RTL', (
    tester,
  ) async {
    DCalendarSelection? selection;
    final controller = DCalendarController(
      focusedDate: DCalendarDate(2026, 9, 8),
    );
    await pump(
      tester,
      DCalendar(
        controller: controller,
        initialDisplayedMonth: september,
        onSelectionChanged: (value, _) => selection = value,
      ),
    );
    controller.focusDate(DCalendarDate(2026, 9, 8));
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('2026-09-08'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      (selection! as DCalendarSingleSelection).date,
      DCalendarDate(2026, 9, 9),
    );

    await pump(
      tester,
      DCalendar(
        controller: controller,
        displayedMonth: september,
        onSelectionChanged: (value, _) => selection = value,
      ),
      direction: TextDirection.rtl,
    );
    controller.focusDate(DCalendarDate(2026, 9, 8));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(
      (selection! as DCalendarSingleSelection).date,
      DCalendarDate(2026, 9, 7),
    );
  });

  testWidgets(
    'two fixed months, week numbers, dropdowns and custom cells render',
    (tester) async {
      await pump(
        tester,
        DCalendar(
          initialDisplayedMonth: september,
          numberOfMonths: 2,
          fixedWeeks: true,
          showWeekNumbers: true,
          captionLayout: DCalendarCaptionLayout.dropdown,
          booked: (date) => date == DCalendarDate(2026, 9, 12),
          dayBuilder: (context, details, child) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [child, if (!details.outside) const Text(r'$100')],
          ),
        ),
        size: const Size(900, 700),
      );
      expect(find.byType(kalender.KalenderView), findsNWidgets(2));
      expect(find.text(r'$100'), findsWidgets);
      expect(find.bySemanticsLabel('Choose month'), findsNWidgets(2));
      expect(
        find.bySemanticsLabel('Saturday, September 12, 2026'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow 200 percent text and live dark theme do not overflow', (
    tester,
  ) async {
    await pump(
      tester,
      DCalendar(
        initialDisplayedMonth: september,
        numberOfMonths: 2,
        bordered: true,
      ),
      size: const Size(320, 900),
      scale: 2,
      brightness: Brightness.dark,
    );
    expect(find.byType(kalender.KalenderView), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
