import 'package:discourse_native/src/styleguide/examples/tabs_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all Tabs examples render at narrow 200 percent RTL', (
    tester,
  ) async {
    expect(tabsExamples.examples, hasLength(7));
    for (final example in tabsExamples.examples) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(260, 800),
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: SizedBox(
                    width: 260,
                    child: Builder(builder: example.builder),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: example.title);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('Card and dynamic examples expose real interaction', (
    tester,
  ) async {
    final card = tabsExamples.examples.singleWhere(
      (example) => example.title == 'Card composition',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Builder(builder: card.builder)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(
      find.text('You have 5 reports ready and available to export.'),
      findsOneWidget,
    );

    final dynamic = tabsExamples.examples.singleWhere(
      (example) => example.title == 'Controlled, dynamic and retained',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Builder(builder: dynamic.builder)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('security'));
    await tester.pumpAndSettle();
    expect(find.text('Security options'), findsOneWidget);
    await tester.tap(find.text('Remove security'));
    await tester.pumpAndSettle();
    expect(find.text('missing: profile'), findsOneWidget);
  });
}
