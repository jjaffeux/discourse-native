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
    await _wheel(tester, 160);
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getTopLeft(body).dy, inExclusiveRange(0, 80));
    await _wheel(tester, -30);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(body).dy, 80);
    expect(controller.offset, 130);
    await _wheel(tester, 100);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(body).dy, 0);
    expect(find.byKey(_header).hitTestable(), findsNothing);
    expect(tester.element(body), same(element));
    await _wheel(tester, -15);
    await tester.pumpAndSettle();
    expect(find.byKey(_header).hitTestable(), findsOneWidget);
    expect(controller.offset, 215);
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
      expect(tester.getTopLeft(find.byKey(_body)).dy, 80);
    }
    await _wheel(tester, 3);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_body)).dy, 0);
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

  testWidgets('reduced motion switches without intermediate animation', (
    tester,
  ) async {
    await _mount(tester, reducedMotion: true);
    await _wheel(tester, 100);
    expect(tester.getTopLeft(find.byKey(_body)).dy, 0);
    await _wheel(tester, -20);
    expect(tester.getTopLeft(find.byKey(_body)).dy, 80);
  });

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
