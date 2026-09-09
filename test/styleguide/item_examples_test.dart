import 'package:discourse_native/src/styleguide/examples/item_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'all Item examples render at reference and narrow RTL large-text sizes',
    (tester) async {
      for (final scale in [1.0, 2.0]) {
        for (final example in itemExamples.examples) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: Directionality(
                    textDirection: scale == 1
                        ? TextDirection.ltr
                        : TextDirection.rtl,
                    child: SingleChildScrollView(
                      child: SizedBox(
                        width: scale == 1 ? 640 : 260,
                        child: Builder(builder: example.builder),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: '${example.title} at $scale',
          );
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );
  testWidgets('temporary dropdown selects a person and dismisses', (
    tester,
  ) async {
    final example = itemExamples.examples.singleWhere(
      (e) => e.title == 'Dropdown',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: example.builder)),
      ),
    );
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('maxleiter'));
    await tester.pumpAndSettle();
    expect(find.text('Selected maxleiter'), findsOneWidget);
    expect(find.text('shadcn@vercel.com'), findsNothing);
  });
}
