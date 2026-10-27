import 'package:discourse_native/discourse_ui.dart';
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
  bool floating = false,
  bool visible = true,
  bool hideOnScroll = true,
  bool keepVisible = false,
  bool hasMore = false,
  bool loading = false,
  bool hasMoreBefore = false,
  bool loadingBefore = false,
  Object identity = 'topics',
  int count = 100,
  bool dock = true,
  VoidCallback? onPressed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Scaffold(
          body: MobileScrollDock(
            floating: floating,
            identity: identity,
            visible: visible,
            hideOnScroll: hideOnScroll,
            keepActionVisible: keepVisible,
            body: DScrollChromePagination(
              hasMore: hasMore,
              loading: loading,
              hasMoreBefore: hasMoreBefore,
              loadingBefore: loadingBefore,
              child:
                  body ??
                  _list(controller: controller, reverse: reverse, count: count),
            ),
            dockBuilder: (_) => dock
                ? SizedBox(
                    key: _dock,
                    height: 60,
                    child: DButton(
                      label: const Text('Dock action'),
                      onPressed: onPressed ?? () {},
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 450));
}

Future<void> _wheel(WidgetTester tester, double delta, {Finder? target}) async {
  await tester.pump(const Duration(milliseconds: 450));
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(target ?? find.byKey(_body)),
      scrollDelta: Offset(0, delta),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 16));
}

