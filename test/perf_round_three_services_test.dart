import 'package:flutter_test/flutter_test.dart';

import '../tool/perf_round_three_service_workloads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'destination bookmark loads retain account boundaries and first order',
    () async {
      for (final count in [1, 20, 500]) {
        final fixture = RoundThreeBookmarkFixture(count);
        await fixture.checkLoad();
        await fixture.checkLoad();
        final entries = fixture.store.entriesFor(
          RoundThreeBookmarkFixture.site,
          'reader',
        );
        expect(entries, hasLength(count));
        expect(() => entries.clear(), throwsUnsupportedError);
      }
    },
  );

  test('round three service workloads consume checked results', () async {
    final values = await measureRoundThreeServicePerformance();
    expect(values.values, everyElement(greaterThan(0)));
    // ignore: avoid_print
    print('ROUND_THREE_SERVICE_TIMES $values');
  });
}
