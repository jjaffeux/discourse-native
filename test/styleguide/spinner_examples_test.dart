import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/spinner_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'payment item keeps the spinner at the start and the amount at the inline end',
    (tester) async {
      await _pump(tester, 'Processing payment');
      final item = tester.getRect(find.byType(DItem));
      expect(item.width, 320);
      expect(tester.getSize(find.byType(DSpinner)), const Size.square(16));
      // A transparent 1px border precedes the 12px padding, as in the reference.
      expect(tester.getRect(find.byType(DSpinner)).left, item.left + 13);
      expect(tester.getRect(find.text(r'$100.00')).right, item.right - 13);
      expect(
        tester.widget<DItem>(find.byType(DItem)).variant,
        DItemVariant.muted,
      );
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    },
  );

  for (final example in spinnerExamples.examples) {
    testWidgets(
      '${example.title} fits narrow RTL with large text and a site palette',
      (tester) async {
        await _pump(tester, example.title, narrow: true);
        expect(tester.takeException(), isNull);
        expect(componentExamples['spinner'], same(spinnerExamples));
      },
    );
  }

  testWidgets('size example shows the four reference diameters', (
    tester,
  ) async {
    await _pump(tester, 'Size');
    expect(
      [
        for (final spinner in find.byType(DSpinner).evaluate())
          tester.getSize(find.byWidget(spinner.widget)).width,
      ],
      [12, 16, 24, 32],
    );
  });

  testWidgets('customization controls update the real public spinner', (
    tester,
  ) async {
    await _pump(tester, 'Customization');
    final sampleKey = find.byKey(const ValueKey('spinner-custom-sample'));
    expect(tester.widget<DSpinner>(sampleKey).child, isNotNull);
    await tester.tap(find.text('Accent color'));
    await tester.tap(find.text('Size 32'));
    await tester.tap(find.text('Animate sample'));
    await tester.pump();
    final sample = tester.widget<DSpinner>(sampleKey);
    expect(sample.size, 32);
    expect(sample.animating, isFalse);
    expect(sample.color, AppTheme.light.colorScheme.primary);
    await _pump(tester, 'Customization', dark: true);
    final changed = tester.widget<DSpinner>(sampleKey);
    expect(
      changed.color,
      StyleguideTheme.plum.resolve(AppTheme.light).colorScheme.primary,
    );
    expect(changed.size, 32);
    expect(changed.child, isNotNull);
    await tester.tap(find.text('Custom artwork'));
    await tester.pump();
    expect(tester.widget<DSpinner>(sampleKey).child, isNull);
  });

  testWidgets(
    'button example reproduces the disabled small reference buttons',
    (tester) async {
      // Pointer platforms keep the 28px reference height; touch platforms
      // enlarge only the invisible target.
      await _pump(tester, 'Button', platform: TargetPlatform.macOS);
      for (final (label, variant) in [
        ('Loading...', DButtonVariant.primary),
        ('Please wait', DButtonVariant.outline),
        ('Processing', DButtonVariant.secondary),
      ]) {
        final finder = find.widgetWithText(DButton, label).first;
        final button = tester.widget<DButton>(finder);
        expect(button.variant, variant, reason: label);
        expect(button.size, DButtonSize.small, reason: label);
        expect(button.onPressed, isNull, reason: label);
        expect(button.icon, isA<DSpinner>(), reason: label);
        final spinner = find.descendant(
          of: finder,
          matching: find.byType(DSpinner),
        );
        final buttonRect = tester.getRect(finder);
        final spinnerRect = tester.getRect(spinner);
        expect(buttonRect.height, 28, reason: label);
        expect(spinnerRect.size, const Size.square(16), reason: label);
        expect(spinnerRect.left - buttonRect.left, 7, reason: label);
        expect(
          tester.getRect(find.text(label).first).left - spinnerRect.right,
          4,
          reason: label,
        );
      }
    },
  );

  testWidgets('button example handles disabled busy, failure and completion', (
    tester,
  ) async {
    await _pump(tester, 'Button');
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
      await _pump(tester, 'Badge', narrow: true);
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

  testWidgets('input group addons tint both spinners muted', (tester) async {
    await _pump(tester, 'Input Group');
    final tokens = DTokens.of(tester.element(find.byType(DInputGroup).first));
    for (final spinner in find.byType(DSpinner).evaluate()) {
      expect(IconTheme.of(spinner).color, tokens.mutedForeground);
    }
    expect(find.byType(DSpinner), findsNWidgets(2));
  });

  testWidgets(
    'input validation preserves edits through theme changes, rejection and retry',
    (tester) async {
      await _pump(tester, 'Input Group', narrow: true);
      await tester.ensureVisible(find.text('Accept sample'));
      await tester.tap(find.text('Accept sample'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('spinner-subject')),
        'A sample subject',
      );
      await tester.enterText(
        find.byKey(const ValueKey('spinner-message')),
        'A message to validate',
      );
      await tester.ensureVisible(find.text('Validate sample'));
      await tester.tap(find.text('Validate sample'));
      await tester.pump();
      expect(find.byType(DSpinner), findsNWidgets(2));
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('spinner-subject')),
                matching: find.byType(TextField),
              ),
            )
            .enabled,
        isFalse,
      );
      await _pump(tester, 'Input Group', narrow: true, dark: true);
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
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('spinner-message')),
                matching: find.byType(TextField),
              ),
            )
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
      await tester.ensureVisible(find.byKey(const ValueKey('spinner-send')));
      await tester.tap(find.byKey(const ValueKey('spinner-send')));
      await tester.pump();
      expect(find.text('Message sent locally'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty example holds the spinner in icon media with a small outline Cancel',
    (tester) async {
      await _pump(tester, 'Empty');
      expect(
        find.descendant(
          of: find.byType(DEmptyMedia),
          matching: find.byType(DSpinner),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<DEmptyMedia>(find.byType(DEmptyMedia)).variant,
        DEmptyMediaVariant.icon,
      );
      expect(tester.getSize(find.byType(DSpinner)), const Size.square(16));
      final cancel = tester.widget<DButton>(
        find.widgetWithText(DButton, 'Cancel'),
      );
      expect(cancel.variant, DButtonVariant.outline);
      expect(cancel.size, DButtonSize.small);
      expect(find.text('Processing your request'), findsOneWidget);
    },
  );

  testWidgets(
    'empty example supports cancellation, failure, retry and completion',
    (tester) async {
      await _pump(tester, 'Empty', narrow: true);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(find.byType(DEmptyMedia), findsNothing);
      for (final (action, result) in [
        ('Cancel', 'Request canceled'),
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

  testWidgets('RTL example switches language and direction together', (
    tester,
  ) async {
    await _pump(tester, 'RTL');
    Rect item() => tester.getRect(find.byType(DItem));
    expect(find.text('جاري معالجة الدفع...'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(DItem))),
      TextDirection.rtl,
    );
    expect(tester.getRect(find.byType(DSpinner)).right, item().right - 13);
    expect(tester.getRect(find.text('١٠٠.٠٠ دولار')).left, item().left + 13);
    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('עברית').last);
    await tester.pumpAndSettle();
    expect(find.text('מעבד תשלום...'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(DItem))),
      TextDirection.rtl,
    );
    await tester.tap(find.text('עברית'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(find.text('Processing payment...'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(DItem))),
      TextDirection.ltr,
    );
    expect(tester.getRect(find.byType(DSpinner)).left, item().left + 13);
    expect(tester.getRect(find.text(r'$100.00')).right, item().right - 13);
  });

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
    final preview = find.byKey(const ValueKey('styleguide-preview'));
    expect(
      find.descendant(of: preview, matching: find.byType(DSpinner)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: preview, matching: find.byType(DItem)),
      findsOneWidget,
    );
    expect(find.text('Processing payment...'), findsWidgets);
  });
}

Future<void> _pump(
  WidgetTester tester,
  String title, {
  bool narrow = false,
  bool dark = false,
  TargetPlatform? platform,
}) {
  final example = spinnerExamples.examples.singleWhere(
    (example) => example.title == title,
  );
  final theme = dark || narrow
      ? StyleguideTheme.plum.resolve(AppTheme.light)
      : AppTheme.light;
  return tester.pumpWidget(
    MaterialApp(
      theme: platform == null ? theme : theme.copyWith(platform: platform),
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
                  child: Builder(builder: example.builder),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
