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
      testWidgets('$kind moves both bars by distance (reverse: $reverse)', (
        tester,
      ) async {
        final controller = ScrollController(initialScrollOffset: 400);
        addTearDown(controller.dispose);
        await _mount(tester, controller: controller, reverse: reverse);
        final drag = await _Drag.start(tester, kind: kind);
        await drag.move(-30, const Duration(seconds: 1));
        await drag.move(-80, const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        _expectHidden(tester);
        await tester.pump(const Duration(milliseconds: 500));
        await drag.move(120, const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        _expectShown(tester);
        await drag.cancel();
      });
    }
    for (final floating in [false, true]) {
      testWidgets(
        'chrome motion preserves the post anchor (reverse: $reverse, floating: $floating)',
        (tester) async {
          final controller = ScrollController(initialScrollOffset: 400);
          addTearDown(controller.dispose);
          await _mount(
            tester,
            controller: controller,
            reverse: reverse,
            floating: floating,
          );
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: tester.getCenter(find.byKey(_body)),
              scrollDelta: const Offset(0, 80),
            ),
          );
          await tester.pump();
          final anchor = tester.getTopLeft(find.byKey(_content));
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              tester.getTopLeft(find.byKey(_content)).dy,
              closeTo(anchor.dy, .01),
            );
          }
          _expectHidden(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'top reveals and navigation resets a panel (reverse: $reverse)',
      (tester) async {
        final controller = ScrollController(initialScrollOffset: 400);
        addTearDown(controller.dispose);
        await _mount(tester, controller: controller, reverse: reverse);
        await _wheel(tester, 80);
        _expectHidden(tester);
        controller.jumpTo(
          reverse ? controller.position.maxScrollExtent - 1 : 1,
        );
        await tester.pumpAndSettle();
        await _wheel(tester, -1);
        _expectShown(tester);
        controller.jumpTo(400);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 500));
        await _wheel(tester, 80);
        _expectHidden(tester);
        await _mount(
          tester,
          controller: controller,
          reverse: reverse,
          identity: 'next page',
        );
        _expectShown(tester);
      },
    );
  }
  testWidgets('coupled header and dock reverse the same partial progress', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 400);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    final drag = await _Drag.start(tester);
    await drag.move(-30, const Duration(seconds: 1));
    await drag.move(-40, const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 40));
    void matching() {
      final rect = tester.getRect(find.byKey(_body));
      final shown = rect.top / 80;
      expect(shown, inExclusiveRange(0, 1));
      expect((600 - rect.bottom) / 60, closeTo(shown, .001));
    }

    matching();
    await drag.move(60, const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    matching();
    await tester.pumpAndSettle();
    _expectShown(tester);
    await drag.cancel();
  });
  for (final floating in [false, true]) {
    testWidgets(
      'short content keeps navigation reachable (floating: $floating)',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await _mount(
          tester,
          controller: controller,
          floating: floating,
          contentHeight: 750,
        );
        await _wheel(tester, 80);
        _expectShown(tester);
      },
    );
  }
  for (final header in [false, true]) {
    testWidgets(
      'focused ${header ? 'header' : 'dock'} action prevents retraction',
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
        await _wheel(tester, 80);
        _expectShown(tester);
        expect(focus.hasFocus, true);
      },
    );
  }
  testWidgets('composer Send remains reachable as its header retracts', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 400);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller, keepActionVisible: true);
    await _wheel(tester, 80);
    expect(find.byKey(_header).hitTestable(), findsNothing);
    expect(find.text('Send').hitTestable(), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await _wheel(tester, -120);
    _expectShown(tester);
  });
  testWidgets('disabling the policy restores chrome and keeps scrolling', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 400);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    await _wheel(tester, 80);
    _expectHidden(tester);
    await _mount(tester, controller: controller, enabled: false);
    _expectShown(tester);
    final offset = controller.offset;
    await _wheel(tester, 100);
    expect(controller.offset, offset + 100);
    _expectShown(tester);
  });
  testWidgets('reduced motion settles both bars without animated geometry', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 400);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller, reducedMotion: true);
    await _wheel(tester, 80);
    _expectHidden(tester);
    expect(tester.hasRunningAnimations, false);
    await tester.pump(const Duration(milliseconds: 500));
    await _wheel(tester, -120);
    _expectShown(tester);
    expect(tester.hasRunningAnimations, false);
  });
  for (final header in [false, true]) {
    testWidgets(
      'focus acquired during motion reveals both bars (header: $header)',
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
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(find.byKey(_body)),
            scrollDelta: const Offset(0, 40),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        expect(
          tester.getTopLeft(find.byKey(_body)).dy,
          inExclusiveRange(0, 80),
        );
        focus.requestFocus();
        await tester.pumpAndSettle();
        _expectShown(tester);
        expect(focus.hasFocus, true);
      },
    );
  }
}
