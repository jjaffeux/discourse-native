import 'dart:async';

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

  group('timezones', () {
    test('preserves Discourse aliases and historical IANA names', () {
      expect(environment.canonicalTimezone('UTC'), 'Etc/UTC');
      expect(environment.canonicalTimezone('IST'), 'Asia/Kolkata');
      expect(environment.canonicalTimezone('KST'), 'Asia/Seoul');
      expect(environment.canonicalTimezone('JST'), 'Asia/Tokyo');
      expect(environment.canonicalTimezone('US/Eastern'), 'US/Eastern');
    });

    test('uses device, account, then UTC reader-zone precedence', () {
      environment.setDeviceTimezone(null);
      expect(environment.readerTimezone('Europe/Paris'), 'Europe/Paris');
      expect(environment.readerTimezone('not/a-zone'), 'Etc/UTC');
      environment.setDeviceTimezone('Asia/Tokyo');
      expect(environment.readerTimezone('Europe/Paris'), 'Asia/Tokyo');
    });

    test('a stale timezone detection cannot replace a newer result', () async {
      final first = Completer<String?>();
      final second = Completer<String?>();
      var reads = 0;
      final isolated = LocalDateEnvironment.forTesting(
        detectDeviceTimezone: () => reads++ == 0 ? first.future : second.future,
      );

      final olderRefresh = isolated.refreshDeviceTimezone();
      final newerRefresh = isolated.refreshDeviceTimezone();
      second.complete('Asia/Tokyo');
      await newerRefresh;
      expect(isolated.deviceTimezone, 'Asia/Tokyo');

      first.complete('Europe/Paris');
      await olderRefresh;

      expect(isolated.deviceTimezone, 'Asia/Tokyo');
      isolated.dispose();
    });
  });

  group('resolution', () {
    const formatter = LocalDateFormatter();

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

      // The digits in front of the unit are author-written and unbounded. One
      // wider than an int used to throw out of the middle of a post's markup;
      // one merely enormous wrapped its own Duration and advanced the date to
      // a moment that never existed. Both stay on the cooked wall time.
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

      // The bound is on the step, not on recurrence: an ordinary one advances.
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

      // Late evening in New York is already the next day in UTC and most
      // device zones; the rendered values must track the displayed date.
      final yearEnd = tz.TZDateTime(newYork, 2026, 12, 31, 23);
      expect(LocalDateFormatter.formatMoment(yearEnd, 'DDD', locale), '365');
      expect(LocalDateFormatter.formatMoment(yearEnd, 'w', locale), '53');
      expect(LocalDateFormatter.formatMoment(yearEnd, 'gggg', locale), '2026');

      // First wall-clock morning after Sydney's 2026-10-04 spring forward.
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

      // A summer date whose ISO-week span crosses the displayed zone's
      // northern-hemisphere DST change.
      final midYear = tz.TZDateTime(
        tz.getLocation('Europe/Paris'),
        2026,
        7,
        1,
        12,
      );
      expect(LocalDateFormatter.formatMoment(midYear, 'DDD', locale), '182');
      expect(LocalDateFormatter.formatMoment(midYear, 'w', locale), '27');

      // The last Monday of 2025 belongs to ISO week 1 of 2026.
      final isoRollover = tz.TZDateTime(newYork, 2025, 12, 29, 12);
      expect(LocalDateFormatter.formatMoment(isoRollover, 'w', locale), '1');
      expect(
        LocalDateFormatter.formatMoment(isoRollover, 'gggg', locale),
        '2026',
      );
    });
  });
}
