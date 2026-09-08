import 'package:flutter/material.dart';
import 'package:kalender/kalender.dart' as kalender;
import 'package:timezone/timezone.dart' as tz;

import '../../plugin_api/timezone_host.dart';
import 'event_data.dart';
import 'event_time.dart';

/// A date is a calendar-day carrier; convert it to the reader's zone only at
/// the Kalender/API boundary, where a day can be 23 or 25 hours long.
@immutable
final class EventCalendarPage {
  const EventCalendarPage(this.view, this.date);
  final EventCalendarView view;
  final DateTime date;

  String routeId(bool mine) =>
      'events-${mine ? 'mine' : 'upcoming'}/${view.name}/${date.year}/${date.month}/${date.day}';
  String webPath(bool mine) =>
      'upcoming-events${mine ? '/mine' : ''}/${view.name}/${date.year}/${date.month}/${date.day}';

  static ({bool mine, EventCalendarPage? page})? readRoute(String id) {
    final parts = id.split('/');
    if (parts.first != 'events-upcoming' && parts.first != 'events-mine') {
      return null;
    }
    final mine = parts.first == 'events-mine';
    if (parts.length == 1) return (mine: mine, page: null);
    if (parts.length != 5) return null;
    final view = EventCalendarView.parse(parts[1]);
    final year = int.tryParse(parts[2]);
    final month = int.tryParse(parts[3]);
    final day = int.tryParse(parts[4]);
    if (view == null || year == null || month == null || day == null) {
      return null;
    }
    if (year < 1900 ||
        year >= 2200 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return null;
    }
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return (mine: mine, page: EventCalendarPage(view, date));
  }

  DateTimeRange days({required int firstDay}) {
    final start = switch (view) {
      EventCalendarView.day => date,
      EventCalendarView.week => date.subtract(
        Duration(days: (date.weekday % 7 - firstDay + 7) % 7),
      ),
      EventCalendarView.month => DateTime.utc(date.year, date.month),
      EventCalendarView.year => DateTime.utc(date.year),
    };
    final end = switch (view) {
      EventCalendarView.day => start.add(const Duration(days: 1)),
      EventCalendarView.week => start.add(const Duration(days: 7)),
      EventCalendarView.month => DateTime.utc(date.year, date.month + 1),
      EventCalendarView.year => DateTime.utc(date.year + 1),
    };
    if (view != EventCalendarView.month) {
      return DateTimeRange(start: start, end: end);
    }
    return DateTimeRange(
      start: start.subtract(
        Duration(days: (start.weekday % 7 - firstDay + 7) % 7),
      ),
      end: end.add(Duration(days: (firstDay - end.weekday % 7 + 7) % 7)),
    );
  }

  EventCalendarPage move(int direction) =>
      EventCalendarPage(view, switch (view) {
        EventCalendarView.day => date.add(Duration(days: direction)),
        EventCalendarView.week => date.add(Duration(days: 7 * direction)),
        EventCalendarView.month => DateTime.utc(
          date.year,
          date.month + direction,
        ),
        EventCalendarView.year => DateTime.utc(date.year + direction),
      });

  @override
  bool operator ==(Object other) =>
      other is EventCalendarPage && other.view == view && other.date == date;
  @override
  int get hashCode => Object.hash(view, date);
}

/// Server-expanded occurrences supply recurrence and exception dates. Kalender
/// owns clipping and overlap placement, never recurrence generation or writes.
final class EventCalendarEntry extends kalender.CalendarEvent {
  static EventCalendarEntry? decode(
    PostEvent event, {
    required PluginTimezoneHost zones,
    required String timezone,
    required EventSettings settings,
    Color? categoryColor,
  }) {
    final location = zones.location(timezone);
    if (location == null) return null;
    final allDay =
        event.allDay ||
        (_midnight(event.startsAt) &&
            (event.endsAt == null || _midnight(event.endsAt)));
    DateTime? parse(String? value) {
      if (allDay) {
        final day = eventCalendarDay(value);
        return day == null
            ? null
            : tz.TZDateTime(location, day.year, day.month, day.day);
      }
      // FullCalendar interprets show_local_time's offset-free timestamps in the
      // calendar zone: a 09:00 local event occupies 09:00 for every reader.
      return eventDate(
        value,
        zones: zones,
        timezone: event.showLocalTime ? timezone : event.timezone,
        accountTimezone: timezone,
      );
    }

    final start = parse(event.startsAt);
    if (start == null) return null;
    var end = parse(event.endsAt);
    if (allDay) {
      end ??= start;
      end = tz.TZDateTime(location, end.year, end.month, end.day + 1);
    } else {
      end ??= start.add(const Duration(hours: 1));
    }
    if (!end.isAfter(start)) return null;
    var title = event.title;
    final sourceZone = zones.location(event.timezone);
    if (event.showLocalTime &&
        sourceZone != null &&
        tz.TZDateTime.from(start, sourceZone).timeZoneOffset !=
            start.timeZoneOffset) {
      title += ' (local time)';
    }
    return EventCalendarEntry._(
      id: '${event.id}:${event.startsAt}',
      event: event,
      location: location,
      title: title,
      color: _color(event, settings) ?? categoryColor,
      dateTimeRange: DateTimeRange(start: start, end: end),
      isAllDay: allDay,
    );
  }

