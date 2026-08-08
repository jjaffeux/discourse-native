import 'package:flutter/foundation.dart';

import 'json.dart';
import 'post.dart' show resolveAvatarUrl;

/// One account the site offered while somebody was typing a mention.
///
/// Deliberately not a [UserCard], and deliberately not [Storable]. A card files
/// itself in the identity store under its username, and `loadUserCard` returns
/// early on anything it finds there — so putting search hits in the store would
/// leave the card popup showing records with no bio, no join date and no
/// badges, and never refetching them.
@immutable
class FoundUser {
  const FoundUser({required this.username, this.name, this.avatarUrl});

  factory FoundUser.fromJson(Map<String, dynamic> json, String siteUrl) {
    return FoundUser(
      username: (json['username'] ?? '') as String,
      // Absent on a site with `enable_names` off, where the username is the
      // only name anyone has.
      name: jsonText(json['name']),
      avatarUrl: resolveAvatarUrl(json['avatar_template'] as String?, siteUrl),
    );
  }

  final String username;
  final String? name;
  final String? avatarUrl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FoundUser &&
          other.username == username &&
          other.name == name &&
          other.avatarUrl == avatarUrl);

  @override
  int get hashCode => Object.hash(username, name, avatarUrl);
}
