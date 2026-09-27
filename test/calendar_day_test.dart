import 'package:discourse_native/src/foundation/calendar_day.dart';
import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  group('calendarDay', () {
    test('truncates to the reader\'s midnight', () {
      expect(
        calendarDay(DateTime(2026, 3, 9, 23, 59, 59, 999)),
        DateTime(2026, 3, 9),
      );
      expect(calendarDay(DateTime(2026, 3, 9)), DateTime(2026, 3, 9));
    });

    test('reads a site\'s UTC stamp in the reader\'s days', () {
      final at = DateTime.utc(2026, 3, 9, 12);
      expect(calendarDay(at), calendarDay(at.toLocal()));
      expect(calendarDay(at)!.isUtc, isFalse);
    });

    test('has nothing to say about a moment that is not there', () {
      expect(calendarDay(null), isNull);
    });
  });

  group('dayLabel', () {
    test('names today and yesterday, and dates the rest', () {
      final now = DateTime(2026, 3, 9, 14, 30);

      expect(dayLabel(DateTime(2026, 3, 9), now: now), 'Today');
      expect(dayLabel(DateTime(2026, 3, 8), now: now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 3, 7), now: now), '7 March 2026');
    });

    test('compares calendar days, not elapsed hours', () {
      final now = DateTime(2026, 3, 9, 14, 30);

      // Across a spring-forward transition, consecutive local midnights sit 23
      // hours apart, not 24. A day start one hour past midnight reproduces
      // that gap in any test timezone: an elapsed-duration difference
      // truncates it to zero whole days and relabels yesterday as Today.
      expect(dayLabel(DateTime(2026, 3, 8, 1), now: now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 3, 7, 1), now: now), '7 March 2026');
    });

    test('dates a day still to come rather than naming it', () {
      final now = DateTime(2026, 3, 9, 14, 30);
      expect(dayLabel(DateTime(2026, 3, 10), now: now), '10 March 2026');
    });

    test('spells the month out for every one of them', () {
      final now = DateTime(2027, 1, 1);
      for (var month = 1; month <= 12; month++) {
        expect(
          dayLabel(DateTime(2026, month, 15), now: now),
          '15 ${monthName(month)} 2026',
        );
      }
    });
  });

  group('upcomingDayName', () {
    test('names today and tomorrow, and leaves other days to the caller', () {
      final now = DateTime(2026, 3, 9, 14);

      expect(upcomingDayName(DateTime(2026, 3, 9, 9), now: now), 'Today');
      expect(upcomingDayName(DateTime(2026, 3, 10, 9), now: now), 'Tomorrow');
      expect(upcomingDayName(DateTime(2026, 3, 11, 9), now: now), isNull);
      expect(upcomingDayName(DateTime(2026, 3, 8, 9), now: now), isNull);
    });

    test('compares calendar days, not elapsed hours', () {
      final now = DateTime(2026, 3, 9, 14);

      // Across a DST change, today's midnight plus 24 hours is not tomorrow's
      // midnight. A day start one hour past midnight reproduces that offset in
      // any test timezone.
      expect(upcomingDayName(DateTime(2026, 3, 10, 1), now: now), 'Tomorrow');
      expect(upcomingDayName(DateTime(2026, 3, 11, 1), now: now), isNull);
    });

    test('names tomorrow on the days daylight saving starts and ends', () {
      final paris = TimezoneEnvironment.instance.location('Europe/Paris')!;

      // 29 March 2026 lasts 23 hours in Paris and 25 October 2026 lasts 25.
      for (final (month, day) in [(3, 29), (10, 25)]) {
        tz.TZDateTime at(int date, [int hour = 0]) =>
            tz.TZDateTime(paris, 2026, month, date, hour);
        final now = at(day, 14);

        expect(upcomingDayName(at(day, 23), now: now), 'Today');
        expect(upcomingDayName(at(day + 1), now: now), 'Tomorrow');
        expect(upcomingDayName(at(day + 1, 9), now: now), 'Tomorrow');
        expect(upcomingDayName(at(day + 2), now: now), isNull);
      }
    });

    test('counts across the end of a month and a year', () {
      expect(
        upcomingDayName(DateTime(2026, 3, 1, 9), now: DateTime(2026, 2, 28)),
        'Tomorrow',
      );
      expect(
        upcomingDayName(DateTime(2027, 1, 1, 9), now: DateTime(2026, 12, 31)),
        'Tomorrow',
      );
    });
  });
}
