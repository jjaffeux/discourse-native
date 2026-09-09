import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/component_fixtures/empty_main.dart' as fixture;

void main() {
  testWidgets(
    'offline fixture mounts production empty pages and completes chat retry',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await fixture.main();
      await tester.pumpAndSettle();
      for (final pair in [
        ('No sites', 'No sites yet'),
        ('Categories', 'No categories yet'),
        ('Category error', 'Local category request failed'),
        ('Tags', 'No tags yet'),
        ('Groups', 'No groups match these filters.'),
        ('Chat retry', 'Local request failed.'),
      ]) {
        await tester.tap(find.text(pair.$1).first);
        await tester.pumpAndSettle();
        expect(find.text(pair.$2), findsOneWidget);
        expect(tester.takeException(), isNull, reason: pair.$1);
      }
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('No threads yet.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
