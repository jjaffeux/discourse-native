import 'package:discourse_native/src/foundation/short_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shortNumber', () {
    test('abbreviates at the web formatter\'s boundaries', () {
      const expected = [
        (0, '0'),
        (999, '999'),
        (1000, '1k'),
        (1499, '1.5k'),
        (3333, '3.3k'),
        (10500, '10.5k'),
        (99999, '100k'),
        (100000, '100k'),
        (999500, '999k'),
        (999999, '999k'),
        (1000000, '1M'),
        (1500000, '1.5M'),
        (2499999, '2.5M'),
      ];
      for (final (count, label) in expected) {
        expect(shortNumber(count), label, reason: '$count');
      }
    });

    test('floors hundreds of thousands rather than rounding into 1000k', () {
      for (var count = 999000; count <= 999999; count += 37) {
        expect(shortNumber(count), '999k', reason: '$count');
      }
    });

    test('rounds a fraction to a whole count first', () {
      const expected = [
        (18.2, '18'),
        (18.6, '19'),
        (12.5, '13'),
        (3.5, '4'),
        (1.0, '1'),
        (999.5, '1k'),
        (1000.0, '1k'),
        (10499.6, '10.5k'),
        (999999.4, '999k'),
        (999999.5, '1M'),
        (-0.2, '0'),
      ];
      for (final (count, label) in expected) {
        expect(shortNumber(count), label, reason: '$count');
      }
    });

    test('leaves a negative count whole, as the web does', () {
      expect(shortNumber(-1250), '-1250');
      expect(shortNumber(-1250000.0), '-1250000');
    });

    test('reads not-a-number as nothing', () {
      expect(shortNumber(double.nan), '0');
    });

    test('carries a magnitude beyond the integer range through', () {
      expect(shortNumber(9223372036854775807), '9223372036854.8M');
      expect(shortNumber(9.3e18), '9300000000000M');
      expect(shortNumber(1e300), '1e+294M');
    });
  });
}
