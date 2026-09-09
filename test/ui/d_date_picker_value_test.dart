import 'package:discourse_native/src/ui/components/d_date_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DIntlDateTextCodec', () {
    const codec = DIntlDateTextCodec();

    test('matches the reference display and parses supported strict forms', () {
      expect(
        codec.format(DateTime(2025, 6), const Locale('en', 'US')),
        'June 01, 2025',
      );
      expect(
        codec.tryParse('June 01, 2025', const Locale('en', 'US')),
        DateTime(2025, 6),
      );
      expect(
        codec.tryParse('2026-09-09', const Locale('fr', 'FR')),
        DateTime(2026, 9, 9),
      );
    });

    test('rejects empty and rollover input', () {
      expect(codec.tryParse('', const Locale('en', 'US')), isNull);
      expect(
        codec.tryParse('February 29, 2025', const Locale('en', 'US')),
        isNull,
      );
      expect(codec.tryParse('2026-2-3', const Locale('en', 'US')), isNull);
      expect(
        codec.tryParse('2026-02-03', const Locale('en', 'US')),
        DateTime(2026, 2, 3),
      );
    });

    test('uses the host locale for formatted and short input', () {
      const locale = Locale('fr', 'FR');
      expect(codec.format(DateTime(2026, 9, 11), locale), '11 septembre 2026');
      expect(codec.tryParse('11/09/2026', locale), DateTime(2026, 9, 11));
    });
  });

  group('DEnglishNaturalDateParser', () {
    const parser = DEnglishNaturalDateParser();
    const locale = Locale('en', 'US');
    final reference = DateTime(2026, 9, 9, 23, 30);

    test('parses deterministic relative phrases as civil days', () {
      expect(
        parser.tryParse('Tomorrow', reference: reference, locale: locale),
        DateTime(2026, 9, 10),
      );
      expect(
        parser.tryParse('In 2 days', reference: reference, locale: locale),
        DateTime(2026, 9, 11),
      );
      expect(
        parser.tryParse('next week', reference: reference, locale: locale),
        DateTime(2026, 9, 16),
      );
    });

    test('clamps calendar-relative month and year phrases', () {
      expect(
        parser.tryParse(
          'next month',
          reference: DateTime(2026, 1, 31),
          locale: locale,
        ),
        DateTime(2026, 2, 28),
      );
      expect(
        parser.tryParse(
          'next year',
          reference: DateTime(2024, 2, 29),
          locale: locale,
        ),
        DateTime(2025, 2, 28),
      );
    });

    test('distinguishes this weekday from the next occurrence', () {
      expect(
        parser.tryParse('this Wednesday', reference: reference, locale: locale),
        DateTime(2026, 9, 9),
      );
      expect(
        parser.tryParse('next Wednesday', reference: reference, locale: locale),
        DateTime(2026, 9, 16),
      );
    });

    test('falls back to strict locale dates and rejects unknown phrases', () {
      expect(
        parser.tryParse(
          'September 30, 2026',
          reference: reference,
          locale: locale,
        ),
        DateTime(2026, 9, 30),
      );
      expect(
        parser.tryParse('sometime soon', reference: reference, locale: locale),
        isNull,
      );
      expect(
        parser.tryParse(
          'demain',
          reference: reference,
          locale: const Locale('fr', 'FR'),
        ),
        isNull,
      );
      expect(
        parser.tryParse('in 10000 years', reference: reference, locale: locale),
        isNull,
      );
    });
  });

  test('natural picker configuration requires an explicit clock', () {
    expect(
      () => DDatePickerInput(
        naturalDateParser: const DEnglishNaturalDateParser(),
      ),
      throwsAssertionError,
    );
  });

  group('DTimeValue', () {
    test('parses seconds exactly and rejects normalized or partial times', () {
      expect(
        DTimeValue.tryParse('10:30:00'),
        const DTimeValue(hour: 10, minute: 30),
      );
      expect(
        DTimeValue.tryParse('23:59:58'),
        const DTimeValue(hour: 23, minute: 59, second: 58),
      );
      expect(DTimeValue.tryParse('24:00:00'), isNull);
      expect(DTimeValue.tryParse('9:30'), isNull);
    });

    test('formats for the documented seconds step without owning timezone', () {
      const value = DTimeValue(hour: 3, minute: 4, second: 5);
      expect(value.format(), '03:04:05');
      expect(value.format(includeSeconds: false), '03:04');
      expect(value.timeOfDay, const TimeOfDay(hour: 3, minute: 4));
    });
  });
}
