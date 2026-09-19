import 'dart:async';

import 'package:discourse_cooking/src/wall_clock_deadline.dart';
import 'package:test/test.dart';

void main() {
  test(
    'deadline expires without advancing or creating caller-zone timers',
    () async {
      var callerTimers = 0;
      final never = Completer<void>();
      await runZoned(
        () async {
          await expectLater(
            withWallClockDeadline(
              never.future,
              const Duration(milliseconds: 10),
            ),
            throwsA(isA<TimeoutException>()),
          );
          // A late error must stay observed after the timeout result is delivered.
          never.completeError(StateError('late transport failure'));
          await Future<void>.value();
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            callerTimers++;
            throw StateError('Native deadline used caller timer');
          },
        ),
      );
      expect(callerTimers, 0);
    },
  );

  test('completion and error delivery preserve caller zone', () async {
    const key = #deadlineZone;
    await runZoned(() async {
      final success = Completer<int>();
      late Timer successTimer;
      final result = withWallClockDeadline(
        success.future,
        const Duration(seconds: 1),
        createTimer: (duration, callback) =>
            successTimer = wallClockTimer(duration, callback),
      );
      success.complete(42);
      expect(await result, 42);
      expect(successTimer.isActive, isFalse);
      expect(Zone.current[key], 'caller');
      final failure = Completer<void>();
      late Timer failureTimer;
      final failed = withWallClockDeadline(
        failure.future,
        const Duration(seconds: 1),
        createTimer: (duration, callback) =>
            failureTimer = wallClockTimer(duration, callback),
      );
      failure.completeError(StateError('transport'));
      await expectLater(failed, throwsStateError);
      expect(failureTimer.isActive, isFalse);
      expect(Zone.current[key], 'caller');
    }, zoneValues: {key: 'caller'});
  });

  test('wall-clock watchdog remains cancellable', () async {
    var fired = false;
    final timer = wallClockTimer(
      const Duration(milliseconds: 10),
      () => fired = true,
    );
    timer.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(fired, isFalse);
  });
}
