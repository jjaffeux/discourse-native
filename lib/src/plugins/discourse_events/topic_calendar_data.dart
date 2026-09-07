import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:timezone/timezone.dart' as tz;

import '../../plugin_api/preserved_json.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../plugin_api/timezone_host.dart';
import 'event_data.dart';
import 'event_time.dart';

const topicCalendarKey = PluginDataKey<TopicCalendarData>(
  owner: 'discourse-events',
  name: 'topic-calendar',
);
const topicCalendarSettingsKey = PluginDataKey<TopicCalendarSettings>(
  owner: 'discourse-events',
  name: 'topic-calendar-settings',
);

/// The first post carries the complete calendar, including unloaded replies.
@immutable
final class TopicCalendarData {
  const TopicCalendarData._(this.topicId, this.details);

  static TopicCalendarData? decode(Map<String, dynamic> json) {
    final topicId = eventInt(json['topic_id']);
    final details = json['calendar_details'];
    if (json['post_number'] != 1 ||
        topicId == null ||
        topicId <= 0 ||
        details is! List) {
      return null;
    }
    return TopicCalendarData._(
      topicId,
      List.unmodifiable([for (final detail in details) ?eventObject(detail)]),
    );
  }

  final int topicId;
  final List<Map<String, Object?>> details;

  @override
  bool operator ==(Object other) =>
      other is TopicCalendarData &&
      topicId == other.topicId &&
      deepJsonEquals(details, other.details);
  @override
  int get hashCode => Object.hash(topicId, deepJsonHash(details));
}

@immutable
final class TopicCalendarSettings {
  const TopicCalendarSettings({this.firstDay = 1, this.holidayTopicId});

  factory TopicCalendarSettings.decode(Map<String, Object?> json) {
    final day = switch (json['calendar_first_day_of_week']) {
      'sunday' => 0,
      'monday' => 1,
      'saturday' => 6,
      final value => int.tryParse('$value'),
    };
    return TopicCalendarSettings(
      firstDay: day != null && day >= 0 && day <= 6 ? day : 1,
      holidayTopicId: int.tryParse('${json['holiday_calendar_topic_id']}'),
    );
  }

  /// Sunday is 0, matching Discourse and MaterialLocalizations.
  final int firstDay;
  final int? holidayTopicId;

  @override
  bool operator ==(Object other) =>
      other is TopicCalendarSettings &&
      firstDay == other.firstDay &&
      holidayTopicId == other.holidayTopicId;
  @override
  int get hashCode => Object.hash(firstDay, holidayTopicId);
}

final class TopicCalendarSettingsCodec
    extends PluginDataPersistenceCodec<TopicCalendarSettings> {
  const TopicCalendarSettingsCodec();
  @override
  PluginDataKey<TopicCalendarSettings> get key => topicCalendarSettingsKey;
  @override
  TopicCalendarSettings? decode(Object? value) => switch (eventObject(value)) {
    final fields? => TopicCalendarSettings.decode(fields),
    _ => null,
  };
  @override
  Object encode(TopicCalendarSettings value) => {
    'calendar_first_day_of_week': value.firstDay,
    'holiday_calendar_topic_id': value.holidayTopicId,
  };
}

final class TopicCalendarOptions {
  TopicCalendarOptions.fromElement(dom.Element element)
    : type = element.attributes['data-calendar-type'] ?? 'dynamic',
      fullDay = element.attributes['data-calendar-full-day'] == 'true',
      timezone = eventText(
        element.attributes['data-calendar-default-timezone'],
      ),
      hiddenDays = Set.unmodifiable({
        if (element.attributes['data-weekends'] == 'false') ...[0, 6],
        for (final token
            in (element.attributes['data-hidden-days'] ?? '').split(','))
          if (int.tryParse(token.trim()) case final day?
              when day >= 0 && day <= 6)
            day,
      });

  final String type;
  final bool fullDay;
  final String? timezone;
  final Set<int> hiddenDays;
}

/// Dates used for grid geometry are UTC carriers, never elapsed local days.
DateTime topicCalendarDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

final class CalendarOccurrence {
  const CalendarOccurrence({
    required this.title,
    required this.description,
    required this.username,
    required this.start,
    required this.end,
    required this.allDay,
    this.postNumber,
  });

  final String title;
  final String description;
  final String username;
  final DateTime start;

  /// Exclusive, including for inclusive date ranges serialized by Discourse.
  final DateTime end;
  final bool allDay;
  final int? postNumber;

  DateTime get firstDay => topicCalendarDay(start);
  DateTime get lastDay => topicCalendarDay(
    end.isAfter(start) ? end.subtract(const Duration(microseconds: 1)) : start,
  );
  bool includes(DateTime day) =>
      !day.isBefore(firstDay) && !day.isAfter(lastDay);
}

