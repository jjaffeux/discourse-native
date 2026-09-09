import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/button_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registers every documented section in reference order', () {
    expect(buttonExamples.examples.map((example) => example.title), [
      'Variants',
      'Size',
      'With icon and rounded',
      'Spinner and disabled',
      'Button Group',
      'As link and shortcuts',
      'Rich labels and trigger states',
      'RTL',
      'Application variants',
    ]);
  });

  testWidgets(
    'the Button Group example opens its menu and keeps the label selection',
    (tester) async {
      final example = buttonExamples.examples.singleWhere(
        (e) => e.title == 'Button Group',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(body: Builder(builder: example.builder)),
        ),
      );
      expect(find.byType(DButtonGroup), findsNWidgets(4));
      expect(find.byTooltip('Go Back'), findsOneWidget);
      await tester.tap(find.text('Report'));
      await tester.pump();
      expect(find.text('Report activated · Label: personal'), findsOneWidget);

      await tester.tap(find.byTooltip('More Options'));
      await tester.pumpAndSettle();
      for (final item in [
        'Mark as Read',
        'Archive',
        'Snooze',
        'Add to Calendar',
        'Add to List',
        'Label As...',
        'Trash',
      ]) {
        expect(
          find.descendant(
            of: find.byType(DDropdownMenuContent),
            matching: find.text(item),
          ),
          findsOneWidget,
          reason: item,
        );
      }
      await tester.tap(find.text('Label As...'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      expect(find.text('Report activated · Label: work'), findsOneWidget);
      await tester.tap(find.text('Trash'));
      await tester.pumpAndSettle();
      expect(find.text('Trash activated · Label: work'), findsOneWidget);
      expect(find.text('Mark as Read'), findsNothing);
    },
  );

  testWidgets('the Button Group example drops Go Back below 640px', (
    tester,
  ) async {
    final example = buttonExamples.examples.singleWhere(
      (e) => e.title == 'Button Group',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(600, 800)),
          child: Scaffold(body: Builder(builder: example.builder)),
        ),
      ),
    );
    expect(find.byTooltip('Go Back'), findsNothing);
    expect(find.text('Archive'), findsOneWidget);
  });

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
      (e) => e.title == 'As link and shortcuts',
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
