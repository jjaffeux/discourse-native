import 'package:discourse_native/src/styleguide/examples/card_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all Card examples render at narrow 200 percent RTL', (
    tester,
  ) async {
    for (final example in cardExamples.examples) {
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
  testWidgets('login validates locally and spacing retains draft', (
    tester,
  ) async {
    final example = cardExamples.examples.singleWhere(
      (e) => e.title == 'Shared spacing',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: Builder(builder: example.builder)),
        ),
      ),
    );
    await tester.tap(find.text('Login').last);
    await tester.pump();
    expect(find.text('Enter an email address'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).first,
      'local@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'local-only');
    await tester.tap(find.text('32px'));
    await tester.pump();
    expect(find.text('local@example.com'), findsOneWidget);
    await tester.ensureVisible(find.text('Login').last);
    await tester.tap(find.text('Login').last);
    await tester.pump();
    expect(find.text('Signed in locally'), findsOneWidget);
  });
}
