import 'dart:convert';

import 'site_preference_keys.dart';

final class PostWelcomeStore {
  const PostWelcomeStore({this.clock = DateTime.now});

  final DateTime Function() clock;

  static const _preferences = OwnedSitePreferences(
    id: 'post_welcome_seen',
    scope: SitePreferenceScope.namedItem,
    value: SitePreferenceValue.boolean,
  );

  Future<bool> claim(
    String siteUrl,
    int? viewerId,
    int postId, {
    required DateTime? createdAt,
  }) async {
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
    return _preferences.claim(
      _identity(siteUrl, viewerId, postId),
      isEligible: () => !clock().toUtc().isAfter(expires),
    );
  }

  SitePreferenceIdentity _identity(String siteUrl, int? viewerId, int postId) =>
      SitePreferenceIdentity.namedItem(siteUrl, jsonEncode([viewerId, postId]));
}
