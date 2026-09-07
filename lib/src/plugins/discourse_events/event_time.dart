import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../plugin_api/timezone_host.dart';
import 'event_data.dart';

/// Calendar days stay calendar days. The UTC carrier is never converted to
/// a reader zone; midnight in an all-day event is not an instant.
DateTime? eventCalendarDay(String? source) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})(?:$|T| )',
  ).firstMatch(source ?? '');
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final result = DateTime.utc(year, month, day);
  return result.year == year && result.month == month && result.day == day
      ? result
      : null;
}

DateTime? eventDate(
  String? source, {
  required PluginTimezoneHost zones,
  String? timezone,
  String? accountTimezone,
  bool allDay = false,
  bool showLocalTime = false,
}) {
  if (allDay) return eventCalendarDay(source);
  if (source == null) return null;
  final hasOffset = RegExp(
    r'(Z|[+-]\d\d:?\d\d)$',
    caseSensitive: false,
  ).hasMatch(source);
  final day = eventCalendarDay(source);
  if (day == null) return null;
  final clock = RegExp(
    r'[T ](\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?$',
    caseSensitive: false,
  ).firstMatch(source);
  if (clock == null ||
      int.parse(clock[1]!) > 23 ||
      int.parse(clock[2]!) > 59 ||
      int.parse(clock[3] ?? '0') > 59) {
    return null;
  }
  final displayZone = zones.location(
    showLocalTime ? timezone : zones.readerTimezone(accountTimezone),
  );
  if (displayZone == null) return null;
  if (hasOffset) {
    final instant = DateTime.tryParse(source);
    return instant == null ? null : tz.TZDateTime.from(instant, displayZone);
  }
  // A wall time has meaning only in its declared event timezone.
  final eventZone = zones.location(timezone);
  final time = RegExp(
    r'[T ](\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?$',
  ).firstMatch(source);
  if (eventZone == null || time == null) return null;
  final hour = int.parse(time[1]!);
  final minute = int.parse(time[2]!);
  final second = int.parse(time[3] ?? '0');
  if (hour > 23 || minute > 59 || second > 59) return null;
  final wall = tz.TZDateTime(
    eventZone,
    day.year,
    day.month,
    day.day,
    hour,
    minute,
    second,
  );
  if (wall.hour != hour || wall.minute != minute || wall.day != day.day) {
    return null;
  }
  return tz.TZDateTime.from(wall, displayZone);
}

String eventDateLabel(
  PostEvent event,
  PluginTimezoneHost zones, {
  String? accountTimezone,
  String? locale,
}) {
  final start = eventDate(
    event.startsAt,
    zones: zones,
    timezone: event.timezone,
    accountTimezone: accountTimezone,
    allDay: event.allDay,
    showLocalTime: event.showLocalTime,
  );
  final end = eventDate(
    event.endsAt,
    zones: zones,
    timezone: event.timezone,
    accountTimezone: accountTimezone,
    allDay: event.allDay,
    showLocalTime: event.showLocalTime,
  );
  if (start == null) {
    return event.flag('is_expired')
        ? 'This event has ended'
        : 'Date unavailable';
  }
  final date = DateFormat.yMMMd(locale);
  final sameDay =
      end != null &&
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  if (event.allDay) {
    return end == null || sameDay
        ? '${date.format(start)} · All day'
        : '${date.format(start)} – ${date.format(end)} · All day';
  }
  final time = DateFormat.Hm(locale);
  final zone = event.showLocalTime
      ? event.timezone
      : zones.readerTimezone(accountTimezone);
  return '${date.format(start)}, ${time.format(start)}'
      '${end == null ? '' : ' → ${sameDay ? '' : '${date.format(end)}, '}${time.format(end)}'}'
      '${zone == null ? '' : ' ($zone)'}';
}

String? eventRecurrenceLabel(String? recurrence) => switch (recurrence) {
  null || '' || 'none' => null,
  'every_day' => 'Every day',
  'every_weekday' => 'Every weekday',
  'every_week' => 'Every week',
  'every_two_weeks' => 'Every two weeks',
  'every_four_weeks' => 'Every four weeks',
  'every_month' => 'Every month on the same weekday',
  _ => 'Repeating event',
};
