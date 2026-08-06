import 'package:flutter/foundation.dart';

import 'post.dart' show resolveAvatarUrl;

/// The summary of an account behind `/u/{username}/card.json`.
///
/// Deliberately much less than a full profile: this is what fits in a popup
/// next to the avatar that was clicked.
@immutable
class UserCard {
  const UserCard({
    required this.username,
    this.name,
    this.title,
    this.bioExcerpt,
    this.avatarUrl,
    this.createdAt,
    this.lastPostedAt,
    this.badgeCount = 0,
    this.isStaff = false,
    this.isSuspended = false,
  });

  /// [json] is the `user` object from the card payload.
  factory UserCard.fromJson(Map<String, dynamic> json, String siteUrl) {
    return UserCard(
      username: (json['username'] ?? '') as String,
      name: _text(json['name']),
      title: _text(json['title']),
      // HTML, like a post's `cooked` — Discourse resolves mentions and emoji
      // in a bio the same way.
      bioExcerpt: _text(json['bio_excerpt']),
      avatarUrl: resolveAvatarUrl(json['avatar_template'] as String?, siteUrl),
      createdAt: DateTime.tryParse((json['created_at'] ?? '') as String),
      lastPostedAt: DateTime.tryParse((json['last_posted_at'] ?? '') as String),
      badgeCount: switch (json['badge_count']) {
        final num n => n.toInt(),
        _ => 0,
      },
      isStaff: json['admin'] == true || json['moderator'] == true,
      // A suspension that has not expired; the card says so rather than
      // pretending the account is ordinary.
      isSuspended:
          DateTime.tryParse(
            (json['suspended_till'] ?? '') as String,
          )?.isAfter(DateTime.now()) ??
          false,
    );
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  final String username;
  final String? name;

  /// The user's title, as shown beside their name on a post.
  final String? title;

  /// First few lines of the bio, as HTML.
  final String? bioExcerpt;

  final String? avatarUrl;
  final DateTime? createdAt;
  final DateTime? lastPostedAt;
  final int badgeCount;
  final bool isStaff;
  final bool isSuspended;

  String get displayName => name ?? username;

  /// Where the full profile lives on the site.
  String get path => '/u/$username';
}
