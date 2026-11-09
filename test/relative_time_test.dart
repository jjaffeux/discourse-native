import 'dart:async';
import 'dart:math';

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

    testWidgets('labels due in the same 30 seconds share one frame', (
      tester,
    ) async {
      final clock = _TickingClock(tester);
      await clock.run(() async {
        const labels = 20;
        final starts = <DateTime>[];
        final shown = ValueNotifier(0);
        addTearDown(shown.dispose);
        await clock.show(
          ValueListenableBuilder<int>(
            valueListenable: shown,
            builder: (context, count, _) => Column(
              children: [
                for (final when in starts.take(count))
                  RelativeTimeText(when, now: clock.now),
              ],
            ),
          ),
        );
        // Rows arrive over time, so neither their ages nor the moments their
        // timers were armed line up.
        for (var index = 0; index < labels; index++) {
          starts.add(clock.now());
          shown.value++;
          await tester.pump();
          await tester.binding.delayed(const Duration(seconds: 3));
        }
        await tester.pump();

        const display = Duration(milliseconds: 16);
        final displayFrames =
            const Duration(minutes: 10).inMilliseconds ~/
            display.inMilliseconds;
        var frames = 0;
        var mostActiveTimers = clock.activeTimers.length;
        for (var frame = 0; frame < displayFrames; frame++) {
          await tester.binding.delayed(display);
          if (!tester.binding.hasScheduledFrame) continue;
          frames++;
          await tester.pump();
          mostActiveTimers = max(mostActiveTimers, clock.activeTimers.length);
        }

        // ignore: avoid_print
        print('PERF_PROOF relative-time frames=$frames');
        // ignore: avoid_print
        print('PERF_PROOF relative-time active_timers=$mostActiveTimers');
        expect(find.text('now'), findsNothing);
        expect(frames, lessThanOrEqualTo(20));
        expect(mostActiveTimers, labels);
      });
    });

    testWidgets('reaches each new value within 30 seconds of its boundary', (
      tester,
    ) async {
      final clock = _TickingClock(tester);
      await clock.run(() async {
        // A change just past a 30-second mark waits the longest for its frame.
        final when = clock.start.subtract(
          const Duration(seconds: 59, milliseconds: 999),
        );
        await clock.show(RelativeTimeText(when, now: clock.now));
        expect(find.text('now'), findsOneWidget);

        for (final minutes in [1, 2, 3]) {
          final bound = when.add(Duration(minutes: minutes, seconds: 30));
          await tester.pump(bound.difference(clock.now()));
          expect(find.text('${minutes}m'), findsOneWidget, reason: '$minutes');
        }
      });
    });

    testWidgets('a label past an hour still wakes once per hour', (
      tester,
    ) async {
      final clock = _TickingClock(tester);
      await clock.run(() async {
        final when = clock.start.subtract(
          const Duration(hours: 2, seconds: 17),
        );
        await clock.show(RelativeTimeText(when, now: clock.now));
        expect(find.text('2h'), findsOneWidget);

        for (var minute = 0; minute < 180; minute++) {
          await tester.pump(const Duration(minutes: 1));
        }

        expect(find.text('5h'), findsOneWidget);
        // The first arm, then one for each of the three hours that changed it.
        expect(clock.durations, hasLength(4));
      });
    });

    testWidgets('keeps an off-stage label asleep beside one that advances', (
      tester,
    ) async {
      final clock = _TickingClock(tester);
      await clock.run(() async {
        await clock.show(
          Column(
            children: [
              RelativeTimeText(clock.start, now: clock.now),
              TickerMode(
                enabled: false,
                child: RelativeTimeText(
                  clock.start.subtract(const Duration(minutes: 10, seconds: 7)),
                  now: clock.now,
                ),
              ),
            ],
          ),
        );

        for (final minutes in [1, 2, 3]) {
          await tester.pump(const Duration(minutes: 1));
          expect(find.text('${minutes}m'), findsOneWidget);
          expect(find.text('10m'), findsOneWidget);
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

    testWidgets('a label left behind while hidden is right on its return', (
      tester,
    ) async {
      final clock = _TickingClock(tester);
      await clock.run(() async {
        final visible = ValueNotifier(true);
        addTearDown(visible.dispose);
        await clock.show(
          ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, enabled, child) =>
                TickerMode(enabled: enabled, child: child!),
            // A topic row's nesting: its own TickerMode, then a LayoutBuilder.
            child: TickerMode(
              enabled: true,
              child: LayoutBuilder(
                builder: (context, _) =>
                    RelativeTimeText(clock.start, now: clock.now),
              ),
            ),
          ),
        );
        expect(find.text('now'), findsOneWidget);
        expect(clock.activeTimers, hasLength(1));

        visible.value = false;
        await tester.pump();
        await clock.expectIdle();
        await tester.pump(const Duration(minutes: 5));
        expect(find.text('now'), findsOneWidget);

        visible.value = true;
        await tester.pump();
        expect(find.text('6m'), findsOneWidget);
        expect(clock.activeTimers, hasLength(1));

        await tester.pump(const Duration(minutes: 1));
        expect(find.text('7m'), findsOneWidget);
      });
    });

    testWidgets('a label still right is not rebuilt by hiding and showing', (
      tester,
    ) async {
      final clock = _TickingClock(tester);
      await clock.run(() async {
        final visible = ValueNotifier(true);
        addTearDown(visible.dispose);
        var builds = 0;
        await clock.show(
          ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, enabled, child) =>
                TickerMode(enabled: enabled, child: child!),
            child: RelativeTimeBuilder(
              when: clock.start,
              now: clock.now,
              builder: (context, label) {
                builds++;
                return Text(label);
              },
            ),
          ),
        );
        expect(builds, 1);

        visible.value = false;
        await tester.pump();
        await tester.pump(const Duration(seconds: 10));
        expect(clock.activeTimers, isEmpty);

        visible.value = true;
        await tester.pump();
        expect(builds, 1);
        expect(clock.activeTimers, hasLength(1));

        await tester.pump(const Duration(seconds: 50));
        expect(find.text('1m'), findsOneWidget);
        expect(builds, 2);
      });
    });

    testWidgets('obeys the TickerMode of wherever it is moved to', (
      tester,
    ) async {
      final clock = _TickingClock(tester);
      await clock.run(() async {
        final key = GlobalKey();
        Widget placed({required bool hidden}) {
          final label = RelativeTimeText(clock.start, key: key, now: clock.now);
          return Column(
            children: [
              TickerMode(
                enabled: false,
                child: hidden ? label : const SizedBox.shrink(),
              ),
              TickerMode(
                enabled: true,
                child: hidden ? const SizedBox.shrink() : label,
              ),
            ],
          );
        }

        await clock.show(placed(hidden: false));
        expect(clock.activeTimers, hasLength(1));

        await clock.show(placed(hidden: true));
        await clock.expectIdle();
        await tester.pump(const Duration(minutes: 4));
        expect(find.text('now'), findsOneWidget);

        await clock.show(placed(hidden: false));
        expect(find.text('5m'), findsOneWidget);
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
        final when = clock.start.subtract(const Duration(minutes: 1));
        DateTime justBeforeMark() =>
            clock.now().subtract(const Duration(microseconds: 500));
        await clock.show(RelativeTimeText(when, now: justBeforeMark));
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
