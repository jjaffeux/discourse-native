import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/breadcrumb_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Breadcrumb registers every frozen documented example', () {
    expect(componentExamples['breadcrumb'], same(breadcrumbExamples));
    expect(breadcrumbExamples.status, ComponentStatus.implemented);
    expect(breadcrumbExamples.examples.map((example) => example.title), [
      'Basic',
      'Custom separator',
      'Dropdown',
      'Collapsed',
      'Link component',
      'RTL',
      'Narrow and scrolling',
    ]);
  });

  testWidgets('every example mounts in live narrow large-text palettes', (
    tester,
  ) async {
    for (final example in breadcrumbExamples.examples) {
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
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: 240,
                    child: Builder(builder: example.builder),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: example.title);
      }
    }
  });

  testWidgets('basic and typed examples dispatch their actual routes', (
    tester,
  ) async {
    Future<void> show(String title) async {
      final example = breadcrumbExamples.examples.firstWhere(
        (example) => example.title == title,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: Builder(builder: example.builder)),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show('Basic');
    await tester.tap(find.text('Components'));
    await tester.pump();
    expect(find.text('Opened Components'), findsOneWidget);

    await show('Link component');
    await tester.tap(find.text('Components'));
    await tester.pump();
    expect(find.text('/components'), findsOneWidget);
  });

  testWidgets('collapsed example selects with keyboard and closes', (
    tester,
  ) async {
    final example = breadcrumbExamples.examples.firstWhere(
      (example) => example.title == 'Collapsed',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: Builder(builder: example.builder)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('More pages'));
    await tester.pumpAndSettle();
    expect(find.text('Documentation'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Themes selected'), findsOneWidget);
    expect(find.text('Documentation'), findsNothing);
  });
}
