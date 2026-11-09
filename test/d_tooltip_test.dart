import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final open in [false, true]) {
    testWidgets(
      'ancestor scrolling cancels ${open ? "open" : "pending"} hover hint',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                controller: scroll,
                child: const Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DTooltip(
                        message: 'Details',
                        hoverDelay: Duration(milliseconds: 400),
                        child: SizedBox(
                          width: 900,
                          height: 48,
                          child: Text('Target'),
                        ),
                      ),
                    ),
                    SizedBox(height: 1200),
                  ],
                ),
              ),
            ),
          ),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: const Offset(20, 20));
        await tester.pump(Duration(milliseconds: open ? 500 : 200));
        await tester.pump();
        expect(find.text('Details'), open ? findsOneWidget : findsNothing);
        scroll.jumpTo(100);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Details'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('hiding a retained control cancels its pending hover tooltip', (
    tester,
  ) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (context, active, child) => TickerMode(
              enabled: active,
              child: Offstage(offstage: !active, child: child),
            ),
            child: const Center(
              child: DTooltip(
                message: 'Close',
                hoverDelay: Duration(milliseconds: 400),
                child: SizedBox.square(dimension: 48, child: Text('Target')),
              ),
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text('Target')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Close'), findsNothing);

    active.value = false;
    await tester.pump();
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Close', skipOffstage: false), findsNothing);

    active.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsNothing);

    await mouse.moveTo(tester.getCenter(find.text('Target')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsOneWidget);

    await mouse.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('a showing tooltip leaves with its page in the same frame', (
    tester,
  ) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await tester.pumpWidget(_retained(active));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text('Target')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsOneWidget);

    active.value = false;
    await tester.pump();
    expect(find.text('Close', skipOffstage: false), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Close', skipOffstage: false), findsNothing);

    active.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsNothing);
    await mouse.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(find.text('Target')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('hiding stops a tooltip partway through its fade', (
    tester,
  ) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await tester.pumpWidget(_retained(active));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text('Target')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    active.value = false;
    await tester.pump();
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a tooltip obeys the TickerMode of wherever it is moved to', (
    tester,
  ) async {
    final key = GlobalKey();
    Widget placed({required bool hidden}) {
      final tooltip = DTooltip(
        key: key,
        message: 'Close',
        hoverDelay: Duration.zero,
        child: const SizedBox.square(dimension: 48, child: Text('Target')),
      );
      return MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TickerMode(
                  enabled: false,
                  child: hidden
                      ? tooltip
                      : const SizedBox.square(dimension: 48),
                ),
                TickerMode(
                  enabled: true,
                  child: hidden
                      ? const SizedBox.square(dimension: 48)
                      : tooltip,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(5, 5));
    Future<void> hover() async {
      await mouse.moveTo(tester.getCenter(find.text('Target')));
      await tester.pumpAndSettle();
    }

    Future<void> leave() async {
      await mouse.moveTo(const Offset(5, 5));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(placed(hidden: true));
    await hover();
    expect(find.text('Close'), findsNothing);
    await leave();

    await tester.pumpWidget(placed(hidden: false));
    await tester.pumpAndSettle();
    await hover();
    expect(find.text('Close'), findsOneWidget);
    await leave();

    await tester.pumpWidget(placed(hidden: true));
    await tester.pumpAndSettle();
    await hover();
    expect(find.text('Close'), findsNothing);
  });
}

Widget _retained(ValueNotifier<bool> active) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(
    body: ValueListenableBuilder<bool>(
      valueListenable: active,
      builder: (context, active, child) => TickerMode(
        enabled: active,
        child: Offstage(offstage: !active, child: child),
      ),
      child: const Center(
        child: DTooltip(
          message: 'Close',
          hoverDelay: Duration(milliseconds: 400),
          child: SizedBox.square(dimension: 48, child: Text('Target')),
        ),
      ),
    ),
  ),
);
