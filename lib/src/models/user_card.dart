import 'package:flutter/foundation.dart';

import '../data/store.dart';
import '../plugin_api/plugin_data.dart';
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
    this.status,
    this.location,
    this.website,
    this.websiteName,
    this.createdAt,
    this.lastPostedAt,
    this.timeRead = 0,
    this.badgeCount = 0,
    this.isStaff = false,
    this.suspendedTill,
    this.plugins = PluginData.none,
  });

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
  final UserStatus? status;
  final String? location;
  final String? website;
  final String? websiteName;
  final DateTime? createdAt;
  final DateTime? lastPostedAt;
  final int timeRead;
  final int badgeCount;
  final bool isStaff;

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
          other.status == status &&
          other.location == location &&
          other.website == website &&
          other.websiteName == websiteName &&
          other.createdAt == createdAt &&
          other.lastPostedAt == lastPostedAt &&
          other.timeRead == timeRead &&
          other.badgeCount == badgeCount &&
          other.isStaff == isStaff &&
          other.suspendedTill == suspendedTill &&
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
    suspendedTill,
    plugins,
  );
}
