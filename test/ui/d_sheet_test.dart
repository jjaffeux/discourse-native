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
  FocusNode? initialFocusNode,
  FocusNode? finalFocusNode,
  bool showCloseButton = true,
  Color? backgroundColor,
  bool fillAvailableHeight = false,
}) => DSheet<T>(
  controller: controller,
  open: open,
  onOpenChanged: onOpenChanged,

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
  const standardPage = DSheetContent(
    variant: DSheetVariant.page,
    showCloseButton: false,
    children: [Expanded(child: SizedBox())],
  );

  Future<void> pumpPage(
    WidgetTester tester,
    DSheetContent page, {
    required MediaQueryData media,
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: MediaQuery(
          data: media,
          child: DSheetViewport(content: page),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  BorderRadiusGeometry? pageClip(WidgetTester tester) => tester
      .widget<Material>(
        find.descendant(
          of: find.byType(DSheetContent),
          matching: find.byType(Material),
        ),
      )
      .borderRadius;

  testWidgets(
    'page keeps its 31px top and 22px bottom corners across display radii and safe insets',
    (tester) async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        for (final bottom in [0.0, 34.0]) {
          for (final radii in [
            null,
            BorderRadius.zero,
            BorderRadius.circular(62),
          ]) {
            await pumpPage(
              tester,
              standardPage,
              platform: platform,
              media: MediaQueryData(
                size: const Size(390, 844),
                displayCornerRadii: radii,
                viewPadding: EdgeInsets.only(bottom: bottom),
              ),
            );
            expect(
              pageClip(tester),
              const BorderRadius.vertical(
                top: Radius.circular(31),
                bottom: Radius.circular(22),
              ),
            );
          }
        }
      }
    },
  );

  for (final foot in [34.0, 0.0]) {
    testWidgets(
      'a menu at the foot stands off it as a sheet at its end ($foot)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.viewPadding = FakeViewPadding(bottom: foot);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _host(
            DSheet<void>(
              trigger: DSheetTrigger(
                builder: (_, open) =>
                    DButton(label: const Text('Open'), onPressed: open),
              ),
              content: const DSheetContent(
                variant: DSheetVariant.menu,
                side: DSheetSide.bottom,
                inset: true,
                showCloseButton: false,
                children: [SizedBox(height: 120, child: Text('Menu content'))],
              ),
            ),
            size: const Size(390, 844),
            theme: ThemeData(platform: TargetPlatform.iOS),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final sheet = find.byType(DSheetContent);
        final bounds = tester.getRect(sheet);
        // Across the screen's width, 6 past half the foot off its bottom edge,
        // its foot following the screen's 55 corner from that far in.
        expect(bounds.left, 0);
        expect(bounds.right, 390);
        expect(bounds.bottom, 844 - (6 + foot / 2));
        final surface = tester.widget<Material>(
          find.descendant(of: sheet, matching: find.byType(Material)).first,
        );
        expect(
          surface.borderRadius,
          BorderRadius.vertical(
            top: const Radius.circular(22),
            bottom: Radius.circular(foot > 0 ? 55 - (6 + foot / 2) : 24),
          ),
        );
      },
    );
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final reducedMotion in [false, true]) {
      for (final variant in [DSheetVariant.menu, DSheetVariant.standard]) {
        testWidgets(
          '$variant backdrop drag shares sheet motion on $platform (reduced: $reducedMotion)',
          (tester) async {
            var closes = 0;
            await tester.pumpWidget(
              _host(
                DSheet<void>(
                  trigger: DSheetTrigger(
                    builder: (_, open) =>
                        DButton(label: const Text('Open'), onPressed: open),
                  ),
                  onOpenChanged: (details) {
                    if (!details.open) closes++;
                  },
                  content: DSheetContent(
                    variant: variant,
                    side: DSheetSide.bottom,
                    inset: true,
                    showCloseButton: false,
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox(
                          height: 120,
                          child: Text('Menu content'),
                        ),
                      ),
                    ],
                  ),
                ),
                theme: ThemeData(platform: platform),
                disableAnimations: reducedMotion,
              ),
            );
            await tester.tap(find.text('Open'));
            await tester.pumpAndSettle();
            final sheet = find.byType(DSheetContent);
            final bounds = tester.getRect(sheet);
            final above = Offset(bounds.center.dx, bounds.top - 40);
            final short = await tester.startGesture(
              above,
              kind: PointerDeviceKind.touch,
            );
            await short.moveBy(const Offset(0, 24));
            await short.moveBy(const Offset(0, 40));
            await tester.pump();
            expect(tester.getRect(sheet).top, greaterThan(bounds.top));
            expect(closes, 0);
            await short.up();
            await tester.pumpAndSettle();
            expect(tester.getRect(sheet), bounds);
            expect(closes, 0);

            final cancelled = await tester.startGesture(
              above,
              kind: PointerDeviceKind.touch,
            );
            await cancelled.moveBy(const Offset(0, 24));
            await cancelled.moveBy(const Offset(0, 160));
            await tester.pump();
            expect(tester.getRect(sheet).top, greaterThan(bounds.top));
            await cancelled.cancel();
            await tester.pumpAndSettle();
            expect(tester.getRect(sheet), bounds);
            expect(closes, 0);

            await tester.dragFrom(
              above,
              const Offset(0, -100),
              kind: PointerDeviceKind.touch,
            );
            await tester.pumpAndSettle();
            expect(tester.getRect(sheet), bounds);
            expect(closes, 0);
            final dismiss = await tester.startGesture(
              above,
              kind: PointerDeviceKind.touch,
            );
            await dismiss.moveBy(const Offset(0, 24));
            await dismiss.moveBy(const Offset(0, 160));
            await tester.pump();
            expect(closes, 0);
            await dismiss.up();
            await tester.pumpAndSettle();
            expect(sheet, findsNothing);
            expect(closes, 1);
            await tester.tap(find.text('Open'));
            await tester.pumpAndSettle();
            await tester.tapAt(above);
            await tester.pumpAndSettle();
            expect(sheet, findsNothing);
            expect(closes, 2);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final imperative in [false, true]) {
    for (final fillHeight in [false, true]) {
      testWidgets('inset bottom sheet clears consumed safe area and keyboard '
          '(imperative: $imperative, full height: $fillHeight)', (
        tester,
      ) async {
        const phone = Size(390, 844);
        tester.view.physicalSize = phone;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
        addTearDown(tester.view.reset);
        DSheetContent content() => DSheetContent(
          side: DSheetSide.bottom,
          inset: true,
          fillAvailableHeight: fillHeight,
          topBottomMaxHeightFactor: fillHeight ? 1 : null,
          children: const [DSheetBody(child: Text('Body'))],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: Scaffold(
              body: SafeArea(
                child: imperative
                    ? Builder(
                        builder: (context) => DButton(
                          label: const Text('Open'),
                          onPressed: () => showDSheet<void>(
                            context: context,
                            side: DSheetSide.bottom,
                            inset: true,
                            fillAvailableHeight: fillHeight,
                            builder: (_, _) => content(),
                          ),
                        ),
                      )
                    : DSheet<void>(
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
        final sheet = find.byType(DSheetContent);
        expect(tester.getRect(sheet).bottom, phone.height - 34 - DSpacing.md);
        expect(
          MediaQuery.paddingOf(tester.element(find.text('Body'))).bottom,
          0,
        );
        if (fillHeight) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          tester.view.padding = const FakeViewPadding(top: 59);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(sheet).bottom,
            phone.height - 300 - DSpacing.md,
          );
          tester.view.viewInsets = FakeViewPadding.zero;
          tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet).bottom, phone.height - 34 - DSpacing.md);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

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
    VoidCallback? onSwipeDismissRequested,
    bool disableAnimations = false,
    Size size = const Size(390, 844),
    DSheetSide side = DSheetSide.bottom,
    ScrollController? scroll,
    ValueChanged<DSheetChangeDetails<void>>? onOpenChanged,
    ValueNotifier<bool>? covering,
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
                        onSwipeDismissRequested: dismissOnSwipe
                            ? onSwipeDismissRequested
                            : null,
                        covering: covering,
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

                      builder: (_, _) => content(),
                    ),
                  ),
                )
              : DSheet<void>(
                  open: controlled ? true : null,

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
      (1800.0, 'helper'),
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
          await gesture.moveBy(const Offset(0, 12), timeStamp: elapsed);
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
        'upward bottom overscroll keeps the $platform $presentation open',
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
          await tester.drag(find.text('Swipe sheet'), const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet), bounds);
          expect(backdropOpacity(tester), 1);

          scroll.jumpTo(maximum - 400);
          await tester.pumpAndSettle();
          await tester.drag(list, const Offset(0, -120));
          await tester.pumpAndSettle();
          expect(scroll.offset, inExclusiveRange(maximum - 400, maximum));
          expect(tester.getRect(sheet), bounds);

          // A continuous drag first consumes the remaining content, then
          // keeps the sheet stationary beyond the bottom edge.
          scroll.jumpTo(maximum - 60);
          await tester.pumpAndSettle();
          final gesture = await tester.startGesture(tester.getCenter(list));
          await gesture.moveBy(const Offset(0, -30));
          await gesture.moveBy(const Offset(0, -100));
          await tester.pump();
          final top = tester.getTopLeft(sheet).dy;
          expect(top, bounds.top);
          await gesture.moveBy(const Offset(0, -120));
          await tester.pump();
          expect(tester.getTopLeft(sheet).dy, top);
          expect(backdropOpacity(tester), 1);
          await gesture.moveBy(const Offset(0, -160));
          await gesture.up();
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet), bounds);
          expect(backdropOpacity(tester), 1);
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
          expect(tester.getTopLeft(sheet).dy, bounds.top);
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
          onSwipeDismissRequested: () => requests++,
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

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final origin in ['header', 'scroll']) {
      for (final reducedMotion in [false, true]) {
        testWidgets(
          '$platform retained $origin swipe requests close at the threshold (reduced: $reducedMotion)',
          (tester) async {
            var requests = 0;
            var exits = 0;
            final sheet = find.byType(DSheetContent);
            late Rect bounds;
            await openSwipeSheet(
              tester,
              platform: platform,
              retained: true,
              controlled: true,
              disableAnimations: reducedMotion,
              onRetainedDismiss: () => exits++,
              onSwipeDismissRequested: () {
                expect(tester.getRect(sheet), bounds);
                requests++;
              },
            );
            bounds = tester.getRect(sheet);
            Finder target() => origin == 'header'
                ? find.text('Swipe sheet')
                : find.byType(ListView);
            final gesture = await tester.startGesture(
              tester.getCenter(target()),
            );
            await gesture.moveBy(const Offset(0, 30));
            await gesture.moveBy(const Offset(0, 120));
            await tester.pump();
            expect(requests, 0);
            expect(tester.getTopLeft(sheet).dy, greaterThan(bounds.top));
            expect(backdropOpacity(tester), lessThan(1));
            await gesture.moveBy(const Offset(0, 150));
            await tester.pump();
            expect(requests, 1);
            expect(exits, 0);
            expect(tester.getRect(sheet), bounds);
            expect(backdropOpacity(tester), 1);
            await gesture.moveBy(const Offset(0, 100));
            await tester.pump(const Duration(milliseconds: 16));
            expect(requests, 1);
            expect(tester.getRect(sheet), bounds);
            await gesture.up();
            await tester.pumpAndSettle();
            expect(requests, 1);
            expect(exits, 0);
            expect(tester.getRect(sheet), bounds);
            final repeat = await tester.startGesture(
              tester.getCenter(target()),
            );
            await repeat.moveBy(const Offset(0, 30));
            await repeat.moveBy(const Offset(0, 300));
            await tester.pump();
            expect(requests, 2);
            await repeat.cancel();
            await tester.pumpAndSettle();
            expect(tester.getRect(sheet), bounds);
            expect(exits, 0);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final reducedMotion in [false, true]) {
      testWidgets(
        '$platform retained swipe completes its exit before dismissal (reduced: $reducedMotion)',
        (tester) async {
          var exits = 0;
          final sheet = find.byType(DSheetContent);
          await openSwipeSheet(
            tester,
            platform: platform,
            retained: true,
            disableAnimations: reducedMotion,
            onRetainedDismiss: () => exits++,
          );
          final top = tester.getTopLeft(sheet).dy;
          final gesture = await tester.startGesture(
            tester.getCenter(find.text('Swipe sheet')),
          );
          await gesture.moveBy(const Offset(0, 30));
          await gesture.moveBy(const Offset(0, 300));
          await tester.pump();
          expect(exits, 0);
          expect(tester.getTopLeft(sheet).dy, greaterThan(top));
          await gesture.up();
          if (!reducedMotion) {
            await tester.pump();
            final releasedTop = tester.getTopLeft(sheet).dy;
            await tester.pump(const Duration(milliseconds: 16));
            expect(exits, 0);
            expect(tester.getTopLeft(sheet).dy, greaterThan(releasedTop));
          }
          await tester.pumpAndSettle();
          expect(exits, 1);
          expect(sheet, findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('a retained sheet covers its host until a swipe reveals it', (
    tester,
  ) async {
    final covering = ValueNotifier(false);
    addTearDown(covering.dispose);
    await openSwipeSheet(tester, retained: true, covering: covering);
    expect(backdropOpacity(tester), 1);
    expect(covering.value, isTrue);

    final title = find.text('Swipe sheet');
    final gesture = await tester.startGesture(tester.getCenter(title));
    await gesture.moveBy(const Offset(0, 30));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    expect(backdropOpacity(tester), lessThan(1));
    expect(covering.value, isFalse);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(backdropOpacity(tester), 1);
    expect(covering.value, isTrue);

    await tester.drag(title, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsNothing);
    expect(covering.value, isFalse);
    expect(tester.takeException(), isNull);
  });

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

  for (final scenario in ['desktop', 'side', 'mouse']) {
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

  testWidgets('under-keyboard sheet retains its full height and live insets', (
    tester,
  ) async {
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
          body: DSheet<void>(
            initialFocusNode: focus,
            trigger: DSheetTrigger(
              builder: (_, open) =>
                  DButton(label: const Text('Open'), onPressed: open),
            ),
            content: content(),
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
      expect(MediaQuery.viewInsetsOf(tester.element(editable)).bottom, inset);
      expect(tester.state(editable), same(state));
      expect(find.text('Retained draft'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
    }
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('narrow 200 percent text remains bounded', (tester) async {
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
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            viewInsets: EdgeInsets.only(bottom: 300),
            disableAnimations: true,
          ),
          child: Scaffold(
            // This fixture passes its keyboard metrics to the capped sheet.
            resizeToAvoidBottomInset: false,
            body: Center(
              child: DSheet<void>(
                trigger: DSheetTrigger(
                  builder: (context, open) =>
                      DButton(onPressed: open, label: const Text('Open')),
                ),
                content: DSheetContent(
                  side: DSheetSide.bottom,
                  topBottomMaxHeightFactor: .85,
                  children: [
                    const DSheetHeader(
                      children: [DSheetTitle(child: Text('Room chat'))],
                    ),
                    SizedBox(
                      height: 448,
                      child: DInput(
                        borderless: true,
                        maxLines: null,
                        expands: true,
                      ),
                    ),
                    const Text('End of room settings'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final last = find.text('End of room settings');
    expect(MediaQuery.viewInsetsOf(tester.element(last)).bottom, 300);
    final owner = Scrollable.of(tester.element(last), axis: Axis.vertical);
    final viewport = find.byElementPredicate(
      (element) => identical(element, owner.context),
    );
    final before = owner.position.pixels;
    expect(owner.position.maxScrollExtent, greaterThan(0));
    expect(tester.getRect(viewport).bottom, lessThanOrEqualTo(341));
    expect(last.hitTestable(), findsNothing);
    await tester.drag(viewport, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(owner.position.pixels, greaterThan(before));
    await tester.scrollUntilVisible(
      last.hitTestable(),
      80,
      scrollable: viewport,
      maxScrolls: 10,
    );
    await tester.pumpAndSettle();
    expect(owner.position.pixels, greaterThan(before));
    expect(last.hitTestable(), findsOneWidget);
    final visible = tester.getRect(viewport);
    final reached = tester.getRect(last);
    expect(reached.top, greaterThanOrEqualTo(visible.top - 1));
    expect(reached.bottom, lessThanOrEqualTo(visible.bottom + 1));
    expect(reached.bottom, lessThanOrEqualTo(341));
    expect(tester.getRect(find.byType(DSheetContent)).bottom, 640);
  });

  group('a page sheet under a band', () {
    late DSheetPageBand band;
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DSheetViewport(
            content: DSheetContent(
              side: DSheetSide.bottom,
              variant: DSheetVariant.page,
              showCloseButton: false,
              children: [
                Expanded(
                  child: Builder(
                    builder: (context) {
                      band = DSheetPageBand.maybeOf(context)!;
                      return const SizedBox.expand();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    DPageSurface card(WidgetTester tester) => tester.widget<DPageSurface>(
      find
          .descendant(
            of: find.byType(DSheetContent),
            matching: find.byType(DPageSurface),
          )
          .first,
    );

    BorderRadiusGeometry? corners(WidgetTester tester) => tester
        .widget<DPageSurface>(
          find
              .descendant(
                of: find.byType(DSheetContent),
                matching: find.byType(DPageSurface),
              )
              .first,
        )
        .borderRadius;
    const round = BorderRadius.vertical(
      top: Radius.circular(31),
      bottom: Radius.circular(22),
    );
    const squared = BorderRadius.vertical(bottom: Radius.circular(22));
    final grabber = find.byKey(const ValueKey('sheet-drag-handle'));

    testWidgets('squares its top and hides its grabber while one rests', (
      tester,
    ) async {
      await pump(tester);
      expect(corners(tester), round);
      expect(card(tester).depth, DSurfaceDepth.panel);
      final head = Object();
      band.report(head, condensed: true, resting: true, coversGrabber: true);
      await tester.pump();
      expect(corners(tester), squared);
      expect(grabber, findsNothing);
      // The band runs on into the screen's head: no edge along the top.
      expect(card(tester).depth, isNull);
      band.report(head, condensed: true, resting: false, coversGrabber: true);
      await tester.pump();
      expect(corners(tester), round);
      expect(grabber, findsNothing);
      band.report(head, condensed: true, resting: false, coversGrabber: false);
      await tester.pump();
      expect(grabber, findsOneWidget);
      expect(card(tester).depth, isNull);
      band.report(head, condensed: false, resting: false, coversGrabber: false);
      await tester.pump();
      expect(card(tester).depth, DSurfaceDepth.panel);
    });

    testWidgets('a withdrawn head is not heard from again', (tester) async {
      await pump(tester);
      final head = Object();
      band.report(head, condensed: true, resting: true, coversGrabber: true);
      await tester.pump();
      band.withdraw(head);
      band.report(head, condensed: true, resting: true, coversGrabber: true);
      await tester.pump();
      expect(corners(tester), round);
      expect(grabber, findsOneWidget);
    });

    testWidgets('a head that is not the band does not lift another one', (
      tester,
    ) async {
      await pump(tester);
      final resting = Object();
      band.report(resting, condensed: true, resting: true, coversGrabber: true);
      await tester.pump();
      band.withdraw(Object());
      await tester.pump();
      expect(corners(tester), squared);
    });
  });
}
