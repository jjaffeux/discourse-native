import 'package:discourse_native/src/plugins/discourse_events/topic_calendar_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/topic_calendar_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/event_fixtures.dart';
import '../../../support/topic_calendar_fixtures.dart';

void main() {
  late EventTestPorts ports;
  setUp(() => ports = EventTestPorts());
  tearDown(() => ports.close());

  List<CalendarOccurrence> occurrences(
    List<Object?> details, {
    String options = 'data-calendar-full-day="true"',
    String timezone = 'America/Los_Angeles',
    DateTime? from,
    DateTime? until,
    bool holiday = false,
  }) => calendarOccurrences(
    TopicCalendarData.decode(calendarPostJson(details: details))!,
    calendarOptions(options),
    zones: ports.zones,
    timezone: timezone,
    from: from ?? DateTime.utc(2026, 9),
    until: until ?? DateTime.utc(2026, 10),
    holidayCalendar: holiday,
  );

  test(
    'absence, null, malformed payload and reply records stay unavailable',
    () {
      for (final fields in <Map<String, dynamic>>[
        <String, dynamic>{},
        {'calendar_details': null},
        {'calendar_details': <String, Object?>{}},
        {'calendar_details': <Object?>[], 'topic_id': 700, 'post_number': 2},
        {'calendar_details': <Object?>[], 'post_number': 1},
      ]) {
        expect(TopicCalendarData.decode(fields), isNull);
      }
      expect(
        TopicCalendarData.decode(calendarPostJson(details: []))!.details,
        isEmpty,
      );
    },
  );

  test(
    'snapshots are immutable and changed calendar details invalidate equality',
    () {
      final row = calendarDetail();
      final json = calendarPostJson(details: [row]);
      final held = TopicCalendarData.decode(json)!;
      expect(held, TopicCalendarData.decode(json));
      row['message'] = 'Changed';
      expect(held.details.single['message'], 'Team availability');
      expect(held, isNot(TopicCalendarData.decode(json)));
      expect(() => held.details.clear(), throwsUnsupportedError);
      expect(
        () => held.details.single['message'] = 'Edit',
        throwsUnsupportedError,
      );
    },
  );

  test(
    'fullDay retains the author dates and includes the end day in any reader zone',
    () {
      final details = [calendarDetail()];
      for (final zone in ['America/Los_Angeles', 'Asia/Tokyo']) {
        final event = occurrences(details, timezone: zone).single;
        expect(event.firstDay, DateTime.utc(2026, 9, 7));
        expect(event.lastDay, DateTime.utc(2026, 9, 10));
        expect(event.end, DateTime.utc(2026, 9, 11));
        expect(event.includes(DateTime.utc(2026, 9, 10)), isTrue);
        expect(event.includes(DateTime.utc(2026, 9, 11)), isFalse);
        expect(event.postNumber, 80);
      }
    },
  );

  test('a single date is one day and date-only ranges remain inclusive', () {
    final single = occurrences([
      calendarDetail(overrides: {'from': '2026-09-07', 'to': null}),
    ], options: '').single;
    expect(single.allDay, isTrue);
    expect(single.firstDay, single.lastDay);
    expect(
      occurrences([
        calendarDetail(overrides: {'from': '2026-09-07', 'to': '2026-09-08'}),
      ], options: '').single.lastDay,
      DateTime.utc(2026, 9, 8),
    );
  });

  test('timed events use the selected zone and an exclusive midnight end', () {
    final event = occurrences([
      calendarDetail(
        overrides: {
          'from': '2026-09-08T03:00:00Z',
          'to': '2026-09-08T07:00:00Z',
        },
      ),
    ], options: '').single;
    expect(event.allDay, isFalse);
    expect(event.start.hour, 20);
    expect(event.firstDay, DateTime.utc(2026, 9, 7));
    expect(event.lastDay, DateTime.utc(2026, 9, 7));
  });

  test('weekly recurrence stays at the author wall time through DST', () {
    final events = occurrences(
      [
        calendarDetail(
          overrides: {
            'from': '2026-10-19T07:00:00Z',
            'to': '2026-10-19T08:00:00Z',
            'recurring': '1.weeks',
          },
        ),
      ],
      options: '',
      timezone: 'Etc/UTC',
      from: DateTime.utc(2026, 10, 19),
      until: DateTime.utc(2026, 11, 1),
    );
    expect(events.map((e) => e.start.day), [19, 26]);
    expect(events.map((e) => e.start.hour), [7, 8]);
  });

  test('invalid rows cannot discard neighboring valid entries', () {
    final events = occurrences([
      null,
      4,
      {},
      calendarDetail(overrides: {'from': '2026-02-30T12:00:00Z'}),
      calendarDetail(overrides: {'to': 'not a date'}),
      calendarDetail(overrides: {'from': '2026-09-07T99:00:00Z'}),
      calendarDetail(overrides: {'to': '2026-09-01T00:00:00Z'}),
      calendarDetail(overrides: {'timezone': 'Unknown/Zone'}),
      calendarDetail(overrides: {'post_number': -1}),
      calendarDetail(overrides: {'type': 'future_type'}),
      calendarDetail(),
    ]);
    expect(events, hasLength(1));
  });

  test('holiday names and users stay readable without inventing a reply', () {
    final event = occurrences([
      {
        'type': 'grouped',
        'from': '2026-09-07T00:00:00Z',
        'name': 'Labor Day',
        'users': [
          {'username': 'sam'},
          {'username': 'lee'},
          {'username': 'sam'},
        ],
      },
    ]).single;
    expect(event.title, '(2) Labor Day');
    expect(event.description, 'Labor Day\nlee, sam');
    expect(event.postNumber, isNull);
    expect(occurrences([calendarDetail()], holiday: true).single.title, 'sam');
    expect(
      occurrences([
        calendarDetail(
          overrides: {'message': 'Planning &amp; review <img src="x">'},
        ),
      ]).single.title,
      'Planning & review',
    );
  });

  test('calendar options hide weekends and chosen weekdays', () {
    final options = calendarOptions(
      'data-weekends="false" data-hidden-days=" 2,8,bad "',
    );
    expect(options.hiddenDays, {0, 2, 6});
    expect(calendarOptions().type, 'dynamic');
    expect(calendarOptions().fullDay, isTrue);
    expect(calendarOptions('').fullDay, isFalse);
  });

  test(
    'site calendar settings survive persistence independently of RSVP settings',
    () {
      const codec = TopicCalendarSettingsCodec();
      final settings = TopicCalendarSettings.decode(const {
        'calendar_first_day_of_week': 'monday',
        'holiday_calendar_topic_id': '700',
      });
      expect(settings.firstDay, 1);
      expect(
        TopicCalendarSettings.decode(const {
          'calendar_first_day_of_week': 'saturday',
        }).firstDay,
        6,
      );
      expect(
        TopicCalendarSettings.decode(const {
          'calendar_first_day_of_week': 'sunday',
        }).firstDay,
        0,
      );
      expect(codec.decode(codec.encode(settings)), settings);
      expect(
        TopicCalendarSettings.decode(const {
          'calendar_first_day_of_week': -1,
        }).firstDay,
        1,
      );
    },
  );

  test(
    'calendar updates and removals refresh only their own topic channel',
    () {
      const plugin = TopicCalendarPlugin();
      for (final type in ['calendar_change', 'deleted', 'recovered']) {
        expect(plugin.staleTopic(700, '/topic/700', {'type': type}), isTrue);
        expect(plugin.staleTopic(701, '/topic/700', {'type': type}), isFalse);
        expect(plugin.staleTopic(700, '/polls/700', {'type': type}), isFalse);
      }
      expect(
        plugin.staleTopic(700, '/topic/700', {'type': 'created'}),
        isFalse,
      );
      expect(plugin.staleTopic(700, '/topic/700', null), isFalse);
    },
  );
}
