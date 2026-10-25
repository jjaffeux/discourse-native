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

  group('same-day range end', () {
    final formatter = LocalDateFormatter(environment: environment);

    String end({
      String? format,
      bool? calendar,
      bool countdown = false,
      bool sameLocalDayAsFrom = true,
    }) => formatter
        .resolve(
          LocalDateSpec(
            date: '2026-08-09',
            time: '10:30:00',
            timezone: 'UTC',
            range: 'to',
            format: format,
            calendar: calendar,
            countdown: countdown,
            fallbackText: '',
          ),
          locale: const Locale('en'),
          now: DateTime.utc(2026, 1, 1),
          sameLocalDayAsFrom: sameLocalDayAsFrom,
        )!
        .formatted;

    String time(String format) => LocalDateFormatter.formatMoment(
      DateTime.utc(2026, 8, 9, 10, 30),
      format,
      const Locale('en'),
    );

    test('shortens to the zoned time while the calendar is in use', () {
      expect(end(), '${time('LT')} (UTC)');
      expect(
        end(format: 'YYYY-MM-DD HH:mm', calendar: true),
        '${time('LT')} (UTC)',
      );
    });

    test('keeps the full format when calendar is off or a format opts out', () {
      expect(end(calendar: false), time('LLL'));
      expect(end(format: 'YYYY-MM-DD HH:mm'), '2026-08-09 10:30');
      expect(
        end(format: 'YYYY-MM-DD HH:mm', calendar: false),
        '2026-08-09 10:30',
      );
    });

    test('a different-day end keeps the full format', () {
      expect(end(sameLocalDayAsFrom: false), time('LLL'));
    });

    test('a countdown ignores the range', () {
      expect(
        end(countdown: true),
        end(countdown: true, sameLocalDayAsFrom: false),
      );
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

    for (final (locale, padded, compact) in const [
      (Locale('en'), '01/05/2026', '1/5/2026'),
      (Locale('en', 'GB'), '05/01/2026', '5/1/2026'),
      (Locale('fr'), '05/01/2026', '5/1/2026'),
      (Locale('de'), '05.01.2026', '5.1.2026'),
      (Locale('zh', 'CN'), '2026/01/05', '2026/1/5'),
    ]) {
      test('numeric aliases preserve padding and locale order for $locale', () {
        final date = DateTime.utc(2026, 1, 5);

        expect(LocalDateFormatter.formatMoment(date, 'L', locale), padded);
        expect(LocalDateFormatter.formatMoment(date, 'l', locale), compact);
      });
    }

    test('numeric aliases compose with time and preserve escaped literals', () {
      final date = DateTime.utc(2026, 1, 5, 13, 7);

      expect(
        LocalDateFormatter.formatMoment(
          date,
          r'[L/l] \L \l L [|] l HH:mm',
          const Locale('en'),
        ),
        'L/l L l 01/05/2026 | 1/5/2026 13:07',
      );
      expect(
        LocalDateFormatter.formatMoment(
          date,
          'L [|] l LT',
          const Locale('fr'),
        ),
        '05/01/2026 | 5/1/2026 13:07',
      );
    });

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

    test('locale week tokens use English week boundaries', () {
      expect(
        LocalDateFormatter.formatMoment(
          DateTime.utc(2026, 12, 31),
          'w ww wo gg gggg | W WW Wo GG GGGG',
          const Locale('en'),
        ),
        '1 01 1st 27 2027 | 53 53 53rd 26 2026',
      );
    });

    test('locale weekday starts on Monday in French', () {
      expect(
        LocalDateFormatter.formatMoment(
          DateTime.utc(2026, 8, 9),
          'd e E',
          const Locale('fr'),
        ),
        '0 6 7',
      );
    });

    test('week numbers and years follow both sides of calendar boundaries', () {
      final cases = [
        (
          const Locale('en'),
          DateTime.utc(2025, 12, 27),
          '52 52 25 2025 | 52 52 25 2025 | 6 6 6',
        ),
        (
          const Locale('en'),
          DateTime.utc(2025, 12, 28),
          '1 01 26 2026 | 52 52 25 2025 | 0 0 7',
        ),
        (
          const Locale('en'),
          DateTime.utc(2027, 1, 1),
          '1 01 27 2027 | 53 53 26 2026 | 5 5 5',
        ),
        (
          const Locale('fr'),
          DateTime.utc(2027, 1, 1),
          '53 53 26 2026 | 53 53 26 2026 | 5 4 5',
        ),
        (
          const Locale('fr'),
          DateTime.utc(2027, 1, 4),
          '1 01 27 2027 | 1 01 27 2027 | 1 0 1',
        ),
        (
          const Locale('fr'),
          DateTime.utc(2021, 1, 1),
          '53 53 20 2020 | 53 53 20 2020 | 5 4 5',
        ),
        (
          const Locale('fr'),
          DateTime.utc(2022, 1, 1),
          '52 52 21 2021 | 52 52 21 2021 | 6 5 6',
        ),
        (
          const Locale('fr'),
          DateTime.utc(2024, 12, 31),
          '1 01 25 2025 | 1 01 25 2025 | 2 1 2',
        ),
      ];
      for (final (locale, date, expected) in cases) {
        expect(
          LocalDateFormatter.formatMoment(
            date,
            'w ww gg gggg | W WW GG GGGG | d e E',
            locale,
          ),
          expected,
          reason: '$locale $date',
        );
      }
    });

    test(
      'regional week rules override language defaults and normalize locale separators',
      () {
        final cases = [
          (
            const Locale('en', 'AU'),
            DateTime.utc(2026, 1, 1),
            '1 2026 1 2026 4',
          ),
          (
            const Locale('en-au'),
            DateTime.utc(2026, 12, 31),
            '53 2026 53 2026 4',
          ),
          (
            const Locale('en', 'AU'),
            DateTime.utc(2027, 1, 1),
            '53 2026 53 2026 5',
          ),
          (
            const Locale('en', 'AU'),
            DateTime.utc(2027, 1, 3),
            '1 2027 53 2026 0',
          ),
          (
            const Locale('en', 'GB'),
            DateTime.utc(2025, 12, 28),
            '52 2025 52 2025 6',
          ),
          (
            const Locale('en', 'NZ'),
            DateTime.utc(2025, 12, 28),
            '52 2025 52 2025 6',
          ),
          (
            const Locale('en', 'SG'),
            DateTime.utc(2025, 12, 28),
            '52 2025 52 2025 6',
          ),
          (
            const Locale('zh', 'CN'),
            DateTime.utc(2025, 12, 28),
            '52 2025 52 2025 6',
          ),
          (
            const Locale('fr', 'CA'),
            DateTime.utc(2026, 12, 31),
            '1 2027 53 2026 4',
          ),
          (
            const Locale('fr', 'XX'),
            DateTime.utc(2026, 12, 31),
            '53 2026 53 2026 3',
          ),
          (
            const Locale('unknown', 'XX'),
            DateTime.utc(2026, 12, 31),
            '1 2027 53 2026 4',
          ),
          (
            const Locale('ar', 'KW'),
            DateTime.utc(2026, 12, 31),
            '2 2027 53 2026 4',
          ),
          (const Locale('dv'), DateTime.utc(2022, 1, 1), '53 2021 52 2021 6'),
        ];
        for (final (locale, date, expected) in cases) {
          expect(
            LocalDateFormatter.formatMoment(date, 'w gggg W GGGG e', locale),
            expected,
            reason: '$locale $date',
          );
        }
      },
    );

    test(
      'minimal and numeric weekdays retain their distinct locale meanings',
      () {
        final cases = [
          (DateTime.utc(2026, 8, 9), const Locale('en'), '0 0 7 Su'),
          (DateTime.utc(2026, 8, 9), const Locale('fr'), '0 6 7 di'),
          (DateTime.utc(2026, 8, 10), const Locale('en'), '1 1 1 Mo'),
          (DateTime.utc(2026, 8, 10), const Locale('fr'), '1 0 1 lu'),
          (DateTime.utc(2026, 8, 11), const Locale('en'), '2 2 2 Tu'),
          (DateTime.utc(2026, 8, 11), const Locale('fr'), '2 1 2 ma'),
          (DateTime.utc(2026, 8, 12), const Locale('en'), '3 3 3 We'),
          (DateTime.utc(2026, 8, 12), const Locale('fr'), '3 2 3 me'),
          (DateTime.utc(2026, 8, 13), const Locale('en'), '4 4 4 Th'),
          (DateTime.utc(2026, 8, 13), const Locale('fr'), '4 3 4 je'),
          (DateTime.utc(2026, 8, 14), const Locale('en'), '5 5 5 Fr'),
          (DateTime.utc(2026, 8, 14), const Locale('fr'), '5 4 5 ve'),
          (DateTime.utc(2026, 8, 15), const Locale('en'), '6 6 6 Sa'),
          (DateTime.utc(2026, 8, 15), const Locale('fr'), '6 5 6 sa'),
        ];
        for (final (date, locale, expected) in cases) {
          expect(
            LocalDateFormatter.formatMoment(date, 'd e E dd', locale),
            expected,
          );
        }
      },
    );

    test('French ordinals distinguish days, weeks, and other periods', () {
      final cases = [
        (const Locale('fr'), DateTime.utc(2027, 1, 1), '1er 1er 1er 53e 53e'),
        (const Locale('fr'), DateTime.utc(2027, 1, 4), '4 4e 1er 1re 1re'),
        (const Locale('fr'), DateTime.utc(2027, 4, 21), '21 111e 2e 16e 16e'),
        (
          const Locale('fr', 'CA'),
          DateTime.utc(2027, 1, 1),
          '1er 1er 1er 1re 53e',
        ),
        (
          const Locale('fr', 'CA'),
          DateTime.utc(2027, 1, 4),
          '4e 4e 1er 2e 1re',
        ),
        (
          const Locale('fr', 'CH'),
          DateTime.utc(2027, 1, 4),
          '4e 4e 1er 1re 1re',
        ),
        (
          const Locale('fr', 'XX'),
          DateTime.utc(2027, 1, 4),
          '4 4e 1er 1re 1re',
        ),
        (
          const Locale('en'),
          DateTime.utc(2027, 1, 11),
          '11th 11th 1st 3rd 2nd',
        ),
        (
          const Locale('en'),
          DateTime.utc(2027, 1, 12),
          '12th 12th 1st 3rd 2nd',
        ),
        (
          const Locale('en'),
          DateTime.utc(2027, 1, 13),
          '13th 13th 1st 3rd 2nd',
        ),
        (
          const Locale('en'),
          DateTime.utc(2027, 4, 21),
          '21st 111th 2nd 17th 16th',
        ),
      ];
      for (final (locale, date, expected) in cases) {
        expect(
          LocalDateFormatter.formatMoment(date, 'Do DDDo Qo wo Wo', locale),
          expected,
          reason: '$locale $date',
        );
      }
    });

    test(
      'locale weeks retain the displayed date across UTC and DST boundaries',
      () {
        final cases = [
          (
            tz.TZDateTime(
              tz.getLocation('America/New_York'),
              2026,
              12,
              31,
              23,
              30,
            ),
            const Locale('en'),
            '1 2027 53 2026 4',
          ),
          (
            tz.TZDateTime(
              tz.getLocation('Pacific/Auckland'),
              2027,
              1,
              4,
              0,
              30,
            ),
            const Locale('fr'),
            '1 2027 1 2027 0',
          ),
          (
            tz.TZDateTime(
              tz.getLocation('Australia/Sydney'),
              2026,
              10,
              4,
              3,
              30,
            ),
            const Locale('en', 'AU'),
            '41 2026 40 2026 0',
          ),
          (
            tz.TZDateTime(tz.getLocation('Europe/Paris'), 2026, 10, 25, 3, 30),
            const Locale('fr'),
            '43 2026 43 2026 6',
          ),
        ];
        for (final (date, locale, expected) in cases) {
          expect(
            LocalDateFormatter.formatMoment(date, 'w gggg W GGGG e', locale),
            expected,
            reason: '$locale $date',
          );
        }
      },
    );

    test('day-of-year and ISO week follow the displayed wall clock', () {
      const locale = Locale('en');
      final newYork = tz.getLocation('America/New_York');

      final yearEnd = tz.TZDateTime(newYork, 2026, 12, 31, 23);
      expect(LocalDateFormatter.formatMoment(yearEnd, 'DDD', locale), '365');
      expect(LocalDateFormatter.formatMoment(yearEnd, 'W', locale), '53');
      expect(LocalDateFormatter.formatMoment(yearEnd, 'GGGG', locale), '2026');

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
        LocalDateFormatter.formatMoment(afterSpringForward, 'W', locale),
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
      expect(LocalDateFormatter.formatMoment(midYear, 'W', locale), '27');

      final isoRollover = tz.TZDateTime(newYork, 2025, 12, 29, 12);
      expect(LocalDateFormatter.formatMoment(isoRollover, 'W', locale), '1');
      expect(
        LocalDateFormatter.formatMoment(isoRollover, 'GGGG', locale),
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
