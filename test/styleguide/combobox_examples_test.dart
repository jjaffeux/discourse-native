import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/combobox_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registers every frozen Combobox composition and example', () {
    expect(componentExamples['combobox'], same(comboboxExamples));
    expect(comboboxExamples.status, ComponentStatus.implemented);
    expect(comboboxExamples.examples.map((example) => example.title), [
      'Composition',
      'Simple',
      'With chips',
      'With groups and collection',
      'Custom Items',
      'Multiple Selection',
      'Basic',
      'Multiple',
      'Clear Button',
      'Groups',
      'Invalid',
      'Disabled',
      'Auto Highlight',
      'Popup',
      'Input Group',
      'RTL',
    ]);
  });

  testWidgets('all examples mount narrow at 200 percent in live palettes', (
    tester,
  ) async {
    for (final example in comboboxExamples.examples) {
      for (final theme in [
        AppTheme.light,
        AppTheme.dark,
        StyleguideTheme.forest.resolve(AppTheme.light),
      ]) {
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
                    child: SizedBox(
                      width: 216,
                      child: Builder(builder: example.builder),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: example.title);
      }
    }
  });

  testWidgets('Popup example moves focus into its inner input and selects', (
    tester,
  ) async {
    final example = comboboxExamples.examples.firstWhere(
      (example) => example.title == 'Popup',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: Builder(builder: example.builder)),
        ),
      ),
    );
    await tester.tap(find.text('Canada'));
    await tester.pumpAndSettle();
    expect(find.byType(DComboboxInput<String>), findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.enterText(find.byType(TextField), 'Japan');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Japan').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(DButton, 'Japan'), findsOneWidget);
  });

  testWidgets('Popup Escape restores focus to its trigger', (tester) async {
    final example = comboboxExamples.examples.firstWhere(
      (example) => example.title == 'Popup',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: Builder(builder: example.builder)),
        ),
      ),
    );
    await tester.tap(find.text('Canada'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DButton>(find.byType(DButton)).focusNode?.hasFocus,
      isTrue,
    );
  });

  testWidgets('Input Group example composes accepted addons and control', (
    tester,
  ) async {
    final example = comboboxExamples.examples.firstWhere(
      (example) => example.title == 'Input Group',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: Builder(builder: example.builder)),
        ),
      ),
    );

    expect(find.byType(DInputGroup), findsOneWidget);
    expect(find.byType(DInputGroupControl), findsOneWidget);
    expect(find.byType(DInputGroupAddon), findsNWidgets(2));
    expect(find.byType(DInputGroupButton), findsOneWidget);
  });

  testWidgets('Custom Items uses passive accepted Item composition', (
    tester,
  ) async {
    final example = comboboxExamples.examples.firstWhere(
      (example) => example.title == 'Custom Items',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: Builder(builder: example.builder)),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.byType(DItem), findsWidgets);
    for (final item in tester.widgetList<DItem>(find.byType(DItem))) {
      expect(item.onPressed, isNull);
      expect(item.link, isFalse);
      expect(item.size, DItemSize.xs);
      expect(item.padding, EdgeInsets.zero);
    }
  });
}
