import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' as fixture;
import 'support/fakes.dart';

void main() {
  testWidgets('forum tracking updates preserve mobile chrome widgets', (
    tester,
  ) async {
    final shell = await fixture.pumpMobileShellFixture(
      tester,
      user: const DiscourseUser(
        id: 7,
        username: 'reader',
        unifiedNewEnabled: true,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('topic-card-7')));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, 7);
    final frame = find.byKey(const ValueKey('mobile-root'));
    final header = find.byKey(const ValueKey('mobile-header'));
    final beforeFrame = tester.widget(frame);
    final beforeHeader = tester.widget(header);
    final topic = shell.currentContent;
    expect(find.byType(MobileForumRoot), findsOneWidget);
    final beforeReplies = shell.newReplyCount;
    FakeSiteTracker.built
        .singleWhere((tracker) => tracker.siteUrl == shell.currentInstance!.url)
        .deliverTopicTracking(const {
          'topic_id': 99,
          'message_type': 'unread',
          'payload': {'highest_post_number': 3, 'notification_level': 2},
        });
    await tester.pumpAndSettle();
    expect(shell.newReplyCount, beforeReplies + 1);
    expect(shell.currentContent, same(topic));
    expect(tester.widget(frame), same(beforeFrame));
    expect(tester.widget(header), same(beforeHeader));
    final tracker = FakeSiteTracker.built.singleWhere(
      (tracker) => tracker.siteUrl == shell.currentInstance!.url,
    );
    tracker.deliverNotification(const {'all_unread_notifications_count': 3});
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(UserMenuButton.unreadDotKey),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(tester.widget(frame), same(beforeFrame));
    expect(tester.widget(header), same(beforeHeader));
    expect(tester.takeException(), isNull);
  });
}
