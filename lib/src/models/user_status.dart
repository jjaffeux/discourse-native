import 'package:flutter/foundation.dart';

import 'json.dart';

/// A Discourse user's custom status.
///
/// Core serializes the same object on posts, user cards, mention results,
/// current-user payloads, and Chat users. [messageBusLastId] is present on
/// snapshots so a client can start `/user-status` without missing a change.
@immutable
final class UserStatus {
  const UserStatus({
    required this.description,
    required this.emoji,
    this.endsAt,
    this.messageBusLastId,
  });

  static UserStatus? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final description = jsonText(value['description'])?.trim();
    final emoji = jsonText(value['emoji'])?.trim();
    if (description == null ||
        description.isEmpty ||
        emoji == null ||
        emoji.isEmpty) {
      return null;
    }
    return UserStatus(
      description: description,
      emoji: emoji,
      endsAt: jsonDate(value['ends_at']),
      messageBusLastId: jsonIntOrNull(value['message_bus_last_id']),
    );
  }

  final String description;
  final String emoji;
  final DateTime? endsAt;
  final int? messageBusLastId;

  bool isActiveAt(DateTime now) => endsAt?.isAfter(now) ?? true;

  Map<String, dynamic> toJson() => {
    'description': description,
    'emoji': emoji,
    'endsAt': endsAt?.toIso8601String(),
    'messageBusLastId': messageBusLastId,
  };

  factory UserStatus.fromStoredJson(Map<String, dynamic> json) => UserStatus(
    description: jsonString(json['description']),
    emoji: jsonString(json['emoji']),
    endsAt: jsonDate(json['endsAt']),
    messageBusLastId: jsonIntOrNull(json['messageBusLastId']),
  );

  @override
  bool operator ==(Object other) =>
      other is UserStatus &&
      other.description == description &&
      other.emoji == emoji &&
      other.endsAt == endsAt &&
      other.messageBusLastId == messageBusLastId;

  @override
  int get hashCode => Object.hash(description, emoji, endsAt, messageBusLastId);
}

/// A status plus the stable account id carried by mention serializers.
@immutable
final class UserStatusReference {
  const UserStatusReference({required this.status, this.userId});

  final UserStatus status;
  final int? userId;

  @override
  bool operator ==(Object other) =>
      other is UserStatusReference &&
      other.status == status &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(status, userId);
}

/// Reads the status-bearing basic-user objects used for cooked mentions.
Map<String, UserStatusReference> userStatusesByUsername(Object? value) =>
    Map.unmodifiable({
      for (final user in jsonObjects(value))
        if ((jsonText(user['username']), UserStatus.fromJson(user['status']))
            case (final username?, final status?))
          username.toLowerCase(): UserStatusReference(
            status: status,
            userId: jsonIntOrNull(user['id']),
          ),
    });
