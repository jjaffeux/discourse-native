import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final dismissOnSwipe in [null, true, false]) {
      testWidgets(
        'imperative $platform Sheet with dismissOnSwipe=$dismissOnSwipe '
        'respects a deliberate downward swipe',
        (tester) async {
          await _open(
            tester,
            platform: platform,
            dismissOnSwipe: dismissOnSwipe,
          );
          final surface = find.byType(DSheetContent);
          final before = tester.getRect(surface);
          await tester.drag(find.text('Swipe sheet'), const Offset(0, 400));
          await tester.pumpAndSettle();
          if (dismissOnSwipe == false) {
            expect(surface, findsOneWidget);
            expect(tester.getRect(surface), before);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
          }
          expect(surface, findsNothing);
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }

  for (final side in [DSheetSide.top, DSheetSide.bottom]) {
    for (final cap in [null, 640.0, 1400.0]) {
      testWidgets('fixed-edge $side Sheet honors optional width cap $cap', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _open(tester, side: side, widthCap: cap);
        final bounds = tester.getRect(find.byType(DSheetContent));
        final width = cap == 640 ? 640.0 : 1000.0;
        expect(bounds.width, width);
        expect(bounds.center.dx, 500);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('imperative Sheet dismissal guard covers every close request', (
    tester,
  ) async {
    var allow = false;
    DSheetController<void>? controller;
    await _open(
      tester,
      platform: TargetPlatform.iOS,
      canDismiss: () => allow,
      onController: (value) => controller = value,
    );
    final surface = find.byType(DSheetContent);
    final before = tester.getRect(surface);
    controller!.close();
    await tester.pumpAndSettle();
    expect(surface, findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(surface, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(surface, findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(surface, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(surface, findsOneWidget);
    await tester.drag(find.text('Swipe sheet'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(tester.getRect(surface), before);
    allow = true;
    controller!.close();
    await tester.pumpAndSettle();
    expect(surface, findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}

Future<void> _open(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.macOS,
  DSheetSide side = DSheetSide.bottom,
  bool? dismissOnSwipe,
  double? widthCap,
  bool Function()? canDismiss,
  ValueChanged<DSheetController<void>>? onController,
}) async {
  Widget content(BuildContext context, DSheetController<void> controller) {
    onController?.call(controller);
    return DSheetContent(
      side: side,
      fillAvailableHeight: true,
      children: const [
        DSheetHeader(children: [DSheetTitle(child: Text('Swipe sheet'))]),
      ],
    );
  }

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: Builder(
          builder: (context) => DButton(
            label: const Text('Open'),
            onPressed: () => dismissOnSwipe == null
                ? showDSheet<void>(
                    context: context,
                    side: side,
                    fillAvailableHeight: true,
                    topBottomMaxWidth: widthCap,
                    canDismiss: canDismiss,
                    builder: content,
                  )
                : showDSheet<void>(
                    context: context,
                    side: side,
                    fillAvailableHeight: true,
                    dismissOnSwipe: dismissOnSwipe,
                    topBottomMaxWidth: widthCap,
                    canDismiss: canDismiss,
                    builder: content,
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
