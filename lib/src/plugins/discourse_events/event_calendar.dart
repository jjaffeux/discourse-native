import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:kalender/kalender.dart' as kalender;
import 'package:timezone/timezone.dart' as tz;

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
  final _calendar = kalender.KalenderController();
  final _events = kalender.DefaultEventsController();
  final _monthScroll = ScrollController();
  late kalender.ViewConfiguration _configuration;
  var _awaitingScheduleEvents = false;
  static final _interaction = kalender.KalenderInteraction(
    allowEventCreation: false,
    allowRescheduling: false,
    allowResizing: false,
  );

  String get _locale => Localizations.localeOf(context).toString();
  EventCalendarView get _view => widget.page.view;
  bool get _schedule => _view == EventCalendarView.schedule;
  DateTime _now() => tz.TZDateTime.from(widget.clock(), widget.location);
  DateTime _inCalendar(DateTime day) =>
      tz.TZDateTime(widget.location, day.year, day.month, day.day);
  DateTimeRange get _days => widget.page.days(firstDay: widget.firstDay);

  @override
  void initState() {
    super.initState();
    unawaited(_localeData);
    _awaitingScheduleEvents = _schedule && widget.events.isEmpty;
    _configure();
    _replaceEvents();
  }

  @override
  void didUpdateWidget(EventCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pageChanged =
        oldWidget.page != widget.page ||
        oldWidget.location != widget.location ||
        oldWidget.firstDay != widget.firstDay;
    final dataChanged = oldWidget.events != widget.events;
    final eventsChanged = dataChanged || oldWidget.page.view != _view;
    if (!_schedule) {
      _awaitingScheduleEvents = false;
    } else if (oldWidget.page.days(firstDay: oldWidget.firstDay) != _days ||
        oldWidget.location != widget.location ||
        oldWidget.mine != widget.mine ||
        (oldWidget.page.view != _view && widget.events.isEmpty)) {
      _awaitingScheduleEvents = true;
    }
    // The schedule mounts before its request completes. Once this month's
    // events arrive, restore the requested day instead of keeping index zero.
    // Later refreshes of a populated month preserve the reader's scroll.
    final scheduleLoaded =
        _awaitingScheduleEvents && dataChanged && widget.events.isNotEmpty;
    if (scheduleLoaded) _awaitingScheduleEvents = false;
    if (pageChanged) {
      _configure();
      if (_monthScroll.hasClients) _monthScroll.jumpTo(0);
    }
    if (eventsChanged) _replaceEvents();
    if (pageChanged || scheduleLoaded) {
      // initialDateTime only applies at first mount. Route and toolbar changes
      // must also navigate an existing view after its configuration updates.
      final page = widget.page;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.page == page) {
          _calendar.jumpToDate(_inCalendar(page.date));
        }
      });
    }
  }

  void _replaceEvents() {
    final events = [...widget.events]
      ..sort((a, b) {
        if (_schedule) {
          if (a.isAllDay != b.isAllDay) return a.isAllDay ? -1 : 1;
          // Continuations keep their daily start time in the schedule.
          final time = (a.localStart.hour * 60 + a.localStart.minute).compareTo(
            b.localStart.hour * 60 + b.localStart.minute,
          );
          if (time != 0) return time;
        }
        final order = a.start.compareTo(b.start);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    _events.replaceEvents(events);
  }

  void _configure() {
    final date = _inCalendar(widget.page.date);
    final range = kalender.KalenderDateTimeRange(
      start: _inCalendar(DateTime.utc(1900)),
      end: _inCalendar(DateTime.utc(2200)),
    );
    final firstDay = widget.firstDay == 0 ? DateTime.sunday : widget.firstDay;
    _configuration = switch (_view) {
      EventCalendarView.month => kalender.MonthViewConfiguration.singleMonth(
        initialDateTime: date,
        dateResolver: (_) =>
            kalender.FloatingDateTime.fromDateTime(widget.page.date),
        displayRange: range,
        firstDayOfWeek: firstDay,
        nowCallback: _now,
      ),
      EventCalendarView.week => kalender.MultiDayViewConfiguration.week(
        initialDateTime: date,
        dateResolver: (_) =>
            kalender.FloatingDateTime.fromDateTime(widget.page.date),
        displayRange: range,
        firstDayOfWeek: firstDay,
        initialTimeOfDay: const kalender.KalenderTime(hour: 8, minute: 0),
        nowCallback: _now,
      ),
      EventCalendarView.day => kalender.MultiDayViewConfiguration.singleDay(
        initialDateTime: date,
        dateResolver: (_) =>
            kalender.FloatingDateTime.fromDateTime(widget.page.date),
        displayRange: range,
        initialTimeOfDay: const kalender.KalenderTime(hour: 8, minute: 0),
        nowCallback: _now,
      ),
      EventCalendarView.schedule =>
        kalender.ScheduleViewConfiguration.paginated(
          name: 'Schedule',
          initialDateTime: date,
          dateResolver: (_) =>
              kalender.FloatingDateTime.fromDateTime(widget.page.date),
          // Keep one internal schedule page. Kalender 0.31's neighboring
          // pages share a mutable item map during animation; returning from
          // an empty month can read the wrong map. The toolbar owns months.
          displayRange: kalender.KalenderDateTimeRange(
            start: _inCalendar(_days.start),
            end: _inCalendar(_days.end),
          ),
          nowCallback: _now,
        ),
      // Core's Year button is FullCalendar listYear: an agenda for that year.
      EventCalendarView.year => kalender.ScheduleViewConfiguration.continuous(
        name: 'Year',
        initialDateTime: _inCalendar(_days.start),
        dateResolver: (_) =>
            kalender.FloatingDateTime.fromDateTime(_days.start),
        displayRange: kalender.KalenderDateTimeRange(
          start: _inCalendar(_days.start),
          end: _inCalendar(_days.end),
        ),
        nowCallback: _now,
      ),
    };
  }

  void _pageChanged(kalender.KalenderDateTimeRange range) {
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
    EventCalendarView.month || EventCalendarView.schedule => DateFormat.yMMMM(
      _locale,
    ).format(widget.page.date),
    EventCalendarView.year => DateFormat.y(_locale).format(widget.page.date),
  };

  Widget _segments<T extends Object>(
    Map<T, String> values,
    T selected,
    ValueChanged<T>? onChanged,
  ) => DToggleGroup<T>(
    items: [
      for (final entry in values.entries)
        DToggleGroupItem(value: entry.key, child: Text(entry.value)),
    ],
    values: [selected],
    allowEmptySelection: false,
    variant: DToggleVariant.outline,
    spacing: 0,
    onChanged: onChanged == null ? null : (values) => onChanged(values.single),
  );

  Widget _toolbar(BuildContext context, BoxConstraints constraints) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    if (constraints.maxWidth < 600) return _mobileToolbar(context, constraints);
    final wide = constraints.maxWidth >= 1100 * scale;
    final scopes = _segments(
      const {false: 'All events', true: 'My events'},
      widget.mine,
      widget.onMineChanged,
    );
    final views = _segments(
      {for (final view in EventCalendarView.values) view: view.label},
      _view,
      _selectView,
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
        DButton.iconOnly(
          onPressed: widget.page.move(-1).date.year >= 1900
              ? () => widget.onPageChanged(widget.page.move(-1))
              : null,
          variant: DButtonVariant.ghost,
          size: DButtonSize.small,
          tooltip: 'Previous ${_view.name}',
          icon: const Icon(Icons.chevron_left),
        ),
        DButton.iconOnly(
          onPressed: widget.page.move(1).date.year < 2200
              ? () => widget.onPageChanged(widget.page.move(1))
              : null,
          variant: DButtonVariant.ghost,
          size: DButtonSize.small,
          tooltip: 'Next ${_view.name}',
          icon: const Icon(Icons.chevron_right),
        ),
        DButton(
          variant: DButtonVariant.outline,
          label: const Text('Today'),
          onPressed: _today,
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
                  spacing: DSpacing.controlGap,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.center,
                  children: [period, navigation, views],
                ),
              ],
            ),
    );
  }

  void _selectView(EventCalendarView view) {
    final now = _now();
    final date =
        view == EventCalendarView.schedule &&
            widget.page.date.year == now.year &&
            widget.page.date.month == now.month
        ? DateTime.utc(now.year, now.month, now.day)
        : widget.page.date;
    widget.onPageChanged(EventCalendarPage(view, date));
  }

  void _today() {
    final now = _now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final inView = !today.isBefore(_days.start) && today.isBefore(_days.end);
    if (_monthScroll.hasClients) _monthScroll.jumpTo(0);
    widget.onPageChanged(EventCalendarPage(_view, today));
    if (inView) unawaited(_calendar.animateToDate(_inCalendar(today)));
  }

  Widget _select<T extends Object>(
    String label,
    Map<T, String> values,
    T selected,
    ValueChanged<T>? onChanged,
  ) => DSelect<T>.controlled(
    value: selected,
    semanticLabel: label,
    enabled: onChanged != null,
    entries: [
      for (final entry in values.entries)
        DSelectItem(
          value: entry.key,
          textValue: entry.value,
          child: Text(entry.value),
        ),
    ],
    onChanged: (value) {
      if (value != null) onChanged?.call(value);
    },
    triggerBuilder: (context, state, _) => DButton(
      variant: DButtonVariant.outline,
      focusNode: state.focusNode,
      hasPopup: true,
      expanded: state.open,
      semanticLabel: label,
      onPressed: state.enabled ? state.toggle : null,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DSpacing.controlGap,
        children: [
          Flexible(child: Text(values[selected]!, maxLines: 2)),
          const Icon(Icons.keyboard_arrow_down),
        ],
      ),
    ),
  );

  Widget _mobileToolbar(BuildContext context, BoxConstraints constraints) {
    final filters = [
      _select(
        'Event filter',
        const {false: 'All events', true: 'My events'},
        widget.mine,
        widget.onMineChanged,
      ),
      _select(
        'Calendar view',
        {
          for (final view in [
            EventCalendarView.month,
            EventCalendarView.schedule,
            EventCalendarView.week,
            EventCalendarView.day,
            EventCalendarView.year,
          ])
            view: view.label,
        },
        _view,
        _selectView,
      ),
    ];
    final today = DButton(
      variant: DButtonVariant.outline,
      label: const Text('Today'),
      onPressed: _today,
    );
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Events',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              widget.actions,
            ],
          ),
          const SizedBox(height: 12),
          if (largeText || constraints.maxWidth < 360)
            Wrap(
              spacing: DSpacing.controlGap,
              runSpacing: 8,
              children: [...filters, today],
            )
          else
            Row(
              spacing: DSpacing.controlGap,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: DSpacing.controlGap,
                    runSpacing: 8,
                    children: filters,
                  ),
                ),
                today,
              ],
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              DButton.iconOnly(
                variant: DButtonVariant.outline,
                size: DButtonSize.small,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous ${_schedule ? 'month' : _view.name}',
                onPressed: widget.page.move(-1).date.year >= 1900
                    ? () => widget.onPageChanged(widget.page.move(-1))
                    : null,
              ),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    _period,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              DButton.iconOnly(
                variant: DButtonVariant.outline,
                size: DButtonSize.small,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next ${_schedule ? 'month' : _view.name}',
                onPressed: widget.page.move(1).date.year < 2200
                    ? () => widget.onPageChanged(widget.page.move(1))
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const DSeparator(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(context, constraints),
          ?widget.status,
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 12,
                0,
                compact ? 16 : 12,
                12,
              ),
              child: _buildCalendar(compact: compact),
            ),
          ),
        ],
      );
    },
  );

  Widget _buildCalendar({required bool compact}) {
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    final rowHeight = math.max(
      touch ? kMinInteractiveDimension : DControlStyle.smallHeight,
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
          }) => DButton(
            onPressed: () => _openDay(date),
            variant: DButtonVariant.ghost,
            size: DButtonSize.small,
            label: Text(
              '+$numberOfHiddenRows more',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
    );
    final body = kalender.KalenderBody(
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
        tileBuilder: _schedule
            ? _scheduleTile
            : (context, event, range) => SizedBox(
                height: rowHeight + 12,
                child: _tile(context, event, range),
              ),
      ),
      scheduleBodyConfiguration: kalender.ScheduleBodyConfiguration(
        emptyDay: kalender.EmptyDayBehavior.hide,
        leadingWidth: _schedule ? 0 : 56,
      ),
    );
    return DKalenderTheme(
      compactMonthLayout: false,
      child: kalender.KalenderView(
        eventsController: _events,
        kalenderController: _calendar,
        viewConfiguration: _configuration,
        location: widget.location,
        locale: Localizations.localeOf(context),
        callbacks: kalender.KalenderCallbacks(onPageChanged: _pageChanged),
        components: kalender.KalenderComponents(
          scheduleComponents: _schedule
              ? kalender.ScheduleComponents(
                  leadingDateBuilder: (context, date) =>
                      const SizedBox.shrink(),
                  monthItemBuilder: (context, range) => const SizedBox.shrink(),
                  scheduleTileHighlightBuilder: (context, date, range, child) =>
                      child,
                )
              : const kalender.ScheduleComponents(),
          monthComponents: kalender.MonthComponents(
            headerComponents: kalender.MonthHeaderComponents(
              weekDayHeaderBuilder: (context, date) =>
                  DCalendarWeekdayHeader(date: date),
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
        header: kalender.KalenderHeader(
          interaction: _interaction,
          multiDayTileComponents: tiles,
          multiDayHeaderConfiguration: kalender.MultiDayHeaderConfiguration(
            maximumNumberOfVerticalEvents: 4,
            tileHeight: rowHeight,
          ),
        ),
        body: _schedule
            ? DKalenderScheduleBody(child: body)
            : _view != EventCalendarView.month
            ? body
            : compact
            ? DKalenderCompactMonthBody(
                onDayPressed: _openDay,
                eventColor: (event) => (event as EventCalendarEntry).color,
                layoutStrategy: const EventCalendarLayout(),
              )
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
                      widget.events
                          .where((event) => event.includes(date))
                          .length,
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
      ),
    );
  }

  Widget _scheduleTile(
    BuildContext context,
    kalender.KalenderEvent raw,
    kalender.KalenderDateTimeRange range,
  ) {
    final event = raw as EventCalendarEntry;
    final day = DateTime.utc(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final first = _events
        .eventsInRange(
          kalender.FloatingDateTimeRange(
            start: kalender.FloatingDateTime.fromDateTime(day),
            end: kalender.FloatingDateTime.fromDateTime(
              day.add(const Duration(days: 1)),
            ),
          ),
          multiDayRule: _configuration.multiDayRule,
          location: widget.location,
        )
        .firstOrNull;
    final now = _now();
    final today = day == DateTime.utc(now.year, now.month, now.day);
    final metadata = event.scheduleMetadata(day);
    return DCalendarScheduleEntry(
      dayLabel: first?.id == event.id
          ? DateFormat('EEE d', _locale).format(day)
          : null,
      today: today,
      time: event.isAllDay
          ? 'All day'
          : (event.localStart.minute == 0
                    ? DateFormat.j(_locale)
                    : DateFormat.jm(_locale))
                .format(event.localStart)
                .toLowerCase()
                .replaceAll('\u202f', ' '),
      title: event.title,
      subtitle: metadata.isEmpty ? null : metadata,
      color: event.color,
      onPressed: () => widget.onOpen(event),
    );
  }

  Widget _dayHeader(BuildContext context, DateTime date) => SizedBox(
    height: 36,
    child: DCalendarDayButton(
      details: DCalendarDayDetails(
        date: DCalendarDate.fromDateTime(date),
        outside: date.month != widget.page.date.month,
        today:
            date.year == _now().year &&
            date.month == _now().month &&
            date.day == _now().day,
        disabled: false,
        hidden: false,
        booked: false,
        selected: false,
        rangeStart: false,
        rangeMiddle: false,
        rangeEnd: false,
      ),
      onPressed: () => _openDay(date),
      semanticLabel: DateFormat.yMMMMEEEEd(_locale).format(date),
      child: Text('${date.day}'),
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
      showDDialog<void>(
        context: context,
        builder: (context, dialog) => DDialogContent(
          maxWidth: 520,
          children: [
            DDialogHeader(
              children: [
                DDialogTitle(
                  child: Text(DateFormat.yMMMMEEEEd(_locale).format(day)),
                ),
              ],
            ),
            if (events.isEmpty)
              const Text('No events on this day.')
            else
              SizedBox(
                height: math.min(420, MediaQuery.sizeOf(context).height * .5),
                child: ListView.builder(
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return DItem(
                      onPressed: () {
                        dialog.close();
                        if (isCurrent()) widget.onOpen(event);
                      },
                      children: [
                        Icon(
                          event.event.recurring ? Icons.repeat : Icons.event,
                          color: event.color,
                        ),
                        DItemContent(
                          children: [
                            DItemTitle(
                              maxLines: null,
                              child: Text(event.title),
                            ),
                            DItemDescription(child: Text(_timeLabel(event))),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            DDialogFooter(
              children: [
                DButton(
                  variant: DButtonVariant.outline,
                  onPressed: () {
                    dialog.close();
                    if (isCurrent()) {
                      widget.onPageChanged(
                        EventCalendarPage(EventCalendarView.day, day),
                      );
                    }
                  },
                  label: const Text('Day view'),
                ),
                DButton(
                  variant: DButtonVariant.ghost,
                  onPressed: dialog.close,
                  label: const Text('Close'),
                ),
              ],
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
    kalender.KalenderEvent raw,
    kalender.KalenderDateTimeRange range, {
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
