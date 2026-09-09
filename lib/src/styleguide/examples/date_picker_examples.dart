import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../styleguide_example.dart';

final datePickerExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Select a civil date or range from a Kalender-backed calendar.',
  notes:
      'Composes Button, Popover, Field, Input Group and Kalender-backed '
      'Calendar. Date-only and wall-clock values remain separate until an '
      'application timezone adapter resolves them.',
  examples: [
    _example(
      'Composition',
      'The documented compact Date Picker composition.',
      'DDatePicker(initialDisplayedMonth: DCalendarDate(2025, 6, 1))',
      (_) => DDatePicker(initialDisplayedMonth: DCalendarDate(2025, 6, 1)),
    ),
    _example(
      'Basic',
      'A labelled picker that remains open after selection.',
      '''DDatePicker(
  label: 'Date',
  width: 176,
  showChevron: false,
)''',
      (_) => DDatePicker(
        label: 'Date',
        width: 176,
        showChevron: false,
        initialDisplayedMonth: DCalendarDate(2025, 6, 1),
      ),
    ),
    _example(
      'Range Picker',
      'A two-month civil-date range.',
      '''DDateRangePicker(
  initialValue: DCalendarRange(
    from: DCalendarDate(2026, 1, 20),
    to: DCalendarDate(2026, 2, 9),
  ),
)''',
      (_) => DDateRangePicker(
        initialValue: DCalendarRange(
          from: DCalendarDate(2026, 1, 20),
          to: DCalendarDate(2026, 2, 9),
        ),
        initialDisplayedMonth: DCalendarDate(2026, 1, 1),
      ),
    ),
    _example(
      'Date of Birth',
      'Month/year caption controls and close-on-select.',
      '''DDatePicker(
  label: 'Date of birth',
  labels: DDatePickerLabels(placeholder: 'Select date'),
  captionLayout: DCalendarCaptionLayout.dropdown,
  closeBehavior: DDatePickerCloseBehavior.onSelection,
  showChevron: false,
)''',
      (_) => DDatePicker(
        label: 'Date of birth',
        labels: const DDatePickerLabels(placeholder: 'Select date'),
        width: 176,
        showChevron: false,
        closeBehavior: DDatePickerCloseBehavior.onSelection,
        captionLayout: DCalendarCaptionLayout.dropdown,
        dateCodec: const DIntlDateTextCodec(
          formatPattern: 'M/d/yyyy',
          useLocaleDateOrder: false,
        ),
        initialDisplayedMonth: DCalendarDate(1990, 6, 1),
        startMonth: DCalendarDate(1900, 1, 1),
        endMonth: DCalendarDate(2026, 9, 9),
      ),
    ),
    _example(
      'Input',
      'Strict editable text with an inline calendar action.',
      '''DDatePickerInput(
  label: 'Subscription Date',
  width: 192,
  initialValue: DCalendarDate(2025, 6, 1),
)''',
      (_) => DDatePickerInput(
        label: 'Subscription Date',
        width: 192,
        initialValue: DCalendarDate(2025, 6, 1),
      ),
    ),
    _example(
      'Time Picker',
      'Separate typed date and wall-clock values.',
      'DDatePicker.controlled(/* date */) + DTimeInput(/* wall clock */)',
      (_) => const _DateAndTimeExample(),
    ),
    _example(
      'Natural Language Picker',
      'Relative input parsed against an explicit deterministic clock.',
      '''DDatePickerInput.controlled(
  label: 'Schedule Date',
  naturalDateParser: DEnglishNaturalDateParser(),
  referenceDate: DateTime(2026, 9, 9),
)''',
      (_) => const _NaturalExample(),
    ),
    _example(
      'RTL',
      'Switch between the documented English, Arabic and Hebrew directions.',
      'Directionality(textDirection: direction, child: DDatePicker(...))',
      (_) => const _RtlDatePickerExample(),
    ),
  ],
);

StyleguideExample _example(
  String title,
  String description,
  String code,
  WidgetBuilder builder,
) => StyleguideExample(
  title: title,
  description: description,
  states: const ['Keyboard', 'Touch', 'Live theme'],
  code: code,
  builder: (context) =>
      Align(alignment: Alignment.topCenter, child: builder(context)),
);

class _DateAndTimeExample extends StatefulWidget {
  const _DateAndTimeExample();
  @override
  State<_DateAndTimeExample> createState() => _DateAndTimeExampleState();
}

class _DateAndTimeExampleState extends State<_DateAndTimeExample> {
  DCalendarDate? date;
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
        labels: const DDatePickerLabels(placeholder: 'Select date'),
        width: 128,
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
  final reference = DateTime(2026, 9, 9);
  final controller = TextEditingController(text: 'In 2 days');
  DCalendarDate? date = DCalendarDate(2026, 9, 11);
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
          label: 'Schedule Date',
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

class _RtlDatePickerExample extends StatefulWidget {
  const _RtlDatePickerExample();

  @override
  State<_RtlDatePickerExample> createState() => _RtlDatePickerExampleState();
}

class _RtlDatePickerExampleState extends State<_RtlDatePickerExample> {
  String _language = 'ar';

  @override
  Widget build(BuildContext context) {
    final rtl = _language != 'en';
    final locale = switch (_language) {
      'ar' => const Locale('ar', 'SA'),
      'he' => const Locale('he'),
      _ => const Locale('en', 'US'),
    };
    final placeholder = switch (_language) {
      'ar' => 'اختر تاريخًا',
      'he' => 'בחר תאריך',
      _ => 'Pick a date',
    };
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DSelect<String>.controlled(
            value: _language,
            width: 180,
            semanticLabel: 'Language',
            entries: const [
              DSelectOption(
                value: 'en',
                label: 'English',
                child: Text('English'),
              ),
              DSelectOption(
                value: 'ar',
                label: 'العربية',
                child: Text('العربية'),
              ),
              DSelectOption(value: 'he', label: 'עברית', child: Text('עברית')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _language = value);
            },
          ),
          const SizedBox(height: 12),
          DDatePicker(
            locale: locale,
            labels: DDatePickerLabels(placeholder: placeholder),
            initialDisplayedMonth: DCalendarDate(2025, 6, 1),
          ),
        ],
      ),
    );
  }
}
