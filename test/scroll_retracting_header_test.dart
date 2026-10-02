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
  testWidgets('a few wheel pixels start a complete short animation', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 600);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    final body = find.byKey(_body);
    final element = tester.element(body);
    await _wheel(tester, 4);
    expect(tester.getTopLeft(body).dy, 80);
    await _wheel(tester, 4);
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.getTopLeft(body).dy, inExclusiveRange(0, 80));
    await tester.pump(const Duration(milliseconds: 68));
    expect(tester.getTopLeft(body).dy, 0);
    expect(controller.offset, 608);
    expect(find.byKey(_header).hitTestable(), findsNothing);
    expect(tester.element(body), same(element));

    // Revealing is distance-only, even with very slow input.
    await _wheel(tester, -3, elapsed: const Duration(milliseconds: 100));
    expect(tester.getTopLeft(body).dy, 0);
    await _wheel(tester, -3, elapsed: const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.getTopLeft(body).dy, inExclusiveRange(0, 80));
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.getTopLeft(body).dy, 80);
    expect(controller.offset, 602);
    expect(tester.element(body), same(element));
  });

  testWidgets('slow wheel movement never accumulates into a hide', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 600);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    for (var i = 0; i < 12; i++) {
      await _wheel(tester, 2, elapsed: const Duration(milliseconds: 100));
      expect(tester.getTopLeft(find.byKey(_body)).dy, 80);
    }
    expect(controller.offset, 624);
    await _wheel(tester, 6);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(find.byKey(_body)).dy, 0);
  });

  testWidgets(
    'direction changes discard tiny movements and reverse animations',
    (tester) async {
      final controller = ScrollController(initialScrollOffset: 600);
      addTearDown(controller.dispose);
      await _mount(tester, controller: controller);
      final body = find.byKey(_body);
      for (var i = 0; i < 4; i++) {
        await _wheel(tester, 4);
        await _wheel(tester, -4);
        expect(tester.getTopLeft(body).dy, 80);
      }
      await _wheel(tester, 8);
      await tester.pump(const Duration(milliseconds: 32));
      final partial = tester.getTopLeft(body).dy;
      expect(partial, inExclusiveRange(0, 80));
      await _wheel(tester, -6);
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.getTopLeft(body).dy, greaterThan(partial));
      await tester.pump(const Duration(milliseconds: 108));
      expect(tester.getTopLeft(body).dy, 80);
    },
  );

  for (final reverse in [false, true]) {
    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.trackpad]) {
      testWidgets(
        'slow $kind keeps the header visible then fast input hides (reverse: $reverse)',
        (tester) async {
          final controller = ScrollController(initialScrollOffset: 600);
          addTearDown(controller.dispose);
          await _mount(tester, controller: controller, reverse: reverse);
          final body = find.byKey(_body);
          final location = tester.getCenter(body);
          final gesture = await tester.createGesture(kind: kind);
          if (kind == PointerDeviceKind.trackpad) {
            await gesture.panZoomStart(location);
          } else {
            await gesture.down(location);
          }
          var time = Duration.zero;
          var pan = 0.0;
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

          // Cross gesture slop slowly, then continue well beyond the distance
          // trigger at low velocity. Neither should retract the header.
          await move(-30, const Duration(seconds: 1));
          for (var i = 0; i < 8; i++) {
            await move(-2, const Duration(milliseconds: 100));
            expect(tester.getTopLeft(body).dy, 80);
          }
          await move(-8, const Duration(milliseconds: 16));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.getTopLeft(body).dy, 0);
          // A slow reversal reveals after just a few pixels.
          await move(6, const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 140));
          expect(tester.getTopLeft(body).dy, 80);
          if (kind == PointerDeviceKind.trackpad) {
            await gesture.panZoomEnd(timeStamp: time);
          } else {
            await gesture.cancel();
          }
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets(
    'visible header buttons accept taps during animation within their bounds',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var taps = 0;
      await _mount(tester, onHeaderPressed: () => taps++);
      final body = find.byKey(_body);
      await _wheel(tester, 8);
      await tester.pump(const Duration(milliseconds: 24));
      var visibleHeight = tester.getTopLeft(body).dy;
      expect(visibleHeight, inExclusiveRange(0, 80));
      await tester.tapAt(Offset(195, visibleHeight / 2));
      expect(taps, 1);
      await tester.tapAt(Offset(195, visibleHeight + 1));
      expect(taps, 1);
      await tester.pumpAndSettle();
      expect(find.byType(DButton).hitTestable(), findsNothing);
      await tester.tapAt(const Offset(195, 1));
      expect(taps, 1);
      await _wheel(tester, -6);
      await tester.pump(const Duration(milliseconds: 48));
      visibleHeight = tester.getTopLeft(body).dy;
      expect(visibleHeight, inExclusiveRange(0, 80));
      await tester.tapAt(Offset(195, visibleHeight / 2));
      expect(taps, 2);
      await tester.pumpAndSettle();
    },
  );

  for (final reverse in [false, true]) {
    testWidgets(
      'optional bottom reveal stays visible through viewport changes (reverse: $reverse)',
      (tester) async {
        final controller = ScrollController(initialScrollOffset: 600);
        addTearDown(controller.dispose);
        await _mount(
          tester,
          controller: controller,
          reverse: reverse,
          revealHeaderAtEnd: true,
        );
        final body = find.byKey(_body);
        await _wheel(tester, 100);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(body).dy, 0);

        controller.jumpTo(
          reverse ? 5 : controller.position.maxScrollExtent - 5,
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(body).dy, 0);
        await _wheel(tester, 1);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(body).dy, 80);

        // Header/dock reappearance changes the available viewport. Continuing
        // the same downward intent must not immediately retract the title.
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

        await _wheel(tester, -200);
        await tester.pumpAndSettle();
        await _wheel(tester, 60);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(body).dy, 0);
        await _wheel(tester, 10000);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(body).dy, 120);

        // Programmatic restoration starts a new reading position.
        controller.jumpTo(600);
        await tester.pumpAndSettle();
        await _wheel(tester, 60);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(body).dy, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('bottom reveal remains opt-in (reverse: $reverse)', (
      tester,
    ) async {
      final controller = ScrollController(initialScrollOffset: 600);
      addTearDown(controller.dispose);
      await _mount(tester, controller: controller, reverse: reverse);
      await _wheel(tester, 10000);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_body)).dy, 0);
    });

    testWidgets(
      'reaching the physical top reveals below the trigger (reverse: $reverse)',
      (tester) async {
        final controller = ScrollController(initialScrollOffset: 600);
        addTearDown(controller.dispose);
        await _mount(tester, controller: controller, reverse: reverse);
        final body = find.byKey(_body);
        await _wheel(tester, 8);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(body).dy, 0);
        controller.jumpTo(
          reverse ? controller.position.maxScrollExtent - 1 : 1,
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(body).dy, 0);
        await _wheel(tester, -1);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(body).dy, 80);
      },
    );
  }

  testWidgets(
    'restoration stays visible and identity resets an in-flight animation',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _mount(tester, controller: controller);
      final body = find.byKey(_body);
      controller.jumpTo(400);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(body).dy, 80);
      await _wheel(tester, 8);
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.getTopLeft(body).dy, inExclusiveRange(0, 80));
      await _mount(tester, controller: controller, identity: 'another feed');
      expect(tester.getTopLeft(body).dy, 80);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getTopLeft(body).dy, 80);
    },
  );

  testWidgets('header height changes retain a complete hide and reveal', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 600);
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    final body = find.byKey(_body);
    await _wheel(tester, 8);
    await tester.pumpAndSettle();
    await _mount(tester, controller: controller, headerHeight: 120);
    expect(tester.getTopLeft(body).dy, 0);
    await _wheel(tester, -6);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(body).dy, 120);
  });

  testWidgets('reduced motion switches completely after the same trigger', (
    tester,
  ) async {
    await _mount(tester, reducedMotion: true);
    final body = find.byKey(_body);
    await _wheel(tester, 4);
    expect(tester.getTopLeft(body).dy, 80);
    await _wheel(tester, 4);
    expect(tester.getTopLeft(body).dy, 0);
    await _wheel(tester, -6);
    expect(tester.getTopLeft(body).dy, 80);
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
