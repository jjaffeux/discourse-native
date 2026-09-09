import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/chart_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all Chart examples render at narrow 200 percent RTL', (
    tester,
  ) async {
    for (final example in chartExamples.examples) {
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
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: 260,
                    child: Builder(builder: example.builder),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: example.title);
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets('interactive reference switches its selected series locally', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ChartInteractiveExample()),
        ),
      ),
    );
    expect(find.text('7,324'), findsOneWidget);
    await tester.tap(find.text('Mobile'));
    await tester.pump();
    expect(find.text('7,250'), findsOneWidget);
    await tester.tapAt(
      tester.getTopLeft(
            find.byWidgetPredicate((widget) => widget is DBarChart),
          ) +
          const Offset(12, 80),
    );
    await tester.pump();
    expect(find.text('150'), findsOneWidget);
  });
}
