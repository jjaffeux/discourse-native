import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:flutter_test/flutter_test.dart';

/// A `/notification/{id}` message, shaped as
/// `User#publish_notifications_state` sends it. Trimmed to the keys anything
/// here reads; the real payload also carries the last notification, the read
/// state of the recent ones, and the high-priority split.
Map<String, Object?> published({
  required int all,
  required int personalMessages,
  int? unreadNotifications,
}) => {
  'all_unread_notifications_count': all,
  'new_personal_messages_notifications_count': personalMessages,
  // Deliberately present and deliberately different from what this class
  // means by the same name — see the test below.
  'unread_notifications': unreadNotifications ?? all,
  'read_first_notification': true,
  'seen_notification_id': 400,
};

void main() {
  group('withNotification', () {
    test('derives the notification count the way the endpoint does', () {
      // `UserNotificationTotalSerializer` reports
      // `all_unread_notifications_count - new_personal_messages_notifications_count`
      // under `unread_notifications`, and the message's own field of that name
      // is a different number entirely. Reading it straight across is the bug
      // this test exists for: the count would jump on the first message and
      // never agree with `/notifications/totals.json` again.
      const held = NotificationTotals(
        unreadNotifications: 4,
        unreadPersonalMessages: 1,
      );

      final updated = held.withNotification(
        published(all: 9, personalMessages: 2, unreadNotifications: 99),
      );

      expect(updated.unreadNotifications, 7);
      expect(updated.unreadPersonalMessages, 2);
    });

    test('leaves the counts it says nothing about alone', () {
      const held = NotificationTotals(
        unseenReviewables: 3,
        chatNotifications: 2,
        topicTrackingUnread: 12,
        topicTrackingNew: 7,
        username: 'joffreyj',
      );

      final updated = held.withNotification(
        published(all: 1, personalMessages: 0),
      );

      expect(updated.unseenReviewables, 3);
      expect(updated.chatNotifications, 2);
      expect(updated.topicTrackingUnread, 12);
      expect(updated.topicTrackingNew, 7);
      expect(updated.username, 'joffreyj');
    });

    test('reading everything leaves nothing on the badge', () {
      const held = NotificationTotals(
        unreadNotifications: 4,
        unreadPersonalMessages: 1,
      );

      final updated = held.withNotification(
        published(all: 0, personalMessages: 0),
      );

      expect(updated.badge, 0);
    });

    test('is unchanged by a message with none of the counts in it', () {
      const held = NotificationTotals(unreadNotifications: 4);

      // Equal rather than identical: the caller compares to decide whether
      // anything needs redrawing.
      expect(held.withNotification(const {'seen_notification_id': 3}), held);
      expect(held.withNotification(null), held);
      expect(held.withNotification('nonsense'), held);
    });

    test('never reports a negative count', () {
      const held = NotificationTotals();

      // Not a shape the server sends, but the subtraction is ours and the two
      // numbers arrive from different queries.
      final updated = held.withNotification(
        published(all: 1, personalMessages: 3),
      );

      expect(updated.unreadNotifications, 0);
      expect(updated.unreadPersonalMessages, 3);
    });
  });

  group('withReviewableCounts', () {
    test('counts what has appeared since the queue was last looked at', () {
      const held = NotificationTotals(unreadNotifications: 4);

      final updated = held.withReviewableCounts(const {
        // The size of the queue, which is not what any badge here shows.
        'reviewable_count': 12,
        'unseen_reviewable_count': 3,
      });

      expect(updated.unseenReviewables, 3);
      expect(updated.unreadNotifications, 4);
      expect(updated.badge, 7);
    });

    test('is unchanged by a message without the count in it', () {
      const held = NotificationTotals(unseenReviewables: 3);

      expect(held.withReviewableCounts(const {'reviewable_count': 12}), held);
      expect(held.withReviewableCounts(null), held);
    });
  });
}
