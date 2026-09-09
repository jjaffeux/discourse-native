import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:kalender/kalender.dart' as kalender;
import 'package:timezone/timezone.dart' as tz;

import '../../theme/discourse_typography.dart';
import 'event_calendar_data.dart';
import 'event_data.dart';

/// Full-page Kalender presentation, independent of requests and shell state.
final class EventCalendar extends StatefulWidget {
  const EventCalendar({
    super.key,
    required this.page,
    required this.events,
    required this.location,
    required this.onPageChanged,
    required this.onOpen,
    required this.mine,
    required this.onMineChanged,
    required this.actions,
    this.status,
    this.firstDay = 1,
    this.display = 'auto',
    this.clock = DateTime.now,
  });

  final EventCalendarPage page;
  final List<EventCalendarEntry> events;
  final tz.Location location;
  final ValueChanged<EventCalendarPage> onPageChanged;
  final ValueChanged<EventCalendarEntry> onOpen;
  final bool mine;
  final ValueChanged<bool>? onMineChanged;
  final Widget actions;
  final Widget? status;
  final int firstDay;
  final String display;
  final DateTime Function() clock;

  @override
  State<EventCalendar> createState() => _EventCalendarState();
}

final class _EventCalendarState extends State<EventCalendar> {
  static final _localeData = initializeDateFormatting();
  final _calendar = kalender.CalendarController();
  final _events = kalender.DefaultEventsController();
  final _monthScroll = ScrollController();
  late kalender.ViewConfiguration _configuration;
  static final _interaction = kalender.CalendarInteraction(
    allowEventCreation: false,
    allowRescheduling: false,
    allowResizing: false,
  );

  String get _locale => Localizations.localeOf(context).toString();
  EventCalendarView get _view => widget.page.view;
  DateTime _now() => tz.TZDateTime.from(widget.clock(), widget.location);
  DateTime _inCalendar(DateTime day) =>
      tz.TZDateTime(widget.location, day.year, day.month, day.day);
  DateTimeRange get _days => widget.page.days(firstDay: widget.firstDay);

  @override
  void initState() {
    super.initState();
    unawaited(_localeData);
    _configure();
    _events.replaceEvents(widget.events);
  }

