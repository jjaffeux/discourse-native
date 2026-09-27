import 'package:discourse_native/src/shell/relative_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('durationLabel', () {
    test('matches the web duration units', () {
      expect(durationLabel(100000), (short: '1d', long: '1 day'));
      expect(durationLabel(1000), (short: '17m', long: '17 mins'));
      expect(durationLabel(0), (short: '<1m', long: 'less than 1 min'));
      expect(durationLabel(2700), (short: '1h', long: 'about 1 hour'));
      expect(durationLabel(7776000), (short: '3mon', long: '3 months'));
    });
  });
}
