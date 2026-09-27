import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

void main() {
  testWidgets('a destination count is read as part of its row', (tester) async {
    const site = 'https://meta.discourse.org';
    const user = DiscourseUser(id: 7, username: 'reader');
    final semantics = tester.ensureSemantics();
    try {
      await pumpShell(
        tester,
        desktop,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: user),
        ],
        authenticator: FakeAuthenticator()..keys[site] = 'meta-key',
        api: FakeDiscourseApi(
          user: user,
          totals: const NotificationTotals(
            unreadPersonalMessages: 3,
            topicTrackingUnread: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();

      Finder inSidebar(Finder finder) =>
          find.descendant(of: find.byType(InstanceSidebar), matching: finder);
      // The counts are still drawn beside their rows.
      expect(inSidebar(find.text('3')), findsOneWidget);
      expect(inSidebar(find.text('2')), findsOneWidget);

      expect(inSidebar(find.bySemanticsLabel(RegExp(r'^\d+$'))), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Messages, 3 unread items')),
        isSemantics(isButton: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Topics, 2 unread items')),
        isSemantics(isButton: true, isSelected: true),
      );
    } finally {
      semantics.dispose();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
