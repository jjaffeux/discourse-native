import 'dart:async';

import 'package:discourse_native/src/plugins/chat/chat_contract.dart';
import 'package:flutter/foundation.dart';

typedef FakeChatConversationKey = ({
  String siteUrl,
  int channelId,
  int threadId,
});

final class FakeChatConversationCapability
    implements ChatConversationCapability {
  final Map<FakeChatConversationKey, FakeChatConversation> conversations = {};
  final List<FakeChatConversationKey> opened = [];

  FakeChatConversation seed({
    required String siteUrl,
    required int channelId,
    required int threadId,
    ChatConversationSnapshot snapshot = const ChatConversationSnapshot(),
    List<ChatMessage> olderMessages = const [],
    bool canLoadMoreAfterOlder = false,
  }) {
    final key = (siteUrl: siteUrl, channelId: channelId, threadId: threadId);
    final conversation = FakeChatConversation(
      siteUrl: siteUrl,
      channelId: channelId,
      threadId: threadId,
      snapshot: snapshot,
      olderMessages: olderMessages,
      canLoadMoreAfterOlder: canLoadMoreAfterOlder,
    );
    conversations[key] = conversation;
    return conversation;
  }

  FakeChatConversation? find({
    required String siteUrl,
    required int channelId,
    required int threadId,
  }) =>
      conversations[(
        siteUrl: siteUrl,
        channelId: channelId,
        threadId: threadId,
      )];

  @override
  ChatConversation openThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
  }) {
    final key = (siteUrl: siteUrl, channelId: channelId, threadId: threadId);
    opened.add(key);
    return conversations.putIfAbsent(
      key,
      () => FakeChatConversation(
        siteUrl: siteUrl,
        channelId: channelId,
        threadId: threadId,
      ),
    );
  }
}

final class FakeChatConversation extends ChangeNotifier
    implements ChatConversation {
  FakeChatConversation({
    required this.siteUrl,
    required this.channelId,
    required this.threadId,
    ChatConversationSnapshot snapshot = const ChatConversationSnapshot(),
    this.olderMessages = const [],
    this.canLoadMoreAfterOlder = false,
  }) : _value = snapshot;

  @override
  final String siteUrl;

  @override
  final int channelId;

  @override
  final int threadId;

  List<ChatMessage> olderMessages;
  bool canLoadMoreAfterOlder;
  bool holdRefreshes = false;
  int refreshCalls = 0;
  int loadOlderCalls = 0;
  int closeCalls = 0;
  final List<String> sentMessages = [];
  final List<Completer<ChatConversationSnapshot>> pendingRefreshes = [];
  Object? sendFailure;
  String? sendError;

  ChatConversationSnapshot _value;

  @override
  ChatConversationSnapshot get value => _value;

  void setSnapshot(ChatConversationSnapshot snapshot) {
    _value = snapshot;
    notifyListeners();
  }

  @override
  Future<void> refresh({bool force = false}) async {
    refreshCalls++;
    if (!holdRefreshes) return;
    final response = Completer<ChatConversationSnapshot>();
    pendingRefreshes.add(response);
    setSnapshot(
      ChatConversationSnapshot(
        messages: _value.messages,
        loading: true,
        sending: _value.sending,
        canLoadMorePast: _value.canLoadMorePast,
        error: _value.error,
      ),
    );
    setSnapshot(await response.future);
  }

  @override
  Future<void> loadOlder() async {
    loadOlderCalls++;
    if (!_value.canLoadMorePast || olderMessages.isEmpty) return;
    final byId = <int, ChatMessage>{
      for (final message in [...olderMessages, ..._value.messages])
        message.id: message,
    };
    final messages = byId.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    setSnapshot(
      ChatConversationSnapshot(
        messages: List.unmodifiable(messages),
        canLoadMorePast: canLoadMoreAfterOlder,
      ),
    );
  }

  @override
  Future<void> send(String message) async {
    sentMessages.add(message);
    if (sendFailure case final failure?) throw failure;
    if (sendError case final error?) {
      setSnapshot(
        ChatConversationSnapshot(
          messages: _value.messages,
          canLoadMorePast: _value.canLoadMorePast,
          error: error,
        ),
      );
    }
  }

  @override
  void close() => closeCalls++;
}
