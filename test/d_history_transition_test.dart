import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _page = ValueKey('live-page');
final _live = find.byKey(_page);

Rect _paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

Future<_HistoryHarnessState> _pump(
  WidgetTester tester, {
  TextDirection direction = TextDirection.ltr,
  bool reducedMotion = false,
  bool tabTransitions = false,
  bool roundedPanel = false,
  bool livePreviews = false,
  bool framed = false,
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
        livePreviews: livePreviews,
        framed: framed,
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
  Future<_SnapshotHarnessState> pumpSnapshot(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<_SnapshotHarnessState>();
    await tester.pumpWidget(MaterialApp(home: _SnapshotHarness(key: key)));
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  Widget? previousUnderlay(WidgetTester tester) =>
      tester.widget<DSheetViewport>(find.byType(DSheetViewport)).underlay;

  testWidgets(
    'previous underlay survives keyboard changes and reduced motion',
    (tester) async {
      final state = await pumpSnapshot(tester);
      state.visit(1);
      await tester.pumpAndSettle();
      expect(previousUnderlay(tester), isNotNull);
      for (final bottom in [300.0, 0.0]) {
        state.keyboard(bottom);
        await tester.pumpAndSettle();
        expect(previousUnderlay(tester), isNotNull);
      }
      final semantics = tester.ensureSemantics();
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
      );
      await drag.moveBy(const Offset(0, 90));
      await tester.pump();
      expect(find.bySemanticsLabel('Source action'), findsNothing);
      expect(find.widgetWithText(DButton, 'Source action'), findsNothing);
      await drag.cancel();
      await tester.pumpAndSettle();
      expect(state.entry, 1);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  for (final invalidation in [
    'history',
    'owner',
    'theme',
    'width',
    'padding',
    'memory',
  ]) {
    testWidgets('previous underlay clears safely on $invalidation', (
      tester,
    ) async {
      final state = await pumpSnapshot(tester);
      state.visit(1);
      await tester.pumpAndSettle();
      expect(previousUnderlay(tester), isNotNull);
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
      );
      await drag.moveBy(const Offset(0, 90));
      await tester.pump();
      switch (invalidation) {
        case 'history':
          state.resetHistory();
        case 'owner':
          state.changeOwner();
        case 'theme':
          state.changeTheme();
        case 'width':
          await tester.binding.setSurfaceSize(const Size(450, 600));
        case 'padding':
          state.changePadding();
        case 'memory':
          tester.binding.handleMemoryPressure();
      }
      await tester.pumpAndSettle();
      expect(previousUnderlay(tester), isNull);
      await drag.cancel();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('previous underlay uses only the bounded adjacent entry cache', (
    tester,
  ) async {
    final state = await pumpSnapshot(tester);
    for (var entry = 1; entry <= 10; entry++) {
      state.visit(entry);
      await tester.pumpAndSettle();
      expect(previousUnderlay(tester), isNotNull);
    }
    state.visit(1);
    await tester.pumpAndSettle();
    expect(previousUnderlay(tester), isNull);
    state.visit(9);
    await tester.pumpAndSettle();
    expect(previousUnderlay(tester), isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    for (final livePreviews in [false, true]) {
      testWidgets(
        '${livePreviews ? 'live' : 'snapshot'} previews grow with back and '
        'forward swipes in $direction',
        (tester) async {
          final state = await _pump(
            tester,
            direction: direction,
            livePreviews: livePreviews,
            framed: true,
          );
          state.visit(1);
          await tester.pumpAndSettle();
          final pageRect = _paintedRect(tester, _live);
          final header = tester.getRect(find.text('Header action'));
          final footer = tester.getRect(find.text('Footer action'));

          // Forward swipes have no live preview; they always use a snapshot.
          for (final back in [true, if (!livePreviews) false]) {
            final fromRight = back
                ? direction == TextDirection.rtl
                : direction != TextDirection.rtl;
            final sign = fromRight ? -1.0 : 1.0;
            final preview = livePreviews
                ? find.descendant(
                    of: find.byKey(const ValueKey('history-previous-preview')),
                    matching: find.byType(DPageSurface),
                  )
                : find.byType(RawImage);
            final initialIndex = state.index;
            var distance = 100.0;
            final gesture = await _drag(
              tester,
              fromRight: fromRight,
              distance: distance,
            );

            Rect previewRect() => _paintedRect(tester, preview);
            void expectChromeUnchanged() {
              expect(tester.getRect(find.text('Header action')), header);
              expect(tester.getRect(find.text('Footer action')), footer);
              if (back) {
                expect(_paintedRect(tester, _live).size, pageRect.size);
              }
            }

            void expectBackgroundInsideViewport() {
              final background = back
                  ? previewRect()
                  : _paintedRect(tester, _live);
              expect(
                background.left,
                greaterThanOrEqualTo(pageRect.left - .001),
              );
              expect(
                background.right,
                lessThanOrEqualTo(pageRect.right + .001),
              );
              expect(
                direction == TextDirection.ltr
                    ? background.left
                    : background.right,
                closeTo(
                  direction == TextDirection.ltr
                      ? pageRect.left
                      : pageRect.right,
                  .001,
                ),
              );
            }

            final smaller = previewRect();
            expect(smaller.width / pageRect.width, inExclusiveRange(.94, 1));
            expect(
              smaller.height / pageRect.height,
              closeTo(smaller.width / pageRect.width, .001),
            );
            expect(smaller.center.dy, closeTo(pageRect.center.dy, .001));
            expectChromeUnchanged();
            expectBackgroundInsideViewport();

            await gesture.moveBy(Offset(sign * 140, 0));
            distance += 140;
            await tester.pump();
            final larger = previewRect();
            expect(larger.width, greaterThan(smaller.width));
            expect(larger.width, lessThan(pageRect.width));
            expectBackgroundInsideViewport();

            // Reversing the finger reverses the scale immediately.
            await gesture.moveBy(Offset(-sign * 80, 0));
            distance -= 80;
            await tester.pump();
            expect(
              previewRect().width,
              inExclusiveRange(smaller.width, larger.width),
            );
            expectChromeUnchanged();
            expectBackgroundInsideViewport();

            // The preview exactly meets the live route before navigation fires.
            await gesture.moveBy(Offset(sign * (pageRect.width - distance), 0));
            await tester.pump();
            final full = previewRect();
            expect(full.left, closeTo(pageRect.left, .001));
            expect(full.top, closeTo(pageRect.top, .001));
            expect(full.width, closeTo(pageRect.width, .001));
            expect(full.height, closeTo(pageRect.height, .001));
            expectBackgroundInsideViewport();
            expect(state.index, initialIndex);
            await gesture.up();
            await tester.pumpAndSettle();
            expect(state.index, back ? 0 : 1);
            expect(_paintedRect(tester, _live), pageRect);
          }
          expect(state.swipes, livePreviews ? 1 : 2);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('frame edges navigate without moving chrome in $direction', (
      tester,
    ) async {
      final state = await _pump(tester, direction: direction, framed: true);
      state.visit(1);
      await tester.pumpAndSettle();
      final header = find.text('Header action');
      final footer = find.text('Footer action');
      final headerRect = tester.getRect(header);
      final footerRect = tester.getRect(footer);
      final page = tester.getRect(_live);
      final rtl = direction == TextDirection.rtl;
      for (final y in [1.0, page.center.dy, 599.0]) {
        for (final back in [true, false]) {
          final fromRight = back ? rtl : !rtl;
          final gesture = await tester.startGesture(
            Offset(fromRight ? 399 : 1, y),
          );
          await gesture.moveBy(
            Offset(fromRight ? -140 : 140, 0),
            timeStamp: const Duration(milliseconds: 200),
          );
          await tester.pump();
          final live = _paintedRect(tester, _live);
          expect(
            rtl ? live.right - page.right : live.left - page.left,
            closeTo(back ? (rtl ? -140 : 140) : 0, .001),
          );
          expect(tester.getRect(header), headerRect);
          expect(tester.getRect(footer), footerRect);
          final preview = tester.widget<RawImage>(find.byType(RawImage)).image!;
          expect(
            preview.width / preview.height,
            closeTo(page.width / page.height, .003),
          );
          await gesture.up();
          await tester.pumpAndSettle();
          expect(state.index, back ? 0 : 1);
        }
      }
      expect(state.swipes, 6);
      expect(state.chromeTaps, 0);
      await tester.tap(header);
      await tester.tap(footer);
      expect(state.chromeTaps, 2);
      expect(tester.takeException(), isNull);
    });

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
      final backWidth = _paintedRect(tester, find.byType(RawImage)).width;
      expect(find.text('Page 0'), findsNothing);
      expect(find.byKey(_page), findsOneWidget);
      await back.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(state.index, 1);
      expect((tester.getTopLeft(_live).dx - origin.dx).abs(), greaterThan(140));
      expect(
        _paintedRect(tester, find.byType(RawImage)).width,
        inExclusiveRange(backWidth, 400),
      );
      await tester.pumpAndSettle();
      expect(state.index, 0);
      expect(state.swipes, 1);
      expect(tester.getTopLeft(_live), origin);

      final forward = await _drag(tester, fromRight: !rtl);
      expect(state.index, 0);
      final background = _paintedRect(tester, _live);
      expect(
        rtl ? background.right : background.left,
        closeTo(rtl ? 400 : 0, .001),
      );
      expect(background.width, inExclusiveRange(400 * .94, 400));
      expect(find.byType(RawImage), findsOneWidget);
      final forwardWidth = _paintedRect(tester, find.byType(RawImage)).width;
      await forward.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        _paintedRect(tester, find.byType(RawImage)).width,
        inExclusiveRange(forwardWidth, 400),
      );
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

  testWidgets('a live previous preview is ready on first reveal and inert', (
    tester,
  ) async {
    final state = await _pump(tester, livePreviews: true);
    state.visit(1);
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    try {
      expect(find.text('Previous preview'), findsNothing);
      final preview = find.text('Previous preview', skipOffstage: false);
      final element = tester.element(preview);
      state.previewFocus.requestFocus();
      await tester.pump();
      expect(state.previewFocus.hasFocus, isFalse);

      final back = await _drag(tester, distance: 260);
      expect(find.text('Previous preview'), findsOneWidget);
      expect(tester.element(preview), same(element));
      expect(find.byType(RawImage), findsNothing);
      expect(find.bySemanticsLabel('Previous preview'), findsNothing);
      await tester.tapAt(tester.getCenter(preview));
      expect(state.previewTaps, 0);
      await back.cancel();
      await tester.pumpAndSettle();
      expect(find.text('Previous preview'), findsNothing);
      expect(tester.element(preview), same(element));
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('short drags and pointer cancellation restore the live page', (
    tester,
  ) async {
    final state = await _pump(tester);
    state.visit(1);
    await tester.pumpAndSettle();
    for (final cancel in [false, true]) {
      final gesture = await _drag(tester, distance: cancel ? 140 : 60);
      expect(tester.getTopLeft(_live).dx, greaterThan(0));
      final previewWidth = _paintedRect(tester, find.byType(RawImage)).width;
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        _paintedRect(tester, find.byType(RawImage)).width,
        lessThan(previewWidth),
      );
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
    final state = await _pump(tester, reducedMotion: true, livePreviews: true);
    state.visit(1);
    await tester.pumpAndSettle();
    final gesture = await _drag(tester);
    expect(tester.getTopLeft(_live).dx, 0);
    expect(_paintedRect(tester, _live).size, const Size(400, 600));
    expect(find.text('Previous preview'), findsNothing);
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

  testWidgets('backgrounding cancels an edge swipe and retains its preview', (
    tester,
  ) async {
    final state = await _pump(tester);
    state.visit(1);
    await tester.pumpAndSettle();
    final gesture = await _drag(tester);
    expect(find.byType(RawImage), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await gesture.up();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(state.swipes, 0);
    expect(tester.getTopLeft(_live).dx, 0);
    expect(find.byType(RawImage), findsNothing);
    final resumedGesture = await _drag(tester);
    expect(find.byType(RawImage), findsOneWidget);
    await resumedGesture.up();
    await tester.pumpAndSettle();
    expect(state.index, 0);
    expect(state.swipes, 1);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets(
      'ordered tabs use a short directional crossfade in $direction',
      (tester) async {
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
          expect((incoming - outgoing).abs(), closeTo(24, .001));
          final fade = tester.widget<Opacity>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('history-incoming-tab')),
                  matching: find.byType(Opacity),
                )
                .first,
          );
          expect(fade.opacity, inExclusiveRange(0, 1));
          expect(find.byKey(_page), findsOneWidget);
          expect(find.byType(RawImage), findsOneWidget);
          expect(find.text('Page $tab'), findsOneWidget);
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(_live).dx, 0);
          expect(find.byType(RawImage), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('the selected tab moved among the others, as when tabs are '
      'reordered, neither slides nor holds the page', (tester) async {
    final state = await _pump(tester, tabTransitions: true);
    state.moveTab(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(find.byKey(const ValueKey('history-incoming-tab')), findsNothing);
    expect(find.byKey(const ValueKey('history-outgoing-tab')), findsNothing);
    expect(find.byType(RawImage), findsNothing);
    expect(_live.hitTestable(), findsOneWidget);
    // Another tab from there slides towards its index still.
    state.selectTab(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final incoming = tester
        .widget<Transform>(find.byKey(const ValueKey('history-incoming-tab')))
        .transform
        .getTranslation()
        .x;
    expect(incoming, lessThan(0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    for (final livePreviews in [false, true]) {
      testWidgets(
        '${livePreviews ? 'live' : 'snapshot'} swipe backgrounds preserve '
        'rounded corners and gutters in $direction',
        (tester) async {
          final state = await _pump(
            tester,
            direction: direction,
            roundedPanel: true,
            livePreviews: livePreviews,
          );
          state.visit(1);
          await tester.pumpAndSettle();
          final rtl = direction == TextDirection.rtl;

          for (final back in [true, false]) {
            final gesture = await _drag(tester, fromRight: back ? rtl : !rtl);
            final background = back
                ? livePreviews
                      ? find.descendant(
                          of: find.byKey(
                            const ValueKey('history-previous-preview'),
                          ),
                          matching: find.byType(DPageSurface),
                        )
                      : find.byType(RawImage)
                : _live;
            final rect = _paintedRect(tester, background);
            // Snapshots include the transparent 16px gutter around the panel.
            final inset = back && !livePreviews ? rect.width / 400 * 16 : 0.0;
            final edge = rtl ? rect.right - inset : rect.left + inset;
            final sign = rtl ? -1.0 : 1.0;
            final corner = Offset(edge + sign, rect.top + 1);
            final gutter = Offset(edge - sign * 8, rect.top + 50);
            final body = Offset(edge + sign * 50, rect.top + 50);
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('history-test-boundary')),
            );
            final image = boundary.toImageSync(pixelRatio: 1);
            final pixels = await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
            );
            List<int> rgb(Offset point) {
              final local = boundary.globalToLocal(point);
              final offset =
                  (local.dy.floor() * image.width + local.dx.floor()) * 4;
              return List.generate(
                3,
                (channel) => pixels!.getUint8(offset + channel),
              );
            }

            expect(rgb(corner), [
              0,
              255,
              0,
            ], reason: 'rounded corner, back: $back');
            expect(rgb(gutter), [
              0,
              255,
              0,
            ], reason: 'outer gutter, back: $back');
            final bodyColor = rgb(body);
            expect(
              bodyColor[0],
              inExclusiveRange(0, 244),
              reason: 'page is dimmed',
            );
            expect(bodyColor[1], inExclusiveRange(0, 67));
            expect(bodyColor[2], inExclusiveRange(0, 54));
            image.dispose();
            await gesture.up();
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('tab fades keep solid page fills and transparent corners', (
    tester,
  ) async {
    final state = await _pump(tester, tabTransitions: true, roundedPanel: true);
    Future<void> expectPageColors({bool atRest = false}) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('history-test-boundary')),
      );
      final image = boundary.toImageSync(pixelRatio: 1);
      final pixels = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      expect(pixels, isNotNull);
      if (atRest) {
        expect(pixels!.getUint8(0), 0);
        expect(pixels.getUint8(1), 255);
        expect(pixels.getUint8(2), 0);
      }
      final center = (image.width * (image.height ~/ 2) + image.width ~/ 2) * 4;
      expect(
        List.generate(3, (channel) => pixels!.getUint8(center + channel)),
        [244, 67, 54],
        reason: 'Solid page fills must not reveal the green canvas mid-fade',
      );
      image.dispose();
    }

    await expectPageColors(atRest: true);
    for (final tab in [1, 0]) {
      state.selectTab(tab);
      await tester.pump();
      final snapshot = tester.widget<RawImage>(find.byType(RawImage)).image!;
      final pixels = await tester.runAsync(
        () => snapshot.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      expect(
        pixels!.getUint8(3),
        0,
        reason: 'Snapshot corners stay transparent',
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        await expectPageColors();
      }
      await tester.pumpAndSettle();
      await expectPageColors(atRest: true);
    }
  });

  testWidgets('tab changes take 300ms to settle', (tester) async {
    final state = await _pump(tester, tabTransitions: true);
    state.selectTab(1);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.byKey(const ValueKey('history-incoming-tab')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 121));
    await tester.pump();
    expect(find.byKey(const ValueKey('history-incoming-tab')), findsNothing);
    expect(tester.getTopLeft(_live).dx, 0);
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
      if (example.title == 'Live navigation preview') {
        expect(find.text('Return to page'), findsNothing);
        await tester.tap(find.text('Open navigation'));
        await tester.pumpAndSettle();
        expect(find.text('Return to page'), findsOneWidget);
        await tester.tap(find.text('Return to page'));
        await tester.pumpAndSettle();
        expect(find.text('Swipe to reveal navigation'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        continue;
      }
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
    this.livePreviews = false,
    this.framed = false,
  });
  final bool tabTransitions;
  final bool roundedPanel;
  final bool livePreviews;
  final bool framed;

  @override
  State<_HistoryHarness> createState() => _HistoryHarnessState();
}

class _HistoryHarnessState extends State<_HistoryHarness> {
  final scroll = ScrollController();
  final previewFocus = FocusNode();
  int previewTaps = 0;
  int chromeTaps = 0;
  Object history = Object();
  int index = 0;
  int furthest = 0;
  int swipes = 0;
  late DHistoryTab? tab = widget.tabTransitions ? (id: 0, index: 0) : null;
  Object tabOwner = Object();

  Widget _previewSurface(Widget child) => Padding(
    padding: EdgeInsets.symmetric(horizontal: widget.roundedPanel ? 16 : 0),
    child: DPageSurface(
      backgroundColor: widget.roundedPanel ? Colors.red : null,
      child: child,
    ),
  );

  void selectTab(int to) => setState(() {
    history = Object();
    tab = (id: to, index: to);
    index = to;
    furthest = to;
  });

  /// The selected tab stands at [at] among the tabs now, as when they are
  /// put in another order.
  void moveTab(int at) => setState(() => tab = (id: tab!.id, index: at));

  void changeOwner() => setState(() {
    tabOwner = Object();
    history = Object();
    tab = (id: 0, index: 0);
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
    previewFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const ValueKey('history-test-boundary'),
    child: ColoredBox(
      color: const Color(0xFF00FF00),
      child: DHistoryTransition(
        frameBuilder: widget.framed
            ? (context, page) => Column(
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: DButton(
                      label: const Text('Header action'),
                      onPressed: () => chromeTaps++,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: page,
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: DButton(
                      label: const Text('Footer action'),
                      onPressed: () => chromeTaps++,
                    ),
                  ),
                ],
              )
            : null,
        history: history,
        tab: tab,
        tabOwner: tabOwner,
        entry: index,
        previousEntry: index > 0 ? index - 1 : null,
        nextEntry: index < furthest ? index + 1 : null,
        previousPreview: widget.livePreviews && index > 0
            ? _previewSurface(
                Center(
                  child: DButton(
                    autofocus: true,
                    focusNode: previewFocus,
                    label: const Text('Previous preview'),
                    onPressed: () => previewTaps++,
                  ),
                ),
              )
            : null,

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
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: DPageSurface(
                  key: _page,
                  backgroundColor: Colors.red,
                  child: SizedBox.expand(),
                ),
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

class _SnapshotHarness extends StatefulWidget {
  const _SnapshotHarness({super.key});

  @override
  State<_SnapshotHarness> createState() => _SnapshotHarnessState();
}

class _SnapshotHarnessState extends State<_SnapshotHarness> {
  Object history = Object();
  Object owner = Object();
  int entry = 0;
  double keyboardBottom = 0;
  bool dark = false;
  bool topPadding = false;

  void visit(int value) => setState(() => entry = value);
  void keyboard(double bottom) => setState(() => keyboardBottom = bottom);
  void resetHistory() => setState(() => history = Object());
  void changeOwner() => setState(() => owner = Object());
  void changeTheme() => setState(() => dark = !dark);
  void changePadding() => setState(() => topPadding = !topPadding);

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    child: MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: true,
        viewInsets: EdgeInsets.only(bottom: keyboardBottom),
        padding: EdgeInsets.only(
          top: topPadding ? 20 : 0,
          bottom: keyboardBottom == 0 ? 34 : 0,
        ),
        viewPadding: const EdgeInsets.only(bottom: 34),
      ),
      child: DHistoryTransition(
        history: history,
        tabOwner: owner,
        entry: entry,
        previousEntry: entry == 0 ? null : entry - 1,
        child: Builder(
          builder: (context) => entry == 0
              ? Center(
                  child: DButton(
                    label: const Text('Source action'),
                    onPressed: () {},
                  ),
                )
              : DSheetViewport(
                  onDismiss: () => visit(entry - 1),
                  underlay: DHistoryTransition.previousPageUnderlayOf(context),
                  content: DSheetContent(
                    variant: DSheetVariant.page,
                    showCloseButton: false,
                    children: [Expanded(child: Text('Visit $entry'))],
                  ),
                ),
        ),
      ),
    ),
  );
}
