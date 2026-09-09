import 'package:discourse_native/src/styleguide/examples/scroll_area_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'reference examples render with large text, RTL and reduced motion',
    (tester) async {
      for (final example in scrollAreaExamples.examples) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SizedBox(
                    width: 360,
                    child: SingleChildScrollView(
                      child: Builder(builder: example.builder),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: example.title);
      }
    },
  );
}
