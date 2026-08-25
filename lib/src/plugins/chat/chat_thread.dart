import 'package:flutter/foundation.dart';

import '../../data/store.dart';
import '../../models/json.dart';
import 'chat_channel.dart';
import 'chat_message.dart';

/// One account-level page from `/chat/api/me/threads`.
///
/// Unlike a channel-local thread list, these rows can belong to unrelated
/// conversations. Core therefore embeds each row's channel in the response;
/// keeping those records beside the threads lets navigation open any result
/// without first guessing whether the channel sidebar happened to load it.
@immutable
final class ChatThreadPage {
  const ChatThreadPage({
    this.threads = const [],
    this.channels = const [],
    this.hasMore = false,
  });

  static const int pageSize = 10;

  factory ChatThreadPage.fromJson(Map<String, dynamic> json, String siteUrl) {
    final tracking = jsonObject(json['tracking']);
    final channels = <int, ChatChannel>{};

    ChatTracking trackingFor(int threadId) {
      final entry = tracking['$threadId'];
      return entry is Map<String, dynamic>
          ? ChatTracking.fromJson(entry)
          : ChatTracking.none;
    }

    final threads = <ChatThread>[];
    for (final entry in jsonObjects(json['threads']).take(pageSize)) {
      final thread = ChatThread.fromJson(entry, siteUrl);
      if (thread.id <= 0 || thread.channelId <= 0) continue;
      threads.add(thread.copyWith(tracking: trackingFor(thread.id)));

      final channelJson = entry['channel'];
      if (channelJson is Map<String, dynamic>) {
        final channel = ChatChannel.fromJson(channelJson, siteUrl);
        if (channel.id > 0 && channel.id == thread.channelId) {
          channels[channel.id] = channel;
        }
      }
    }

    return ChatThreadPage(
      threads: List.unmodifiable(threads),
      channels: List.unmodifiable(channels.values),
      hasMore: jsonText(jsonObject(json['meta'])['load_more_url']) != null,
    );
  }

  final List<ChatThread> threads;
  final List<ChatChannel> channels;
  final bool hasMore;
}

/// How closely the current account follows one thread.
enum ChatThreadNotificationLevel {
  muted(0),
  normal(1),
  tracking(2),
  watching(3);

  const ChatThreadNotificationLevel(this.value);

  final int value;

  static ChatThreadNotificationLevel fromJson(Object? value) =>
      switch (jsonIntOrNull(value)) {
        0 => muted,
        2 => tracking,
        3 => watching,
        _ => normal,
      };
}

/// This account's read and notification state for a thread.
@immutable
final class ChatThreadMembership {
  const ChatThreadMembership({
    required this.threadId,
    this.notificationLevel = ChatThreadNotificationLevel.normal,
    this.lastReadMessageId,
    this.threadTitlePromptSeen = false,
  });

  static ChatThreadMembership? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return ChatThreadMembership(
      threadId: jsonInt(value['thread_id']),
      notificationLevel: ChatThreadNotificationLevel.fromJson(
        value['notification_level'],
      ),
      lastReadMessageId: jsonIntOrNull(value['last_read_message_id']),
      threadTitlePromptSeen: value['thread_title_prompt_seen'] == true,
    );
  }

  final int threadId;
  final ChatThreadNotificationLevel notificationLevel;
  final int? lastReadMessageId;
  final bool threadTitlePromptSeen;

  ChatThreadMembership copyWith({
    ChatThreadNotificationLevel? notificationLevel,
    int? lastReadMessageId,
    bool clearLastReadMessageId = false,
    bool? threadTitlePromptSeen,
  }) => ChatThreadMembership(
    threadId: threadId,
    notificationLevel: notificationLevel ?? this.notificationLevel,
    lastReadMessageId: clearLastReadMessageId
        ? null
        : lastReadMessageId ?? this.lastReadMessageId,
    threadTitlePromptSeen: threadTitlePromptSeen ?? this.threadTitlePromptSeen,
  );

  ChatThreadMembership withNotificationLevel(
    ChatThreadNotificationLevel notificationLevel,
  ) => copyWith(notificationLevel: notificationLevel);

  ChatThreadMembership withLastReadMessageId(int messageId) =>
      copyWith(lastReadMessageId: messageId);

  @override
  bool operator ==(Object other) =>
      other is ChatThreadMembership &&
      other.threadId == threadId &&
      other.notificationLevel == notificationLevel &&
      other.lastReadMessageId == lastReadMessageId &&
      other.threadTitlePromptSeen == threadTitlePromptSeen;

  @override
  int get hashCode => Object.hash(
    threadId,
    notificationLevel,
    lastReadMessageId,
    threadTitlePromptSeen,
  );
}

