import 'package:discourse_native/src/shell/decorative_cadence.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resumed decorations notify at a bounded cadence', (
    tester,
  ) async {
    await _withClock(tester, (clock) async {
      var notifications = 0;
      clock.addListener(() => notifications++);
      clock.setActive(true);
      await tester.pump();
      notifications = 0;

      await _pumpSecond(tester);

      expect(notifications, inInclusiveRange(29, 31));
      expect(clock.sampleElapsed().inMicroseconds, closeTo(1000000, 100));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  testWidgets('inactive visible decorations slow without losing phase', (
    tester,
  ) async {
    await _withClock(tester, (clock) async {
      var notifications = 0;
      clock.addListener(() => notifications++);
      clock.setActive(true);
      await tester.pump();
      await _pumpSecond(tester);
      notifications = 0;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await _pumpSecond(tester);

      expect(notifications, inInclusiveRange(9, 11));
      expect(clock.sampleElapsed().inMicroseconds, closeTo(2000000, 100));
      notifications = 0;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpSecond(tester);
      expect(notifications, inInclusiveRange(29, 31));
      expect(clock.sampleElapsed().inMicroseconds, closeTo(3000000, 100));
    });
  });

  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets('$state cancels pending work and excludes suspended time', (
      tester,
    ) async {
      await _withClock(tester, (clock) async {
        var notifications = 0;
        clock.addListener(() => notifications++);
        clock.setActive(true);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(clock.sampleElapsed(), const Duration(seconds: 1));
        clock.setActive(false);
        clock.setActive(true);

        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump(const Duration(seconds: 10));
        final frozenNotifications = notifications;
        await tester.pump(const Duration(seconds: 10));
        expect(notifications, frozenNotifications);
        expect(clock.sampleElapsed(), const Duration(seconds: 1));
        expect(tester.binding.hasScheduledFrame, isFalse);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(clock.sampleElapsed(), const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(clock.sampleElapsed(), const Duration(seconds: 2));
      });
    });
  }

  testWidgets(
    'disabling before a frame cancels it and preserves elapsed time',
    (tester) async {
      await _withClock(tester, (clock) async {
        var notifications = 0;
        clock.addListener(() => notifications++);
        clock.setActive(true);
        clock.setActive(false);
        await tester.pump(const Duration(seconds: 5));
        expect(notifications, 0);
        expect(clock.sampleElapsed(), Duration.zero);

        clock.setActive(true);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        clock.setActive(false);
        final frozenNotifications = notifications;
        await tester.pump(const Duration(seconds: 10));
        expect(notifications, frozenNotifications);
        expect(clock.sampleElapsed(), const Duration(seconds: 2));

        clock.setActive(true);
        clock.setActive(false);
        clock.setActive(true);
        await tester.pump();
        expect(notifications, frozenNotifications + 1);
        expect(clock.sampleElapsed(), const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 1));
        expect(clock.sampleElapsed(), const Duration(seconds: 3));
      });
    },
  );

  testWidgets(
    'a delayed frame samples current time once without replaying ticks',
    (tester) async {
      await _withClock(tester, (clock) async {
        var notifications = 0;
        clock.addListener(() => notifications++);
        clock.setActive(true);
        await tester.pump();
        notifications = 0;

        await tester.pump(const Duration(seconds: 2));

        expect(notifications, 1);
        expect(clock.sampleElapsed(), const Duration(seconds: 2));
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pump();
        expect(notifications, 1);
      });
    },
  );

  testWidgets('elapsed shader time remains unbounded beyond one hour', (
    tester,
  ) async {
    await _withClock(tester, (clock) async {
      clock.setActive(true);
      await tester.pump();
      await tester.pump(const Duration(hours: 1, seconds: 1));

      expect(clock.sampleElapsed(), const Duration(hours: 1, seconds: 1));
    });
  });

  testWidgets('disposing a clock cancels a pending repaint and later wakeups', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final clock = DecorativeCadence();
    var notifications = 0;
    clock.addListener(() => notifications++);
    clock.setActive(true);
    clock.dispose();

    await tester.pump(const Duration(seconds: 2));

    expect(notifications, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(notifications, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('independent UI animation keeps its own frame cadence', (
    tester,
  ) async {
    await _withClock(tester, (clock) async {
      clock.setActive(true);
      var decorativeFrames = 0;
      var uiFrames = 0;
      clock.addListener(() => decorativeFrames++);
      final ticker = Ticker((_) {
        uiFrames++;
        clock.sampleElapsed();
      });
      try {
        ticker.start();
        await tester.pump();
        decorativeFrames = 0;
        uiFrames = 0;

        await _pumpSecond(tester);

        expect(uiFrames, 60);
        expect(decorativeFrames, inInclusiveRange(29, 31));
        expect(clock.sampleElapsed().inMicroseconds, closeTo(1000000, 100));
      } finally {
        ticker.dispose();
      }
    });
  });
}

Future<void> _withClock(
  WidgetTester tester,
  Future<void> Function(DecorativeCadence clock) body,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final clock = DecorativeCadence();
  try {
    await body(clock);
  } finally {
    clock.dispose();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

Future<void> _pumpSecond(WidgetTester tester) async {
  for (var frame = 0; frame < 60; frame++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}
