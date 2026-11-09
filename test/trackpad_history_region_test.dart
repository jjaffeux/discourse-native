import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/src/shell/trackpad_history_region.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _inner = Key('inner-scroller');
const _center = Offset(400, 300);

void main() {
  group('a sideways run', () {
    testWidgets('is one step only once it reaches the distance', (
      tester,
    ) async {
      final steps = await _pumpRegion(tester, const SizedBox.expand());
      final run = await _startRun(tester);

      await _pan(tester, run, const [Offset(40, 0), Offset(79.5, 0)]);
      expect(steps, isEmpty);

      await _pan(tester, run, const [Offset(80, 0)]);
      expect(steps, ['back']);
    });

    testWidgets('of any length is one step, and the next run is another', (
      tester,
    ) async {
      final steps = await _pumpRegion(tester, const SizedBox.expand());
      final first = await _startRun(tester);

      await _pan(tester, first, const [
        Offset(100, 0),
        Offset(400, 0),
        Offset(800, 0),
        Offset(0, 0),
        Offset(-800, 0),
      ]);
      expect(steps, ['back']);
      await first.panZoomEnd();

      final second = await _startRun(tester);
      await _pan(tester, second, const [Offset(100, 0)]);
      expect(steps, ['back', 'back']);
    });

    testWidgets('of fingers left is Forward', (tester) async {
      final steps = await _pumpRegion(tester, const SizedBox.expand());
      final run = await _startRun(tester);

      await _pan(tester, run, const [Offset(-79, 0), Offset(-81, 0)]);

      expect(steps, ['forward']);
    });

    testWidgets('that returns on itself before the distance is no step', (
      tester,
    ) async {
      final steps = await _pumpRegion(tester, const SizedBox.expand());
      final run = await _startRun(tester);

      await _pan(tester, run, const [Offset(70, 0), Offset(0, 0)]);
      await run.panZoomEnd();

      expect(steps, isEmpty);
    });

    testWidgets('does not count travel from a run that already ended', (
      tester,
    ) async {
      final steps = await _pumpRegion(tester, const SizedBox.expand());
      final first = await _startRun(tester);
      await _pan(tester, first, const [Offset(70, 0)]);
      await first.panZoomEnd();

      final second = await _startRun(tester);
      await _pan(tester, second, const [Offset(70, 0)]);

      expect(steps, isEmpty);
    });
  });

  group('a mostly vertical scroll', () {
    testWidgets('never steps however far it drifts sideways', (tester) async {
      final steps = await _pumpRegion(tester, const SizedBox.expand());
      final run = await _startRun(tester);

      await _pan(tester, run, const [
        Offset(50, 400),
        Offset(100, 800),
        Offset(200, 1600),
      ]);

      expect(steps, isEmpty);
    });

    testWidgets('never steps from stray updates that are sideways alone', (
      tester,
    ) async {
      final steps = await _pumpRegion(tester, const SizedBox.expand());
      final run = await _startRun(tester);

      var x = 0.0;
      var y = 0.0;
      for (var i = 0; i < 40; i++) {
        y += 60;
        await run.panZoomUpdate(_center, pan: Offset(x, y));
        x += 4;
        await run.panZoomUpdate(_center, pan: Offset(x, y));
      }

      expect(x, greaterThan(TrackpadHistoryRegion.distance));
      expect(steps, isEmpty);
    });

    testWidgets('adds no travel from updates more vertical than sideways', (
      tester,
    ) async {
      final steps = await _pumpRegion(tester, const SizedBox.expand());
      final run = await _startRun(tester);

      await _pan(tester, run, const [
        Offset(30, 0),
        Offset(70, 50),
        Offset(100, 50),
        Offset(140, 100),
      ]);

      expect(steps, isEmpty);
    });

    testWidgets('leaves the page free to scroll under the region', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final steps = await _pumpRegion(
        tester,
        ListView(
          controller: controller,
          children: const [SizedBox(height: 4000)],
        ),
      );
      final run = await _startRun(tester);

      await _pan(tester, run, const [Offset(0, -100), Offset(0, -300)]);
      await tester.pump();

      expect(controller.offset, greaterThan(0));
      expect(steps, isEmpty);
    });
  });

  group('an inner horizontal scroller', () {
    testWidgets('keeps a swipe while it can still go that way', (tester) async {
      final controller = ScrollController(initialScrollOffset: 1000);
      addTearDown(controller.dispose);
      final steps = await _pumpRegion(tester, _carousel(controller));
      final run = await _startRun(tester);

      await _pan(tester, run, const [
        Offset(30, 0),
        Offset(200, 0),
        Offset(400, 0),
      ]);
      await tester.pump();

      expect(controller.offset, lessThan(1000));
      expect(steps, isEmpty);
    });

    testWidgets('keeps a swipe of one large update', (tester) async {
      final controller = ScrollController(initialScrollOffset: 1000);
      addTearDown(controller.dispose);
      final steps = await _pumpRegion(tester, _carousel(controller));
      final run = await _startRun(tester);

      await _pan(tester, run, const [Offset(300, 0)]);

      expect(steps, isEmpty);
    });

    testWidgets('lets a swipe through in the direction it has no room', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final steps = await _pumpRegion(tester, _carousel(controller));
      final run = await _startRun(tester);

      await _pan(tester, run, const [Offset(40, 0), Offset(100, 0)]);

      expect(steps, ['back']);
    });

    testWidgets('steps only after the distance past its own limit', (
      tester,
    ) async {
      final controller = ScrollController(initialScrollOffset: 50);
      addTearDown(controller.dispose);
      final steps = await _pumpRegion(tester, _carousel(controller));
      final run = await _startRun(tester);

      await _pan(tester, run, const [Offset(30, 0), Offset(60, 0)]);
      expect(steps, isEmpty);

      controller.jumpTo(0);
      await _pan(tester, run, const [Offset(120, 0)]);
      expect(steps, isEmpty);
      await _pan(tester, run, const [Offset(140, 0)]);
      expect(steps, ['back']);
    });

    testWidgets('that fits its content does not keep a swipe', (tester) async {
      final steps = await _pumpRegion(
        tester,
        SingleChildScrollView(
          key: _inner,
          scrollDirection: Axis.horizontal,
          child: Container(width: 100, height: 600, color: Colors.black),
        ),
      );
      final run = await _startRun(tester);

      await _pan(tester, run, const [Offset(100, 0)]);

      expect(steps, ['back']);
    });

    testWidgets('that cannot be dragged does not keep a swipe', (tester) async {
      final steps = await _pumpRegion(
        tester,
        SingleChildScrollView(
          key: _inner,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Container(width: 4000, height: 600, color: Colors.black),
        ),
      );
      final run = await _startRun(tester);

      await _pan(tester, run, const [Offset(-100, 0)]);

      expect(steps, ['forward']);
    });

    testWidgets('in a code block shape keeps a swipe', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final steps = await _pumpRegion(
        tester,
        SingleChildScrollView(
          key: _inner,
          controller: controller,
          scrollDirection: Axis.horizontal,
          child: Container(width: 4000, height: 600, color: Colors.black),
        ),
      );
      final run = await _startRun(tester);

      await _pan(tester, run, const [Offset(-40, 0), Offset(-300, 0)]);
      await tester.pump();

      expect(controller.offset, greaterThan(0));
      expect(steps, isEmpty);
    });

    testWidgets('laid out right to left reads room from its own direction', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final steps = await _pumpRegion(
        tester,
        ListView(
          key: _inner,
          controller: controller,
          reverse: true,
          scrollDirection: Axis.horizontal,
          children: const [SizedBox(width: 4000, height: 600)],
        ),
      );

      final toward = await _startRun(tester);
      await _pan(tester, toward, const [Offset(100, 0), Offset(200, 0)]);
      await toward.panZoomEnd();
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect(steps, isEmpty);

      controller.jumpTo(0);
      final away = await _startRun(tester);
      await _pan(tester, away, const [Offset(-100, 0)]);
      expect(steps, ['forward']);
    });

    testWidgets('keeps nothing from a page it is hidden behind', (
      tester,
    ) async {
      final controller = ScrollController(initialScrollOffset: 1000);
      addTearDown(controller.dispose);
      final steps = await _pumpRegion(
        tester,
        IndexedStack(
          index: 1,
          children: [_carousel(controller), const SizedBox.expand()],
        ),
      );
      final run = await _startRun(tester);

      await _pan(tester, run, const [Offset(100, 0)]);

      expect(steps, ['back']);
    });

    testWidgets('elsewhere in the page does not keep a swipe', (tester) async {
      final controller = ScrollController(initialScrollOffset: 1000);
      addTearDown(controller.dispose);
      final steps = await _pumpRegion(
        tester,
        Column(
          children: [
            SizedBox(height: 100, child: _carousel(controller)),
            const Expanded(child: SizedBox.expand()),
          ],
        ),
      );
      final run = await _startRun(tester);

      await _pan(tester, run, const [Offset(100, 0)]);

      expect(steps, ['back']);
    });
  });

  testWidgets('a run outlives a page that disappears beneath it', (
    tester,
  ) async {
    final page = ValueNotifier(true);
    addTearDown(page.dispose);
    final steps = <String>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder(
          valueListenable: page,
          builder: (context, visible, _) => visible
              ? TrackpadHistoryRegion(
                  onBack: () => steps.add('back'),
                  onForward: () => steps.add('forward'),
                  child: const SizedBox.expand(),
                )
              : const SizedBox.expand(),
        ),
      ),
    );
    final run = await _startRun(tester);
    await _pan(tester, run, const [Offset(10, 0)]);

    page.value = false;
    await tester.pump();
    await _pan(tester, run, const [Offset(200, 0)]);
    await run.panZoomEnd();

    expect(steps, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Widget _carousel(ScrollController controller) => ListView(
  key: _inner,
  controller: controller,
  scrollDirection: Axis.horizontal,
  children: const [SizedBox(width: 4000, height: 600)],
);

Future<List<String>> _pumpRegion(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final steps = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox.expand(
        child: TrackpadHistoryRegion(
          onBack: () => steps.add('back'),
          onForward: () => steps.add('forward'),
          child: child,
        ),
      ),
    ),
  );
  await tester.pump();
  return steps;
}

Future<TestGesture> _startRun(WidgetTester tester) async {
  final run = await tester.createGesture(kind: PointerDeviceKind.trackpad);
  await run.panZoomStart(_center);
  return run;
}

Future<void> _pan(
  WidgetTester tester,
  TestGesture run,
  List<Offset> cumulative,
) async {
  for (final pan in cumulative) {
    await run.panZoomUpdate(_center, pan: pan);
  }
}
