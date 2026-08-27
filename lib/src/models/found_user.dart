import 'package:flutter/foundation.dart';

import 'json.dart';
import 'user_status.dart';

/// One account the site offered while somebody was typing a mention.
///
/// Deliberately not a [UserCard], and deliberately not [Storable]. A card files
/// itself in the identity store under its username, and `loadUserCard` returns
/// early on anything it finds there — so putting search hits in the store would
/// leave the card popup showing records with no bio, no join date and no
/// badges, and never refetching them.
@immutable
class FoundUser {
  const FoundUser({
    required this.username,
    this.id,
    this.name,
    this.avatarUrl,
    this.status,
  });

  factory FoundUser.fromJson(Map<String, dynamic> json, String siteUrl) {
    return FoundUser(
      username: jsonString(json['username']),
      id: jsonIntOrNull(json['id']),
      // Absent on a site with `enable_names` off, where the username is the
      // only name anyone has.
      name: jsonText(json['name']),
      avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
      status: UserStatus.fromJson(json['status']),
    );
  }

  final String username;
  final int? id;
  final String? name;
  final String? avatarUrl;
  final UserStatus? status;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FoundUser &&
          other.username == username &&
          other.id == id &&
          other.name == name &&
          other.avatarUrl == avatarUrl &&
          other.status == status);

  @override
  int get hashCode => Object.hash(username, id, name, avatarUrl, status);
}
