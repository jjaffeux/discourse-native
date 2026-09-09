import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/input_otp_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registers every frozen documented composition', () {
    expect(componentExamples['input-otp'], same(inputOTPExamples));
    expect(inputOTPExamples.status, ComponentStatus.implemented);
    expect(
      inputOTPExamples.examples.map((example) => example.title),
      containsAll([
        'Default',
        'Pattern',
        'Separator',
        'Disabled',
        'Controlled',
        'Invalid',
        'Four Digits',
        'Alphanumeric',
        'Form',
        'RTL',
      ]),
    );
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('all examples render at 320px, ${scale}x text and RTL', (
      tester,
    ) async {
      for (final example in inputOTPExamples.examples) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: 320,
                        child: SingleChildScrollView(
                          child: example.builder(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: example.title);
        expect(find.byType(DInputOTP), findsWidgets, reason: example.title);
      }
    });
  }

  testWidgets('controlled and Form examples exercise their real callbacks', (
    tester,
  ) async {
    final controlled = inputOTPExamples.examples.singleWhere(
      (example) => example.title == 'Controlled',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(body: controlled.builder(context)),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    expect(find.text('You entered: 123456'), findsOneWidget);

    final form = inputOTPExamples.examples.singleWhere(
      (example) => example.title == 'Form',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(body: form.builder(context)),
        ),
      ),
    );
    final largeSlots = tester.widgetList<DInputOTPSlot>(
      find.byType(DInputOTPSlot),
    );
    expect(largeSlots, hasLength(6));
    expect(largeSlots.every((slot) => slot.lineHeight == 28), isTrue);
    await tester.tap(find.widgetWithText(DButton, 'Verify'));
    await tester.pump();
    expect(find.text('Enter all six digits'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '654321');
    await tester.tap(find.widgetWithText(DButton, 'Verify'));
    await tester.pump();
    expect(find.text('Verified 654321'), findsOneWidget);
    await tester.tap(find.widgetWithText(DButton, 'Reset'));
    await tester.pump();
    expect(find.text('Verified 654321'), findsNothing);
  });

  testWidgets('alphanumeric example requests a keyboard with letters', (
    tester,
  ) async {
    final alphanumeric = inputOTPExamples.examples.singleWhere(
      (example) => example.title == 'Alphanumeric',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(body: alphanumeric.builder(context)),
        ),
      ),
    );

    expect(
      tester.widget<TextField>(find.byType(TextField)).keyboardType,
      TextInputType.text,
    );
  });
}