  @override
  void didUpdateWidget(EventCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page ||
        oldWidget.location != widget.location ||
        oldWidget.firstDay != widget.firstDay) {
      _configure();
      if (_monthScroll.hasClients) _monthScroll.jumpTo(0);
    }
    if (oldWidget.events != widget.events) _events.replaceEvents(widget.events);
  }

  void _configure() {
    final date = _inCalendar(widget.page.date);
    final range = DateTimeRange(
      start: _inCalendar(DateTime.utc(1900)),
      end: _inCalendar(DateTime.utc(2200)),
    );
    final firstDay = widget.firstDay == 0 ? DateTime.sunday : widget.firstDay;
    _configuration = switch (_view) {
      EventCalendarView.month => kalender.MonthViewConfiguration.singleMonth(
        initialDateTime: date,
        displayRange: range,
        firstDayOfWeek: firstDay,
        nowCallback: _now,
      ),
      EventCalendarView.week => kalender.MultiDayViewConfiguration.week(
        initialDateTime: date,
        displayRange: range,
        firstDayOfWeek: firstDay,
        initialTimeOfDay: const TimeOfDay(hour: 8, minute: 0),
        nowCallback: _now,
      ),
      EventCalendarView.day => kalender.MultiDayViewConfiguration.singleDay(
        initialDateTime: date,
        displayRange: range,
        initialTimeOfDay: const TimeOfDay(hour: 8, minute: 0),
        nowCallback: _now,
      ),
      // Core's Year button is FullCalendar listYear: an agenda for that year.
      EventCalendarView.year => kalender.ScheduleViewConfiguration.continuous(
        name: 'Year',
        initialDateTime: _inCalendar(_days.start),
        displayRange: DateTimeRange(
          start: _inCalendar(_days.start),
          end: _inCalendar(_days.end),
        ),
        nowCallback: _now,
      ),
    };
  }

  void _pageChanged(DateTimeRange range) {
    if (_view == EventCalendarView.year) return;
    final start = DateTime.utc(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final end = DateTime.utc(range.end.year, range.end.month, range.end.day);
    if (_days.start == start && _days.end == end) return;
    final focus = _view == EventCalendarView.month
        ? start.add(end.difference(start) ~/ 2)
        : start;
    final page = EventCalendarPage(
      _view,
      _view == EventCalendarView.month
          ? DateTime.utc(focus.year, focus.month)
          : focus,
    );
    // PageView reports during layout. Only publish after that frame, and drop
    // a swipe that was superseded by a toolbar/view change in the meantime.
    final previous = widget.page;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.page == previous) widget.onPageChanged(page);
    });
  }

  @override
  void dispose() {
    _calendar.dispose();
    _events.dispose();
    _monthScroll.dispose();
    super.dispose();
  }

  String get _period => switch (_view) {
    EventCalendarView.day => DateFormat.yMMMMd(
      _locale,
    ).format(widget.page.date),
    EventCalendarView.week =>
      '${DateFormat.MMMd(_locale).format(_days.start)} – '
          '${DateFormat.yMMMd(_locale).format(_days.end.subtract(const Duration(days: 1)))}',
    EventCalendarView.month => DateFormat.yMMMM(
      _locale,
    ).format(widget.page.date),
    EventCalendarView.year => DateFormat.y(_locale).format(widget.page.date),
  };

  Widget _segments<T>(
    Map<T, String> values,
    T selected,
    ValueChanged<T>? onChanged,
  ) => SegmentedButton<T>(
    segments: [
      for (final entry in values.entries)
        ButtonSegment(value: entry.key, label: Text(entry.value)),
    ],
    selected: {selected},
    showSelectedIcon: false,
    onSelectionChanged: onChanged == null
        ? null
        : (values) => onChanged(values.single),
    style: SegmentedButton.styleFrom(
      selectedBackgroundColor: Theme.of(context).colorScheme.primary,
      selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      visualDensity: VisualDensity.compact,
    ),
  );

  Widget _toolbar(BuildContext context, BoxConstraints constraints) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final wide = constraints.maxWidth >= 1100 * scale;
    final scopes = _segments(
      const {false: 'All events', true: 'My events'},
      widget.mine,
      widget.onMineChanged,
    );
    final views = _segments(
      {for (final view in EventCalendarView.values) view: view.label},
      _view,
      (view) => widget.onPageChanged(EventCalendarPage(view, widget.page.date)),
    );
    final period = Semantics(
      header: true,
      child: Text(
        _period,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
    final navigation = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DTooltip(
          message: 'Previous ${_view.name}',
          labelTrigger: true,
          child: IconButton(
            tooltip: '',
            onPressed: widget.page.move(-1).date.year >= 1900
                ? () => widget.onPageChanged(widget.page.move(-1))
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
        ),
        DTooltip(
          message: 'Next ${_view.name}',
          labelTrigger: true,
          child: IconButton(
            tooltip: '',
            onPressed: widget.page.move(1).date.year < 2200
                ? () => widget.onPageChanged(widget.page.move(1))
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ),
        DButton(
          variant: DButtonVariant.transparentPrimary,
          label: const Text('Today'),
          onPressed: () {
            final now = _now();
            final today = DateTime.utc(now.year, now.month, now.day);
            final inView =
                !today.isBefore(_days.start) && today.isBefore(_days.end);
            if (_monthScroll.hasClients) _monthScroll.jumpTo(0);
            widget.onPageChanged(EventCalendarPage(_view, today));
            if (inView) unawaited(_calendar.animateToDate(_inCalendar(today)));
          },
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: wide
          ? Row(
              children: [
                scopes,
                const SizedBox(width: 16),
                navigation,
                Expanded(child: period),
                views,
                widget.actions,
              ],
            )
          : Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: scopes,
                      ),
                    ),
                    widget.actions,
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.center,
                  children: [period, navigation, views],
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(builder: _toolbar),
      ?widget.status,
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: _buildCalendar(),
          ),
        ),
      ),
    ],
  );

  Widget _buildCalendar() {
    final rowHeight = math.max(
      26.0,
      MediaQuery.textScalerOf(context).scale(DiscourseTypography.sm) *
              DiscourseTypography.lineHeightSmall +
          10,
    );
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
            onPressed: () => _openDay(date),
            child: Text(
              '+$numberOfHiddenRows more',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
    );
    final body = kalender.CalendarBody(
      interaction: _interaction,
      monthTileComponents: tiles,
      multiDayTileComponents: kalender.TileComponents(
        tileBuilder: (context, event, range) =>
            _tile(context, event, range, timeline: true),
      ),
      monthBodyConfiguration: kalender.MonthBodyConfiguration(
        tileHeight: rowHeight,
        multiDayLayoutStrategy: const EventCalendarLayout(),
      ),
      scheduleTileComponents: kalender.ScheduleTileComponents(
        tileBuilder: (context, event, range) => SizedBox(
          height: rowHeight + 12,
          child: _tile(context, event, range),
        ),
      ),
      scheduleBodyConfiguration: kalender.ScheduleBodyConfiguration(
        emptyDay: kalender.EmptyDayBehavior.hide,
      ),
    );
    return kalender.KalenderView(
      eventsController: _events,
      calendarController: _calendar,
      viewConfiguration: _configuration,
      location: widget.location,
      locale: Localizations.localeOf(context),
      callbacks: kalender.CalendarCallbacks(onPageChanged: _pageChanged),
      components: kalender.CalendarComponents(
        monthComponents: kalender.MonthComponents(
          headerComponents: kalender.MonthHeaderComponents(
            weekDayHeaderBuilder: (context, date) => SizedBox(
              height: 32,
              child: Center(
                child: Text(
                  DateFormat.E(_locale).format(date).toUpperCase(),
                  maxLines: 1,
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
                    ).colorScheme.primaryContainer.withValues(alpha: 0.3)
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
          maximumNumberOfVerticalEvents: 4,
          tileHeight: rowHeight,
        ),
      ),
      body: _view != EventCalendarView.month
          ? body
          : LayoutBuilder(
              builder: (context, constraints) {
                var most = 0;
                for (
                  var date = _days.start;
                  date.isBefore(_days.end);
                  date = date.add(const Duration(days: 1))
                ) {
                  most = math.max(
                    most,
                    widget.events.where((event) => event.includes(date)).length,
                  );
                }
                // Dense months scroll vertically like core. Reserve an overflow row
                // for unusually crowded days; its dialog includes every occurrence.
                final lanes = most.clamp(3, 20);
                final weeks = _days.duration.inDays ~/ 7;
                final height = math.max(
                  constraints.maxHeight,
                  weeks * (36 + (lanes + 1) * rowHeight),
                );
                return DScrollBar(
                  controller: _monthScroll,
                  child: SingleChildScrollView(
                    controller: _monthScroll,
                    child: SizedBox(height: height, child: body),
                  ),
                );
              },
            ),
    );
  }

  Widget _dayHeader(BuildContext context, DateTime date) => SizedBox(
    height: 36,
    child: TextButton(
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        foregroundColor: date.month == widget.page.date.month
            ? Theme.of(context).colorScheme.onSurface
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
      ),
      onPressed: () => _openDay(date),
      child: Text(
        '${date.day}',
        semanticsLabel: DateFormat.yMMMMEEEEd(_locale).format(date),
      ),
    ),
  );

  void _openDay(DateTime date) {
    final source = widget.events;
    final page = widget.page;
    bool isCurrent() =>
        mounted && identical(source, widget.events) && page == widget.page;
    final day = DateTime.utc(date.year, date.month, date.day);
    final events = widget.events.where((event) => event.includes(day)).toList();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(DateFormat.yMMMMEEEEd(_locale).format(day)),
          content: SizedBox(
            width: 520,
            child: events.isEmpty
                ? const Text('No events on this day.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return ListTile(
                        leading: Icon(
                          event.event.recurring ? Icons.repeat : Icons.event,
                          color: event.color,
                        ),
                        title: Text(event.title),
                        subtitle: Text(_timeLabel(event)),
                        onTap: () {
                          Navigator.pop(context);
                          if (isCurrent()) widget.onOpen(event);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            DButton(
              variant: DButtonVariant.transparentPrimary,
              onPressed: () {
                Navigator.pop(context);
                if (isCurrent()) {
                  widget.onPageChanged(
                    EventCalendarPage(EventCalendarView.day, day),
                  );
                }
              },
              label: const Text('Day view'),
            ),
            DButton(
              variant: DButtonVariant.transparentPrimary,
              onPressed: () => Navigator.pop(context),
              label: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(EventCalendarEntry event) => event.isAllDay
      ? 'All day'
      : '${DateFormat.Hm(_locale).format(event.localStart)} – ${DateFormat.Hm(_locale).format(event.localEnd)}';

  Widget _tile(
    BuildContext context,
    kalender.CalendarEvent raw,
    DateTimeRange range, {
    bool timeline = false,
  }) {
    final event = raw as EventCalendarEntry;
    final colors = Theme.of(context).colorScheme;
    final block =
        timeline ||
        (_view != EventCalendarView.year &&
            (widget.display == 'block' ||
                (widget.display != 'list-item' &&
                    (event.isAllDay || event.spansDays))));
    final background = event.color ?? colors.primary;
    final foreground = block
        ? (background.computeLuminance() > 0.179 ? Colors.black : Colors.white)
        : colors.primary;
    final label =
        '${event.title}, ${DateFormat.yMMMd(_locale).format(event.localStart)}, ${_timeLabel(event)}';
    return DTooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: block ? background : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => widget.onOpen(event),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 100;
                final text = Text.rich(
                  TextSpan(
                    children: [
                      if (!event.isAllDay && !compact)
                        TextSpan(
                          text:
                              '${timeline ? _timeLabel(event) : DateFormat.Hm(_locale).format(event.localStart)} ',
                          style: const TextStyle(fontWeight: FontWeight.normal),
                        ),
                      if (event.event.recurring && !compact)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(end: 2),
                            child: Icon(
                              Icons.repeat,
                              size: 13,
                              color: foreground,
                            ),
                          ),
                        ),
                      TextSpan(text: event.title),
                    ],
                  ),
                  maxLines: timeline ? null : 1,
                  overflow: timeline
                      ? TextOverflow.clip
                      : TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: block ? FontWeight.normal : FontWeight.w600,
                  ),
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    crossAxisAlignment: timeline
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      if (!block) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.circle,
                            size: 8,
                            color: event.color ?? colors.outline,
                          ),
                        ),
                      ],
                      Expanded(child: text),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
