import 'dart:math' as math;

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:kalender/kalender.dart' as kalender;
import 'package:timezone/timezone.dart' as tz;

import '../../foundation/calendar_day.dart';
import '../../foundation/icons/d_icons.dart';
import '../../theme/d_icon.dart';
import '../../theme/discourse_typography.dart';
import '../../theme/tokens.dart';
import 'd_badge.dart';
import 'd_button.dart';
import 'd_calendar.dart';
import 'd_item.dart';
import 'd_separator.dart';

part 'd_calendar_schedule.dart';

/// Event-lane activation with visible cell bounds and Native focus treatment.
class DCalendarEventAction extends StatelessWidget {
  const DCalendarEventAction({
    super.key,
    required this.onPressed,
    required this.child,
    this.backgroundColor = Colors.transparent,
    this.semanticLabel,
    this.focusNode,
  });

  final VoidCallback onPressed;
  final Widget child;
  final Color backgroundColor;
  final String? semanticLabel;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(3),
      color: backgroundColor,
    ),
    child: DItem(
      size: DItemSize.artwork,
      shape: DItemShape.calendarEvent,
      semanticLabel: semanticLabel,
      focusNode: focusNode,
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      children: [child],
    ),
  );
}

/// A localized event-calendar weekday label that fits narrow, scaled columns.
class DCalendarWeekdayHeader extends StatelessWidget {
  const DCalendarWeekdayHeader({
    super.key,
    required this.date,
    this.start = false,
  });

  final DateTime date;

