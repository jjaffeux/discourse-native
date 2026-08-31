import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/notification_type_counts.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _assigned = NotificationWireType(34, 'assigned');
const _assignedReminder = NotificationWireType(35, 'assigned_reminder');

NotificationTypeCounts _counts(Object? wire) =>
    NotificationTypeCounts.fromWire(wire);

void main() {
  group('NotificationTypeCounts wire parsing', () {
    test('distinguishes an absent value from a server-confirmed empty map', () {
      final absent = _counts(null);
      final malformedEnvelope = _counts('not a map');
      final empty = _counts(const <String, Object?>{});

      expect(absent.isAvailable, isFalse);
      expect(absent.toJson(), isNull);
      expect(malformedEnvelope.isAvailable, isFalse);
      expect(malformedEnvelope.toJson(), isNull);
      expect(empty.isAvailable, isTrue);
      expect(empty.toJson(), isEmpty);
    });

    test('accepts integer and decimal-string keys and values', () {
      final counts = _counts(const <Object, Object>{'34': '4', 35: 7});

      expect(counts.isAvailable, isTrue);
      expect(counts.count(_assigned), 4);
      expect(counts.count(_assignedReminder), 7);
      expect(counts.toJson(), {'34': 4, '35': 7});
    });

    test('ignores malformed entries and non-positive type IDs', () {
      final counts = _counts(const <Object?, Object?>{
        'not-an-id': 1,
        0: 2,
        -1: 3,
        34: 'not-a-count',
        35: null,
      });

      expect(counts.isAvailable, isTrue);
      expect(counts.toJson(), isEmpty);
      expect(counts.count(_assigned), 0);
      expect(counts.count(_assignedReminder), 0);
    });

    test('floors negative counts without making the field unavailable', () {
      final counts = _counts(const <Object, Object>{'34': -3});

      expect(counts.isAvailable, isTrue);
      expect(counts.count(_assigned), 0);
      expect(counts.toJson(), {'34': 0});
    });
  });

  group('NotificationTotals grouped unread integration', () {
    test('current totals preserve field availability and parse counts', () {
      final absent = NotificationTotals.fromJson(const {});
      final empty = NotificationTotals.fromJson(const {
        'grouped_unread_notifications': <String, Object?>{},
      });
      final populated = NotificationTotals.fromJson(const {
        'grouped_unread_notifications': <Object, Object>{'34': '2', 35: 5},
      });

      expect(absent.groupedUnreadNotifications.isAvailable, isFalse);
      expect(empty.groupedUnreadNotifications.isAvailable, isTrue);
      expect(populated.groupedUnreadNotifications.count(_assigned), 2);
      expect(populated.groupedUnreadNotifications.count(_assignedReminder), 5);
    });

    test('live notification messages update, clear, or preserve counts', () {
      final held = NotificationTotals(
        unreadNotifications: 8,
        groupedUnreadNotifications: _counts(const {'34': 3}),
      );

      final updated = held.withNotification(const {
        'grouped_unread_notifications': {'34': 6},
      });
      final cleared = updated.withNotification(const {
        'grouped_unread_notifications': <String, Object?>{},
      });

      expect(updated.unreadNotifications, 8);
      expect(updated.groupedUnreadNotifications.count(_assigned), 6);
      expect(cleared.groupedUnreadNotifications.isAvailable, isTrue);
      expect(cleared.groupedUnreadNotifications.count(_assigned), 0);
      expect(held.withNotification(const {'unrelated': true}), same(held));
      expect(
        held.withNotification(const {
          'grouped_unread_notifications': 'not a map',
        }),
        same(held),
      );
    });

    test('persistence round trips available counts and their empty state', () {
      final totals = NotificationTotals(
        groupedUnreadNotifications: _counts(const <Object, Object>{
          '34': 2,
          35: '4',
        }),
      );
      final stored = totals.toStoredJson();
      final restored = NotificationTotals.fromStoredJson(stored);
      final storedEmpty = const NotificationTotals(
        groupedUnreadNotifications: NotificationTypeCounts.empty,
      ).toStoredJson();

      expect(stored['groupedUnreadNotifications'], {'34': 2, '35': 4});
      expect(
        restored.groupedUnreadNotifications,
        totals.groupedUnreadNotifications,
      );
      expect(storedEmpty, containsPair('groupedUnreadNotifications', isEmpty));
      expect(
        const NotificationTotals().toStoredJson(),
        isNot(contains('groupedUnreadNotifications')),
      );
    });

    test('refresh keeps a grouped count changed by a live message', () {
      final before = NotificationTotals(
        groupedUnreadNotifications: _counts(const {'34': 1}),
      );
      final live = before.withGroupedUnreadNotifications(
        _counts(const {'34': 4}),
      );
      final response = NotificationTotals(
        groupedUnreadNotifications: _counts(const {'34': 9}),
      );

      final merged = NotificationTotals.mergeRefresh(
        response: response,
        before: before,
        live: live,
      );

      expect(merged.groupedUnreadNotifications.count(_assigned), 4);
    });

    test(
      'refresh takes an available response when live state is unchanged',
      () {
        final before = NotificationTotals(
          groupedUnreadNotifications: _counts(const {'34': 1}),
        );
        final response = NotificationTotals(
          groupedUnreadNotifications: _counts(const {'34': 9}),
        );

        final merged = NotificationTotals.mergeRefresh(
          response: response,
          before: before,
          live: before,
        );

        expect(merged.groupedUnreadNotifications.count(_assigned), 9);
      },
    );

    test('refresh does not erase counts when its response omits the field', () {
      final before = NotificationTotals(
        groupedUnreadNotifications: _counts(const {'34': 3}),
      );

      final merged = NotificationTotals.mergeRefresh(
        response: const NotificationTotals(),
        before: before,
        live: before,
      );

      expect(merged.groupedUnreadNotifications.isAvailable, isTrue);
      expect(merged.groupedUnreadNotifications.count(_assigned), 3);
    });
  });

  test('DiscourseModelCodec parses grouped counts on the current user', () {
    const codec = DiscourseModelCodec.core();

    final populated = codec.currentUser(const {
      'username': 'reader',
      'grouped_unread_notifications': <Object, Object>{'34': '5', 35: 2},
    }, 'https://forum.example');
    final absent = codec.currentUser(const {
      'username': 'reader',
    }, 'https://forum.example');

    expect(populated.groupedUnreadNotifications.isAvailable, isTrue);
    expect(populated.groupedUnreadNotifications.count(_assigned), 5);
    expect(populated.groupedUnreadNotifications.count(_assignedReminder), 2);
    expect(absent.groupedUnreadNotifications.isAvailable, isFalse);
  });

  test('PluginUserMenuContext falls back to user counts and prefers live', () {
    final user = DiscourseUser(
      username: 'reader',
      groupedUnreadNotifications: _counts(const {'34': 7}),
    );
    final withoutTotals = PluginUserMenuContext(
      siteUrl: 'https://forum.example',
      user: user,
      totals: null,
    );
    final unavailableLive = PluginUserMenuContext(
      siteUrl: 'https://forum.example',
      user: user,
      totals: const NotificationTotals(),
    );
    final availableLive = PluginUserMenuContext(
      siteUrl: 'https://forum.example',
      user: user,
      totals: const NotificationTotals(
        groupedUnreadNotifications: NotificationTypeCounts.empty,
      ),
    );

    expect(withoutTotals.unreadCountFor(_assigned), 7);
    expect(unavailableLive.unreadCountFor(_assigned), 7);
    expect(availableLive.unreadCountFor(_assigned), 0);
  });
}
