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
  bool revealHeaderAtEnd = false,
  Object? identity,
  int count = 100,
  FocusNode? focusNode,
  double headerHeight = 80,
  VoidCallback? onHeaderPressed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Scaffold(
          body: DPageSurface(
            hideHeaderOnScroll: true,
            revealHeaderAtEnd: revealHeaderAtEnd,
            framed: false,
            identity: identity,
            header: SizedBox(
              key: _header,
              height: headerHeight,
              child: DButton(
                focusNode: focusNode,
                onPressed: onHeaderPressed ?? () {},
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

Future<void> _wheel(
  WidgetTester tester,
  double delta, {
  Duration elapsed = const Duration(milliseconds: 16),
}) async {
  await tester.pump(elapsed);
  await tester.sendEventToBinding(
    PointerScrollEvent(
      timeStamp: Duration(
        milliseconds: tester.binding.clock.now().millisecondsSinceEpoch,
      ),
      position: tester.getCenter(find.byKey(_body)),
      scrollDelta: Offset(0, delta),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'floating motion updates geometry without rebuilding or laying out its content',
    (tester) async {
      final controller = ScrollController(initialScrollOffset: 600);
      addTearDown(controller.dispose);
      var headerLayouts = 0;
      var bodyBuilds = 0;
      DPageHeaderGeometry? geometry;
      await tester.pumpWidget(
        MaterialApp(
          home: DPageSurface.scrollable(
            framed: false,
            hideHeaderOnScroll: true,
            header: LayoutBuilder(
              builder: (context, constraints) {
                headerLayouts++;
                return const SizedBox(height: 80, child: Text('Header'));
              },
            ),
            bodyBuilder: (context, header) {
              geometry = header;
              bodyBuilds++;
              return CustomScrollView(
                key: _body,
                controller: controller,
                slivers: [
                  SliverToBoxAdapter(child: header.spacer),
                  const SliverToBoxAdapter(child: SizedBox(height: 5000)),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final layouts = headerLayouts;
      final builds = bodyBuilds;
      final viewport = tester.getRect(find.byKey(_body));
      await _wheel(tester, 40);
      await tester.pump(const Duration(milliseconds: 40));
      expect(geometry!.visibleExtent, inExclusiveRange(0, 80));
      expect(headerLayouts, layouts);
      expect(bodyBuilds, builds);
      expect(tester.getRect(find.byKey(_body)), viewport);
      await tester.pumpAndSettle();
      expect(geometry!.visibleExtent, 0);
      expect(headerLayouts, layouts);
      expect(bodyBuilds, builds);
      expect(tester.getRect(find.byKey(_body)), viewport);
    },
  );
  for (final reverse in [false, true]) {
    testWidgets(
      'distance follows scroll through reversal slack (reverse: $reverse)',
      (tester) async {
        final controller = ScrollController(initialScrollOffset: 600);
        addTearDown(controller.dispose);
        await _mount(tester, controller: controller, reverse: reverse);
        final body = find.byKey(_body);
        final element = tester.element(body);
        await _wheel(tester, 40);
        await tester.pump(const Duration(milliseconds: 40));
        final partial = tester.getTopLeft(body).dy;
        expect(partial, inExclusiveRange(0, 80));
        await _wheel(tester, -40);
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester.getTopLeft(body).dy,
          lessThan(partial),
          reason: 'slack leaves the hide target unchanged',
        );
        await _wheel(tester, -24);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(body).dy, 80);
        expect(tester.element(body), same(element));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'top overrides hold and bottom reveal remains opt-in (reverse: $reverse)',
      (tester) async {
        final controller = ScrollController(initialScrollOffset: 600);
        addTearDown(controller.dispose);
        await _mount(tester, controller: controller, reverse: reverse);
        final body = find.byKey(_body);
        await _wheel(tester, 80);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(body).dy, 0);
        controller.jumpTo(
          reverse ? controller.position.maxScrollExtent - 1 : 1,
        );
        await tester.pumpAndSettle();
        await _wheel(tester, -1);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(body).dy, 80);
        controller.jumpTo(600);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 500));
        await _wheel(tester, 10000);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(body).dy, 0);
        await _mount(
          tester,
          controller: controller,
          reverse: reverse,
          revealHeaderAtEnd: true,
        );
        controller.jumpTo(
          reverse ? 5 : controller.position.maxScrollExtent - 5,
        );
        await tester.pumpAndSettle();
        await _wheel(tester, 1);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(body).dy, 80);
        await _mount(
          tester,
          controller: controller,
          reverse: reverse,
          revealHeaderAtEnd: true,
          headerHeight: 120,
        );
        await _wheel(tester, 8);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(body).dy, 120);
      },
    );
  }

  testWidgets('slow distance also retracts, without a velocity threshold', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 600);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    await _wheel(tester, 16, elapsed: const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_body)).dy, 0);
  });

  testWidgets(
    'endpoint hold ignores a reversal until fresh slack is consumed',
    (tester) async {
      final controller = ScrollController(initialScrollOffset: 600);
      addTearDown(controller.dispose);
      await _mount(tester, controller: controller);
      await _wheel(tester, 80);
      await tester.pumpAndSettle();
      await _wheel(tester, -80);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_body)).dy, 0);
      await tester.pump(const Duration(milliseconds: 500));
      await _wheel(tester, -40);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_body)).dy, 0);
      await _wheel(tester, -24);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_body)).dy, 80);
    },
  );

  testWidgets(
    'visible header actions retain their exact hit bounds during movement',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = ScrollController(initialScrollOffset: 600);
      addTearDown(controller.dispose);
      var taps = 0;
      await _mount(
        tester,
        controller: controller,
        onHeaderPressed: () => taps++,
      );
      await _wheel(tester, 40);
      await tester.pump(const Duration(milliseconds: 24));
      final visible = tester.getTopLeft(find.byKey(_body)).dy;
      expect(visible, inExclusiveRange(0, 80));
      await tester.tapAt(Offset(195, visible / 2));
      expect(taps, 1);
      await tester.tapAt(Offset(195, visible + 1));
      expect(taps, 1);
      await tester.pumpAndSettle();
      expect(find.byType(DButton).hitTestable(), findsNothing);
    },
  );

  testWidgets(
    'restoration stays visible, navigation cancels motion, and height is remeasured',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _mount(tester, controller: controller);
      final body = find.byKey(_body);
      controller.jumpTo(400);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(body).dy, 80);
      await _wheel(tester, 40);
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.getTopLeft(body).dy, inExclusiveRange(0, 80));
      await _mount(
        tester,
        controller: controller,
        identity: 'another feed',
        headerHeight: 120,
      );
      expect(tester.getTopLeft(body).dy, 120);
      await _wheel(tester, 120);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(body).dy, 0);
      await tester.pump(const Duration(milliseconds: 500));
      await _wheel(tester, -160);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(body).dy, 120);
    },
  );

  testWidgets('reduced motion applies scroll progress immediately', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 600);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller, reducedMotion: true);
    await _wheel(tester, 40);
    expect(tester.getTopLeft(find.byKey(_body)).dy, 40);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_body)).dy, 0);
  });

  testWidgets('short pages and focused controls stay reachable', (
    tester,
  ) async {
    await _mount(tester, count: 11);
    await _wheel(tester, 80);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_body)).dy, 80);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _mount(tester, focusNode: focus);
    focus.requestFocus();
    await tester.pump();
    await _wheel(tester, 100);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_body)).dy, 80);
    expect(focus.hasFocus, true);
  });
  testWidgets('acquiring focus while moving cancels pending hiding', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 600);
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await _mount(tester, controller: controller, focusNode: focus);
    await _wheel(tester, 40);
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.getTopLeft(find.byKey(_body)).dy, inExclusiveRange(0, 80));
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_body)).dy, 80);
    expect(focus.hasFocus, true);
  });
  testWidgets(
    'compact header remeasurement preserves progress and the full spacer',
    (tester) async {
      final controller = ScrollController(initialScrollOffset: 600);
      addTearDown(controller.dispose);
      DPageHeaderGeometry? geometry;
      Future<void> mount(double height) => tester.pumpWidget(
        MaterialApp(
          home: DPageSurface.scrollable(
            framed: false,
            hideHeaderOnScroll: true,
            identity: 'same topic',
            initialCompactHeader: true,
            header: const SizedBox(height: 120, child: Text('Header')),
            compactHeader: SizedBox(
              height: height,
              child: const Text('Header'),
            ),
            bodyBuilder: (context, header) {
              geometry = header;
              return CustomScrollView(
                key: _body,
                controller: controller,
                slivers: [
                  SliverToBoxAdapter(child: header.spacer),
                  const SliverToBoxAdapter(
                    child: SizedBox(
                      key: ValueKey('compact-post'),
                      height: 5000,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await mount(120);
      await tester.pumpAndSettle();
      await _wheel(tester, 60);
      await tester.pump(const Duration(milliseconds: 40));
      final visible = geometry!.visibleExtent;
      final anchor = tester.getTopLeft(
        find.byKey(const ValueKey('compact-post')),
      );
      expect(visible, inExclusiveRange(0, 120));
      await mount(60);
      expect(geometry!.naturalExtent, 120);
      expect(geometry!.visibleExtent, closeTo(visible / 2, .01));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('compact-post'))),
        anchor,
      );
      await tester.pumpAndSettle();
      expect(geometry!.visibleExtent, 0);
    },
  );
}
