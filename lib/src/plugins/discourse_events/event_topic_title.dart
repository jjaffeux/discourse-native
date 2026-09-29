import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'event_controller.dart';
import 'event_data.dart';
import 'event_date_stamp.dart';
import 'event_notifications.dart';
import 'event_time.dart';

/// Event dates sit below narrow titles and beside wide titles.
class EventTopicTitle extends StatelessWidget {
  const EventTopicTitle({
    super.key,
    required this.site,
    required this.event,
    required this.controller,
    required this.child,
  });

  final String site;
  final EventTopicData event;
  final EventController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _buildTitle(context, mobile: constraints.maxWidth < 600),
  );

  // Not the controller: every event's load and write notifies it, and a topic
  // list holds a title per event topic, possibly beside a stream of cards.
  Widget _buildTitle(
    BuildContext context, {
    required bool mobile,
  }) => ListenableBuilder(
    listenable: controller.readerChanges,
    builder: (context, _) {
      final schedule = _schedule(context);
      if (!controller.settings(site).displayTopicDate || schedule == null) {
        return child;
      }
      return Flex(
        direction: mobile ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DSpacing.sm,
        children: [
          if (!mobile)
            ExcludeSemantics(
              child: EventDateStamp(
                key: const ValueKey('event-calendar-stamp'),
                date: schedule.start,
                locale: schedule.locale,
                compact: true,
              ),
            ),
          Flexible(
            flex: mobile ? 0 : 1,
            fit: mobile ? FlexFit.loose : FlexFit.tight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                child,
                DTooltip(
                  key: const ValueKey('event-schedule-summary'),
                  message: schedule.description,
                  excludeFromSemantics: true,
                  // Let the topic row own pointer interactions, like its title.
                  triggerMode: TooltipTriggerMode.manual,
                  child: DItemDescription(
                    maxLines: null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: DSpacing.sm,
                      children: [
                        if (mobile) const DIcon(EventIcons.calendar, size: 14),
                        Flexible(
                          child: Text(
                            schedule.summary(
                              controller.api.clock().year,
                              includeDate: mobile,
                            ),
                            semanticsLabel: schedule.description,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  _EventSchedule? _schedule(BuildContext context) {
    DateTime? date(String? source) => eventDate(
      source,
      zones: controller.zones,
      timezone: event.timezone,
      allDay: event.allDay,
      showLocalTime: event.showLocalTime,
      accountTimezone: controller.accountTimezone(site),
    );
    final start = date(event.startsAt);
    if (start == null) return null;
    final end = date(event.endsAt);
    return _EventSchedule(
      start: start,
      end: end != null && !end.isBefore(start) ? end : null,
      allDay: event.allDay,
      zone: event.showLocalTime
          ? event.timezone
          : controller.zones.readerTimezone(controller.accountTimezone(site)),
      locale: Localizations.localeOf(context).toString(),
      use24HourClock: use24HourClockOf(context),
    );
  }
}

class _EventSchedule {
  _EventSchedule({
    required this.start,
    required this.end,
    required this.allDay,
    required this.zone,
    required this.locale,
    required this.use24HourClock,
  });

  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final String? zone;
  final String locale;
  final bool use24HourClock;

  // A list row uses the same description for its tooltip and semantics, and
  // the same formatters for both endpoints. Resolve each once per schedule.
  late final _fullDateFormat = DateFormat.yMMMMEEEEd(locale);
  String _time(DateTime value) =>
      clockTime(value, use24HourClock: use24HourClock, locale: locale);

  bool get spansDays => end != null && _day(start) != _day(end!);
  DateTime _day(DateTime date) => DateTime.utc(date.year, date.month, date.day);

  String summary(int currentYear, {bool includeDate = false}) {
    final year =
        start.year != currentYear || (end?.year ?? start.year) != currentYear;
    if (spansDays) {
      final date = year ? DateFormat.yMMMd(locale) : DateFormat.MMMd(locale);
      final days = _day(end!).difference(_day(start)).inDays + 1;
      return appL10n.messageEventtopictitle(
        (allDay).toString(),
        (date.format(start)).toString(),
        (date.format(end!)).toString(),
        ((allDay) ? (appL10n.allDay) : '').toString(),
        ((!(allDay)) ? (days) : '').toString(),
      );
    }
    final date = year
        ? DateFormat.yMMMEd(locale)
        : includeDate
        ? DateFormat.MMMEd(locale)
        : DateFormat.E(locale);
    return appL10n.messageEventtopictitleValue(
      (allDay).toString(),
      (date.format(start)).toString(),
      ((allDay) ? (appL10n.allDay) : '').toString(),
      ((!(allDay)) ? (_time(start)) : '').toString(),
    );
  }

  String fullDate(DateTime date) =>
      '${_fullDateFormat.format(date)}'
      '${allDay ? appL10n.allDayEventtopictitle : ' · ${_time(date)}'}';

  late final String description =
      '${fullDate(start)}'
      '${end == null ? '' : ' → ${fullDate(end!)}'}'
      '${allDay || zone == null ? '' : ' · $zone'}';
}
