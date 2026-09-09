import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:timezone/timezone.dart' as tz;

import '../styleguide_example.dart';

final calendarExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Select dates and date ranges in a compact month grid.',
  notes:
      'Backed by kalender 0.29.1 and themed with DKalenderTheme. Calendar owns '
      'inline date selection; Date Picker owns its future popover/input. '
      'Gregorian locale labels and RTL are supported. True Persian, Hijri, or '
      'Jalali chronology needs a kalender engine implementation, matching the '
      'official example’s calendar-engine substitution boundary.',
  examples: [
    _example(
      'Basic',
      'A controlled single-date calendar.',
      const ['Single', 'Controlled', 'Today'],
      (_) => _frame(
        DCalendar(
          initialDisplayedMonth: DCalendarDate(2026, 9, 1),
          bordered: true,
        ),
        width: 320,
      ),
    ),
    _example('Range', 'A two-month range with connected endpoints.', const [
      'Range',
      'Two months',
    ], (_) => const _RangeCalendar()),
    _example(
      'Month and Year Selector',
      'Compact Select controls change the visible month without changing selection.',
      const ['Dropdown caption', 'Bounds', 'Controlled month'],
      (_) => const _DropdownCalendar(),
    ),
    _example(
      'Presets',
      'Preset actions and a fixed six-week grid share controller ownership.',
      const ['Card', 'Fixed weeks', 'Controller'],
      (_) => const _PresetCalendar(),
    ),
    _example(
      'Date and Time',
      'Calendar date selection composes with Field and Input Group time ownership.',
      const ['Card', 'Field', 'Input Group', 'Time'],
      (_) => const _DateTimeCalendar(),
    ),
    _example(
      'Booked Dates',
      'Booked days are disabled, announced, and struck through.',
      const ['Booked', 'Disabled', 'Semantics'],
      (_) => const _BookedCalendar(),
    ),
    _example(
      'Custom Cell Size',
      'A responsive day builder adds prices while preserving day interaction.',
      const ['Custom cells', 'Responsive', 'Prices'],
      (_) => const _PricedCalendar(),
    ),
    _example(
      'Week Numbers',
      'ISO week numbers add an accessible leading grid column.',
      const ['Week numbers', 'First weekday'],
      (_) => const _WeekNumberCalendar(),
    ),
    _example(
      'RTL',
      'Logical navigation and range geometry follow Arabic reading direction.',
      const ['RTL', 'Arabic labels', 'Custom numerals'],
      (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _RtlCalendar(),
      ),
    ),
    _example(
      'Timezone boundary',
      'Date-only selection converts to an instant only with an explicit location.',
      const ['Timezone', 'Date-only', 'DST-safe'],
      (_) => const _TimezoneCalendar(),
    ),
  ],
);

StyleguideExample _example(
  String title,
  String description,
  List<String> states,
  WidgetBuilder builder,
) => StyleguideExample(
  title: title,
  description: description,
  states: states,
  code: '''DCalendar(
  selection: selection,
  onSelectionChanged: (next, reason) => setState(() => selection = next),
)''',
  builder: builder,
);

Widget _frame(Widget child, {double width = 640}) => Align(
  alignment: Alignment.topCenter,
  child: ConstrainedBox(
    constraints: BoxConstraints(maxWidth: width),
    child: child,
  ),
);

class _RangeCalendar extends StatefulWidget {
  const _RangeCalendar();
  @override
  State<_RangeCalendar> createState() => _RangeCalendarState();
}

class _RangeCalendarState extends State<_RangeCalendar> {
  DCalendarSelection _selection = DCalendarRangeSelection(
    DCalendarRange(
      from: DCalendarDate(2026, 9, 12),
      to: DCalendarDate(2026, 10, 12),
    ),
  );

  @override
  Widget build(BuildContext context) => _frame(
    DCalendar(
      mode: DCalendarSelectionMode.range,
      displayedMonth: DCalendarDate(2026, 9, 1),
      numberOfMonths: 2,
      selection: _selection,
      bordered: true,
      onSelectionChanged: (value, _) => setState(() => _selection = value),
    ),
  );
}

class _DropdownCalendar extends StatefulWidget {
  const _DropdownCalendar();
  @override
  State<_DropdownCalendar> createState() => _DropdownCalendarState();
}

class _DropdownCalendarState extends State<_DropdownCalendar> {
  var _month = DCalendarDate(2026, 9, 1);
  @override
  Widget build(BuildContext context) => _frame(
    DCalendar(
      displayedMonth: _month,
      onDisplayedMonthChanged: (value) => setState(() => _month = value),
      captionLayout: DCalendarCaptionLayout.dropdown,
      startMonth: DCalendarDate(2020, 1, 1),
      endMonth: DCalendarDate(2030, 12, 1),
      bordered: true,
    ),
    width: 340,
  );
}

