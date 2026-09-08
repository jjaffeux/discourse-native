import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/spinner_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final example in spinnerExamples.examples) {
    testWidgets(
      '${example.title} fits narrow RTL with large text and a site palette',
      (tester) async {
        await _pump(
          tester,
          spinnerExamples.examples.indexOf(example),
          narrow: true,
        );
        expect(tester.takeException(), isNull);
        expect(componentExamples['spinner'], same(spinnerExamples));
      },
    );
  }

  testWidgets('customization controls update the real public spinner', (
    tester,
  ) async {
    await _pump(tester, 0);
    await tester.tap(find.text('Custom artwork'));
    await tester.tap(find.text('Accent color'));
    await tester.tap(find.text('Size 32'));
    await tester.tap(find.text('Animate sample'));
    await tester.pump();
    final sample = tester.widget<DSpinner>(
      find.byKey(const ValueKey('spinner-custom-sample')),
    );
    expect(sample.size, 32);
    expect(sample.animating, isFalse);
    expect(sample.child, isA<Icon>());
    expect(sample.color, AppTheme.light.colorScheme.primary);
    await _pump(tester, 0, dark: true);
    final changed = tester.widget<DSpinner>(
      find.byKey(const ValueKey('spinner-custom-sample')),
    );
    expect(
      changed.color,
      StyleguideTheme.plum.resolve(AppTheme.light).colorScheme.primary,
    );
    expect(changed.size, 32);
    expect(changed.child, isA<Icon>());
  });

  testWidgets('button example handles disabled busy, failure and completion', (
    tester,
  ) async {
    await _pump(tester, 1);
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(find.text('Save changes in progress'), findsOneWidget);
    expect(
      tester.widget<DButton>(find.widgetWithText(DButton, 'Loading…')).loading,
      isTrue,
    );
    await tester.tap(find.text('Fail operation'));
    await tester.pump();
    expect(find.text('Operation failed. Try again.'), findsOneWidget);
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.tap(find.text('Complete operation'));
    await tester.pump();
    expect(find.text('Operation complete'), findsOneWidget);
    expect(
      tester
          .widget<DButton>(find.widgetWithText(DButton, 'Save changes'))
          .loading,
      isFalse,
    );
  });

  testWidgets(
    'badge completion removes indicators and inline placement follows RTL',
    (tester) async {
      await _pump(tester, 2, narrow: true);
      final syncing = find.text('Syncing');
      final spinner = find.byType(DSpinner).first;
      expect(
        tester.getCenter(spinner).dx,
        greaterThan(tester.getCenter(syncing).dx),
      );
      await tester.tap(find.text('Spinner at inline end'));
      await tester.pump();
      expect(
        tester.getCenter(spinner).dx,
        lessThan(tester.getCenter(syncing).dx),
      );
      await tester.tap(find.text('Activity in progress'));
      await tester.pump();
      expect(find.byType(DSpinner), findsNothing);
      expect(find.text('Synced'), findsOneWidget);
      expect(find.text('Updated'), findsOneWidget);
      expect(find.text('Processed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'input validation preserves edits through theme changes, rejection and retry',
    (tester) async {
      await _pump(tester, 3, narrow: true);
      await tester.enterText(
        find.widgetWithText(TextField, 'Subject'),
        'A sample subject',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Message'),
        'A message to validate',
      );
      await tester.ensureVisible(find.text('Validate sample'));
      await tester.tap(find.text('Validate sample'));
      await tester.pump();
      expect(find.byType(DSpinner), findsNWidgets(2));
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Subject'))
            .enabled,
        isFalse,
      );
      await _pump(tester, 3, narrow: true, dark: true);
      expect(find.text('A sample subject'), findsOneWidget);
      expect(find.text('A message to validate'), findsOneWidget);
      await tester.ensureVisible(find.text('Reject sample'));
      await tester.tap(find.text('Reject sample'));
      await tester.pump();
      expect(find.byType(DSpinner), findsNothing);
      expect(
        find.text('Sample rejected. Edit your message and retry.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Message'))
            .enabled,
        isTrue,
      );
      await tester.ensureVisible(find.text('Validate sample'));
      await tester.tap(find.text('Validate sample'));
      await tester.pump();
      await tester.ensureVisible(find.text('Accept sample'));
      await tester.tap(find.text('Accept sample'));
      await tester.pump();
      expect(find.text('Validation complete'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Send message'));
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      expect(find.text('Message sent locally'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty example supports cancellation, failure, retry and completion',
    (tester) async {
      await _pump(tester, 4, narrow: true);
      for (final (action, result) in [
        ('Cancel request', 'Request canceled'),
        ('Fail request', 'Request failed. Start again to retry.'),
        ('Complete request', 'Request complete'),
      ]) {
        await tester.ensureVisible(find.text('Start request'));
        await tester.tap(find.text('Start request'));
        await tester.pump();
        expect(find.byType(DSpinner), findsOneWidget);
        await tester.ensureVisible(find.text(action));
        await tester.tap(find.text(action));
        await tester.pump();
        expect(find.byType(DSpinner), findsNothing);
        expect(find.text(result), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('search opens runnable Spinner examples in the styleguide', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ComponentStyleguidePage()),
    );
    await tester.enterText(
      find.byKey(const ValueKey('styleguide-search')),
      'spinner',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('styleguide-component-spinner')),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('styleguide-preview')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('styleguide-detail-spinner')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.byType(DSpinner), findsNWidgets(5));
    expect(find.text('Size and customization'), findsWidgets);
  });
}

Future<void> _pump(
  WidgetTester tester,
  int index, {
  bool narrow = false,
  bool dark = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: dark || narrow
        ? StyleguideTheme.plum.resolve(AppTheme.light)
        : AppTheme.light,
    themeAnimationDuration: Duration.zero,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(narrow ? 2 : 1),
          disableAnimations: true,
        ),
        child: Directionality(
          textDirection: narrow ? TextDirection.rtl : TextDirection.ltr,
          child: SingleChildScrollView(
            child: SizedBox(
              width: narrow ? 280 : 600,
              child: Padding(
                padding: const EdgeInsets.all(DSpacing.sm),
                child: Builder(
                  builder: spinnerExamples.examples[index].builder,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
