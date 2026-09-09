import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../styleguide_example.dart';

final datePickerExamples = ComponentExamples(
  status: ComponentStatus.baseline,
  description: 'Select a civil date or range from a Kalender-backed calendar.',
  notes:
      'Composes Button, Popover, Field, Input Group and Kalender-backed '
      'Calendar. Date-only and wall-clock values remain separate until an '
      'application timezone adapter resolves them.',
  examples: [
    _example(
      'Composition',
      'The documented compact Date Picker composition.',
      (_) => DDatePicker(initialValue: DCalendarDate(2025, 6, 1)),
    ),
    _example(
      'Basic',
      'A labelled picker that remains open after selection.',
      (_) => DDatePicker(
        label: 'Date',
        width: 176,
        initialDisplayedMonth: DCalendarDate(2025, 6, 1),
      ),
    ),
    _example(
      'Range Picker',
      'A two-month civil-date range.',
      (_) => DDateRangePicker(
        initialValue: DCalendarRange(
          from: DCalendarDate(2025, 6, 12),
          to: DCalendarDate(2025, 6, 18),
        ),
        initialDisplayedMonth: DCalendarDate(2025, 6, 1),
      ),
    ),
    _example(
      'Date of Birth',
      'Month/year caption controls and close-on-select.',
      (_) => DDatePicker(
        label: 'Date of birth',
        width: 176,
        closeBehavior: DDatePickerCloseBehavior.onSelection,
        captionLayout: DCalendarCaptionLayout.dropdown,
        initialDisplayedMonth: DCalendarDate(1990, 6, 1),
        startMonth: DCalendarDate(1900, 1, 1),
        endMonth: DCalendarDate(2026, 9, 9),
      ),
    ),
    _example(
      'Input',
      'Strict editable text with an inline calendar action.',
      (_) =>
          DDatePickerInput(width: 192, initialValue: DCalendarDate(2025, 6, 1)),
    ),
    _example(
      'Time Picker',
      'Separate typed date and wall-clock values.',
      (_) => const _DateAndTimeExample(),
    ),
    _example(
      'Natural Language Picker',
      'Relative input parsed against an explicit deterministic clock.',
      (_) => const _NaturalExample(),
    ),
    _example(
      'RTL',
      'Logical trigger geometry and calendar navigation mirror.',
      (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: DDatePicker(
          locale: const Locale('ar'),
          initialValue: DCalendarDate(2025, 6, 1),
        ),
      ),
    ),
  ],
);

StyleguideExample _example(
  String title,
  String description,
  WidgetBuilder builder,
) => StyleguideExample(
  title: title,
  description: description,
  states: const ['Keyboard', 'Touch', 'Live theme'],
  code: 'DDatePicker(/* composes DPopover and DCalendar */)',
  builder: (context) =>
      Align(alignment: Alignment.topCenter, child: builder(context)),
);

class _DateAndTimeExample extends StatefulWidget {
  const _DateAndTimeExample();
  @override
  State<_DateAndTimeExample> createState() => _DateAndTimeExampleState();
}

class _DateAndTimeExampleState extends State<_DateAndTimeExample> {
  DCalendarDate? date = DCalendarDate(2025, 6, 1);
  DTimeValue? time = const DTimeValue(hour: 10, minute: 30);
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      DDatePicker.controlled(
        value: date,
        onChanged: (value) => setState(() => date = value),
        label: 'Date',
        width: 176,
        closeBehavior: DDatePickerCloseBehavior.onSelection,
      ),
      DTimeInput(
        initialValue: time,
        label: 'Time',
        width: 128,
        onChanged: (value) => setState(() => time = value),
      ),
    ],
  );
}

class _NaturalExample extends StatefulWidget {
  const _NaturalExample();
  @override
  State<_NaturalExample> createState() => _NaturalExampleState();
}

class _NaturalExampleState extends State<_NaturalExample> {
  final reference = DateTime(2025, 6, 1);
  final controller = TextEditingController(text: 'In 2 days');
  DCalendarDate? date = DCalendarDate(2025, 6, 3);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 320,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DDatePickerInput.controlled(
          value: date,
          controller: controller,
          onChanged: (value) => setState(() => date = value),
          placeholder: 'In 2 days',
          naturalDateParser: const DEnglishNaturalDateParser(),
          referenceDate: reference,
          width: 320,
        ),
        const SizedBox(height: 8),
        Text(
          date == null
              ? 'No publish date selected.'
              : 'Your post will be published on ${DateFormat.yMMMMd().format(date!.dateTimeUtc)}.',
        ),
      ],
    ),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
