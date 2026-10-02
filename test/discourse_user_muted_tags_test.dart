import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_type_counts.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const models = DiscourseModelCodec.core();

  test('muted tag IDs decode from tag objects and survive stored copies', () {
    final user = models.currentUser(const {
      'username': 'reader',
      'muted_tags': [
        {'id': 44, 'name': 'muted-tag'},
        {'id': '45', 'name': 'other-tag'},
        {'id': false},
        null,
      ],
    }, 'https://forum.example');
    expect(user.mutedTagIds, [44, 45]);
    final stored = DiscourseUser.fromJson(user.toJson());
    expect(stored, user);
    expect(stored.hashCode, user.hashCode);
    expect(() => user.mutedTagIds!.clear(), throwsUnsupportedError);
    expect(() => stored.mutedTagIds!.clear(), throwsUnsupportedError);
  });

  test('every user copy helper retains muted tag preferences', () {
    const user = DiscourseUser(username: 'reader', mutedTagIds: [44]);
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
      expect(copy.mutedTagIds, [44]);
    }
  });

  test('mute tag changes participate in equality', () {
    const user = DiscourseUser(username: 'reader');
    expect(
      DiscourseUser.fromJson({
        ...user.toJson(),
        'mutedTagIds': const [44],
      }),
      isNot(user),
    );
  });

  test('older stored and wire users keep unknown or empty tag preferences', () {
    final stored = DiscourseUser.fromJson(const {'username': 'reader'});
    expect(stored.mutedTagIds, isNull);
    expect(DiscourseUser.fromJson(stored.toJson()), stored);
    expect(
      models.currentUser(const {'username': 'reader'}, '').mutedTagIds,
      isEmpty,
    );
  });
}
