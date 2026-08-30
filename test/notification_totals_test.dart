import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/plugin_api/notification_counters.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _pluginCounter = PluginNotificationCounter(
  id: PluginNotificationCounterId(
    owner: PluginId('test-plugin'),
    name: 'alerts',
  ),
  wireName: 'test_alerts',
);

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
  test('selects the web sidebar topic count in both New modes', () {
    expect(
      const NotificationTotals(
        topicTrackingUnread: 12,
        topicTrackingNew: 7,
      ).topicTrackingSidebarCount,
      12,
    );
    expect(
      const NotificationTotals(topicTrackingNew: 19).topicTrackingSidebarCount,
      19,
    );
  });

  test('account identity and plugin counters participate in equality', () {
    const baseline = NotificationTotals(username: 'sam');

    expect(baseline, isNot(const NotificationTotals(username: 'alex')));
    expect(
      baseline,
      isNot(
        NotificationTotals(
          username: 'sam',
          pluginCounters: PluginNotificationCounters.single(_pluginCounter),
        ),
      ),
    );
  });

  test('floors impossible initial core counts', () {
    final totals = NotificationTotals.fromJson(const {
      'unread_notifications': -1,
      'unread_personal_messages': '-2',
      'unseen_reviewables': -3,
      'topic_tracking': {'unread': -5, 'new': 7},
    });

    expect(totals.unreadNotifications, 0);
    expect(totals.unreadPersonalMessages, 0);
    expect(totals.unseenReviewables, 0);
    expect(totals.topicTrackingUnread, 0);
    expect(totals.topicTrackingNew, 7);
  });

  test('unknown stored counter namespaces round trip through core', () {
    final totals = NotificationTotals.fromStoredJson(const {
      'plugins': {
        'absent-plugin/alerts': {
          'count': 7,
          'metadata': ['opaque'],
        },
      },
    });

    expect(totals.toStoredJson()['plugins'], {
      'absent-plugin/alerts': {
        'count': 7,
        'metadata': ['opaque'],
      },
    });
  });

  test('refresh keeps live counts but takes response availability', () {
    final before = NotificationTotals(
      pluginCounters: PluginNotificationCounters.fromLive(const [
        _pluginCounter,
      ], const {}),
    );
    final live = before.updatePluginCounter(_pluginCounter, (_) => 5);
    final availableResponse = NotificationTotals(
      pluginCounters: PluginNotificationCounters.fromLive(
        const [_pluginCounter],
        const {'test_alerts': 1},
      ),
    );
    final unavailableResponse = NotificationTotals(
      pluginCounters: PluginNotificationCounters.fromLive(const [
        _pluginCounter,
      ], const {}),
    );

    final available = NotificationTotals.mergeRefresh(
      response: availableResponse,
      before: before,
      live: live,
    );
    final unavailable = NotificationTotals.mergeRefresh(
      response: unavailableResponse,
      before: before,
      live: live,
    );

    expect(available.pluginCounter(_pluginCounter.id), 5);
    expect(available.hasPluginCounter(_pluginCounter.id), isTrue);
    expect(unavailable.pluginCounter(_pluginCounter.id), 5);
    expect(unavailable.hasPluginCounter(_pluginCounter.id), isFalse);
    expect(unavailable.badge, 0);
  });

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
      final held = NotificationTotals(
        unseenReviewables: 3,
        topicTrackingUnread: 12,
        topicTrackingNew: 7,
        username: 'joffreyj',
        pluginCounters: PluginNotificationCounters.single(
          _pluginCounter,
          count: 2,
        ),
      );

      final updated = held.withNotification(
        published(all: 1, personalMessages: 0),
      );

      expect(updated.unseenReviewables, 3);
      expect(updated.pluginCounter(_pluginCounter.id), 2);
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
      expect(
        held.withNotification(const {
          'all_unread_notifications_count': 'not a count',
          'new_personal_messages_notifications_count': Object(),
        }),
        held,
      );
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

    test('floors negative live counts before deriving the badge', () {
      const held = NotificationTotals(
        unreadNotifications: 4,
        unreadPersonalMessages: 2,
      );

      final negativeAll = held.withNotification(
        published(all: -1, personalMessages: 2),
      );
      final negativePersonal = held.withNotification(
        published(all: 5, personalMessages: -3),
      );

      expect(negativeAll.unreadNotifications, 0);
      expect(negativeAll.unreadPersonalMessages, 2);
      expect(negativePersonal.unreadNotifications, 5);
      expect(negativePersonal.unreadPersonalMessages, 0);
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
      expect(
        held.withReviewableCounts(const {
          'unseen_reviewable_count': 'not a count',
        }),
        held,
      );
      expect(held.withReviewableCounts(null), held);
    });

    test('floors a negative live reviewable count', () {
      const held = NotificationTotals(unseenReviewables: 3);

      final updated = held.withReviewableCounts(const {
        'unseen_reviewable_count': -1,
      });

      expect(updated.unseenReviewables, 0);
    });
  });
}
