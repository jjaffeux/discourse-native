import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:kalender/kalender.dart' as kalender;
import 'package:kalender/kalender_extensions.dart' as kalender_ext;
import 'package:timezone/timezone.dart' as tz;

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_select.dart';

/// A date without a time-of-day or timezone.
///
/// An instant must be converted with [fromInstant]. A selected day can be
/// turned back into a zoned wall time with [atTime]. Keeping these operations
/// explicit avoids the common UTC-midnight selected-date offset.
@immutable
class DCalendarDate implements Comparable<DCalendarDate> {
  DCalendarDate(int year, int month, int day)
    : _value = DateTime.utc(year, month, day) {
    if (_value.year != year || _value.month != month || _value.day != day) {
      throw ArgumentError.value('$year-$month-$day', 'date', 'Invalid date');
    }
  }

  const DCalendarDate._(this._value);

  factory DCalendarDate.fromDateTime(DateTime value) =>
      DCalendarDate(value.year, value.month, value.day);

  factory DCalendarDate.fromInstant(DateTime instant, tz.Location location) {
    final local = tz.TZDateTime.from(instant, location);
    return DCalendarDate(local.year, local.month, local.day);
  }

  final DateTime _value;
  int get year => _value.year;
  int get month => _value.month;
  int get day => _value.day;
  int get weekday => _value.weekday;

  DCalendarDate addDays(int days) =>
      DCalendarDate._(_value.add(Duration(days: days)));

  DCalendarDate addMonths(int months) {
    final first = DateTime.utc(year, month + months);
    final lastDay = DateTime.utc(first.year, first.month + 1, 0).day;
    return DCalendarDate(first.year, first.month, math.min(day, lastDay));
  }

  tz.TZDateTime atTime(
    tz.Location location, {
    int hour = 0,
    int minute = 0,
    int second = 0,
  }) => tz.TZDateTime(location, year, month, day, hour, minute, second);

  DateTime get dateTimeUtc => _value;

