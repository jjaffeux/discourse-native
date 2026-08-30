import 'package:flutter/foundation.dart';

import '../../models/json.dart';
import 'chat_channel.dart';

/// One result from Chat's `/chat/api/chatables` direct-message search.
///
/// Core returns people and existing channels in separate arrays, but presents
/// them as one ranked list. Keeping the ranked item typed lets the picker open
/// an existing conversation without making another create request.
sealed class ChatDirectMessageSearchItem {
  const ChatDirectMessageSearchItem({
    required this.identifier,
    required this.matchQuality,
    required this.enabled,
  });

  final String identifier;
  final int matchQuality;
  final bool enabled;
}

@immutable
final class ChatDirectMessageUser extends ChatDirectMessageSearchItem {
  const ChatDirectMessageUser({
    required super.identifier,
    required super.matchQuality,
    required super.enabled,
    required this.username,
    this.name,
    this.avatarUrl,
  });

  factory ChatDirectMessageUser.fromJson(
    Map<String, dynamic> json,
    String siteUrl,
  ) {
    final model = jsonObject(json['model']);
    return ChatDirectMessageUser(
      identifier: jsonText(json['identifier']) ?? '',
      matchQuality: jsonIntOrNull(json['match_quality']) ?? 3,
      enabled: model['has_chat_enabled'] == true,
      username: jsonString(model['username']),
      name: jsonText(model['name']),
      avatarUrl: resolveAvatarUrl(jsonText(model['avatar_template']), siteUrl),
    );
  }

  final String username;
  final String? name;
  final String? avatarUrl;
}

@immutable
final class ChatDirectMessageChannel extends ChatDirectMessageSearchItem {
  const ChatDirectMessageChannel({
    required super.identifier,
    required super.matchQuality,
    required super.enabled,
    required this.channel,
  });

  factory ChatDirectMessageChannel.fromJson(
    Map<String, dynamic> json,
    String siteUrl,
  ) {
    final model = jsonObject(json['model']);
    final channel = ChatChannel.fromJson(model, siteUrl);
    final chatable = jsonObject(model['chatable']);
    final users = jsonObjects(chatable['users']);
    return ChatDirectMessageChannel(
      identifier: jsonText(json['identifier']) ?? '',
      matchQuality: jsonIntOrNull(json['match_quality']) ?? 3,
      enabled: users.length != 1 || users.single['has_chat_enabled'] != false,
      channel: channel,
    );
  }

  final ChatChannel channel;
}

@immutable
final class ChatDirectMessageSearchResults {
  ChatDirectMessageSearchResults(Iterable<ChatDirectMessageSearchItem> items)
    : items = List.unmodifiable(items);

  factory ChatDirectMessageSearchResults.fromJson(
    Map<String, dynamic> json,
    String siteUrl,
  ) {
    final items = <ChatDirectMessageSearchItem>[];
    for (final user in jsonObjects(json['users'])) {
      final candidate = ChatDirectMessageUser.fromJson(user, siteUrl);
      if (candidate.username.isNotEmpty) items.add(candidate);
    }
    for (final channel in jsonObjects(json['direct_message_channels'])) {
      final candidate = ChatDirectMessageChannel.fromJson(channel, siteUrl);
      if (candidate.channel.id > 0) items.add(candidate);
    }
    items.sort(_compareItems);
    return ChatDirectMessageSearchResults(items.take(10));
  }

  final List<ChatDirectMessageSearchItem> items;

  static int _compareItems(
    ChatDirectMessageSearchItem left,
    ChatDirectMessageSearchItem right,
  ) {
    final quality = left.matchQuality.compareTo(right.matchQuality);
    if (quality != 0) return quality;

    final type = _typePriority(left).compareTo(_typePriority(right));
    if (type != 0) return type;

    if (left.enabled != right.enabled) return left.enabled ? -1 : 1;
    return 0;
  }

  static int _typePriority(ChatDirectMessageSearchItem item) => switch (item) {
    ChatDirectMessageUser() => 0,
    ChatDirectMessageChannel() => 1,
  };
}
