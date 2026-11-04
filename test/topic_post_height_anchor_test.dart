import 'package:discourse_native/src/shell/topic_post_sliver.dart';
import 'package:discourse_native/src/shell/topic_viewport_coordinator.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

void main() {
  for (final direction in TextDirection.values) {
    for (final growth in [120.0, 1000.0]) {
      testWidgets(
        'cached post height changes preserve an active drag ($direction, $growth)',
        (tester) async {
          final h = _Harness();
          addTearDown(h.dispose);
          await _show(tester, h, direction: direction);
          final viewport = tester.getRect(find.byType(CustomScrollView));
          final leading = find.byKey(const ValueKey(3), skipOffstage: false);
          final anchor = find.byKey(const ValueKey(5));
          expect(leading, findsOneWidget);
          expect(tester.getBottomLeft(leading).dy, lessThan(viewport.top));
          expect(
            tester.getTopLeft(anchor).dy,
            inExclusiveRange(viewport.top, viewport.bottom),
          );
          final drag = await tester.startGesture(viewport.center);
          await drag.moveBy(const Offset(0, -30));
          await tester.pump();
          var top = tester.getTopLeft(anchor).dy;
          var pixels = h.scroll.offset;
          final element = tester.element(anchor);
          h.heights[2].value = 200 + growth;
          await tester.pump();
          expect(
            anchor,
            findsOneWidget,
            reason:
                'The previously visible post must remain visible after growth',
          );
          expect(
            tester.getTopLeft(anchor).dy,
            closeTo(top, .01),
            reason: 'Growth above the viewport must not move the visible post',
          );
          expect(h.scroll.offset, closeTo(pixels + growth, .01));
          for (var frame = 0; frame < 3; frame++) {
            await tester.pump(const Duration(milliseconds: 8));
            expect(tester.getTopLeft(anchor).dy, closeTo(top, .01));
          }
          expect(tester.element(anchor), same(element));
          await drag.moveBy(const Offset(0, -20));
          await tester.pump();
          expect(tester.getTopLeft(anchor).dy, closeTo(top - 20, .01));
          top = tester.getTopLeft(anchor).dy;
          pixels = h.scroll.offset;
          h.heights[2].value = 240;
          await tester.pump();
          expect(
            tester.getTopLeft(anchor).dy,
            closeTo(top, .01),
            reason:
                'Shrinking above the viewport must not move the visible post',
          );
          expect(h.scroll.offset, closeTo(pixels - (growth - 40), .01));
          expect(tester.element(anchor), same(element));
          await drag.up();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'growing the partially visible post keeps its own reading position',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await _show(tester, h);
      final anchor = find.byKey(const ValueKey(4));
      expect(tester.getTopLeft(anchor).dy, lessThan(0));
      final top = tester.getTopLeft(anchor).dy;
      final pixels = h.scroll.offset;
      final element = tester.element(anchor);
      h.heights[3].value = 1000;
      await tester.pump();
      expect(tester.getTopLeft(anchor).dy, top);
      expect(h.scroll.offset, pixels);
      expect(tester.element(anchor), same(element));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a rebuilt delegate still preserves cached prefix growth', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await _show(tester, h);
    final anchor = find.byKey(const ValueKey(5));
    final top = tester.getTopLeft(anchor).dy;
    final element = tester.element(anchor);
    h.heights[2].value = 320;
    await tester.pumpWidget(h.tree());
    expect(tester.getTopLeft(anchor).dy, closeTo(top, .01));
    expect(tester.element(anchor), same(element));
    expect(tester.takeException(), isNull);
  });

  testWidgets('prefix changes respect an explicit jump to another post', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await _show(tester, h);
    h.heights[2].value = 320;
    h.list.jumpToItem(index: 18, scrollController: h.scroll, alignment: 0);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(10))).dy,
      closeTo(0, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a growing leading cache preserves the trailing boundary', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await _show(tester, h);
    h.scroll.jumpTo(h.scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final last = find.byKey(const ValueKey(30));
    final bottom = tester.getBottomLeft(last).dy;
    final element = tester.element(last);
    expect(bottom, closeTo(500, .01));
    h.heights[26].value = 1200;
    await tester.pump();
    expect(tester.getBottomLeft(last).dy, closeTo(bottom, .01));
    expect(h.scroll.offset, closeTo(h.scroll.position.maxScrollExtent, .01));
    expect(tester.element(last), same(element));
    expect(tester.takeException(), isNull);
  });

  testWidgets('width changes preserve the existing visible-row resize anchor', (
    tester,
  ) async {
    final h = _Harness(wrapRows: true);
    addTearDown(h.dispose);
    await _show(tester, h);
    final anchor = find.byKey(const ValueKey(5));
    final top = tester.getTopLeft(anchor).dy;
    await tester.pumpWidget(h.tree(width: 300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(anchor).dy, closeTo(top, .01));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _show(
  WidgetTester tester,
  _Harness h, {
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = const Size(430, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(h.tree(direction: direction));
  await tester.pumpAndSettle();
}

class _Harness {
  _Harness({this.wrapRows = false}) {
    geometry.applyWindowChange(
      TopicViewportWindowChange(
        extentAction: TopicViewportExtentAction.replace,
        previousPostIds: const [],
        currentPostIds: ids,
        previousHasHeader: false,
        hasHeader: false,
        prepended: false,
        appendOnly: false,
      ),
    );
  }
  final bool wrapRows;
  final scroll = ScrollController(initialScrollOffset: 650);
  final list = ListController();
  final ids = List.generate(30, (i) => i + 1);
  final heights = List.generate(30, (_) => ValueNotifier(200.0));
  late final geometry = TopicReaderGeometry(
    scrollController: () => scroll,
    listController: () => list,
    topInset: () => 0,
    startsAtBeginning: () => true,
    postFrame: (callback) =>
        WidgetsBinding.instance.addPostFrameCallback((_) => callback()),
  );

  Widget tree({
    TextDirection direction = TextDirection.ltr,
    double width = 430,
  }) => Directionality(
    textDirection: direction,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: 500,
        child: CustomScrollView(
          controller: scroll,
          physics: const ClampingScrollPhysics(),
          scrollCacheExtent: const ScrollCacheExtent.pixels(500),
          slivers: [
            TopicPostSliver(
              geometry: geometry,
              delayPopulatingCacheArea: false,
              itemCount: ids.length,
              itemBuilder: (_, index) => ValueListenableBuilder<double>(
                key: ValueKey(ids[index]),
                valueListenable: heights[index],
                builder: (_, value, _) => LayoutBuilder(
                  builder: (_, constraints) => SizedBox(
                    height:
                        value *
                        (wrapRows && constraints.maxWidth < 400 ? 2 : 1),
                  ),
                ),
              ),
              separatorBuilder: (_, index) => SizedBox(
                key: geometry.window.separatorKeyAfterItem(index),
                height: 1,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void dispose() {
    scroll.dispose();
    list.dispose();
    for (final height in heights) {
      height.dispose();
    }
  }
}
