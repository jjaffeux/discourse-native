import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'site_preference_keys.dart';

final class PostWelcomeStore extends ChangeNotifier {
  static const _preferences = OwnedSitePreferences(
    id: 'post_welcome_seen',
    scope: SitePreferenceScope.namedItem,
    value: SitePreferenceValue.boolean,
  );

  Future<bool> hasSeen(String siteUrl, int? viewerId, int postId) async =>
      await _preferences.read(_identity(siteUrl, viewerId, postId)) ?? false;

  Future<void> markSeen(String siteUrl, int? viewerId, int postId) {
    final saved = _preferences.write(
      _identity(siteUrl, viewerId, postId),
      true,
    );
    notifyListeners();
    return saved;
  }

  SitePreferenceIdentity _identity(String siteUrl, int? viewerId, int postId) =>
      SitePreferenceIdentity.namedItem(siteUrl, jsonEncode([viewerId, postId]));
}
