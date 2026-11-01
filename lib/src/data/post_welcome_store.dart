import 'dart:convert';

import 'serial_operation_queue.dart';
import 'site_preference_keys.dart';

final class PostWelcomeStore {
  const PostWelcomeStore();

  static const _preferences = OwnedSitePreferences(
    id: 'post_welcome_seen',
    scope: SitePreferenceScope.namedItem,
    value: SitePreferenceValue.boolean,
  );
  static final _claims = SerialOperationQueue();

  Future<bool> _hasSeen(String siteUrl, int? viewerId, int postId) async =>
      await _preferences.read(_identity(siteUrl, viewerId, postId)) ?? false;

  Future<bool> claim(String siteUrl, int? viewerId, int postId) => _claims.run(
    owner: _preferences,
    key: (siteUrl, viewerId, postId),
    operation: () async {
      if (await _hasSeen(siteUrl, viewerId, postId)) return false;
      await _preferences.write(_identity(siteUrl, viewerId, postId), true);
      return _hasSeen(siteUrl, viewerId, postId);
    },
  );

  SitePreferenceIdentity _identity(String siteUrl, int? viewerId, int postId) =>
      SitePreferenceIdentity.namedItem(siteUrl, jsonEncode([viewerId, postId]));
}
