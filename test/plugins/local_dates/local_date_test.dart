import 'package:discourse_native/src/plugins/local_dates/local_date.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  final environment = LocalDateEnvironment.instance;
  environment.ensureDatabase();

  setUpAll(() async {
    environment.ensureDatabase();
    environment.setDeviceTimezone('Etc/UTC');
    await initializeDateFormatting('fr');
  });

  setUp(() => environment.setDeviceTimezone('Etc/UTC'));

  group('resolution', () {
    final formatter = LocalDateFormatter(environment: environment);

    test(
      'rejects invalid zones and DST gaps instead of inventing instants',
      () {
        expect(
          formatter.resolve(
            const LocalDateSpec(
              date: '2026-01-01',
              time: '12:00:00',
              timezone: 'Mars/Olympus',
              fallbackText: 'server text',
            ),
            locale: const Locale('en'),
          ),
          isNull,
        );
        expect(
          formatter.resolve(
            const LocalDateSpec(
              date: '2024-03-10',
              time: '02:30:00',
              timezone: 'America/New_York',
              fallbackText: 'server text',
            ),
            locale: const Locale('en'),
          ),
          isNull,
        );
      },
    );

    test('accepts a DST overlap as one real source-wall occurrence', () {
      final value = formatter.resolve(
        const LocalDateSpec(
          date: '2024-11-03',
          time: '01:30:00',
          timezone: 'America/New_York',
          fallbackText: '',
        ),
        locale: const Locale('en'),
      );

      expect(value, isNotNull);
      expect(value!.source.hour, 1);
      expect(value.source.minute, 30);
    });

    test('converts a source wall time into the device zone', () {
      environment.setDeviceTimezone('Europe/Paris');
      final value = formatter.resolve(
        const LocalDateSpec(
          date: '2026-01-15',
          time: '12:00:00',
          timezone: 'America/New_York',
          calendar: false,
          format: 'YYYY-MM-DD HH:mm',
          fallbackText: '',
        ),
        locale: const Locale('en'),
        now: DateTime.utc(2020),
      );

      expect(value!.displayed.hour, 18);
      expect(value.formatted, '2026-01-15 18:00');
    });

    test(
      'advances weekly recurrence while preserving source wall time over DST',
      () {
        environment.setDeviceTimezone('Europe/Paris');
        final value = formatter.resolve(
          const LocalDateSpec(
            date: '2021-11-22',
            time: '11:00:00',
            timezone: 'Europe/Paris',
            recurring: '1.weeks',
            calendar: false,
            fallbackText: '',
          ),
          locale: const Locale('en'),
          now: DateTime.utc(2022, 4, 5, 20),
        );

        expect(
          value!.source,
          tz.TZDateTime(tz.getLocation('Europe/Paris'), 2022, 4, 11, 11),
        );
      },
    );

    test('leaves a recurrence nobody could mean where the server put it', () {
      environment.setDeviceTimezone('Europe/Paris');
      LocalDateResolved? resolve(String recurring) => formatter.resolve(
        LocalDateSpec(
          date: '2021-11-22',
          time: '11:00:00',
          timezone: 'Europe/Paris',
          recurring: recurring,
          calendar: false,
          format: 'YYYY-MM-DD HH:mm',
          fallbackText: '',
        ),
        locale: const Locale('en'),
        now: DateTime.utc(2022, 4, 5, 20),
      );

      // User-authored counts must not overflow int parsing or Duration math.
      for (final recurring in const [
        '99999999999999999999999.days',
        '900000000000.days',
        '99999999999999999999999999.milliseconds',
      ]) {
        expect(
          resolve(recurring)?.formatted,
          '2021-11-22 11:00',
          reason: recurring,
        );
      }

      expect(resolve('1.weeks')?.formatted, '2022-04-11 11:00');
    });

    test(
      'uses localized natural day labels and explicit formats disable them',
      () {
        environment.setDeviceTimezone('Europe/Paris');
        final natural = formatter.resolve(
          const LocalDateSpec(
            date: '2026-08-10',
            timezone: 'Europe/Paris',
            fallbackText: '',
          ),
          locale: const Locale('fr'),
          now: DateTime.utc(2026, 8, 9, 10),
        );
        final explicit = formatter.resolve(
          const LocalDateSpec(
            date: '2026-08-10',
            timezone: 'Europe/Paris',
            format: 'YYYY',
            fallbackText: '',
          ),
          locale: const Locale('fr'),
          now: DateTime.utc(2026, 8, 9, 10),
        );

        expect(natural!.formatted.toLowerCase(), contains('demain'));
        expect(explicit!.formatted, '2026');
      },
    );

    test('countdown has a localized elapsed state', () {
      final elapsed = formatter.resolve(
        const LocalDateSpec(
          date: '2020-01-01',
          time: '00:00:00',
          timezone: 'UTC',
          countdown: true,
          fallbackText: '',
        ),
        locale: const Locale('en'),
        now: DateTime.utc(2026),
      );
      expect(elapsed!.formatted, 'now');
    });

    test('countdown matches upstream humanize buckets without a prefix', () {
      String countdown(DateTime now) => formatter
          .resolve(
            const LocalDateSpec(
              date: '2026-01-11',
              time: '00:00:00',
              timezone: 'UTC',
              countdown: true,
              fallbackText: '',
            ),
            locale: const Locale('en'),
            now: now,
          )!
          .formatted;

      expect(countdown(DateTime.utc(2026, 1, 10, 23, 59, 40)), 'a few seconds');
      expect(countdown(DateTime.utc(2026, 1, 10, 23, 30)), '30 minutes');
      expect(countdown(DateTime.utc(2026, 1, 10, 23, 15)), 'an hour');
      expect(countdown(DateTime.utc(2026, 1, 1)), '10 days');
      expect(countdown(DateTime.utc(2025, 12, 12)), 'a month');
    });

    test('previews preserve order while deduplicating zones and offsets', () {
      environment.setDeviceTimezone('Etc/UTC');
      final previews = formatter.previews(
        const LocalDateSpec(
          date: '2026-01-15',
          time: '12:00:00',
          timezone: 'GMT',
          timezones: [
            'UTC',
            'Etc/GMT',
            'America/New_York',
            'US/Eastern',
            'Asia/Tokyo',
            'JST',
          ],
          fallbackText: '',
        ),
        locale: const Locale('en'),
        now: DateTime.utc(2020),
      );

      expect(previews.map((preview) => preview.timezone), [
        'Etc/UTC',
        'Etc/GMT',
        'America/New_York',
        'Asia/Tokyo',
      ]);
      expect(previews.first.current, isTrue);
      expect(previews[1].source, isTrue);
    });

    test('preview deduplication stays bounded for oversized cooked input', () {
      environment.setDeviceTimezone('Etc/UTC');
      final previews = formatter.previews(
        LocalDateSpec(
          date: '2026-01-15',
          time: '12:00:00',
          timezone: 'America/New_York',
          timezones: List.filled(100000, 'Asia/Tokyo'),
          fallbackText: '',
        ),
        locale: const Locale('en'),
        now: DateTime.utc(2020),
      );

      expect(previews.map((preview) => preview.timezone), [
        'Etc/UTC',
        'America/New_York',
        'Asia/Tokyo',
      ]);
    });
  });

  group('recurrence', () {
    final formatter = LocalDateFormatter(environment: environment);

    DateTime? resolve({
      required String date,
      required DateTime now,
      String time = '00:00:00',
      String zone = 'America/New_York',
      String recurring = '1.milliseconds',
    }) => formatter.resolveInstant(
      LocalDateSpec(
        date: date,
        time: time,
        timezone: zone,
        recurring: recurring,
        fallbackText: '',
      ),
      now: now,
    );

    for (final zone in ['America/New_York', 'Australia/Lord_Howe']) {
      for (final (startMonth, endMonth) in [(1, 7), (7, 12)]) {
        test('resolves fine intervals across $zone $startMonth–$endMonth', () {
          final now = DateTime.utc(2026, endMonth);
          for (final unit in ['seconds', 'milliseconds']) {
            final date = '2026-${startMonth.toString().padLeft(2, '0')}-01';
            expect(
              resolve(date: date, zone: zone, recurring: '1.$unit', now: now),
              now,
              reason: unit,
            );
            expect(
              resolve(
                date: date,
                zone: zone,
                recurring: '1.$unit',
                now: now.add(const Duration(microseconds: 1)),
              ),
              now.add(
                unit == 'seconds'
                    ? const Duration(seconds: 1)
                    : const Duration(milliseconds: 1),
              ),
              reason: '$unit just after the boundary',
            );
          }
        });
      }
    }

    test('keeps the first eligible wall recurrence across a spring gap', () {
      // 02:50 normalizes to 03:50; the next wall occurrence, 03:30,
      // maps backwards and has already elapsed at this deadline.
      expect(
        resolve(
          date: '2026-03-08',
          time: '00:50:00',
          recurring: '40.minutes',
          now: DateTime.utc(2026, 3, 8, 7, 35),
        ),
        DateTime.utc(2026, 3, 8, 7, 50),
      );
      expect(
        resolve(
          date: '2026-03-08',
          time: '01:59:59',
          recurring: '7.milliseconds',
          now: DateTime.utc(2026, 3, 8, 7, 0, 0, 0, 1),
        ),
        DateTime.utc(2026, 3, 8, 7, 0, 0, 1),
      );
    });

    test('does not invent a second occurrence during the New York fold', () {
      expect(
        resolve(date: '2026-11-01', now: DateTime.utc(2026, 11, 1, 6, 30)),
        DateTime.utc(2026, 11, 1, 7),
      );
    });

    test('preserves Lord Howe gap normalization and overlap selection', () {
      expect(
        resolve(
          date: '2026-10-04',
          time: '00:55:00',
          zone: 'Australia/Lord_Howe',
          recurring: '20.minutes',
          now: DateTime.utc(2026, 10, 3, 15, 40),
        ),
        DateTime.utc(2026, 10, 3, 15, 45),
      );
      // The constructor chooses the later 01:30 here, so it is the first
      // eligible wall occurrence even while the clock first reads 01:45.
      expect(
        resolve(
          date: '2026-04-05',
          zone: 'Australia/Lord_Howe',
          now: DateTime.utc(2026, 4, 4, 14, 45),
        ),
        DateTime.utc(2026, 4, 4, 15),
      );
    });

    test(
      'resolves across Apia’s skipped day without skipping an occurrence',
      () {
        expect(
          resolve(
            date: '2011-12-29',
            time: '12:00:00',
            zone: 'Pacific/Apia',
            recurring: '20.hours',
            now: DateTime.utc(2011, 12, 30, 15),
          ),
          DateTime.utc(2011, 12, 30, 18),
        );
        expect(
          resolve(
            date: '2011-01-01',
            zone: 'Pacific/Apia',
            now: DateTime.utc(2012, 1, 2),
          ),
          DateTime.utc(2012, 1, 2),
        );
      },
    );

    for (final (recurring, date, boundary, next) in [
      (
        '1.days',
        '2026-03-06',
        DateTime.utc(2026, 3, 8, 7, 30),
        DateTime.utc(2026, 3, 9, 6, 30),
      ),
      (
        '1.weeks',
        '2026-03-01',
        DateTime.utc(2026, 3, 8, 7, 30),
        DateTime.utc(2026, 3, 15, 6, 30),
      ),
      (
        '1.months',
        '2026-02-08',
        DateTime.utc(2026, 3, 8, 7, 30),
        DateTime.utc(2026, 4, 8, 6, 30),
      ),
      (
        '1.months',
        '2026-01-31',
        DateTime.utc(2026, 2, 28, 7, 30),
        DateTime.utc(2026, 3, 31, 6, 30),
      ),
      (
        '1.quarters',
        '2026-01-31',
        DateTime.utc(2026, 4, 30, 6, 30),
        DateTime.utc(2026, 7, 31, 6, 30),
      ),
      (
        '1.years',
        '2024-02-29',
        DateTime.utc(2027, 2, 28, 7, 30),
        DateTime.utc(2028, 2, 29, 7, 30),
      ),
    ]) {
      test(
        '$recurring from $date keeps its boundary and original wall anchor',
        () {
          expect(
            resolve(
              date: date,
              time: '02:30:00',
              recurring: recurring,
              now: boundary,
            ),
            boundary,
          );
          expect(
            resolve(
              date: date,
              time: '02:30:00',
              recurring: recurring,
              now: boundary.add(const Duration(microseconds: 1)),
            ),
            next,
          );
        },
      );
    }

    test('keeps an invalid recurring source in a DST gap unresolved', () {
      expect(
        resolve(
          date: '2026-03-08',
          time: '02:30:00',
          now: DateTime.utc(2026, 7, 1),
        ),
        isNull,
      );
    });

    for (final (zone, date, transition, offsetChange) in [
      (
        'America/New_York',
        '2026-03-07',
        DateTime.utc(2026, 3, 8, 7),
        const Duration(hours: 1),
      ),
      (
        'America/New_York',
        '2026-10-31',
        DateTime.utc(2026, 11, 1, 6),
        const Duration(hours: -1),
      ),
      (
        'Australia/Lord_Howe',
        '2026-10-03',
        DateTime.utc(2026, 10, 3, 15, 30),
        const Duration(minutes: 30),
      ),
      (
        'Australia/Lord_Howe',
        '2026-04-04',
        DateTime.utc(2026, 4, 4, 15),
        const Duration(minutes: -30),
      ),
      (
        'Pacific/Apia',
        '2011-12-29',
        DateTime.utc(2011, 12, 30, 10),
        const Duration(days: 1),
      ),
      (
        'Pacific/Kwajalein',
        '1969-09-29',
        DateTime.utc(1969, 9, 30, 13),
        const Duration(hours: -23),
      ),
    ]) {
      test('matches sequential wall occurrences around $zone $date', () {
        final location = tz.getLocation(zone);
        // Guard the corpus: each named instant must still exercise its offset
        // change in the bundled timezone database.
        expect(
          tz.TZDateTime.from(transition, location).timeZoneOffset -
              tz.TZDateTime.from(
                transition.subtract(const Duration(microseconds: 1)),
                location,
              ).timeZoneOffset,
          offsetChange,
        );
        for (final minutes in [17, 40, 90]) {
          for (final delta in const [
            Duration(microseconds: -1),
            Duration.zero,
            Duration(microseconds: 1),
            Duration(minutes: 30),
            Duration(minutes: 90),
            Duration(hours: 23),
          ]) {
            final now = transition.add(delta);
            expect(
              resolve(
                date: date,
                zone: zone,
                recurring: '$minutes.minutes',
                now: now,
              ),
              _firstWallOccurrence(
                location,
                DateTime.parse('${date}T00:00:00Z'),
                Duration(minutes: minutes),
                now,
              ),
              reason: '$minutes minutes, now=$now',
            );
          }
        }
      });
    }

    test('fine intervals do not scan every skipped DST millisecond', () {
      final now = DateTime.utc(2026, 7, 1);
      var best = const Duration(days: 1);
      for (var trial = 0; trial < 3; trial++) {
        final stopwatch = Stopwatch()..start();
        for (var render = 0; render < 8; render++) {
          expect(resolve(date: '2026-01-01', now: now), now);
        }
        stopwatch.stop();
        if (stopwatch.elapsed < best) best = stopwatch.elapsed;
      }
      // The old correction loop took several seconds for this batch. Leave
      // ample room for loaded CI machines; no microsecond timing contract.
      expect(best, lessThan(const Duration(seconds: 1)));
    });
  });

  group('Moment formatting', () {
    final value = tz.TZDateTime(
      tz.getLocation('America/New_York'),
      2026,
      8,
      9,
      13,
      5,
      7,
      123,
    );

    test('supports standard, ordinal, offset, zone, and bracket tokens', () {
      expect(
        LocalDateFormatter.formatMoment(
          value,
          'YYYY-MM-DD Do [at] HH:mm:ss.SSS Z z',
          const Locale('en'),
        ),
        '2026-08-09 9th at 13:05:07.123 -04:00 EDT',
      );
    });

    test('keeps unknown future tokens literal', () {
      expect(
        LocalDateFormatter.formatMoment(
          value,
          '[prefix] FUTURE',
          const Locale('en'),
        ),
        'prefix FUTURE',
      );
    });

    test(
      'a lone unknown letter stays literal while adjacent tokens format',
      () {
        final time = tz.TZDateTime(
          tz.getLocation('Etc/UTC'),
          2026,
          8,
          21,
          14,
          30,
        );

        expect(
          LocalDateFormatter.formatMoment(
            time,
            'YYYY-MM-DDTHH:mm',
            const Locale('en'),
          ),
          '2026-08-21T14:30',
        );
        expect(
          LocalDateFormatter.formatMoment(time, 'THH', const Locale('en')),
          'T14',
        );
        expect(
          LocalDateFormatter.formatMoment(time, 'FUTURE', const Locale('en')),
          'FUTURE',
        );
      },
    );

    test('day-of-year and ISO week follow the displayed wall clock', () {
      const locale = Locale('en');
      final newYork = tz.getLocation('America/New_York');

      final yearEnd = tz.TZDateTime(newYork, 2026, 12, 31, 23);
      expect(LocalDateFormatter.formatMoment(yearEnd, 'DDD', locale), '365');
      expect(LocalDateFormatter.formatMoment(yearEnd, 'w', locale), '53');
      expect(LocalDateFormatter.formatMoment(yearEnd, 'gggg', locale), '2026');

      final afterSpringForward = tz.TZDateTime(
        tz.getLocation('Australia/Sydney'),
        2026,
        10,
        4,
        3,
        30,
      );
      expect(
        LocalDateFormatter.formatMoment(afterSpringForward, 'DDD', locale),
        '277',
      );
      expect(
        LocalDateFormatter.formatMoment(afterSpringForward, 'w', locale),
        '40',
      );

      final midYear = tz.TZDateTime(
        tz.getLocation('Europe/Paris'),
        2026,
        7,
        1,
        12,
      );
      expect(LocalDateFormatter.formatMoment(midYear, 'DDD', locale), '182');
      expect(LocalDateFormatter.formatMoment(midYear, 'w', locale), '27');

      final isoRollover = tz.TZDateTime(newYork, 2025, 12, 29, 12);
      expect(LocalDateFormatter.formatMoment(isoRollover, 'w', locale), '1');
      expect(
        LocalDateFormatter.formatMoment(isoRollover, 'gggg', locale),
        '2026',
      );
    });
  });
}

// Enumerate a small wall-clock series independently of the formatter's
// estimation and transition skipping. The bound keeps test mistakes finite.
DateTime _firstWallOccurrence(
  tz.Location location,
  DateTime wall,
  Duration interval,
  DateTime now,
) {
  for (var repetition = 0; repetition < 500; repetition++) {
    final instant = tz.TZDateTime(
      location,
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
      wall.second,
      wall.millisecond,
    ).toUtc();
    if (!instant.isBefore(now)) return instant;
    wall = wall.add(interval);
  }
  throw StateError('reference series did not reach $now in $location');
}
