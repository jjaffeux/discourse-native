import 'package:flutter/foundation.dart';

import '../../data/store.dart';
import '../../models/json.dart';
import '../../plugin_api/reaction_presentation.dart';

@immutable
class ChatReactor implements ReactionUser {
  const ChatReactor({
    required this.id,
    required this.username,
    required this.reaction,
    this.name,
    this.avatarUrl,
  });

  factory ChatReactor.fromJson(Map<String, dynamic> json, String siteUrl) =>
      ChatReactor(
        id: jsonInt(json['id']),
        username: jsonString(json['username']),
        name: jsonText(json['name']),
        avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
        reaction: jsonString(json['reaction']),
      );

  @override
  final int id;

  @override
  final String username;

  @override
  final String reaction;

  @override
  final String? name;

  @override
  final String? avatarUrl;

  @override
  String get displayName => name ?? username;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatReactor &&
          other.id == id &&
          other.username == username &&
          other.reaction == reaction &&
          other.name == name &&
          other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(id, username, reaction, name, avatarUrl);
}

@immutable
class ChatMessageReactors
    with Storable<ChatMessageReactors>
    implements ReactionUsersPage {
  const ChatMessageReactors({
    required this.channelId,
    required this.messageId,
    required this.reactors,
    required this.total,
    this.filter,
  });

  static const int maximumPageSize = 50;

  factory ChatMessageReactors.parse(
    Map<String, dynamic> json, {
    required int channelId,
    required int messageId,
    required String siteUrl,
    String? filter,
  }) => ChatMessageReactors(
    channelId: channelId,
    messageId: messageId,
    filter: filter,
    reactors: List.unmodifiable(
      jsonObjects(json['users'])
          .take(maximumPageSize)
          .map((entry) => ChatReactor.fromJson(entry, siteUrl)),
    ),
    total: jsonInt(json['total_rows']),
  );

  final int channelId;
  final int messageId;
  final String? filter;

  @override
  final List<ChatReactor> reactors;

  @override
  final int total;

  @override
  Object get storeId => key(channelId, messageId, filter);

  @override
  ChatMessageReactors merge(ChatMessageReactors incoming) =>
      this == incoming ? this : incoming;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageReactors &&
          other.channelId == channelId &&
          other.messageId == messageId &&
          other.filter == filter &&
          other.total == total &&
          listEquals(other.reactors, reactors);

  @override
  int get hashCode => Object.hash(
    channelId,
    messageId,
    filter,
    total,
    Object.hashAll(reactors),
  );

  static String key(int channelId, int messageId, String? filter) =>
      [channelId, messageId, ?filter].join(':');
}
