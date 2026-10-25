import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_directory.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_time.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

void main() {
  late EventTestPorts ports;
  setUp(() => ports = EventTestPorts());
  tearDown(() => ports.close());

  test('offset instants use account timezone, then device, then UTC', () {
    final paris = eventDate(
      '2026-09-08T23:00:00+02:00',
      zones: ports.zones,
      accountTimezone: 'America/New_York',
    )!;
    expect(paris.hour, 17);
    expect(paris.toUtc(), DateTime.utc(2026, 9, 8, 21));
    ports.environment.setDeviceTimezone('Asia/Tokyo');
    final device = eventDate(
      '2026-09-08T23:00:00+02:00',
      zones: ports.zones,
      accountTimezone: 'invalid',
    )!;
    expect((device.day, device.hour), (9, 6));
    ports.environment.setDeviceTimezone(null);
    expect(
      eventDate('2026-09-08T23:00:00+02:00', zones: ports.zones)!.hour,
      21,
    );
  });

  test('offset-free wall time is interpreted in the event zone across DST', () {
    final before = eventDate(
      '2026-03-22T23:00:00',
      zones: ports.zones,
      timezone: 'Europe/Paris',
      showLocalTime: true,
    )!;
    final after = eventDate(
      '2026-03-29T23:00:00',
      zones: ports.zones,
      timezone: 'Europe/Paris',
      showLocalTime: true,
    )!;
    expect(before.timeZoneOffset.inHours, 1);
    expect(after.timeZoneOffset.inHours, 2);
    expect(before.hour, after.hour);
    expect(eventDate('2026-09-08T23:00:00', zones: ports.zones), isNull);
  });

  test('all-day dates never move when device or account zones change', () {
    for (final zone in ['Pacific/Honolulu', 'Pacific/Kiritimati']) {
      final day = eventDate(
        '2026-09-08',
        zones: ports.zones,
        allDay: true,
        accountTimezone: zone,
      )!;
      expect((day.year, day.month, day.day), (2026, 9, 8));
    }
    expect(eventCalendarDay('2026-02-30'), isNull);
    expect(
      eventDate(
        '2026-09-08T26:00:00',
        zones: ports.zones,
        timezone: 'Europe/Paris',
      ),
      isNull,
    );
  });

  test('offset instants with an impossible clock are rejected, not rolled', () {
    for (final source in [
      '2026-09-08T24:00:00Z',
      '2026-09-08T23:60:00+02:00',
    ]) {
      expect(eventDate(source, zones: ports.zones), isNull, reason: source);
    }
  });

  test('labels drop the end date only when both ends share a calendar day', () {
    String label(Map<String, Object?> overrides) => eventDateLabel(
      PostEvent.decode(eventJson(overrides: overrides))!,
      ports.zones,
      accountTimezone: 'Europe/Paris',
      locale: 'en_US',
      use24HourClock: true,
    );

    expect(
      label({
        'starts_at': '2026-09-08T10:00:00+02:00',
        'ends_at': '2026-09-08T11:00:00+02:00',
      }),
      'Sep 8, 2026, 10:00 → 11:00 (Europe/Paris)',
    );
    expect(
      label({
        'starts_at': '2026-09-08T10:00:00+02:00',
        'ends_at': '2026-10-08T11:00:00+02:00',
      }),
      'Sep 8, 2026, 10:00 → Oct 8, 2026, 11:00 (Europe/Paris)',
    );
    expect(
      label({
        'all_day': true,
        'starts_at': '2026-09-08',
        'ends_at': '2026-09-08',
      }),
      'Sep 8, 2026 · All day',
    );
    expect(
      label({
        'all_day': true,
        'starts_at': '2026-09-08',
        'ends_at': '2026-09-10',
      }),
      'Sep 8, 2026 – Sep 10, 2026 · All day',
    );
  });

  test('show_local_time labels name the event zone, not the reader zone', () {
    expect(
      eventDateLabel(
        PostEvent.decode(
          eventJson(
            overrides: {
              'show_local_time': true,
              'timezone': 'America/New_York',
              'starts_at': '2026-09-08T09:00:00',
              'ends_at': '2026-09-08T10:00:00',
            },
          ),
        )!,
        ports.zones,
        accountTimezone: 'Europe/Paris',
        locale: 'en_US',
        use24HourClock: true,
      ),
      'Sep 8, 2026, 09:00 → 10:00 (America/New_York)',
    );
  });

  test('a series that does not repeat has no recurrence label', () {
    for (final none in [null, '', 'none']) {
      expect(eventRecurrenceLabel(none), isNull, reason: none);
    }
    expect(eventRecurrenceLabel('every_week'), 'Every week');
    expect(eventRecurrenceLabel('every_quarter'), 'Repeating event');
  });

  test(
    'midnight range displays the next day and series without dates is safe',
    () {
      expect(
        eventDateLabel(
          PostEvent.decode(eventJson())!,
          ports.zones,
          accountTimezone: 'Europe/Paris',
          use24HourClock: true,
        ),
        contains('Sep 9, 2026, 00:00'),
      );
      expect(
        eventDateLabel(
          PostEvent.decode(
            eventJson(overrides: {'starts_at': null, 'is_expired': true}),
          )!,
          ports.zones,
          use24HourClock: true,
        ),
        'This event has ended',
      );
    },
  );

  test('times follow the reader clock rather than always reading 24-hour', () {
    String label({required bool use24HourClock}) => eventDateLabel(
      PostEvent.decode(eventJson())!,
      ports.zones,
      accountTimezone: 'Europe/Paris',
      locale: 'en_US',
      use24HourClock: use24HourClock,
    );

    expect(
      label(use24HourClock: false),
      'Sep 8, 2026, 11:00 PM → Sep 9, 2026, 12:00 AM (Europe/Paris)',
    );
    expect(
      label(use24HourClock: true),
      'Sep 8, 2026, 23:00 → Sep 9, 2026, 00:00 (Europe/Paris)',
    );
  });

  test(
    'directory uses server occurrences, orders instants and hides current RSVP data',
    () {
      final event = PostEvent.decode(
        eventJson(
          overrides: {
            'occurrences': [
              {'starts_at': '2026-09-08T23:00:00+02:00', 'ends_at': null},
              {'starts_at': '2026-09-15T23:00:00+02:00', 'ends_at': null},
            ],
          },
        ),
      )!;
      final other = PostEvent.decode({
        'id': 43,
        'starts_at': '2026-09-08T22:00:00Z',
      })!;
      final rows = eventDirectoryOccurrences([event, other], ports.zones);
      expect(rows.map((row) => row.id), [42, 43, 42]);
      expect(rows.last.stats, isNull);
      expect(rows.last.displayInvitees, isFalse);
      expect(rows.last.canRespond, isFalse);
      expect(
        eventDirectoryOccurrences([
          PostEvent.decode(eventJson(overrides: {'occurrences': []}))!,
        ], ports.zones),
        isEmpty,
      );
    },
  );
}
