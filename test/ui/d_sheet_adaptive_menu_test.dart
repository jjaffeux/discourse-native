import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openMenu(
  WidgetTester tester, {
  required TargetPlatform platform,
  required ScrollController scroll,
  int count = 60,
  bool reducedMotion = false,
  bool settle = true,
  VoidCallback? onContentLayout,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);
  final contents = Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DInput(hintText: 'Add a filter'),
      Flexible(
        child: ListView.builder(
          controller: scroll,
          shrinkWrap: true,
          itemExtent: 40,
          itemCount: count,
          itemBuilder: (_, index) =>
              DButton(label: Text('Filter $index'), onPressed: () {}),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: MediaQuery(
        data: MediaQueryData.fromView(
          tester.view,
        ).copyWith(disableAnimations: reducedMotion),
        child: Scaffold(
          body: Center(
            child: DPopover(
              sheetOnMobile: true,
              mobileSheetVariant: DSheetVariant.adaptiveMenu,
              content: DPopoverContent(
                semanticLabel: 'Filters',
                child: onContentLayout == null
                    ? contents
                    : LayoutBuilder(
                        builder: (_, _) {
                          onContentLayout();
                          return contents;
                        },
                      ),
              ),
              child: DPopoverTrigger(
                builder: (_, trigger) => DButton(
                  label: const Text('Open filters'),
                  onPressed: trigger.toggle,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open filters'));
  if (settle) await tester.pumpAndSettle();
}

Future<void> expand(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const ValueKey('sheet-drag-handle')),
    const Offset(0, -350),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opening frames never paint the expanded sheet at the top', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await openMenu(
      tester,
      platform: TargetPlatform.iOS,
      scroll: scroll,
      settle: false,
    );
    for (var frame = 0; frame < 24; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final sheet = find.byType(DSheetContent);
      if (sheet.evaluate().isNotEmpty) {
        expect(
          tester.getTopLeft(sheet).dy,
          greaterThanOrEqualTo(844 * .45 - 1),
        );
      }
    }
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsOneWidget);
  });

  testWidgets(
    'iOS finishes keyboard, then raises and resizes the sheet with margins',
    (tester) async {
      const channel = MethodChannel('org.discourse.native/keyboard');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => false,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await openMenu(tester, platform: TargetPlatform.iOS, scroll: scroll);
      final sheet = find.byType(DSheetContent);
      final opened = tester.getRect(sheet);
      await tester.tap(find.byType(EditableText));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getRect(sheet).left,
        0,
        reason: 'focus is not keyboard completion',
      );
      for (final inset in [100.0, 200.0, 300.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester.getRect(sheet),
          opened,
          reason: 'the sheet waits for the keyboard',
        );
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.getRect(sheet).left,
        0,
        reason: 'native completion takes precedence over a timeout',
      );
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('keyboardReady', true),
        ),
        (_) {},
      );
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(sheet), opened);
      var previous = opened;
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 32));
        final current = tester.getRect(sheet);
        expect(current.left, inExclusiveRange(previous.left, 6));
        expect(current.top, inExclusiveRange(55, previous.top));
        expect(current.height, lessThan(previous.height));
        expect(scroll.offset, 0, reason: 'focus keeps the list at its place');
        expect(
          current.left / 6,
          closeTo((opened.top - current.top) / (opened.top - 55), .01),
          reason: 'margins and position share the same animation progress',
        );
        previous = current;
      }
      await tester.pump(const Duration(milliseconds: 153));
      final placed = tester.getRect(sheet);
      expect(placed.left, 6);
      expect(placed.top, closeTo(55, 1));
      expect(placed.bottom, closeTo(538, 1));
      expect(scroll.offset, 0);
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet), placed);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final expanded in [false, true]) {
      for (final origin in ['handle', 'content']) {
        testWidgets(
          'short fast $origin pull restores ${expanded ? 'expanded' : 'lower'} sheet on $platform',
          (tester) async {
            final scroll = ScrollController();
            addTearDown(scroll.dispose);
            await openMenu(tester, platform: platform, scroll: scroll);
            if (expanded) await expand(tester);
            final sheet = find.byType(DSheetContent);
            final opened = tester.getRect(sheet);
            final target = origin == 'handle'
                ? find.byKey(const ValueKey('sheet-drag-handle'))
                : find.byType(ListView);
            await tester.fling(target, const Offset(0, 70), 6000);
            await tester.pumpAndSettle();
            expect(tester.getRect(sheet), opened);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets(
      'a deliberate pull lowers an expanded sheet before dismissal on $platform',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await openMenu(tester, platform: platform, scroll: scroll);
        final sheet = find.byType(DSheetContent);
        final lower = tester.getRect(sheet);
        await expand(tester);
        final handle = find.byKey(const ValueKey('sheet-drag-handle'));
        await tester.timedDrag(
          handle,
          const Offset(0, 300),
          const Duration(milliseconds: 400),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet), lower);
        await tester.timedDrag(
          handle,
          const Offset(0, 200),
          const Duration(milliseconds: 400),
        );
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
      },
    );

    for (final expanded in [false, true]) {
      testWidgets(
        'outside tap slides ${expanded ? 'expanded' : 'lower'} sheet down quickly on $platform',
        (tester) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          await openMenu(tester, platform: platform, scroll: scroll);
          if (expanded) await expand(tester);
          final sheet = find.byType(DSheetContent);
          final opened = tester.getRect(sheet);
          await tester.tapAt(const Offset(8, 20));
          await tester.pump();
          await tester.pump();
          expect(
            tester.getRect(sheet),
            opened,
            reason: 'exit starts from the current geometry',
          );
          await tester.pump(const Duration(milliseconds: 60));
          expect(tester.getRect(sheet).top, greaterThan(opened.top + 20));
          expect(
            sheet,
            findsOneWidget,
            reason: 'the sheet stays mounted during its exit',
          );
          await tester.pump(const Duration(milliseconds: 140));
          await tester.pump();
          expect(sheet, findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final count in [2, 60]) {
      testWidgets(
        'dragging follows the finger without laying out menu content ($count rows) on $platform',
        (tester) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          var layouts = 0;
          await openMenu(
            tester,
            platform: platform,
            scroll: scroll,
            onContentLayout: () => layouts++,
            count: count,
          );
          final sheet = find.byType(DSheetContent);
          final handle = find.byKey(const ValueKey('sheet-drag-handle'));
          final drag = await tester.startGesture(tester.getCenter(handle));
          await drag.moveBy(const Offset(0, 40));
          await tester.pump();
          final before = tester.getRect(sheet);
          final beforeLayouts = layouts;
          for (var i = 0; i < 10; i++) {
            await drag.moveBy(const Offset(0, 3));
            await tester.pump(const Duration(milliseconds: 16));
            final current = tester.getRect(sheet);
            expect(current.top, closeTo(before.top + (i + 1) * 3, .1));
            expect(current.size, before.size);
            expect(scroll.offset, 0);
            expect(layouts, beforeLayouts);
          }
          await drag.cancel();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final reduced in [false, true]) {
      testWidgets(
        'adaptive menu expands, floats at its end, and returns on $platform (reduced: $reduced)',
        (tester) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          await openMenu(
            tester,
            platform: platform,
            scroll: scroll,
            reducedMotion: reduced,
          );
          final sheet = find.byType(DSheetContent);
          final opened = tester.getRect(sheet);
          expect(opened.left, 0);
          expect(opened.width, 390);
          expect(opened.top, closeTo(844 * .45, 1));
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .focusNode
                .hasFocus,
            isFalse,
          );
          await expand(tester);
          final expanded = tester.getRect(sheet);
          expect(expanded.top, closeTo(55, 1));
          expect(expanded.left, 0);
          scroll.jumpTo(scroll.position.maxScrollExtent);
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          if (!reduced) {
            expect(tester.getRect(sheet).left, inExclusiveRange(0, 6));
          }
          await tester.pumpAndSettle();
          final floating = tester.getRect(sheet);
          expect(floating.left, 6);
          expect(floating.right, 384);
          expect(floating.bottom, closeTo(804, 1));
          expect(floating.top, closeTo(expanded.top, 1));
          expect(scroll.position.extentAfter, closeTo(0, 1));
          await tester.pump(const Duration(seconds: 1));
          expect(tester.getRect(sheet), floating);
          final reverse = await tester.startGesture(
            tester.getCenter(find.byType(ListView)),
          );
          await reverse.moveBy(const Offset(0, 40));
          await reverse.moveBy(const Offset(0, 6));
          await tester.pump();
          await tester.pump();
          final distance = scroll.position.extentAfter;
          expect(
            distance,
            greaterThan(0),
            reason: 'small reverse drags must leave the end',
          );
          expect(
            distance,
            lessThan(40),
            reason: 'exercise the former snap-back range',
          );
          await reverse.moveBy(const Offset(0, 6));
          await tester.pump();
          expect(
            scroll.position.extentAfter,
            greaterThan(distance),
            reason: 'the same drag stays active while margins change',
          );
          await reverse.up();
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet).left, 0);
          scroll.jumpTo(scroll.offset - 200);
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet).left, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('short content and the system keyboard float on $platform', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await openMenu(tester, platform: platform, scroll: scroll, count: 2);
      final sheet = find.byType(DSheetContent);
      expect(tester.getRect(sheet).left, 6);
      expect(tester.getRect(sheet).bottom, closeTo(804, 1));
      await tester.tapAt(const Offset(10, 60));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await openMenu(tester, platform: platform, scroll: scroll);
      expect(tester.getRect(sheet).left, 0);
      await tester.tap(find.byType(EditableText));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet).left, 6);
      expect(tester.getRect(sheet).bottom, closeTo(538, 1));
      expect(tester.getRect(sheet).top, closeTo(55, 1));
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet).left, 0);
      expect(tester.getRect(sheet).top, closeTo(55, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'one content drag expands then scrolls; a cancelled pull restores on $platform',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await openMenu(tester, platform: platform, scroll: scroll);
        final sheet = find.byType(DSheetContent);
        final drag = await tester.startGesture(
          const Offset(195, 600),
          kind: PointerDeviceKind.touch,
        );
        await drag.moveBy(const Offset(0, -100));
        await tester.pump();
        expect(tester.getRect(sheet).top, lessThan(844 * .45));
        expect(scroll.offset, 0);
        await drag.moveBy(const Offset(0, -350));
        await tester.pump();
        expect(scroll.offset, greaterThan(0));
        await drag.up();
        await tester.pumpAndSettle();
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        final before = tester.getRect(sheet);
        final pull = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
        );
        await pull.moveBy(const Offset(0, 20));
        await pull.moveBy(const Offset(0, 90));
        await tester.pump();
        expect(tester.getRect(sheet).top, greaterThan(before.top));
        await pull.cancel();
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet), before);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'handle offers expansion and a downward pull dismisses on $platform',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final semantics = tester.ensureSemantics();
        try {
          await openMenu(tester, platform: platform, scroll: scroll);
          expect(find.bySemanticsLabel('Expand'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('sheet-drag-handle')));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byType(DSheetContent)).top,
            closeTo(55, 1),
          );
          expect(find.bySemanticsLabel('Collapse'), findsOneWidget);
          await tester.timedDrag(
            find.byKey(const ValueKey('sheet-drag-handle')),
            const Offset(0, 600),
            const Duration(milliseconds: 500),
          );
          await tester.pumpAndSettle();
          expect(find.byType(DSheetContent), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  for (final height in [600.0, 1000.0]) {
    testWidgets(
      'adaptive pull threshold scales with $height and is checked on release',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await openMenu(
          tester,
          platform: TargetPlatform.iOS,
          scroll: scroll,
          size: Size(390, height),
        );
        final sheet = find.byType(DSheetContent);
        final handle = find.byKey(const ValueKey('sheet-drag-handle'));
        final opened = tester.getRect(sheet);
        final threshold = (height - opened.top) * .3;
        Future<TestGesture> pullTo(double offset) async {
          final gesture = await tester.startGesture(tester.getCenter(handle));
          await gesture.moveBy(const Offset(0, 40));
          await tester.pump(const Duration(milliseconds: 16));
          final moved = tester.getRect(sheet).top - opened.top;
          await gesture.moveBy(Offset(0, offset - moved));
          await tester.pump(const Duration(milliseconds: 16));
          return gesture;
        }

        final retreat = await pullTo(threshold + 20);
        await retreat.moveBy(const Offset(0, -21));
        await tester.pump();
        expect(
          tester.getRect(sheet).top - opened.top,
          closeTo(threshold - 1, .01),
        );
        await retreat.up();
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet), opened);
        final dismiss = await pullTo(threshold + 1);
        await dismiss.up();
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
      },
    );
  }

  testWidgets('the keyboard does not make the pull threshold shorter', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await openMenu(tester, platform: TargetPlatform.iOS, scroll: scroll);
    await tester.tap(find.byType(EditableText));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final sheet = find.byType(DSheetContent);
    final opened = tester.getRect(sheet);
    await tester.timedDrag(
      find.byKey(const ValueKey('sheet-drag-handle')),
      const Offset(0, 200),
      const Duration(milliseconds: 400),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(sheet), opened);
  });

  testWidgets(
    'outside dismissal during opening starts from its visible position',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await openMenu(
        tester,
        platform: TargetPlatform.iOS,
        scroll: scroll,
        settle: false,
      );
      final sheet = find.byType(DSheetContent);
      for (var frame = 0; frame < 8 && sheet.evaluate().isEmpty; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(sheet, findsOneWidget);
      expect(
        ModalRoute.of(tester.element(sheet))!.animation!.status,
        AnimationStatus.forward,
      );
      final opened = tester.getRect(sheet);
      await tester.tapAt(const Offset(8, 20));
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(sheet), opened);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getRect(sheet).top, greaterThan(opened.top));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
    },
  );

  testWidgets('retained adaptive menus finish their swipe before dismissal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var dismissals = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: DSheetViewport(
          onDismiss: () => dismissals++,
          content: const DSheetContent(
            variant: DSheetVariant.adaptiveMenu,
            side: DSheetSide.bottom,
            showCloseButton: false,
            children: [SizedBox(height: 180, child: Text('Retained menu'))],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('sheet-drag-handle')),
      const Offset(0, 130),
    );
    expect(dismissals, 0);
    await tester.pumpAndSettle();
    expect(dismissals, 1);
    expect(tester.takeException(), isNull);
  });
}