  /// Aligns the label with day numbers drawn at the start of each cell.
  final bool start;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.localeOf(context).toString();
    final day = headerColumnDay(date);
    return SizedBox(
      height: math.max(32, scaler.scale(12) * 1.3 + 8),
      child: LayoutBuilder(
        builder: (context, constraints) => Container(
          alignment: start
              ? AlignmentDirectional.centerStart
              : AlignmentDirectional.center,
          padding: EdgeInsetsDirectional.only(start: start ? 9 : 0),
          child: Text(
            DateFormat(
              constraints.maxWidth < scaler.scale(28) + 8 ? 'EEEEE' : 'EEE',
              locale,
            ).format(day).toUpperCase(),
            semanticsLabel: DateFormat.EEEE(locale).format(day),
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: DTokens.of(context).mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact, read-only month body for [kalender.KalenderView].
///
/// Kalender owns paging, timezone conversion and event lane placement. Weeks
/// grow with their content, showing at most four lanes, and with [fillHeight]
/// share any remaining height. Each whole day is an accessible action; the
/// thin bars and overflow counts are passive summaries. [selectedDate] is
/// outlined for layouts that show the chosen day beside the month.
class DKalenderCompactMonthBody extends StatelessWidget {
  const DKalenderCompactMonthBody({
    super.key,
    required this.onDayPressed,
    required this.eventColor,
    this.eventTitle,
    this.layoutStrategy = const kalender.MultiDayLayoutStrategy.byDuration(),
    this.selectedDate,
    this.fillHeight = false,
    this.phone = false,
    this.visibleWeek,
    this.onVerticalPage,
  });

  final ValueChanged<DateTime> onDayPressed;
  final Color? Function(kalender.KalenderEvent) eventColor;
  final String Function(kalender.KalenderEvent)? eventTitle;
  final kalender.MultiDayLayoutStrategy layoutStrategy;
  final DateTime? selectedDate;
  final bool fillHeight;
  final bool phone;
  final DateTime? visibleWeek;
  final ValueChanged<int>? onVerticalPage;

  static double phoneWeekExtentOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return math.max(28.0, scaler.scale(13) + 12) + scaler.scale(12) + 46;
  }

  @override
  Widget build(BuildContext context) {
    final view =
        kalender.KalenderScope.viewControllerOf(context)
            as kalender.MonthViewController;
    final events = kalender.KalenderScope.eventsControllerOf(context);
    final location = kalender.KalenderScope.locationOf(context);
    final calculator = view.viewConfiguration.pageIndexCalculator;
    final pages = ListenableBuilder(
      listenable: events,
      builder: (context, _) => PageView.builder(
        controller: view.pageController,
        scrollDirection: phone ? Axis.vertical : Axis.horizontal,
        physics: phone ? const NeverScrollableScrollPhysics() : null,
        itemCount: calculator.numberOfPages(location),
        onPageChanged: (index) {
          final range = calculator.rangeFromIndex(index, location);
          view.floatingVisibleRange.value = range;
          kalender.KalenderScope.callbacksOf(
            context,
          )?.onPageChanged?.call(range.forLocation(location: location));
        },
        itemBuilder: (context, index) {
          final range = calculator.rangeFromIndex(index, location);
          final month = calculator.monthStartFromIndex(index, location);
          final now =
              view.viewConfiguration.nowCallback?.call() ??
              (location == null ? DateTime.now() : tz.TZDateTime.now(location));
          final weeks = range.dates().length ~/ 7;
          int? weekOf(DateTime? date) {
            if (date == null ||
                month.year != date.year ||
                month.month != date.month) {
              return null;
            }
            final first = DateTime.utc(
              range.start.year,
              range.start.month,
              range.start.day,
            );
            return date.difference(first).inDays ~/ 7;
          }

          final weekIndex = weekOf(visibleWeek);
          return LayoutBuilder(
            key: ValueKey(month),
            builder: (context, constraints) => _CompactMonthScroll(
              onPage: onVerticalPage,
              focusedWeek: phone ? weekOf(selectedDate) : null,
              weekExtent: phoneWeekExtentOf(context),
              viewportExtent: constraints.maxHeight,
              weekOnly: weekIndex != null,
              child: Column(
                children: [
                  for (var week = 0; week < weeks; week++)
                    if (weekIndex == null || weekIndex == week)
                      _CompactWeek(
                        phone: phone,
                        month: month,
                        today: DateTime.utc(now.year, now.month, now.day),
                        selected: selectedDate,
                        minHeight: fillHeight && constraints.hasBoundedHeight
                            ? constraints.maxHeight / weeks
                            : 0,
                        onDayPressed: onDayPressed,
                        eventColor: eventColor,
                        eventTitle: eventTitle,
                        frame: layoutStrategy.generateFrame(
                          visibleRange: kalender.FloatingDateTimeRange(
                            start: range.start.add(Duration(days: week * 7)),
                            end: range.start.add(
                              Duration(days: (week + 1) * 7),
                            ),
                          ),
                          events: events
                              .eventsInRange(
                                kalender.FloatingDateTimeRange(
                                  start: range.start.add(
                                    Duration(days: week * 7),
                                  ),
                                  end: range.start.add(
                                    Duration(days: (week + 1) * 7),
                                  ),
                                ),
                                multiDayRule:
                                    view.viewConfiguration.multiDayRule,
                                location: location,
                              )
                              .toList(),
                          textDirection: Directionality.of(context),
                          location: location,
                          cache: null,
                        ),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!phone) return pages;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.topCenter,
        // The pager spans 3,600 months. Whole logical pixels keep Flutter's
        // fixed-extent sliver within its precision tolerance as the panel moves.
        child: SizedBox(
          height: constraints.maxHeight.floorToDouble(),
          child: pages,
        ),
      ),
    );
  }
}

class _CompactMonthScroll extends StatefulWidget {
  const _CompactMonthScroll({
    required this.child,
    required this.onPage,
    required this.focusedWeek,
    required this.weekExtent,
    required this.viewportExtent,
    required this.weekOnly,
  });

  final Widget child;
  final int? focusedWeek;
  final double weekExtent;
  final double viewportExtent;
  final bool weekOnly;
  final ValueChanged<int>? onPage;

  @override
  State<_CompactMonthScroll> createState() => _CompactMonthScrollState();
}

class _CompactMonthScrollState extends State<_CompactMonthScroll> {
  double _travel = 0;
  double _monthOffset = 0;
  bool _startedAtTop = false;
  bool _startedAtBottom = false;
  late final _controller = ScrollController(
    initialScrollOffset: _focusedOffset(0),
  );

  double _focusedOffset(double offset) {
    final week = widget.focusedWeek;
    if (week == null) return _monthOffset;
    if (widget.weekOnly) return 0;
    final bottom = (week + 1) * widget.weekExtent;
    final min = math.max(0.0, bottom - widget.viewportExtent);
    return offset.clamp(min, math.max(min, bottom - widget.weekExtent));
  }

  @override
  void didUpdateWidget(_CompactMonthScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusedWeek == widget.focusedWeek &&
        oldWidget.weekOnly == widget.weekOnly &&
        (widget.focusedWeek == null ||
            oldWidget.viewportExtent == widget.viewportExtent) &&
        oldWidget.weekExtent == widget.weekExtent) {
      return;
    }
    if (oldWidget.focusedWeek == null &&
        widget.focusedWeek != null &&
        _controller.hasClients) {
      _monthOffset = _controller.offset;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      final offset = _focusedOffset(
        position.pixels,
      ).clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((position.pixels - offset).abs() > .5) _controller.jumpTo(offset);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _page() {
    if (_travel.abs() < 60) return;
    final direction = _travel.sign.toInt();
    _travel = 0;
    widget.onPage?.call(direction);
  }

  @override
  Widget build(BuildContext context) {
    final focus = widget.focusedWeek != null && widget.onPage != null;
    final scroll = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (focus || widget.onPage == null || notification.depth != 0) {
          return false;
        }
        switch (notification) {
          case ScrollStartNotification(:final metrics):
            _travel = 0;
            _startedAtTop = metrics.pixels <= metrics.minScrollExtent;
            _startedAtBottom = metrics.pixels >= metrics.maxScrollExtent;
          case OverscrollNotification(:final overscroll, :final dragDetails)
              when dragDetails != null &&
                  (overscroll < 0 ? _startedAtTop : _startedAtBottom):
            _travel += overscroll;
          case ScrollEndNotification():
            _page();
        }
        return false;
      },
      child: SingleChildScrollView(
        controller: _controller,
        physics: focus
            ? const NeverScrollableScrollPhysics()
            : widget.onPage == null
            ? null
            : const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
        child: widget.child,
      ),
    );
    if (!focus) return scroll;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onVerticalDragStart: (_) => _travel = 0,
      onVerticalDragUpdate: (details) => _travel -= details.delta.dy,
      onVerticalDragEnd: (_) => _page(),
      onVerticalDragCancel: () => _travel = 0,
      child: scroll,
    );
  }
}

class _CompactWeek extends StatelessWidget {
  const _CompactWeek({
    required this.month,
    required this.phone,
    required this.today,
    required this.frame,
    required this.onDayPressed,
    required this.eventColor,
    this.eventTitle,
    this.selected,
    this.minHeight = 0,
  });

  final kalender.FloatingDateTime month;
  final bool phone;
  final DateTime today;
  final DateTime? selected;
  final double minHeight;
  final kalender.MultiDayLayoutFrame frame;
  final ValueChanged<DateTime> onDayPressed;
  final Color? Function(kalender.KalenderEvent) eventColor;
  final String Function(kalender.KalenderEvent)? eventTitle;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final locale = kalender.KalenderScope.localeOf(context)?.toString();
    final location = kalender.KalenderScope.locationOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final headerHeight = math.max(28.0, scaler.scale(13) + 12);
    final countHeight = scaler.scale(12) + 4;
    final labelFor = eventTitle;
    final laneHeight = labelFor == null ? 9.0 : scaler.scale(12) + 8;

    final lanes = phone ? 4 : frame.totalNumberOfRows.clamp(1, 4);
    final overflow = frame.totalNumberOfRows > 4;
    final height = math.max(
      math.max(48.0, minHeight),
      headerHeight +
          lanes * laneHeight +
          (phone || overflow ? countHeight : 0) +
          6,
    );
    final visible = frame.visibleEvents(4);
    bool inMonth(int column) =>
        frame.dateFromColumn(column).month == month.month;
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columnWidth = constraints.maxWidth / 7;
          return Stack(
            children: [
              for (var column = 0; column < 7; column++)
                Positioned(
                  left: column * columnWidth,
                  width: columnWidth,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: phone
                          ? null
                          : Border(
                              top: BorderSide(color: tokens.border),
                              left: column == 0
                                  ? BorderSide.none
                                  : BorderSide(color: tokens.border),
                            ),
                    ),
                    child: !inMonth(column)
                        ? null
                        : Builder(
                            builder: (context) {
                              final floatingDate = frame.dateFromColumn(column);
                              final date = DateTime.utc(
                                floatingDate.year,
                                floatingDate.month,
                                floatingDate.day,
                              );
                              final count = frame
                                  .eventsForColumn(column)
                                  .length;
                              final hidden = frame.layoutInfo
                                  .where(
                                    (entry) =>
                                        entry.row >= 4 &&
                                        entry.columns.contains(column),
                                  )
                                  .length;
                              final isToday = date == today;
                              final isSelected = date == selected;
                              void open() => onDayPressed(date);
                              final button = DCalendarDayButton(
                                details: DCalendarDayDetails(
                                  date: DCalendarDate.fromDateTime(date),
                                  outside: false,
                                  today: isToday,
                                  disabled: false,
                                  hidden: false,
                                  booked: false,
                                  // The outline marks the pick; a selected
                                  // fill would hide the day's bars.
                                  selected: false,
                                  rangeStart: false,
                                  rangeMiddle: false,
                                  rangeEnd: false,
                                ),
                                semanticLabel: context.l10n
                                    .calendarDayEventCount(
                                      DateFormat.yMMMMEEEEd(
                                        locale,
                                      ).format(date),
                                      isToday.toString(),
                                      count,
                                    ),
                                onPressed: open,
                                onKeyEvent: (event) {
                                  if (event is KeyDownEvent &&
                                      (event.logicalKey ==
                                              LogicalKeyboardKey.enter ||
                                          event.logicalKey ==
                                              LogicalKeyboardKey.space)) {
                                    open();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    PositionedDirectional(
                                      start: 4,
                                      top: 6,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: isToday && !phone
                                              ? tokens.primary.withValues(
                                                  alpha: .2,
                                                )
                                              : null,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 2,
                                          ),
                                          child: Text(
                                            '${date.day}',
                                            style: TextStyle(
                                              color: isToday
                                                  ? tokens.primary
                                                  : isSelected
                                                  ? tokens.foreground
                                                  : tokens.mutedForeground,
                                              fontSize:
                                                  DiscourseTypography.control,
                                              fontWeight: isToday || isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (hidden > 0)
                                      PositionedDirectional(
                                        start: 4,
                                        top: headerHeight + lanes * laneHeight,
                                        child: Text(
                                          '+$hidden',
                                          style: TextStyle(
                                            fontSize: DiscourseTypography.xs,
                                            color: tokens.mutedForeground,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                              if (!isSelected && !(phone && isToday)) {
                                return button;
                              }
                              if (phone) {
                                return Semantics(
                                  selected: isSelected,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: isToday
                                          ? tokens.primary.withValues(
                                              alpha: .16,
                                            )
                                          : null,
                                      border: isSelected
                                          ? Border.all(
                                              color: tokens.foreground,
                                              width: 1.5,
                                            )
                                          : null,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: button,
                                  ),
                                );
                              }
                              return Semantics(
                                selected: true,
                                child: DecoratedBox(
                                  position: DecorationPosition.foreground,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: tokens.primary,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      tokens.radius * .8,
                                    ),
                                  ),
                                  child: button,
                                ),
                              );
                            },
                          ),
                  ),
                ),
              for (var i = 0; i < visible.$1.length; i++)
                if (visible.$2[i].columns.where(inMonth).toList()
                    case final columns when columns.isNotEmpty)
                  Positioned(
                    left: columns.first * columnWidth + 4,
                    width: columns.length * columnWidth - 8,
                    top: headerHeight + visible.$2[i].row * laneHeight,
                    height: labelFor == null ? 6 : laneHeight - 3,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Builder(
                          builder: (context) {
                            final event = visible.$1[i];
                            final eventRange = event.floatingRange(
                              location: location,
                            );
                            final rtl =
                                frame.textDirection == TextDirection.rtl;
                            final first = frame.dateFromColumn(
                              rtl ? columns.last : columns.first,
                            );
                            final last = frame.dateFromColumn(
                              rtl ? columns.first : columns.last,
                            );
                            final startsHere = !eventRange.start.isBefore(
                              first,
                            );
                            final endsHere = !eventRange.end.isAfter(
                              last.add(const Duration(days: 1)),
                            );
                            final color = eventColor(event) ?? tokens.primary;
                            final dayStart =
                                kalender.FloatingDateTime.fromDateTime(today);
                            final past = !eventRange.end.isAfter(dayStart);
                            return DecoratedBox(
                              key: ValueKey(
                                'calendar-bar-${event.id}-${frame.range.start}',
                              ),
                              decoration: BoxDecoration(
                                color: phone
                                    ? null
                                    : color.withValues(
                                        alpha: labelFor == null ? 1 : .24,
                                      ),
                                gradient: phone
                                    ? LinearGradient(
                                        begin: AlignmentDirectional.centerStart,
                                        end: AlignmentDirectional.centerEnd,
                                        colors: [
                                          color.withValues(
                                            alpha: past ? .064 : .16,
                                          ),
                                          color.withValues(
                                            alpha: past ? .288 : .72,
                                          ),
                                        ],
                                      )
                                    : null,
                                borderRadius:
                                    BorderRadiusDirectional.horizontal(
                                      start: Radius.circular(
                                        startsHere ? 6 : 0,
                                      ),
                                      end: Radius.circular(endsHere ? 6 : 0),
                                    ),
                              ),
                              child: labelFor == null
                                  ? null
                                  : Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: Text(
                                        labelFor(event),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                    ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// Removes Kalender's reserved date column and Material row spacing when
/// composing a schedule from [DCalendarScheduleEntry] tiles.
class DKalenderScheduleBody extends StatelessWidget {
  const DKalenderScheduleBody({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ListTileTheme(
    data: const ListTileThemeData(
      contentPadding: EdgeInsets.zero,
      horizontalTitleGap: 0,
      minLeadingWidth: 0,
      minVerticalPadding: 0,
      minTileHeight: 0,
      visualDensity: VisualDensity.standard,
    ),
    child: child,
  );
}

/// The shared date heading for a schedule row and its pinned viewport copy.
class DCalendarScheduleDay extends StatelessWidget {
  const DCalendarScheduleDay({
    super.key,
    required this.label,
    this.today = false,
    this.pinned = false,
  });

  final String label;
  final bool today;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final heading = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 30, 8),
      child: Semantics(
        header: true,
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontSize: DiscourseTypography.sm,
            height: DiscourseTypography.lineHeightSmall,
            color: tokens.foreground,
            fontWeight: FontWeight.w700,
          ),
          child: Row(
            spacing: DSpacing.sm,
            children: [
              Expanded(child: Text(label)),
              if (today)
                DBadge(
                  backgroundColor: tokens.primary,
                  foregroundColor: tokens.primaryForeground,
                  child: Text(context.l10n.todayDcalendarevents),
                ),
            ],
          ),
        ),
      ),
    );
    if (pinned) return heading;
    return _ScheduleSourceHeading(
      frame: _ScheduleScope.of(context),
      date: context
          .dependOnInheritedWidgetOfExactType<_ScheduleRowScope>()
          ?.date,
      child: heading,
    );
  }
}

/// A schedule row with an optional day heading and a continuous date rail.
/// Dates, times and metadata are already formatted by the calendar adapter.
class DCalendarScheduleEntry extends StatelessWidget {
  const DCalendarScheduleEntry({
    super.key,
    this.dayLabel,
    this.today = false,
    required this.time,
    required this.title,
    this.subtitle,
    this.color,
    required this.onPressed,
  }) : _empty = false;

  const DCalendarScheduleEntry.empty({
    super.key,
    required this.dayLabel,
    this.today = false,
    required this.title,
  }) : time = '',
       subtitle = null,
       color = null,
       onPressed = null,
       _empty = true;

  final String? dayLabel;
  final bool today;
  final String time;
  final String title;
  final String? subtitle;
  final Color? color;
  final VoidCallback? onPressed;
  final bool _empty;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontSize: DiscourseTypography.sm,
        height: DiscourseTypography.lineHeightSmall,
        color: tokens.foreground,
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            start: 3.5,
            top: 0,
            bottom: 0,
            child: DSeparator(orientation: Axis.vertical, color: tokens.border),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (dayLabel != null)
                DCalendarScheduleDay(label: dayLabel!, today: today),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 20),
                child: DItem(
                  onPressed: onPressed,
                  size: DItemSize.xs,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  children: [
                    DItemContent(
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final timeWidth = math.min(
                              70.0,
                              constraints.maxWidth * .3,
                            );
                            final details = Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DSeparator(
                                  orientation: Axis.vertical,
                                  thickness: 3,
                                  length:
                                      scaler.scale(20) *
                                      (subtitle == null ? 1 : 2),
                                  color: _empty
                                      ? tokens.mutedForeground
                                      : color ?? tokens.primary,
                                  radius: BorderRadius.circular(2),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: TextStyle(
                                          fontWeight: _empty
                                              ? FontWeight.w400
                                              : FontWeight.w600,
                                          color: _empty
                                              ? tokens.mutedForeground
                                              : null,
                                        ),
                                      ),
                                      if (subtitle != null)
                                        Text(
                                          subtitle!,
                                          style: TextStyle(
                                            color: tokens.mutedForeground,
                                            fontSize:
                                                DiscourseTypography.preview,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                            final timeLabel = Text(
                              time,
                              style: TextStyle(
                                color: tokens.mutedForeground,
                                fontSize: DiscourseTypography.preview,
                              ),
                            );
                            if (scaler.scale(14) > 21 ||
                                constraints.maxWidth < 220) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!_empty) ...[
                                    timeLabel,
                                    const SizedBox(height: 4),
                                  ],
                                  details,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: timeWidth, child: timeLabel),
                                Expanded(child: details),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
