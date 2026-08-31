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
    ChatConversationSnapshot? snapshotAfterLoadOlder,
    ChatConversationSnapshot? snapshotAfterSend,
  }) {
    final key = (siteUrl: siteUrl, channelId: channelId, threadId: threadId);
    final conversation = FakeChatConversation(
      siteUrl: siteUrl,
      channelId: channelId,
      threadId: threadId,
      snapshot: snapshot,
      snapshotAfterLoadOlder: snapshotAfterLoadOlder,
      snapshotAfterSend: snapshotAfterSend,
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
    this.snapshotAfterLoadOlder,
    this.snapshotAfterSend,
  }) : _value = snapshot;

  @override
  final String siteUrl;

  @override
  final int channelId;

  @override
  final int threadId;

  final ChatConversationSnapshot? snapshotAfterLoadOlder;
  final ChatConversationSnapshot? snapshotAfterSend;
  int refreshCalls = 0;
  int loadOlderCalls = 0;
  int closeCalls = 0;
  final List<String> sentMessages = [];
  bool _closed = false;

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
  }

  @override
  Future<void> loadOlder() async {
    loadOlderCalls++;
    final configured = snapshotAfterLoadOlder;
    if (configured != null) setSnapshot(configured);
  }

  @override
  Future<void> send(String message) async {
    sentMessages.add(message);
    final configured = snapshotAfterSend;
    if (configured != null) setSnapshot(configured);
  }

  @override
  void close() {
    closeCalls++;
    if (_closed) return;
    _closed = true;
    dispose();
  }
}
