import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/sheet_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Side example preserves the reference capped scroll layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final example = sheetExamples.examples.singleWhere(
      (example) => example.title == 'Side',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: example.builder)),
      ),
    );

    for (final side in const [
      DSheetSide.top,
      DSheetSide.right,
      DSheetSide.bottom,
      DSheetSide.left,
    ]) {
      await tester.tap(find.widgetWithText(DButton, side.name));
      await tester.pumpAndSettle();

      final sheet = find.byType(DSheetContent);
      final rect = tester.getRect(sheet);
      if (side == DSheetSide.top || side == DSheetSide.bottom) {
        expect(rect.height, 300, reason: side.name);
      } else {
        expect(rect.height, 600, reason: side.name);
      }
      expect(
        find.descendant(of: sheet, matching: find.byType(DSheetBody)),
        findsOneWidget,
        reason: side.name,
      );
      expect(find.text('Save changes'), findsOneWidget, reason: side.name);
      expect(find.text('Cancel'), findsOneWidget, reason: side.name);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('all Sheet examples open at narrow 200 percent RTL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final example in sheetExamples.examples) {
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
      expect(find.byType(DSheetContent), findsOneWidget, reason: example.title);
      expect(tester.takeException(), isNull, reason: example.title);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}
