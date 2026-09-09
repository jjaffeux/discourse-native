import 'package:discourse_native/src/styleguide/examples/field_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  Widget child, {
  double width = 500,
  double scale = 1,
  bool rtl = false,
}) => MaterialApp(
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
      ),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  for (final example in fieldExamples.examples) {
    testWidgets('${example.title} wraps at 280px with 200% RTL text', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Builder(builder: example.builder),
          width: 280,
          scale: 2,
          rtl: true,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(example.code, contains('void main()'));
    });
  }
  testWidgets(
    'responsive example validates saves and resets its sole field owner',
    (tester) async {
      await tester.pumpWidget(host(const FieldResponsiveExample()));
      await tester.tap(find.text('Submit profile'));
      await tester.pump();
      expect(find.text('Provide your full name.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Evil Rabbit');
      await tester.tap(find.text('Submit profile'));
      await tester.pump();
      expect(find.text('Saved locally: Evil Rabbit'), findsOneWidget);
      await tester.pumpWidget(
        host(const FieldResponsiveExample(), width: 280, scale: 2),
      );
      expect(find.text('Evil Rabbit'), findsNWidgets(2));
      await tester.ensureVisible(find.text('Reset profile'));
      await tester.tap(find.text('Reset profile'));
      await tester.pump();
      expect(find.text('Saved locally: Evil Rabbit'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(find.text('Provide your full name.'), findsNothing);
    },
  );
}
