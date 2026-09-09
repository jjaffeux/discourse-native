import 'package:discourse_native/chart_review_main.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/poll/poll_card.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'offline fixture mounts migrated Users and Poll marks with confidential counts hidden',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const ChartReviewFixture()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UsersPage), findsOneWidget);
      expect(find.byType(DChartBar), findsNWidgets(2));
      await tester.tap(find.text('Directory empty'));
      await tester.pumpAndSettle();
      expect(find.byType(DChartBar), findsNothing);
      await tester.tap(find.text('Directory ready'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Actual PollCard: visible quantitative results'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      final ready = find.byWidgetPredicate(
        (widget) => widget is PollCard && widget.poll.name == 'ready',
      );
      expect(
        find.descendant(of: ready, matching: find.byType(DChartBar)),
        findsNWidgets(2),
      );
      await tester.scrollUntilVisible(
        find.text('Confidential results remain confidential'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      final confidential = find.byWidgetPredicate(
        (widget) => widget is PollCard && widget.poll.name == 'confidential',
      );
      expect(
        find.descendant(of: confidential, matching: find.byType(DChartBar)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
