import 'dart:io';

import 'package:discourse_native/src/data/retry_after.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseRetryAfter', () {
    final now = DateTime.utc(2026, 8, 24, 12);
    const maximum = Duration(hours: 1);

    for (final serverDate in [
      null,
      '',
      'not a date',
      '30',
      'Mon Aug',
      'Mon, 24 NotAMonth 2026 12:00:00 GMT',
      '2026-08-24T12:00:00Z',
      'Mon, 24 Aug 2026 12:00:00 GMT, Mon, 24 Aug 2026 12:00:01 GMT',
    ]) {
      test('uses the local clock for Date "$serverDate"', () {
        expect(
          parseRetryAfter(
            HttpDate.format(now.add(const Duration(seconds: 30))),
            maximum: maximum,
            now: now,
            serverDate: serverDate,
          ),
          const Duration(seconds: 30),
        );
      });
    }

    test('accepts surrounding whitespace in date headers', () {
      expect(
        parseRetryAfter(
          ' \tMon, 24 Aug 2026 12:00:30 GMT ',
          maximum: maximum,
          now: now.add(const Duration(minutes: 5)),
          serverDate: ' \tMon, 24 Aug 2026 12:00:00 GMT ',
        ),
        const Duration(seconds: 30),
      );
    });

    for (final seconds in [-30, 0]) {
      test('permits an immediate retry $seconds seconds after Date', () {
        expect(
          parseRetryAfter(
            HttpDate.format(now.add(Duration(seconds: seconds))),
            maximum: maximum,
            now: now.subtract(const Duration(minutes: 5)),
            serverDate: HttpDate.format(now),
          ),
          Duration.zero,
        );
      });
    }

    test('permits an elapsed HTTP date without a server Date', () {
      expect(
        parseRetryAfter(
          HttpDate.format(now.subtract(const Duration(seconds: 30))),
          maximum: maximum,
          now: now,
        ),
        Duration.zero,
      );
    });

    test('bounds a delay calculated from an untrusted server Date', () {
      expect(
        parseRetryAfter(
          HttpDate.format(now.add(const Duration(seconds: 30))),
          maximum: maximum,
          now: now,
          serverDate: HttpDate.format(DateTime.utc(1970)),
        ),
        maximum,
      );
    });

    for (final (header, expected) in [
      ('0', Duration.zero),
      (' 30 ', const Duration(seconds: 30)),
      ('7200', maximum),
    ]) {
      test('keeps numeric Retry-After "$header" independent of Date', () {
        for (final serverDate in [
          HttpDate.format(DateTime.utc(1970)),
          HttpDate.format(DateTime.utc(9999)),
          'Mon Aug',
        ]) {
          expect(
            parseRetryAfter(
              header,
              maximum: maximum,
              now: now,
              serverDate: serverDate,
            ),
            expected,
            reason: 'Date: $serverDate',
          );
        }
      });
    }

    for (final header in [null, '', '-1', 'not a date', 'Mon Aug']) {
      test('leaves Retry-After "$header" to the caller fallback', () {
        expect(
          parseRetryAfter(
            header,
            maximum: maximum,
            now: now,
            serverDate: HttpDate.format(now),
          ),
          isNull,
        );
      });
    }
  });
}
