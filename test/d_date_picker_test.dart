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

  testWidgets('editable input ignores active IME composition', (tester) async {
    final changes = <DCalendarDate?>[];
    await pump(
      tester,
      DDatePickerInput(
        initialValue: DCalendarDate(2025, 6, 1),
        onChanged: changes.add,
      ),
    );

    await tester.tap(find.byType(TextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'February 29, 2025',
        selection: TextSelection.collapsed(offset: 17),
        composing: TextRange(start: 0, end: 17),
      ),
    );
    await tester.pump();

    expect(changes, isEmpty);
    expect(find.text('Enter a valid date'), findsNothing);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'February 29, 2025',
        selection: TextSelection.collapsed(offset: 17),
      ),
    );
    await tester.pump();
    expect(changes, isEmpty);
  });

  testWidgets('disabled editable picker cannot be opened imperatively', (
    tester,
  ) async {
    final popover = DPopoverController();
    addTearDown(popover.dispose);
    await pump(tester, const DDatePickerInput());

    popover.open();
    await tester.pumpAndSettle();
    expect(find.byType(DCalendar), findsNothing);
  });

  testWidgets('editable picker preserves and never disposes borrowed editors', (
    tester,
  ) async {
    final first = TextEditingController(text: '2026-09-09');
    final second = TextEditingController(text: '2026-09-10');
    final focus = FocusNode();
    addTearDown(() {
      first.dispose();
      second.dispose();
      focus.dispose();
    });
    const key = ValueKey('editable-date');

    await pump(tester, DDatePickerInput(key: key, controller: first));
    await pump(tester, const DDatePickerInput(key: key));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '2026-09-09',
    );
    expect(() => first.text = 'still owned by caller', returnsNormally);

    await pump(tester, DDatePickerInput(key: key, controller: second));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller,
      same(second),
    );
    await pump(tester, const SizedBox());
    expect(() => second.text = 'still alive', returnsNormally);
    expect(() => focus.requestFocus(), returnsNormally);
  });

  testWidgets('editable calendar action retains a touch-sized target', (
    tester,
  ) async {
    await pump(
      tester,
      const DDatePickerInput(width: 192),
      size: const Size(320, 640),
    );
    final action = find.bySemanticsLabel('Select date');
    expect(tester.getSize(action).width, 40);
    expect(tester.getSize(action).height, 40);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('time input reports only strict typed wall-clock values', (
    tester,
  ) async {
    final changes = <DTimeValue?>[];
    final validity = <bool>[];
    await pump(
      tester,
      DTimeInput(onChanged: changes.add, onValidityChanged: validity.add),
    );
    await tester.enterText(find.byType(TextField), '25:00:00');
    await tester.pump();
    expect(changes, isEmpty);
    expect(validity, [false]);
    expect(find.text('Enter a valid time'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '08:30:15');
    await tester.pump();
    expect(changes.last, const DTimeValue(hour: 8, minute: 30, second: 15));
    expect(validity, [false, true]);

    await tester.enterText(find.byType(TextField), '08:30:99');
    await tester.pump();
    expect(changes, [const DTimeValue(hour: 8, minute: 30, second: 15)]);
    expect(validity.last, isFalse);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(changes.last, isNull);
    expect(validity.last, isTrue);
  });
}
