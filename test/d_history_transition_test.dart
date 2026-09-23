import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _page = ValueKey('live-page');
final _live = find.byKey(_page);

Future<_HistoryHarnessState> _pump(
  WidgetTester tester, {
  TextDirection direction = TextDirection.ltr,
  bool reducedMotion = false,
  bool tabTransitions = false,
  bool roundedPanel = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final key = GlobalKey<_HistoryHarnessState>();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: _HistoryHarness(
        key: key,
        tabTransitions: tabTransitions,
        roundedPanel: roundedPanel,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

Future<TestGesture> _drag(
  WidgetTester tester, {
  bool fromRight = false,
  double distance = 140,
}) async {
  final start = Offset(fromRight ? 395 : 5, 250);
  final gesture = await tester.startGesture(start);
  await gesture.moveTo(
    start + Offset(fromRight ? -distance : distance, 0),
    timeStamp: const Duration(milliseconds: 200),
  );
  await tester.pump();
  return gesture;
}

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('back and forward follow the finger in $direction', (
      tester,
    ) async {
      final state = await _pump(tester, direction: direction);
      state.visit(1);
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(_live);
      final rtl = direction == TextDirection.rtl;
      final back = await _drag(tester, fromRight: rtl);
      expect(state.index, 1);
      expect(state.swipes, 0);
      expect(tester.getTopLeft(_live).dx - origin.dx, rtl ? -140 : 140);
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.text('Page 0'), findsNothing);
      expect(find.byKey(_page), findsOneWidget);
      await back.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(state.index, 1);
      expect((tester.getTopLeft(_live).dx - origin.dx).abs(), greaterThan(140));
      await tester.pumpAndSettle();
      expect(state.index, 0);
      expect(state.swipes, 1);
      expect(tester.getTopLeft(_live), origin);

      final forward = await _drag(tester, fromRight: !rtl);
      expect(state.index, 0);
      expect(tester.getTopLeft(_live).dx - origin.dx, rtl ? 35 : -35);
      expect(find.byType(RawImage), findsOneWidget);
      await forward.up();
      await tester.pumpAndSettle();
      expect(state.index, 1);
      expect(state.swipes, 2);
      expect(tester.getTopLeft(_live), origin);
      expect(tester.takeException(), isNull);
    });
  }

  for (final direction in TextDirection.values) {
    for (final width in [400.0, 1000.0]) {
      testWidgets('near-edge 70px swipes navigate at $width in $direction', (
        tester,
      ) async {
        final state = await _pump(tester, direction: direction);
        await tester.binding.setSurfaceSize(Size(width, 600));
        state.visit(1);
        await tester.pumpAndSettle();
        final rtl = direction == TextDirection.rtl;
        for (final inset in [5.0, 40.0]) {
          for (final back in [true, false]) {
            final fromRight = back ? rtl : !rtl;
            final start = Offset(fromRight ? width - inset : inset, 250);
            final gesture = await tester.startGesture(start);
            await gesture.moveBy(
              Offset(fromRight ? -70 : 70, 8),
              timeStamp: const Duration(milliseconds: 300),
            );
            await tester.pump();
            await gesture.up(timeStamp: const Duration(milliseconds: 500));
            await tester.pumpAndSettle();
            expect(state.index, back ? 0 : 1);
            expect(state.swipes, (inset == 5 ? 0 : 2) + (back ? 1 : 2));
          }
        }
      });
    }
  }

  testWidgets('short drags and pointer cancellation restore the live page', (
    tester,
  ) async {
    final state = await _pump(tester);
    state.visit(1);
    await tester.pumpAndSettle();
    for (final cancel in [false, true]) {
      final gesture = await _drag(tester, distance: cancel ? 140 : 60);
      expect(tester.getTopLeft(_live).dx, greaterThan(0));
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pumpAndSettle();
      expect(state.index, 1);
      expect(state.swipes, 0);
      expect(tester.getTopLeft(_live).dx, 0);
      expect(find.byType(RawImage), findsNothing);
    }
  });

  testWidgets(
    'a reverse flick cancels even after passing the distance threshold',
    (tester) async {
      final state = await _pump(tester);
      state.visit(1);
      await tester.pumpAndSettle();
      final gesture = await _drag(tester, distance: 220);
      for (var step = 1; step <= 4; step++) {
        await gesture.moveTo(
          Offset(225 - step * 20, 250),
          timeStamp: Duration(milliseconds: 200 + step * 10),
        );
      }
      await gesture.up(timeStamp: const Duration(milliseconds: 245));
      await tester.pumpAndSettle();
      expect(state.index, 1);
      expect(state.swipes, 0);
    },
  );

  testWidgets('a fast short flick commits', (tester) async {
    final state = await _pump(tester);
    state.visit(1);
    await tester.pumpAndSettle();
    await tester.flingFrom(const Offset(5, 250), const Offset(70, 0), 1000);
    await tester.pumpAndSettle();
    expect(state.index, 0);
    expect(state.swipes, 1);
  });

  testWidgets(
    'vertical, body, mouse and unavailable-edge drags do not navigate',
    (tester) async {
      final state = await _pump(tester);
      await tester.dragFrom(const Offset(5, 250), const Offset(140, 0));
      await tester.pumpAndSettle();
      expect(state.swipes, 0);
      state.visit(1);
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(200, 250), const Offset(140, 0));
      await tester.dragFrom(const Offset(5, 250), const Offset(30, -150));
      await tester.dragFrom(const Offset(395, 250), const Offset(-140, 0));
      final mouse = await tester.startGesture(
        const Offset(5, 250),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(140, 0));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(state.index, 1);
      expect(state.swipes, 0);
      expect(state.scroll.offset, greaterThan(0));
    },
  );

  testWidgets('vertical scrolling inside the wider edges does not navigate', (
    tester,
  ) async {
    final state = await _pump(tester);
    state.visit(2);
    state.visit(1);
    await tester.pumpAndSettle();
    for (final x in [40.0, 360.0]) {
      final before = state.scroll.offset;
      await tester.dragFrom(Offset(x, 250), const Offset(8, -120));
      await tester.pumpAndSettle();
      expect(state.scroll.offset, greaterThan(before));
      expect(state.index, 1);
      expect(state.swipes, 0);
    }
  });

  testWidgets('a second finger cancels navigation', (tester) async {
    final state = await _pump(tester);
    state.visit(1);
    await tester.pumpAndSettle();
    final first = await _drag(tester);
    final second = await tester.startGesture(
      const Offset(200, 300),
      pointer: 2,
    );
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(state.swipes, 0);
    expect(tester.getTopLeft(_live).dx, 0);
  });

  testWidgets(
    'external navigation and history resets invalidate pending swipes',
    (tester) async {
      final state = await _pump(tester);
      state.visit(1);
      await tester.pumpAndSettle();
      final gesture = await _drag(tester);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 30));
      state.visit(2);
      await tester.pumpAndSettle();
      expect(state.index, 2);
      expect(state.swipes, 0);
      final next = await _drag(tester);
      state.resetHistory();
      await tester.pump();
      await next.up();
      await tester.pumpAndSettle();
      expect(state.index, 0);
      expect(state.swipes, 0);
      expect(find.byType(RawImage), findsNothing);
    },
  );

  testWidgets('modal routes cancel and block gestures on the covered page', (
    tester,
  ) async {
    final state = await _pump(tester);
    state.visit(1);
    await tester.pumpAndSettle();
    final gesture = await _drag(tester);
    final result = showDDialog<void>(
      context: tester.element(_live),
      builder: (_, _) => const DDialogContent(
        children: [
          DDialogHeader(children: [DDialogTitle(child: Text('Modal'))]),
        ],
      ),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.swipes, 0);
    await tester.dragFrom(const Offset(5, 250), const Offset(140, 0));
    await tester.pumpAndSettle();
    expect(state.swipes, 0);
    Navigator.of(tester.element(_live)).pop();
    await result;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_live).dx, 0);
  });

  testWidgets('reduced motion navigates on release without moving the page', (
    tester,
  ) async {
    final state = await _pump(tester, reducedMotion: true);
    state.visit(1);
    await tester.pumpAndSettle();
    final gesture = await _drag(tester);
    expect(tester.getTopLeft(_live).dx, 0);
    expect(find.byType(RawImage), findsNothing);
    expect(state.index, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.index, 0);
    expect(state.swipes, 1);
  });

  testWidgets('disposing during settlement leaves no callback or ticker', (
    tester,
  ) async {
    final state = await _pump(tester);
    state.visit(1);
    await tester.pumpAndSettle();
    final gesture = await _drag(tester);
    await gesture.up();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(state.swipes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resize and memory pressure clear previews and cancel gestures', (
    tester,
  ) async {
    final state = await _pump(tester);
    state.visit(1);
    await tester.pumpAndSettle();
    final gesture = await _drag(tester);
    expect(find.byType(RawImage), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(600, 400));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.swipes, 0);
    expect(find.byType(RawImage), findsNothing);
    state.visit(2);
    await tester.pumpAndSettle();
    final next = await _drag(tester, distance: 200);
    expect(find.byType(RawImage), findsOneWidget);
    tester.binding.handleMemoryPressure();
    await next.up();
    await tester.pumpAndSettle();
    expect(state.swipes, 0);
    expect(tester.getTopLeft(_live).dx, 0);
    expect(find.byType(RawImage), findsNothing);
  });

  for (final direction in TextDirection.values) {
    testWidgets('ordered tabs push both pages in $direction', (tester) async {
      final state = await _pump(
        tester,
        direction: direction,
        tabTransitions: true,
      );
      final mirror = direction == TextDirection.rtl ? -1 : 1;
      for (final (tab, sign) in [(3, 1), (1, -1), (4, 1)]) {
        state.selectTab(tab);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 70));
        final incoming = tester
            .widget<Transform>(
              find.byKey(const ValueKey('history-incoming-tab')),
            )
            .transform
            .getTranslation()
            .x;
        final outgoing = tester
            .widget<Transform>(
              find.byKey(const ValueKey('history-outgoing-tab')),
            )
            .transform
            .getTranslation()
            .x;
        expect(incoming * sign * mirror, greaterThan(0));
        expect(outgoing * sign * mirror, lessThan(0));
        expect((incoming - outgoing).abs(), 400);
        expect(find.byKey(_page), findsOneWidget);
        expect(find.byType(RawImage), findsOneWidget);
        expect(find.text('Page $tab'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(_live).dx, 0);
        expect(find.byType(RawImage), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rounded tab surfaces reveal the background at their seam', (
    tester,
  ) async {
    final state = await _pump(tester, tabTransitions: true, roundedPanel: true);
    state.selectTab(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final outgoing = tester
        .widget<Transform>(find.byKey(const ValueKey('history-outgoing-tab')))
        .transform
        .getTranslation()
        .x;
    final seam = (400 + outgoing).round();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('history-test-boundary')),
    );
    final image = boundary.toImageSync(pixelRatio: 1);
    final pixels = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(pixels, isNotNull);
    final offset = seam * 4;
    expect(pixels!.getUint8(offset), 0);
    expect(pixels.getUint8(offset + 1), 255);
    expect(pixels.getUint8(offset + 2), 0);
    image.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets('tab changes respect reduced motion and owner changes', (
    tester,
  ) async {
    final state = await _pump(
      tester,
      reducedMotion: true,
      tabTransitions: true,
    );
    state.selectTab(2);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_live).dx, 0);
    expect(find.byType(RawImage), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    final animated = await _pump(tester, tabTransitions: true);
    animated.selectTab(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(RawImage), findsOneWidget);
    animated.changeOwner();
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
    expect(tester.getTopLeft(_live).dx, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid tab changes, resizing and disposal release previews', (
    tester,
  ) async {
    final state = await _pump(tester, tabTransitions: true);
    state.selectTab(3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    state.selectTab(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(RawImage), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(450, 600));
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
    state.selectTab(4);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('history-transition examples use the working component', (
    tester,
  ) async {
    final examples = componentExamples['history-transition']!;
    for (final example in examples.examples) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: Builder(builder: example.builder)),
        ),
      );
      await tester.pumpAndSettle();
      if (example.title == 'Ordered tabs') {
        await tester.tap(find.text('Messages'));
        await tester.pumpAndSettle();
        expect(find.text('Messages page'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        continue;
      }
      await tester.tap(find.text('Open Topics'));
      await tester.pumpAndSettle();
      expect(find.text('1 completed navigations'), findsOneWidget);
      expect(find.byType(DHistoryTransition), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

class _HistoryHarness extends StatefulWidget {
  const _HistoryHarness({
    super.key,
    this.tabTransitions = false,
    this.roundedPanel = false,
  });
  final bool tabTransitions;
  final bool roundedPanel;

  @override
  State<_HistoryHarness> createState() => _HistoryHarnessState();
}

class _HistoryHarnessState extends State<_HistoryHarness> {
  final scroll = ScrollController();
  Object history = Object();
  int index = 0;
  int furthest = 0;
  int swipes = 0;
  late int? tabIndex = widget.tabTransitions ? 0 : null;
  Object tabOwner = Object();

  void selectTab(int tab) => setState(() {
    history = Object();
    tabIndex = tab;
    index = tab;
    furthest = tab;
  });

  void changeOwner() => setState(() {
    tabOwner = Object();
    history = Object();
    tabIndex = 0;
    index = 0;
  });

  void visit(int page) => setState(() {
    index = page;
    if (page > furthest) furthest = page;
  });

  void resetHistory() => setState(() {
    history = Object();
    index = 0;
    furthest = 0;
  });

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const ValueKey('history-test-boundary'),
    child: ColoredBox(
      color: const Color(0xFF00FF00),
      child: DHistoryTransition(
        history: history,
        tabIndex: tabIndex,
        tabOwner: tabOwner,
        entry: index,
        previousEntry: index > 0 ? index - 1 : null,
        nextEntry: index < furthest ? index + 1 : null,
        onBack: index > 0
            ? () {
                swipes++;
                visit(index - 1);
              }
            : null,
        onForward: index < furthest
            ? () {
                swipes++;
                visit(index + 1);
              }
            : null,
        child: widget.roundedPanel
            ? const DPageSurface(
                key: _page,
                backgroundColor: Colors.red,
                child: SizedBox.expand(),
              )
            : ColoredBox(
                key: _page,
                color: DTokens.of(context).background,
                child: ListView(
                  controller: scroll,
                  children: [
                    Text('Page $index'),
                    for (var row = 0; row < 40; row++)
                      SizedBox(height: 48, child: Text('Row $row')),
                  ],
                ),
              ),
      ),
    ),
  );
}
