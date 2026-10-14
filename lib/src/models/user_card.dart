import 'package:flutter/foundation.dart';

import '../data/store.dart';
import '../plugin_api/plugin_data.dart';
import 'badge.dart';
import 'json.dart';
import 'user_status.dart';

@immutable
class UserCard with Storable<UserCard> {
  const UserCard({
    required this.username,
    this.id,
    this.name,
    this.title,
    this.bioExcerpt,
    this.avatarUrl,
    this.cardBackgroundUrl,
    this.status,
    this.location,
    this.website,
    this.websiteName,
    this.createdAt,
    this.lastPostedAt,
    this.timeRead = 0,
    this.badgeCount = 0,
    this.featuredBadges = const [],
    this.timezone,
    this.canSendPrivateMessage = false,
    this.isStaff = false,
    this.isAdmin = false,
    this.isModerator = false,
    this.suspendedTill,
    this.plugins = PluginData.none,
  });

  factory UserCard.fromJson(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
    Map<String, dynamic>? payload,
  }) {
    return UserCard(
      username: jsonString(json['username']),
      id: jsonIntOrNull(json['id']),
      name: jsonText(json['name']),
      title: jsonText(json['title']),
      bioExcerpt: jsonText(json['bio_excerpt']),
      avatarUrl: resolveAvatarUrl(
        jsonText(json['avatar_template']),
        siteUrl,
        size: 240,
      ),
      cardBackgroundUrl: _backgroundUrl(
        json['card_background_upload_url'],
        siteUrl,
      ),
      status: UserStatus.fromJson(json['status']),
      location: jsonText(json['location']),
      website: jsonText(json['website']),
      websiteName: jsonText(json['website_name']),
      createdAt: jsonDate(json['created_at']),
      lastPostedAt: jsonDate(json['last_posted_at']),
      timeRead: jsonInt(json['time_read']),
      badgeCount: jsonInt(json['badge_count']),
      timezone: jsonText(json['timezone']),
      canSendPrivateMessage: json['can_send_private_message_to_user'] == true,
      featuredBadges: _featuredBadges(
        json,
        payload ?? const <String, dynamic>{},
        siteUrl,
      ),
      isStaff: json['admin'] == true || json['moderator'] == true,
      isAdmin: json['admin'] == true,
      isModerator: json['moderator'] == true,
      suspendedTill: jsonDate(json['suspended_till']),
      plugins: extensions.readUserCard(json, siteUrl),
    );
  }

  final String username;
  final int? id;
  final String? name;

  final String? title;

  final String? bioExcerpt;

  final String? avatarUrl;
  final String? cardBackgroundUrl;
  final UserStatus? status;
  final String? location;
  final String? website;
  final String? websiteName;
  final DateTime? createdAt;
  final DateTime? lastPostedAt;
  final int timeRead;
  final int badgeCount;
  final List<UserCardBadge> featuredBadges;
  final String? timezone;
  final bool canSendPrivateMessage;
  final bool isStaff;
  final bool isAdmin;
  final bool isModerator;

  /// Present only while the site reports the user as suspended.
  final DateTime? suspendedTill;

  /// Decided when drawn, not when parsed: a card is cached, and a suspension
  /// ends while it is held.
  bool isSuspendedAt(DateTime now) => suspendedTill?.isAfter(now) ?? false;

  final PluginData plugins;

  String get displayName => name ?? username;

  String get path => '/u/$username';

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
          other.cardBackgroundUrl == cardBackgroundUrl &&
          other.status == status &&
          other.location == location &&
          other.website == website &&
          other.websiteName == websiteName &&
          other.createdAt == createdAt &&
          other.lastPostedAt == lastPostedAt &&
          other.timeRead == timeRead &&
          other.badgeCount == badgeCount &&
          listEquals(other.featuredBadges, featuredBadges) &&
          other.timezone == timezone &&
          other.canSendPrivateMessage == canSendPrivateMessage &&
          other.isStaff == isStaff &&
          other.isAdmin == isAdmin &&
          other.isModerator == isModerator &&
          other.suspendedTill == suspendedTill &&
          other.plugins == plugins;

  @override
  int get hashCode => Object.hashAll([
    username,
    id,
    name,
    title,
    bioExcerpt,
    avatarUrl,
    cardBackgroundUrl,
    status,
    location,
    website,
    websiteName,
    createdAt,
    lastPostedAt,
    timeRead,
    badgeCount,
    Object.hashAll(featuredBadges),
    timezone,
    canSendPrivateMessage,
    isStaff,
    isAdmin,
    isModerator,
    suspendedTill,
    plugins,
  ]);
}

String? _backgroundUrl(dynamic value, String siteUrl) {
  final path = jsonText(value);
  if (path == null) return null;
  final relative = Uri.tryParse(path);
  if (relative == null) return null;
  final uri = Uri.tryParse(siteUrl)?.resolveUri(relative);
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http')
      ? uri.toString()
      : null;
}

/// Featured badge artwork carried by the card endpoint's side-loaded records.
@immutable
class UserCardBadge {
  const UserCardBadge({
    required this.id,
    required this.name,
    this.icon = 'certificate',
    this.imageUrl,
    this.tier = BadgeTier.bronze,
  });
  factory UserCardBadge.fromJson(Map<String, dynamic> json, String siteUrl) {
    final badge = DiscourseBadge.fromJson(json, siteUrl);
    return UserCardBadge(
      id: badge.id,
      name: badge.name,
      icon: badge.icon,
      imageUrl: badge.imageUrl,
      tier: badge.tier,
    );
  }
  final int id;
  final String name;
  final String icon;
  final String? imageUrl;
  final BadgeTier tier;
  @override
  bool operator ==(Object other) =>
      other is UserCardBadge &&
      other.id == id &&
      other.name == name &&
      other.icon == icon &&
      other.imageUrl == imageUrl &&
      other.tier == tier;
  @override
  int get hashCode => Object.hash(id, name, icon, imageUrl, tier);
}

List<UserCardBadge> _featuredBadges(
  Map<String, dynamic> user,
  Map<String, dynamic> payload,
  String siteUrl,
) {
  final badges = {
    for (final badge in jsonObjects(payload['badges']))
      jsonInt(badge['id']): badge,
  };
  final grants = {
    for (final grant in jsonObjects(payload['user_badges']))
      jsonInt(grant['id']): grant,
  };
  final featured = user['featured_user_badges'];
  final ids = featured is List
      ? featured.map(jsonIntOrNull).whereType<int>()
      : grants.keys;
  final seen = <int>{};
  return List.unmodifiable([
    for (final grantId in ids.take(3))
      if (grants[grantId] case final grant?)
        if (badges[jsonInt(grant['badge_id'])] case final badge?)
          if (seen.add(jsonInt(badge['id'])))
            UserCardBadge.fromJson(badge, siteUrl),
  ]);
}
