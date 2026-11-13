import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/src/utils/pagination.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scroll_gestures.dart';

void main() {
  group('ScrollPagingGate', () {
    bool admits({
      bool hasMore = true,
      bool busy = false,
      bool lastPageFailed = false,
    }) => ScrollPagingGate(
      hasMore: hasMore,
      busy: busy,
      lastPageFailed: lastPageFailed,
    ).admits;

    test('admits a page when there is more and nothing stands in the way', () {
      expect(admits(), isTrue);
    });

    test('refuses when the feed is exhausted', () {
      expect(admits(hasMore: false), isFalse);
    });

    test('refuses while a request is in flight', () {
      expect(admits(busy: true), isFalse);
    });

    test('refuses after a failed page', () {
      expect(admits(lastPageFailed: true), isFalse);
    });
  });

  group('UserScrollGestures', () {
    late int starts;
    late ScrollController scroll;

    Future<void> pumpList(WidgetTester tester) async {
      starts = 0;
      scroll = ScrollController();
      addTearDown(scroll.dispose);
      final gestures = UserScrollGestures();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (gestures.starts(notification)) starts += 1;
              return false;
            },
            child: ListView.builder(
              controller: scroll,
              itemExtent: 40,
              itemCount: 200,
              itemBuilder: (_, index) => Text('$index'),
            ),
          ),
        ),
      );
    }

    testWidgets('a drag that reverses without lifting is one gesture', (
      tester,
    ) async {
      await pumpList(tester);
      for (final expected in [1, 2]) {
        await dragOnceThroughUpdates(
          tester,
          find.byType(ListView),
          reach: -200,
          travel: 8,
        );
        expect(starts, expected);
      }
    });

    testWidgets('a fling is one gesture through its settling', (tester) async {
      await pumpList(tester);
      await tester.fling(find.byType(ListView), const Offset(0, -400), 2000);
      await tester.pumpAndSettle();
      expect(starts, 1);
    });

    testWidgets('each wheel notch is a gesture', (tester) async {
      await pumpList(tester);
      final wheel = TestPointer(1, PointerDeviceKind.mouse)
        ..hover(tester.getCenter(find.byType(ListView)));
      for (final expected in [1, 2]) {
        await tester.sendEventToBinding(wheel.scroll(const Offset(0, 40)));
        await tester.pumpAndSettle();
        expect(starts, expected);
      }
    });

    testWidgets('programmatic scrolling is not a gesture', (tester) async {
      await pumpList(tester);
      scroll.jumpTo(400);
      await tester.pump();
      unawaited(
        scroll.animateTo(
          800,
          duration: const Duration(milliseconds: 100),
          curve: Curves.linear,
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, 800);
      expect(starts, 0);
    });
  });

  testWidgets('the footer loads at the end of a scrollable list', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListView(
          children: [
            const SizedBox(height: 1200),
            ScrollPageTrigger(
              enabled: true,
              onLoad: () => calls++,
              child: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
    expect(calls, 0);
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('a leading boundary only loads when visible', (tester) async {
    final controller = ScrollController(initialScrollOffset: 800);
    addTearDown(controller.dispose);
    var calls = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          controller: controller,
          child: Column(
            children: [
              ScrollPageTrigger(
                leading: true,
                enabled: true,
                onLoad: () => calls++,
                child: const SizedBox.shrink(),
              ),
              const SizedBox(height: 1600),
            ],
          ),
        ),
      ),
    );
    expect(calls, 0);
    controller.jumpTo(0);
    await tester.pump();
    expect(calls, 1);
  });

  test('prefetch distance accommodates both small and tall viewports', () {
    double distance(double height) => paginationPrefetchDistance(
      FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 10000,
        pixels: 0,
        viewportDimension: height,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1,
      ),
    );
    expect(distance(400), 1600);
    expect(distance(1200), 2400);
  });

  test('flings fetch ahead with bounded, directional headroom', () {
    final metrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 10000,
      pixels: 4000,
      viewportDimension: 800,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    expect(paginationPrefetchDistance(metrics, velocity: 4000), 3000);
    expect(paginationPrefetchDistance(metrics, velocity: 10000), 4800);
    expect(paginationPrefetchDistance(metrics, velocity: -10000), 1600);
    expect(paginationPrefetchDistance(metrics, velocity: double.nan), 1600);
  });
}
