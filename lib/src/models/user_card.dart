import 'package:flutter/foundation.dart';

import '../data/store.dart';
import '../plugin_api/plugin_data.dart';
import 'json.dart';
import 'user_status.dart';

/// The summary of an account behind `/u/{username}/card.json`.
///
/// Deliberately much less than a full profile: this is what fits in a popup
/// next to the avatar that was clicked.
@immutable
class UserCard with Storable<UserCard> {
  const UserCard({
    required this.username,
    this.id,
    this.name,
    this.title,
    this.bioExcerpt,
    this.avatarUrl,
    this.status,
    this.location,
    this.website,
    this.websiteName,
    this.createdAt,
    this.lastPostedAt,
    this.timeRead = 0,
    this.badgeCount = 0,
    this.isStaff = false,
    this.isSuspended = false,
    this.plugins = PluginData.none,
  });

  /// [json] is the `user` object from the card payload.
  factory UserCard.fromJson(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    return UserCard(
      username: jsonString(json['username']),
      id: jsonIntOrNull(json['id']),
      name: jsonText(json['name']),
      title: jsonText(json['title']),
      // HTML, like a post's `cooked` — Discourse resolves mentions and emoji
      // in a bio the same way.
      bioExcerpt: jsonText(json['bio_excerpt']),
      avatarUrl: resolveAvatarUrl(
        jsonText(json['avatar_template']),
        siteUrl,
        size: 240,
      ),
      status: UserStatus.fromJson(json['status']),
      location: jsonText(json['location']),
      website: jsonText(json['website']),
      websiteName: jsonText(json['website_name']),
      createdAt: jsonDate(json['created_at']),
      lastPostedAt: jsonDate(json['last_posted_at']),
      timeRead: jsonInt(json['time_read']),
      badgeCount: jsonInt(json['badge_count']),
      isStaff: json['admin'] == true || json['moderator'] == true,
      // A suspension that has not expired; the card says so rather than
      // pretending the account is ordinary.
      isSuspended:
          jsonDate(json['suspended_till'])?.isAfter(DateTime.now()) ?? false,
      plugins: extensions.readUserCard(json, siteUrl),
    );
  }

  final String username;
  final int? id;
  final String? name;

  /// The user's title, as shown beside their name on a post.
  final String? title;

  /// First few lines of the bio, as HTML.
  final String? bioExcerpt;

  final String? avatarUrl;
  final UserStatus? status;
  final String? location;
  final String? website;
  final String? websiteName;
  final DateTime? createdAt;
  final DateTime? lastPostedAt;
  final int timeRead;
  final int badgeCount;
  final bool isStaff;
  final bool isSuspended;

  /// Values contributed by serializers belonging to installed plugins.
  final PluginData plugins;

  String get displayName => name ?? username;

  /// Where the full profile lives on the site.
  String get path => '/u/$username';

  /// Accounts are identified by name here, not by id: a post carries the
  /// username of whoever wrote it and nothing else, so that is the only handle
  /// the thing wanting the card ever has.
  ///
  /// Lowercased, because Discourse resolves usernames case-insensitively: a
  /// link that says `/u/johndoe` and a payload that says `JohnDoe` are one
  /// account, and keying the store by the payload's casing would file the
  /// card where the panel never looks.
  @override
  Object get storeId => username.toLowerCase();

  @override
  UserCard merge(UserCard incoming) => this == incoming ? this : incoming;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserCard &&
          other.username == username &&
          other.id == id &&
          other.name == name &&
          other.title == title &&
          other.bioExcerpt == bioExcerpt &&
          other.avatarUrl == avatarUrl &&
          other.status == status &&
          other.location == location &&
          other.website == website &&
          other.websiteName == websiteName &&
          other.createdAt == createdAt &&
          other.lastPostedAt == lastPostedAt &&
          other.timeRead == timeRead &&
          other.badgeCount == badgeCount &&
          other.isStaff == isStaff &&
          other.isSuspended == isSuspended &&
          other.plugins == plugins;

  @override
  int get hashCode => Object.hash(
    username,
    id,
    name,
    title,
    bioExcerpt,
    avatarUrl,
    status,
    location,
    website,
    websiteName,
    createdAt,
    lastPostedAt,
    timeRead,
    badgeCount,
    isStaff,
    isSuspended,
    plugins,
  );
}
