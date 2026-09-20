import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _page = ValueKey('live-page');
final _live = find.byKey(_page);

Future<_HistoryHarnessState> _pump(
  WidgetTester tester, {
  TextDirection direction = TextDirection.ltr,
  bool reducedMotion = false,
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
      home: _HistoryHarness(key: key),
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
  const _HistoryHarness({super.key});

  @override
  State<_HistoryHarness> createState() => _HistoryHarnessState();
}

class _HistoryHarnessState extends State<_HistoryHarness> {
  final scroll = ScrollController();
  Object history = Object();
  int index = 0;
  int furthest = 0;
  int swipes = 0;

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
  Widget build(BuildContext context) => DHistoryTransition(
    history: history,
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
    child: ColoredBox(
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
  );
}
