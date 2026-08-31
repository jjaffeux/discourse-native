import 'package:flutter/foundation.dart' show immutable;

import '../../models/json.dart';
import 'chat_channel.dart';
import 'chat_message.dart';

typedef ChatPins = ({List<ChatPin> pins, ChatMembership? membership});

@immutable
class ChatPin {
  const ChatPin({
    required this.id,
    required this.messageId,
    required this.message,
    required this.pinnedBy,
    this.pinnedAt,
    this.excerpt = '',
  });

  static const int maximumPerChannel = 20;

  factory ChatPin.fromJson(Map<String, dynamic> json, String siteUrl) {
    final messageJson = jsonObject(json['message']);
    final parsed = ChatMessage.fromJson(messageJson, siteUrl);
    return ChatPin(
      id: jsonInt(json['id']),
      messageId: jsonIntOrNull(json['chat_message_id']) ?? parsed.id,
      message: parsed.pinned ? parsed : parsed.withPinned(true),
      pinnedBy: ChatMessageAuthor.fromJson(json['pinned_by'], siteUrl),
      pinnedAt: jsonDate(json['pinned_at']),
      excerpt: jsonHtmlText(json['excerpt']) ?? '',
    );
  }

  static ChatPins parse(Map<String, dynamic> json, String siteUrl) {
    final membership = json['membership'];
    return (
      pins: List.unmodifiable([
        for (final entry in jsonObjects(
          json['pinned_messages'],
        ).take(maximumPerChannel))
          ChatPin.fromJson(entry, siteUrl),
      ]),
      membership: membership is Map<String, dynamic>
          ? ChatMembership.fromJson(membership)
          : null,
    );
  }

  final int id;
  final int messageId;
  final ChatMessage message;
  final ChatMessageAuthor pinnedBy;
  final DateTime? pinnedAt;
  final String excerpt;

  @override
  bool operator ==(Object other) =>
      other is ChatPin &&
      other.id == id &&
      other.messageId == messageId &&
      other.message == message &&
      other.pinnedBy == pinnedBy &&
      other.pinnedAt == pinnedAt &&
      other.excerpt == excerpt;

  @override
  int get hashCode =>
      Object.hash(id, messageId, message, pinnedBy, pinnedAt, excerpt);
}
