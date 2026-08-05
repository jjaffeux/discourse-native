import 'package:flutter/foundation.dart';

/// The account an API key belongs to, from `/session/current.json`.
@immutable
class DiscourseUser {
  const DiscourseUser({required this.username, this.name, this.avatarUrl});

  factory DiscourseUser.fromJson(Map<String, dynamic> json) => DiscourseUser(
    username: json['username'] as String,
    name: json['name'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
  );

  final String username;
  final String? name;
  final String? avatarUrl;

  Map<String, dynamic> toJson() => {
    'username': username,
    'name': name,
    'avatarUrl': avatarUrl,
  };

  /// Display name if the site has one, otherwise the username.
  String get displayName => (name?.isNotEmpty ?? false) ? name! : username;

  @override
  bool operator ==(Object other) =>
      other is DiscourseUser &&
      other.username == username &&
      other.name == name &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(username, name, avatarUrl);
}
