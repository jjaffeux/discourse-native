import 'package:discourse_native/src/styleguide/examples/questionnaire_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(
    Widget child, {
    double width = 640,
    double textScale = 1,
    TextDirection direction = TextDirection.ltr,
    bool reducedMotion = false,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 800),
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reducedMotion,
      ),
      child: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SizedBox(width: width - 32, child: child),
          ),
        ),
      ),
    ),
  );

  testWidgets('all documented examples build with their real components', (
    tester,
  ) async {
    expect(questionnaireExamples.examples, hasLength(9));
    for (final example in questionnaireExamples.examples) {
      await tester.pumpWidget(host(Builder(builder: example.builder)));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: example.title);
    }
  });

  testWidgets('all examples remain readable at narrow 200 percent RTL', (
    tester,
  ) async {
    for (final example in questionnaireExamples.examples) {
      await tester.pumpWidget(
        host(
          Builder(builder: example.builder),
          width: 280,
          textScale: 2,
          direction: TextDirection.rtl,
          reducedMotion: true,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: example.title);
    }
  });

  testWidgets('dialog example opens and closes through the real Dialog owner', (
    tester,
  ) async {
    final example = questionnaireExamples.examples.singleWhere(
      (value) => value.title == 'Dialog composition',
    );
    await tester.pumpWidget(host(Builder(builder: example.builder)));
    await tester.tap(find.text('Open clarification'));
    await tester.pumpAndSettle();
    expect(find.text('Clarify the request'), findsOneWidget);
    expect(find.text('What should the agent build next?'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Clarify the request'), findsNothing);
  });
}
