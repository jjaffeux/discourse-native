import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_directory.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

void main() {
  late EventTestPorts ports;
  setUp(() => ports = EventTestPorts());
  tearDown(() => ports.close());

  test('malformed occurrences do not hide valid neighbors or duplicates', () {
    final series = PostEvent.decode(
      eventJson(
        overrides: {
          'occurrences': [
            null,
            'invalid',
            {'ends_at': '2026-09-08T22:00:00Z'},
            {'starts_at': 123},
            {'starts_at': ''},
            // Invalid rows must not consume the view limit or a dedup key.
            for (var index = 0; index < 201; index++)
              {'id': 'invalid', 'starts_at': '2026-09-08T21:00:00Z'},
            for (final id in [null, 0, -1])
              {'id': id, 'starts_at': '2026-09-08T21:00:00Z'},
            {'id': 43, 'starts_at': '2026-09-08T21:00:00Z'},
            {
              'post': {'id': 99},
              'starts_at': '2026-09-08T21:00:00Z',
            },
            {'starts_at': '2026-09-15T21:00:00Z', 'ends_at': null},
            {'starts_at': '2026-09-08T21:00:00Z', 'ends_at': null},
            {'starts_at': '2026-09-08T21:00:00Z', 'ends_at': null},
          ],
        },
      ),
    )!;
    final other = PostEvent.decode({
      'id': 43,
      'starts_at': '2026-09-08T22:00:00Z',
    })!;

    final rows = eventDirectoryOccurrences([series, other], ports.zones);

    expect(rows.map((row) => (row.id, row.startsAt)), [
      (42, '2026-09-08T21:00:00Z'),
      (43, '2026-09-08T22:00:00Z'),
      (42, '2026-09-15T21:00:00Z'),
    ]);
  });

  test(
    'deduplication keeps distinct event IDs and wire dates at one instant',
    () {
      final events = [
        PostEvent.decode({
          'id': 42,
          'occurrences': [
            {'starts_at': '2026-09-08T21:00:00Z', 'ends_at': null},
            {'starts_at': '2026-09-08T23:00:00+02:00', 'ends_at': null},
            {
              'starts_at': '2026-09-08T21:00:00Z',
              'ends_at': '2026-09-08T22:00:00Z',
            },
          ],
        })!,
        PostEvent.decode({'id': 43, 'starts_at': '2026-09-08T21:00:00Z'})!,
      ];

      final rows = eventDirectoryOccurrences(events, ports.zones);

      expect(rows.map((row) => (row.id, row.startsAt)), [
        (42, '2026-09-08T21:00:00Z'),
        (42, '2026-09-08T23:00:00+02:00'),
        (43, '2026-09-08T21:00:00Z'),
      ]);
      expect(rows.first.endsAt, isNull);
    },
  );

  test('projected snapshots omit recurrence arrays and current attendance', () {
    final series = PostEvent.decode(
      eventJson(
        overrides: {
          'watching_invitee': watching(),
          'custom_fields': {'room': 'Library'},
          'rrule': 'FREQ=WEEKLY',
          'occurrences': [
            {
              'starts_at': '2026-09-15T21:00:00Z',
              'ends_at': null,
              'should_display_invitees': true,
              'can_update_attendance': true,
              'watching_invitee': watching(),
              'occurrences': [
                {'starts_at': '2026-09-22T21:00:00Z'},
              ],
            },
          ],
        },
      ),
    )!;

    final rows = eventDirectoryOccurrences([series], ports.zones);
    final row = rows.single;

    expect(row.fields.containsKey('occurrences'), isFalse);
    expect(row.displayInvitees, isFalse);
    expect(row.sampleInvitees, isEmpty);
    expect(row.stats, isNull);
    expect(row.watching, isNull);
    expect(row.canRespond, isFalse);
    expect(row.endsAt, isNull);
    expect(row.id, series.id);
    expect(row.topicId, series.topicId);
    expect(row.topicPath, series.topicPath);
    expect(row.title, series.title);
    expect(row.timezone, series.timezone);
    expect(row.recurrence, series.recurrence);
    expect(row.fields['rrule'], 'FREQ=WEEKLY');
    expect(row.fields['custom_fields'], {'room': 'Library'});
    expect(row.private, isTrue);
    expect(series.fields['occurrences'], hasLength(1));
    expect(series.watching, isNotNull);
    expect(series.canRespond, isTrue);
    expect(() => rows.add(series), throwsUnsupportedError);
    expect(() => row.fields['name'] = 'Changed', throwsUnsupportedError);
  });

  test('timezone resolution work grows with inputs, not sort comparisons', () {
    var locationCalls = 0;
    final zones = PluginTimezoneHost(
      readerTimezone: ports.zones.readerTimezone,
      location: (name) {
        locationCalls++;
        return ports.zones.location(name);
      },
      timezoneNames: ports.zones.timezoneNames,
      changes: ports.zones.changes,
    );
    const count = 400;
    final start = DateTime.utc(2026, 9, 8);
    final events = [
      for (var series = 0; series < 2; series++)
        PostEvent.decode({
          'id': series + 1,
          'occurrences': [
            for (var index = count ~/ 2 - 1; index >= 0; index--)
              {
                'starts_at': start
                    .add(Duration(minutes: index * 2 + series))
                    .toIso8601String(),
                'ends_at': null,
              },
          ],
        })!,
    ];

    final rows = eventDirectoryOccurrences(events, zones);

    expect(rows, hasLength(200));
    expect(rows.first.startsAt, start.toIso8601String());
    expect(
      rows.last.startsAt,
      start.add(const Duration(minutes: 199)).toIso8601String(),
    );
    expect(locationCalls, lessThanOrEqualTo(count * 2));
  });

  test('200 series yield the globally earliest 200 distinct occurrences', () {
    const count = 200;
    final start = DateTime.utc(2026, 9, 8);
    final events = [
      for (var id = count; id > 0; id--)
        PostEvent.decode({
          'id': id,
          'name': 'Series $id',
          'occurrences': [
            // Reverse chronological input with duplicate (id, starts_at) rows.
            for (var index = count - 1; index >= 0; index--)
              {
                'starts_at': start
                    .add(Duration(minutes: (index ~/ 2) * count + id - 1))
                    .toIso8601String(),
                'ends_at': null,
              },
          ],
        })!,
    ];

    final rows = eventDirectoryOccurrences(events, ports.zones);

    expect(rows, hasLength(count));
    expect(rows.map((row) => row.id), [for (var id = 1; id <= count; id++) id]);
    expect(rows.map((row) => row.startsAt), [
      for (var minute = 0; minute < count; minute++)
        start.add(Duration(minutes: minute)).toIso8601String(),
    ]);
    expect(rows.every((row) => !row.fields.containsKey('occurrences')), isTrue);
    expect(rows.map((row) => row.title), [
      for (var id = 1; id <= count; id++) 'Series $id',
    ]);
  });

  test('sorting preserves all-day and DST wall times across reader zones', () {
    final events = [
      PostEvent.decode({
        'id': 1,
        'timezone': 'Europe/Paris',
        'show_local_time': true,
        'occurrences': [
          {'starts_at': '2026-03-29T03:30:00'},
          {'starts_at': '2026-03-22T03:30:00'},
        ],
      })!,
      PostEvent.decode({
        'id': 2,
        'occurrences': [
          {'starts_at': '2026-03-29T01:00:00Z'},
        ],
      })!,
      PostEvent.decode({
        'id': 3,
        'all_day': true,
        'occurrences': [
          {'starts_at': '2026-03-29T23:00:00-10:00'},
          {'starts_at': '2026-03-22'},
        ],
      })!,
      // Keep an unavailable date from disrupting the known chronological order.
      PostEvent.decode({'id': 4, 'starts_at': '2026-03-29T01:15:00'})!,
    ];

    for (final zone in ['Pacific/Honolulu', 'Pacific/Kiritimati']) {
      ports.environment.setDeviceTimezone(zone);
      final rows = eventDirectoryOccurrences(events, ports.zones);

      expect(rows.map((row) => (row.id, row.startsAt)), [
        (3, '2026-03-22'),
        (1, '2026-03-22T03:30:00'),
        (3, '2026-03-29T23:00:00-10:00'),
        (2, '2026-03-29T01:00:00Z'),
        (1, '2026-03-29T03:30:00'),
        (4, '2026-03-29T01:15:00'),
      ]);
      expect(rows.first.allDay, isTrue);
      expect(rows[1].showLocalTime, isTrue);
      expect(rows[1].timezone, 'Europe/Paris');
    }
  });

  test(
    'empty server occurrences are authoritative and standalone rows survive',
    () {
      final current = PostEvent.decode(eventJson())!;
      final exhausted = PostEvent.decode(
        eventJson(overrides: {'occurrences': []}),
      )!;
      final undated = PostEvent.decode(
        eventJson(overrides: {'starts_at': null}),
      )!;

      final rows = eventDirectoryOccurrences([
        exhausted,
        current,
        undated,
        current,
      ], ports.zones);

      expect(rows.single, same(current));
      expect(rows.single.canRespond, isTrue);
    },
  );
}
