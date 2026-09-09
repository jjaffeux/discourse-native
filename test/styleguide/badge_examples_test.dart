import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/badge_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Badge catalogue registers all six documented example sections', () {
    expect(componentExamples['badge'], same(badgeExamples));
    expect(badgeExamples.examples, hasLength(6));
    expect(
      badgeExamples.examples.every((e) => e.code.contains('DBadge')),
      isTrue,
    );
  });
  for (var index = 0; index < badgeExamples.examples.length; index++) {
    testWidgets(
      '${badgeExamples.examples[index].title} fits 280px RTL at 200% across palettes',
      (tester) async {
        for (final theme in [
          AppTheme.light,
          AppTheme.dark,
          StyleguideTheme.forest.resolve(AppTheme.light),
          StyleguideTheme.plum.resolve(AppTheme.light),
        ]) {
          await _pump(tester, index, theme: theme, width: 280, scale: 2);
          expect(find.byType(DBadge), findsWidgets);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
  testWidgets('loading completion and restart update real spinners', (
    tester,
  ) async {
    await _pump(tester, 2);
    expect(find.byType(DSpinner), findsNWidgets(2));
    await tester.tap(find.text('Complete operation'));
    await tester.pump();
    expect(find.text('Deleted'), findsOneWidget);
    expect(find.byType(DSpinner), findsNothing);
    await _pump(tester, 2, theme: StyleguideTheme.plum.resolve(AppTheme.light));
    expect(find.text('Generated'), findsOneWidget);
    await tester.tap(find.text('Restart operation'));
    await tester.pump();
    expect(find.byType(DSpinner), findsNWidgets(2));
  });
  testWidgets(
    'local navigation returns and disabled actions preserve counter across themes',
    (tester) async {
      await _pump(tester, 3);
      await tester.tap(find.text('Open Link'));
      await tester.pumpAndSettle();
      expect(find.text('Badge link detail'), findsOneWidget);
      await tester.tap(find.text('Return to badges'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Count 0'));
      await tester.pump();
      await tester.tap(find.text('Disable actions'));
      await tester.pump();
      await _pump(
        tester,
        3,
        theme: StyleguideTheme.forest.resolve(AppTheme.light),
      );
      await tester.tap(find.text('Count 1'));
      await tester.pump();
      expect(find.text('Count 1'), findsOneWidget);
      expect(
        tester
            .widget<DBadge>(find.byKey(const ValueKey('badge-counter')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Enable actions'));
      await tester.pump();
      await tester.tap(find.text('Count 1'));
      await tester.pump();
      expect(find.text('Count 2'), findsOneWidget);
    },
  );
  testWidgets(
    'language switch changes direction and retains state through palette changes',
    (tester) async {
      await _pump(tester, 5);
      expect(find.text('متحقق'), findsOneWidget);
      await tester.tap(find.text('Use English'));
      await tester.pump();
      expect(find.text('Verified'), findsOneWidget);
      await _pump(tester, 5, theme: AppTheme.dark);
      expect(find.text('Verified'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('Verified'))),
        TextDirection.ltr,
      );
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  int index, {
  ThemeData? theme,
  double width = 580,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: width,
              child: MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Builder(
                    builder: badgeExamples.examples[index].builder,
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
}
