import 'package:flutter/foundation.dart';

import 'json.dart';
import 'user_status.dart';

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
