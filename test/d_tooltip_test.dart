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
}
