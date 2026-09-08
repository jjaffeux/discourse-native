import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_type_counts.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const models = DiscourseModelCodec.core();

  test('decodes and persists direct and server-resolved indirect mutes', () {
    final user = models.currentUser(const {
      'username': 'author',
      'muted_category_ids': [1, '2', false, null],
      'indirectly_muted_category_ids': ['3', 4, false],
    }, 'https://forum.example');

    expect(user.mutedCategoryIds, [1, 2]);
    expect(user.indirectlyMutedCategoryIds, [3, 4]);
    final restored = DiscourseUser.fromJson(user.toJson());
    expect(restored, user);
    expect(restored.hashCode, user.hashCode);
    for (final snapshot in [user, restored]) {
      expect(() => snapshot.mutedCategoryIds!.clear(), throwsUnsupportedError);
      expect(
        () => snapshot.indirectlyMutedCategoryIds!.clear(),
        throwsUnsupportedError,
      );
    }
  });

  test('copy helpers retain mute preferences', () {
    const user = DiscourseUser(
      username: 'author',
      mutedCategoryIds: [1],
      indirectlyMutedCategoryIds: [2],
    );
    for (final copied in [
      user.withDraftCount(3),
      user.withStatus(null),
      user.withDoNotDisturbUntil(DateTime.utc(2026)),
      user.withGroupedUnreadNotifications(NotificationTypeCounts.unavailable),
      user.withPreferences(timezone: 'Europe/Paris'),
      user.withHidePresence(true),
      user.withPlugins(PluginData.none),
    ]) {
      expect(copied.mutedCategoryIds, [1]);
      expect(copied.indirectlyMutedCategoryIds, [2]);
    }
  });

  test('mute changes participate in equality', () {
    const user = DiscourseUser(username: 'author');
    expect(
      DiscourseUser.fromJson({
        ...user.toJson(),
        'mutedCategoryIds': const [1],
      }),
      isNot(user),
    );
    expect(
      DiscourseUser.fromJson({
        ...user.toJson(),
        'indirectlyMutedCategoryIds': const [2],
      }),
      isNot(user),
    );
  });

  test('old stored users and older server responses remain readable', () {
    final stored = DiscourseUser.fromJson(const {'username': 'author'});
    expect(stored.mutedCategoryIds, isNull);
    expect(stored.indirectlyMutedCategoryIds, isNull);
    expect(DiscourseUser.fromJson(stored.toJson()), stored);

    final live = models.currentUser(const {
      'username': 'author',
    }, 'https://forum.example');
    expect(live.mutedCategoryIds, isEmpty);
    expect(live.indirectlyMutedCategoryIds, isEmpty);
  });
}
