import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/button_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('every Button example supports narrow large RTL text', (
    tester,
  ) async {
    for (final theme in [
      AppTheme.light,
      AppTheme.dark,
      StyleguideTheme.forest.resolve(AppTheme.light),
      StyleguideTheme.plum.resolve(AppTheme.dark),
    ]) {
      for (final example in buttonExamples.examples) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: 260,
                        child: Builder(builder: example.builder),
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
        expect(find.byType(DButton), findsWidgets);
        await tester.pumpWidget(const SizedBox());
      }
    }
  });
  testWidgets('loading example blocks repeats and safely survives removal', (
    tester,
  ) async {
    final example = buttonExamples.examples.singleWhere(
      (e) => e.title == 'Spinner and disabled',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: example.builder)),
      ),
    );
    await tester.tap(find.text('Generate'));
    await tester.pump();
    expect(find.text('Generating'), findsOneWidget);
    await tester.tap(find.text('Generating'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('1 operations completed'), findsOneWidget);
    await tester.tap(find.text('Generate'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('navigation example opens and returns from its local route', (
    tester,
  ) async {
    final example = buttonExamples.examples.singleWhere(
      (e) => e.title.startsWith('Links,'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: example.builder)),
      ),
    );
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to examples'));
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsOneWidget);
  });
}
