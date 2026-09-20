import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _header = ValueKey('header');
const _body = ValueKey('body');

Future<void> _mount(
  WidgetTester tester, {
  ScrollController? controller,
  bool reducedMotion = false,
  bool reverse = false,
  Object? identity,
  int count = 100,
  FocusNode? focusNode,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Scaffold(
          body: DPageSurface(
            hideHeaderOnScroll: true,
            framed: false,
            identity: identity,
            header: SizedBox(
              key: _header,
              height: 80,
              child: DButton(
                focusNode: focusNode,
                onPressed: () {},
                label: const Text('Header action'),
              ),
            ),
            child: ListView.builder(
              key: _body,
              reverse: reverse,
              controller: controller,
              itemExtent: 50,
              itemCount: count,
              itemBuilder: (_, i) => Text('Row $i'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _wheel(WidgetTester tester, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(find.byKey(_body)),
      scrollDelta: Offset(0, delta),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('wheel retracts smoothly, reverses, and retains the viewport', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    final body = find.byKey(_body);
    final element = tester.element(body);
    await _wheel(tester, 20);
    expect(tester.getTopLeft(body).dy, 60);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getTopLeft(body).dy, 60);
    await _wheel(tester, 140);
    await _wheel(tester, -100);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(body).dy, 80);
    expect(controller.offset, 60);
    await _wheel(tester, 100);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(body).dy, 0);
    expect(find.byKey(_header).hitTestable(), findsNothing);
    expect(tester.element(body), same(element));
    await _wheel(tester, -100);
    await tester.pumpAndSettle();
    expect(find.byKey(_header).hitTestable(), findsOneWidget);
    expect(controller.offset, 60);
  });

  testWidgets('wheel distance controls partial reveal and immediate reversal', (
    tester,
  ) async {
    await _mount(tester);
    final body = find.byKey(_body);
    await _wheel(tester, 400);
    expect(tester.getTopLeft(body).dy, 0);
    await _wheel(tester, -20);
    expect(tester.getTopLeft(body).dy, 20);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(body).dy, 20);
    await _wheel(tester, -15);
    expect(tester.getTopLeft(body).dy, 35);
    await _wheel(tester, 10);
    expect(tester.getTopLeft(body).dy, 25);
    await _wheel(tester, -55);
    expect(tester.getTopLeft(body).dy, 80);
  });

  testWidgets('reaching the top fully reveals the header', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    final body = find.byKey(_body);
    await _wheel(tester, 60);
    await tester.pumpAndSettle();
    await _wheel(tester, -59);
    await tester.pumpAndSettle();
    expect(controller.offset, 1);
    expect(tester.getTopLeft(body).dy, closeTo(79, 0.001));
    await _wheel(tester, -1);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(tester.getTopLeft(body).dy, 80);
  });

  testWidgets(
    'reversed lists track physical scroll distance in both directions',
    (tester) async {
      final controller = ScrollController(initialScrollOffset: 600);
      addTearDown(controller.dispose);
      await _mount(tester, controller: controller, reverse: true);
      final body = find.byKey(_body);
      final element = tester.element(body);
      await _wheel(tester, 200);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(body).dy, 0);
      await _wheel(tester, -25);
      expect(tester.getTopLeft(body).dy, 25);
      await _wheel(tester, 10);
      expect(tester.getTopLeft(body).dy, closeTo(15, 0.001));
      await _wheel(tester, -65);
      expect(tester.getTopLeft(body).dy, 80);
      expect(tester.element(body), same(element));

      // The present (minimum extent) is the bottom, not the top.
      await _wheel(tester, 2000);
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
      expect(tester.getTopLeft(body).dy, 0);
      controller.jumpTo(controller.position.maxScrollExtent - 40);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(body).dy, 0);
      await _wheel(tester, -40);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(body).dy, 80);
    },
  );

  testWidgets('reversed touch scrolling hides and reveals the header', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 600);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller, reverse: true);
    final body = find.byKey(_body);
    await tester.drag(body, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(body).dy, 0);
    await tester.drag(body, const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(body).dy, 80);
  });

  testWidgets('restoration does not hide and tiny wheel deltas accumulate', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    controller.jumpTo(400);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_body)).dy, 80);
    for (var i = 0; i < 3; i++) {
      await _wheel(tester, 3);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_body)).dy, 80 - (i + 1) * 3);
    }
    await _wheel(tester, 3);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_body)).dy, 68);
    await _mount(tester, controller: controller, identity: 'another feed');
    expect(tester.getTopLeft(find.byKey(_body)).dy, 80);
  });

  testWidgets('touch drag hides and upward scrolling reveals at the top', (
    tester,
  ) async {
    await _mount(tester);
    await tester.drag(find.byKey(_body), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_body)).dy, 0);
    await tester.drag(find.byKey(_body), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_body)).dy, 80);
  });

  for (final reverse in [false, true]) {
    testWidgets(
      'touch motion tracks distance without easing (reverse: $reverse)',
      (tester) async {
        final controller = ScrollController(initialScrollOffset: 600);
        addTearDown(controller.dispose);
        await _mount(tester, controller: controller, reverse: reverse);
        final body = find.byKey(_body);
        final gesture = await tester.startGesture(tester.getCenter(body));
        // Cross touch slop before measuring incremental movement.
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump();
        await tester.pump();
        final before = tester.getTopLeft(body).dy;
        await gesture.moveBy(const Offset(0, -10));
        await tester.pump();
        await tester.pump();
        expect(tester.getTopLeft(body).dy, closeTo(before - 10, 0.001));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getTopLeft(body).dy, closeTo(before - 10, 0.001));
        await gesture.moveBy(const Offset(0, 5));
        await tester.pump();
        await tester.pump();
        expect(tester.getTopLeft(body).dy, closeTo(before - 5, 0.001));
        await gesture.cancel();
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'reduced motion follows scroll distance without independent animation',
    (tester) async {
      await _mount(tester, reducedMotion: true);
      await _wheel(tester, 20);
      expect(tester.getTopLeft(find.byKey(_body)).dy, 60);
      await _wheel(tester, 80);
      expect(tester.getTopLeft(find.byKey(_body)).dy, 0);
      await _wheel(tester, -100);
      expect(tester.getTopLeft(find.byKey(_body)).dy, 80);
    },
  );

  testWidgets('short pages retain reachable controls', (tester) async {
    await _mount(tester, count: 11);
    await _wheel(tester, 80);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_body)).dy, 80);
  });

  testWidgets('focused header controls stay visible while scrolling', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _mount(tester, focusNode: focus);
    focus.requestFocus();
    await tester.pump();
    await _wheel(tester, 100);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_body)).dy, 80);
    expect(focus.hasFocus, isTrue);
  });
}
