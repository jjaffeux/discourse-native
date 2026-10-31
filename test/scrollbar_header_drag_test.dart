import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in [
    (header: 0.0, content: 40000.0, rtl: false),
    (header: 80.0, content: 40000.0, rtl: false),
    (header: 160.0, content: 40000.0, rtl: false),
    (header: 160.0, content: 3000.0, rtl: false),
    (header: 160.0, content: 3000.0, rtl: true),
  ]) {
    testWidgets('mouse grip follows retracting header $scenario', (
      tester,
    ) async {
      final fixture = await _mount(
        tester,
        headerHeight: scenario.header,
        contentHeight: scenario.content,
        rtl: scenario.rtl,
      );
      final thumb = fixture.thumb;
      final origin = Offset(thumb.center.dx, thumb.top + thumb.height / 3);
      final gripOffset = origin.dy - thumb.top;
      final gesture = await tester.startGesture(
        origin,
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      expect(fixture.painter.padding.resolve(TextDirection.ltr).top, 0);
      expect(fixture.scroll.offset, greaterThan(1000));
      expect(
        fixture.thumb.top + gripOffset,
        closeTo(origin.dy + 200, 2),
        reason: 'The absolute point grabbed within the thumb follows the mouse',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the bottom grip point inside the viewport reaches topic end', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    final thumb = fixture.thumb;
    final origin = thumb.center;
    final gripOffset = origin.dy - thumb.top;
    final bounds = tester.getRect(fixture.paint);
    final bottomGrip = bounds.bottom - 2 - (thumb.height - gripOffset);
    final gesture = await tester.startGesture(
      origin,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(Offset(origin.dx, bottomGrip));
    await tester.pumpAndSettle();
    expect(fixture.scroll.position.extentAfter, closeTo(0, 1));
    expect(fixture.thumb.top + gripOffset, closeTo(bottomGrip, 2));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('stationary mouse keeps its grip while the header settles', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    final thumb = fixture.thumb;
    final origin = thumb.center;
    final gripOffset = origin.dy - thumb.top;
    final gesture = await tester.startGesture(
      origin,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      fixture.painter.padding.resolve(TextDirection.ltr).top,
      greaterThan(0),
    );
    await tester.pumpAndSettle();
    expect(fixture.thumb.top + gripOffset, closeTo(origin.dy + 30, 2));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse keeps its grip as reversal expands the moving header', (
    tester,
  ) async {
    final fixture = await _mount(tester, contentHeight: 3000);
    final thumb = fixture.thumb;
    final origin = thumb.center;
    final gripOffset = origin.dy - thumb.top;
    final gesture = await tester.startGesture(
      origin,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final retractingPadding = fixture.painter.padding
        .resolve(TextDirection.ltr)
        .top;
    expect(retractingPadding, inExclusiveRange(0, 160));
    await gesture.moveBy(const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(
      fixture.painter.padding.resolve(TextDirection.ltr).top,
      greaterThan(retractingPadding),
    );
    expect(fixture.thumb.top + gripOffset, closeTo(origin.dy + 20, 2));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rejected pointer cannot release the accepted thumb grip', (
    tester,
  ) async {
    final interceptPointer = ValueNotifier(true);
    addTearDown(interceptPointer.dispose);
    final fixture = await _mount(tester, interceptPointer: interceptPointer);
    final rejected = await tester.startGesture(
      fixture.thumb.center,
      kind: PointerDeviceKind.touch,
    );
    interceptPointer.value = false;
    await tester.pump();
    final thumb = fixture.thumb;
    final origin = thumb.center;
    final gripOffset = origin.dy - thumb.top;
    final accepted = await tester.startGesture(
      origin,
      kind: PointerDeviceKind.mouse,
    );
    await accepted.moveBy(const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 16));
    expect(fixture.scroll.offset, greaterThan(0));
    expect(
      fixture.painter.padding.resolve(TextDirection.ltr).top,
      greaterThan(0),
    );
    await rejected.up();
    await tester.pumpAndSettle();
    expect(fixture.thumb.top + gripOffset, closeTo(origin.dy + 30, 2));
    await accepted.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a large thumb preserves a grip near its leading edge', (
    tester,
  ) async {
    final fixture = await _mount(tester, contentHeight: 3000);
    final thumb = fixture.thumb;
    expect(thumb.height, greaterThan(16));
    final origin = Offset(thumb.center.dx, thumb.top + 3);
    final gesture = await tester.startGesture(
      origin,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(fixture.painter.padding.resolve(TextDirection.ltr).top, 0);
    expect(fixture.thumb.top + 3, closeTo(origin.dy + 200, 2));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final cancel in [false, true]) {
    testWidgets(
      'header animation cannot scroll after mouse ${cancel ? 'cancel' : 'up'}',
      (tester) async {
        final fixture = await _mount(tester);
        final gesture = await tester.startGesture(
          fixture.thumb.center,
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          fixture.painter.padding.resolve(TextDirection.ltr).top,
          greaterThan(0),
        );
        if (cancel) {
          await gesture.cancel();
        } else {
          final beforeLastInput = fixture.scroll.offset;
          await gesture.moveBy(const Offset(0, 5));
          await gesture.up();
          expect(fixture.scroll.offset, greaterThan(beforeLastInput));
        }
        final releasedOffset = fixture.scroll.offset;
        await tester.pumpAndSettle();
        expect(fixture.scroll.offset, closeTo(releasedOffset, .001));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('replacing the controller discards the preceding mouse grip', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    final gesture = await tester.startGesture(
      fixture.thumb.center,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 16));
    final transferredOffset = fixture.scroll.offset;
    final replacement = await _mount(tester);
    expect(replacement.scroll.offset, closeTo(transferredOffset, .001));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(replacement.scroll.offset, closeTo(transferredOffset, .001));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disposing during header animation discards queued grip updates',
    (tester) async {
      final fixture = await _mount(tester);
      final gesture = await tester.startGesture(
        fixture.thumb.center,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpWidget(const SizedBox());
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_ScrollbarFixture> _mount(
  WidgetTester tester, {
  double headerHeight = 160,
  double contentHeight = 40000,
  bool rtl = false,
  ValueNotifier<bool>? interceptPointer,
}) async {
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: DPageSurface.scrollable(
          framed: false,
          hideHeaderOnScroll: true,
          header: SizedBox(height: headerHeight),
          bodyBuilder: (_, header) {
            final scrollbar = DScrollBar(
              controller: scroll,
              child: CustomScrollView(
                controller: scroll,
                slivers: [
                  SliverToBoxAdapter(child: header.spacer),
                  SliverToBoxAdapter(child: SizedBox(height: contentHeight)),
                ],
              ),
            );
            if (interceptPointer == null) return scrollbar;
            return ValueListenableBuilder<bool>(
              valueListenable: interceptPointer,
              child: scrollbar,
              builder: (_, intercept, child) => RawGestureDetector(
                gestures: {
                  if (intercept)
                    EagerGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          EagerGestureRecognizer
                        >(EagerGestureRecognizer.new, (_) {}),
                },
                child: child,
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _ScrollbarFixture(tester, scroll, rtl);
}

class _ScrollbarFixture {
  _ScrollbarFixture(this.tester, this.scroll, this.rtl);

  final WidgetTester tester;
  final ScrollController scroll;
  final bool rtl;

  Finder get paint => find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint && widget.foregroundPainter is ScrollbarPainter,
  );

  ScrollbarPainter get painter =>
      tester.widget<CustomPaint>(paint).foregroundPainter! as ScrollbarPainter;

  Rect get thumb {
    final bounds = tester.getRect(paint);
    final x = rtl ? 4.0 : bounds.width - 4;
    final points = [
      for (var y = 0.0; y < bounds.height; y += .5)
        if (painter.hitTestOnlyThumbInteractive(
          Offset(x, y),
          PointerDeviceKind.mouse,
        ))
          y,
    ];
    expect(points, isNotEmpty);
    return Rect.fromLTRB(
      bounds.left + x - 2,
      bounds.top + points.first,
      bounds.left + x + 2,
      bounds.top + points.last + .5,
    );
  }
}
