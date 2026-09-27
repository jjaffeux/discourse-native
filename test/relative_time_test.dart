import 'dart:async';

import 'package:discourse_native/src/shell/relative_time.dart';
import 'package:flutter/widgets.dart';
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

  group('relativeTime', () {
    final when = DateTime.utc(2026, 1, 1, 12);
    String aged(Duration age) => relativeTime(when, now: when.add(age));

    test('changes unit exactly at each boundary', () {
      expect(aged(Duration.zero), 'now');
      expect(aged(const Duration(seconds: 59, milliseconds: 999)), 'now');
      expect(aged(const Duration(minutes: 1)), '1m');
      expect(aged(const Duration(minutes: 59, seconds: 59)), '59m');
      expect(aged(const Duration(hours: 1)), '1h');
      expect(aged(const Duration(hours: 23, minutes: 59)), '23h');
      expect(aged(const Duration(days: 1)), '1d');
      expect(aged(const Duration(days: 29, hours: 23)), '29d');
      expect(aged(const Duration(days: 30)), '1mo');
      expect(aged(const Duration(days: 364, hours: 23)), '12mo');
      expect(aged(const Duration(days: 365)), '1y');
      expect(aged(const Duration(days: 730)), '2y');
    });

    test('reads an instant ahead of the clock as now', () {
      expect(aged(const Duration(minutes: -5)), 'now');
    });
  });

  group('RelativeTimeText', () {
    testWidgets('advances at each label boundary while it stays open', (
      tester,
    ) async {
      final clock = _TickingClock(tester);
      await clock.run(() async {
        await clock.show(RelativeTimeText(clock.start, now: clock.now));
        expect(find.text('now'), findsOneWidget);

        for (final (step, label) in [
          (const Duration(seconds: 59), 'now'),
          (const Duration(seconds: 1), '1m'),
          (const Duration(minutes: 58), '59m'),
          (const Duration(minutes: 1), '1h'),
          (const Duration(hours: 22), '23h'),
          (const Duration(hours: 1), '1d'),
          (const Duration(days: 28), '29d'),
          (const Duration(days: 1), '1mo'),
        ]) {
          await tester.pump(step);
          expect(find.text(label), findsOneWidget, reason: label);
          expect(clock.activeTimers, hasLength(1));
        }
      });
    });

    testWidgets('rebuilds only itself, once per label change', (tester) async {
      final clock = _TickingClock(tester);
      await clock.run(() async {
        var parentBuilds = 0;
        var labelBuilds = 0;
        await clock.show(
          Builder(
            builder: (context) {
              parentBuilds++;
              return RelativeTimeBuilder(
                when: clock.start,
                now: clock.now,
                builder: (context, label) {
                  labelBuilds++;
                  return Text(label);
                },
              );
            },
          ),
        );
        expect((parentBuilds, labelBuilds), (1, 1));

        await tester.pump(const Duration(seconds: 30));
        expect((parentBuilds, labelBuilds), (1, 1));
        expect(tester.binding.hasScheduledFrame, isFalse);

        await tester.pump(const Duration(seconds: 30));
        expect(find.text('1m'), findsOneWidget);
        expect((parentBuilds, labelBuilds), (1, 2));
      });
    });

    testWidgets('cancels its timer when it leaves the tree', (tester) async {
      final clock = _TickingClock(tester);
      await clock.run(() async {
        await clock.show(RelativeTimeText(clock.start, now: clock.now));
        expect(clock.activeTimers, hasLength(1));

        await clock.show(const SizedBox.shrink());
        await clock.expectIdle();
      });
    });

    testWidgets('sleeps under a disabled TickerMode and catches up after', (
      tester,
    ) async {
      final clock = _TickingClock(tester);
      await clock.run(() async {
        final visible = ValueNotifier(false);
        addTearDown(visible.dispose);
        await clock.show(
          ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, enabled, child) =>
                TickerMode(enabled: enabled, child: child!),
            child: RelativeTimeText(clock.start, now: clock.now),
          ),
        );
        expect(find.text('now'), findsOneWidget);
        await clock.expectIdle();
        expect(find.text('now'), findsOneWidget);

        await tester.pump(const Duration(minutes: 5));
        visible.value = true;
        await tester.pump();
        expect(find.text('6m'), findsOneWidget);
        expect(clock.activeTimers, hasLength(1));
      });
    });

    testWidgets('never arms a timer shorter than a millisecond', (
      tester,
    ) async {
      final clock = _TickingClock(tester);
      await clock.run(() async {
        // A sub-millisecond remainder would round down to an immediate VM
        // timer that wakes before the label changes and re-arms with none.
        final when = clock.start.subtract(
          const Duration(seconds: 59, milliseconds: 999, microseconds: 500),
        );
        await clock.show(RelativeTimeText(when, now: clock.now));
        expect(find.text('now'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 1));
        expect(find.text('1m'), findsOneWidget);
        expect(
          clock.durations,
          everyElement(greaterThanOrEqualTo(const Duration(milliseconds: 1))),
        );
      });
    });

    testWidgets('holds an instant ahead of the clock at now until it ages', (
      tester,
    ) async {
      final clock = _TickingClock(tester);
      await clock.run(() async {
        final when = clock.start.add(const Duration(minutes: 2));
        await clock.show(RelativeTimeText(when, now: clock.now));

        await tester.pump(const Duration(minutes: 2, seconds: 59));
        expect(find.text('now'), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('1m'), findsOneWidget);
      });
    });

    testWidgets('turns twelve months into a year at 365 days', (tester) async {
      final clock = _TickingClock(tester);
      await clock.run(() async {
        final when = clock.start.subtract(const Duration(days: 364));
        await clock.show(RelativeTimeText(when, now: clock.now));
        expect(find.text('12mo'), findsOneWidget);

        await tester.pump(const Duration(days: 1));
        expect(find.text('1y'), findsOneWidget);
      });
    });
  });
}

class _TickingClock {
  _TickingClock(this.tester) : start = tester.binding.clock.now();

  final WidgetTester tester;
  final DateTime start;
  final List<Timer> _timers = [];
  final List<Duration> durations = [];

  Iterable<Timer> get activeTimers => _timers.where((timer) => timer.isActive);

  DateTime now() => tester.binding.clock.now();

  Future<void> run(Future<void> Function() body) => runZoned(
    () async {
      try {
        await body();
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        final timer = parent.createTimer(zone, duration, callback);
        _timers.add(timer);
        durations.add(duration);
        return timer;
      },
    ),
  );

  Future<void> show(Widget child) => tester.pumpWidget(
    Directionality(textDirection: TextDirection.ltr, child: child),
  );

  Future<void> expectIdle() async {
    // Bounded pumps expose a stray or zero-delay refresh that pumpAndSettle
    // would hang on.
    expect(activeTimers, isEmpty);
    for (final duration in [
      Duration.zero,
      const Duration(milliseconds: 1),
      const Duration(minutes: 1),
    ]) {
      await tester.pump(duration);
      expect(activeTimers, isEmpty);
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
  }
}
