import 'package:discourse_native/src/foundation/clock_time.dart';
import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  final afternoon = DateTime(2026, 9, 25, 15, 45);

  group('clockTime', () {
    test('a 24-hour clock overrides a 12-hour locale', () {
      expect(
        clockTime(afternoon, use24HourClock: false, locale: 'en_US'),
        '3:45 PM',
      );
      expect(
        clockTime(afternoon, use24HourClock: true, locale: 'en_US'),
        '15:45',
      );
      expect(
        clockTime(DateTime(2026, 9, 25), use24HourClock: false),
        '12:00 AM',
      );
      expect(clockTime(DateTime(2026, 9, 25), use24HourClock: true), '00:00');
    });

    test('without the preference, the locale decides', () async {
      await initializeDateFormatting('de');
      expect(
        clockTime(afternoon, use24HourClock: false, locale: 'de'),
        '15:45',
      );
    });

    test('a locale without date symbols falls back rather than throwing', () {
      expect(
        clockTime(afternoon, use24HourClock: false, locale: 'xx_YY'),
        '3:45 PM',
      );
    });

    test('reads the wall time it is given, in whatever zone that is', () {
      final environment = TimezoneEnvironment.instance..ensureDatabase();
      final kathmandu = tz.TZDateTime.from(
        DateTime.utc(2026, 9, 25, 10),
        environment.location('Asia/Kathmandu')!,
      );
      expect(clockTime(kathmandu, use24HourClock: true), '15:45');
    });
  });

  testWidgets('clockTimeLabel follows the device 24-hour setting', (
    tester,
  ) async {
    final labels = <bool, String>{};
    for (final use24HourClock in [false, true]) {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(alwaysUse24HourFormat: use24HourClock),
          child: Builder(
            builder: (context) {
              labels[use24HourClock] = clockTimeLabel(context, afternoon);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    }
    expect(labels, {false: '3:45 PM', true: '15:45'});
  });
}
