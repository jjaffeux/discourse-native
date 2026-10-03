import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/mobile_scroll_dock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _body = ValueKey('body');
const _header = ValueKey('header');
const _dock = ValueKey('dock');
const _content = ValueKey('content');

Future<void> _mount(
  WidgetTester tester, {
  required ScrollController controller,
  bool reverse = false,
  bool floating = false,
  bool reducedMotion = false,
  bool keepActionVisible = false,
  bool enabled = true,
  Object identity = 'page',
  double contentHeight = 5000,
  FocusNode? headerFocus,
  FocusNode? footerFocus,
}) async {
  final header = SizedBox(
    key: _header,
    height: 80,
    child: DButton(
      focusNode: headerFocus,
      onPressed: () {},
      label: const Text('Header'),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: MobileScrollDock(
          identity: identity,
          hideOnScroll: enabled,
          keepActionVisible: keepActionVisible,
          dockBuilder: (hidden) => SizedBox(
            key: _dock,
            height: keepActionVisible && hidden ? 30 : 60,
            child: DButton(
              focusNode: footerFocus,
              onPressed: () {},
              label: Text(keepActionVisible ? 'Send' : 'Navigation'),
            ),
          ),
          body: floating
              ? DPageSurface.scrollable(
                  framed: false,
                  hideHeaderOnScroll: true,
                  header: header,
                  bodyBuilder: (_, geometry) => CustomScrollView(
                    key: _body,
                    controller: controller,
                    reverse: reverse,
                    slivers: [
                      SliverToBoxAdapter(child: geometry.spacer),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          key: _content,
                          height: contentHeight - 80,
                        ),
                      ),
                    ],
                  ),
                )
              : DPageSurface(
                  framed: false,
                  hideHeaderOnScroll: true,
                  header: header,
                  child: ListView(
                    key: _body,
                    controller: controller,
                    reverse: reverse,
                    padding: EdgeInsets.zero,
                    children: [SizedBox(key: _content, height: contentHeight)],
                  ),
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectShown(WidgetTester tester) {
  expect(find.byKey(_header).hitTestable(), findsOneWidget);
  expect(find.byKey(_dock).hitTestable(), findsOneWidget);
}

void _expectHidden(WidgetTester tester) {
  expect(find.byKey(_header).hitTestable(), findsNothing);
  expect(find.byKey(_dock), findsNothing);
}

class _Drag {
  _Drag(this.tester, this.gesture, this.kind, this.location);
  final WidgetTester tester;
  final TestGesture gesture;
  final PointerDeviceKind kind;
  final Offset location;
  Duration time = Duration.zero;
  double pan = 0;

  static Future<_Drag> start(
    WidgetTester tester, {
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) async {
    final location = tester.getCenter(find.byKey(_body));
    final gesture = await tester.createGesture(kind: kind);
    if (kind == PointerDeviceKind.trackpad) {
      await gesture.panZoomStart(location);
    } else {
      await gesture.down(location);
    }
    return _Drag(tester, gesture, kind, location);
  }

  Future<void> move(double dy, Duration elapsed) async {
    time += elapsed;
    await tester.pump(elapsed);
    if (kind == PointerDeviceKind.trackpad) {
      pan += dy;
      await gesture.panZoomUpdate(
        location,
        pan: Offset(0, pan),
        timeStamp: time,
      );
    } else {
      await gesture.moveBy(Offset(0, dy), timeStamp: time);
    }
    await tester.pump();
  }

  Future<void> cancel() async {
    if (kind == PointerDeviceKind.trackpad) {
      await gesture.panZoomEnd(timeStamp: time);
    } else {
      await gesture.cancel(timeStamp: time);
    }
    await tester.pumpAndSettle();
  }
}

Future<void> _wheel(WidgetTester tester, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(find.byKey(_body)),
      scrollDelta: Offset(0, delta),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final reverse in [false, true]) {
    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.trackpad]) {
      testWidgets('slow $kind reads stay visible; acceleration hides both '
          '(reverse: $reverse)', (tester) async {
        final controller = ScrollController(initialScrollOffset: 2000);
        addTearDown(controller.dispose);
        await _mount(tester, controller: controller, reverse: reverse);
        final drag = await _Drag.start(tester, kind: kind);
        await drag.move(-30, const Duration(seconds: 1));
        for (var i = 0; i < 40; i++) {
          await drag.move(-10, const Duration(milliseconds: 100));
          _expectShown(tester);
        }
        expect((controller.offset - 2000).abs(), greaterThan(400));
        await drag.move(-20, const Duration(milliseconds: 16));
        await tester.pumpAndSettle();
        _expectHidden(tester);
        await drag.move(5, const Duration(milliseconds: 100));
        _expectHidden(tester);
        await drag.move(5, const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        _expectShown(tester);
        await drag.cancel();
      });
    }
  }

  for (final reverse in [false, true]) {
    for (final floating in [false, true]) {
      testWidgets('chrome animation preserves the reading anchor '
          '(reverse: $reverse, floating: $floating)', (tester) async {
        final controller = ScrollController(initialScrollOffset: 2000);
        addTearDown(controller.dispose);
        await _mount(
          tester,
          controller: controller,
          reverse: reverse,
          floating: floating,
        );
        final drag = await _Drag.start(tester);
        await drag.move(-80, const Duration(milliseconds: 80));
        final anchor = tester.getTopLeft(find.byKey(_content)).dy;
        await tester.pump(const Duration(milliseconds: 32));
        expect(
          tester.getTopLeft(find.byKey(_content)).dy,
          closeTo(anchor, .01),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byKey(_content)).dy,
          closeTo(anchor, .01),
        );
        _expectHidden(tester);
        await drag.move(10, const Duration(milliseconds: 20));
        final restoredAnchor = tester.getTopLeft(find.byKey(_content)).dy;
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byKey(_content)).dy,
          closeTo(restoredAnchor, .01),
        );
        _expectShown(tester);
        await drag.cancel();
      });
    }
  }

  for (final hz in [60, 120]) {
    for (final velocity in [150.0, 240.0]) {
      testWidgets('$velocity pixels/second has the same outcome at $hz Hz', (
        tester,
      ) async {
        final controller = ScrollController(initialScrollOffset: 400);
        addTearDown(controller.dispose);
        await _mount(tester, controller: controller);
        final drag = await _Drag.start(tester);
        await drag.move(-30, const Duration(seconds: 1));
        final frame = Duration(microseconds: (1000000 / hz).round());
        for (var i = 0; i < hz ~/ 3; i++) {
          await drag.move(-velocity * frame.inMicroseconds / 1000000, frame);
        }
        await tester.pumpAndSettle();
        if (velocity < 180) {
          _expectShown(tester);
        } else {
          _expectHidden(tester);
        }
        await drag.cancel();
      });
    }
  }

  testWidgets('pause, reversal and slow input discard pending hide distance', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 400);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    final drag = await _Drag.start(tester);
    await drag.move(-30, const Duration(seconds: 1));
    await drag.move(-12, const Duration(milliseconds: 16));
    await drag.move(-4, const Duration(milliseconds: 200));
    _expectShown(tester);
    for (var i = 0; i < 6; i++) {
      await drag.move(-8, const Duration(milliseconds: 16));
      await drag.move(8, const Duration(milliseconds: 16));
      _expectShown(tester);
    }
    await drag.move(-12, const Duration(milliseconds: 16));
    await drag.move(-1, const Duration(milliseconds: 100));
    await drag.move(-4, const Duration(milliseconds: 16));
    _expectShown(tester);
    await drag.move(-20, const Duration(milliseconds: 16));
    await tester.pumpAndSettle();
    _expectHidden(tester);
    await drag.cancel();
  });

  testWidgets('a fresh drag does not inherit pending distance', (tester) async {
    final controller = ScrollController(initialScrollOffset: 400);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    for (var i = 0; i < 2; i++) {
      final drag = await _Drag.start(tester);
      await drag.move(-30, const Duration(seconds: 1));
      await drag.move(-12, const Duration(milliseconds: 16));
      await drag.cancel();
      _expectShown(tester);
    }
  });

  testWidgets(
    'ballistic scrolling cannot initiate a hide after a short flick',
    (tester) async {
      final controller = ScrollController(initialScrollOffset: 400);
      addTearDown(controller.dispose);
      await _mount(tester, controller: controller);
      final drag = await _Drag.start(tester);
      await drag.move(-30, const Duration(seconds: 1));
      for (var i = 0; i < 3; i++) {
        await drag.move(-3, const Duration(milliseconds: 8));
      }
      final releaseOffset = controller.offset;
      // Supply release velocity explicitly: fling recognition below 16 pixels
      // varies by platform. Keep the real user direction and scroll simulation.
      (controller.position as ScrollPositionWithSingleContext).goBallistic(800);
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(releaseOffset));
      _expectShown(tester);
      await drag.cancel();
    },
  );

  testWidgets('both bars share animation progress and reverse together', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 400);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    final drag = await _Drag.start(tester);
    await drag.move(-80, const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 32));
    void expectMatchingProgress() {
      final rect = tester.getRect(find.byKey(_body));
      final header = rect.top / 80;
      final footer = (600 - rect.bottom) / 60;
      expect(header, inExclusiveRange(0, 1));
      expect(footer, closeTo(header, .001));
    }

    expectMatchingProgress();
    await drag.move(10, const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 32));
    expectMatchingProgress();
    await tester.pumpAndSettle();
    _expectShown(tester);
    await drag.cancel();
  });

  for (final floating in [false, true]) {
    testWidgets('short content and two-screen cutoff stay stable '
        '(floating: $floating)', (tester) async {
      final controller = ScrollController(initialScrollOffset: 100);
      addTearDown(controller.dispose);
      final viewport = floating ? 540.0 : 460.0;
      await _mount(
        tester,
        controller: controller,
        floating: floating,
        contentHeight: viewport * 1.99,
      );
      await _wheel(tester, 40);
      _expectShown(tester);
      await _mount(
        tester,
        controller: controller,
        floating: floating,
        contentHeight: viewport * 2,
      );
      await _wheel(tester, 40);
      _expectHidden(tester);
      await _wheel(tester, 40);
      _expectHidden(tester);
      await _wheel(tester, 10000);
      _expectShown(tester);
      await _wheel(tester, 40);
      _expectShown(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('near the top and after navigation both bars stay visible', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    await _wheel(tester, 40);
    _expectShown(tester);
    await _wheel(tester, 120);
    _expectHidden(tester);
    await _mount(tester, controller: controller, identity: 'next');
    _expectShown(tester);
    await _wheel(tester, 120);
    _expectHidden(tester);
    await _wheel(tester, -10000);
    _expectShown(tester);
  });

  for (final header in [false, true]) {
    testWidgets(
      'a focused ${header ? 'header' : 'footer'} keeps both reachable',
      (tester) async {
        final controller = ScrollController(initialScrollOffset: 400);
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        await _mount(
          tester,
          controller: controller,
          headerFocus: header ? focus : null,
          footerFocus: header ? null : focus,
        );
        focus.requestFocus();
        await tester.pump();
        await _wheel(tester, 40);
        _expectShown(tester);
        expect(focus.hasFocus, isTrue);
      },
    );
  }

  testWidgets('composer Send stays reachable as navigation retracts', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 400);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller, keepActionVisible: true);
    await _wheel(tester, 40);
    expect(find.byKey(_header).hitTestable(), findsNothing);
    expect(find.text('Send').hitTestable(), findsOneWidget);
    await _wheel(tester, -10);
    _expectShown(tester);
  });

  testWidgets(
    'disabling the policy restores both bars and preserves scrolling',
    (tester) async {
      final controller = ScrollController(initialScrollOffset: 400);
      addTearDown(controller.dispose);
      await _mount(tester, controller: controller);
      await _wheel(tester, 40);
      _expectHidden(tester);
      await _mount(tester, controller: controller, enabled: false);
      _expectShown(tester);
      final offset = controller.offset;
      await _wheel(tester, 100);
      expect(controller.offset, offset + 100);
      _expectShown(tester);
    },
  );

  testWidgets(
    'reduced motion switches both bars without intermediate geometry',
    (tester) async {
      final controller = ScrollController(initialScrollOffset: 400);
      addTearDown(controller.dispose);
      await _mount(tester, controller: controller, reducedMotion: true);
      await _wheel(tester, 40);
      _expectHidden(tester);
      expect(tester.hasRunningAnimations, isFalse);
      await _wheel(tester, -10);
      _expectShown(tester);
      expect(tester.hasRunningAnimations, isFalse);
    },
  );
}
