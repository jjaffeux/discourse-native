import 'package:discourse_native/src/models/discourse_model_codec.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_type_counts.dart';
import 'package:discourse_native/src/models/plugin_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const models = DiscourseModelCodec.core();

  test('ignored usernames decode and survive a stored copy', () {
    final user = models.currentUser(const {
      'username': 'reader',
      'ignored_users': ['sam', 12, null, 'lena'],
    }, 'https://forum.example');

    expect(user.ignoredUsernames, ['sam', 'lena']);
    final stored = DiscourseUser.fromJson(user.toJson());
    expect(stored, user);
    expect(stored.hashCode, user.hashCode);
    expect(() => user.ignoredUsernames.clear(), throwsUnsupportedError);
  });

  test('a site that sends no list ignores nobody', () {
    final user = models.currentUser(const {
      'username': 'reader',
    }, 'https://forum.example');

    expect(user.ignoredUsernames, isEmpty);
    expect(DiscourseUser.fromJson(user.toJson()).ignoredUsernames, isEmpty);
  });

  test('every user copy helper retains the ignored usernames', () {
    const user = DiscourseUser(username: 'reader', ignoredUsernames: ['sam']);
    for (final copy in [
      user.withCategoryNotificationPreferences(
        trackedCategoryIds: [],
        watchedCategoryIds: [],
        watchedFirstPostCategoryIds: [],
        mutedCategoryIds: [],
        indirectlyMutedCategoryIds: [],
      ),
      user.withDraftCount(3),
      user.withStatus(null),
      user.withDoNotDisturbUntil(DateTime.utc(2026)),
      user.withGroupedUnreadNotifications(NotificationTypeCounts.unavailable),
      user.withPreferences(timezone: 'Europe/Paris'),
      user.withHidePresence(true),
      user.withPlugins(PluginData.none),
    ]) {
      expect(copy.ignoredUsernames, ['sam']);
    }
  });
}
