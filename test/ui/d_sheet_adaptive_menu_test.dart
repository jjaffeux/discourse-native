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
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DInput(hintText: 'Add a filter'),
                    Flexible(
                      child: ListView.builder(
                        controller: scroll,
                        shrinkWrap: true,
                        itemExtent: 40,
                        itemCount: count,
                        itemBuilder: (_, index) => DButton(
                          label: Text('Filter $index'),
                          onPressed: () {},
                        ),
                      ),
                    ),
                  ],
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

  testWidgets('iOS waits for keyboard completion before animating margins', (
    tester,
  ) async {
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
      expect(tester.getRect(sheet).left, 0);
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
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(sheet).left, inExclusiveRange(0, 6));
    await tester.pumpAndSettle();
    expect(tester.getRect(sheet).left, 6);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
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
            const Offset(0, 450),
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