/// The compact original-message representation embedded in a thread detail.
@immutable
final class ChatThreadOriginalMessage {
  const ChatThreadOriginalMessage({
    required this.id,
    required this.channelId,
    required this.author,
    this.message,
    this.cooked,
    this.excerpt,
    this.createdAt,
    this.deletedAt,
  });

  static ChatThreadOriginalMessage? fromJson(Object? value, String siteUrl) {
    if (value is! Map<String, dynamic>) return null;
    return ChatThreadOriginalMessage(
      id: jsonInt(value['id']),
      channelId: jsonInt(value['chat_channel_id']),
      author: ChatMessageAuthor.fromJson(value['user'], siteUrl),
      message: jsonText(value['message']),
      cooked: jsonText(value['cooked']),
      excerpt: jsonText(value['excerpt']),
      createdAt: jsonDate(value['created_at']),
      deletedAt: jsonDate(value['deleted_at']),
    );
  }

  final int id;
  final int channelId;
  final ChatMessageAuthor author;
  final String? message;
  final String? cooked;
  final String? excerpt;
  final DateTime? createdAt;
  final DateTime? deletedAt;

  ChatThreadOriginalMessage copyWith({
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => ChatThreadOriginalMessage(
    id: id,
    channelId: channelId,
    author: author,
    message: message,
    cooked: cooked,
    excerpt: excerpt,
    createdAt: createdAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is ChatThreadOriginalMessage &&
      other.id == id &&
      other.channelId == channelId &&
      other.author == author &&
      other.message == message &&
      other.cooked == cooked &&
      other.excerpt == excerpt &&
      other.createdAt == createdAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(
    id,
    channelId,
    author,
    message,
    cooked,
    excerpt,
    createdAt,
    deletedAt,
  );
}

/// A thread detail returned by Discourse Chat.
@immutable
final class ChatThread with Storable<ChatThread> {
  const ChatThread({
    required this.id,
    required this.channelId,
    required this.status,
    required this.replyCount,
    this.title,
    this.messageBusLastId,
    this.membership,
    this.tracking = ChatTracking.none,
    this.preview,
    this.lastMessageId,
    this.force = false,
    this.originalMessage,
  });

  factory ChatThread.fromJson(Map<String, dynamic> json, String siteUrl) {
    final messageBusLastIds = jsonObject(
      jsonObject(json['meta'])['message_bus_last_ids'],
    );
    return ChatThread(
      id: jsonInt(json['id']),
      channelId: jsonInt(json['channel_id']),
      status: jsonText(json['status']) ?? '',
      replyCount: jsonInt(json['reply_count']),
      title: jsonText(json['title']),
      messageBusLastId: jsonIntOrNull(
        messageBusLastIds['thread_message_bus_last_id'],
      ),
      membership: ChatThreadMembership.fromJson(
        json['current_user_membership'],
      ),
      preview: json['preview'] is Map<String, dynamic>
          ? ChatThreadPreview.fromJson(json, siteUrl)
          : null,
      lastMessageId: jsonIntOrNull(json['last_message_id']),
      force: json['force'] == true,
      originalMessage: ChatThreadOriginalMessage.fromJson(
        json['original_message'],
        siteUrl,
      ),
    );
  }

  final int id;
  final int channelId;
  final String status;
  final int replyCount;
  final String? title;
  final int? messageBusLastId;
  final ChatThreadMembership? membership;
  final ChatTracking tracking;
  final ChatThreadPreview? preview;
  final int? lastMessageId;
  final bool force;
  final ChatThreadOriginalMessage? originalMessage;

  ChatThread copyWith({
    String? title,
    bool clearTitle = false,
    String? status,
    int? replyCount,
    int? messageBusLastId,
    ChatThreadMembership? membership,
    bool clearMembership = false,
    ChatTracking? tracking,
    ChatThreadPreview? preview,
    int? lastMessageId,
    bool clearLastMessageId = false,
    bool? force,
    ChatThreadOriginalMessage? originalMessage,
  }) => ChatThread(
    id: id,
    channelId: channelId,
    status: status ?? this.status,
    replyCount: replyCount ?? this.replyCount,
    title: clearTitle ? null : title ?? this.title,
    messageBusLastId: messageBusLastId ?? this.messageBusLastId,
    membership: clearMembership ? null : membership ?? this.membership,
    tracking: tracking ?? this.tracking,
    preview: preview ?? this.preview,
    lastMessageId: clearLastMessageId
        ? null
        : lastMessageId ?? this.lastMessageId,
    force: force ?? this.force,
    originalMessage: originalMessage ?? this.originalMessage,
  );

  /// Applies a complete thread-detail response.
  ///
  /// Unlike [merge], absence is authoritative here: a removed title stays
  /// removed and a membership revoked on another client becomes null, which
  /// disables read receipts. The local read cursor remains monotonic when the
  /// membership still exists, while incremental tracking survives endpoints
  /// that do not serialize it.
  ChatThread withDetail(ChatThread detail) {
    assert(detail.id == id);
    assert(detail.channelId == channelId);
    final incomingMembership = detail.membership;
    final previousRead = membership?.lastReadMessageId;
    final incomingRead = incomingMembership?.lastReadMessageId;
    final membershipWithMonotonicRead = incomingMembership?.copyWith(
      lastReadMessageId:
          previousRead != null &&
              (incomingRead == null || previousRead > incomingRead)
          ? previousRead
          : incomingRead,
    );
    return ChatThread(
      id: detail.id,
      channelId: detail.channelId,
      status: detail.status,
      replyCount: detail.replyCount,
      title: detail.title,
      messageBusLastId: detail.messageBusLastId,
      membership: membershipWithMonotonicRead,
      tracking: detail.tracking == ChatTracking.none
          ? tracking
          : detail.tracking,
      preview: detail.preview,
      lastMessageId: detail.lastMessageId,
      force: detail.force,
      originalMessage: detail.originalMessage,
    );
  }

  @override
  ChatThread merge(ChatThread incoming) {
    final merged = ChatThread(
      id: incoming.id,
      channelId: incoming.channelId,
      status: incoming.status,
      replyCount: incoming.replyCount,
      title: incoming.title ?? title,
      messageBusLastId: incoming.messageBusLastId ?? messageBusLastId,
      membership: incoming.membership ?? membership,
      tracking: incoming.tracking == ChatTracking.none
          ? tracking
          : incoming.tracking,
      preview: incoming.preview ?? preview,
      lastMessageId: incoming.lastMessageId ?? lastMessageId,
      force: incoming.force,
      originalMessage: incoming.originalMessage ?? originalMessage,
    );
    return merged == this ? this : merged;
  }

  @override
  Object get storeId => id;

  @override
  bool operator ==(Object other) =>
      other is ChatThread &&
      other.id == id &&
      other.channelId == channelId &&
      other.status == status &&
      other.replyCount == replyCount &&
      other.title == title &&
      other.messageBusLastId == messageBusLastId &&
      other.membership == membership &&
      other.tracking == tracking &&
      other.preview == preview &&
      other.lastMessageId == lastMessageId &&
      other.force == force &&
      other.originalMessage == originalMessage;

  @override
  int get hashCode => Object.hash(
    id,
    channelId,
    status,
    replyCount,
    title,
    messageBusLastId,
    membership,
    tracking,
    preview,
    lastMessageId,
    force,
    originalMessage,
  );
}
