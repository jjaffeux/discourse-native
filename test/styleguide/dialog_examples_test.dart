import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/dialog_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all Dialog examples open at narrow 200 percent RTL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final example in dialogExamples.examples) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Builder(builder: example.builder),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final buttons = find.byType(DButton);
      expect(buttons, findsWidgets, reason: example.title);
      await tester.tap(buttons.first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: example.title);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('reference close-button examples preserve their composition', (
    tester,
  ) async {
    final customClose = dialogExamples.examples.singleWhere(
      (example) => example.title == 'Custom Close Button',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: customClose.builder)),
      ),
    );
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    final popup = tester.getRect(find.byType(DDialogContent));
    final footer = tester.getRect(find.byType(DDialogFooter));
    final close = tester.getRect(find.widgetWithText(DButton, 'Close'));
    expect(popup.width, 448);
    expect(close.left, footer.left + DSpacing.lg);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.widgetWithText(DButton, 'Close'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    final noClose = dialogExamples.examples.singleWhere(
      (example) => example.title == 'No Close Button',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: noClose.builder)),
      ),
    );
    await tester.tap(find.text('No Close Button'));
    await tester.pumpAndSettle();

    expect(find.byType(DDialogFooter), findsNothing);
    expect(find.byTooltip('Close'), findsNothing);
    expect(find.widgetWithText(DButton, 'Close'), findsNothing);
  });
}
