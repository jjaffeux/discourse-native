import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/popover_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Popover registers every frozen documentation and edge example', () {
    expect(componentExamples['popover'], same(popoverExamples));
    expect(popoverExamples.status, ComponentStatus.implemented);
    expect(popoverExamples.examples.map((example) => example.title), [
      'Basic',
      'Align',
      'With Form',
      'Controlled and close',
      'Sides and RTL',
      'Anchor, collision and movement',
    ]);
  });

  testWidgets('examples mount at narrow 200 percent RTL in live palettes', (
    tester,
  ) async {
    for (final example in popoverExamples.examples) {
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

  testWidgets('Basic example opens, closes, and restores keyboard focus', (
    tester,
  ) async {
    final example = popoverExamples.examples.first;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: Builder(builder: example.builder)),
        ),
      ),
    );
    final trigger = tester.widget<DButton>(
      find.widgetWithText(DButton, 'Open Popover'),
    );
    trigger.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Dimensions'), findsOneWidget);
    expect(find.text('Set the dimensions for the layer.'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Dimensions'), findsNothing);
    expect(trigger.focusNode!.hasFocus, isTrue);
  });

  testWidgets('form example composes DInput and Form save behavior', (
    tester,
  ) async {
    final example = popoverExamples.examples.firstWhere(
      (example) => example.title == 'With Form',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: Builder(builder: example.builder)),
        ),
      ),
    );
    await tester.tap(find.text('Open Popover'));
    await tester.pumpAndSettle();
    expect(find.byType(DInput), findsNWidgets(2));
    await tester.enterText(find.byType(DInput).first, '640px');
    await tester.scrollUntilVisible(
      find.text('Save'),
      80,
      scrollable: find
          .descendant(
            of: find.byType(DPopoverContent),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Saved width: 640px'), findsOneWidget);
  });
}
