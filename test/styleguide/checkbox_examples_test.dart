import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/checkbox_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final example in checkboxExamples.examples) {
    testWidgets(
      '${example.title} renders real controls in all themes at 200% RTL',
      (tester) async {
        for (final theme in StyleguideTheme.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.resolve(AppTheme.light),
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
                        width: 360,
                        child: Builder(builder: example.builder),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(DCheckbox), findsWidgets);
          expect(tester.takeException(), null);
        }
      },
    );
  }
  testWidgets('table partial/all/none and form recovery work', (tester) async {
    Future<void> show(int index) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: checkboxExamples.examples[index].builder),
        ),
      ),
    );
    await show(3);
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is DCheckbox && widget.semanticLabel == 'Select all people',
      ),
    );
    await tester.pump();
    expect(find.text('4 selected'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is DCheckbox && widget.semanticLabel == 'Select all people',
      ),
    );
    await tester.pump();
    expect(find.text('0 selected'), findsOneWidget);
    await show(4);
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Please accept the terms.'), findsOneWidget);
    await tester.tap(find.text('Accept terms and conditions'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Saved: true'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(find.text('Saved: true'), findsNothing);
  });
}
