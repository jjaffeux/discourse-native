import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  setUpAll(tz.initializeTimeZones);

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(900, 800),
    double scale = 1,
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: Directionality(
              textDirection: direction,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('basic picker stays open and updates its owned civil date', (
    tester,
  ) async {
    final changes = <DCalendarDate?>[];
    await pump(
      tester,
      DDatePicker(
        label: 'Date',
        width: 176,
        initialDisplayedMonth: DCalendarDate(2026, 9, 1),
        today: DCalendarDate(2026, 9, 9),
        onChanged: changes.add,
      ),
    );

    await tester.tap(find.text('Pick a date'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Friday, September 11, 2026'));
    await tester.pumpAndSettle();

    expect(changes, [DCalendarDate(2026, 9, 11)]);
    expect(find.text('September 11, 2026'), findsOneWidget);
    expect(find.byType(DCalendar), findsOneWidget);
  });

  testWidgets('date-of-birth close behavior restores trigger focus', (
    tester,
  ) async {
    final triggerFocus = FocusNode();
    addTearDown(triggerFocus.dispose);
    await pump(
      tester,
      DDatePicker(
        label: 'Date of birth',
        width: 176,
        focusNode: triggerFocus,
        closeBehavior: DDatePickerCloseBehavior.onSelection,
        captionLayout: DCalendarCaptionLayout.dropdown,
        initialDisplayedMonth: DCalendarDate(1990, 6, 1),
      ),
    );

    triggerFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(DCalendar), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Friday, June 15, 1990'));
    await tester.pumpAndSettle();
    expect(find.byType(DCalendar), findsNothing);
    expect(triggerFocus.hasFocus, isTrue);
  });

  testWidgets('controlled picker reports but does not accept a declined date', (
    tester,
  ) async {
    DCalendarDate? proposal;
    await pump(
      tester,
      DDatePicker.controlled(
        value: DCalendarDate(2026, 9, 8),
        onChanged: (value) => proposal = value,
        initialDisplayedMonth: DCalendarDate(2026, 9, 1),
      ),
    );
    await tester.tap(find.text('September 08, 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Friday, September 11, 2026'));
    await tester.pumpAndSettle();

    expect(proposal, DCalendarDate(2026, 9, 11));
    expect(find.text('September 08, 2026'), findsOneWidget);
  });

  testWidgets('range picker exposes an incomplete and then complete range', (
    tester,
  ) async {
    final changes = <DCalendarRange?>[];
    await pump(
      tester,
      DDateRangePicker(
        initialDisplayedMonth: DCalendarDate(2026, 9, 1),
        onChanged: changes.add,
      ),
    );
    await tester.tap(find.text('Pick a date'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Tuesday, September 8, 2026'));
    await tester.pumpAndSettle();
    expect(changes.last, DCalendarRange(from: DCalendarDate(2026, 9, 8)));
    expect(find.text('Sep 08, 2026'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Friday, September 11, 2026'));
    await tester.pumpAndSettle();
    expect(
      changes.last,
      DCalendarRange(
        from: DCalendarDate(2026, 9, 8),
        to: DCalendarDate(2026, 9, 11),
      ),
    );
    expect(find.text('Sep 08, 2026 - Sep 11, 2026'), findsOneWidget);
  });

  testWidgets('disabled bounds prevent selection and disabled picker opening', (
    tester,
  ) async {
    var changes = 0;
    await pump(
      tester,
      DDatePicker(
        initialDisplayedMonth: DCalendarDate(2026, 9, 1),
        startMonth: DCalendarDate(2026, 9, 1),
        endMonth: DCalendarDate(2026, 9, 30),
        disabled: (date) => date == DCalendarDate(2026, 9, 11),
        onChanged: (_) => changes++,
      ),
    );
    await tester.tap(find.text('Pick a date'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Friday, September 11, 2026'));
    await tester.pump();
    expect(changes, 0);

    await pump(tester, const DDatePicker(enabled: false));
    await tester.tap(find.text('Pick a date'));
    await tester.pumpAndSettle();
    expect(find.byType(DCalendar), findsNothing);
  });

  testWidgets('Form validates, saves, changes and resets typed dates', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    DCalendarDate? saved;
    final changes = <DCalendarDate?>[];
    await pump(
      tester,
      Form(
        key: form,
        child: DDatePickerFormField(
          label: 'Required date',
          isRequired: true,
          initialValue: DCalendarDate(2026, 9, 8),
          initialDisplayedMonth: DCalendarDate(2026, 9, 1),
          validator: (value) => value == null ? 'Choose a date.' : null,
          onSaved: (value) => saved = value,
          onChanged: changes.add,
        ),
      ),
    );
    await tester.tap(find.text('September 08, 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Friday, September 11, 2026'));
    await tester.pumpAndSettle();
    form.currentState!.save();
    expect(saved, DCalendarDate(2026, 9, 11));

    form.currentState!.reset();
    await tester.pumpAndSettle();
    expect(changes.last, DCalendarDate(2026, 9, 8));
    expect(find.text('September 08, 2026'), findsOneWidget);
  });

  testWidgets('controlled Form keeps an unaccepted proposal out of save', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    DCalendarDate? proposed;
    DCalendarDate? saved;
    await pump(
      tester,
      Form(
        key: form,
        child: DDatePickerFormField.controlled(
          value: DCalendarDate(2026, 9, 8),
          onChanged: (value) {
            proposed = value;
            form.currentState!.save();
          },
          onSaved: (value) => saved = value,
          initialDisplayedMonth: DCalendarDate(2026, 9, 1),
        ),
      ),
    );
    await tester.tap(find.text('September 08, 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Friday, September 11, 2026'));
    await tester.pumpAndSettle();

    expect(proposed, DCalendarDate(2026, 9, 11));
    expect(saved, DCalendarDate(2026, 9, 8));
    expect(find.text('September 08, 2026'), findsOneWidget);
  });

  testWidgets('range calendar stays usable at narrow 200 percent RTL', (
    tester,
  ) async {
    await pump(
      tester,
      DDateRangePicker(initialDisplayedMonth: DCalendarDate(2026, 9, 1)),
      size: const Size(216, 900),
      scale: 2,
      direction: TextDirection.rtl,
    );
    await tester.tap(find.text('Pick a date'));
    await tester.pumpAndSettle();

    expect(find.byType(DCalendar), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
