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

  test(
    'midnight range displays the next day and series without dates is safe',
    () {
      expect(
        eventDateLabel(
          PostEvent.decode(eventJson())!,
          ports.zones,
          accountTimezone: 'Europe/Paris',
        ),
        contains('Sep 9, 2026, 00:00'),
      );
      expect(
        eventDateLabel(
          PostEvent.decode(
            eventJson(overrides: {'starts_at': null, 'is_expired': true}),
          )!,
          ports.zones,
        ),
        'This event has ended',
      );
    },
  );

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
