import 'dart:math' as math;

import 'package:discourse_native/src/ui/foundation/header_motion.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Harness extends StatefulWidget {
  const _Harness({super.key});
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness>
    with SingleTickerProviderStateMixin {
  late final motion = HeaderMotion(this);
  @override
  Widget build(BuildContext context) => const SizedBox();
  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }
}

Future<HeaderMotion> _mount(
  WidgetTester tester, [
  DHeaderTuning tuning = const DHeaderTuning(),
]) async {
  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(_Harness(key: key));
  final motion = key.currentState!.motion;
  motion.configure(tuning, disableAnimations: false);
  return motion;
}

void main() {
  testWidgets('distance, smoothing and reversal retain continuous progress', (
    tester,
  ) async {
    final motion = await _mount(
      tester,
      const DHeaderTuning(settle: DHeaderSettle.stay),
    );
    motion.scroll(60, span: 100);
    expect(motion.target, .6);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(motion.value, closeTo(.6 * (1 - math.exp(-1)), .0001));
    final partial = motion.value;
    motion.scroll(-24, span: 100);
    expect(motion.target, .6);
    motion.scroll(-36, span: 100);
    expect(motion.target, closeTo(.4, .0001));
    expect(
      motion.value,
      partial,
      reason: 'reversing does not restart a show animation',
    );
    await tester.pumpAndSettle();
    expect(motion.value, closeTo(.4, .0001));
    motion.scroll(40, span: 100);
    expect(motion.target, closeTo(.4, .0001));
    motion.scroll(10, span: 100);
    expect(motion.target, closeTo(.5, .0001));
  });

  testWidgets('endpoint hold ignores travel and restarts reversal slack', (
    tester,
  ) async {
    final motion = await _mount(tester, const DHeaderTuning(smoothing: 0));
    motion.scroll(100, span: 100);
    expect(motion.value, 1);
    motion.scroll(-200, span: 100);
    expect(motion.target, 1);
    await tester.pump(const Duration(milliseconds: 399));
    motion.scroll(-200, span: 100);
    expect(motion.target, 1);
    await tester.pump(const Duration(milliseconds: 2));
    motion.scroll(-40, span: 100);
    expect(motion.target, 1);
    motion.scroll(-25, span: 100);
    expect(motion.value, .75);
    motion.reveal(fresh: true);
    expect(
      motion.value,
      0,
      reason: 'top reveal overrides hold and reversal slack',
    );
  });

  for (final settle in DHeaderSettle.values) {
    testWidgets('$settle waits for the configured pause', (tester) async {
      final motion = await _mount(
        tester,
        DHeaderTuning(settle: settle, point: .7, smoothing: 0),
      );
      motion.scroll(60, span: 100);
      await tester.pump(const Duration(milliseconds: 120));
      expect(motion.value, .6);
      await tester.pump(const Duration(milliseconds: 1));
      expect(motion.value, switch (settle) {
        DHeaderSettle.direction => 1,
        DHeaderSettle.halfway => 0,
        DHeaderSettle.stay => .6,
      });
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, false);
    });
  }
  testWidgets('direction settling restores barely started movement', (
    tester,
  ) async {
    final motion = await _mount(
      tester,
      const DHeaderTuning(smoothing: 0, hold: 0),
    );
    motion.scroll(8, span: 100);
    await tester.pumpAndSettle();
    expect(motion.value, 0);
    motion.scroll(100, span: 100);
    motion.scroll(-48, span: 100);
    await tester.pumpAndSettle();
    expect(motion.value, 1);
  });
  for (final hz in [60, 120]) {
    testWidgets('smoothing follows elapsed time at $hz Hz', (tester) async {
      final motion = await _mount(
        tester,
        const DHeaderTuning(settle: DHeaderSettle.stay),
      );
      motion.scroll(50, span: 100);
      await tester.pump();
      final frame = Duration(microseconds: (1000000 / hz).round());
      for (var i = 0; i < hz ~/ 10; i++) {
        await tester.pump(frame);
      }
      expect(motion.value, closeTo(.5 * (1 - math.exp(-2.5)), .001));
    });
  }
  testWidgets('reduced motion and reset leave no stale frame work', (
    tester,
  ) async {
    final motion = await _mount(tester);
    motion.scroll(50, span: 100);
    await tester.pump(const Duration(milliseconds: 16));
    motion.configure(const DHeaderTuning(), disableAnimations: true);
    expect(motion.value, .5);
    motion.reset();
    expect(motion.value, 0);
    motion.scroll(20, span: 100);
    expect(motion.value, .2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(tester.hasRunningAnimations, false);
  });
}