class _PresetCalendar extends StatefulWidget {
  const _PresetCalendar();
  @override
  State<_PresetCalendar> createState() => _PresetCalendarState();
}

class _PresetCalendarState extends State<_PresetCalendar> {
  final _controller = DCalendarController(
    displayedMonth: DCalendarDate(2026, 9, 1),
  );
  DCalendarSelection _selection = DCalendarSingleSelection(
    DCalendarDate(2026, 9, 9),
  );

  void _choose(int days) {
    final date = DCalendarDate(2026, 9, 9).addDays(days);
    setState(() => _selection = DCalendarSingleSelection(date));
    _controller.showMonth(date);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _frame(
    DCard(
      size: DCardSize.small,
      footer: DCardFooter(
        muted: false,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in const [
              ('Today', 0),
              ('Tomorrow', 1),
              ('In 3 days', 3),
              ('In a week', 7),
              ('In 2 weeks', 14),
            ])
              DButton(
                label: Text(preset.$1),
                onPressed: () => _choose(preset.$2),
                size: DButtonSize.small,
                variant: DButtonVariant.outline,
              ),
          ],
        ),
      ),
      children: [
        DCardContent(
          child: DCalendar(
            controller: _controller,
            selection: _selection,
            fixedWeeks: true,
            cellSize: 38,
            padding: EdgeInsets.zero,
            onSelectionChanged: (value, _) =>
                setState(() => _selection = value),
          ),
        ),
      ],
    ),
    width: 300,
  );
}

class _DateTimeCalendar extends StatefulWidget {
  const _DateTimeCalendar();
  @override
  State<_DateTimeCalendar> createState() => _DateTimeCalendarState();
}

