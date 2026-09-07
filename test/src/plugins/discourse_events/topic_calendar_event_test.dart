import 'package:discourse_native/src/plugins/discourse_events/topic_calendar_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/topic_calendar_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../support/event_fixtures.dart';

void main() {
  late EventTestPorts ports;
  setUp(() => ports = EventTestPorts());
  tearDown(() => ports.close());

  CalendarOccurrence occurrence({
    required DateTime start,
    required DateTime end,
    bool allDay = true,
    String title = 'Away',
  }) => CalendarOccurrence(
    title: title,
    description: title,
    username: 'sam',
    start: start,
    end: end,
    allDay: allDay,
    postNumber: 80,
  );

  test(
    'Kalender receives local midnight boundaries across 23/25-hour days',
    () {
      for (final (zone, day, hours) in [
        ('America/New_York', DateTime.utc(2026, 3, 8), 23),
        ('Europe/Paris', DateTime.utc(2026, 10, 25), 25),
        ('Asia/Tokyo', DateTime.utc(2026, 9, 7), 24),
      ]) {
        final location = ports.zones.location(zone)!;
        final nextDay = day.add(const Duration(days: 1));
        final event = TopicCalendarEvent(
          id: '80',
          occurrence: occurrence(start: day, end: nextDay),
          location: location,
        );
        final start = tz.TZDateTime.from(event.start, location);
        final end = tz.TZDateTime.from(event.end, location);
        expect(
          (start.year, start.month, start.day, start.hour),
          (day.year, day.month, day.day, 0),
        );
        expect(
          (end.year, end.month, end.day, end.hour),
          (nextDay.year, nextDay.month, nextDay.day, 0),
        );
        expect(event.duration.inHours, hours);
        expect(event.isAllDay, isTrue);
      }
    },
  );

  test('timed instants and reply metadata survive Kalender copies', () {
    final value = occurrence(
      start: DateTime.utc(2026, 9, 8, 1),
      end: DateTime.utc(2026, 9, 8, 2),
      allDay: false,
    );
    final event = TopicCalendarEvent(
      id: '80',
      occurrence: value,
      location: ports.zones.location('America/Los_Angeles')!,
    );
    expect(event.start, value.start);
    expect(event.end, value.end);
    expect(event.isAllDay, isFalse);
    final copy =
        event.withDateTimeRange(
              DateTimeRange(
                start: value.start.add(const Duration(days: 1)),
                end: value.end.add(const Duration(days: 1)),
              ),
            )
            as TopicCalendarEvent;
    expect(copy.occurrence, same(value));
    expect(copy.id, event.id);
    expect(copy.interaction.allowRescheduling, isFalse);
    expect(copy.interaction.allowStartResize, isFalse);
    expect(copy.interaction.allowEndResize, isFalse);
  });

  test('edited reply labels invalidate Kalender tile caches', () {
    TopicCalendarEvent event(String title) => TopicCalendarEvent(
      id: '80',
      occurrence: occurrence(
        start: DateTime.utc(2026, 9, 7),
        end: DateTime.utc(2026, 9, 8),
        title: title,
      ),
      location: ports.zones.location('Etc/UTC')!,
    );
    final before = event('Away');
    final after = event('Available');
    expect(before, isNot(after));
    expect(before.layoutEquals(after), isFalse);
  });
}
