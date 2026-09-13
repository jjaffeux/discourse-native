import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:kalender/kalender.dart' as kalender;
import 'package:timezone/timezone.dart' as tz;

import '../../plugin_api/timezone_host.dart';
import '../../theme/discourse_typography.dart';
import 'topic_calendar_data.dart';
import 'topic_calendar_event.dart';

/// A Kalender view of the first post's server-maintained reply dates.
final class TopicCalendar extends StatefulWidget {
  const TopicCalendar({
    super.key,
    required this.data,
    required this.options,
    required this.zones,
    required this.onOpenReply,
    required this.onOpenWeb,
    this.settings = const TopicCalendarSettings(),
    this.accountTimezone,
    this.now,
  });

  final TopicCalendarData data;
  final TopicCalendarOptions options;
  final TopicCalendarSettings settings;
  final PluginTimezoneHost zones;
  final String? accountTimezone;
  final ValueChanged<int> onOpenReply;
  final VoidCallback onOpenWeb;
  final DateTime? now;

  @override
  State<TopicCalendar> createState() => _TopicCalendarState();
}

enum _CalendarView {
  month('Month'),
  week('Week'),
  day('Day'),
  agenda('Agenda');

  const _CalendarView(this.label);
  final String label;
}

final class _TopicCalendarState extends State<TopicCalendar> {
  static final _localeData = initializeDateFormatting();
  final _calendar = kalender.CalendarController();
  final _events = kalender.DefaultEventsController();
  late kalender.ViewConfiguration _configuration;
  late DateTime _focus;
  late DateTimeRange _loadedRange;
  DateTimeRange? _visibleRange;
  List<CalendarOccurrence> _occurrences = const [];
  _CalendarView _view = _CalendarView.month;
  String? _selectedTimezone;
  late String _loadedTimezone;
  bool _rangeUpdateScheduled = false;

  final _interaction = kalender.CalendarInteraction(
    allowEventCreation: false,
    allowRescheduling: false,
    allowResizing: false,
  );

  @override
  void initState() {
    super.initState();
    // The local intl initializer installs its date tables synchronously.
    unawaited(_localeData);
    _focus = _today;
    _configuration = _viewConfiguration();
    _refreshEvents();
    _calendar.visibleDateTimeRange.addListener(_scheduleRangeUpdate);
  }

