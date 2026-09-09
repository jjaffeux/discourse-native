import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/radio_group_review_main.dart' as fixture;

void main() {
  testWidgets('local production fixture opens owner and move radio results', (
    tester,
  ) async {
    await fixture.main();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change owner'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('topic-change-owner-search')),
      'review',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Alex Example'), findsOneWidget);
    await tester.tap(find.text('Alex Example'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move posts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Existing topic'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('topic-move-posts-search')),
      'review',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Destination topic'), findsOneWidget);
    await tester.tap(find.text('Destination topic'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  });
}
