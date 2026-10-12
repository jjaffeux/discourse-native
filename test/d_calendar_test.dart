import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart' show kPressTimeout;
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
      tz.TZDateTime(
        tz.UTC,
        selected.year,
        selected.month,
        selected.day,
        10,
        30,
      ),
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
        selection: DCalendarSingleSelection(DCalendarDate(2026, 9, 8)),
        onSelectionChanged: (value, reason) => next = value,

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

  testWidgets('disabling a pressed day releases its pressed fill', (
    tester,
  ) async {
    final target = DCalendarDate(2026, 9, 10);
    final disabled = ValueNotifier(false);
    addTearDown(disabled.dispose);
    await pump(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: disabled,
        builder: (context, value, _) => DCalendar(
          initialDisplayedMonth: september,
          disabled: (date) => value && date == target,
        ),
      ),
    );
    final day = find.byWidgetPredicate(
      (widget) =>
          widget is DCalendarDayButton &&
          widget.semanticLabel == 'Thursday, September 10, 2026',
    );
    Color? fill() =>
        (tester
                    .widget<AnimatedContainer>(
                      find.descendant(
                        of: day,
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration!
                as BoxDecoration)
            .color;
    final resting = fill();

    // The month pager competes for the pointer, so the press shows only once
    // it outlasts the press timeout.
    final press = await tester.startGesture(tester.getCenter(day));
    await tester.pump(kPressTimeout);
    expect(fill(), isNot(resting));

    disabled.value = true;
    await tester.pump();
    expect(tester.takeException(), isNull);
    await press.up();
    await tester.pump();
    disabled.value = false;
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(fill(), resting);
  });

  testWidgets('shift-arrow shortcuts move by month and year', (tester) async {
    final controller = DCalendarController(
      focusedDate: DCalendarDate(2026, 9, 8),
    );
    addTearDown(controller.dispose);
    await pump(
      tester,
      DCalendar(controller: controller, initialDisplayedMonth: september),
    );
    Focus.of(tester.element(find.text('8').first)).requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('2026-10-08'),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('2027-10-08'),
    );
  });

  testWidgets('narrow 200 percent text and live dark theme do not overflow', (
    tester,
  ) async {
    await pump(
      tester,
      DCalendar(initialDisplayedMonth: september, numberOfMonths: 2),
      size: const Size(320, 900),
      scale: 2,
      brightness: Brightness.dark,
    );
    expect(find.byType(kalender.KalenderView), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
