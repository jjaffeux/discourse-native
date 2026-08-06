import 'package:flutter/foundation.dart';

/// The account an API key belongs to, from `/session/current.json`.
@immutable
class DiscourseUser {
  const DiscourseUser({
    required this.username,
    this.id,
    this.name,
    this.avatarUrl,
  });

  factory DiscourseUser.fromJson(Map<String, dynamic> json) => DiscourseUser(
    username: json['username'] as String,
    // Absent from anything stored before the live counters needed it, which is
    // why it is nullable rather than required — see `ShellController`, which
    // asks the site again when it finds one missing.
    id: switch (json['id']) {
      final num id => id.toInt(),
      _ => null,
    },
    name: json['name'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
  );

  final String username;

  /// The account's own id, which is how Discourse names the message_bus
  /// channels it publishes a user's counts on.
  final int? id;

  final String? name;
  final String? avatarUrl;

  Map<String, dynamic> toJson() => {
    'username': username,
    'id': id,
    'name': name,
    'avatarUrl': avatarUrl,
  };

  /// Display name if the site has one, otherwise the username.
  String get displayName => (name?.isNotEmpty ?? false) ? name! : username;

  @override
  bool operator ==(Object other) =>
      other is DiscourseUser &&
      other.username == username &&
      other.id == id &&
      other.name == name &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(username, id, name, avatarUrl);
}
