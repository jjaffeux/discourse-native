import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/collapsible_review_main.dart';

void main() {
  testWidgets(
    'local fixture mounts actual alert groups and quote callback without services',
    (tester) async {
      LocalDateEnvironment.instance.ensureDatabase();
      await tester.pumpWidget(const CollapsibleReviewApp());
      await tester.tap(find.text('Alert groups'));
      await tester.pumpAndSettle();
      expect(find.text('review (32)'), findsOneWidget);
      await tester.tap(find.text('review (32)'));
      await tester.pumpAndSettle();
      expect(find.text('Local database alert 0'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Quote Alert').first);
      await tester.pump();
      expect(find.text('Quote: Local database alert 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
