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
import 'event_day_agenda.dart';

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
    this.creatorAvatar,
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
  final Widget? Function(EventPerson)? creatorAvatar;
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
  DateTime? _pickedDay;
  bool _phoneDayVisible = true;
  bool _phoneDayExpanded = false;
  int _phonePanelRevision = 0;
  DateTime? _phonePanelAnchor;
  String _query = '';
  late List<EventCalendarEntry> _shownEvents;
  DScrollChromeController? _chrome;
  bool _hideDock = false;
  bool _turningPhoneMonth = false;
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

  DateTime get _selectedDay => switch (_pickedDay) {
    final day? when _inPageMonth(day) => day,
    _ when widget.page.date.day != 1 => widget.page.date,
    _ when _inPageMonth(_todayDate) => _todayDate,
    _ => _firstAgendaDay(
      widget.page.date,
      DateTime.utc(widget.page.date.year, widget.page.date.month + 1),
    ),
  };

  DateTime _firstAgendaDay(DateTime first, DateTime end) {
    final today = _todayDate;
    for (
      var day = first;
      day.isBefore(end);
      day = day.add(const Duration(days: 1))
    ) {
      if (day == today || _shownEvents.any((event) => event.includes(day))) {
        return day;
      }
    }
    return first;
  }

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
    if (oldWidget.page.date != widget.page.date &&
        !_inPageMonth(oldWidget.page.date)) {
      if (_pickedDay case final picked? when !_inPageMonth(picked)) {
        _pickedDay = null;
        _phonePanelAnchor = null;
      }
    }
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

  void _search(String query) {
    setState(() {
      _query = query;
      _replaceEvents();
    });
  }

  void _replaceEvents() {
    final words = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    _shownEvents = words.isEmpty
        ? widget.events
        : widget.events.where((entry) {
            final creator = entry.event.creator;
            final fields = <String>[
              entry.title,
              ?entry.categoryName,
              ?creator?.name,
              ?(creator?.username ??
                  eventText(
                    eventObject(entry.event.fields['post'])?['username'],
                  )),
            ].map((value) => value.toLowerCase()).toList();
            return words.every(
              (word) => fields.any((field) => field.contains(word)),
            );
          }).toList();
    final events = [..._shownEvents]
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
    if (_view == EventCalendarView.year || _turningPhoneMonth) return;
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
    _chrome?.setFooterHidden(this, hidden: false);
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

  Widget _filters(BuildContext context, {required bool phoneMonth}) {
    final l10n = context.l10n;
    return Row(
      spacing: DSpacing.sm,
      children: [
        Expanded(
          child: DInputGroup(
            variant: DInputGroupVariant.quiet,
            size: DControlSize.filter,
            children: [
              DInput(
                value: _query,
                hintText: l10n.findAnEvent,
                semanticLabel: l10n.findAnEvent,
                onChanged: _search,
              ),
              const DInputGroupAddon(child: DIcon(DIcons.magnifyingGlass)),
              if (_query.isNotEmpty)
                DInputGroupAddon(
                  alignment: DInputGroupAddonAlignment.inlineEnd,
                  child: DInputGroupButton.icon(
                    icon: const DIcon(DIcons.xmark),
                    tooltip: l10n.clearSearch,
                    onPressed: () => _search(''),
                  ),
                ),
            ],
          ),
        ),
        DReferenceTextScale(
          child: DToggleGroup<bool>(
            size: DControlSize.segment,
            inset: true,
            allowEmptySelection: false,
            semanticLabel: l10n.eventFilter,
            values: [widget.mine],
            items: [
              DToggleGroupItem.iconOnly(
                value: false,
                icon: const DIcon(DIcons.users, size: 13),
                semanticLabel: l10n.allEvents,
                tooltip: l10n.allEvents,
              ),
              DToggleGroupItem.iconOnly(
                value: true,
                icon: const DIcon(DIcons.user, size: 13),
                semanticLabel: l10n.myEvents,
                tooltip: l10n.myEvents,
              ),
            ],
            onChanged: widget.onMineChanged == null
                ? null
                : (values) => widget.onMineChanged?.call(values.single),
          ),
        ),
        if (!_schedule && _view != EventCalendarView.month) Text(_view.label),
        if (!phoneMonth)
          DReferenceTextScale(
            child: DToggleGroup<EventCalendarView>(
              size: DControlSize.segment,
              inset: true,
              allowEmptySelection: false,
              semanticLabel: l10n.calendarView,
              values: [
                if (_schedule || _view == EventCalendarView.month) _view,
              ],
              items: [
                DToggleGroupItem.iconOnly(
                  value: EventCalendarView.month,
                  icon: const DIcon(DIcons.calendarDays, size: 13),
                  semanticLabel: l10n.month,
                  tooltip: l10n.month,
                ),
                DToggleGroupItem.iconOnly(
                  value: EventCalendarView.schedule,
                  icon: const DIcon(DIcons.list, size: 13),
                  semanticLabel: l10n.schedule,
                  tooltip: l10n.schedule,
                ),
              ],
              onChanged: (values) => _selectView(values.single),
            ),
          ),
      ],
    );
  }

  Widget _periodControls(BuildContext context, {required bool showToday}) {
    final tokens = DTokens.of(context);
    Widget navigation(int direction) {
      final next = widget.page.move(direction);
      return DButton.iconOnly(
        variant: DButtonVariant.quiet,
        size: DControlSize.filter,
        icon: DIcon(
          direction < 0 ? DIcons.chevronLeft : DIcons.chevronRight,
          size: 11,
        ),
        tooltip: context.l10n.messageEventcalendar(
          (direction < 0).toString(),
          _schedule.toString(),
          direction < 0 ? context.l10n.previous : '',
          _schedule ? '' : _view.name,
          direction > 0 ? context.l10n.next : '',
        ),
        onPressed: next.date.year >= 1900 && next.date.year < 2200
            ? () => widget.onPageChanged(next)
            : null,
      );
    }

    return Row(
      spacing: DSpacing.sm,
      children: [
        navigation(-1),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              toBeginningOfSentenceCase(_period, _locale),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
        if (showToday)
          DButton(
            variant: DButtonVariant.outline,
            size: DControlSize.chip,
            label: Text(context.l10n.todayDcalendarevents),
            onPressed: _today,
          ),
      ],
    );
  }

  void _syncDock(BuildContext context, bool hidden) {
    final chrome = DScrollChrome.maybeOf(context);
    final hide = hidden && TickerMode.valuesOf(context).enabled;
    if (identical(_chrome, chrome) && _hideDock == hide) return;
    final previous = _chrome;
    _chrome = chrome;
    _hideDock = hide;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!identical(previous, _chrome)) {
        previous?.setFooterHidden(this, hidden: false);
      }
      if (mounted && identical(chrome, _chrome)) {
        chrome?.setFooterHidden(this, hidden: _hideDock);
      }
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      final phoneMonth = compact && _touch && _view == EventCalendarView.month;
      final phoneDay = phoneMonth && _phoneDayVisible;
      final weekFocused = phoneDay && _phoneDayExpanded;
      _syncDock(context, phoneDay);
      return DPageSurface.headed(
        title: Text(context.l10n.events),
        controls: _filters(context, phoneMonth: phoneMonth),
        secondaryControls: Column(
          key: const ValueKey('event-calendar-header'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSwitcher(
              duration: DMotion.duration(context, DMotion.change),
              transitionBuilder: (child, animation) => SizeTransition(
                sizeFactor: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: weekFocused
                  ? const SizedBox.shrink()
                  : DReferenceTextScale(
                      child: _periodControls(
                        context,
                        showToday: !_schedule && !phoneMonth,
                      ),
                    ),
            ),
            if (widget.events.isNotEmpty && _shownEvents.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: DSpacing.sm),
                child: Text(context.l10n.noEventsMatchYourSearch),
              ),
            ?widget.status,
          ],
        ),
        child: Padding(
          // Mobile scroll fades reach the page edge beneath the dock.
          padding: EdgeInsets.only(bottom: _touch ? 0 : 16),
          child: LayoutBuilder(
            builder: (context, bounds) {
              final weekdayExtent = math.max(
                32.0,
                MediaQuery.textScalerOf(context).scale(12) * 1.3 + 8,
              );
              final weekRoom =
                  DKalenderCompactMonthBody.phoneWeekExtentOf(context) +
                  weekdayExtent +
                  DSpacing.sm;
              final rest = bounds.maxHeight * .51;
              final showPanels = phoneDay && !widget.loading;
              final panelHeight = weekFocused
                  ? math.max(rest, bounds.maxHeight - weekRoom)
                  : rest;
              final motion = DMotion.duration(context, DMotion.change);
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Retain Kalender while showing the next month's loading state.
                  AnimatedPadding(
                    duration: motion,
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.only(
                      bottom: showPanels ? panelHeight : 0,
                    ),
                    child: ExcludeFocus(
                      excluding: widget.loading,
                      child: Visibility(
                        visible: !widget.loading,
                        maintainState: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildCalendar(
                            compact: compact,
                            phoneMonth: phoneMonth,
                            weekFocused: weekFocused,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (phoneMonth)
                    AnimatedPositioned(
                      duration: motion,
                      curve: Curves.easeOutCubic,
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: panelHeight,
                      child: IgnorePointer(
                        ignoring: !showPanels,
                        child: AnimatedSwitcher(
                          duration: widget.loading ? Duration.zero : motion,
                          transitionBuilder: (child, animation) =>
                              SlideTransition(
                                position:
                                    Tween(
                                      begin: const Offset(0, 1),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    ),
                                child: child,
                              ),
                          child: showPanels
                              ? KeyedSubtree(
                                  key: const ValueKey('open-agenda'),
                                  child: _phoneDayPanels(),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  if (widget.loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: EventCalendarSkeleton(
                        view: _view,
                        dayCount: _days.duration.inDays,
                        month: EventMonthMetrics(
                          layout: compact
                              ? EventMonthLayout.compact
                              : EventMonthLayout.grid,
                          dayHeaderHeight: _dayHeaderHeight,
                          laneHeight: _monthTileHeight,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );
    },
  );

  Widget _buildCalendar({
    required bool compact,
    required bool phoneMonth,
    required bool weekFocused,
  }) {
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
    final monthTiles = kalender.TileComponents(tileBuilder: _monthTile);
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
      tileComponents: monthTiles,
      configuration: kalender.MonthBodyConfiguration(
        tileHeight: monthTileHeight,
        multiDayLayoutStrategy: EventCalendarLayout(month: widget.page.date),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DCalendarScheduleDay(
                            label: DateFormat('EEE d', _locale).format(day),
                            today: true,
                          ),
                          const EventAgendaEmpty(),
                        ],
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
                  DCalendarWeekdayHeader(date: date, start: true),
            ),
            bodyComponents: kalender.MonthBodyComponents(
              monthGridBuilder: (_, _) => const SizedBox.shrink(),
              monthDayHeaderBuilder: _dayHeader,
              monthDayCellBuilder: (context, details) =>
                  details.isToday && details.isInFocusedMonth
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.primary.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    )
                  : const SizedBox.shrink(),
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
            body: compact
                ? DKalenderCompactMonthBody(
                    phone: phoneMonth,
                    selectedDate: phoneMonth && _phoneDayVisible
                        ? _selectedDay
                        : null,
                    visibleWeek: weekFocused ? _selectedDay : null,
                    onVerticalPage: phoneMonth ? _movePhoneCalendar : null,
                    onDayPressed: phoneMonth ? _showPhoneDay : _openDay,
                    eventColor: (event) => (event as EventCalendarEntry).color,
                    layoutStrategy: const EventCalendarLayout(),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Leave three equal event lanes and an overflow count
                      // in every week, including when a week is empty.
                      final weeks = _days.duration.inDays ~/ 7;
                      final height =
                          weeks * (_dayHeaderHeight + 4 * monthTileHeight);
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
          if (day == today || _shownEvents.any((event) => event.includes(day)))
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
                if (!_shownEvents.any((event) => event.includes(day))) 'empty',
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
    return DCalendarScheduleRow(
      date: day,
      rowId: event.id,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (dayEvents.firstOrNull?.id == event.id)
            DCalendarScheduleDay(
              label: DateFormat('EEE d', _locale).format(day),
              today: day == _todayDate,
            ),
          EventAgendaRow(
            event: event,
            day: day,
            creatorAvatar: widget.creatorAvatar,
            time: _scheduleTime(event),
            gapAbove: eventAgendaGaps(
              dayEvents.cast<EventCalendarEntry>(),
              day,
            ).contains(event.id),
            onOpen: () => widget.onOpen(event),
          ),
        ],
      ),
    );
  }

  double get _dayHeaderHeight => _touch ? 36 : 28;

  double get _monthTileHeight => math.max(
    _touch ? kMinInteractiveDimension : 23.0,
    MediaQuery.textScalerOf(context).scale(DiscourseTypography.xs) * 1.3 + 7,
  );

  Widget _dayHeader(BuildContext context, DateTime date) {
    final tokens = DTokens.of(context);
    final day = DateTime.utc(date.year, date.month, date.day);
    final today = day == _todayDate;
    if (!_inPageMonth(day)) {
      return SizedBox(width: double.infinity, height: _dayHeaderHeight);
    }
    return SizedBox(
      height: _dayHeaderHeight,
      child: Builder(
        builder: (context) => DCalendarDayButton(
          details: DCalendarDayDetails(
            date: DCalendarDate.fromDateTime(date),
            outside: false,
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
              padding: const EdgeInsetsDirectional.only(start: 9),
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: DiscourseTypography.control,
                  fontWeight: today ? FontWeight.w700 : FontWeight.w500,
                  color: today ? tokens.primary : tokens.mutedForeground,
                ),
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

  void _showPhoneDay(DateTime day) => setState(() {
    _pickedDay = day;
    _phonePanelAnchor = day;
    _phoneDayVisible = true;
    _phonePanelRevision++;
  });

  void _dismissPhoneDay() => setState(() {
    _phoneDayVisible = false;
    _phoneDayExpanded = false;
  });

  void _movePhoneCalendar(int direction) {
    if (_turningPhoneMonth) return;
    if (!_phoneDayExpanded) {
      unawaited(_turnPhoneMonth(widget.page.move(direction)));
      return;
    }
    final selected = _selectedDay;
    final startOfMonth = DateTime.utc(selected.year, selected.month);
    final endOfMonth = DateTime.utc(selected.year, selected.month + 1);
    final startOfWeek = selected.subtract(
      Duration(days: (selected.weekday % 7 - widget.firstDay + 7) % 7),
    );
    final targetWeek = startOfWeek.add(Duration(days: direction * 7));
    final targetEnd = targetWeek.add(const Duration(days: 7));
    final next = !targetWeek.isBefore(endOfMonth)
        ? endOfMonth
        : !targetEnd.isAfter(startOfMonth)
        ? startOfMonth.subtract(const Duration(days: 1))
        : _firstAgendaDay(
            targetWeek.isBefore(startOfMonth) ? startOfMonth : targetWeek,
            targetEnd.isAfter(endOfMonth) ? endOfMonth : targetEnd,
          );
    if (next.year < 1900 || next.year >= 2200) return;
    _showPhoneDay(next);
    if (!_inPageMonth(next)) {
      unawaited(
        _turnPhoneMonth(EventCalendarPage(EventCalendarView.month, next)),
      );
    }
  }

  Future<void> _turnPhoneMonth(EventCalendarPage next) async {
    if (next.date.year < 1900 || next.date.year >= 2200) return;
    final previous = widget.page;
    final motion = DMotion.duration(context, DMotion.change);
    _turningPhoneMonth = true;
    try {
      if (motion > Duration.zero) {
        await _calendar.animateToDate(
          _inCalendar(next.date),
          duration: motion,
          curve: Curves.easeOutCubic,
        );
      }
      if (mounted && widget.page == previous) widget.onPageChanged(next);
    } finally {
      _turningPhoneMonth = false;
    }
  }

  Widget _phoneDayPanels() {
    final active = _selectedDay;
    final start = DateTime.utc(active.year, active.month);
    final end = DateTime.utc(active.year, active.month + 1);
    final dates = [
      for (
        var day = start;
        day.isBefore(end);
        day = day.add(const Duration(days: 1))
      )
        if (day == active ||
            day == _phonePanelAnchor ||
            day == _todayDate ||
            _shownEvents.any((event) => event.includes(day)))
          day,
    ];
    final selected = dates.indexOf(active);
    return DCalendarDayPanels(
      key: ValueKey((_phonePanelRevision, Object.hashAll(dates))),
      initialIndex: selected,
      selectedIndex: selected,
      expanded: _phoneDayExpanded,
      onSelected: (index) {
        final day = dates[index];
        if (day != _pickedDay) setState(() => _pickedDay = day);
      },
      onExpand: () => setState(() => _phoneDayExpanded = true),
      onCollapse: () => setState(() => _phoneDayExpanded = false),
      onDismiss: _dismissPhoneDay,
      days: [
        for (final day in dates)
          (
            label: DateFormat.yMMMMEEEEd(_locale).format(day),
            child: Builder(
              builder: (context) => EventDayAgenda(
                day: day,
                creatorAvatar: widget.creatorAvatar,
                events: _eventsOn(day),
                formatTime: _scheduleTime,
                onOpen: (event) {
                  _dismissPhoneDay();
                  widget.onOpen(event);
                },
              ),
            ),
          ),
      ],
    );
  }

  List<EventCalendarEntry> _eventsOn(DateTime day) =>
      _shownEvents.where((event) => event.includes(day)).toList()..sort((a, b) {
        if (a.isAllDay != b.isAllDay) return a.isAllDay ? -1 : 1;
        final time = (a.localStart.hour * 60 + a.localStart.minute).compareTo(
          b.localStart.hour * 60 + b.localStart.minute,
        );
        return time != 0 ? time : a.id.compareTo(b.id);
      });

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

  Widget _monthTile(
    BuildContext context,
    kalender.KalenderEvent raw,
    kalender.KalenderDateTimeRange range,
  ) {
    final event = raw as EventCalendarEntry;
    final tokens = DTokens.of(context);
    final color = event.color ?? tokens.primary;
    final month = widget.page.date;
    final clippedStart =
        event.start.isBefore(range.start) ||
        event.localStart.isBefore(
          tz.TZDateTime(widget.location, month.year, month.month),
        );
    final clippedEnd =
        event.end.isAfter(range.end) ||
        event.localEnd.isAfter(
          tz.TZDateTime(widget.location, month.year, month.month + 1),
        );
    final label =
        '${event.title}, ${DateFormat.yMMMd(_locale).format(event.localStart)}, ${_timeLabel(event)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 3),
      child: Opacity(
        opacity: event.lastDay.isBefore(_todayDate) ? .4 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: [
                color.withValues(alpha: .16),
                color.withValues(alpha: .72),
              ],
            ),
            borderRadius: BorderRadiusDirectional.horizontal(
              start: Radius.circular(clippedStart ? 0 : 6),
              end: Radius.circular(clippedEnd ? 0 : 6),
            ),
          ),
          child: DTooltip(
            message: label,
            child: DCalendarEventAction(
              semanticLabel: label,
              onPressed: () => widget.onOpen(event),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  clippedStart ? '…${event.title}' : event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: event.event.watching?.status == 'going'
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: tokens.foreground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

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
