import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/keyboard_test_harness.dart';

Future<void> openMenu(
  WidgetTester tester, {
  required TargetPlatform platform,
  required ScrollController scroll,
  int count = 60,
  ValueListenable<int>? counts,
  ValueListenable<bool> loading = const AlwaysStoppedAnimation(false),
  bool sizeToContent = true,
  bool reducedMotion = false,
  bool settle = true,
  VoidCallback? onContentLayout,
  Size size = const Size(390, 844),
  double devicePixelRatio = 1,
}) async {
  tester.view.physicalSize = size * devicePixelRatio;
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.viewPadding = FakeViewPadding(
    top: 47 * devicePixelRatio,
    bottom: 34 * devicePixelRatio,
  );
  tester.view.padding = FakeViewPadding(
    top: 47 * devicePixelRatio,
    bottom: 34 * devicePixelRatio,
  );
  addTearDown(tester.view.reset);
  Widget menu(int rows) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DInput(hintText: 'Add a filter'),
      Flexible(
        child: ListView.builder(
          controller: scroll,
          shrinkWrap: true,
          itemExtent: 40,
          itemCount: rows,
          itemBuilder: (_, index) =>
              DButton(label: Text('Filter $index'), onPressed: () {}),
        ),
      ),
    ],
  );
  final contents = counts == null
      ? menu(count)
      : ValueListenableBuilder<int>(
          valueListenable: counts,
          builder: (_, rows, _) => menu(rows),
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
            child: ValueListenableBuilder<bool>(
              valueListenable: loading,
              builder: (_, pending, _) => DPopover(
                sheetOnMobile: true,
                mobileSheetVariant: DSheetVariant.adaptiveMenu,
                mobileSheetSizeToContent: sizeToContent,
                mobileSheetContentLoading: pending,
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

/// The test screen's foot, and the radius its floating sheet's bottom corners
/// reach there. A floating sheet is full width and lifts off the foot, so
/// these corners are the progress of floating that survives it.
const _foot = 34.0;
final _floatedRadius = const DMobileDockGeometry(foot: _foot).endRadius(24);

double footRadius(WidgetTester tester, Finder sheet) {
  final surface = tester.widget<Material>(
    find.descendant(of: sheet, matching: find.byType(Material)).first,
  );
  return (surface.borderRadius as BorderRadius).bottomLeft.x;
}

/// How far a sheet has floated off the foot, 0 to 1, with no keyboard.
double floatProgress(WidgetTester tester, Finder sheet) =>
    footRadius(tester, sheet) / _floatedRadius;

/// The corner radius at progress [p] while the keyboard rises with it: from
/// the screen corner's to the keyboard's 24, never swelling past either.
double keyboardFootRadius(double p) =>
    (_floatedRadius + (24 - _floatedRadius) * p) * p;

/// A floating sheet spans the screen, rounds its foot corners and stands off
/// the bottom edge: by the foot's room, or by the bar's inset alone once the
/// keyboard takes that room (then [keyboard] is the keyboard's height).
void expectFloating(WidgetTester tester, Finder sheet, {double keyboard = 0}) {
  final rect = tester.getRect(sheet);
  expect(rect.left, 0);
  expect(rect.right, 390);
  expect(
    footRadius(tester, sheet),
    closeTo(keyboard > 0 ? 24 : _floatedRadius, .01),
  );
  expect(
    844 - keyboard - rect.bottom,
    closeTo(
      keyboard > 0 ? 6 : const DMobileDockGeometry(foot: _foot).endLift,
      .01,
    ),
  );
}

/// A docked sheet spans the screen and its foot corners are square.
void expectDocked(WidgetTester tester, Finder sheet) {
  final rect = tester.getRect(sheet);
  expect(rect.left, 0);
  expect(rect.right, 390);
  expect(footRadius(tester, sheet), 0);
}

void main() {
  setUp(() {
    const channel = MethodChannel('org.discourse.native/keyboard');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw MissingPluginException(),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  });

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
        expect(footRadius(tester, sheet), 0);
        expect(tester.getRect(sheet).left, 0);
      }
    }
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsOneWidget);
  });

  testWidgets(
    'legacy bridge waits for keyboard before raising and resizing while floating',
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
        footRadius(tester, sheet),
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
        footRadius(tester, sheet),
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
        expect(current.left, 0);
        expect(current.right, 390);
        expect(current.top, inExclusiveRange(55, previous.top));
        expect(current.height, lessThan(previous.height));
        expect(scroll.offset, 0, reason: 'focus keeps the list at its place');
        expect(
          footRadius(tester, sheet),
          closeTo(
            keyboardFootRadius((opened.top - current.top) / (opened.top - 55)),
            .01,
          ),
          reason: 'floating and position share the same animation progress',
        );
        previous = current;
      }
      await tester.pump(const Duration(milliseconds: 153));
      final placed = tester.getRect(sheet);
      expectFloating(tester, sheet, keyboard: 300);
      expect(placed.top, closeTo(55, 1));
      expect(placed.bottom, closeTo(538, 1));
      expect(scroll.offset, 0);
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet), placed);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
    },
  );

  for (final sizeToContent in [true, false]) {
    for (final curve in [0, 3, 7]) {
      testWidgets(
        'native keyboard timing drives every sheet bound (content: $sizeToContent, curve: $curve)',
        (tester) async {
          const channel = MethodChannel('org.discourse.native/keyboard');
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            (_) async => false,
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null),
          );
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          await openMenu(
            tester,
            platform: TargetPlatform.iOS,
            scroll: scroll,
            sizeToContent: sizeToContent,
            devicePixelRatio: 3,
          );
          final sheet = find.byType(DSheetContent);
          final opened = tester.getRect(sheet);
          await tester.tap(find.byType(EditableText));
          await tester.pump();
          expect(tester.getRect(sheet), opened);
          await sendKeyboardFrame(
            tester,
            curve: curve,
            spring: curve == 7
                ? {'mass': 1, 'stiffness': 100, 'damping': 20, 'velocity': 0}
                : null,
          );
          await tester.pump();
          expect(tester.getRect(sheet), opened);
          for (var step = 1; step <= 4; step++) {
            // The frame is known before metrics arrive. Later intermediate
            // insets must not multiply or restart the native transition.
            if (step > 1) {
              tester.view.viewInsets = FakeViewPadding(bottom: step * 60 * 3);
            }
            await tester.pump(const Duration(milliseconds: 50));
            final t = step / 8;
            final p = curve == 0
                ? Curves.easeInOut.transform(t)
                : curve == 7
                ? 1 - (1 + 4 * t) * math.exp(-4 * t)
                : t;
            final rect = tester.getRect(sheet);
            expect(rect.left, 0);
            expect(rect.right, 390);
            expect(
              footRadius(tester, sheet),
              closeTo(keyboardFootRadius(p), .1),
            );
            expect(rect.top, closeTo(opened.top + (55 - opened.top) * p, .2));
            expect(scroll.offset, 0);
          }
          tester.view.viewInsets = const FakeViewPadding(bottom: 900);
          await tester.pump(const Duration(milliseconds: 201));
          final shown = tester.getRect(sheet);
          expect(shown.top, closeTo(55, 1));
          expectFloating(tester, sheet, keyboard: 300);
          expect(shown.bottom, closeTo(538, 1));
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet), shown);
          await sendKeyboardFrame(tester, inset: 360, milliseconds: 200);
          await tester.pump();
          expect(tester.getRect(sheet), shown);
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.getRect(sheet).bottom, closeTo(523, 1));
          await tester.pump(const Duration(milliseconds: 151));
          expect(tester.getRect(sheet).bottom, closeTo(478, 1));
          await sendKeyboardFrame(tester, inset: 0, milliseconds: 300);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          expect(footRadius(tester, sheet), greaterThan(0));
          expect(tester.getRect(sheet).bottom, inExclusiveRange(478, 821));
          await tester.pump(const Duration(milliseconds: 151));
          final hidden = tester.getRect(sheet);
          expect(hidden.bottom, closeTo(821, 1));
          expectFloating(tester, sheet);
          tester.view.viewInsets = FakeViewPadding.zero;
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet), hidden);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('opening with an existing keyboard uses its cached final frame', (
    tester,
  ) async {
    const channel = MethodChannel('org.discourse.native/keyboard');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'keyboardTransition'
          ? keyboardFramePayload(elapsedMilliseconds: 400)
          : true,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await openMenu(
      tester,
      platform: TargetPlatform.iOS,
      scroll: scroll,
      sizeToContent: false,
    );
    expect(tester.getRect(find.byType(DSheetContent)).bottom, closeTo(538, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a covered sheet refreshes its keyboard target after a child closes',
    (tester) async {
      const channel = MethodChannel('org.discourse.native/keyboard');
      Map<String, Object>? snapshot;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'keyboardTransition' ? snapshot : false,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await openMenu(
        tester,
        platform: TargetPlatform.iOS,
        scroll: scroll,
        sizeToContent: false,
      );
      snapshot = keyboardFramePayload(milliseconds: 0);
      await sendKeyboardFrame(tester, milliseconds: 0);
      await tester.pumpAndSettle();
      final sheet = find.byType(DSheetContent, skipOffstage: false);
      final shown = tester.getRect(sheet);
      final closed = showDDialog<void>(
        context: tester.element(sheet),
        builder: (_, controller) => DDialogContent(
          children: [
            DButton(
              label: const Text('Close child'),
              onPressed: () => controller.close(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      snapshot = keyboardFramePayload(inset: 0, milliseconds: 0);
      await sendKeyboardFrame(tester, inset: 0, milliseconds: 0);
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet), shown);
      await tester.tap(find.text('Close child'));
      await tester.pumpAndSettle();
      await closed;
      expectFloating(tester, sheet);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion applies the native keyboard frame without animating',
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
      await openMenu(
        tester,
        platform: TargetPlatform.iOS,
        scroll: scroll,
        sizeToContent: false,
        reducedMotion: true,
      );
      await sendKeyboardFrame(tester);
      await tester.pumpAndSettle();
      final shown = tester.getRect(find.byType(DSheetContent));
      expect(shown.bottom, closeTo(538, 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(find.byType(DSheetContent)), shown);
      await sendKeyboardFrame(tester, inset: 0);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(DSheetContent)).bottom,
        closeTo(821, 1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an immediate keyboard cancellation stops the pending rise', (
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
    await openMenu(
      tester,
      platform: TargetPlatform.iOS,
      scroll: scroll,
      sizeToContent: false,
    );
    await sendKeyboardFrame(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await sendKeyboardFrame(tester, inset: 0, milliseconds: 0);
    await tester.pump();
    final cancelled = tester.getRect(find.byType(DSheetContent));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(DSheetContent)), cancelled);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final sizeToContent in [true, false]) {
      for (final origin in ['handle', 'content']) {
        testWidgets(
          'upward $origin pull floats with expansion on $platform (content: $sizeToContent)',
          (tester) async {
            final scroll = ScrollController();
            addTearDown(scroll.dispose);
            await openMenu(
              tester,
              platform: platform,
              scroll: scroll,
              sizeToContent: sizeToContent,
            );
            final sheet = find.byType(DSheetContent);
            final opened = tester.getRect(sheet);
            void expectProgress() {
              final current = tester.getRect(sheet);
              final progress = (opened.top - current.top) / (opened.top - 55);
              expect(current.left, 0);
              expect(current.right, 390);
              expect(
                current.bottom,
                closeTo(opened.bottom + (821 - opened.bottom) * progress, .01),
              );
              expect(
                footRadius(tester, sheet),
                closeTo(_floatedRadius * progress, .01),
              );
              expect(
                scroll.offset,
                0,
                reason: 'expanding keeps the current row',
              );
            }

            final drag = await tester.startGesture(
              tester.getCenter(
                origin == 'handle'
                    ? find.byKey(const ValueKey('sheet-drag-handle'))
                    : find.byType(ListView),
              ),
            );
            await drag.moveBy(const Offset(0, -40));
            await tester.pump();
            for (var step = 0; step < 5; step++) {
              await drag.moveBy(const Offset(0, -35));
              await tester.pump(const Duration(milliseconds: 16));
              expect(
                footRadius(tester, sheet),
                inExclusiveRange(0, _floatedRadius),
              );
              expectProgress();
            }
            await drag.up();
            await tester.pump();
            for (var frame = 0; frame < 4; frame++) {
              await tester.pump(const Duration(milliseconds: 32));
              expectProgress();
            }
            await tester.pumpAndSettle();
            expect(tester.getRect(sheet), const Rect.fromLTRB(0, 55, 390, 821));
            expect(scroll.offset, 0);
            expect(tester.takeException(), isNull);
          },
        );
      }

      testWidgets(
        'cancelled expansion restores its spacing on $platform (content: $sizeToContent)',
        (tester) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          await openMenu(
            tester,
            platform: platform,
            scroll: scroll,
            sizeToContent: sizeToContent,
          );
          final sheet = find.byType(DSheetContent);
          final opened = tester.getRect(sheet);
          final drag = await tester.startGesture(
            tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
          );
          await drag.moveBy(const Offset(0, -40));
          await drag.moveBy(const Offset(0, -100));
          await tester.pump();
          final pulled = footRadius(tester, sheet);
          expect(pulled, inExclusiveRange(0, _floatedRadius));
          await drag.moveBy(const Offset(0, 35));
          await tester.pump();
          expect(footRadius(tester, sheet), inExclusiveRange(0, pulled));
          await drag.cancel();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
          final restoring = tester.getRect(sheet);
          expect(footRadius(tester, sheet), inExclusiveRange(0, pulled));
          expect(
            floatProgress(tester, sheet),
            closeTo((opened.top - restoring.top) / (opened.top - 55), .01),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet), opened);
          expect(scroll.offset, 0);
          expect(tester.takeException(), isNull);
        },
      );

      for (final reducedMotion in [false, true]) {
        testWidgets('backdrop swipes share the adaptive threshold on $platform '
            '(content: $sizeToContent, reduced: $reducedMotion)', (
          tester,
        ) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          await openMenu(
            tester,
            platform: platform,
            scroll: scroll,
            sizeToContent: sizeToContent,
            reducedMotion: reducedMotion,
          );
          final sheet = find.byType(DSheetContent);
          final opened = tester.getRect(sheet);
          final above = Offset(opened.center.dx, opened.top - 50);
          final threshold = (844 - opened.top) * .3;
          Future<TestGesture> pull(double distance) async {
            final gesture = await tester.startGesture(above);
            await gesture.moveBy(const Offset(0, 40));
            await tester.pump();
            final moved = tester.getRect(sheet).top - opened.top;
            await gesture.moveBy(Offset(0, distance - moved));
            await tester.pump();
            expect(
              tester.getRect(sheet).top,
              closeTo(opened.top + distance, .1),
            );
            expect(scroll.offset, 0);
            return gesture;
          }

          final short = await pull(threshold - 1);
          await short.up();
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet), opened);
          final cancelled = await pull(threshold + 20);
          await cancelled.cancel();
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet), opened);
          await tester.dragFrom(above, const Offset(0, -100));
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet), opened);
          await tester.dragFrom(above, const Offset(100, 0));
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet), opened);
          final dismiss = await pull(threshold + 1);
          await dismiss.up();
          if (!reducedMotion) {
            await tester.pump();
            await tester.pump();
            final released = tester.getRect(sheet);
            await tester.pump(const Duration(milliseconds: 60));
            expect(tester.getRect(sheet).top, greaterThan(released.top));
          }
          await tester.pumpAndSettle();
          expect(sheet, findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('an expansion fling cannot start list momentum on $platform', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await openMenu(
        tester,
        platform: platform,
        scroll: scroll,
        sizeToContent: false,
      );
      final sheet = find.byType(DSheetContent);
      await tester.fling(find.byType(ListView), const Offset(0, -120), 5000);
      await tester.pump();
      expect(scroll.offset, 0);
      expect(scroll.position.isScrollingNotifier.value, isFalse);
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(scroll.offset, 0);
        expect(footRadius(tester, sheet), greaterThan(0));
      }
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet).top, closeTo(55, 1));
      await tester.fling(find.byType(ListView), const Offset(0, -120), 1800);
      await tester.pump();
      final released = scroll.offset;
      expect(released, greaterThan(0));
      expect(scroll.position.isScrollingNotifier.value, isTrue);
      await tester.pump(const Duration(milliseconds: 64));
      expect(scroll.offset, greaterThan(released));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'short async results float the sheet through later loading on $platform',
      (tester) async {
        final scroll = ScrollController();
        final counts = ValueNotifier(0);
        final loading = ValueNotifier(true);
        addTearDown(scroll.dispose);
        addTearDown(counts.dispose);
        addTearDown(loading.dispose);
        await openMenu(
          tester,
          platform: platform,
          scroll: scroll,
          counts: counts,
          loading: loading,
          sizeToContent: false,
        );
        final sheet = find.byType(DSheetContent);
        expectDocked(tester, sheet);
        counts.value = 2;
        loading.value = false;
        var animated = false;
        for (var frame = 0; frame < 24; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final radius = footRadius(tester, sheet);
          animated |= radius > 0 && radius < _floatedRadius;
        }
        expect(animated, isTrue);
        await tester.pumpAndSettle();
        expectFloating(tester, sheet);
        loading.value = true;
        counts.value = 60;
        await tester.pumpAndSettle();
        expectFloating(tester, sheet);
        loading.value = false;
        await tester.pumpAndSettle();
        expectFloating(tester, sheet);
        await tester.tapAt(const Offset(8, 20));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open filters'));
        await tester.pumpAndSettle();
        expectDocked(tester, sheet);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'fixed menu reserves its height across async results on $platform',
      (tester) async {
        final scroll = ScrollController();
        final counts = ValueNotifier(0);
        final loading = ValueNotifier(true);
        var layouts = 0;
        addTearDown(scroll.dispose);
        addTearDown(counts.dispose);
        addTearDown(loading.dispose);
        await openMenu(
          tester,
          platform: platform,
          scroll: scroll,
          counts: counts,
          loading: loading,
          sizeToContent: false,
          onContentLayout: () => layouts++,
        );
        final sheet = find.byType(DSheetContent);
        expect(tester.getRect(sheet).top, closeTo(844 * .45, 1));
        expectDocked(tester, sheet);
        counts.value = 60;
        loading.value = false;
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(sheet, findsOneWidget);
          expect(tester.getRect(sheet).top, closeTo(844 * .45, 1));
          expectDocked(tester, sheet);
        }
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet).height, closeTo(844 * .55, 1));
        final drag = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
        );
        await drag.moveBy(const Offset(0, 40));
        await tester.pump();
        final before = tester.getRect(sheet);
        final beforeLayouts = layouts;
        for (var step = 0; step < 10; step++) {
          await drag.moveBy(const Offset(0, 3));
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            tester.getRect(sheet).top,
            closeTo(before.top + (step + 1) * 3, .1),
          );
          expect(tester.getRect(sheet).size, before.size);
          expect(layouts, beforeLayouts);
        }
        await drag.cancel();
        await tester.pumpAndSettle();
        await tester.fling(
          find.byKey(const ValueKey('sheet-drag-handle')),
          const Offset(0, 70),
          6000,
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet).top, closeTo(844 * .45, 1));
        await expand(tester);
        expect(tester.getRect(sheet).top, closeTo(55, 1));
        counts.value = 2;
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet).top, closeTo(55, 1));
        expect(tester.getRect(sheet).bottom, closeTo(821, 1));
        await tester.tap(find.byType(EditableText));
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        final keyboard = tester.getRect(sheet);
        expect(keyboard.top, closeTo(55, 1));
        expect(keyboard.bottom, closeTo(538, 1));
        counts.value = 0;
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet), keyboard);
        tester.view.viewInsets = FakeViewPadding.zero;
        await tester.pumpAndSettle();
        final beforeExit = tester.getRect(sheet);
        await tester.tapAt(const Offset(8, 20));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(tester.getRect(sheet).top, greaterThan(beforeExit.top));
        expect(tester.getRect(sheet).height, beforeExit.height);
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

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
        expect(
          tester.getRect(sheet),
          Rect.fromLTRB(0, lower.top, 390, lower.bottom - 23),
          reason: 'committed expansion keeps its floating clearance',
        );
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
        'expanded menu keeps floating while scrolling on $platform (reduced: $reduced)',
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
            tester.getRect(find.byType(ListView)).bottom,
            closeTo(opened.bottom - 10, .1),
            reason: 'the scroll viewport extends through the bottom safe area',
          );
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
          expectFloating(tester, sheet);
          scroll.jumpTo(scroll.position.maxScrollExtent);
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expectFloating(tester, sheet);
          await tester.pumpAndSettle();
          final floating = tester.getRect(sheet);
          expectFloating(tester, sheet);
          expect(floating.bottom, closeTo(821, 1));
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
            reason: 'the same drag stays active after leaving the end',
          );
          await reverse.up();
          await tester.pumpAndSettle();
          expectFloating(tester, sheet);
          scroll.jumpTo(scroll.offset - 200);
          await tester.pumpAndSettle();
          expectFloating(tester, sheet);
          await tester.tapAt(const Offset(8, 20));
          await tester.pumpAndSettle();
          expect(sheet, findsNothing);
          await tester.tap(find.text('Open filters'));
          await tester.pumpAndSettle();
          expectDocked(tester, sheet);
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
      expectFloating(tester, sheet);
      expect(tester.getRect(sheet).bottom, closeTo(821, 1));
      await tester.tapAt(const Offset(10, 60));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await openMenu(tester, platform: platform, scroll: scroll);
      expectDocked(tester, sheet);
      await tester.tap(find.byType(EditableText));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expectFloating(tester, sheet, keyboard: 300);
      expect(tester.getRect(sheet).bottom, closeTo(538, 1));
      expect(tester.getRect(sheet).top, closeTo(55, 1));
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expectFloating(tester, sheet);
      expect(tester.getRect(sheet).bottom, closeTo(821, 1));
      expect(tester.getRect(sheet).top, closeTo(55, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('expansion leaves scrolling to the next gesture on $platform', (
      tester,
    ) async {
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
      expect(tester.getRect(sheet).top, closeTo(55, 1));
      expect(scroll.offset, 0);
      await drag.up();
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expectFloating(tester, sheet);
      await tester.fling(find.byType(ListView), const Offset(0, -120), 1800);
      await tester.pump();
      final released = scroll.offset;
      expect(released, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 64));
      expect(scroll.offset, greaterThan(released));
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
    });
    for (final reduced in [false, true]) {
      testWidgets(
        'handle expansion floats and a downward pull dismisses on $platform (reduced: $reduced)',
        (tester) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          final semantics = tester.ensureSemantics();
          try {
            await openMenu(
              tester,
              platform: platform,
              scroll: scroll,
              reducedMotion: reduced,
            );
            expect(find.bySemanticsLabel('Expand'), findsOneWidget);
            final sheet = find.byType(DSheetContent);
            final opened = tester.getRect(sheet);
            await tester.tap(find.byKey(const ValueKey('sheet-drag-handle')));
            await tester.pump();
            if (!reduced) {
              await tester.pump(const Duration(milliseconds: 64));
              final moving = tester.getRect(sheet);
              expect(
                footRadius(tester, sheet),
                inExclusiveRange(0, _floatedRadius),
              );
              expect(
                floatProgress(tester, sheet),
                closeTo((opened.top - moving.top) / (opened.top - 55), .01),
              );
            }
            expect(
              footRadius(tester, sheet),
              reduced
                  ? closeTo(_floatedRadius, .01)
                  : inExclusiveRange(0, _floatedRadius),
            );
            await tester.pumpAndSettle();
            expect(
              tester.getRect(find.byType(DSheetContent)).top,
              closeTo(55, 1),
            );
            expectFloating(tester, sheet);
            expect(tester.getRect(sheet).bottom, 821);
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

  testWidgets('imperative adaptive menus can reserve their opening height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => DButton(
              label: const Text('Open'),
              onPressed: () => showDSheet<void>(
                context: context,
                side: DSheetSide.bottom,
                variant: DSheetVariant.adaptiveMenu,
                sizeToContent: false,
                builder: (_, _) => const DSheetContent(
                  side: DSheetSide.bottom,
                  variant: DSheetVariant.adaptiveMenu,
                  showCloseButton: false,
                  children: [Text('Loading menu')],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(DSheetContent)).top,
      closeTo(844 * .45, 1),
    );
    expect(tester.takeException(), isNull);
  });

  for (final sizeToContent in [true, false]) {
    for (final backdrop in [false, true]) {
      testWidgets(
        'retained adaptive menu finishes its swipe (content: $sizeToContent, backdrop: $backdrop)',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var dismissals = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: TargetPlatform.iOS),
              home: DSheetViewport(
                onDismiss: () => dismissals++,
                content: DSheetContent(
                  variant: DSheetVariant.adaptiveMenu,
                  sizeToContent: sizeToContent,
                  side: DSheetSide.bottom,
                  showCloseButton: false,
                  children: const [
                    SizedBox(height: 180, child: Text('Retained menu')),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final sheet = find.byType(DSheetContent);
          final above = Offset(195, tester.getRect(sheet).top - 40);
          if (backdrop) {
            await tester.tapAt(above);
            await tester.pumpAndSettle();
            expect(
              dismissals,
              0,
              reason: 'a retained backdrop tap stays inert',
            );
          }
          await tester.dragFrom(
            backdrop
                ? above
                : tester.getCenter(
                    find.byKey(const ValueKey('sheet-drag-handle')),
                  ),
            Offset(0, sizeToContent ? 130 : 200),
          );
          expect(dismissals, 0);
          await tester.pumpAndSettle();
          expect(dismissals, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
