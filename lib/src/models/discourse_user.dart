import 'package:flutter/foundation.dart';

import 'json.dart';

/// The account an API key belongs to, from `/session/current.json`.
@immutable
class DiscourseUser {
  const DiscourseUser({
    required this.username,
    this.id,
    this.name,
    this.avatarUrl,
    this.draftCount = 0,
    this.canCreatePoll,
    this.staff = false,
    this.groups = const [],
  });

  factory DiscourseUser.fromJson(Map<String, dynamic> json) => DiscourseUser(
    username: json['username'] as String,
    // Absent from anything stored before the live counters needed it, which is
    // why it is nullable rather than required — see `ShellController`, which
    // asks the site again when it finds one missing.
    id: jsonIntOrNull(json['id']),
    name: json['name'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    draftCount: jsonInt(json['draftCount']),
    // Optional so accounts persisted before Poll support remain readable. A
    // stored value is display state only; ShellController requires a fresh
    // session read before it treats this as a capability.
    canCreatePoll: json['canCreatePoll'] as bool?,
    staff: json['staff'] == true,
    groups: List.unmodifiable(
      jsonArray(json['groups']).map(jsonText).whereType<String>(),
    ),
  );

  final String username;

  /// The account's own id, which is how Discourse names the message_bus
  /// channels it publishes a user's counts on.
  final int? id;

  final String? name;
  final String? avatarUrl;
  final int draftCount;

  /// The Poll plugin's session capability. Null means the plugin did not add
  /// it (or this account predates the field), rather than false.
  final bool? canCreatePoll;

  /// Whether the current account is an administrator or moderator.
  final bool staff;

  /// Group names from the freshly loaded current-user payload.
  final List<String> groups;

  Map<String, dynamic> toJson() => {
    'username': username,
    'id': id,
    'name': name,
    'avatarUrl': avatarUrl,
    'draftCount': draftCount,
    'canCreatePoll': canCreatePoll,
    'staff': staff,
    'groups': groups,
  };

  /// Display name if the site has one, otherwise the username.
  String get displayName => (name?.isNotEmpty ?? false) ? name! : username;

  @override
  bool operator ==(Object other) =>
      other is DiscourseUser &&
      other.username == username &&
      other.id == id &&
      other.name == name &&
      other.avatarUrl == avatarUrl &&
      other.draftCount == draftCount &&
      other.canCreatePoll == canCreatePoll &&
      other.staff == staff &&
      listEquals(other.groups, groups);

  @override
  int get hashCode => Object.hash(
    username,
    id,
    name,
    avatarUrl,
    draftCount,
    canCreatePoll,
    staff,
    Object.hashAll(groups),
  );
}
