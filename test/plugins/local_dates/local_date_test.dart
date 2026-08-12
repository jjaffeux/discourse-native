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
  });
}
