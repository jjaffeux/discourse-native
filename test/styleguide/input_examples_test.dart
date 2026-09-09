import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/input_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Input registers actual runnable reference examples', () {
    expect(componentExamples['input'], same(inputExamples));
    expect(inputExamples.examples, hasLength(7));
  });
  for (final palette in [
    StyleguideTheme.light,
    StyleguideTheme.dark,
    StyleguideTheme.forest,
    StyleguideTheme.plum,
  ]) {
    testWidgets('Input examples fit narrow RTL at 200% in ${palette.name}', (
      tester,
    ) async {
      for (final example in inputExamples.examples) {
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
        await tester.pumpAndSettle();
        expect(
          find.byType(DInput).evaluate().isNotEmpty ||
              find.byType(DFileInput).evaluate().isNotEmpty,
          isTrue,
        );
        expect(tester.takeException(), isNull, reason: example.title);
      }
    });
  }
  testWidgets(
    'example validates required fields then saves and resets independent local values',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(child: InputFormExample()),
          ),
        ),
      );
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(find.text('Enter your name.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Jordan');
      await tester.enterText(
        find.byType(TextField).at(1),
        'jordan@example.com',
      );
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(find.text('Saved Jordan · jordan@example.com'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(find.text('Form reset'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
    },
  );
}
