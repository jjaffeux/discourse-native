import 'package:discourse_native/src/shell/time_gap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('counts complete 24-hour periods like Discourse web', () {
    final start = DateTime.utc(2026, 1, 1, 12);

    expect(
      timeGapDaysBetween(start, start.add(const Duration(days: 8, hours: 23))),
      8,
    );
    expect(timeGapDaysBetween(null, start), isNull);
    expect(timeGapDaysBetween(start, null), isNull);
  });

  test('uses the web unit boundaries and rounding', () {
    expect(timeGapLabel(1), '1 day later');
    expect(timeGapLabel(29), '29 days later');
    expect(timeGapLabel(30), '1 month later');
    expect(timeGapLabel(90), '3 months later');
    expect(timeGapLabel(364), '12 months later');
    expect(timeGapLabel(365), '1 year later');
    expect(timeGapLabel(730), '2 years later');
  });
}
