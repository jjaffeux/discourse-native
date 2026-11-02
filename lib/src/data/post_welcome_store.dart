import 'dart:convert';

import 'serial_operation_queue.dart';
import 'site_preference_keys.dart';

final class PostWelcomeStore {
  const PostWelcomeStore({this.clock = DateTime.now});

  final DateTime Function() clock;

  static const _preferences = OwnedSitePreferences(
    id: 'post_welcome_seen',
    scope: SitePreferenceScope.namedItem,
    value: SitePreferenceValue.boolean,
  );
  static final _claims = SerialOperationQueue();

  Future<bool> _hasSeen(String siteUrl, int? viewerId, int postId) async =>
      await _preferences.read(_identity(siteUrl, viewerId, postId)) ?? false;

  Future<bool> claim(
    String siteUrl,
    int? viewerId,
    int postId, {
    required DateTime? createdAt,
  }) => _claims.run(
    owner: _preferences,
    key: (siteUrl, viewerId, postId),
    operation: () async {
      if (createdAt == null) return false;
      final created = createdAt.toUtc();
      final lastDay = DateTime.utc(created.year, created.month + 2, 0).day;
      final expires = DateTime.utc(
        created.year,
        created.month + 1,
        created.day > lastDay ? lastDay : created.day,
        created.hour,
        created.minute,
        created.second,
        created.millisecond,
        created.microsecond,
      );
      if (clock().toUtc().isAfter(expires)) return false;
      if (await _hasSeen(siteUrl, viewerId, postId)) return false;
      await _preferences.write(_identity(siteUrl, viewerId, postId), true);
      return _hasSeen(siteUrl, viewerId, postId);
    },
  );

  SitePreferenceIdentity _identity(String siteUrl, int? viewerId, int postId) =>
      SitePreferenceIdentity.namedItem(siteUrl, jsonEncode([viewerId, postId]));
}
