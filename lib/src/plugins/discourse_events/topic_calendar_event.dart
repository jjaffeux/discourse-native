import 'package:kalender/kalender.dart' as kalender;
import 'package:timezone/timezone.dart' as tz;

import 'topic_calendar_data.dart';

/// Keeps Discourse's reply metadata alongside Kalender's layout data.
final class TopicCalendarEvent extends kalender.KalenderEvent {
  factory TopicCalendarEvent({
    required String id,
    required CalendarOccurrence occurrence,
    required tz.Location location,
  }) {
    // All-day dates are calendar-day carriers, not UTC instants. Anchor both
    // midnights in the displayed zone before Kalender converts them to UTC.
    // Construct the end separately: a local day can be 23 or 25 hours long.
    DateTime inCalendar(DateTime date) => occurrence.allDay
        ? tz.TZDateTime(location, date.year, date.month, date.day)
        : date;
    return TopicCalendarEvent._(
      id: id,
      occurrence: occurrence,
      start: inCalendar(occurrence.start),
      end: inCalendar(occurrence.end),
    );
  }

  TopicCalendarEvent._({
    super.id,
    required this.occurrence,
    required super.start,
    required super.end,
  }) : super(
         isAllDay: occurrence.allDay,
         interaction: kalender.EventInteraction.allowNone(),
       );

  final CalendarOccurrence occurrence;

  @override
  TopicCalendarEvent copyWithData({
    required DateTime start,
    required DateTime end,
  }) => TopicCalendarEvent._(occurrence: occurrence, start: start, end: end);

  @override
  bool layoutEquals(kalender.KalenderEvent other) =>
      super.layoutEquals(other) &&
      other is TopicCalendarEvent &&
      other.occurrence == occurrence;

  @override
  bool operator ==(Object other) =>
      other is TopicCalendarEvent && layoutEquals(other);

  @override
  int get hashCode => Object.hash(super.hashCode, occurrence);
}
