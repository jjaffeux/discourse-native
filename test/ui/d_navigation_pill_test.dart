import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the reference pill remains part of its containing row target', (
    tester,
  ) async {
    var opened = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DItem(
            onPressed: () => opened++,
            semanticLabel: 'Topics and posts',
            children: const [DNavigationPill()],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(DNavigationPill)), const Size(31, 19));
    expect(find.bySemanticsLabel('Topics and posts'), findsOneWidget);
    await tester.tap(find.byType(DNavigationPill));
    expect(opened, 1);
    semantics.dispose();
  });

  testWidgets('the pill follows reading direction and accessibility size', (
    tester,
  ) async {
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Directionality(
              textDirection: direction,
              child: const Center(child: DNavigationPill()),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(DNavigationPill)), const Size(42, 30));
      final transform = tester.widget<Transform>(
        find
            .descendant(
              of: find.byType(DNavigationPill),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(
        transform.transform.entry(0, 0),
        direction == TextDirection.ltr ? -1 : 1,
      );
    }
  });
}
