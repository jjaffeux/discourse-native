import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/navigation_menu_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Navigation Menu registers the frozen documentation compositions', () {
    expect(componentExamples['navigation-menu'], same(navigationMenuExamples));
    expect(navigationMenuExamples.status, ComponentStatus.implemented);
    expect(navigationMenuExamples.examples.map((example) => example.title), [
      'Basic',
      'Link component and current page',
      'Controlled, dynamic and disabled',
      'Inline viewport and RTL',
    ]);
  });

  testWidgets('all examples mount in live palettes at narrow 200 percent RTL', (
    tester,
  ) async {
    for (final example in navigationMenuExamples.examples) {
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
                  size: Size(216, 700),
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SizedBox(
                    width: 216,
                    child: SingleChildScrollView(
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

  testWidgets('reference example routes from panel and direct link', (
    tester,
  ) async {
    final example = navigationMenuExamples.examples.first;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: Builder(builder: example.builder)),
        ),
      ),
    );
    await tester.tap(find.text('Getting started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Introduction'));
    await tester.pumpAndSettle();
    expect(find.text('Destination: Introduction'), findsOneWidget);

    await tester.tap(find.text('Documentation'));
    await tester.pump();
    expect(find.text('Destination: Documentation'), findsOneWidget);
  });
}
