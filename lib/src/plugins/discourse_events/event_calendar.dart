import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:kalender/kalender.dart' as kalender;
import 'package:timezone/timezone.dart' as tz;

import 'event_calendar_data.dart';
import 'event_calendar_skeleton.dart';
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
    this.onViewSelected,
    this.loading = false,
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
  final VoidCallback? onViewSelected;
  final bool loading;
  final Widget? status;
  final int firstDay;
  final String display;
  final DateTime Function() clock;

  @override
  State<EventCalendar> createState() => _EventCalendarState();
}

final class _EventCalendarState extends State<EventCalendar> {
  static final _localeData = initializeDateFormatting();
  static const _dayPanelWidth = 340.0;
  static const _dayPanelGap = 16.0;
  late final kalender.KalenderController _calendar;
  final _events = kalender.DefaultEventsController();
  final _monthScroll = ScrollController();
  late kalender.ViewConfiguration _configuration;
  var _awaitingScheduleEvents = false;
  DateTime? _pickedDay;
  static final _interaction = kalender.KalenderInteraction(
    allowEventCreation: false,
    allowRescheduling: false,
    allowResizing: false,
  );

  String get _locale => Localizations.localeOf(context).toString();
  bool get _touch => switch (Theme.of(context).platform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
  bool get _use24HourClock => use24HourClockOf(context);
  String _time(DateTime value) =>
      clockTime(value, use24HourClock: _use24HourClock, locale: _locale);
  EventCalendarView get _view => widget.page.view;
  bool get _schedule => _view == EventCalendarView.schedule;
  DateTime _now() => tz.TZDateTime.from(widget.clock(), widget.location);
  DateTime _inCalendar(DateTime day) =>
      tz.TZDateTime(widget.location, day.year, day.month, day.day);
  DateTimeRange get _days => widget.page.days(firstDay: widget.firstDay);
  DateTime get _todayDate {
    final now = _now();
    return DateTime.utc(now.year, now.month, now.day);
  }

  bool _inPageMonth(DateTime day) =>
      day.year == widget.page.date.year && day.month == widget.page.date.month;

  /// The wide month's day panel follows the reader's pick while it stays in
  /// the shown month, otherwise today when shown, otherwise the first.
  DateTime get _selectedDay => switch (_pickedDay) {
    final day? when _inPageMonth(day) => day,
    _ when _inPageMonth(_todayDate) => _todayDate,
    _ => DateTime.utc(widget.page.date.year, widget.page.date.month),
  };

  @override
  void initState() {
    super.initState();
    unawaited(_localeData);
    _awaitingScheduleEvents = _schedule && widget.events.isEmpty;
    _configure();
    _calendar = kalender.KalenderController(
      viewConfiguration: _configuration,
      location: widget.location,
    );
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
      _calendar
        ..location = widget.location
        ..viewConfiguration = _configuration;
      if (_monthScroll.hasClients) _monthScroll.jumpTo(0);
    }
    if (eventsChanged) _replaceEvents();
    if (pageChanged || scheduleLoaded) {
      // initialDateTime only applies at first mount. Route and toolbar changes
      // must also navigate an existing view after its configuration updates.
      final page = widget.page;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.page == page) {
          final view = _calendar.viewController;
          if (_schedule && view is kalender.ScheduleViewController) {
            final index =
                view.indexFromDateTime(_inCalendar(page.date)) ??
                view.closestIndex(_inCalendar(page.date));
            if (view.itemScrollController?.isAttached == true) {
              view.itemScrollController!.jumpTo(index: index);
            }
          } else {
            _calendar.jumpToDate(_inCalendar(page.date));
          }
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
          name: appL10n.schedule,
          initialDateTime: date,
          dateResolver: (_) =>
              kalender.FloatingDateTime.fromDateTime(widget.page.date),
          // The toolbar owns months; keep the schedule on its requested month.
          displayRange: kalender.KalenderDateTimeRange(
            start: _inCalendar(_days.start),
            end: _inCalendar(_days.end),
          ),
          nowCallback: _now,
        ),
      // Core's Year button is FullCalendar listYear: an agenda for that year.
      EventCalendarView.year => kalender.ScheduleViewConfiguration.continuous(
        name: appL10n.year,
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

  void _selectView(EventCalendarView view) {
    widget.onViewSelected?.call();
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
    if (inView) {
      if (_schedule) {
        final view =
            _calendar.viewController as kalender.ScheduleViewController;
        final index = view.indexFromDateTime(_inCalendar(today));
        if (index != null && view.itemScrollController?.isAttached == true) {
          if (MediaQuery.disableAnimationsOf(context)) {
            view.itemScrollController!.jumpTo(index: index);
          } else {
            unawaited(
              view.itemScrollController!.scrollTo(
                index: index,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
              ),
            );
          }
        }
      } else {
        unawaited(_calendar.animateToDate(_inCalendar(today)));
      }
    }
  }

  Widget _select<T extends Object>(
    String label,
    List<T> values,
    String Function(T value) describe,
    T selected,
    ValueChanged<T>? onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (!values.contains(selected)) Text(describe(selected)),
      DToggleGroup<T>(
        size: DControlSize.segment,
        inset: true,
        semanticLabel: label,
        allowEmptySelection: false,
        values: values.contains(selected) ? [selected] : const [],
        onChanged: onChanged == null
            ? null
            : (choices) => onChanged(choices.single),
        items: [
          for (final value in values)
            DToggleGroupItem(value: value, child: Text(describe(value))),
        ],
      ),
    ],
  );

  Widget _toolbar(BuildContext context, {required bool oneRow}) {
    final tokens = DTokens.of(context);
    Widget navigation(int direction) => DButton.iconOnly(
      variant: DButtonVariant.quiet,
      size: DControlSize.filter,
      icon: DIcon(
        direction < 0 ? DIcons.chevronLeft : DIcons.chevronRight,
        size: 11,
      ),
      tooltip: context.l10n.messageEventcalendar(
        (direction < 0).toString(),
        (_schedule).toString(),
        ((direction < 0) ? (context.l10n.previous) : '').toString(),
        ((!(_schedule)) ? (_view.name) : '').toString(),
        ((!(direction < 0)) ? (context.l10n.next) : '').toString(),
      ),
      onPressed:
          widget.page.move(direction).date.year >= 1900 &&
              widget.page.move(direction).date.year < 2200
          ? () => widget.onPageChanged(widget.page.move(direction))
          : null,
    );
    final scope = _select(
      context.l10n.eventFilter,
      const [false, true],
      (mine) => mine ? context.l10n.myEvents : context.l10n.allEvents,
      widget.mine,
      widget.onMineChanged,
    );
    // Route-supplied views stay active until a choice is made.
    final views = _select(
      context.l10n.calendarView,
      const [EventCalendarView.month, EventCalendarView.schedule],
      (view) => view.label,
      _view,
      _selectView,
    );
    final today = _schedule
        ? null
        : DButton(
            variant: DButtonVariant.outline,
            size: DControlSize.chip,
            label: Text(context.l10n.todayDcalendarevents),
            onPressed: _today,
          );
    if (oneRow) {
      return Row(
        key: const ValueKey('event-calendar-header'),
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Semantics(
                    header: true,
                    child: Text(
                      toBeginningOfSentenceCase(_period, _locale),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tokens.foreground,
                        fontSize: DiscourseTypography.lg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                navigation(-1),
                navigation(1),
                if (today != null) ...[const SizedBox(width: 8), today],
              ],
            ),
          ),
          const SizedBox(width: 8),
          scope,
          const SizedBox(width: 8),
          views,
        ],
      );
    }
    return Padding(
      key: const ValueKey('event-calendar-header'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DControlWrap(
            direction: Axis.vertical,
            wrap: false,
            spacing: 10,
            children: [
              DControlWrap(
                wrap: false,
                spacing: 8,
                children: [
                  DControlExpanded(
                    child: DControlWrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [scope, views],
                    ),
                  ),
                  ?today,
                ],
              ),
              DControlWrap(
                wrap: false,
                spacing: 8,
                children: [
                  navigation(-1),
                  DControlExpanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        toBeginningOfSentenceCase(_period, _locale),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: tokens.foreground,
                          fontSize: DiscourseTypography.compact,
                          height: DiscourseTypography.lineHeightSmall,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  navigation(1),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      final split = !compact && constraints.maxWidth >= 1000;
      return DPageSurface.headed(
        title: Text(context.l10n.events),
        controls: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DReferenceTextScale(
              child: LayoutBuilder(
                builder: (context, constraints) => _toolbar(
                  context,
                  // One row fits the period, navigation and both switches
                  // only on wide windows at ordinary text sizes.
                  oneRow:
                      constraints.maxWidth >= (_touch ? 900 : 760) &&
                      MediaQuery.textScalerOf(context).scale(14) <= 18,
                ),
              ),
            ),
            ?widget.status,
          ],
        ),
        child: Padding(
          // Mobile scroll fades reach the page edge beneath the dock.
          padding: EdgeInsets.fromLTRB(16, 0, 16, _touch ? 0 : 16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Retain Kalender's controllers and scroll position while
              // replacing stale content with the loading placeholders.
              ExcludeFocus(
                excluding: widget.loading,
                child: Visibility(
                  visible: !widget.loading,
                  maintainState: true,
                  child: _buildCalendar(compact: compact, split: split),
                ),
              ),
              if (widget.loading)
                EventCalendarSkeleton(
                  view: _view,
                  dayCount: _days.duration.inDays,
                  month: EventMonthMetrics(
                    layout: compact
                        ? EventMonthLayout.compact
                        : split
                        ? EventMonthLayout.split
                        : EventMonthLayout.grid,
                    dayHeaderHeight: _dayHeaderHeight,
                    laneHeight: _monthTileHeight,
                    panelWidth: _dayPanelWidth,
                    panelGap: _dayPanelGap,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _buildCalendar({required bool compact, required bool split}) {
    final tokens = DTokens.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final rowHeight = math.max(
      _touch ? kMinInteractiveDimension : DControlStyle.smallHeight,
      scaler.scale(DiscourseTypography.sm) *
              DiscourseTypography.lineHeightSmall +
          10,
    );
    // Month lanes are a dense summary; the day popover is the full list.
    final monthTileHeight = _monthTileHeight;
    final tiles = kalender.TileComponents(tileBuilder: _tile);
    final overlays = kalender.OverlayBuilders(
      multiDayOverlayPortalBuilder:
          (
            context, {
            required date,
            required events,
            required numberOfHiddenRows,
            required tileHeight,
            required overlayBuilders,
          }) => Builder(
            builder: (context) => DCalendarEventAction(
              semanticLabel: appL10n.moreEventcalendar(
                numberOfHiddenRows.toString(),
              ),
              onPressed: () => _openDay(date, anchor: _anchorOf(context)),
              child: Text(
                appL10n.moreEventcalendar(numberOfHiddenRows.toString()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.mutedForeground,
                  fontSize: DiscourseTypography.xs,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
    );
    final monthBody = kalender.MonthBody(
      tileComponents: tiles,
      configuration: kalender.MonthBodyConfiguration(
        tileHeight: monthTileHeight,
        multiDayLayoutStrategy: const EventCalendarLayout(),
      ),
    );
    final scheduleBody = kalender.ScheduleBody(
      tileComponents: kalender.ScheduleTileComponents(
        tileBuilder: _schedule
            ? _scheduleTile
            : (context, event, range) => SizedBox(
                height: rowHeight + 12,
                child: _tile(context, event, range),
              ),
      ),
      configuration: kalender.ScheduleBodyConfiguration(
        emptyDay: _schedule
            ? kalender.EmptyDayBehavior.showOnlyToday
            : kalender.EmptyDayBehavior.hide,
        leadingWidth: _schedule ? 0 : 56,
      ),
    );
    return DKalenderTheme(
      compactMonthLayout: false,
      child: kalender.KalenderView(
        eventsController: _events,
        kalenderController: _calendar,
        locale: Localizations.localeOf(context),
        callbacks: kalender.KalenderCallbacks(onPageChanged: _pageChanged),
        components: kalender.KalenderComponents(
          scheduleComponents: _schedule
              ? kalender.ScheduleComponents(
                  leadingDateBuilder: (context, date) =>
                      const SizedBox.shrink(),
                  monthItemBuilder: (context, range) => const SizedBox.shrink(),
                  emptyItemBuilder: (context, range) {
                    final day = DateTime.utc(
                      range.start.year,
                      range.start.month,
                      range.start.day,
                    );
                    return DCalendarScheduleRow(
                      date: day,
                      rowId: 'empty',
                      child: DCalendarScheduleEntry.empty(
                        dayLabel: DateFormat('EEE d', _locale).format(day),
                        today: true,
                        title: context.l10n.nothingPlanned,
                      ),
                    );
                  },
                  scheduleTileHighlightBuilder: (context, date, range, child) =>
                      child,
                )
              : const kalender.ScheduleComponents(),
          monthComponents: kalender.MonthComponents(
            headerComponents: kalender.MonthHeaderComponents(
              weekDayHeaderBuilder: (context, date) =>
                  DCalendarWeekdayHeader(date: date, start: !compact && !split),
            ),
            bodyComponents: kalender.MonthBodyComponents(
              monthGridBuilder: (context, rows) => kalender.MonthGrid(
                numberOfRows: rows,
                style: kalender.MonthGridStyle(
                  color: tokens.border.withValues(alpha: .55),
                  thickness: 1,
                ),
              ),
              monthDayHeaderBuilder: _dayHeader,
              monthDayCellBuilder: (context, details) => ColoredBox(
                color: details.isToday
                    ? tokens.primary.withValues(alpha: .08)
                    : !details.isInFocusedMonth
                    ? tokens.muted.withValues(alpha: .45)
                    : details.date.weekday >= DateTime.saturday
                    ? tokens.muted.withValues(alpha: .2)
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
        interaction: _interaction,
        views: [
          kalender.MultiDayViewParts(
            header: kalender.MultiDayHeader(
              tileComponents: tiles,
              configuration: kalender.MultiDayHeaderConfiguration(
                maximumNumberOfVerticalEvents: 4,
                tileHeight: rowHeight,
              ),
            ),
            body: kalender.MultiDayBody(
              tileComponents: kalender.TileComponents(
                tileBuilder: (context, event, range) =>
                    _tile(context, event, range, timeline: true),
              ),
            ),
          ),
          kalender.ScheduleViewParts(
            body: _schedule ? _buildSchedule(scheduleBody) : scheduleBody,
          ),
          kalender.MonthViewParts(
            // Weekday names stay over the month's columns, not the day panel.
            header: split
                ? const Padding(
                    padding: EdgeInsetsDirectional.only(
                      end: _dayPanelWidth + _dayPanelGap,
                    ),
                    child: kalender.MonthHeader(),
                  )
                : null,
            body: split
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: DKalenderCompactMonthBody(
                          onDayPressed: (day) =>
                              setState(() => _pickedDay = day),
                          eventColor: (event) =>
                              (event as EventCalendarEntry).color,
                          layoutStrategy: const EventCalendarLayout(),
                          selectedDate: _selectedDay,
                          fillHeight: true,
                        ),
                      ),
                      const SizedBox(width: _dayPanelGap),
                      SizedBox(
                        width: _dayPanelWidth,
                        child: _dayPanel(_selectedDay),
                      ),
                    ],
                  )
                : compact
                ? DKalenderCompactMonthBody(
                    onDayPressed: _openDay,
                    eventColor: (event) => (event as EventCalendarEntry).color,
                    layoutStrategy: const EventCalendarLayout(),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // The month fits the window and crowded days collapse
                      // into "+N more". Only windows too short for three lanes
                      // and the overflow row scroll.
                      final weeks = _days.duration.inDays ~/ 7;
                      final height = math.max(
                        constraints.maxHeight,
                        weeks * (_dayHeaderHeight + 4 * monthTileHeight),
                      );
                      return DScrollBar(
                        controller: _monthScroll,
                        child: SingleChildScrollView(
                          controller: _monthScroll,
                          child: SizedBox(height: height, child: monthBody),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchedule(Widget body) {
    final now = _now();
    final today = DateTime.utc(now.year, now.month, now.day);
    return DCalendarScheduleViewport(
      days: [
        for (
          var day = _days.start;
          day.isBefore(_days.end);
          day = day.add(const Duration(days: 1))
        )
          if (day == today || widget.events.any((event) => event.includes(day)))
            DCalendarScheduleDayData(
              date: day,
              label: DateFormat('EEE d', _locale).format(day),
              today: day == today,
              rows: [
                for (final event in _events.eventsInRange(
                  kalender.FloatingDateTimeRange(
                    start: kalender.FloatingDateTime.fromDateTime(day),
                    end: kalender.FloatingDateTime.fromDateTime(
                      day.add(const Duration(days: 1)),
                    ),
                  ),
                  multiDayRule: _configuration.multiDayRule,
                  location: widget.location,
                ))
                  event.id,
                if (!widget.events.any((event) => event.includes(day))) 'empty',
              ],
            ),
      ],
      missingTodayPosition: today.isBefore(_days.start)
          ? DCalendarScheduleTodayPosition.before
          : today.isBefore(_days.end)
          ? DCalendarScheduleTodayPosition.visible
          : DCalendarScheduleTodayPosition.after,
      todayLabel: context.l10n.todayDcalendarevents,
      onToday: _today,
      bottomInset: math.max(
        MediaQuery.paddingOf(context).bottom,
        DScrollChrome.bottomInsetOf(context),
      ),
      child: DKalenderScheduleBody(child: body),
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
    final dayEvents = _events
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
        .toList();
    final first = dayEvents.firstOrNull;
    final now = _now();
    final today = day == DateTime.utc(now.year, now.month, now.day);
    final metadata = event.scheduleMetadata(day);
    return DCalendarScheduleRow(
      date: day,
      rowId: event.id,
      child: DCalendarScheduleEntry(
        dayLabel: first?.id == event.id
            ? DateFormat('EEE d', _locale).format(day)
            : null,
        today: today,
        time: _scheduleTime(event),
        title: event.title,
        subtitle: metadata.isEmpty ? null : metadata,
        color: event.color,
        onPressed: () => widget.onOpen(event),
      ),
    );
  }

  double get _dayHeaderHeight => _touch ? 36 : 28;

  double get _monthTileHeight => math.max(
    _touch ? kMinInteractiveDimension : 20.0,
    MediaQuery.textScalerOf(context).scale(DiscourseTypography.xs) * 1.3 + 4,
  );

  Widget _dayHeader(BuildContext context, DateTime date) {
    final tokens = DTokens.of(context);
    final day = DateTime.utc(date.year, date.month, date.day);
    final today = day == _todayDate;
    final outside = date.month != widget.page.date.month;
    final scaler = MediaQuery.textScalerOf(context);
    final number = Container(
      constraints: BoxConstraints(
        minWidth: scaler.scale(22),
        minHeight: scaler.scale(22),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: today
          ? BoxDecoration(color: tokens.primary, shape: BoxShape.circle)
          : null,
      child: Text(
        '${date.day}',
        style: TextStyle(
          fontSize: DiscourseTypography.xs,
          fontWeight: FontWeight.w600,
          color: today
              ? tokens.primaryForeground
              : outside
              ? tokens.mutedForeground
              : tokens.foreground,
        ),
      ),
    );
    return SizedBox(
      height: _dayHeaderHeight,
      child: Builder(
        builder: (context) => DCalendarDayButton(
          details: DCalendarDayDetails(
            date: DCalendarDate.fromDateTime(date),
            outside: outside,
            today: today,
            disabled: false,
            hidden: false,
            booked: false,
            selected: false,
            rangeStart: false,
            rangeMiddle: false,
            rangeEnd: false,
          ),
          onPressed: () => _openDay(date, anchor: _anchorOf(context)),
          semanticLabel: DateFormat.yMMMMEEEEd(_locale).format(date),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  number,
                  if (date.day == 1)
                    Flexible(
                      child: Text(
                        DateFormat.MMM(_locale).format(date),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DiscourseTypography.xs,
                          color: tokens.mutedForeground,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The overlay-local bounds a day popover anchors to.
  Rect? _anchorOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(
              context,
              rootNavigator: true,
            ).overlay?.context.findRenderObject()
            as RenderBox?;
    if (box == null || overlay == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  }

  List<EventCalendarEntry> _eventsOn(DateTime day) =>
      widget.events.where((event) => event.includes(day)).toList()
        ..sort((a, b) {
          if (a.isAllDay != b.isAllDay) return a.isAllDay ? -1 : 1;
          final time = (a.localStart.hour * 60 + a.localStart.minute).compareTo(
            b.localStart.hour * 60 + b.localStart.minute,
          );
          return time != 0 ? time : a.id.compareTo(b.id);
        });

  Widget _dayPanel(DateTime day) {
    final tokens = DTokens.of(context);
    final events = _eventsOn(day);
    return DecoratedBox(
      key: const ValueKey('event-calendar-day-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Semantics(
              header: true,
              child: Text(
                DateFormat.MMMMEEEEd(_locale).format(day),
                style: TextStyle(
                  fontSize: DiscourseTypography.lg,
                  fontWeight: FontWeight.w700,
                  color: tokens.foreground,
                ),
              ),
            ),
          ),
          Expanded(
            child: DKalenderScheduleBody(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  if (events.isEmpty)
                    DCalendarScheduleEntry.empty(
                      dayLabel: null,
                      title: context.l10n.nothingPlanned,
                    ),
                  for (final event in events)
                    DCalendarScheduleEntry(
                      time: _scheduleTime(event),
                      title: event.title,
                      subtitle: switch (event.scheduleMetadata(day)) {
                        '' => null,
                        final metadata => metadata,
                      },
                      color: event.color,
                      onPressed: () => widget.onOpen(event),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _scheduleTime(EventCalendarEntry event) => event.isAllDay
      ? context.l10n.allDay
      : _use24HourClock
      ? _time(event.localStart)
      : (event.localStart.minute == 0
                ? DateFormat.j(_locale)
                : DateFormat.jm(_locale))
            .format(event.localStart)
            .toLowerCase()
            .replaceAll('\u202f', ' ');

  Widget _dayEventList(
    List<EventCalendarEntry> events,
    VoidCallback close,
    bool Function() isCurrent,
  ) => ListView.builder(
    shrinkWrap: true,
    itemCount: events.length,
    itemBuilder: (context, index) {
      final event = events[index];
      return DItem(
        onPressed: () {
          close();
          if (isCurrent()) widget.onOpen(event);
        },
        children: [
          DIcon(
            event.event.recurring ? DNativeIcons.repeat : DIcons.calendarDays,
            color: event.color,
          ),
          DItemContent(
            children: [
              DItemTitle(maxLines: null, child: Text(event.title)),
              DItemDescription(child: Text(_timeLabel(event))),
            ],
          ),
        ],
      );
    },
  );

  void _openDay(DateTime date, {Rect? anchor}) {
    final source = widget.events;
    final page = widget.page;
    bool isCurrent() =>
        mounted && identical(source, widget.events) && page == widget.page;
    final day = DateTime.utc(date.year, date.month, date.day);
    final events = _eventsOn(day);
    final title = DateFormat.yMMMMEEEEd(_locale).format(day);
    if (anchor != null && !_touch) {
      unawaited(
        showDPopover(
          context: context,
          useRootNavigator: true,
          anchorRect: anchor,
          anchorMode: DPopoverAnchorMode.rectangle,
          builder: (popover) => DPopoverContent(
            width: 320,
            constraints: BoxConstraints(
              maxHeight: math.min(460, MediaQuery.sizeOf(context).height * .6),
            ),
            side: DPopoverSide.bottom,
            align: DPopoverAlign.start,
            semanticLabel: title,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DPopoverHeader(children: [DPopoverTitle(child: Text(title))]),
                if (events.isEmpty)
                  Text(appL10n.noEventsOnThisDay)
                else
                  Flexible(
                    child: _dayEventList(
                      events,
                      () => Navigator.of(popover).maybePop(),
                      isCurrent,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    unawaited(
      showDDialog<void>(
        context: context,
        builder: (context, dialog) => DDialogContent(
          maxWidth: 520,
          children: [
            DDialogHeader(children: [DDialogTitle(child: Text(title))]),
            if (events.isEmpty)
              Text(appL10n.noEventsOnThisDay)
            else
              SizedBox(
                height: math.min(420, MediaQuery.sizeOf(context).height * .5),
                child: _dayEventList(events, dialog.close, isCurrent),
              ),
            // The toolbar offers only Month and Schedule, so the dialog is the
            // day's whole presentation rather than a way into a Day view.
            DDialogFooter(
              children: [
                DButton(
                  variant: DButtonVariant.ghost,
                  onPressed: dialog.close,
                  label: Text(appL10n.close),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(EventCalendarEntry event) => event.isAllDay
      ? appL10n.allDay
      : '${_time(event.localStart)} – ${_time(event.localEnd)}';

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
    final tokens = DTokens.of(context);
    final background = event.color ?? colors.primary;
    // Timelines keep solid blocks; month and year lanes stay quiet so only
    // the category color marks an event.
    final foreground = !timeline
        ? tokens.foreground
        : (background.computeLuminance() > 0.179 ? Colors.black : Colors.white);
    final label =
        '${event.title}, ${DateFormat.yMMMd(_locale).format(event.localStart)}, ${_timeLabel(event)}';
    return DTooltip(
      message: label,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 100;
          final text = Text.rich(
            TextSpan(
              children: [
                if (!event.isAllDay && !compact)
                  TextSpan(
                    text: context.l10n.messageEventcalendarValue(
                      (timeline).toString(),
                      ((timeline) ? (_timeLabel(event)) : '').toString(),
                      ((!(timeline)) ? (_time(event.localStart)) : '')
                          .toString(),
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.normal,
                      color: timeline ? null : tokens.mutedForeground,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                if (event.event.recurring && timeline)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 2),
                      child: DIcon(
                        DNativeIcons.repeat,
                        size: 13,
                        color: foreground,
                      ),
                    ),
                  ),
                TextSpan(text: event.title),
              ],
            ),
            maxLines: timeline ? null : 1,
            overflow: timeline ? TextOverflow.clip : TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: foreground,
              fontSize: timeline ? null : DiscourseTypography.xs,
              height: timeline ? null : 1.3,
              fontWeight: FontWeight.normal,
            ),
          );
          final action = DCalendarEventAction(
            backgroundColor: !block
                ? Colors.transparent
                : timeline
                ? background
                : background.withValues(alpha: .22),
            semanticLabel: label,
            onPressed: () => widget.onOpen(event),
            child: ExcludeSemantics(
              child: Row(
                crossAxisAlignment: timeline
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  if (!block) ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 5),
                      child: DIcon(
                        DIcons.circle,
                        size: 6,
                        color: event.color ?? colors.outline,
                      ),
                    ),
                  ],
                  Expanded(child: text),
                ],
              ),
            ),
          );
          if (!block || timeline) return action;
          return DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: background, width: 3),
              ),
            ),
            child: action,
          );
        },
      ),
    );
  }
}
