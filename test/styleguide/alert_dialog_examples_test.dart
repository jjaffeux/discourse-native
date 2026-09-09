import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/alert_dialog_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('covers every frozen documented example', () {
    expect(
      alertDialogExamples.examples.map((example) => example.title),
      containsAll(<String>[
        'Basic',
        'Small',
        'Media',
        'Small with Media',
        'Destructive',
        'RTL',
        'Controlled and typed',
      ]),
    );
    expect(
      alertDialogExamples.notes,
      contains('Outside presses never dismiss'),
    );
    expect(alertDialogExamples.notes, contains('no Dialog corner close'));
  });

  testWidgets('all examples open at narrow 200 percent RTL without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final dark in [false, true]) {
      for (final example in alertDialogExamples.examples) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 760),
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
        expect(
          find.byWidgetPredicate((widget) => widget is DAlertDialog),
          findsWidgets,
        );
        await tester.tap(find.byType(DButton).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: example.title);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    }
  });
}
