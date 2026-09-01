import 'chat_channel.dart';
import 'chat_direct_message_search.dart';
import 'chat_message.dart';
import 'chat_pin.dart';
import 'chat_reactors.dart';
import 'chat_search.dart';
import 'chat_thread.dart';

enum ChatReactionAction { add, remove }

typedef ChatMessageMove = ({int destinationChannelId, int firstMovedMessageId});

abstract interface class ChatApi {
  Future<ChatDirectMessageSearchResults> searchChatDirectMessages({
    required String siteUrl,
    required String apiKey,
    required String term,
    bool includeGroups = false,
    bool includeDirectMessageChannels = true,
    String? clientId,
  });

  Future<ChatChannel> createChatDirectMessageChannel({
    required String siteUrl,
    required String apiKey,
    required List<String> usernames,
    List<String> groups = const [],
    String? name,
    bool upsert = false,
    String? clientId,
  });

  Future<ChatChannels> chatChannels({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  });

  Future<ChatChannel> chatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  });

  Future<ChatChannel> updateChatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? name,
    String? slug,
    String? description,
    bool? threadingEnabled,
    String? clientId,
  });

  Future<ChatChannel> updateChatChannelStatus({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required ChatChannelStatus status,
    String? clientId,
  });

  Future<void> updateChatChannelStarred({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required bool starred,
    String? clientId,
  });

  Future<ChatMembership> updateChatChannelNotifications({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    bool? muted,
    ChatChannelNotificationLevel? notificationLevel,
    String? clientId,
  });

  Future<ChatChannelMembersPage> chatChannelMembers({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String username = '',
    int offset = 0,
    int limit = 20,
    String? clientId,
  });

  Future<ChatChannelBrowsePage> browseChatChannels({
    required String siteUrl,
    required String apiKey,
    String filter = '',
    ChatChannelBrowseStatus status = ChatChannelBrowseStatus.all,
    int offset = 0,
    int limit = ChatChannelBrowsePage.pageSize,
    String? clientId,
  });

  Future<ChatMembership> followChatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  });

  Future<ChatMembership> unfollowChatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  });

  Future<ChatThreadPage> chatThreads({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = ChatThreadPage.pageSize,
    String? clientId,
  });

  Future<ChatThreadPage> chatChannelThreads({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    int offset = 0,
    int limit = ChatThreadPage.pageSize,
    String? clientId,
  });

  Future<ChatSearchPage> searchChatMessages({
    required String siteUrl,
    required String apiKey,
    required String query,
    int? channelId,
    ChatSearchSort sort = ChatSearchSort.relevance,
    int offset = 0,
    int limit = ChatSearchPage.defaultPageSize,
    bool excludeThreads = false,
    String? clientId,
  });

  Future<ChatMessagePage> chatMessages({
    required String siteUrl,
    required int channelId,
    int? before,
    int? after,
    int? targetMessageId,
    bool fromLastRead = false,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  });

  Future<void> markChatChannelRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  });

  Future<ChatMessagePage> chatThreadMessages({
    required String siteUrl,
    required int channelId,
    required int threadId,
    int? before,
    int? after,
    int? targetMessageId,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  });

  Future<ChatThread> chatThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
    String? apiKey,
    String? clientId,
  });

  Future<ChatThread> createChatThread({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int originalMessageId,
    String? title,
    String? clientId,
  });

  Future<void> updateChatThreadTitle({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required String title,
    String? clientId,
  });

  Future<ChatThreadMembership> updateChatThreadNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required ChatThreadNotificationLevel notificationLevel,
    String? clientId,
  });

  Future<int?> sendChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required String message,
    List<int> uploadIds = const [],
    int? threadId,
    String? stagedId,
    DateTime? clientCreatedAt,
    int? contextTopicId,
    List<int> contextPostIds = const [],
    String? clientId,
  });

  Future<void> editChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required String message,
    List<int> uploadIds = const [],
    String? clientId,
  });

  Future<void> deleteChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  });

  Future<void> deleteChatMessages({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required List<int> messageIds,
    String? clientId,
  });

  Future<ChatMessageMove> moveChatMessages({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int destinationChannelId,
    required List<int> messageIds,
    String? clientId,
  });

  Future<void> restoreChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  });

  Future<void> rebakeChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  });

  Future<String> generateChatQuote({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required List<int> messageIds,
    String? clientId,
  });

  Future<void> updateChatMessagePinned({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required bool pinned,
    String? clientId,
  });

  Future<ChatPins> chatPinnedMessages({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  });

  Future<void> markChatPinsRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  });

  Future<void> flagChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required int flagTypeId,
    String? message,
    String? clientId,
  });

  Future<void> setChatMessageReaction({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required String emoji,
    required ChatReactionAction action,
    String? clientId,
  });

  Future<ChatMessageReactors> chatMessageReactors({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? reaction,
    int limit = ChatMessageReactors.maximumPageSize,
    String? clientId,
  });

  Future<void> markChatThreadRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required int messageId,
    String? clientId,
  });
}