  EventCalendarEntry._({
    super.id,
    required this.event,
    required this.location,
    required this.title,
    required this.color,
    required super.dateTimeRange,
    required super.isAllDay,
  }) : super(interaction: kalender.EventInteraction.allowNone());

  final PostEvent event;
  final tz.Location location;
  final String title;
  final Color? color;
  late final localStart = tz.TZDateTime.from(start, location);
  late final localEnd = tz.TZDateTime.from(end, location);
  late final firstDay = DateTime.utc(
    localStart.year,
    localStart.month,
    localStart.day,
  );
  late final lastDay = (() {
    final last = localEnd.subtract(const Duration(microseconds: 1));
    return DateTime.utc(last.year, last.month, last.day);
  })();

  bool includes(DateTime day) {
    return !day.isBefore(firstDay) && !day.isAfter(lastDay);
  }

  bool get spansDays {
    return firstDay != lastDay;
  }

  @override
  EventCalendarEntry copyWithData({required DateTimeRange dateTimeRange}) =>
      EventCalendarEntry._(
        id: id,
        event: event,
        location: location,
        title: title,
        color: color,
        isAllDay: isAllDay,
        dateTimeRange: dateTimeRange,
      );
  @override
  bool spansMultipleDays({
    required tz.Location? location,
    required kalender.MultiDayRule defaultRule,
  }) => isAllDay;

  @override
  bool layoutEquals(kalender.CalendarEvent other) =>
      super.layoutEquals(other) &&
      other is EventCalendarEntry &&
      event == other.event &&
      title == other.title &&
      color == other.color &&
      location == other.location;
  @override
  bool operator ==(Object other) =>
      other is EventCalendarEntry && layoutEquals(other);
  @override
  int get hashCode =>
      Object.hash(super.hashCode, event, title, color, location);
}

bool _midnight(String? value) =>
    value != null &&
    RegExp(
      r'^\d{4}-\d{2}-\d{2}(?:$|T00:00(?::00(?:\.0+)?)?(?:Z|[+-]\d{2}:?\d{2})?$)',
    ).hasMatch(value);

Color? _color(PostEvent event, EventSettings settings) {
  final post = eventObject(event.fields['post']);
  final topic = eventObject(post?['topic']);
  final tags = topic?['tags'];
  if (tags is List) {
    for (final tag in tags) {
      final fields = eventObject(tag);
      for (final rule in settings.calendarColors) {
        if (rule['type'] == 'tag' &&
            eventText(rule['slug']) != null &&
            (rule['slug'] == (fields?['name'] ?? tag) ||
                rule['slug'] == fields?['slug'])) {
          if (_hexColor(rule['color']) case final color?) return color;
        }
      }
    }
  }
  for (final rule in settings.calendarColors) {
    if (rule['type'] == 'category' &&
        eventText(rule['slug']) != null &&
        rule['slug'] == post?['category_slug']) {
      if (_hexColor(rule['color']) case final color?) return color;
    }
  }
  return null;
}

Color? _hexColor(Object? value) {
  if (value is! String) return null;
  var hex = value.replaceFirst('#', '');
  if (hex.length == 3) hex = hex.split('').map((char) => '$char$char').join();
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(0xff000000 | int.parse(hex, radix: 16));
}

/// Core orders month entries by start, longest duration, all-day, then title.
/// Keep Kalender's lane packing and cache while supplying that ordering.
final class EventCalendarLayout extends kalender.MultiDayLayoutStrategy {
  const EventCalendarLayout();
  @override
  kalender.MultiDayLayoutFrame generateFrame({
    required kalender.InternalDateTimeRange visibleDateTimeRange,
    required List<kalender.CalendarEvent> events,
    required TextDirection textDirection,
    required tz.Location? location,
    required kalender.MultiDayLayoutFrameCache? cache,
  }) => kalender.defaultMultiDayFrameGenerator(
    visibleDateTimeRange: visibleDateTimeRange,
    events: events,
    textDirection: textDirection,
    location: location,
    cache: cache,
    eventComparator: (a, b) {
      final start = a.start.compareTo(b.start);
      if (start != 0) return start;
      final duration = b.duration.compareTo(a.duration);
      if (duration != 0) return duration;
      if (a.isAllDay != b.isAllDay) return a.isAllDay ? -1 : 1;
      return (a as EventCalendarEntry).title.compareTo(
        (b as EventCalendarEntry).title,
      );
    },
  );
}
