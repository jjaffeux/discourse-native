import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:kalender/kalender.dart' as kalender;
import 'package:timezone/timezone.dart' as tz;

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_badge.dart';
import 'd_calendar.dart';
import 'd_item.dart';
import 'd_separator.dart';

/// A localized event-calendar weekday label that fits narrow, scaled columns.
class DCalendarWeekdayHeader extends StatelessWidget {
  const DCalendarWeekdayHeader({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.localeOf(context).toString();
    return SizedBox(
      height: math.max(32, scaler.scale(12) * 1.3 + 8),
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: Text(
            DateFormat(
              constraints.maxWidth < scaler.scale(28) + 8 ? 'EEEEE' : 'EEE',
              locale,
            ).format(date).toUpperCase(),
            semanticsLabel: DateFormat.EEEE(locale).format(date),
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
/// grow with their content, showing at most four lanes. Each whole day is an
/// accessible action; the thin bars and overflow counts are passive summaries.
class DKalenderCompactMonthBody extends StatelessWidget {
  const DKalenderCompactMonthBody({
    super.key,
    required this.onDayPressed,
    required this.eventColor,
    this.layoutStrategy = const kalender.MultiDayLayoutStrategy.byDuration(),
  });

  final ValueChanged<DateTime> onDayPressed;
  final Color? Function(kalender.KalenderEvent) eventColor;
  final kalender.MultiDayLayoutStrategy layoutStrategy;

  @override
  Widget build(BuildContext context) {
    final controller = kalender.KalenderScope.kalenderControllerOf(context);
    final view = controller.viewController! as kalender.MonthViewController;
    final events = kalender.KalenderScope.eventsControllerOf(context);
    final location = kalender.KalenderScope.locationOf(context);
    final calculator = view.viewConfiguration.pageIndexCalculator;
    return ListenableBuilder(
      listenable: events,
      builder: (context, _) => PageView.builder(
        controller: view.pageController,
        itemCount: calculator.numberOfPages(location),
        onPageChanged: (index) {
          final range = calculator.rangeFromIndex(index, location);
          controller.floatingVisibleRange.value = range;
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
          return SingleChildScrollView(
            key: ValueKey(month),
            child: Column(
              children: [
                for (var week = 0; week < range.dates().length ~/ 7; week++)
                  _CompactWeek(
                    month: month,
                    today: DateTime.utc(now.year, now.month, now.day),
                    onDayPressed: onDayPressed,
                    eventColor: eventColor,
                    frame: layoutStrategy.generateFrame(
                      visibleRange: kalender.FloatingDateTimeRange(
                        start: range.start.add(Duration(days: week * 7)),
                        end: range.start.add(Duration(days: (week + 1) * 7)),
                      ),
                      events: events
                          .eventsInRange(
                            kalender.FloatingDateTimeRange(
                              start: range.start.add(Duration(days: week * 7)),
                              end: range.start.add(
                                Duration(days: (week + 1) * 7),
                              ),
                            ),
                            multiDayRule: view.viewConfiguration.multiDayRule,
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
          );
        },
      ),
    );
  }
}

class _CompactWeek extends StatelessWidget {
  const _CompactWeek({
    required this.month,
    required this.today,
    required this.frame,
    required this.onDayPressed,
    required this.eventColor,
  });

  final kalender.FloatingDateTime month;
  final DateTime today;
  final kalender.MultiDayLayoutFrame frame;
  final ValueChanged<DateTime> onDayPressed;
  final Color? Function(kalender.KalenderEvent) eventColor;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final locale = kalender.KalenderScope.localeOf(context)?.toString();
    final location = kalender.KalenderScope.locationOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final headerHeight = math.max(28.0, scaler.scale(13) + 12);
    final countHeight = scaler.scale(12) + 4;
    const laneHeight = 9.0;
    final lanes = frame.totalNumberOfRows.clamp(1, 4);
    final overflow = frame.totalNumberOfRows > 4;
    final height = math.max(
      48.0,
      headerHeight + lanes * laneHeight + (overflow ? countHeight : 0) + 6,
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
                      border: Border(
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
                              void open() => onDayPressed(date);
                              return DCalendarDayButton(
                                details: DCalendarDayDetails(
                                  date: DCalendarDate.fromDateTime(date),
                                  outside: false,
                                  today: isToday,
                                  disabled: false,
                                  hidden: false,
                                  booked: false,
                                  selected: false,
                                  rangeStart: false,
                                  rangeMiddle: false,
                                  rangeEnd: false,
                                ),
                                semanticLabel:
                                    '${DateFormat.yMMMMEEEEd(locale).format(date)}'
                                    '${isToday ? ', Today' : ''}, $count ${count == 1 ? 'event' : 'events'}',
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
                                          color: isToday
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
                                                  : tokens.mutedForeground,
                                              fontSize:
                                                  DiscourseTypography.control,
                                              fontWeight: isToday
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
                    height: 5,
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
                            return DecoratedBox(
                              key: ValueKey(
                                'calendar-bar-${event.id}-${frame.range.start}',
                              ),
                              decoration: BoxDecoration(
                                color: eventColor(event) ?? tokens.primary,
                                borderRadius:
                                    BorderRadiusDirectional.horizontal(
                                      start: Radius.circular(
                                        startsHere ? 4 : 0,
                                      ),
                                      end: Radius.circular(endsHere ? 4 : 0),
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
  });

  final String? dayLabel;
  final bool today;
  final String time;
  final String title;
  final String? subtitle;
  final Color? color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final textStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: DiscourseTypography.sm,
      height: DiscourseTypography.lineHeightSmall,
      color: tokens.foreground,
    );
    return DefaultTextStyle(
      style: textStyle,
      child: Stack(
        children: [
          PositionedDirectional(
            start: 3.5,
            top: 0,
            bottom: 0,
            child: DSeparator(orientation: Axis.vertical, color: tokens.border),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (dayLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    child: Semantics(
                      header: true,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            dayLabel!,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (today)
                            DBadge(
                              backgroundColor: tokens.primary.withValues(
                                alpha: .2,
                              ),
                              foregroundColor: tokens.primary,
                              child: const Text('Today'),
                            ),
                        ],
                      ),
                    ),
                  ),
                DItem(
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
                                  color: color ?? tokens.primary,
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
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
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
                                  timeLabel,
                                  const SizedBox(height: 4),
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
              ],
            ),
          ),
          if (dayLabel != null)
            PositionedDirectional(
              start: 0,
              top:
                  16 +
                  scaler.scale(14) * DiscourseTypography.lineHeightSmall / 2 -
                  4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: today ? tokens.primary : tokens.mutedForeground,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: 8),
              ),
            ),
        ],
      ),
    );
  }
}