class _DateTimeCalendarState extends State<_DateTimeCalendar> {
  DCalendarSelection _selection = DCalendarSingleSelection(
    DCalendarDate(2026, 9, 9),
  );
  @override
  Widget build(BuildContext context) => _frame(
    DCard(
      size: DCardSize.small,
      footer: DCardFooter(
        muted: false,
        child: DFieldGroup(
          children: [
            for (final field in const [
              ('Start Time', '10:30:00'),
              ('End Time', '12:30:00'),
            ])
              DField(
                children: [
                  DFieldLabel(child: Text(field.$1)),
                  DInputGroup(
                    semanticLabel: field.$1,
                    children: [
                      DInputGroupInput(
                        initialValue: field.$2,
                        keyboardType: TextInputType.datetime,
                      ),
                      const DInputGroupAddon(
                        alignment: DInputGroupAddonAlignment.inlineEnd,
                        child: Icon(Icons.access_time, size: 16),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
      children: [
        DCardContent(
          child: DCalendar(
            displayedMonth: DCalendarDate(2026, 9, 1),
            selection: _selection,
            padding: EdgeInsets.zero,
            onSelectionChanged: (value, _) =>
                setState(() => _selection = value),
          ),
        ),
      ],
    ),
    width: 360,
  );
}

class _BookedCalendar extends StatefulWidget {
  const _BookedCalendar();
  @override
  State<_BookedCalendar> createState() => _BookedCalendarState();
}

class _BookedCalendarState extends State<_BookedCalendar> {
  DCalendarSelection _selection = DCalendarSingleSelection(
    DCalendarDate(2026, 9, 6),
  );
  @override
  Widget build(BuildContext context) => _frame(
    DCard(
      size: DCardSize.small,
      spacing: 0,
      children: [
        DCardContent(
          edgeToEdge: true,
          child: DCalendar(
            displayedMonth: DCalendarDate(2026, 9, 1),
            selection: _selection,
            booked: (date) => date.day >= 12 && date.day <= 26,
            disabled: (date) => date.day >= 12 && date.day <= 26,
            onSelectionChanged: (value, _) =>
                setState(() => _selection = value),
          ),
        ),
      ],
    ),
    width: 320,
  );
}

class _PricedCalendar extends StatefulWidget {
  const _PricedCalendar();
  @override
  State<_PricedCalendar> createState() => _PricedCalendarState();
}

class _PricedCalendarState extends State<_PricedCalendar> {
  DCalendarSelection _selection = DCalendarRangeSelection(
    DCalendarRange(
      from: DCalendarDate(2026, 9, 8),
      to: DCalendarDate(2026, 9, 18),
    ),
  );

  @override
  Widget build(BuildContext context) => _frame(
    DCard(
      size: DCardSize.small,
      spacing: 0,
      children: [
        DCardContent(
          edgeToEdge: true,
          child: DCalendar(
            mode: DCalendarSelectionMode.range,
            displayedMonth: DCalendarDate(2026, 9, 1),
            selection: _selection,
            onSelectionChanged: (value, _) =>
                setState(() => _selection = value),
            captionLayout: DCalendarCaptionLayout.dropdown,
            cellSize: 40,
            responsiveCellSize: (width) => width < 360 ? 40 : 48,
            dateSemanticLabelBuilder: (context, date) =>
                '${DateFormat.yMMMMd(Localizations.localeOf(context).toLanguageTag()).format(date.dateTimeUtc)}, \$${date.weekday >= 6 ? 120 : 100}',
            dayBuilder: (context, details, child) => FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  child,
                  MediaQuery.withNoTextScaling(
                    child: Text(
                      details.date.weekday >= 6 ? r'$120' : r'$100',
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
    width: 420,
  );
}

class _WeekNumberCalendar extends StatefulWidget {
  const _WeekNumberCalendar();
  @override
  State<_WeekNumberCalendar> createState() => _WeekNumberCalendarState();
}

class _WeekNumberCalendarState extends State<_WeekNumberCalendar> {
  DCalendarSelection _selection = DCalendarSingleSelection(
    DCalendarDate(2026, 9, 12),
  );

  @override
  Widget build(BuildContext context) => _frame(
    DCard(
      size: DCardSize.small,
      spacing: 0,
      children: [
        DCardContent(
          edgeToEdge: true,
          child: DCalendar(
            displayedMonth: DCalendarDate(2026, 9, 1),
            selection: _selection,
            onSelectionChanged: (value, _) =>
                setState(() => _selection = value),
            showWeekNumbers: true,
            firstWeekday: DateTime.monday,
          ),
        ),
      ],
    ),
    width: 350,
  );
}

class _RtlCalendar extends StatelessWidget {
  const _RtlCalendar();
  static const _digits = '٠١٢٣٤٥٦٧٨٩';
  static const _months = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];
  String _number(int value) =>
      '$value'.split('').map((v) => _digits[int.parse(v)]).join();

  @override
  Widget build(BuildContext context) => _frame(
    DCalendar(
      displayedMonth: DCalendarDate(2026, 9, 1),
      locale: const Locale('ar', 'SA'),
      captionLayout: DCalendarCaptionLayout.dropdown,
      cellSize: 36,
      bordered: true,
      labels: const DCalendarLabels(
        calendar: 'التقويم',
        previousMonth: 'الشهر السابق',
        nextMonth: 'الشهر التالي',
        chooseMonth: 'اختر الشهر',
        chooseYear: 'اختر السنة',
        week: 'أسبوع',
        booked: 'محجوز',
      ),
      monthLabelBuilder: (_, month, short) =>
          '${_months[month.month - 1]}${short ? '' : ' ${_number(month.year)}'}',
      yearLabelBuilder: (_, date) => _number(date.year),
      dayNumberBuilder: (_, date) => _number(date.day),
      weekdayLabelBuilder: (_, date) =>
          const ['اث', 'ثل', 'أر', 'خم', 'جم', 'سب', 'أح'][date.weekday - 1],
      dateSemanticLabelBuilder: (_, date) =>
          '${_number(date.day)} ${_months[date.month - 1]} ${_number(date.year)}',
    ),
    width: 320,
  );
}

class _TimezoneCalendar extends StatefulWidget {
  const _TimezoneCalendar();
  @override
  State<_TimezoneCalendar> createState() => _TimezoneCalendarState();
}

class _TimezoneCalendarState extends State<_TimezoneCalendar> {
  DCalendarSelection _selection = DCalendarSingleSelection(
    DCalendarDate(2026, 9, 9),
  );
  @override
  Widget build(BuildContext context) {
    final date = (_selection as DCalendarSingleSelection).date;
    final instant = date?.atTime(tz.UTC, hour: 9).toUtc();
    return _frame(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DCalendar(
            location: tz.UTC,
            displayedMonth: DCalendarDate(2026, 9, 1),
            selection: _selection,
            onSelectionChanged: (value, _) =>
                setState(() => _selection = value),
          ),
          Text(
            instant == null
                ? 'No instant selected'
                : '09:00 UTC → ${instant.toIso8601String()}',
          ),
        ],
      ),
      width: 340,
    );
  }
}
