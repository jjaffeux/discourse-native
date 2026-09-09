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
    expect(find.byType(DSpinner), findsNWidgets(DBadgeVariant.values.length));
    expect(
      tester
          .widgetList<DBadge>(find.byType(DBadge))
          .map((badge) => badge.variant)
          .toSet(),
      DBadgeVariant.values.toSet(),
    );
    await tester.tap(find.text('Complete operation'));
    await tester.pump();
    expect(find.text('Deleted'), findsOneWidget);
    expect(find.byType(DSpinner), findsNothing);
    await _pump(tester, 2, theme: StyleguideTheme.plum.resolve(AppTheme.light));
    expect(find.text('Generated'), findsOneWidget);
    await tester.tap(find.text('Restart operation'));
    await tester.pump();
    expect(find.byType(DSpinner), findsNWidgets(DBadgeVariant.values.length));
  });
  testWidgets('icon example covers both slots across every variant', (
    tester,
  ) async {
    await _pump(tester, 1);
    final badges = tester.widgetList<DBadge>(find.byType(DBadge)).toList();
    expect(
      badges.where((badge) => badge.leading != null).map((b) => b.variant),
      containsAll(DBadgeVariant.values),
    );
    expect(
      badges.where((badge) => badge.trailing != null).map((b) => b.variant),
      containsAll(DBadgeVariant.values),
    );
  });
  testWidgets('custom colors include linked solid and adaptive palettes', (
    tester,
  ) async {
    await _pump(tester, 4);
    final badges = tester.widgetList<DBadge>(find.byType(DBadge)).toList();
    expect(badges, hasLength(10));
    expect(badges.take(4).map((badge) => badge.backgroundColor), const [
      Color(0xff2563eb),
      Color(0xff16a34a),
      Color(0xff0284c7),
      Color(0xff9333ea),
    ]);
    expect(badges.skip(4).take(5).map((badge) => badge.backgroundColor), const [
      Color(0xffeff6ff),
      Color(0xfff0fdf4),
      Color(0xfff0f9ff),
      Color(0xfffaf5ff),
      Color(0xfffef2f2),
    ]);
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
    'language cycle covers the documented Arabic, English and Hebrew directions and retains state through palette changes',
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
      await tester.tap(find.text('Use Hebrew'));
      await tester.pump();
      expect(find.text('מאומת'), findsOneWidget);
      expect(find.text('סימנייה'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('מאומת'))),
        TextDirection.rtl,
      );
      await tester.tap(find.text('Use Arabic'));
      await tester.pump();
      expect(find.text('متحقق'), findsOneWidget);
      expect(find.text('إشارة مرجعية'), findsOneWidget);
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
