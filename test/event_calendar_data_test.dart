import 'package:discourse_native/src/plugins/discourse_events/event_calendar_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalender/kalender.dart' as kalender;
import 'package:timezone/timezone.dart' as tz;

import 'support/event_fixtures.dart';

void main() {
  late EventTestPorts ports;
  setUp(() => ports = EventTestPorts());
  tearDown(() => ports.close());

  EventCalendarEntry? entry(
    Map<String, Object?> fields, {
    String zone = 'Europe/Paris',
    EventSettings settings = const EventSettings(),
    Color? categoryColor,
  }) => EventCalendarEntry.decode(
    PostEvent.decode(eventJson(overrides: fields))!,
    zones: ports.zones,
    timezone: zone,
    settings: settings,
    categoryColor: categoryColor,
  );

  test('month bounds include spillover days and honor the first weekday', () {
    final page = EventCalendarPage(
      EventCalendarView.month,
      DateTime.utc(2026, 9, 8),
    );
    expect(
      page.days(firstDay: 1),
      DateTimeRange(
        start: DateTime.utc(2026, 8, 31),
        end: DateTime.utc(2026, 10, 5),
      ),
    );
    expect(
      page.days(firstDay: 0),
      DateTimeRange(
        start: DateTime.utc(2026, 8, 30),
        end: DateTime.utc(2026, 10, 4),
      ),
    );
    expect(
      page.days(firstDay: 6),
      DateTimeRange(
        start: DateTime.utc(2026, 8, 29),
        end: DateTime.utc(2026, 10, 3),
      ),
    );
  });

  DateTimeRange month(int year, int month, {required int firstDay}) =>
      EventCalendarPage(
        EventCalendarView.month,
        DateTime.utc(year, month, 15),
      ).days(firstDay: firstDay);

  test('a four-week month requests the fifth row Kalender draws', () {
    // 1 Feb 2027 is a Monday and February has 28 days, but Kalender never
    // draws fewer than five rows: 1–7 March is on screen.
    expect(
      month(2027, 2, firstDay: 1),
      DateTimeRange(
        start: DateTime.utc(2027, 2, 1),
        end: DateTime.utc(2027, 3, 8),
      ),
    );
  });

  test('Sunday- and Saturday-first four-week months request a fifth row', () {
    // 1 Feb 2026 is a Sunday; 1 Feb 2025 is a Saturday.
    expect(
      month(2026, 2, firstDay: 0),
      DateTimeRange(
        start: DateTime.utc(2026, 2, 1),
        end: DateTime.utc(2026, 3, 8),
      ),
    );
    expect(
      month(2025, 2, firstDay: 6),
      DateTimeRange(
        start: DateTime.utc(2025, 2, 1),
        end: DateTime.utc(2025, 3, 8),
      ),
    );
  });

  test('a six-row month requests all six rows', () {
    // 1 Aug 2026 is a Saturday: five leading days push 31 days past 35.
    final days = month(2026, 8, firstDay: 1);
    expect(
      days,
      DateTimeRange(
        start: DateTime.utc(2026, 7, 27),
        end: DateTime.utc(2026, 9, 7),
      ),
    );
    expect(days.duration, const Duration(days: 42));
  });

  test('the first weekday decides how many rows a month draws', () {
    // February 2027 is four weeks from Monday (padded to five rows) but five
    // natural rows from Sunday.
    expect(
      month(2027, 2, firstDay: 1),
      DateTimeRange(
        start: DateTime.utc(2027, 2, 1),
        end: DateTime.utc(2027, 3, 8),
      ),
    );
    expect(
      month(2027, 2, firstDay: 0),
      DateTimeRange(
        start: DateTime.utc(2027, 1, 31),
        end: DateTime.utc(2027, 3, 7),
      ),
    );
    // August 2026 fits five rows from Saturday and needs six from Sunday.
    expect(
      month(2026, 8, firstDay: 6),
      DateTimeRange(
        start: DateTime.utc(2026, 8, 1),
        end: DateTime.utc(2026, 9, 5),
      ),
    );
    expect(
      month(2026, 8, firstDay: 0),
      DateTimeRange(
        start: DateTime.utc(2026, 7, 26),
        end: DateTime.utc(2026, 9, 6),
      ),
    );
  });

  test('month and week requests cover exactly the days Kalender draws', () {
    final paris = ports.zones.location('Europe/Paris')!;
    DateTime inParis(DateTime day) =>
        tz.TZDateTime(paris, day.year, day.month, day.day);
    // Configured as EventCalendar configures its views, so a Kalender layout
    // change fails here instead of leaving a drawn row unrequested.
    final display = kalender.KalenderDateTimeRange(
      start: inParis(DateTime.utc(1900)),
      end: inParis(DateTime.utc(2200)),
    );
    DateTimeRange drawn(kalender.PageIndexCalculator pages, DateTime day) {
      final range = pages.rangeFromIndex(
        pages.indexFromDate(inParis(day), paris),
        paris,
      );
      return DateTimeRange(start: range.start, end: range.end);
    }

    for (var firstDay = 0; firstDay < 7; firstDay++) {
      final weekday = firstDay == 0 ? DateTime.sunday : firstDay;
      final months = kalender.MonthViewConfiguration.singleMonth(
        displayRange: display,
        firstDayOfWeek: weekday,
      ).pageIndexCalculator;
      final weeks = kalender.MultiDayViewConfiguration.week(
        displayRange: display,
        firstDayOfWeek: weekday,
      ).pageIndexCalculator;
      // Every month of three years reaches all three row counts, including
      // the four-week Februaries of 2025, 2026 and 2027.
      for (var index = 0; index < 36; index++) {
        final day = DateTime.utc(2025, 1 + index, 15);
        expect(
          EventCalendarPage(
            EventCalendarView.month,
            day,
          ).days(firstDay: firstDay),
          drawn(months, day),
          reason: 'month of $day, first day $firstDay',
        );
      }
      for (var offset = 0; offset < 14; offset++) {
        final day = DateTime.utc(2027, 2, 22 + offset);
        expect(
          EventCalendarPage(
            EventCalendarView.week,
            day,
          ).days(firstDay: firstDay),
          drawn(weeks, day),
          reason: 'week of $day, first day $firstDay',
        );
      }
    }
  });

  test('schedule bounds and routes navigate by calendar month', () {
    final page = EventCalendarPage(
      EventCalendarView.schedule,
      DateTime.utc(2026, 12, 31),
    );
    expect(
      page.days(firstDay: 1),
      DateTimeRange(start: DateTime.utc(2026, 12), end: DateTime.utc(2027)),
    );
    expect(page.move(1).date, DateTime.utc(2027));
    expect(page.move(-1).date, DateTime.utc(2026, 11));
    expect(EventCalendarPage.readRoute(page.routeId(false))!.page, page);
    expect(page.webPath(false), 'upcoming-events/listMonth/2026/12/31');
    expect(EventCalendarView.parse('listMonth'), EventCalendarView.schedule);
  });

  test('schedule continuation labels count civil days across DST', () {
    final event = entry({
      'all_day': true,
      'starts_at': '2026-10-24',
      'ends_at': '2026-10-26',
    })!;
    expect(
      event.scheduleMetadata(DateTime.utc(2026, 10, 25)),
      'sam · day 2 of 3',
    );
    expect(
      event.scheduleMetadata(DateTime.utc(2026, 10, 26)),
      'sam · day 3 of 3',
    );
  });

  test('all-day inclusive end stays on its dates across DST and timezones', () {
    for (final (start, end, hours) in [
      ('2026-03-29', '2026-03-29', 23),
      ('2026-10-25', '2026-10-25', 25),
      ('2026-03-28', '2026-03-30', 71),
    ]) {
      final event = entry({
        'all_day': true,
        'starts_at': start,
        'ends_at': end,
      })!;
      expect(event.duration.inHours, hours);
      expect(event.localStart.hour, 0);
      expect(event.localEnd.hour, 0);
      expect(event.includes(DateTime.parse('${start}T00:00:00Z')), isTrue);
      expect(event.includes(DateTime.parse('${end}T00:00:00Z')), isTrue);
      expect(
        event.includes(
          DateTime.parse('${end}T00:00:00Z').add(const Duration(days: 1)),
        ),
        isFalse,
      );
    }
    final event = entry({
      'all_day': true,
      'starts_at': '2026-09-08',
      'ends_at': null,
    }, zone: 'America/Los_Angeles')!;
    expect(
      (event.localStart.day, event.localEnd.day, event.isAllDay),
      (8, 9, true),
    );
  });

  test(
    'timed instants convert to the reader while local-time events float',
    () {
      final instant = entry({
        'starts_at': '2026-09-08T23:30:00+02:00',
        'ends_at': '2026-09-09T01:00:00+02:00',
      }, zone: 'America/Los_Angeles')!;
      expect(
        (
          instant.localStart.day,
          instant.localStart.hour,
          instant.localStart.minute,
        ),
        (8, 14, 30),
      );
      expect(instant.spansDays, isFalse);
      final local = entry({
        'show_local_time': true,
        'starts_at': '2026-09-08T09:00:00',
        'ends_at': '2026-09-08T10:00:00',
      }, zone: 'America/Los_Angeles')!;
      expect((local.localStart.day, local.localStart.hour), (8, 9));
      expect(local.title, 'Engineering Managers Call (local time)');
      final overnight = entry({
        'starts_at': '2026-09-08T23:30:00+02:00',
        'ends_at': '2026-09-09T01:00:00+02:00',
      })!;
      expect(overnight.spansDays, isTrue);
      expect(overnight.isAllDay, isFalse);
    },
  );

  test(
    'invalid dates are omitted and legacy midnight events occupy full days',
    () {
      expect(entry({'starts_at': 'not a date'}), isNull);
      expect(entry({'starts_at': '2026-02-30T09:00:00Z'}), isNull);
      expect(
        entry({
          'starts_at': '2026-09-08T10:00:00Z',
          'ends_at': '2026-09-08T09:00:00Z',
        }),
        isNull,
      );
      final legacy = entry({
        'starts_at': '2026-09-08T00:00:00',
        'ends_at': '2026-09-09T00:00:00',
      })!;
      expect(
        (legacy.isAllDay, legacy.localStart.day, legacy.localEnd.day),
        (true, 8, 10),
      );
    },
  );

  test('tag overrides precede category overrides and category fallback', () {
    final settings = EventSettings.decode(const {
      'calendar_upcoming_events_default_view': 'agendaWeek',
      'calendar_event_display': 'list-item',
      'map_events_to_color':
          '[{"type":"category","slug":"team","color":"#0077aa"},{"type":"tag","slug":"launch","color":"#d25"}]',
    });
    final post = {
      'id': 42,
      'category_slug': 'team',
      'topic': {
        'id': 700,
        'tags': [
          {'name': 'Launch', 'slug': 'launch'},
        ],
      },
    };
    expect(
      entry(
        {'post': post},
        settings: settings,
        categoryColor: Colors.orange,
      )!.color,
      const Color(0xffdd2255),
    );
    expect(
      entry({
        'post': {
          ...post,
          'topic': {'id': 700},
        },
      }, settings: settings)!.color,
      const Color(0xff0077aa),
    );
    expect(entry({}, categoryColor: Colors.orange)!.color, Colors.orange);
    expect(
      (settings.calendarView, settings.calendarDisplay),
      (EventCalendarView.week, 'list-item'),
    );
    expect(
      const EventSettingsCodec().decode(
        const EventSettingsCodec().encode(settings),
      ),
      settings,
    );
    expect(
      EventSettings.decode(const {
        'map_events_to_color': 'invalid',
      }).calendarColors,
      isEmpty,
    );
  });

  test(
    'dated route aliases round-trip without accepting invalid dates or views',
    () {
      final route = EventCalendarPage.readRoute(
        'events-mine/agendaWeek/2026/9/8',
      )!;
      expect(route.mine, isTrue);
      expect(route.page!.routeId(true), 'events-mine/week/2026/9/8');
      expect(route.page!.webPath(true), 'upcoming-events/mine/week/2026/9/8');
      for (final invalid in [
        'events-upcoming/month/2026/2/30',
        'events-upcoming/unknown/2026/9/8',
        'events-upcoming/day/999999999999/1/1',
        'events-other',
      ]) {
        expect(EventCalendarPage.readRoute(invalid), isNull);
      }
    },
  );
}
