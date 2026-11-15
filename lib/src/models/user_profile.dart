import 'package:flutter/foundation.dart';

import 'json.dart';
import 'plugin_data.dart';
import 'user_card.dart';

/// The `user` object of `/u/{username}.json`. Discourse's UserSerializer
/// extends UserCardSerializer, so the card reads the same object; the profile
/// adds the fields only the full serializer carries.
@immutable
final class UserProfile {
  const UserProfile({
    required this.card,
    this.bioCooked,
    this.lastSeenAt,
    this.hidden = false,
  });

  factory UserProfile.fromJson(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
    Map<String, dynamic>? payload,
  }) => UserProfile(
    card: UserCard.fromJson(
      json,
      siteUrl,
      extensions: extensions,
      payload: payload,
    ),
    bioCooked: jsonText(json['bio_cooked']),
    lastSeenAt: jsonDate(json['last_seen_at']),
    hidden: json['profile_hidden'] == true,
  );

  final UserCard card;
  final String? bioCooked;
  final DateTime? lastSeenAt;

  /// The person hid their public profile: the server sends identity only.
  final bool hidden;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          other.card == card &&
          other.bioCooked == bioCooked &&
          other.lastSeenAt == lastSeenAt &&
          other.hidden == hidden;

  @override
  int get hashCode => Object.hash(card, bioCooked, lastSeenAt, hidden);
}
