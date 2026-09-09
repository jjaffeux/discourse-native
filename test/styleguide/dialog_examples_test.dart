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
}
