import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_chrome_scroll_view.dart';
import 'package:discourse_native/src/shell/mobile_scroll_dock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _body = ValueKey('scroll-body');
const _dock = ValueKey('scroll-dock');

Widget _list({
  ScrollController? controller,
  bool reverse = false,
  int count = 100,
}) => ListView.builder(
  key: _body,
  controller: controller,
  reverse: reverse,
  itemExtent: 50,
  itemCount: count,
  itemBuilder: (_, index) => Text('Row $index'),
);

Future<void> _mount(
  WidgetTester tester, {
  ScrollController? controller,
  Widget? body,
  bool reverse = false,
  bool reducedMotion = false,
  bool visible = true,
  bool keepVisible = false,
  Object identity = 'topics',
  int count = 100,
  VoidCallback? onPressed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Scaffold(
          body: MobileScrollDock(
            identity: identity,
            visible: visible,
            keepActionVisible: keepVisible,
            body:
                body ??
                _list(controller: controller, reverse: reverse, count: count),
            dockBuilder: (_) => SizedBox(
              key: _dock,
              height: 60,
              child: DButton(
                label: const Text('Dock action'),
                onPressed: onPressed ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _wheel(WidgetTester tester, double delta, {Finder? target}) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(target ?? find.byKey(_body)),
      scrollDelta: Offset(0, delta),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('down hides and a deliberate upward nudge restores the dock', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    final originalBody = tester.element(find.byKey(_body));
    final originalHeight = tester.getSize(find.byKey(_body)).height;
    for (var i = 0; i < 16; i++) {
      await _wheel(tester, 1);
      expect(find.byKey(_dock), findsOneWidget);
    }
    await _wheel(tester, 1);
    expect(find.byKey(_dock), findsNothing);
    expect(tester.getSize(find.byKey(_body)).height, originalHeight + 60);
    expect(controller.offset, 217);
    expect(tester.element(find.byKey(_body)), same(originalBody));
    await _wheel(tester, -10);
    expect(find.byKey(_dock), findsNothing);
    await _wheel(tester, -1);
    expect(find.byKey(_dock), findsOneWidget);
    expect(tester.getSize(find.byKey(_body)).height, originalHeight);
    expect(controller.offset, 206);
    expect(tester.element(find.byKey(_body)), same(originalBody));
  });

  for (final reverse in [false, true]) {
    testWidgets('touch directions follow visual travel (reverse: $reverse)', (
      tester,
    ) async {
      final controller = ScrollController(
        initialScrollOffset: reverse ? 4000 : 400,
      );
      addTearDown(controller.dispose);
      await _mount(tester, controller: controller, reverse: reverse);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_body)),
      );
      await gesture.moveBy(const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(find.byKey(_dock), findsNothing);
      await gesture.moveBy(const Offset(0, 30));
      await tester.pumpAndSettle();
      expect(find.byKey(_dock), findsOneWidget);
      await gesture.cancel();
      await tester.pumpAndSettle();
    });
  }

  testWidgets('trackpad scrolling hides and reveals the dock', (tester) async {
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    final location = tester.getCenter(find.byKey(_body));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(location);
    await gesture.panZoomUpdate(location, pan: const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(find.byKey(_dock), findsNothing);
    await gesture.panZoomUpdate(location, pan: const Offset(0, -70));
    await tester.pumpAndSettle();
    expect(find.byKey(_dock), findsOneWidget);
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();
  });

  testWidgets('tiny reversals cannot accumulate into a hide or reveal', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    for (var i = 0; i < 5; i++) {
      await _wheel(tester, 8);
      await _wheel(tester, -8);
      expect(find.byKey(_dock), findsOneWidget);
    }
    await _wheel(tester, 40);
    for (var i = 0; i < 5; i++) {
      await _wheel(tester, -8);
      await _wheel(tester, 8);
      expect(find.byKey(_dock), findsNothing);
    }
  });

  testWidgets('top and list end restore the dock without extent feedback', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    await _wheel(tester, 40);
    await _wheel(tester, -210);
    expect(controller.offset, 30);
    expect(find.byKey(_dock), findsOneWidget);
    await _wheel(tester, 100);
    expect(find.byKey(_dock), findsNothing);
    await _wheel(tester, 10000);
    expect(find.byKey(_dock), findsOneWidget);
    // Revealing shrinks the viewport and leaves one dock's height of travel.
    // Continuing down to that new end must not take the dock away again.
    await _wheel(tester, 25);
    expect(find.byKey(_dock), findsOneWidget);
    await _wheel(tester, 10000);
    expect(find.byKey(_dock), findsOneWidget);
  });

  testWidgets('short and non-scrolling pages leave their dock visible', (
    tester,
  ) async {
    for (final count in [2, 13]) {
      await _mount(tester, count: count);
      await _wheel(tester, 100);
      expect(find.byKey(_dock), findsOneWidget);
    }
  });

  for (final atEnd in [false, true]) {
    testWidgets('dock returns after hiding reduces travel below its threshold '
        '(at end: $atEnd)', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _mount(tester, controller: controller, count: 14);
      expect(controller.position.maxScrollExtent, 160);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_body)),
      );
      await gesture.moveBy(const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(find.byKey(_dock), findsNothing);
      expect(controller.position.maxScrollExtent, 100);

      await gesture.moveBy(Offset(0, atEnd ? -80 : 30));
      await tester.pumpAndSettle();
      expect(find.byKey(_dock), findsOneWidget);
      if (atEnd) {
        // Returning the dock adds travel again. Continuing to that new end
        // must not immediately hide it and start an extent feedback loop.
        await gesture.moveBy(const Offset(0, -80));
        await tester.pumpAndSettle();
        expect(find.byKey(_dock), findsOneWidget);
      }
      await gesture.cancel();
      await tester.pumpAndSettle();
    });
  }

  testWidgets('elastic overscroll restores the dock at the top', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    await _mount(
      tester,
      body: ListView.builder(
        key: _body,
        controller: controller,
        physics: const BouncingScrollPhysics(),
        itemExtent: 50,
        itemCount: 100,
        itemBuilder: (_, index) => Text('Row $index'),
      ),
    );
    await _wheel(tester, 40);
    expect(find.byKey(_dock), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_body)),
    );
    await gesture.moveBy(const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(controller.offset, lessThan(0));
    expect(find.byKey(_dock), findsOneWidget);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.byKey(_dock), findsOneWidget);
  });

  testWidgets(
    'scroll areas and vertical tables inside horizontal viewports control the dock',
    (tester) async {
      for (final table in [false, true]) {
        final controller = ScrollController();
        final body = table
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1200,
                  child: _list(controller: controller),
                ),
              )
            : DScrollArea(
                controller: controller,
                child: Column(
                  children: [
                    for (var i = 0; i < 100; i++)
                      SizedBox(height: 50, child: Text('Row $i')),
                  ],
                ),
              );
        await _mount(tester, body: body);
        await _wheel(tester, 100, target: find.byType(MobileScrollDock));
        expect(find.byKey(_dock), findsNothing);
        await _wheel(tester, -20, target: find.byType(MobileScrollDock));
        expect(find.byKey(_dock), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets('restoration and navigation never hide the next page dock', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    controller.jumpTo(600);
    await tester.pumpAndSettle();
    expect(find.byKey(_dock), findsOneWidget);
    final restoration = controller.animateTo(
      800,
      duration: const Duration(milliseconds: 100),
      curve: Curves.linear,
    );
    await tester.pumpAndSettle();
    await restoration;
    expect(find.byKey(_dock), findsOneWidget);
    await _wheel(tester, 40);
    expect(find.byKey(_dock), findsNothing);
    controller.jumpTo(300);
    await tester.pumpAndSettle();
    expect(find.byKey(_dock), findsNothing);
    await _mount(tester, controller: controller, identity: 'users');
    expect(find.byKey(_dock), findsOneWidget);
    expect(controller.offset, 300);
  });

  testWidgets('sidebar scrolling has no say after returning to the page', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    await _wheel(tester, 40);
    await _mount(tester, controller: controller, visible: false);
    await _wheel(tester, 200);
    await _mount(tester, controller: controller);
    expect(find.byKey(_dock), findsOneWidget);
  });

  testWidgets('active composer actions stay reachable while the page scrolls', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    await _wheel(tester, 40);
    await _mount(tester, controller: controller, keepVisible: true);
    await _wheel(tester, 200);
    expect(find.byKey(_dock).hitTestable(), findsOneWidget);
  });

  testWidgets(
    'a lazy chat list inside a non-scrolling wrapper controls the dock',
    (tester) async {
      final controller = ScrollController(initialScrollOffset: 200);
      addTearDown(controller.dispose);
      await _mount(
        tester,
        body: ChatChromeScrollView(
          header: const SizedBox(height: 80),
          list: (_, _) => _list(controller: controller),
        ),
      );
      await _wheel(tester, 40);
      expect(find.byKey(_dock), findsNothing);
      await _wheel(tester, -20);
      expect(find.byKey(_dock), findsOneWidget);
    },
  );

  testWidgets('embedded vertical and horizontal scrolls cannot hide the dock', (
    tester,
  ) async {
    const embedded = ValueKey('embedded');
    const horizontal = ValueKey('horizontal');
    await _mount(
      tester,
      body: ListView(
        key: _body,
        children: [
          SizedBox(
            height: 200,
            child: ListView.builder(
              key: embedded,
              itemExtent: 40,
              itemCount: 100,
              itemBuilder: (_, index) => Text('Code $index'),
            ),
          ),
          SizedBox(
            height: 100,
            child: ListView.builder(
              key: horizontal,
              scrollDirection: Axis.horizontal,
              itemExtent: 100,
              itemCount: 100,
              itemBuilder: (_, index) => Text('Column $index'),
            ),
          ),
          const SizedBox(height: 4000),
        ],
      ),
    );
    await _wheel(tester, 200, target: find.byKey(embedded));
    expect(find.byKey(_dock), findsOneWidget);
    await tester.drag(find.byKey(horizontal), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(_dock), findsOneWidget);
    await _wheel(tester, 200, target: find.byKey(_body));
    expect(find.byKey(_dock), findsNothing);
  });

  testWidgets('hidden and exiting dock controls cannot receive input', (
    tester,
  ) async {
    var taps = 0;
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller, onPressed: () => taps++);
    final dockCenter = tester.getCenter(find.byKey(_dock));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byKey(_body)),
        scrollDelta: const Offset(0, 40),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(DButton).hitTestable(), findsNothing);
    await tester.tapAt(dockCenter);
    expect(taps, 0);
    await tester.pumpAndSettle();
    expect(find.byKey(_dock), findsNothing);
    await _wheel(tester, -20);
    await tester.tap(find.byType(DButton));
    expect(taps, 1);
  });

  testWidgets('reduced motion releases dock space immediately', (tester) async {
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller, reducedMotion: true);
    final height = tester.getSize(find.byKey(_body)).height;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byKey(_body)),
        scrollDelta: const Offset(0, 40),
      ),
    );
    await tester.pump();
    expect(find.byKey(_dock), findsNothing);
    expect(tester.getSize(find.byKey(_body)).height, height + 60);
  });
}