  @override
  void didUpdateWidget(covariant TopicCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_loadedTimezone != _timezone ||
        oldWidget.settings.firstDay != widget.settings.firstDay) {
      _configuration = _viewConfiguration();
    }
    if (oldWidget.data != widget.data ||
        oldWidget.options.fullDay != widget.options.fullDay ||
        oldWidget.settings != widget.settings ||
        _loadedTimezone != _timezone) {
      _refreshEvents();
    }
  }

  @override
  void dispose() {
    _calendar.visibleDateTimeRange.removeListener(_scheduleRangeUpdate);
    _calendar.dispose();
    _events.dispose();
    super.dispose();
  }

  String get _timezone {
    final configured = _selectedTimezone ?? widget.options.timezone;
    return widget.zones.location(configured) != null
        ? configured!
        : widget.zones.readerTimezone(widget.accountTimezone);
  }

  tz.Location get _location => widget.zones.location(_timezone)!;

  DateTime _now() => widget.now ?? DateTime.now();

  DateTime get _today =>
      topicCalendarDay(tz.TZDateTime.from(_now(), _location));

  DateTime _inCalendar(DateTime day) =>
      tz.TZDateTime(_location, day.year, day.month, day.day);

  kalender.ViewConfiguration _viewConfiguration() {
    final firstDay = widget.settings.firstDay == 0
        ? DateTime.sunday
        : widget.settings.firstDay;
    // Kalender's default navigation window is only a few years. Topic calendars
    // can contain much older posts; give them a wider navigation window.
    final displayRange = DateTimeRange(
      start: _inCalendar(DateTime.utc(1900)),
      end: _inCalendar(DateTime.utc(2200)),
    );
    return switch (_view) {
      _CalendarView.month => kalender.MonthViewConfiguration.singleMonth(
        initialDateTime: _inCalendar(_focus),
        nowCallback: _now,
        firstDayOfWeek: firstDay,
        displayRange: displayRange,
      ),
      _CalendarView.week => kalender.MultiDayViewConfiguration.week(
        initialDateTime: _inCalendar(_focus),
        nowCallback: _now,
        firstDayOfWeek: firstDay,
        initialTimeOfDay: const TimeOfDay(hour: 8, minute: 0),
        displayRange: displayRange,
      ),
      _CalendarView.day => kalender.MultiDayViewConfiguration.singleDay(
        initialDateTime: _inCalendar(_focus),
        nowCallback: _now,
        initialTimeOfDay: const TimeOfDay(hour: 8, minute: 0),
        displayRange: displayRange,
      ),
      _CalendarView.agenda => kalender.ScheduleViewConfiguration.paginated(
        name: 'Agenda',
        initialDateTime: _inCalendar(_focus),
        nowCallback: _now,
        displayRange: displayRange,
      ),
    };
  }

  void _refreshEvents() {
    _loadedTimezone = _timezone;
    // Include neighboring pages for swiping, while keeping recurrence expansion
    // bounded even for topics with years of history.
    _loadedRange = DateTimeRange(
      start: DateTime.utc(_focus.year, _focus.month - 1, -7),
      end: DateTime.utc(_focus.year, _focus.month + 2, 8),
    );
    _occurrences = calendarOccurrences(
      widget.data,
      widget.options,
      zones: widget.zones,
      timezone: _timezone,
      from: _loadedRange.start,
      until: _loadedRange.end,
      holidayCalendar: widget.settings.holidayTopicId == widget.data.topicId,
    );
    _events.replaceEvents([
      for (var index = 0; index < _occurrences.length; index++)
        TopicCalendarEvent(
          id: '${widget.data.topicId}:$index:${_occurrences[index].start}',
          occurrence: _occurrences[index],
          location: _location,
        ),
    ]);
  }

  void _scheduleRangeUpdate() {
    if (_rangeUpdateScheduled) return;
    _rangeUpdateScheduled = true;
    // Kalender publishes its range during controller attachment and layout.
    // Update the enclosing post only once that frame has finished.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rangeUpdateScheduled = false;
      if (!mounted) return;
      final range = _calendar.visibleDateTimeRange.value;
      if (range == null) return;
      final days = DateTimeRange(
        start: topicCalendarDay(range.start),
        end: topicCalendarDay(range.end),
      );
      if (days == _visibleRange) return;
      setState(() {
        _visibleRange = days;
        if (_view == _CalendarView.month || _view == _CalendarView.agenda) {
          final middle = days.start.add(days.duration ~/ 2);
          if (_focus.year != middle.year || _focus.month != middle.month) {
            _focus = DateTime.utc(middle.year, middle.month);
          }
        } else if (_focus.isBefore(days.start) || !_focus.isBefore(days.end)) {
          _focus = days.start;
        }
        if (days.start.isBefore(_loadedRange.start) ||
            days.end.isAfter(_loadedRange.end)) {
          _refreshEvents();
        }
      });
    });
  }

  void _switchView(_CalendarView view) {
    if (view == _view) return;
    setState(() {
      _view = view;
      _visibleRange = null;
      _configuration = _viewConfiguration();
    });
  }

  Future<void> _pickTimezone() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => _TimezonePicker(
        names: widget.zones.timezoneNames().toList()..sort(),
        selected: _timezone,
      ),
    );
    if (mounted && selected != null) {
      setState(() {
        _selectedTimezone = selected;
        _configuration = _viewConfiguration();
        _refreshEvents();
      });
    }
  }

  Future<void> _goToday() async {
    final today = _today;
    await _calendar.animateToDate(_inCalendar(today));
    if (mounted) setState(() => _focus = today);
  }

  String get _locale => Localizations.localeOf(context).toString();

  String _dateLabel(CalendarOccurrence event) {
    final date = DateFormat.yMMMd(_locale);
    if (event.allDay) {
      final end = event.lastDay == event.firstDay
          ? ''
          : ' – ${date.format(event.lastDay)}';
      return '${date.format(event.start)}$end · All day';
    }
    final time = DateFormat.Hm(_locale);
    final endDay = topicCalendarDay(event.end) == event.firstDay
        ? ''
        : '${date.format(event.end)}, ';
    return '${date.format(event.start)}, ${time.format(event.start)}'
        ' – $endDay${time.format(event.end)} ($_timezone)';
  }

  void _openDay(DateTime day, List<CalendarOccurrence> events) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(DateFormat.yMMMMEEEEd(_locale).format(day)),
          content: SizedBox(
            width: 480,
            child: events.isEmpty
                ? const Text('No calendar entries for this day.')
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final event in events)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.title,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                Text(_dateLabel(event)),
                                if (event.description.isNotEmpty &&
                                    event.description != event.title)
                                  Text(event.description),
                                if (event.postNumber case final number?)
                                  DButton(
                                    variant: DButtonVariant.link,
                                    onPressed: () {
                                      Navigator.pop(context);
                                      widget.onOpenReply(number);
                                    },
                                    label: Text('View reply #$number'),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            DButton(
              variant: DButtonVariant.ghost,
              onPressed: () => Navigator.pop(context),
              label: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  String get _periodLabel => switch (_view) {
    _CalendarView.day => DateFormat.yMMMd(_locale).format(_focus),
    _CalendarView.week when _visibleRange != null =>
      '${DateFormat.MMMd(_locale).format(_visibleRange!.start)} – '
          '${DateFormat.yMMMd(_locale).format(_visibleRange!.end.subtract(const Duration(days: 1)))}',
    _ => DateFormat.yMMMM(_locale).format(_focus),
  };

  List<CalendarOccurrence> _eventsOn(DateTime day) =>
      _occurrences.where((event) => event.includes(day)).toList();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hiddenDays = widget.options.hiddenDays;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hiddenDays.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                hiddenDays.length == 7
                    ? 'All weekdays are hidden in this calendar.'
                    : 'Open the web calendar to view its configured weekdays.',
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        _periodLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  DTooltip(
                    message:
                        'Previous ${_view == _CalendarView.agenda ? 'month' : _view.label.toLowerCase()}',
                    labelTrigger: true,
                    child: IconButton(
                      tooltip: '',
                      onPressed: () =>
                          unawaited(_calendar.animateToPreviousPage()),
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ),
                  DTooltip(
                    message:
                        'Next ${_view == _CalendarView.agenda ? 'month' : _view.label.toLowerCase()}',
                    labelTrigger: true,
                    child: IconButton(
                      tooltip: '',
                      onPressed: () => unawaited(_calendar.animateToNextPage()),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DButton(
                    variant: DButtonVariant.outline,
                    onPressed: _goToday,
                    label: const Text('Today'),
                  ),
                  DTooltip(
                    message: 'Calendar view',
                    labelTrigger: true,
                    child: PopupMenuButton<_CalendarView>(
                      tooltip: '',
                      initialValue: _view,
                      onSelected: _switchView,
                      itemBuilder: (_) => [
                        for (final view in _CalendarView.values)
                          PopupMenuItem(value: view, child: Text(view.label)),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_view.label),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                  ),
                  DButton(
                    variant: DButtonVariant.outline,
                    onPressed: _pickTimezone,
                    icon: const Icon(Icons.public),
                    label: Text(_timezone.replaceAll('_', ' ')),
                  ),
                ],
              ),
            ),
            LayoutBuilder(builder: _buildCalendar),
            if (!_occurrences.any((event) {
              final from =
                  _visibleRange?.start ??
                  DateTime.utc(_focus.year, _focus.month);
              final until =
                  _visibleRange?.end ??
                  DateTime.utc(_focus.year, _focus.month + 1);
              return event.firstDay.isBefore(until) &&
                  !event.lastDay.isBefore(from);
            }))
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _view == _CalendarView.month || _view == _CalendarView.agenda
                      ? 'No calendar entries this month.'
                      : 'No calendar entries in this view.',
                ),
              ),
          ],
          Padding(
            padding: const EdgeInsets.all(4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: DButton(
                variant: DButtonVariant.link,
                onPressed: widget.onOpenWeb,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Open web calendar'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar(BuildContext context, BoxConstraints constraints) {
    final rowHeight = math.max(
      28.0,
      MediaQuery.textScalerOf(context).scale(DiscourseTypography.sm) *
              DiscourseTypography.lineHeightSmall +
          10,
    );
    final lanes = constraints.maxWidth < 450 ? 3 : 4;
    final first = DateTime.utc(_focus.year, _focus.month);
    final next = DateTime.utc(_focus.year, _focus.month + 1);
    final leadingDays = (first.weekday % 7 - widget.settings.firstDay + 7) % 7;
    final weeks = ((next.difference(first).inDays + leadingDays) / 7).ceil();
    final tiles = kalender.TileComponents(tileBuilder: _tile);
    final overlays = kalender.OverlayBuilders(
      multiDayOverlayPortalBuilder:
          (
            context, {
            required date,
            required events,
            required numberOfHiddenRows,
            required tileHeight,
            required getMultiDayEventLayoutRenderBox,
            required overlayTileBuilder,
            required overlayBuilders,
          }) => TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _openDay(
              topicCalendarDay(date),
              events
                  .whereType<TopicCalendarEvent>()
                  .map((event) => event.occurrence)
                  .toList(),
            ),
            child: Text(
              '+$numberOfHiddenRows',
              semanticsLabel: '$numberOfHiddenRows more entries',
            ),
          ),
    );
    return DKalenderTheme(
      compactMonthLayout: false,
      child: SizedBox(
        // An embedded post must give Kalender a bounded viewport. Reserve an
        // overflow row and scale event heights with the reader's text size.
        height: _view == _CalendarView.month
            ? 36 + weeks * (44 + rowHeight * (lanes + 1) + 2)
            : 580 + (rowHeight - 28) * lanes,
        child: kalender.KalenderView(
          eventsController: _events,
          calendarController: _calendar,
          viewConfiguration: _configuration,
          locale: Localizations.localeOf(context),
          location: _location,
          components: kalender.CalendarComponents(
            monthComponents: kalender.MonthComponents(
              headerComponents: kalender.MonthHeaderComponents(
                weekDayHeaderBuilder: (context, date) => SizedBox(
                  height: 36,
                  child: Center(
                    child: Text(
                      DateFormat.E(_locale).format(date),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
              bodyComponents: kalender.MonthBodyComponents(
                monthGridBuilder: (context, rows) => kalender.MonthGrid(
                  numberOfRows: rows,
                  style: kalender.MonthGridStyle(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    thickness: 1,
                  ),
                ),
                monthDayHeaderBuilder: _dayHeader,
                monthDayCellBuilder: (context, details) => ColoredBox(
                  color: details.isToday
                      ? Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.35)
                      : Colors.transparent,
                ),
                overlayBuilders: overlays,
              ),
            ),
            multiDayComponents: kalender.MultiDayComponents(
              headerComponents: kalender.MultiDayHeaderComponents(
                overlayBuilders: overlays,
              ),
            ),
          ),
          header: kalender.CalendarHeader(
            interaction: _interaction,
            multiDayTileComponents: tiles,
            multiDayHeaderConfiguration: kalender.MultiDayHeaderConfiguration(
              maximumNumberOfVerticalEvents: lanes,
              tileHeight: rowHeight,
            ),
          ),
          body: kalender.CalendarBody(
            interaction: _interaction,
            monthTileComponents: tiles,
            multiDayTileComponents: tiles,
            scheduleTileComponents: kalender.ScheduleTileComponents(
              tileBuilder: (context, event, range) => SizedBox(
                height: rowHeight + 8,
                child: _tile(context, event, range),
              ),
            ),
            monthBodyConfiguration: kalender.MonthBodyConfiguration(
              tileHeight: rowHeight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dayHeader(BuildContext context, DateTime date) {
    final day = topicCalendarDay(date);
    return SizedBox(
      height: 44,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          foregroundColor: day.month == _focus.month
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
        ),
        onPressed: () => _openDay(day, _eventsOn(day)),
        child: Text(
          '${day.day}',
          semanticsLabel:
              '${DateFormat.yMMMMEEEEd(_locale).format(day)}, ${_eventsOn(day).length} entries',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    kalender.CalendarEvent event,
    DateTimeRange range,
  ) => _bar((event as TopicCalendarEvent).occurrence);

  Widget _bar(CalendarOccurrence event) {
    var hash = 0;
    for (final unit
        in (event.username.isEmpty ? event.title : event.username).codeUnits) {
      hash = unit + ((hash << 5) - hash);
    }
    final colors = Theme.of(context).colorScheme;
    final background = event.postNumber == null
        ? colors.surfaceContainerHighest
        : Color.fromARGB(
            255,
            hash & 255,
            (hash >> 8) & 255,
            (hash >> 16) & 255,
          );
    final foreground = background.computeLuminance() > 0.179
        ? Colors.black
        : Colors.white;
    final label = '${event.title}, ${_dateLabel(event)}';
    return DTooltip(
      message: label,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(3),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (event.postNumber case final number?) {
              widget.onOpenReply(number);
            } else {
              _openDay(event.firstDay, [event]);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '${event.allDay ? '' : '${DateFormat.Hm(_locale).format(event.start)} '}${event.title}',
                semanticsLabel: label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _TimezonePicker extends StatefulWidget {
  const _TimezonePicker({required this.names, required this.selected});
  final List<String> names;
  final String selected;
  @override
  State<_TimezonePicker> createState() => _TimezonePickerState();
}

final class _TimezonePickerState extends State<_TimezonePicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final names = widget.names
        .where(
          (name) => name
              .replaceAll('_', ' ')
              .toLowerCase()
              .contains(_query.toLowerCase()),
        )
        .toList();
    return AlertDialog(
      title: const Text('Calendar timezone'),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          children: [
            TextField(
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: const InputDecoration(labelText: 'Search timezones'),
              onChanged: (value) => setState(() => _query = value),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: names.length,
                itemBuilder: (context, index) => ListTile(
                  title: Text(names[index].replaceAll('_', ' ')),
                  selected: names[index] == widget.selected,
                  onTap: () => Navigator.pop(context, names[index]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        DButton(
          variant: DButtonVariant.ghost,
          onPressed: () => Navigator.pop(context),
          label: const Text('Cancel'),
        ),
      ],
    );
  }
}