  @override
  int compareTo(DCalendarDate other) => _value.compareTo(other._value);
  bool isBefore(DCalendarDate other) => compareTo(other) < 0;
  bool isAfter(DCalendarDate other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is DCalendarDate && other._value == _value;
  @override
  int get hashCode => _value.hashCode;
  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

@immutable
class DCalendarRange {
  const DCalendarRange({required this.from, this.to});
  final DCalendarDate from;
  final DCalendarDate? to;

  bool contains(DCalendarDate date) =>
      to == null ? date == from : !date.isBefore(from) && !date.isAfter(to!);

  int? get lengthInDays => to == null
      ? null
      : to!.dateTimeUtc.difference(from.dateTimeUtc).inDays + 1;

  @override
  bool operator ==(Object other) =>
      other is DCalendarRange && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
}

sealed class DCalendarSelection {
  const DCalendarSelection();
}

@immutable
class DCalendarSingleSelection extends DCalendarSelection {
  const DCalendarSingleSelection(this.date);
  final DCalendarDate? date;

  @override
  bool operator ==(Object other) =>
      other is DCalendarSingleSelection && other.date == date;
  @override
  int get hashCode => date.hashCode;
}

@immutable
class DCalendarMultipleSelection extends DCalendarSelection {
  DCalendarMultipleSelection(Iterable<DCalendarDate> dates)
    : dates = List.unmodifiable({...dates}.toList()..sort());
  final List<DCalendarDate> dates;

  @override
  bool operator ==(Object other) =>
      other is DCalendarMultipleSelection && _sameDates(other.dates, dates);
  @override
  int get hashCode => Object.hashAll(dates);
}

@immutable
class DCalendarRangeSelection extends DCalendarSelection {
  const DCalendarRangeSelection(this.range);
  final DCalendarRange? range;

  @override
  bool operator ==(Object other) =>
      other is DCalendarRangeSelection && other.range == range;
  @override
  int get hashCode => range.hashCode;
}

bool _sameDates(List<DCalendarDate> a, List<DCalendarDate> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

enum DCalendarSelectionMode { single, multiple, range }

enum DCalendarCaptionLayout { label, dropdown }

enum DCalendarSelectReason { press, keyboard, controller }

typedef DCalendarPredicate = bool Function(DCalendarDate date);
typedef DCalendarSelectionChanged =
    void Function(DCalendarSelection selection, DCalendarSelectReason reason);
typedef DCalendarDayBuilder =
    Widget Function(
      BuildContext context,
      DCalendarDayDetails details,
      Widget defaultChild,
    );
typedef DCalendarDateStringBuilder =
    String Function(BuildContext context, DCalendarDate date);
typedef DCalendarMonthStringBuilder =
    String Function(BuildContext context, DCalendarDate month, bool short);

@immutable
class DCalendarLabels {
  const DCalendarLabels({
    this.calendar = 'Calendar',
    this.previousMonth = 'Previous month',
    this.nextMonth = 'Next month',
    this.chooseMonth = 'Choose month',
    this.chooseYear = 'Choose year',
    this.week = 'Week',
    this.booked = 'Booked',
  });
  final String calendar;
  final String previousMonth;
  final String nextMonth;
  final String chooseMonth;
  final String chooseYear;
  final String week;
  final String booked;
}

@immutable
class DCalendarDayDetails {
  const DCalendarDayDetails({
    required this.date,
    required this.outside,
    required this.today,
    required this.disabled,
    required this.hidden,
    required this.booked,
    required this.selected,
    required this.rangeStart,
    required this.rangeMiddle,
    required this.rangeEnd,
  });
  final DCalendarDate date;
  final bool outside;
  final bool today;
  final bool disabled;
  final bool hidden;
  final bool booked;
  final bool selected;
  final bool rangeStart;
  final bool rangeMiddle;
  final bool rangeEnd;
}

/// Imperative selection, focus and month ownership for [DCalendar].
///
/// This is distinct from kalender's event controller. [DCalendar] uses kalender
/// internally for its month paging and cell layout, while this controller keeps
/// the shadcn date-selection contract stable for Calendar and Date Picker.
class DCalendarController extends ChangeNotifier {
  factory DCalendarController({
    DCalendarSelection? selection,
    DCalendarDate? displayedMonth,
    DCalendarDate? focusedDate,
  }) => DCalendarController._(selection, displayedMonth, focusedDate);

  DCalendarController._(
    this._selection,
    this._displayedMonth,
    this._focusedDate,
  );

  DCalendarSelection? _selection;
  DCalendarDate? _displayedMonth;
  DCalendarDate? _focusedDate;
  DCalendarSelection? get selection => _selection;
  DCalendarDate? get displayedMonth => _displayedMonth;
  DCalendarDate? get focusedDate => _focusedDate;

  void setSelection(DCalendarSelection selection) {
    _selection = selection;
    notifyListeners();
  }

  void showMonth(DCalendarDate month) {
    _displayedMonth = DCalendarDate(month.year, month.month, 1);
    notifyListeners();
  }

  void focusDate(DCalendarDate date) {
    _focusedDate = date;
    notifyListeners();
  }

  /// Clears the current selection while preserving its selection mode.
  void clear() {
    _selection = switch (_selection) {
      DCalendarSingleSelection() => const DCalendarSingleSelection(null),
      DCalendarMultipleSelection() => DCalendarMultipleSelection(const []),
      DCalendarRangeSelection() => const DCalendarRangeSelection(null),
      null => null,
    };
    notifyListeners();
  }

  void _sync({
    DCalendarSelection? selection,
    DCalendarDate? displayedMonth,
    DCalendarDate? focusedDate,
  }) {
    if (selection != null) _selection = selection;
    if (displayedMonth != null) _displayedMonth = displayedMonth;
    if (focusedDate != null) _focusedDate = focusedDate;
  }
}

/// Applies shadcn semantic tokens to any kalender-backed calendar surface.
///
/// Event tiles and business-specific day builders remain caller-owned. This
/// theme gives the package grid, dates, week numbers, timelines and overlays a
/// live host palette/font/radius baseline.
class DKalenderTheme extends StatelessWidget {
  const DKalenderTheme({
    super.key,
    required this.child,
    this.compactMonthLayout = true,
  });
  final Widget child;
  final bool compactMonthLayout;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final label = textTheme.bodyMedium!.copyWith(
      fontSize: DiscourseTypography.sm,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: tokens.foreground,
    );
    final mutedLabel = label.copyWith(
      fontSize: DiscourseTypography.base * .8,
      height: 16 / 12.8,
      color: tokens.mutedForeground,
    );
    return kalender.KalenderTheme(
      data: kalender.KalenderThemeData(
        dayHeaderStyle: kalender.DayHeaderStyle(
          textStyle: mutedLabel,
          numberTextStyle: label,
        ),
        weekDayHeaderStyle: kalender.WeekDayHeaderStyle(
          textStyle: mutedLabel,
          padding: compactMonthLayout ? EdgeInsets.zero : null,
        ),
        monthDayHeaderStyle: kalender.MonthDayHeaderStyle(
          numberTextStyle: label,
          margin: compactMonthLayout ? EdgeInsets.zero : null,
        ),
        weekNumberStyle: kalender.WeekNumberStyle(
          textStyle: mutedLabel,
          buttonSize: compactMonthLayout ? const Size.square(28) : null,
          padding: compactMonthLayout ? EdgeInsets.zero : null,
          alignment: compactMonthLayout ? Alignment.topCenter : null,
        ),
        monthGridStyle: compactMonthLayout
            ? const kalender.MonthGridStyle(
                color: Colors.transparent,
                thickness: 0,
              )
            : null,
        hourLinesStyle: kalender.HourLinesStyle(
          color: tokens.border,
          thickness: 1,
        ),
        daySeparatorStyle: kalender.DaySeparatorStyle(
          color: tokens.border,
          width: 1,
        ),
        scheduleDateStyle: kalender.ScheduleDateStyle(
          textStyle: mutedLabel,
          numberTextStyle: label,
        ),
        scheduleTileHighlightStyle: kalender.ScheduleTileHighlightStyle(
          decoration: BoxDecoration(color: tokens.muted),
        ),
        multiDayOverlayStyle: kalender.MultiDayOverlayStyle(
          closeIcon: Icon(Icons.close, color: tokens.mutedForeground, size: 16),
          dateTextStyle: label,
          headerPadding: const EdgeInsets.all(8),
          eventsPadding: const EdgeInsets.all(4),
          eventPadding: const EdgeInsets.symmetric(vertical: 2),
        ),
        multiDayPortalOverlayButtonStyle:
            kalender.MultiDayPortalOverlayButtonStyle(
              textStyle: label,
              textPadding: const EdgeInsets.symmetric(horizontal: 4),
              textOverflow: TextOverflow.ellipsis,
            ),
      ),
      child: child,
    );
  }
}

/// A compact base-nova date-selection calendar powered by kalender 0.29.1.
///
/// Non-null [selection] and [displayedMonth] are controlled. Otherwise initial
/// values and the owned/borrowed [controller] drive state. Borrowed controllers
/// and focus nodes are never disposed. This widget owns inline day selection;
/// input and popover composition belongs to the Date Picker component.
///
/// Kalender 0.29.1 uses Gregorian [DateTime] pages. Localized Gregorian labels
/// and RTL are supported here. As with the official React example's engine
/// replacement, Persian/Hijri/Jalali chronology requires a kalender engine that
/// supplies that calendar math; relabeling Gregorian dates is intentionally not
/// presented as a correct alternate calendar.
class DCalendar extends StatefulWidget {
  const DCalendar({
    super.key,
    this.mode = DCalendarSelectionMode.single,
    this.selection,
    this.initialSelection,
    this.onSelectionChanged,
    this.displayedMonth,
    this.initialDisplayedMonth,
    this.onDisplayedMonthChanged,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.locale,
    this.location,
    this.labels = const DCalendarLabels(),
    this.captionLayout = DCalendarCaptionLayout.label,
    this.numberOfMonths = 1,
    this.showOutsideDays = true,
    this.fixedWeeks = false,
    this.showWeekNumbers = false,
    this.firstWeekday = DateTime.sunday,
    this.cellSize = 28,
    this.responsiveCellSize,
    this.startMonth,
    this.endMonth,
    this.disabled,
    this.hidden,
    this.booked,
    this.minRangeDays,
    this.maxRangeDays,
    this.excludeDisabledInRange = false,
    this.dayBuilder,
    this.weekNumberBuilder,
    this.dayNumberBuilder,
    this.weekdayLabelBuilder,
    this.monthLabelBuilder,
    this.yearLabelBuilder,
    this.dateSemanticLabelBuilder,
    this.today,
    this.bordered = false,
    this.padding = const EdgeInsets.all(8),
    this.semanticLabel,
  }) : assert(
         selection == null ||
             (mode == DCalendarSelectionMode.single &&
                 selection is DCalendarSingleSelection) ||
             (mode == DCalendarSelectionMode.multiple &&
                 selection is DCalendarMultipleSelection) ||
             (mode == DCalendarSelectionMode.range &&
                 selection is DCalendarRangeSelection),
         'selection must match mode',
       ),
       assert(
         initialSelection == null ||
             (mode == DCalendarSelectionMode.single &&
                 initialSelection is DCalendarSingleSelection) ||
             (mode == DCalendarSelectionMode.multiple &&
                 initialSelection is DCalendarMultipleSelection) ||
             (mode == DCalendarSelectionMode.range &&
                 initialSelection is DCalendarRangeSelection),
         'initialSelection must match mode',
       ),
       assert(numberOfMonths > 0),
       assert(cellSize >= 24),
       assert(
         firstWeekday >= DateTime.monday && firstWeekday <= DateTime.sunday,
       ),
       assert(minRangeDays == null || minRangeDays > 0),
       assert(maxRangeDays == null || maxRangeDays > 0),
       assert(
         minRangeDays == null ||
             maxRangeDays == null ||
             minRangeDays <= maxRangeDays,
       );

  final DCalendarSelectionMode mode;
  final DCalendarSelection? selection;
  final DCalendarSelection? initialSelection;
  final DCalendarSelectionChanged? onSelectionChanged;
  final DCalendarDate? displayedMonth;
  final DCalendarDate? initialDisplayedMonth;
  final ValueChanged<DCalendarDate>? onDisplayedMonthChanged;
  final DCalendarController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final Locale? locale;
  final tz.Location? location;
  final DCalendarLabels labels;
  final DCalendarCaptionLayout captionLayout;
  final int numberOfMonths;
  final bool showOutsideDays;
  final bool fixedWeeks;
  final bool showWeekNumbers;
  final int firstWeekday;
  final double cellSize;
  final double Function(double availableWidth)? responsiveCellSize;
  final DCalendarDate? startMonth;
  final DCalendarDate? endMonth;
  final DCalendarPredicate? disabled;
  final DCalendarPredicate? hidden;
  final DCalendarPredicate? booked;
  final int? minRangeDays;
  final int? maxRangeDays;
  final bool excludeDisabledInRange;
  final DCalendarDayBuilder? dayBuilder;
  final int Function(DCalendarDate weekStart)? weekNumberBuilder;
  final DCalendarDateStringBuilder? dayNumberBuilder;
  final DCalendarDateStringBuilder? weekdayLabelBuilder;
  final DCalendarMonthStringBuilder? monthLabelBuilder;
  final DCalendarDateStringBuilder? yearLabelBuilder;
  final DCalendarDateStringBuilder? dateSemanticLabelBuilder;
  final DCalendarDate? today;
  final bool bordered;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  State<DCalendar> createState() => _DCalendarState();
}

class _DCalendarState extends State<DCalendar> {
  static final _noInteraction = kalender.CalendarInteraction(
    allowEventCreation: false,
    allowRescheduling: false,
    allowResizing: false,
  );

  late DCalendarController _controller;
  late bool _ownsController;
  late FocusNode _rootFocus;
  late bool _ownsRootFocus;
  final List<kalender.CalendarController> _pageControllers = [];
  final List<kalender.DefaultEventsController> _eventsControllers = [];
  final Map<String, FocusNode> _dayFocusNodes = {};
  DCalendarSelection? _selection;
  late DCalendarDate _month;
  DCalendarDate? _focusedDate;
  bool _syncingPages = false;

  DCalendarSelection get _effectiveSelection =>
      widget.selection ?? _selection ?? _emptySelection;
  DCalendarSelection get _emptySelection => switch (widget.mode) {
    DCalendarSelectionMode.single => const DCalendarSingleSelection(null),
    DCalendarSelectionMode.multiple => DCalendarMultipleSelection(const []),
    DCalendarSelectionMode.range => const DCalendarRangeSelection(null),
  };

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
    _attachFocus(widget.focusNode);
    _selection =
        widget.selection ??
        widget.initialSelection ??
        _controller.selection ??
        _emptySelection;
    final anchor =
        widget.displayedMonth ??
        widget.initialDisplayedMonth ??
        _controller.displayedMonth ??
        _selectionAnchor(_selection!) ??
        _todayDate;
    _month = _clampDisplayedMonth(_monthStart(anchor));
    final requestedFocus = _controller.focusedDate;
    _focusedDate = requestedFocus ?? _selectionAnchor(_selection!);
    if (_focusedDate == null || !_isFocusableAndVisible(_focusedDate!)) {
      _focusedDate = _firstFocusableVisible();
    }
    _ensurePages();
    _controller._sync(
      selection: _selection,
      displayedMonth: _month,
      focusedDate: _focusedDate,
    );
    if (_focusedDate != null && (requestedFocus != null || widget.autofocus)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moveFocus(_focusedDate!);
      });
    }
  }

  void _attachController(DCalendarController? value) {
    _ownsController = value == null;
    _controller = value ?? DCalendarController();
    _controller.addListener(_controllerChanged);
  }

  void _attachFocus(FocusNode? value) {
    _ownsRootFocus = value == null;
    _rootFocus = value ?? FocusNode(debugLabel: 'DCalendar');
  }

  void _ensurePages() {
    while (_pageControllers.length < widget.numberOfMonths) {
      _pageControllers.add(kalender.CalendarController());
      _eventsControllers.add(kalender.DefaultEventsController());
    }
    while (_pageControllers.length > widget.numberOfMonths) {
      _pageControllers.removeLast().dispose();
      _eventsControllers.removeLast().dispose();
    }
  }

  @override
  void didUpdateWidget(DCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_controllerChanged);
      if (_ownsController) _controller.dispose();
      _attachController(widget.controller);
      if (widget.selection == null && _controller.selection != null) {
        _selection = _controller.selection;
      }
      if (widget.displayedMonth == null && _controller.displayedMonth != null) {
        _setMonth(_controller.displayedMonth!, notify: false);
      }
      if (_controller.focusedDate != null) {
        _focusedDate = _controller.focusedDate;
      }
    }
    if (oldWidget.focusNode != widget.focusNode) {
      if (_ownsRootFocus) _rootFocus.dispose();
      _attachFocus(widget.focusNode);
    }
    if (oldWidget.numberOfMonths != widget.numberOfMonths) _ensurePages();
    if (oldWidget.mode != widget.mode && widget.selection == null) {
      _selection = _emptySelection;
      _controller._sync(selection: _selection);
    }
    if (widget.selection != null) {
      _selection = widget.selection;
      _controller._sync(selection: widget.selection);
    }
    if (widget.displayedMonth != null &&
        widget.displayedMonth != oldWidget.displayedMonth) {
      _setMonth(widget.displayedMonth!, notify: false);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_controllerChanged);
    if (_ownsController) _controller.dispose();
    if (_ownsRootFocus) _rootFocus.dispose();
    for (final controller in _pageControllers) {
      controller.dispose();
    }
    for (final controller in _eventsControllers) {
      controller.dispose();
    }
    for (final node in _dayFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _controllerChanged() {
    if (!mounted) return;
    final nextSelection = _controller.selection;
    if (nextSelection != null && nextSelection != _selection) {
      if (widget.selection == null) _selection = nextSelection;
      widget.onSelectionChanged?.call(
        nextSelection,
        DCalendarSelectReason.controller,
      );
    }
    final nextMonth = _controller.displayedMonth;
    if (nextMonth != null &&
        (nextMonth.year != _month.year || nextMonth.month != _month.month)) {
      _setMonth(nextMonth);
    }
    final nextFocus = _controller.focusedDate;
    if (nextFocus != null && nextFocus != _focusedDate) {
      _moveFocus(nextFocus);
    }
    setState(() {});
  }

  DCalendarDate? _selectionAnchor(DCalendarSelection selection) =>
      switch (selection) {
        DCalendarSingleSelection(:final date) => date,
        DCalendarMultipleSelection(:final dates) =>
          dates.isEmpty ? null : dates.first,
        DCalendarRangeSelection(:final range) => range?.from,
      };

  DCalendarDate _monthStart(DCalendarDate date) =>
      DCalendarDate(date.year, date.month, 1);

  DCalendarDate get _todayDate {
    if (widget.today case final today?) return today;
    final now = widget.location == null
        ? DateTime.now()
        : tz.TZDateTime.now(widget.location!);
    return DCalendarDate.fromDateTime(now);
  }

  DCalendarDate _clampDisplayedMonth(DCalendarDate candidate) {
    var result = _monthStart(candidate);
    if (widget.startMonth case final start?) {
      final first = _monthStart(start);
      if (result.isBefore(first)) result = first;
    }
    if (widget.endMonth case final end?) {
      final lastBase = _monthStart(end).addMonths(1 - widget.numberOfMonths);
      if (result.isAfter(lastBase)) result = lastBase;
    }
    return result;
  }

  bool _outsideBounds(DCalendarDate date) {
    final month = _monthStart(date);
    return (widget.startMonth != null &&
            month.isBefore(_monthStart(widget.startMonth!))) ||
        (widget.endMonth != null &&
            month.isAfter(_monthStart(widget.endMonth!)));
  }

  bool _isDisabled(DCalendarDate date) =>
      _outsideBounds(date) || (widget.disabled?.call(date) ?? false);
  bool _isHidden(DCalendarDate date) => widget.hidden?.call(date) ?? false;

  void _setMonth(DCalendarDate value, {bool notify = true}) {
    final next = DCalendarDate(value.year, value.month, 1);
    if (!_canShow(next)) return;
    final changed = next != _month;
    if (widget.displayedMonth == null) setState(() => _month = next);
    _controller._sync(displayedMonth: next);
    _syncPages(next);
    if (changed && notify) widget.onDisplayedMonthChanged?.call(next);
  }

  bool _canShow(DCalendarDate month) {
    final candidate = _monthStart(month);
    final lastCandidate = candidate.addMonths(widget.numberOfMonths - 1);
    return !(widget.startMonth != null &&
            candidate.isBefore(_monthStart(widget.startMonth!))) &&
        !(widget.endMonth != null &&
            lastCandidate.isAfter(_monthStart(widget.endMonth!)));
  }

  bool _isVisible(DCalendarDate date) =>
      !date.isBefore(_month) &&
      date.isBefore(_month.addMonths(widget.numberOfMonths));

  bool _isFocusableAndVisible(DCalendarDate date) =>
      _isVisible(date) && !_isDisabled(date) && !_isHidden(date);

  DCalendarDate? _firstFocusableVisible() {
    final today = _todayDate;
    if (_isFocusableAndVisible(today)) return today;
    for (
      var date = _month;
      date.isBefore(_month.addMonths(widget.numberOfMonths));
      date = date.addDays(1)
    ) {
      if (!_isDisabled(date) && !_isHidden(date)) return date;
    }
    return null;
  }

  void _syncPages(DCalendarDate base) {
    _syncingPages = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (var i = 0; i < _pageControllers.length; i++) {
        final date = _externalDate(base.addMonths(i));
        _pageControllers[i].jumpToDate(date);
      }
      _syncingPages = false;
    });
  }

  void _pageChanged(int pane, DateTimeRange range) {
    if (_syncingPages) return;
    final midpoint = range.start.add(range.duration ~/ 2);
    final visible = DCalendarDate(midpoint.year, midpoint.month, 1);
    _setMonth(visible.addMonths(-pane));
  }

  void _select(DCalendarDate date, DCalendarSelectReason reason) {
    if (_isDisabled(date) || _isHidden(date)) return;
    final current = _effectiveSelection;
    final next = switch (widget.mode) {
      DCalendarSelectionMode.single => DCalendarSingleSelection(
        current is DCalendarSingleSelection && current.date == date
            ? null
            : date,
      ),
      DCalendarSelectionMode.multiple => _toggleMultiple(current, date),
      DCalendarSelectionMode.range => _extendRange(current, date),
    };
    if (widget.selection == null) _selection = next;
    _focusedDate = date;
    _controller._sync(selection: next, focusedDate: date);
    widget.onSelectionChanged?.call(next, reason);
    setState(() {});
  }

  DCalendarMultipleSelection _toggleMultiple(
    DCalendarSelection current,
    DCalendarDate date,
  ) {
    final dates = current is DCalendarMultipleSelection
        ? [...current.dates]
        : <DCalendarDate>[];
    dates.contains(date) ? dates.remove(date) : dates.add(date);
    return DCalendarMultipleSelection(dates);
  }

  DCalendarRangeSelection _extendRange(
    DCalendarSelection current,
    DCalendarDate date,
  ) {
    final range = current is DCalendarRangeSelection ? current.range : null;
    if (range == null || range.to != null) {
      return DCalendarRangeSelection(DCalendarRange(from: date));
    }
    final candidate = date.isBefore(range.from)
        ? DCalendarRange(from: date, to: range.from)
        : DCalendarRange(from: range.from, to: date);
    final length = candidate.lengthInDays!;
    if (widget.minRangeDays != null && length < widget.minRangeDays!) {
      return DCalendarRangeSelection(range);
    }
    if (widget.maxRangeDays != null && length > widget.maxRangeDays!) {
      return DCalendarRangeSelection(range);
    }
    if (widget.excludeDisabledInRange) {
      for (
        var cursor = candidate.from;
        !cursor.isAfter(candidate.to!);
        cursor = cursor.addDays(1)
      ) {
        if (_isDisabled(cursor)) return DCalendarRangeSelection(range);
      }
    }
    return DCalendarRangeSelection(candidate);
  }

  void _moveFocus(DCalendarDate requested) {
    var date = requested;
    final step = requested.isBefore(_focusedDate ?? requested) ? -1 : 1;
    for (var i = 0; i < 370 && (_isDisabled(date) || _isHidden(date)); i++) {
      date = date.addDays(step);
    }
    if (_outsideBounds(date)) return;
    final lastVisible = _month.addMonths(widget.numberOfMonths);
    if (date.isBefore(_month) || !date.isBefore(lastVisible)) {
      _setMonth(DCalendarDate(date.year, date.month, 1));
    }
    setState(() => _focusedDate = date);
    _controller._sync(focusedDate: date);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pane = ((date.year - _month.year) * 12 + date.month - _month.month)
          .clamp(0, widget.numberOfMonths - 1);
      _dayFocusNodes['$pane:$date']?.requestFocus();
    });
  }

  KeyEventResult _onDayKey(DCalendarDate current, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    DCalendarDate? target;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      target = current.addDays(rtl ? -1 : 1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      target = current.addDays(rtl ? 1 : -1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      target = current.addDays(7);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      target = current.addDays(-7);
    } else if (event.logicalKey == LogicalKeyboardKey.home) {
      target = current.addDays(
        -((current.weekday - widget.firstWeekday + 7) % 7),
      );
    } else if (event.logicalKey == LogicalKeyboardKey.end) {
      target = current.addDays(
        6 - ((current.weekday - widget.firstWeekday + 7) % 7),
      );
    } else if (event.logicalKey == LogicalKeyboardKey.pageUp ||
        event.logicalKey == LogicalKeyboardKey.pageDown) {
      final sign = event.logicalKey == LogicalKeyboardKey.pageUp ? -1 : 1;
      target = current.addMonths(
        HardwareKeyboard.instance.isShiftPressed ? sign * 12 : sign,
      );
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _select(_focusedDate ?? current, DCalendarSelectReason.keyboard);
      return KeyEventResult.handled;
    }
    if (target == null) return KeyEventResult.ignored;
    _moveFocus(target);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Semantics(
      container: true,
      label: widget.semanticLabel ?? widget.labels.calendar,
      child: Focus(
        focusNode: _rootFocus,
        skipTraversal: true,
        onFocusChange: (focused) {
          if (focused && _rootFocus.hasPrimaryFocus) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _focusedDate != null) {
                _moveFocus(_focusedDate!);
              }
            });
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cell = _effectiveCellSize(context, constraints.maxWidth);
            final monthWidth = cell * (7 + (widget.showWeekNumbers ? 1 : 0));
            final horizontal =
                widget.numberOfMonths > 1 &&
                constraints.maxWidth >=
                    widget.numberOfMonths * monthWidth +
                        (widget.numberOfMonths - 1) * 16 +
                        16;
            final content = Flex(
              direction: horizontal ? Axis.horizontal : Axis.vertical,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var pane = 0; pane < widget.numberOfMonths; pane++) ...[
                  if (pane > 0)
                    SizedBox(
                      width: horizontal ? 16 : 0,
                      height: horizontal ? 0 : 16,
                    ),
                  _monthPane(pane, cell, monthWidth),
                ],
              ],
            );
            return DKalenderTheme(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.background,
                  borderRadius: BorderRadius.circular(tokens.radius * .8),
                  border: widget.bordered
                      ? Border.all(color: tokens.border)
                      : null,
                ),
                child: Padding(
                  padding: widget.padding,
                  child: Stack(
                    children: [
                      content,
                      PositionedDirectional(
                        top: 0,
                        start: 0,
                        child: _navigationButton(previous: true),
                      ),
                      PositionedDirectional(
                        top: 0,
                        end: 0,
                        child: _navigationButton(previous: false),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  double _effectiveCellSize(BuildContext context, double width) {
    var value = widget.responsiveCellSize?.call(width) ?? widget.cellSize;
    value = math.max(
      value,
      MediaQuery.textScalerOf(context).scale(DiscourseTypography.sm) + 12,
    );
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.android) {
      value = math.max(value, DSpacing.touchTarget);
    }
    return value;
  }

  Widget _navigationButton({required bool previous}) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final delta = previous ? -1 : 1;
    final enabled = _canShow(
      _month.addMonths(previous ? -1 : widget.numberOfMonths),
    );
    return DButton.iconOnly(
      icon: DIcon(
        (previous != rtl) ? DIcons.chevronLeft : DIcons.chevronRight,
        size: 16,
      ),
      tooltip: previous ? widget.labels.previousMonth : widget.labels.nextMonth,
      semanticLabel: previous
          ? widget.labels.previousMonth
          : widget.labels.nextMonth,
      variant: DButtonVariant.ghost,
      size: DButtonSize.small,
      onPressed: enabled ? () => _setMonth(_month.addMonths(delta)) : null,
    );
  }

  Widget _monthPane(int pane, double cell, double width) {
    final month = _month.addMonths(pane);
    final rows = widget.fixedWeeks ? 6 : _rowsInMonth(month);
    final laneHeight = cell + 8;
    final configuration = kalender.MonthViewConfiguration(
      name: 'DCalendar-$pane',
      initialDateTime: _externalDate(month),
      firstDayOfWeek: widget.firstWeekday,
      showWeekNumbers: widget.showWeekNumbers,
      pageIndexCalculator: _DMonthIndexCalculator(
        dateTimeRange: _displayRange,
        firstDayOfWeek: widget.firstWeekday,
        fixedWeeks: widget.fixedWeeks,
      ),
    );
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: cell,
            child: Center(child: _caption(month)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: cell + rows * laneHeight,
            child: kalender.KalenderView(
              eventsController: _eventsControllers[pane],
              calendarController: _pageControllers[pane],
              viewConfiguration: configuration,
              locale: widget.locale ?? Localizations.localeOf(context),
              location: widget.location,
              callbacks: kalender.CalendarCallbacks(
                onPageChanged: (range) => _pageChanged(pane, range),
                onTapped: (date) => _select(
                  DCalendarDate.fromDateTime(date),
                  DCalendarSelectReason.press,
                ),
              ),
              components: _components(pane, month, cell),
              header: SizedBox(
                height: cell,
                child: const kalender.CalendarHeader(),
              ),
              body: kalender.CalendarBody(interaction: _noInteraction),
            ),
          ),
        ],
      ),
    );
  }

  DateTimeRange get _displayRange => DateTimeRange(
    start: _monthStart(
      widget.startMonth ?? DCalendarDate(1900, 1, 1),
    ).dateTimeUtc,
    end: _monthStart(
      widget.endMonth ?? DCalendarDate(2200, 12, 1),
    ).addMonths(1).dateTimeUtc,
  );

  DateTime _externalDate(DCalendarDate date) => widget.location == null
      ? DateTime(date.year, date.month, date.day, 12)
      : date.atTime(widget.location!, hour: 12);

  int _rowsInMonth(DCalendarDate month) {
    final leading = (month.weekday - widget.firstWeekday + 7) % 7;
    final days = DateTime.utc(month.year, month.month + 1, 0).day;
    return ((leading + days) / 7).ceil();
  }

  kalender.CalendarComponents _components(
    int pane,
    DCalendarDate month,
    double cell,
  ) => kalender.CalendarComponents(
    monthComponents: kalender.MonthComponents(
      headerComponents: kalender.MonthHeaderComponents(
        weekDayHeaderBuilder: (context, date) => SizedBox(
          height: cell,
          child: Center(
            child: Text(
              _weekdayLabel(context, date),
              maxLines: 1,
              style: TextStyle(
                fontSize: DiscourseTypography.base * .8,
                height: 16 / 12.8,
                color: DTokens.of(context).mutedForeground,
              ),
            ),
          ),
        ),
      ),
      bodyComponents: kalender.MonthBodyComponents(
        monthGridBuilder: (_, rows) => kalender.MonthGrid(
          numberOfRows: rows,
          style: const kalender.MonthGridStyle(
            color: Colors.transparent,
            thickness: 0,
          ),
        ),
        monthDayHeaderBuilder: (context, date) =>
            _dayButton(context, pane, month, date, cell),
        monthDayCellBuilder: (context, details) =>
            _dayBackground(context, month, details, cell),
        weekNumberWidth: (_) => cell,
        weekNumberBuilder: (context, range) {
          final number =
              widget.weekNumberBuilder?.call(
                DCalendarDate.fromDateTime(range.start),
              ) ??
              _isoWeek(DCalendarDate.fromDateTime(range.start));
          return Semantics(
            container: true,
            label: '${widget.labels.week} $number',
            excludeSemantics: true,
            child: SizedBox(
              width: cell,
              height: cell,
              child: Center(
                child: Text(
                  '$number',
                  style: TextStyle(
                    fontSize: DiscourseTypography.base * .8,
                    color: DTokens.of(context).mutedForeground,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  String _weekdayLabel(BuildContext context, DateTime date) {
    final calendarDate = DCalendarDate.fromDateTime(date);
    if (widget.weekdayLabelBuilder case final builder?) {
      return builder(context, calendarDate);
    }
    final locale = (widget.locale ?? Localizations.localeOf(context))
        .toLanguageTag();
    return DateFormat.E(locale).format(date).characters.take(2).toString();
  }

  Widget _caption(DCalendarDate month) {
    final locale = (widget.locale ?? Localizations.localeOf(context))
        .toLanguageTag();
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: DiscourseTypography.sm,
      height: 20 / 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      color: DTokens.of(context).foreground,
    );
    if (widget.captionLayout == DCalendarCaptionLayout.label) {
      return Text(
        widget.monthLabelBuilder?.call(context, month, false) ??
            DateFormat.yMMMM(locale).format(month.dateTimeUtc),
        style: style,
      );
    }
    final startYear = widget.startMonth?.year ?? month.year - 100;
    final endYear = widget.endMonth?.year ?? month.year + 100;
    return DefaultTextStyle(
      style: style,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DSelect<int>.controlled(
            entries: [
              for (var value = 1; value <= 12; value++)
                DSelectOption<int>(
                  value: value,
                  label:
                      widget.monthLabelBuilder?.call(
                        context,
                        DCalendarDate(month.year, value, 1),
                        true,
                      ) ??
                      DateFormat.MMM(locale).format(DateTime.utc(2024, value)),
                  child: Text(
                    widget.monthLabelBuilder?.call(
                          context,
                          DCalendarDate(month.year, value, 1),
                          true,
                        ) ??
                        DateFormat.MMM(
                          locale,
                        ).format(DateTime.utc(2024, value)),
                  ),
                ),
            ],
            value: month.month,
            onChanged: (value) {
              if (value != null) _setMonth(DCalendarDate(month.year, value, 1));
            },
            semanticLabel: widget.labels.chooseMonth,
            size: DSelectSize.small,
            width: 72,
          ),
          const SizedBox(width: 6),
          DSelect<int>.controlled(
            entries: [
              for (var year = startYear; year <= endYear; year++)
                DSelectOption<int>(
                  value: year,
                  label:
                      widget.yearLabelBuilder?.call(
                        context,
                        DCalendarDate(year, 1, 1),
                      ) ??
                      '$year',
                  child: Text(
                    widget.yearLabelBuilder?.call(
                          context,
                          DCalendarDate(year, 1, 1),
                        ) ??
                        '$year',
                  ),
                ),
            ],
            value: month.year,
            onChanged: (value) {
              if (value != null) {
                _setMonth(DCalendarDate(value, month.month, 1));
              }
            },
            semanticLabel: widget.labels.chooseYear,
            size: DSelectSize.small,
            width: 84,
          ),
        ],
      ),
    );
  }

  Widget _dayBackground(
    BuildContext context,
    DCalendarDate month,
    kalender.MonthDayCellDetails packageDetails,
    double cell,
  ) {
    final date = DCalendarDate.fromDateTime(packageDetails.date);
    final details = _details(
      month,
      date,
      widget.today == null ? packageDetails.isToday : date == widget.today,
    );
    if (details.hidden || (details.outside && !widget.showOutsideDays)) {
      return const SizedBox.shrink();
    }
    final tokens = DTokens.of(context);
    final fill = details.rangeMiddle || details.rangeStart || details.rangeEnd
        ? tokens.muted
        : details.today && !details.selected
        ? tokens.muted
        : Colors.transparent;
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: cell,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadiusDirectional.only(
              topStart: Radius.circular(
                details.rangeMiddle || details.rangeEnd
                    ? 0
                    : tokens.radius * .8,
              ),
              bottomStart: Radius.circular(
                details.rangeMiddle || details.rangeEnd
                    ? 0
                    : tokens.radius * .8,
              ),
              topEnd: Radius.circular(
                details.rangeMiddle || details.rangeStart
                    ? 0
                    : tokens.radius * .8,
              ),
              bottomEnd: Radius.circular(
                details.rangeMiddle || details.rangeStart
                    ? 0
                    : tokens.radius * .8,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dayButton(
    BuildContext context,
    int pane,
    DCalendarDate month,
    DateTime rawDate,
    double cell,
  ) {
    final date = DCalendarDate.fromDateTime(rawDate);
    final details = _details(month, date, date == _todayDate);
    if (details.hidden || (details.outside && !widget.showOutsideDays)) {
      return SizedBox(height: cell);
    }
    final key = '$pane:$date';
    final focusNode = _dayFocusNodes.putIfAbsent(
      key,
      () => FocusNode(debugLabel: 'DCalendar $date'),
    );
    focusNode.skipTraversal =
        details.outside || details.disabled || date != _focusedDate;
    final locale = (widget.locale ?? Localizations.localeOf(context))
        .toLanguageTag();
    final defaultChild = Text(
      widget.dayNumberBuilder?.call(context, date) ?? '${date.day}',
    );
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: cell,
        child: DCalendarDayButton(
          details: details,
          focusNode: focusNode,
          semanticLabel:
              widget.dateSemanticLabelBuilder?.call(context, date) ??
              DateFormat.yMMMMEEEEd(locale).format(rawDate),
          bookedLabel: widget.labels.booked,
          onPressed: details.disabled
              ? null
              : () => _select(date, DCalendarSelectReason.press),
          onFocused: () {
            _focusedDate = date;
            _controller._sync(focusedDate: date);
          },
          onKeyEvent: (event) => _onDayKey(date, event),
          child:
              widget.dayBuilder?.call(context, details, defaultChild) ??
              defaultChild,
        ),
      ),
    );
  }

  DCalendarDayDetails _details(
    DCalendarDate month,
    DCalendarDate date,
    bool isToday,
  ) {
    final outside = date.year != month.year || date.month != month.month;
    final range = _effectiveSelection is DCalendarRangeSelection
        ? (_effectiveSelection as DCalendarRangeSelection).range
        : null;
    return DCalendarDayDetails(
      date: date,
      outside: outside,
      today: isToday,
      disabled: _isDisabled(date),
      hidden: _isHidden(date),
      booked: widget.booked?.call(date) ?? false,
      selected: _isSelected(date),
      rangeStart: range?.from == date,
      rangeMiddle:
          range?.to != null &&
          date.isAfter(range!.from) &&
          date.isBefore(range.to!),
      rangeEnd: range?.to == date,
    );
  }

  bool _isSelected(DCalendarDate target) => switch (_effectiveSelection) {
    DCalendarSingleSelection(:final date) => date == target,
    DCalendarMultipleSelection(:final dates) => dates.contains(target),
    DCalendarRangeSelection(:final range) => range?.contains(target) ?? false,
  };

  int _isoWeek(DCalendarDate date) {
    final thursday = date.addDays(DateTime.thursday - date.weekday);
    final first = DCalendarDate(thursday.year, 1, 4);
    final firstThursday = first.addDays(DateTime.thursday - first.weekday);
    return 1 +
        thursday.dateTimeUtc.difference(firstThursday.dateTimeUtc).inDays ~/ 7;
  }
}

/// Public shadcn day-cell presentation, reusable by real kalender event views.
class DCalendarDayButton extends StatefulWidget {
  const DCalendarDayButton({
    super.key,
    required this.details,
    required this.semanticLabel,
    required this.onPressed,
    required this.child,
    this.focusNode,
    this.bookedLabel = 'Booked',
    this.onFocused,
    this.onKeyEvent,
  });
  final DCalendarDayDetails details;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final Widget child;
  final FocusNode? focusNode;
  final String bookedLabel;
  final VoidCallback? onFocused;
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;

  @override
  State<DCalendarDayButton> createState() => _DCalendarDayButtonState();
}

class _DCalendarDayButtonState extends State<DCalendarDayButton> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  void didUpdateWidget(DCalendarDayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPressed == null && oldWidget.onPressed != null) {
      _hovered = false;
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final details = widget.details;
    final endpoint = details.rangeStart || details.rangeEnd;
    final single =
        details.selected &&
        !details.rangeStart &&
        !details.rangeMiddle &&
        !details.rangeEnd;
    var background = Colors.transparent;
    var foreground = tokens.foreground;
    if (single || endpoint) {
      background = tokens.primary;
      foreground = tokens.primaryForeground;
    } else if (_hovered || _pressed) {
      background = tokens.muted;
    }
    if (details.outside && !details.selected) {
      foreground = tokens.mutedForeground;
    }
    if (details.disabled) {
      foreground = foreground.withValues(alpha: foreground.a * .5);
    }
    final radius = BorderRadiusDirectional.only(
      topStart: Radius.circular(
        details.rangeMiddle || details.rangeEnd ? 0 : tokens.radius * .8,
      ),
      bottomStart: Radius.circular(
        details.rangeMiddle || details.rangeEnd ? 0 : tokens.radius * .8,
      ),
      topEnd: Radius.circular(
        details.rangeMiddle || details.rangeStart ? 0 : tokens.radius * .8,
      ),
      bottomEnd: Radius.circular(
        details.rangeMiddle || details.rangeStart ? 0 : tokens.radius * .8,
      ),
    );
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: DiscourseTypography.sm,
      height: 1,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: foreground,
      decoration: details.booked ? TextDecoration.lineThrough : null,
    );
    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      selected: details.selected,
      label: widget.semanticLabel,
      hint: details.booked ? widget.bookedLabel : null,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: Focus(
        focusNode: widget.focusNode,
        canRequestFocus: widget.onPressed != null,
        onFocusChange: (value) {
          setState(() => _focused = value);
          if (value) widget.onFocused?.call();
        },
        onKeyEvent: (_, event) =>
            widget.onKeyEvent?.call(event) ?? KeyEventResult.ignored,
        child: MouseRegion(
          cursor: widget.onPressed == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onEnter: widget.onPressed == null
              ? null
              : (_) => setState(() => _hovered = true),
          onExit: widget.onPressed == null
              ? null
              : (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed == null
                ? null
                : () {
                    widget.focusNode?.requestFocus();
                    widget.onPressed!();
                  },
            onTapDown: widget.onPressed == null
                ? null
                : (_) => setState(() => _pressed = true),
            onTapCancel: widget.onPressed == null
                ? null
                : () => setState(() => _pressed = false),
            onTapUp: widget.onPressed == null
                ? null
                : (_) => setState(() => _pressed = false),
            child: AnimatedContainer(
              duration: DMotion.duration(context, DMotion.exit),
              decoration: BoxDecoration(
                color: background,
                borderRadius: radius,
              ),
              foregroundDecoration: _CalendarFocusRingDecoration(
                color: _focused
                    ? tokens.focusRing.withValues(
                        alpha: tokens.focusRing.a * .5,
                      )
                    : tokens.focusRing.withValues(alpha: 0),
                radius: radius,
              ),
              child: DefaultTextStyle(
                style: style,
                textAlign: TextAlign.center,
                child: Center(child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints only outside the day surface so the ring cannot tint its fill.
class _CalendarFocusRingDecoration extends Decoration {
  const _CalendarFocusRingDecoration({
    required this.color,
    required this.radius,
  });

  final Color color;
  final BorderRadiusGeometry radius;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _CalendarFocusRingPainter(this);

  @override
  Decoration? lerpFrom(Decoration? a, double t) =>
      a is _CalendarFocusRingDecoration
      ? _CalendarFocusRingDecoration(
          color: Color.lerp(a.color, color, t)!,
          radius: BorderRadiusGeometry.lerp(a.radius, radius, t)!,
        )
      : super.lerpFrom(a, t);

  @override
  Decoration? lerpTo(Decoration? b, double t) =>
      b is _CalendarFocusRingDecoration
      ? _CalendarFocusRingDecoration(
          color: Color.lerp(color, b.color, t)!,
          radius: BorderRadiusGeometry.lerp(radius, b.radius, t)!,
        )
      : super.lerpTo(b, t);
}

class _CalendarFocusRingPainter extends BoxPainter {
  _CalendarFocusRingPainter(this.decoration);

  final _CalendarFocusRingDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final direction = configuration.textDirection ?? TextDirection.ltr;
    final inner = decoration.radius
        .resolve(direction)
        .toRRect(offset & configuration.size!);
    canvas.drawDRRect(
      inner.inflate(3),
      inner,
      Paint()..color = decoration.color,
    );
  }
}

class _DMonthIndexCalculator extends kalender.MonthIndexCalculator {
  _DMonthIndexCalculator({
    required super.dateTimeRange,
    required super.firstDayOfWeek,
    required this.fixedWeeks,
  });
  final bool fixedWeeks;

  @override
  kalender_ext.InternalDateTimeRange dateTimeRangeFromIndex(
    int index,
    tz.Location? location,
  ) {
    if (!fixedWeeks) return super.dateTimeRangeFromIndex(index, location);
    final month = monthStartFromIndex(index, location);
    var start = month.startOfWeek(firstDayOfWeek: firstDayOfWeek);
    if (start.isAfter(month)) start = start.subtract(const Duration(days: 7));
    return kalender_ext.InternalDateTimeRange(
      start: start,
      end: start.add(const Duration(days: 42)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _DMonthIndexCalculator &&
      other.dateTimeRange == dateTimeRange &&
      other.firstDayOfWeek == firstDayOfWeek &&
      other.fixedWeeks == fixedWeeks;

  @override
  int get hashCode => Object.hash(
    _DMonthIndexCalculator,
    dateTimeRange,
    firstDayOfWeek,
    fixedWeeks,
  );
}