void main() {
  testWidgets('interactive footer travel is immediate and keeps the viewport', (
    tester,
  ) async {
    final fraction = ValueNotifier(0.0);
    addTearDown(fraction.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: fraction,
          builder: (context, hidden, _) => MobileScrollDock(
            identity: 'topics',
            floating: true,
            hiddenFraction: hidden,
            body: const SizedBox.expand(key: _body),
            dockBuilder: (_) => SizedBox(
              key: _dock,
              height: 60,
              child: DButton(
                label: const Text('Dock action'),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final body = tester.getRect(find.byKey(_body));
    final dock = tester.getRect(find.byKey(_dock));
    for (final hidden in [.25, .75, 1.0, .5, 0.0]) {
      fraction.value = hidden;
      await tester.pump();
      expect(tester.getRect(find.byKey(_body)), body);
      expect(tester.getTopLeft(find.byKey(_dock)).dy, dock.top + 60 * hidden);
      expect(
        DScrollChrome.bottomInsetOf(tester.element(find.byKey(_body))),
        60,
      );
      expect(
        find.byKey(_dock).hitTestable(at: const Alignment(0, -.9)),
        hidden == 1 ? findsNothing : findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getTopLeft(find.byKey(_dock)).dy, dock.top + 60 * hidden);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'floating dock keeps the viewport and exposes measured clearance',
    (tester) async {
      final controller = ScrollController(initialScrollOffset: 200);
      addTearDown(controller.dispose);
      await _mount(tester, controller: controller, floating: true);
      final height = tester.getSize(find.byKey(_body)).height;
      expect(height, tester.getSize(find.byType(Scaffold)).height);
      expect(
        DScrollChrome.bottomInsetOf(tester.element(find.byKey(_body))),
        60,
      );
      await _wheel(tester, 80);
      expect(tester.getSize(find.byKey(_body)).height, height);
      expect(find.byKey(_dock), findsOneWidget);
      expect(
        DScrollChrome.bottomInsetOf(tester.element(find.byKey(_body))),
        60,
      );
    },
  );

  testWidgets('an empty floating footer clears the room of the dock before', (
    tester,
  ) async {
    double clearance() =>
        DScrollChrome.bottomInsetOf(tester.element(find.byKey(_body)));
    await _mount(tester, floating: true);
    expect(clearance(), 60);
    await _mount(tester, floating: true, dock: false, identity: 'board');
    expect(clearance(), 0);
    await _mount(tester, floating: true);
    expect(clearance(), 60);
  });

  testWidgets('disabling scroll hiding restores and keeps the full dock', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    await _wheel(tester, 40);
    expect(find.byKey(_dock), findsNothing);

    await _mount(tester, controller: controller, hideOnScroll: false);
    final dockRect = tester.getRect(find.byKey(_dock));
    for (final delta in [100.0, -40.0]) {
      final offset = controller.offset;
      await _wheel(tester, delta);
      expect(controller.offset, offset + delta);
      expect(find.byKey(_dock).hitTestable(), findsOneWidget);
      expect(tester.getRect(find.byKey(_dock)), dockRect);
    }

    await _mount(tester, controller: controller);
    await _wheel(tester, 40);
    expect(find.byKey(_dock), findsNothing);
  });

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
    await _wheel(tester, 40);
    expect(find.byKey(_dock), findsNothing);
    expect(tester.getSize(find.byKey(_body)).height, originalHeight + 60);
    expect(controller.offset, 256);
    expect(tester.element(find.byKey(_body)), same(originalBody));
    await _wheel(tester, -9);
    expect(find.byKey(_dock), findsNothing);
    await _wheel(tester, -60);
    expect(find.byKey(_dock), findsOneWidget);
    expect(tester.getSize(find.byKey(_body)).height, originalHeight);
    expect(controller.offset, 187);
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
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byKey(_dock), findsNothing);
      await gesture.moveBy(const Offset(0, 80));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byKey(_dock), findsOneWidget);
      await gesture.cancel();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 450));
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
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(_dock), findsNothing);
    await gesture.panZoomUpdate(location, pan: Offset.zero);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(_dock), findsOneWidget);
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 450));
  });

  testWidgets('sub-threshold reversals cannot accumulate into a hide or reveal', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    final shownHeight = tester.getSize(find.byKey(_body)).height;
    // The dock's 64px motion span settles a first nudge back to shown below 10%.
    for (var i = 0; i < 5; i++) {
      await _wheel(tester, 5);
      await _wheel(tester, -5);
      expect(find.byKey(_dock), findsOneWidget);
      expect(tester.getSize(find.byKey(_body)).height, shownHeight);
    }
    await _wheel(tester, 80);
    for (var i = 0; i < 5; i++) {
      await _wheel(tester, -5);
      await _wheel(tester, 5);
      expect(find.byKey(_dock), findsNothing);
      expect(tester.getSize(find.byKey(_body)).height, shownHeight + 60);
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

  for (final floating in [false, true]) {
    for (final reducedMotion in [false, true]) {
      for (final loading in [false, true]) {
        testWidgets(
          'temporary bottom stays compact through loading and appended rows '
          '(floating: $floating, reduced motion: $reducedMotion, loading: $loading)',
          (tester) async {
            final controller = ScrollController(initialScrollOffset: 200);
            addTearDown(controller.dispose);
            Future<void> mount({required int count, bool complete = false}) =>
                _mount(
                  tester,
                  controller: controller,
                  count: count,
                  floating: floating,
                  reducedMotion: reducedMotion,
                  hasMore: !complete && !loading,
                  loading: !complete && loading,
                );
            double fraction() => DScrollChrome.maybeOf(
              tester.element(find.byKey(_body)),
            )!.hiddenFraction;
            await mount(count: 100);
            await _wheel(tester, 100);
            expect(fraction(), 1);
            await _wheel(tester, 10000);
            expect(fraction(), 1);
            // A slow request must not cause even a partial expansion.
            for (var frame = 0; frame < 60; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
              expect(fraction(), 1);
            }
            await mount(count: 150);
            expect(fraction(), 1);
            await _wheel(tester, 100);
            expect(fraction(), 1);
            await _wheel(tester, -100);
            expect(fraction(), 0);
            await _wheel(tester, 100);
            expect(fraction(), 1);
            // The final response appends rows before marking the feed complete.
            await mount(count: 200, complete: true);
            expect(fraction(), 1);
            await _wheel(tester, 10000);
            expect(fraction(), 0);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final reverse in [false, true]) {
    testWidgets(
      'temporary top does not reveal while scrolling down (reverse: $reverse)',
      (tester) async {
        final controller = ScrollController(
          initialScrollOffset: reverse ? 4300 : 200,
        );
        addTearDown(controller.dispose);
        Future<void> mount({bool more = true, bool loading = false}) => _mount(
          tester,
          controller: controller,
          reverse: reverse,
          hasMoreBefore: more,
          loadingBefore: loading,
        );
        double fraction() => DScrollChrome.maybeOf(
          tester.element(find.byKey(_body)),
        )!.hiddenFraction;
        await mount();
        await _wheel(tester, 100);
        expect(fraction(), 1);
        // Paging may move the loaded top under a reader. That layout correction
        // is not an instruction to reveal, nor is a downward drag at that edge.
        controller.jumpTo(
          reverse ? controller.position.maxScrollExtent - 2 : 2,
        );
        await tester.pumpAndSettle();
        await mount(loading: true);
        await _wheel(tester, 20);
        expect(fraction(), 1);
        await mount(more: false, loading: true);
        expect(fraction(), 1); // Still loading.
        await mount(more: false, loading: false);
        expect(fraction(), 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('an empty final page reveals the dock at the confirmed end', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller, hasMore: true);
    await _wheel(tester, 100);
    await _wheel(tester, 10000);
    expect(find.byKey(_dock), findsNothing);
    await _mount(tester, controller: controller, loading: true);
    expect(find.byKey(_dock), findsNothing);
    await _mount(tester, controller: controller);
    expect(find.byKey(_dock), findsOneWidget);
    // The automatic reveal releases layout space without retracting again.
    await _wheel(tester, 25);
    expect(find.byKey(_dock), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('content growth releases the bottom hold during the same drag', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_body)),
    );
    await gesture.moveBy(const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(_dock), findsNothing);
    await gesture.moveBy(const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(find.byKey(_dock), findsOneWidget);
    await _mount(tester, controller: controller, count: 150);
    // Appending rows does not itself retract the bar; continued input does.
    expect(find.byKey(_dock), findsOneWidget);
    await gesture.moveBy(const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(find.byKey(_dock), findsNothing);
    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('a confirmed end reveals during elastic bottom overscroll', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 400);
    addTearDown(controller.dispose);
    Widget body() => ListView.builder(
      key: _body,
      controller: controller,
      physics: const BouncingScrollPhysics(),
      itemExtent: 50,
      itemCount: 100,
      itemBuilder: (_, index) => Text('Row $index'),
    );
    Future<void> mount(bool hasMore) =>
        _mount(tester, floating: true, hasMore: hasMore, body: body());
    double fraction() => DScrollChrome.maybeOf(
      tester.element(find.byKey(_body)),
    )!.hiddenFraction;
    await mount(true);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_body)),
    );
    await gesture.moveBy(const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(fraction(), 1);
    await gesture.moveBy(const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.position.outOfRange, isTrue);
    expect(fraction(), 1);
    await mount(false);
    expect(fraction(), 0);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(fraction(), 0);
    expect(tester.takeException(), isNull);
  });

  for (final reverse in [false, true]) {
    testWidgets('touch overscroll at a paginated visual bottom stays compact '
        '(reverse: $reverse)', (tester) async {
      final controller = ScrollController(
        initialScrollOffset: reverse ? 4000 : 400,
      );
      addTearDown(controller.dispose);
      await _mount(
        tester,
        floating: true,
        hasMore: true,
        body: ListView.builder(
          key: _body,
          controller: controller,
          reverse: reverse,
          physics: const BouncingScrollPhysics(),
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, index) => Text('Row $index'),
        ),
      );
      double fraction() => DScrollChrome.maybeOf(
        tester.element(find.byKey(_body)),
      )!.hiddenFraction;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_body)),
      );
      await gesture.moveBy(const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(fraction(), 1);
      await tester.pump(const Duration(milliseconds: 450));
      await gesture.moveBy(const Offset(0, -10000));
      await tester.pumpAndSettle();
      expect(controller.position.outOfRange, isTrue);
      expect(fraction(), 1);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(fraction(), 1);
      await _wheel(tester, -100);
      expect(fraction(), 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final atEnd in [false, true]) {
    testWidgets(
      'two-screen cutoff stays stable as the dock changes the viewport '
      '(at end: $atEnd)',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await _mount(tester, controller: controller, count: 22);
        expect(controller.position.maxScrollExtent, 560);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(_body)),
        );
        await gesture.moveBy(const Offset(0, -200));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.byKey(_dock), findsNothing);
        expect(controller.position.maxScrollExtent, 500);

        await gesture.moveBy(Offset(0, atEnd ? -600 : 80));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.byKey(_dock), findsOneWidget);
        expect(controller.position.maxScrollExtent, 560);
        if (!atEnd) {
          expect(controller.offset, greaterThan(48));
          // Still eligible to hide after revealing, even at the larger viewport.
          await gesture.moveBy(const Offset(0, -80));
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 450));
          expect(find.byKey(_dock), findsNothing);
          expect(controller.position.maxScrollExtent, 500);
        }
        if (atEnd) {
          // Returning the dock adds travel again. Continuing to that new end
          // must not immediately hide it and start an extent feedback loop.
          await gesture.moveBy(const Offset(0, -80));
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 450));
          expect(find.byKey(_dock), findsOneWidget);
        }
        await gesture.cancel();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 450));
      },
    );
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
    await tester.pump(const Duration(milliseconds: 450));
    expect(controller.offset, lessThan(0));
    expect(find.byKey(_dock), findsOneWidget);
    await gesture.cancel();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 450));
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
        await _wheel(tester, -80, target: find.byType(MobileScrollDock));
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
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(_dock), findsOneWidget);
    final restoration = controller.animateTo(
      800,
      duration: const Duration(milliseconds: 100),
      curve: Curves.linear,
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 450));
    await restoration;
    expect(find.byKey(_dock), findsOneWidget);
    await _wheel(tester, 40);
    expect(find.byKey(_dock), findsNothing);
    controller.jumpTo(300);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 450));
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
        body: DPageSurface.headed(
          title: const Text('Chats'),
          controls: const SizedBox(height: 80),
          adaptiveBodyBuilder: (_, _) => _list(controller: controller),
        ),
      );
      await _wheel(tester, 40);
      expect(find.byKey(_dock), findsNothing);
      await _wheel(tester, -80);
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
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(_dock), findsOneWidget);
    await _wheel(tester, 200, target: find.byKey(_body));
    expect(find.byKey(_dock), findsNothing);
  });

  testWidgets('dock hits stay inside the visible bounds during retraction', (
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
    expect(find.byType(DButton).hitTestable(), findsOneWidget);
    // Follow the smoothing long enough for the old center to leave the clip,
    // while keeping a visible, interactive slice before the 120ms settle.
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byType(DButton).hitTestable(), findsNothing);
    final visibleTop = tester.getBottomLeft(find.byKey(_body)).dy;
    expect(visibleTop, greaterThan(dockCenter.dy));
    expect(
      visibleTop,
      lessThan(tester.getBottomRight(find.byType(MobileScrollDock)).dy),
    );
    await tester.tapAt(dockCenter);
    expect(taps, 0);
    await tester.tapAt(Offset(dockCenter.dx, visibleTop + 2));
    expect(taps, 1);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(_dock), findsNothing);
    await _wheel(tester, -80);
    await tester.tap(find.byType(DButton));
    expect(taps, 2);
  });

  testWidgets('reduced motion releases proportional dock space immediately', (
    tester,
  ) async {
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
    final partialHeight = height + 60 * 40 / 64;
    expect(find.byKey(_dock), findsOneWidget);
    expect(tester.getSize(find.byKey(_body)).height, partialHeight);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getSize(find.byKey(_body)).height, partialHeight);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(_dock), findsNothing);
    expect(tester.getSize(find.byKey(_body)).height, height + 60);
  });
}
