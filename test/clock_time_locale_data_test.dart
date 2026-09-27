import 'package:discourse_native/src/foundation/clock_time.dart';
import 'package:flutter_test/flutter_test.dart';

// Its own file, so nothing else in the isolate has installed intl's locale
// data before the first label is drawn.
void main() {
  test('the first label for a non-English reader uses their locale', () {
    expect(
      clockTime(
        DateTime(2026, 9, 25, 15, 45),
        use24HourClock: false,
        locale: 'fr_FR',
      ),
      '15:45',
    );
  });
}
