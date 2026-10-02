import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart';
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
  late final kalender.KalenderController _calendar;
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
  bool get _use24HourClock => use24HourClockOf(context);
  String _time(DateTime value) =>
      clockTime(value, use24HourClock: _use24HourClock, locale: _locale);
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
    if (inView) unawaited(_calendar.animateToDate(_inCalendar(today)));
  }

  Widget _select<T extends Object>(
    String label,
    List<T> values,
    String Function(T value) describe,
    T selected,
    ValueChanged<T>? onChanged, {
    bool lead = false,
  }) => DSelect<T>.controlled(
    size: DControlSize.filter,
    value: selected,
    semanticLabel: label,
    width: 190,
    maxPopupHeight: 280,
    align: DPopoverAlign.start,
    alignItemWithTrigger: false,
    enabled: onChanged != null,
    entries: [
      for (final value in values)
        DSelectItem(
          value: value,
          textValue: describe(value),
          child: Text(describe(value)),
        ),
    ],
    onChanged: (value) {
      if (value != null) onChanged?.call(value);
    },
    triggerBuilder: (context, state, _) => DButton(
      size: DControlSize.filter,
      variant: DButtonVariant.outline,
      focusNode: state.focusNode,
      hasPopup: true,
      expanded: state.open,
      semanticLabel: label,
      icon: DIcon(
        DIcons.chevronDown,
        size: DControlStyle.chevronDimension(DControlSize.filter),
      ),
      iconPosition: DButtonIconPosition.end,
      onPressed: state.enabled ? state.toggle : null,
      label: Text(
        describe(selected),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: lead ? FontWeight.w600 : FontWeight.w400),
      ),
    ),
  );

  Widget _toolbar(BuildContext context) {
    final tokens = DTokens.of(context);
    Widget navigation(int direction) => DButton.iconOnly(
      variant: DButtonVariant.outline,
      size: DControlSize.chip,
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
    return Padding(
      key: const ValueKey('event-calendar-header'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              context.l10n.events,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: tokens.foreground,
                fontSize: DiscourseTypography.xxl,
                height: DiscourseTypography.lineHeightHeading,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
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
                      children: [
                        _select(
                          context.l10n.eventFilter,
                          const [false, true],
                          (mine) => mine
                              ? context.l10n.myEvents
                              : context.l10n.allEvents,
                          widget.mine,
                          widget.onMineChanged,
                          lead: true,
                        ),
                        // A page in a view the select does not offer still
                        // names that view on the trigger.
                        _select(
                          context.l10n.calendarView,
                          const [
                            EventCalendarView.month,
                            EventCalendarView.schedule,
                          ],
                          (view) => view.label,
                          _view,
                          _selectView,
                        ),
                      ],
                    ),
                  ),
                  DButton(
                    variant: DButtonVariant.outline,
                    size: DControlSize.chip,
                    label: Text(context.l10n.todayDcalendarevents),
                    onPressed: _today,
                  ),
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
          const SizedBox(height: 14),
          DSeparator(
            color: Color.lerp(tokens.background, tokens.foreground, .12),
          ),
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
          _toolbar(context),
          ?widget.status,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                      child: _buildCalendar(compact: compact),
                    ),
                  ),
                  if (widget.loading)
                    EventCalendarSkeleton(
                      view: _view,
                      dayCount: _days.duration.inDays,
                    ),
                ],
              ),
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
            required overlayBuilders,
          }) => DButton(
            onPressed: () => _openDay(date),
            variant: DButtonVariant.ghost,
            size: DButtonSize.small,
            label: Text(
              appL10n.moreEventcalendar((numberOfHiddenRows).toString()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
    );
    final monthBody = kalender.MonthBody(
      tileComponents: tiles,
      configuration: kalender.MonthBodyConfiguration(
        tileHeight: rowHeight,
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
        emptyDay: kalender.EmptyDayBehavior.hide,
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
            body: _schedule
                ? DKalenderScheduleBody(child: scheduleBody)
                : scheduleBody,
          ),
          kalender.MonthViewParts(
            body: compact
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
          ? context.l10n.allDay
          : _use24HourClock
          ? _time(event.localStart)
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
              Text(appL10n.noEventsOnThisDay)
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
                          text: context.l10n.messageEventcalendarValue(
                            (timeline).toString(),
                            ((timeline) ? (_timeLabel(event)) : '').toString(),
                            ((!(timeline)) ? (_time(event.localStart)) : '')
                                .toString(),
                          ),
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
