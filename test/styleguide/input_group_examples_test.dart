import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/input_group_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Input Group registers actual runnable examples', () {
    expect(componentExamples['input-group'], same(inputGroupExamples));
    expect(inputGroupExamples.examples, hasLength(9));
  });

  for (final palette in [
    StyleguideTheme.light,
    StyleguideTheme.dark,
    StyleguideTheme.forest,
    StyleguideTheme.plum,
  ]) {
    testWidgets(
      'Input Group examples fit narrow RTL at 200% in ${palette.name}',
      (tester) async {
        for (final example in inputGroupExamples.examples) {
          await tester.pumpWidget(
            MaterialApp(
              theme: palette.resolve(AppTheme.light),
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Center(
                      child: SizedBox(
                        width: 320,
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Builder(
                              key: ValueKey(example.title),
                              builder: example.builder,
                            ),
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
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.byType(DInputGroup), findsAtLeastNWidgets(1));
          expect(tester.takeException(), isNull, reason: example.title);
        }
      },
    );
  }

  testWidgets('Button handoff fixture keeps editor and action state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SizedBox(width: 360, child: InputGroupButtonHandoffExample()),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'abc');
    await tester.tap(find.text('Search'));
    await tester.pump();
    expect(find.text('Searched abc'), findsOneWidget);

    await tester.tap(find.text('Show loading'));
    await tester.pump();
    expect(find.byType(DSpinner), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'still editable');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'still editable',
    );
  });
}
