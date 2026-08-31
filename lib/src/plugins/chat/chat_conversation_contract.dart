import 'package:flutter/foundation.dart';

import 'chat_message.dart';

@immutable
final class ChatConversationSnapshot {
  const ChatConversationSnapshot({
    this.messages = const [],
    this.loading = false,
    this.sending = false,
    this.canLoadMorePast = false,
    this.error,
  });

  final List<ChatMessage> messages;
  final bool loading;
  final bool sending;
  final bool canLoadMorePast;
  final String? error;
}

abstract interface class ChatConversation
    implements ValueListenable<ChatConversationSnapshot> {
  String get siteUrl;

  int get channelId;

  int get threadId;

  Future<void> refresh({bool force = false});

  Future<void> loadOlder();

  Future<void> send(String message);

  void close();
}

abstract interface class ChatConversationCapability {
  ChatConversation openThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
  });
}