String _plainText(Object? value) =>
    html.parseFragment(eventText(value) ?? '').text?.trim() ?? '';

/// Expand only the visible window. Weekly dates are advanced in the author's
/// zone so a recurrence across DST retains its wall time.
List<CalendarOccurrence> calendarOccurrences(
  TopicCalendarData data,
  TopicCalendarOptions options, {
  required PluginTimezoneHost zones,
  required String timezone,
  required DateTime from,
  required DateTime until,
  bool holidayCalendar = false,
}) {
  final displayZone = zones.location(timezone);
  if (displayZone == null) return const [];
  final result = <CalendarOccurrence>[];
  for (final detail in data.details) {
    final grouped = detail['type'] == 'grouped';
    if (!grouped && detail['type'] != 'standalone') continue;
    final postNumber = eventInt(detail['post_number']);
    if (!grouped && (postNumber == null || postNumber <= 0)) continue;
    final sourceZone = eventText(detail['timezone']) ?? 'Etc/UTC';
    DateTime? date(Object? raw) {
      final value = eventText(raw);
      if (value == null) return null;
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
        return eventCalendarDay(value);
      }
      return eventDate(
        value,
        zones: zones,
        timezone: sourceZone,
        showLocalTime: true,
      );
    }

    final start = date(detail['from']);
    final end = date(detail['to']);
    if (start == null ||
        (detail['to'] != null && end == null) ||
        (end != null && end.isBefore(start))) {
      continue;
    }
    bool midnight(DateTime value) =>
        value.hour == 0 && value.minute == 0 && value.second == 0;
    final allDay =
        options.fullDay ||
        grouped ||
        end == null ||
        (midnight(start) && midnight(end));
    // Long-lived calendar topics include years of replies. Only parse labels
    // and descriptions for entries that actually intersect the visible month.
    late final message = _plainText(detail['message']);
    final username = eventText(detail['username']) ?? '';
    final users = detail['users'];
    late final names = <String>{
      if (users is List)
        for (final user in users) ?eventText(eventObject(user)?['username']),
    }.toList()..sort();
    late final holidayName = _plainText(detail['name']);
    late final title = grouped
        ? names.length == 1
              ? names.single
              : '(${names.length}) $holidayName'
        : !holidayCalendar && message.isNotEmpty
        ? message.split('\n').first
        : username;
    late final description = grouped
        ? '$holidayName${names.isEmpty ? '' : '\n${names.join(', ')}'}'
        : message;

    void add(DateTime occurrenceStart, DateTime? occurrenceEnd) {
      final first = allDay
          ? topicCalendarDay(occurrenceStart)
          : tz.TZDateTime.from(occurrenceStart, displayZone);
      final last = allDay
          ? topicCalendarDay(
              occurrenceEnd ?? occurrenceStart,
            ).add(const Duration(days: 1))
          : tz.TZDateTime.from(occurrenceEnd!, displayZone);
      final lastDay = topicCalendarDay(
        last.isAfter(first)
            ? last.subtract(const Duration(microseconds: 1))
            : first,
      );
      if (!topicCalendarDay(first).isBefore(until) || lastDay.isBefore(from)) {
        return;
      }
      final occurrence = CalendarOccurrence(
        title: title.isEmpty ? 'Calendar entry' : title,
        description: description,
        username: username,
        start: first,
        end: last,
        allDay: allDay,
        postNumber: grouped ? null : postNumber,
      );
      result.add(occurrence);
    }

    if (detail['recurring'] != '1.weeks') {
      add(start, end);
      continue;
    }
    DateTime shift(DateTime value, int days) => value is tz.TZDateTime
        ? tz.TZDateTime(
            value.location,
            value.year,
            value.month,
            value.day + days,
            value.hour,
            value.minute,
            value.second,
          )
        : DateTime.utc(
            value.year,
            value.month,
            value.day + days,
            value.hour,
            value.minute,
            value.second,
          );
    final duration = topicCalendarDay(
      end ?? start,
    ).difference(topicCalendarDay(start)).inDays;
    final firstWeek =
        (from.difference(topicCalendarDay(start)).inDays - duration - 1) ~/ 7;
    final lastWeek =
        (until.difference(topicCalendarDay(start)).inDays + 7) ~/ 7;
    // A malformed multi-year repeating range must not expand without a bound.
    for (
      var week = firstWeek;
      week <= lastWeek && week < firstWeek + 64;
      week++
    ) {
      add(shift(start, week * 7), end == null ? null : shift(end, week * 7));
    }
  }
  result.sort((a, b) {
    final start = a.firstDay.compareTo(b.firstDay);
    if (start != 0) return start;
    final length = b.lastDay.compareTo(a.lastDay);
    return length != 0 ? length : a.title.compareTo(b.title);
  });
  return List.unmodifiable(result);
}
