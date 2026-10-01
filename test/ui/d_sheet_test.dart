import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  Widget child, {
  Size size = const Size(800, 600),
  TextDirection direction = TextDirection.ltr,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
  EdgeInsets viewInsets = EdgeInsets.zero,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme,
  home: MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: textScaler,
      disableAnimations: disableAnimations,
      viewInsets: viewInsets,
    ),
    child: Directionality(
      textDirection: direction,
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

Widget _sheet<T>({
  DSheetSide side = DSheetSide.right,
  DSheetController<T>? controller,
  bool? open,
  ValueChanged<DSheetChangeDetails<T>>? onOpenChanged,
  bool dismissOnBarrier = true,
  bool dismissOnEscape = true,
  FocusNode? initialFocusNode,
  FocusNode? finalFocusNode,
  bool showCloseButton = true,
  Color? backgroundColor,
  bool fillAvailableHeight = false,
}) => DSheet<T>(
  controller: controller,
  open: open,
  onOpenChanged: onOpenChanged,
  dismissOnBarrier: dismissOnBarrier,
  dismissOnEscape: dismissOnEscape,
  initialFocusNode: initialFocusNode,
  finalFocusNode: finalFocusNode,
  trigger: DSheetTrigger(
    builder: (context, show) => DButton(
      onPressed: show,
      variant: DButtonVariant.outline,
      label: const Text('Open'),
    ),
  ),
  content: DSheetContent(
    fillAvailableHeight: fillAvailableHeight,
    backgroundColor: backgroundColor,
    side: side,
    showCloseButton: showCloseButton,
    semanticLabel: 'Example sheet',
    children: [
      const DSheetHeader(
        children: [
          DSheetTitle(child: Text('Example sheet')),
          DSheetDescription(child: Text('Useful complementary content.')),
        ],
      ),
      const DSheetBody(child: Text('Body')),
      DSheetFooter(
        children: [
          DSheetClose<T>(
            result: null,
            builder: (context, close) => DButton(
              onPressed: close,
              variant: DButtonVariant.outline,
              label: const Text('Done'),
            ),
          ),
        ],
      ),
    ],
  ),
);

void main() {
  double visibleOpacity(WidgetTester tester, Finder finder) {
    var opacity = 1.0;
    for (final element
        in find
            .ancestor(of: finder, matching: find.byType(Opacity))
            .evaluate()) {
      opacity *= (element.widget as Opacity).opacity;
    }
    for (final element
        in find
            .ancestor(of: finder, matching: find.byType(FadeTransition))
            .evaluate()) {
      opacity *= (element.widget as FadeTransition).opacity.value;
    }
    return opacity;
  }

  double backdropOpacity(WidgetTester tester) => visibleOpacity(
    tester,
    find.byWidgetPredicate(
      (widget) =>
          widget is ModalBarrier &&
          (widget.semanticsLabel == 'Dismiss sheet' ||
              widget.semanticsLabel == 'Sheet background'),
    ),
  );

  Future<void> openSwipeSheet(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.iOS,
    bool imperative = false,
    bool dismissOnSwipe = true,
    bool controlled = false,
    bool retained = false,
    VoidCallback? onRetainedDismiss,
    bool disableAnimations = false,
    Size size = const Size(390, 844),
    DSheetSide side = DSheetSide.bottom,
    ScrollController? scroll,
    ValueChanged<DSheetChangeDetails<void>>? onOpenChanged,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var visible = true;
    DSheetContent content() => DSheetContent(
      side: side,
      showCloseButton: !retained,
      fillAvailableHeight: true,
      scrollWholeSheet: false,
      children: [
        const DSheetHeader(children: [DSheetTitle(child: Text('Swipe sheet'))]),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            itemCount: 50,
            itemBuilder: (_, index) =>
                SizedBox(height: 48, child: Text('Item $index')),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => retained
              ? visible
                    ? DSheetViewport(
                        onDismiss: dismissOnSwipe
                            ? () {
                                onRetainedDismiss?.call();
                                if (!controlled) {
                                  setState(() => visible = false);
                                }
                              }
                            : null,
                        content: content(),
                      )
                    : const SizedBox.shrink()
              : imperative
              ? DButton(
                  label: const Text('Open'),
                  onPressed: () => unawaited(
                    showDSheet<void>(
                      context: context,
                      side: side,
                      fillAvailableHeight: true,
                      dismissOnSwipe: dismissOnSwipe,
                      builder: (_, _) => content(),
                    ),
                  ),
                )
              : DSheet<void>(
                  open: controlled ? true : null,
                  dismissOnSwipe: dismissOnSwipe,
                  onOpenChanged: onOpenChanged,
                  trigger: DSheetTrigger(
                    builder: (_, open) =>
                        DButton(label: const Text('Open'), onPressed: open),
                  ),
                  content: content(),
                ),
        ),
        theme: ThemeData(platform: platform),
        size: size,
        disableAnimations: disableAnimations,
      ),
    );
    if (!controlled && !retained) await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final height in [600.0, 1000.0]) {
    testWidgets('release threshold scales with a $height viewport', (
      tester,
    ) async {
      await openSwipeSheet(tester, size: Size(390, height));
      final sheet = find.byType(DSheetContent);
      final bounds = tester.getRect(sheet);
      final threshold = (height - bounds.top) * .3;
      final title = find.text('Swipe sheet');
      final gesture = await tester.startGesture(tester.getCenter(title));
      await gesture.moveBy(Offset(0, threshold + 20));
      await gesture.moveBy(const Offset(0, -21));
      await tester.pump();
      expect(
        tester.getTopLeft(sheet).dy - bounds.top,
        closeTo(threshold - 1, .01),
      );
      // Crossing the threshold does not commit dismissal until release.
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet), bounds);
      expect(backdropOpacity(tester), 1);

      final dismiss = await tester.startGesture(tester.getCenter(title));
      await dismiss.moveBy(Offset(0, threshold + 1));
      await dismiss.up();
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final origin in ['header', 'scroll', 'helper']) {
      testWidgets('partial $origin swipe restores the sheet on $platform', (
        tester,
      ) async {
        await openSwipeSheet(
          tester,
          platform: platform,
          imperative: origin == 'helper',
        );
        final sheet = find.byType(DSheetContent);
        final bounds = tester.getRect(sheet);
        final target = origin == 'scroll'
            ? find.byType(ListView)
            : find.text('Swipe sheet');
        final gesture = await tester.startGesture(tester.getCenter(target));
        await gesture.moveBy(const Offset(0, 30));
        await gesture.moveBy(const Offset(0, 150));
        await tester.pump();
        expect(tester.getTopLeft(sheet).dy, greaterThan(bounds.top + 72));
        expect(backdropOpacity(tester), inExclusiveRange(0, 1));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(sheet, findsOneWidget);
        expect(tester.getRect(sheet), bounds);
        expect(backdropOpacity(tester), 1);
      });
    }

    for (final reducedMotion in [false, true]) {
      testWidgets(
        'short fast flick restores $platform sheet (reduced: $reducedMotion)',
        (tester) async {
          await openSwipeSheet(
            tester,
            platform: platform,
            disableAnimations: reducedMotion,
          );
          final sheet = find.byType(DSheetContent);
          final bounds = tester.getRect(sheet);
          await tester.fling(
            find.text('Swipe sheet'),
            const Offset(0, 65),
            1200,
          );
          await tester.pumpAndSettle();
          expect(sheet, findsOneWidget);
          expect(tester.getRect(sheet), bounds);
          expect(backdropOpacity(tester), 1);
        },
      );

      testWidgets(
        'backdrop follows a cancelled $platform swipe (reduced: $reducedMotion)',
        (tester) async {
          await openSwipeSheet(
            tester,
            platform: platform,
            disableAnimations: reducedMotion,
          );
          final sheet = find.byType(DSheetContent);
          final bounds = tester.getRect(sheet);
          expect(backdropOpacity(tester), 1);
          final gesture = await tester.startGesture(
            tester.getCenter(find.text('Swipe sheet')),
          );
          await gesture.moveBy(const Offset(0, 30));
          await gesture.moveBy(const Offset(0, 120));
          await tester.pump();
          final firstOpacity = backdropOpacity(tester);
          expect(firstOpacity, inExclusiveRange(0, 1));
          expect(visibleOpacity(tester, sheet), 1);

          await gesture.moveBy(const Offset(0, 120));
          await tester.pump();
          final lowerOpacity = backdropOpacity(tester);
          expect(lowerOpacity, lessThan(firstOpacity));
          await gesture.moveBy(const Offset(0, -80));
          await tester.pump();
          expect(backdropOpacity(tester), greaterThan(lowerOpacity));
          await gesture.cancel();
          await tester.pumpAndSettle();
          expect(backdropOpacity(tester), 1);
          expect(tester.getRect(sheet), bounds);
        },
      );
    }

    for (final (speed, origin) in [
      (400.0, 'header'),
      (1800.0, 'header'),
      (4000.0, 'header'),
      (1800.0, 'scroll'),
      (1800.0, 'bottom scroll'),
      (1800.0, 'helper'),
      (400.0, 'retained header'),
      (1800.0, 'retained scroll'),
      (1800.0, 'retained bottom scroll'),
    ]) {
      testWidgets('swipe exit retains $speed px/s from $origin on $platform', (
        tester,
      ) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await openSwipeSheet(
          tester,
          platform: platform,
          scroll: scroll,
          imperative: origin == 'helper',
          retained: origin.startsWith('retained'),
        );
        final fromBottom = origin.contains('bottom');
        if (fromBottom) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
          await tester.pumpAndSettle();
        }
        final sheet = find.byType(DSheetContent);
        final gesture = await tester.startGesture(
          tester.getCenter(
            origin.endsWith('scroll')
                ? find.byType(ListView)
                : find.text('Swipe sheet'),
          ),
        );
        var elapsed = Duration.zero;
        final sampleDuration = Duration(
          microseconds: (12 / speed * 1e6).round(),
        );
        // Build a real velocity history instead of a drag with zero timestamps.
        for (var step = 0; step < 24; step++) {
          elapsed += sampleDuration;
          await gesture.moveBy(
            Offset(0, fromBottom ? -12 : 12),
            timeStamp: elapsed,
          );
          await tester.pump(sampleDuration);
        }
        final releaseTop = tester.getTopLeft(sheet).dy;
        var previousOpacity = backdropOpacity(tester);
        expect(previousOpacity, inExclusiveRange(0, 1));
        await gesture.up(timeStamp: elapsed);
        await tester.pump();

        var previousTop = releaseTop;
        var previousSpeed = speed;
        for (var frame = 0; frame < 22; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (sheet.evaluate().isEmpty) break;
          final top = tester.getTopLeft(sheet).dy;
          final opacity = backdropOpacity(tester);
          expect(opacity, lessThanOrEqualTo(previousOpacity));
          expect(visibleOpacity(tester, sheet), 1);
          previousOpacity = opacity;
          final frameSpeed = (top - previousTop) / .016;
          expect(
            frameSpeed,
            greaterThanOrEqualTo(previousSpeed - 5),
            reason: 'A dismissing swipe must not lose speed (frame $frame).',
          );
          previousTop = top;
          previousSpeed = frameSpeed;
        }
        expect(sheet, findsNothing);
        expect(previousOpacity, lessThan(.15));
        expect(
          previousTop + previousSpeed * .032,
          greaterThanOrEqualTo(844),
          reason:
              'The sheet should travel offscreen instead of fading in place.',
        );
        expect(tester.takeException(), isNull);
      });
    }

    for (final imperative in [false, true]) {
      testWidgets(
        'swipe closes the $platform ${imperative ? 'helper' : 'sheet'} header',
        (tester) async {
          await openSwipeSheet(
            tester,
            platform: platform,
            imperative: imperative,
          );
          await tester.drag(find.text('Swipe sheet'), const Offset(0, 300));
          await tester.pumpAndSettle();
          expect(find.byType(DSheetContent), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'swipe scrolls normally then dismisses at the top on $platform',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await openSwipeSheet(tester, platform: platform, scroll: scroll);
        final sheet = find.byType(DSheetContent);
        final bounds = tester.getRect(sheet);
        scroll.jumpTo(400);
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, 120));
        await tester.pumpAndSettle();
        expect(scroll.offset, lessThan(400));
        expect(scroll.offset, greaterThan(0));
        expect(tester.getRect(sheet), bounds);
        expect(backdropOpacity(tester), 1);
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, 500));
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final presentation in ['sheet', 'helper', 'retained']) {
      testWidgets(
        'bottom overscroll dismisses the $platform $presentation downward',
        (tester) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          await openSwipeSheet(
            tester,
            platform: platform,
            scroll: scroll,
            imperative: presentation == 'helper',
            retained: presentation == 'retained',
          );
          final sheet = find.byType(DSheetContent);
          final bounds = tester.getRect(sheet);
          final list = find.byType(ListView);
          final maximum = scroll.position.maxScrollExtent;
          scroll.jumpTo(maximum - 400);
          await tester.pumpAndSettle();
          await tester.drag(list, const Offset(0, -120));
          await tester.pumpAndSettle();
          expect(scroll.offset, inExclusiveRange(maximum - 400, maximum));
          expect(tester.getRect(sheet), bounds);

          // A continuous drag first consumes the remaining content, then
          // transfers the movement beyond its bottom to sheet dismissal.
          scroll.jumpTo(maximum - 60);
          await tester.pumpAndSettle();
          final gesture = await tester.startGesture(tester.getCenter(list));
          await gesture.moveBy(const Offset(0, -30));
          await gesture.moveBy(const Offset(0, -100));
          await tester.pump();
          final top = tester.getTopLeft(sheet).dy;
          expect(top, greaterThan(bounds.top));
          await gesture.moveBy(const Offset(0, -120));
          await tester.pump();
          expect(tester.getTopLeft(sheet).dy, closeTo(top + 120, .01));
          expect(backdropOpacity(tester), inExclusiveRange(0, 1));
          await gesture.moveBy(const Offset(0, -160));
          await gesture.up();
          await tester.pumpAndSettle();
          expect(sheet, findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'short, reversed, cancelled and ballistic bottom overscroll keep the $platform sheet open',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await openSwipeSheet(tester, platform: platform, scroll: scroll);
        final sheet = find.byType(DSheetContent);
        final bounds = tester.getRect(sheet);
        final list = find.byType(ListView);
        final maximum = scroll.position.maxScrollExtent;

        scroll.jumpTo(maximum);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, -100), 1800);
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet), bounds);
        expect(backdropOpacity(tester), 1);

        for (final cancelled in [false, true]) {
          scroll.jumpTo(maximum);
          await tester.pumpAndSettle();
          final gesture = await tester.startGesture(tester.getCenter(list));
          await gesture.moveBy(const Offset(0, -30));
          await gesture.moveBy(const Offset(0, -280));
          await tester.pump();
          expect(tester.getTopLeft(sheet).dy, greaterThan(bounds.top + 250));
          if (cancelled) {
            await gesture.cancel();
          } else {
            await gesture.moveBy(const Offset(0, 280));
            await tester.pump();
            expect(tester.getTopLeft(sheet).dy, lessThan(bounds.top + 40));
            await gesture.up();
          }
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet), bounds);
          expect(backdropOpacity(tester), 1);
        }

        // Momentum reaching the boundary after release is not a dismiss drag.
        scroll.jumpTo(maximum - 300);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, -150), 1800);
        await tester.pumpAndSettle();
        expect(scroll.offset, closeTo(maximum, .01));
        expect(tester.getRect(sheet), bounds);

        // The next gesture can still dismiss from the opposite edge.
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.drag(list, const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'cancelled and ballistic overscroll keep the $platform sheet open',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await openSwipeSheet(tester, platform: platform, scroll: scroll);
        final sheet = find.byType(DSheetContent);
        final bounds = tester.getRect(sheet);
        final list = find.byType(ListView);
        final gesture = await tester.startGesture(tester.getCenter(list));
        await gesture.moveBy(const Offset(0, 30));
        await gesture.moveBy(const Offset(0, 180));
        await tester.pump();
        expect(tester.getTopLeft(sheet).dy, greaterThan(bounds.top));
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet), bounds);

        scroll.jumpTo(300);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, 150), 1800);
        await tester.pumpAndSettle();
        expect(scroll.offset, closeTo(0, .01));
        expect(tester.getRect(sheet), bounds);

        // The same drag can scroll to the top and then pull the sheet down.
        scroll.jumpTo(80);
        await tester.pumpAndSettle();
        await tester.drag(list, const Offset(0, 600));
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
      },
    );
  }

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'short, upward and cancelled swipes restore the sheet (reduced: $reducedMotion)',
      (tester) async {
        await openSwipeSheet(tester, disableAnimations: reducedMotion);
        final title = find.text('Swipe sheet');
        final sheet = find.byType(DSheetContent);
        final bounds = tester.getRect(sheet);
        for (final delta in [
          const Offset(0, 35),
          const Offset(0, -150),
          const Offset(150, 0),
        ]) {
          await tester.drag(title, delta);
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet), bounds);
        }
        final gesture = await tester.startGesture(tester.getCenter(title));
        await gesture.moveBy(const Offset(0, 30));
        await gesture.moveBy(const Offset(0, 150));
        await tester.pump();
        expect(tester.getTopLeft(sheet).dy, greaterThan(bounds.top));
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet), bounds);
        await tester.fling(title, const Offset(0, 300), 1200);
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
      },
    );
  }

  testWidgets('a controlled sheet can decline swipe dismissal', (tester) async {
    final changes = <DSheetChangeDetails<void>>[];
    await openSwipeSheet(tester, controlled: true, onOpenChanged: changes.add);
    final bounds = tester.getRect(find.byType(DSheetContent));
    await tester.drag(find.text('Swipe sheet'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(changes.single.open, isFalse);
    expect(changes.single.reason, DSheetChangeReason.close);
    expect(tester.getRect(find.byType(DSheetContent)), bounds);
    expect(backdropOpacity(tester), 1);
  });

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'retained sheets restore cancelled and declined swipes (reduced: $reducedMotion)',
      (tester) async {
        var requests = 0;
        await openSwipeSheet(
          tester,
          retained: true,
          controlled: true,
          disableAnimations: reducedMotion,
          onRetainedDismiss: () => requests++,
        );
        final title = find.text('Swipe sheet');
        final sheet = find.byType(DSheetContent);
        final bounds = tester.getRect(sheet);
        await tester.drag(title, const Offset(0, 35));
        await tester.pumpAndSettle();
        expect(requests, 0);
        expect(tester.getRect(sheet), bounds);
        final gesture = await tester.startGesture(tester.getCenter(title));
        await gesture.moveBy(const Offset(0, 30));
        await gesture.moveBy(const Offset(0, 120));
        await tester.pump();
        expect(tester.getTopLeft(sheet).dy, greaterThan(bounds.top));
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(requests, 0);
        expect(tester.getRect(sheet), bounds);

        await tester.drag(title, const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(requests, 1);
        expect(tester.getRect(sheet), bounds);
        expect(backdropOpacity(tester), 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('retained sheets without a close callback do not swipe', (
    tester,
  ) async {
    await openSwipeSheet(tester, retained: true, dismissOnSwipe: false);
    final sheet = find.byType(DSheetContent);
    final bounds = tester.getRect(sheet);
    await tester.drag(find.text('Swipe sheet'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(tester.getRect(sheet), bounds);
  });

  testWidgets('removing a retained sheet cancels its pending dismissal', (
    tester,
  ) async {
    var requests = 0;
    await openSwipeSheet(
      tester,
      retained: true,
      onRetainedDismiss: () => requests++,
    );
    await tester.drag(find.text('Swipe sheet'), const Offset(0, 300));
    await tester.pump();
    expect(requests, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in ['disabled', 'desktop', 'side', 'mouse']) {
    testWidgets('$scenario does not swipe-dismiss', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await openSwipeSheet(
        tester,
        scroll: scroll,
        dismissOnSwipe: scenario != 'disabled',
        platform: scenario == 'desktop'
            ? TargetPlatform.macOS
            : TargetPlatform.iOS,
        side: scenario == 'side' ? DSheetSide.right : DSheetSide.bottom,
      );
      final bounds = tester.getRect(find.byType(DSheetContent));
      await tester.drag(
        find.text('Swipe sheet'),
        const Offset(0, 300),
        kind: scenario == 'mouse'
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(DSheetContent)), bounds);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ListView),
        const Offset(0, -350),
        kind: scenario == 'mouse'
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(DSheetContent)), bounds);
    });
  }

  for (final imperative in [false, true]) {
    testWidgets(
      'under-keyboard ${imperative ? 'helper' : 'sheet'} retains its full height and live insets',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
        tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewInsets);
        final focus = FocusNode();
        addTearDown(focus.dispose);
        const editorKey = ValueKey('sheet-editor');
        DSheetContent content() => DSheetContent(
          side: DSheetSide.bottom,
          fillAvailableHeight: true,
          extendBehindKeyboard: true,
          scrollWholeSheet: false,
          children: [
            Expanded(
              child: DInput(
                key: editorKey,
                focusNode: focus,
                borderless: true,
                maxLines: null,
                expands: true,
              ),
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => imperative
                    ? DButton(
                        label: const Text('Open'),
                        onPressed: () {
                          unawaited(
                            showDSheet<void>(
                              context: context,
                              side: DSheetSide.bottom,
                              fillAvailableHeight: true,
                              extendBehindKeyboard: true,
                              initialFocusNode: focus,
                              builder: (_, _) => content(),
                            ),
                          );
                        },
                      )
                    : DSheet<void>(
                        initialFocusNode: focus,
                        trigger: DSheetTrigger(
                          builder: (_, open) => DButton(
                            label: const Text('Open'),
                            onPressed: open,
                          ),
                        ),
                        content: content(),
                      ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final editable = find.descendant(
          of: find.byKey(editorKey),
          matching: find.byType(EditableText),
        );
        await tester.enterText(editable, 'Retained draft');
        final state = tester.state(editable);
        for (final inset in [336.0, 210.0, 0.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          tester.view.padding = FakeViewPadding(
            top: 59,
            bottom: inset == 0 ? 34 : 0,
          );
          await tester.pumpAndSettle();
          final sheet = tester.getRect(find.byType(DSheetContent));
          expect(sheet, const Rect.fromLTRB(0, 59 + DSpacing.sm, 390, 844));
          expect(tester.getRect(find.byKey(editorKey)).bottom, 844);
          expect(
            MediaQuery.viewInsetsOf(tester.element(editable)).bottom,
            inset,
          );
          expect(tester.state(editable), same(state));
          expect(find.text('Retained draft'), findsOneWidget);
          expect(focus.hasFocus, isTrue);
        }
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final reducedMotion in [false, true]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'full-height picker has a darker opaque backdrop and subtle scale ($brightness, reduced: $reducedMotion)',
        (tester) async {
          final theme = ThemeData(brightness: brightness);
          final background = brightness == Brightness.dark
              ? const Color(0xff182330)
              : const Color(0xffe9f4ee);
          await tester.pumpWidget(
            _host(
              _sheet<void>(side: DSheetSide.bottom, fillAvailableHeight: true),
              theme: theme.copyWith(
                extensions: [
                  DTokens.fromTheme(theme).copyWith(background: background),
                ],
              ),
              disableAnimations: reducedMotion,
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pump();
          await tester.pump();
          final barrier = find.byWidgetPredicate(
            (widget) =>
                widget is ModalBarrier &&
                widget.color?.a == 1 &&
                widget.color!.computeLuminance() <
                    background.computeLuminance(),
          );
          expect(barrier, findsOneWidget);
          expect(
            find.ancestor(of: barrier, matching: find.byType(FadeTransition)),
            findsNothing,
          );
          final scale = find.ancestor(
            of: find.byType(DSheetContent),
            matching: find.byType(ScaleTransition),
          );
          if (reducedMotion) {
            expect(scale, findsNothing);
          } else {
            expect(
              tester.widget<ScaleTransition>(scale).scale.value,
              closeTo(.97, .001),
            );
            await tester.pump(const Duration(milliseconds: 80));
            expect(
              tester.widget<ScaleTransition>(scale).scale.value,
              inExclusiveRange(.97, 1),
            );
          }
          await tester.pumpAndSettle();
          expect(barrier, findsOneWidget);
          if (!reducedMotion) {
            expect(tester.widget<ScaleTransition>(scale).scale.value, 1);
          }
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
          expect(find.byType(DSheetContent), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final side in [DSheetSide.left, DSheetSide.right]) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'side accessory belongs to sheet focus and physical edge ($side, $direction)',
        (tester) async {
          var clicks = 0;
          final focus = FocusNode();
          addTearDown(focus.dispose);
          await tester.pumpWidget(
            _host(
              direction: direction,
              DSheet<void>(
                initialFocusNode: focus,
                trigger: DSheetTrigger(
                  builder: (context, open) =>
                      DButton(label: const Text('Open'), onPressed: open),
                ),
                content: DSheetContent(
                  key: const ValueKey('accessory-sheet'),
                  side: side,
                  inset: true,
                  sidePanelWidth: 700,
                  sidePanelMaxWidth: 700,
                  sideAccessory: DButton(
                    key: const ValueKey('accessory'),
                    focusNode: focus,
                    label: const Text('Go'),
                    onPressed: () => clicks++,
                  ),
                  children: const [
                    Expanded(child: SizedBox(key: ValueKey('surface'))),
                  ],
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final sheet = tester.getRect(
            find.byKey(const ValueKey('accessory-sheet')),
          );
          final surface = tester.getRect(find.byKey(const ValueKey('surface')));
          final accessory = find.byKey(const ValueKey('accessory'));
          final button = tester.getRect(accessory);
          expect(sheet.width - surface.width, 52);
          expect(button.center.dy, sheet.center.dy);
          expect(
            button.center.dx,
            side == DSheetSide.right ? sheet.left + 26 : sheet.right - 26,
          );
          expect(focus.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(clicks, 1);
          await tester.tap(accessory);
          await tester.pumpAndSettle();
          expect(clicks, 2);
          expect(find.byKey(const ValueKey('accessory-sheet')), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('accessory-sheet')), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final imperative in [false, true]) {
    testWidgets(
      'non-modal ${imperative ? 'helper' : 'sheet'} allows background clicks, input and scrolling',
      (tester) async {
        final controller = DSheetController<String>();
        final backgroundFocus = FocusNode();
        final triggerFocus = FocusNode();
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(backgroundFocus.dispose);
        addTearDown(triggerFocus.dispose);
        addTearDown(scroll.dispose);
        var clicks = 0;
        String? result;
        VoidCallback? closeSheet;
        DSheetContent content() => DSheetContent(
          children: [
            const DSheetHeader(
              children: [DSheetTitle(child: Text('Non-modal sheet'))],
            ),
            DSheetBody(child: DInput(semanticLabel: 'Sheet input')),
            DSheetFooter(
              children: [
                DSheetClose<String>(
                  result: 'done',
                  builder: (_, close) =>
                      DButton(onPressed: close, label: const Text('Done')),
                ),
              ],
            ),
          ],
        );
        Widget background(BuildContext context, VoidCallback open) => Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: Column(
              children: [
                DButton(
                  focusNode: triggerFocus,
                  onPressed: open,
                  label: const Text('Open'),
                ),
                DButton(
                  onPressed: () => clicks++,
                  label: const Text('Background action'),
                ),
                DInput(
                  focusNode: backgroundFocus,
                  semanticLabel: 'Background input',
                ),
                Expanded(
                  child: ListView(
                    controller: scroll,
                    children: List.generate(
                      50,
                      (i) => SizedBox(height: 50, child: Text('Row $i')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pumpWidget(
          _host(
            imperative
                ? Builder(
                    builder: (context) => background(context, () async {
                      result = await showDSheet<String>(
                        context: context,
                        modal: false,
                        builder: (_, helperController) {
                          closeSheet = () => helperController.close('done');
                          return content();
                        },
                      );
                    }),
                  )
                : DSheet<String>(
                    controller: controller,
                    modal: false,
                    onOpenChanged: (details) => result = details.result,
                    trigger: DSheetTrigger(builder: background),
                    content: content(),
                  ),
          ),
        );
        triggerFocus.requestFocus();
        await tester.pump();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
        final sheetEditor = find.descendant(
          of: find.byType(DSheetContent),
          matching: find.byType(EditableText),
        );
        await tester.enterText(sheetEditor, 'Retained draft');
        await tester.tap(find.text('Background action'));
        await tester.pumpAndSettle();
        expect(clicks, 1);
        expect(find.byType(DSheetContent), findsOneWidget);
        final backgroundEditor = find.byWidgetPredicate(
          (w) => w is EditableText && w.focusNode == backgroundFocus,
        );
        await tester.tap(backgroundEditor);
        await tester.pumpAndSettle();
        expect(backgroundFocus.hasFocus, isTrue);
        await tester.enterText(backgroundEditor, 'Background still editable');
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(0));
        expect(find.text('Retained draft'), findsOneWidget);

        // Closing from application state must preserve background focus.
        if (imperative) {
          closeSheet!();
        } else {
          controller.close('done');
        }
        await tester.pumpAndSettle();
        expect(result, 'done');
        expect(find.byType(DSheetContent), findsNothing);
        expect(backgroundFocus.hasFocus, isTrue);

        triggerFocus.requestFocus();
        await tester.pump();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(triggerFocus.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'modal dialogs above non-modal sheets still block the background',
    (tester) async {
      var clicks = 0;
      await tester.pumpWidget(
        _host(
          DSheet<void>(
            modal: false,
            initiallyOpen: true,
            trigger: DSheetTrigger(
              builder: (_, _) => Align(
                alignment: Alignment.topLeft,
                child: DButton(
                  onPressed: () => clicks++,
                  label: const Text('Background action'),
                ),
              ),
            ),
            content: DSheetContent(
              children: [
                DSheetHeader(
                  children: [
                    DDialog<void>(
                      dismissOnBarrier: false,
                      trigger: DDialogTrigger(
                        builder: (_, open) => DButton(
                          onPressed: open,
                          label: const Text('Open dialog'),
                        ),
                      ),
                      content: const DDialogContent(
                        children: [DDialogTitle(child: Text('Modal dialog'))],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.text('Background action')));
      await tester.pumpAndSettle();
      expect(clicks, 0);
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Modal dialog'), findsNothing);
      expect(find.byType(DSheetContent), findsOneWidget);
      await tester.tap(find.text('Background action'));
      await tester.pumpAndSettle();
      expect(clicks, 1);
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsNothing);
    },
  );

  testWidgets(
    'modality changes update an open sheet without losing its input',
    (tester) async {
      final modal = ValueNotifier(true);
      addTearDown(modal.dispose);
      var clicks = 0;
      await tester.pumpWidget(
        _host(
          ValueListenableBuilder<bool>(
            valueListenable: modal,
            builder: (_, value, _) => DSheet<void>(
              modal: value,
              initiallyOpen: true,
              dismissOnBarrier: false,
              trigger: DSheetTrigger(
                builder: (_, _) => Align(
                  alignment: Alignment.topLeft,
                  child: DButton(
                    onPressed: () => clicks++,
                    label: const Text('Background action'),
                  ),
                ),
              ),
              content: DSheetContent(children: [DSheetBody(child: DInput())]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Retained draft');
      final editor = tester.state(find.byType(EditableText));
      final point = tester.getCenter(find.text('Background action'));
      for (final value in [true, false, true]) {
        modal.value = value;
        await tester.pumpAndSettle();
        final previousClicks = clicks;
        await tester.tapAt(point);
        await tester.pumpAndSettle();
        expect(clicks, value ? previousClicks : previousClicks + 1);
        expect(
          find.byType(BackdropFilter),
          value ? findsOneWidget : findsNothing,
        );
        expect(tester.state(find.byType(EditableText)), same(editor));
        expect(find.text('Retained draft'), findsOneWidget);
      }
    },
  );

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'inset sheet animates width and retains its editor (reduced motion: $reducedMotion)',
      (tester) async {
        tester.view.physicalSize = const Size(900, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final width = ValueNotifier<double>(400);
        addTearDown(width.dispose);
        await tester.pumpWidget(
          _host(
            ValueListenableBuilder<double>(
              valueListenable: width,
              builder: (context, value, _) => DSheet<void>(
                initiallyOpen: true,
                trigger: DSheetTrigger(
                  builder: (_, _) => const SizedBox.shrink(),
                ),
                content: DSheetContent(
                  key: const ValueKey('inset-sheet'),
                  inset: true,
                  animateSize: true,
                  sidePanelWidth: value,
                  sidePanelMaxWidth: 900,
                  children: [
                    DSheetHeader(
                      children: [DInput(semanticLabel: 'Retained input')],
                    ),
                  ],
                ),
              ),
            ),
            size: const Size(900, 700),
            disableAnimations: reducedMotion,
          ),
        );
        await tester.pumpAndSettle();
        final sheet = find.byKey(const ValueKey('inset-sheet'));
        final original = tester.getRect(sheet);
        expect(original, const Rect.fromLTWH(488, 12, 400, 676));
        await tester.enterText(
          find.byType(EditableText),
          'Retained through resizing',
        );
        final editor = tester.state(find.byType(EditableText));
        width.value = 700;
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final intermediate = tester.getSize(sheet).width;
        if (reducedMotion) {
          expect(intermediate, 700);
        } else {
          expect(intermediate, greaterThan(400));
          expect(intermediate, lessThan(700));
        }
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet), const Rect.fromLTWH(188, 12, 700, 676));
        expect(tester.state(find.byType(EditableText)), same(editor));
        expect(find.text('Retained through resizing'), findsOneWidget);
        width.value = 1200;
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet), const Rect.fromLTWH(12, 12, 876, 676));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('uncontrolled trigger and typed close restore focus', (
    tester,
  ) async {
    final triggerFocus = FocusNode();
    addTearDown(triggerFocus.dispose);
    final changes = <DSheetChangeDetails<String>>[];
    await tester.pumpWidget(
      _host(
        DSheet<String>(
          onOpenChanged: changes.add,
          trigger: DSheetTrigger(
            builder: (context, open) => DButton(
              focusNode: triggerFocus,
              onPressed: open,
              label: const Text('Open'),
            ),
          ),
          content: DSheetContent(
            semanticLabel: 'Typed sheet',
            children: [
              const DSheetHeader(
                children: [DSheetTitle(child: Text('Typed sheet'))],
              ),
              DSheetFooter(
                children: [
                  DSheetClose<String>(
                    result: 'chosen',
                    builder: (context, close) =>
                        DButton(onPressed: close, label: const Text('Choose')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    triggerFocus.requestFocus();
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(changes.single.reason, DSheetChangeReason.trigger);
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(changes.last.result, 'chosen');
    expect(changes.last.reason, DSheetChangeReason.close);
    expect(triggerFocus.hasFocus, isTrue);
  });

  testWidgets('trigger builder does not rerun for ancestor keyboard insets', (
    tester,
  ) async {
    var triggerBuilds = 0;
    final sheet = DSheet<void>(
      trigger: DSheetTrigger(
        builder: (context, open) {
          triggerBuilds++;
          return DButton(onPressed: open, label: const Text('Open'));
        },
      ),
      content: const DSheetContent(
        side: DSheetSide.bottom,
        semanticLabel: 'Message actions',
        children: [
          DSheetHeader(children: [DSheetTitle(child: Text('Message actions'))]),
        ],
      ),
    );
    var keyboard = 0.0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQueryData(
                  size: const Size(800, 600),
                  viewInsets: EdgeInsets.only(bottom: keyboard),
                ),
                child: Center(child: sheet),
              );
            },
          ),
        ),
      ),
    );
    expect(triggerBuilds, 1);

    for (final inset in [96.0, 192.0, 288.0, 0.0]) {
      update(() => keyboard = inset);
      await tester.pump();
    }
    expect(triggerBuilds, 1);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Message actions'), findsOneWidget);
    expect(triggerBuilds, 1);
  });

  testWidgets('open route keeps its transition curves across keyboard insets', (
    tester,
  ) async {
    final curves = <CurvedAnimation>[];
    void track(ObjectEvent event) {
      if (event case ObjectCreated(object: final CurvedAnimation curve)) {
        curves.add(curve);
      }
    }

    FlutterMemoryAllocations.instance.addListener(track);
    addTearDown(() => FlutterMemoryAllocations.instance.removeListener(track));
    var keyboard = 0.0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQueryData(
                  size: const Size(800, 600),
                  viewInsets: EdgeInsets.only(bottom: keyboard),
                ),
                child: Center(child: _sheet<void>(side: DSheetSide.bottom)),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.text('Body')))!.animation!;
    List<CurvedAnimation> routeCurves() => [
      for (final curve in curves)
        if (identical(curve.parent, route)) curve,
    ];
    final opened = routeCurves();
    expect(opened, hasLength(2));

    for (final inset in [96.0, 192.0, 288.0, 0.0]) {
      update(() => keyboard = inset);
      await tester.pump();
    }
    expect(routeCurves(), opened);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
    expect(opened.every((curve) => curve.isDisposed), isTrue);
  });

  testWidgets('physical sides and centered panels match their geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final side in const [
      DSheetSide.top,
      DSheetSide.right,
      DSheetSide.bottom,
      DSheetSide.left,
      DSheetSide.center,
    ]) {
      await tester.pumpWidget(_host(_sheet<void>(side: side)));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(DSheetContent));
      switch (side) {
        case DSheetSide.center:
          expect(rect.center.dx, 400);
          expect(rect.width, 384);
          expect(rect.height, 600);
        case DSheetSide.top:
          expect(rect.top, 0);
          expect(rect.width, 800);
        case DSheetSide.right:
          expect(rect.right, 800);
          expect(rect.width, 384);
          expect(rect.height, 600);
        case DSheetSide.bottom:
          expect(rect.bottom, 600);
          expect(rect.width, 800);
        case DSheetSide.left:
          expect(rect.left, 0);
          expect(rect.width, 384);
          expect(rect.height, 600);
        case DSheetSide.start || DSheetSide.end:
          fail('Logical sides are not in this loop.');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('side width is 75 percent below the 640 breakpoint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(_sheet<void>(), size: const Size(320, 640)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 240);
  });

  testWidgets('explicit side width is clamped by the maximum and viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) =>
                DButton(onPressed: open, label: const Text('Open')),
          ),
          content: const DSheetContent(
            sidePanelWidth: 288,
            children: [DSheetBody(child: Text('Body'))],
          ),
        ),
        size: const Size(320, 640),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 288);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _host(
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) =>
                DButton(onPressed: open, label: const Text('Open')),
          ),
          content: const DSheetContent(
            sidePanelWidth: 480,
            children: [DSheetBody(child: Text('Body'))],
          ),
        ),
        size: const Size(320, 640),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 320);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(800, 640);
    await tester.pumpWidget(
      _host(
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) =>
                DButton(onPressed: open, label: const Text('Open')),
          ),
          content: const DSheetContent(
            sidePanelWidth: 480,
            children: [DSheetBody(child: Text('Body'))],
          ),
        ),
        size: const Size(800, 640),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 384);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _host(
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) =>
                DButton(onPressed: open, label: const Text('Open')),
          ),
          content: const DSheetContent(
            side: DSheetSide.top,
            sidePanelWidth: 100,
            children: [DSheetBody(child: Text('Body'))],
          ),
        ),
        size: const Size(800, 640),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 800);
  });

  testWidgets('logical sides resolve with current RTL direction', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_sheet<void>(side: DSheetSide.start), direction: TextDirection.rtl),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(DSheetContent)).right, 800);
  });

  testWidgets('corner close stays physically right in RTL', (tester) async {
    await tester.pumpWidget(
      _host(_sheet<void>(), direction: TextDirection.rtl),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byType(DSheetContent));
    final close = tester.getRect(find.byTooltip('Close'));
    expect(close.right, closeTo(sheet.right - 12, .01));
  });

  testWidgets('title matches the reference text-base leading', (tester) async {
    await tester.pumpWidget(_host(_sheet<void>()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final titleContext = tester.element(find.text('Example sheet'));
    final style = DefaultTextStyle.of(titleContext).style;
    expect(style.fontSize, 14);
    expect(style.height, 24 / 16);
    expect(style.fontWeight, FontWeight.w500);
  });

  testWidgets('no close button and disabled dismissal remain open', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _sheet<void>(
          showCloseButton: false,
          dismissOnBarrier: false,
          dismissOnEscape: false,
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsNothing);
    await tester.tapAt(const Offset(8, 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Example sheet'), findsOneWidget);
  });

  testWidgets('barrier and Escape report Sheet dismissal reasons', (
    tester,
  ) async {
    final changes = <DSheetChangeDetails<void>>[];
    await tester.pumpWidget(_host(_sheet<void>(onOpenChanged: changes.add)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 300));
    await tester.pumpAndSettle();
    expect(changes.last.reason, DSheetChangeReason.barrier);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(changes.last.reason, DSheetChangeReason.escape);
  });

  testWidgets('controller coalesces submit and closes its open session', (
    tester,
  ) async {
    final controller = DSheetController<String>();
    addTearDown(controller.dispose);
    final gate = Completer<String>();
    await tester.pumpWidget(_host(_sheet<String>(controller: controller)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final first = controller.submit(() => gate.future);
    final second = controller.submit(() async => 'wrong');
    expect(identical(first, second), isTrue);
    gate.complete('saved');
    await first;
    await tester.pumpAndSettle();
    expect(find.text('Example sheet'), findsNothing);
  });

  for (final pageBackground in [false, true]) {
    testWidgets(
      'live theme and direction update an open sheet (page background: $pageBackground)',
      (tester) async {
        var dark = false;
        var direction = TextDirection.ltr;
        late StateSetter update;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              final scheme = ColorScheme.fromSeed(
                seedColor: dark ? Colors.purple : Colors.orange,
                brightness: dark ? Brightness.dark : Brightness.light,
              );
              return _host(
                Builder(
                  builder: (context) => _sheet<void>(
                    side: DSheetSide.end,
                    backgroundColor: pageBackground
                        ? DTokens.of(context).background
                        : null,
                  ),
                ),
                direction: direction,
                theme: ThemeData(colorScheme: scheme),
              );
            },
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final before = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(DSheetContent),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(tester.getRect(find.byType(DSheetContent)).right, 800);
        var tokens = DTokens.of(tester.element(find.byType(DSheetContent)));
        expect(
          before.color,
          pageBackground ? tokens.background : tokens.surface,
        );
        update(() {
          dark = true;
          direction = TextDirection.rtl;
        });
        await tester.pumpAndSettle();
        final after = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(DSheetContent),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(after.color, isNot(before.color));
        tokens = DTokens.of(tester.element(find.byType(DSheetContent)));
        expect(
          after.color,
          pageBackground ? tokens.background : tokens.surface,
        );
        expect(tester.getRect(find.byType(DSheetContent)).left, 0);
      },
    );
  }

  testWidgets('narrow 200 percent text and keyboard insets remain bounded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        _sheet<void>(),
        size: const Size(320, 640),
        textScaler: const TextScaler.linear(2),
        disableAnimations: true,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byType(DSheetContent));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(640));
  });

  testWidgets('keyboard inset scrolls a capped fixed-height bottom sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) =>
                DButton(onPressed: open, label: const Text('Open')),
          ),
          content: const DSheetContent(
            side: DSheetSide.bottom,
            topBottomMaxHeightFactor: .85,
            children: [
              DSheetHeader(children: [DSheetTitle(child: Text('Room chat'))]),
              SizedBox(height: 448, child: TextField()),
            ],
          ),
        ),
        size: const Size(320, 640),
        viewInsets: const EdgeInsets.only(bottom: 300),
        disableAnimations: true,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byType(DSheetContent),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(tester.getRect(find.byType(DSheetContent)).bottom, 640);
  });

  testWidgets('showDSheet uses nearest Navigator and returns typed result', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      _host(
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (nestedContext) => Builder(
              builder: (context) => DButton(
                onPressed: () async {
                  result = await showDSheet<String>(
                    context: context,
                    sidePanelWidth: 288,
                    inset: true,
                    builder: (context, controller) => DSheetContent(
                      children: [
                        DSheetClose<String>(
                          result: 'result',
                          builder: (context, close) => DButton(
                            onPressed: close,
                            label: const Text('Return'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                label: const Text('Helper'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Helper'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 288);
    expect(tester.getTopLeft(find.byType(DSheetContent)).dy, DSpacing.md);
    final surface = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(DSheetContent),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(surface.borderRadius, isNot(BorderRadius.zero));
    expect(surface.clipBehavior, Clip.antiAlias);
    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();
    expect(result, 'result');
  });
}
