import 'package:flutter/foundation.dart';

import '../../data/store.dart';
import '../../models/bookmark.dart';
import '../../models/composer_upload.dart';
import '../../models/json.dart';
import '../../models/user_status.dart';
import 'chat_bookmark.dart';
import 'chat_preview.dart';

/// Preview metadata is trusted only when supplied by an app-owned picker.
@immutable
final class OutgoingChatMessage {
  const OutgoingChatMessage._(this.raw, this.trustedPreviewSeed, this.uploads);

  factory OutgoingChatMessage.text(
    String raw, {
    List<ComposerUploadResult> uploads = const [],
  }) => OutgoingChatMessage._(raw, null, List.unmodifiable(uploads));

  factory OutgoingChatMessage.trustedGif({
    required String raw,
    required String url,
    required String title,
    required int width,
    required int height,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.hasFragment ||
        title.trim().isEmpty ||
        width <= 0 ||
        height <= 0 ||
        width > 10000 ||
        height > 10000) {
      throw ArgumentError('Invalid trusted GIF preview metadata.');
    }
    return OutgoingChatMessage._(
      raw,
      TrustedGifPreviewSeed(
        url: uri,
        title: title,
        width: width,
        height: height,
      ),
      const [],
    );
  }

  final String raw;
  final TrustedPreviewSeed? trustedPreviewSeed;
  final List<ComposerUploadResult> uploads;
}

enum ChatSendResult { sent, failed, cancelled }

@immutable
final class ChatSendHandle {
  const ChatSendHandle.internal({
    required this.localId,
    required this.stagedId,
    required this.settled,
  });

  final int localId;
  final String stagedId;
  final Future<ChatSendResult> settled;
}

@immutable
class ChatMessageAuthor {
  const ChatMessageAuthor({
    required this.id,
    required this.username,
    this.name,
    this.avatarUrl,
    this.status,
    this.isStaff = false,
  });

  factory ChatMessageAuthor.fromJson(Object? value, String siteUrl) {
    if (value is! Map<String, dynamic>) {
      return const ChatMessageAuthor(id: 0, username: '');
    }
    return ChatMessageAuthor(
      id: jsonInt(value['id']),
      username: jsonString(value['username']),
      name: jsonText(value['name']),
      avatarUrl: resolveAvatarUrl(jsonText(value['avatar_template']), siteUrl),
      status: UserStatus.fromJson(value['status']),
      // Discourse serializes `staff` alongside the two constituent roles.
      isStaff:
          value['admin'] == true ||
          value['moderator'] == true ||
          value['staff'] == true,
    );
  }

  final int id;
  final String username;
  final String? name;
  final String? avatarUrl;
  final UserStatus? status;
  final bool isStaff;

  String get displayName => name ?? username;

  @override
  bool operator ==(Object other) =>
      other is ChatMessageAuthor &&
      other.id == id &&
      other.username == username &&
      other.name == name &&
      other.avatarUrl == avatarUrl &&
      other.status == status &&
      other.isStaff == isStaff;

  @override
  int get hashCode =>
      Object.hash(id, username, name, avatarUrl, status, isStaff);
}

/// [reactorIds] is a truncated deduplication aid; [count] is authoritative.
@immutable
class ChatReaction {
  const ChatReaction({
    required this.emoji,
    required this.count,
    this.reacted = false,
    this.reactorIds = const [],
  });

  factory ChatReaction.fromJson(Map<String, dynamic> json) => ChatReaction(
    emoji: jsonString(json['emoji']),
    count: jsonInt(json['count']),
    reacted: json['reacted'] == true,
    reactorIds: List.unmodifiable([
      for (final user in jsonObjects(json['users']).take(maximumReactorsNamed))
        if (jsonIntOrNull(user['id']) case final id? when id > 0) id,
    ]),
  );

  /// Bounds live-event growth beyond the five users serialized by Discourse.
  static const int maximumReactorsNamed = 50;

  final String emoji;
  final int count;

  final bool reacted;

  /// Known subset of reactors, newest last.
  final List<int> reactorIds;

  /// False when Discourse omitted reactor identities.
  bool get namesEveryReactor => reactorIds.length >= count;

  bool hasReactor(int userId) => reactorIds.contains(userId);

  /// A null user ID preserves truncation semantics.
  List<int> reactorIdsWith(int? userId, {required bool reacted}) {
    if (userId == null) return reactorIds;
    if (!reacted) {
      return List.unmodifiable([
        for (final id in reactorIds)
          if (id != userId) id,
      ]);
    }
    if (hasReactor(userId) || reactorIds.length >= maximumReactorsNamed) {
      return reactorIds;
    }
    return List.unmodifiable([...reactorIds, userId]);
  }

  ChatReaction withReacted(bool value, {int? userId}) {
    final nextCount = value == reacted ? count : count + (value ? 1 : -1);
    return ChatReaction(
      emoji: emoji,
      count: nextCount < 0 ? 0 : nextCount,
      reacted: value,
      reactorIds: reactorIdsWith(userId, reacted: value),
    );
  }

  /// Restores reader-specific state omitted by anonymous MessageBus payloads.
  ChatReaction withPersonalizationOf(
    ChatReaction held, {
    required int? userId,
  }) {
    if (!held.reacted) return this;
    return ChatReaction(
      emoji: emoji,
      count: count,
      reacted: true,
      reactorIds: reactorIdsWith(userId, reacted: true),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatReaction &&
      other.emoji == emoji &&
      other.count == count &&
      other.reacted == reacted &&
      listEquals(other.reactorIds, reactorIds);

  @override
  int get hashCode =>
      Object.hash(emoji, count, reacted, Object.hashAll(reactorIds));
}

/// Discourse's UploadSerializer leaves media classification to the client.
enum ChatUploadKind {
  image,
  video,
  audio,
  attachment;

  static const Set<String> _images = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'tif',
    'tiff',
    'svg',
    'heic',
    'heif',
    'avif',
  };
  static const Set<String> _videos = {
    'mov',
    'mp4',
    'webm',
    'ogv',
    'm4v',
    '3gp',
    'avi',
    'mpeg',
  };
  static const Set<String> _audios = {
    'mp3',
    'ogg',
    'oga',
    'opus',
    'wav',
    'm4a',
    'm4b',
    'aac',
    'flac',
  };

  static ChatUploadKind read(String? extension, String filename) {
    final ext = (extension ?? _extensionOf(filename)).toLowerCase();
    if (_images.contains(ext)) return ChatUploadKind.image;
    if (_videos.contains(ext)) return ChatUploadKind.video;
    if (_audios.contains(ext)) return ChatUploadKind.audio;
    return ChatUploadKind.attachment;
  }

  static String _extensionOf(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot < 0 ? '' : filename.substring(dot + 1);
  }
}

/// Chat attachments arrive outside `cooked` and must be rendered separately.
@immutable
class ChatUpload {
  const ChatUpload({
    this.id = 0,
    required this.url,
    required this.originalFilename,
    required this.kind,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.humanFilesize,
    this.dominantColor,
  });

  factory ChatUpload.fromJson(Map<String, dynamic> json) {
    final filename = jsonString(json['original_filename']);
    return ChatUpload(
      id: jsonInt(json['id']),
      url: jsonString(json['url']),
      originalFilename: filename,
      kind: ChatUploadKind.read(jsonText(json['extension']), filename),
      thumbnailUrl: jsonText(jsonObject(json['thumbnail'])['url']),
      width: jsonIntOrNull(json['width']),
      height: jsonIntOrNull(json['height']),
      humanFilesize: jsonText(json['human_filesize']),
      dominantColor: jsonText(json['dominant_color']),
    );
  }

  factory ChatUpload.fromComposerUpload(ComposerUploadResult upload) =>
      ChatUpload(
        id: upload.id,
        url: upload.url,
        originalFilename: upload.originalFilename,
        kind: ChatUploadKind.read(null, upload.originalFilename),
        thumbnailUrl: upload.thumbnailUrl,
        width: upload.thumbnailWidth ?? upload.width,
        height: upload.thumbnailHeight ?? upload.height,
      );

  /// Needed when an edit retains this attachment in `upload_ids`.
  final int id;
  final String url;
  final String originalFilename;
  final ChatUploadKind kind;

  final String? thumbnailUrl;

  final int? width;
  final int? height;
  final String? humanFilesize;
  final String? dominantColor;

  double? get aspectRatio {
    final (w, h) = (width, height);
    if (w == null || h == null || h <= 0 || w <= 0) return null;
    final ratio = w / h;
    if (!ratio.isFinite || ratio <= 0) return null;
    // Remote dimensions are layout hints. Keep one corrupt attachment from
    // reserving an effectively unbounded/tiny extent in the chat list.
    return ratio.clamp(1 / 4, 4).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      other is ChatUpload &&
      other.id == id &&
      other.url == url &&
      other.originalFilename == originalFilename &&
      other.kind == kind &&
      other.thumbnailUrl == thumbnailUrl &&
      other.width == width &&
      other.height == height &&
      other.humanFilesize == humanFilesize &&
      other.dominantColor == dominantColor;

  @override
  int get hashCode => Object.hash(
    url,
    id,
    originalFilename,
    kind,
    thumbnailUrl,
    width,
    height,
    humanFilesize,
    dominantColor,
  );
}

/// `Chat::InReplyToSerializer` carries cooked content and an excerpt, not raw
/// Markdown.
@immutable
class ChatReplyTo {
  const ChatReplyTo({
    required this.id,
    required this.userId,
    required this.excerpt,
    required this.username,
    this.avatarUrl,
  });

  factory ChatReplyTo.fromJson(Map<String, dynamic> json, String siteUrl) {
    final user = jsonObject(json['user']);
    return ChatReplyTo(
      id: jsonInt(json['id']),
      userId: jsonInt(user['id']),
      excerpt: jsonHtmlText(json['excerpt']) ?? '',
      username: jsonString(user['username']),
      avatarUrl: resolveAvatarUrl(jsonText(user['avatar_template']), siteUrl),
    );
  }

  final int id;
  final int userId;
  final String excerpt;
  final String username;
  final String? avatarUrl;

  @override
  bool operator ==(Object other) =>
      other is ChatReplyTo &&
      other.id == id &&
      other.userId == userId &&
      other.excerpt == excerpt &&
      other.username == username &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(id, userId, excerpt, username, avatarUrl);
}

/// Discourse includes this only on a thread's original message; replies are
/// absent from the channel stream.
@immutable
class ChatThreadPreview {
  const ChatThreadPreview({
    required this.threadId,
    required this.replyCount,
    this.title,
    this.lastReplyAt,
    this.lastReplyExcerpt,
    this.lastReplyId,
    this.lastReplyUser,
    this.participantCount,
    this.participantUsers = const [],
    this.lastReplyUsername,
    this.lastReplyAvatarUrl,
  });

  /// A thread remains valid without its optional preview block.
  static ChatThreadPreview? fromJson(Object? value, String url) {
    if (value is! Map<String, dynamic>) return null;
    final preview = jsonObject(value['preview']);
    final user = jsonObject(preview['last_reply_user']);
    final participants = List<ChatMessageAuthor>.unmodifiable([
      for (final participant in jsonObjects(preview['participant_users']))
        ChatMessageAuthor.fromJson(participant, url),
    ]);
    final lastReplyUser = user.isEmpty
        ? null
        : ChatMessageAuthor.fromJson(user, url);
    return ChatThreadPreview(
      threadId: jsonInt(value['id']),
      replyCount: jsonInt(value['reply_count']),
      title: jsonText(value['title']),
      lastReplyAt: jsonDate(preview['last_reply_created_at']),
      lastReplyExcerpt: jsonHtmlText(preview['last_reply_excerpt']),
      lastReplyId: jsonIntOrNull(preview['last_reply_id']),
      lastReplyUser: lastReplyUser,
      participantCount:
          jsonIntOrNull(preview['participant_count']) ?? participants.length,
      participantUsers: participants,
      lastReplyUsername: jsonText(user['username']),
      lastReplyAvatarUrl: resolveAvatarUrl(
        jsonText(user['avatar_template']),
        url,
      ),
    );
  }

  final int threadId;
  final int replyCount;
  final String? title;
  final DateTime? lastReplyAt;
  final String? lastReplyExcerpt;
  final int? lastReplyId;

  final ChatMessageAuthor? lastReplyUser;

  /// Total distinct participants, which can exceed [participantUsers] because
  /// the server deliberately serializes only a small representative set.
  final int? participantCount;
  final List<ChatMessageAuthor> participantUsers;

  final String? lastReplyUsername;
  final String? lastReplyAvatarUrl;

  @override
  bool operator ==(Object other) =>
      other is ChatThreadPreview &&
      other.threadId == threadId &&
      other.replyCount == replyCount &&
      other.title == title &&
      other.lastReplyAt == lastReplyAt &&
      other.lastReplyExcerpt == lastReplyExcerpt &&
      other.lastReplyId == lastReplyId &&
      other.lastReplyUser == lastReplyUser &&
      other.participantCount == participantCount &&
      listEquals(other.participantUsers, participantUsers) &&
      other.lastReplyUsername == lastReplyUsername &&
      other.lastReplyAvatarUrl == lastReplyAvatarUrl;

  @override
  int get hashCode => Object.hash(
    threadId,
    replyCount,
    title,
    lastReplyAt,
    lastReplyExcerpt,
    lastReplyId,
    lastReplyUser,
    participantCount,
    Object.hashAll(participantUsers),
    lastReplyUsername,
    lastReplyAvatarUrl,
  );
}

/// Discourse only returns the pagination flag relevant to the requested
/// direction; the other is serialized as nil.
typedef ChatMessagePage = ({
  List<ChatMessage> messages,
  bool canLoadMorePast,
  bool canLoadMoreFuture,
  int? targetMessageId,
});

/// Chooses which edge survives a nonconforming oversized response.
enum ChatMessagePageWindow { retainNewest, retainOldest, aroundTarget }

enum ChatMessageDelivery { sending, sent, failed }

@immutable
class ChatMessage with Storable<ChatMessage> {
  const ChatMessage({
    required this.id,
    required this.channelId,
    required this.cooked,
    required this.author,
    this.mentionedUserStatuses = const {},
    this.raw = '',
    this.createdAt,
    this.deletedAt,
    this.deletedById,
    this.pinned = false,
    this.availableFlags = const [],
    this.userFlagStatus,
    this.reviewableId,
    this.edited = false,
    this.isWebhook = false,
    this.replyTo,
    this.threadId,
    this.thread,
    this.bookmark,
    this.reactions = const [],
    this.uploads = const [],
    this.optimisticRaw,
    this.preview,
    this.stagedId,
    this.serverId,
    this.canonicalReceived = true,
    this.delivery = ChatMessageDelivery.sent,
    this.sendError,
    this.deliveryUncertain = false,
  });

  /// Bounds eager reaction widgets for malformed responses.
  static const int maximumReactionsPerMessage = 50;

  /// Matches the upload-concurrency ceiling and bounds eager attachment widgets.
  static const int maximumUploadsPerMessage = 30;

  /// Bounds model construction before parsing a malformed response.
  static const int maximumPageSize = 50;

  /// Native preview and edit ceiling; core's default maximum is 20,000.
  static const int maximumEditLength = 20000;

  /// Keeps a negative local row ID separate from Discourse's echoed staged ID.
  factory ChatMessage.optimistic({
    required int id,
    required int channelId,
    required String raw,
    required String stagedId,
    required ChatPreviewResult preview,
    required ChatMessageAuthor author,
    required DateTime createdAt,
    int? threadId,
    List<ChatUpload> uploads = const [],
  }) {
    assert(id < 0);
    return ChatMessage(
      id: id,
      channelId: channelId,
      cooked: '',
      author: author,
      raw: raw,
      createdAt: createdAt,
      threadId: threadId,
      optimisticRaw: raw,
      preview: preview,
      uploads: List.unmodifiable(uploads),
      stagedId: stagedId,
      canonicalReceived: false,
      delivery: ChatMessageDelivery.sending,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json, String siteUrl) {
    final replyTo = switch (json['in_reply_to']) {
      final Map<String, dynamic> reply => reply,
      _ => null,
    };
    return ChatMessage(
      id: jsonInt(json['id']),
      channelId: jsonInt(json['chat_channel_id']),
      cooked: jsonString(json['cooked']),
      author: ChatMessageAuthor.fromJson(json['user'], siteUrl),
      mentionedUserStatuses: userStatusesByUsername(json['mentioned_users']),
      raw: jsonString(json['message']),
      createdAt: jsonDate(json['created_at']),
      deletedAt: jsonDate(json['deleted_at']),
      deletedById: jsonIntOrNull(json['deleted_by_id']),
      pinned: json['pinned'] == true,
      availableFlags: List.unmodifiable([
        for (final value in jsonArray(json['available_flags']).take(20))
          ?jsonText(value),
      ]),
      userFlagStatus: jsonIntOrNull(json['user_flag_status']),
      reviewableId: jsonIntOrNull(json['reviewable_id']),
      edited: json['edited'] == true,
      isWebhook: json['chat_webhook_event'] != null,
      replyTo: replyTo == null ? null : ChatReplyTo.fromJson(replyTo, siteUrl),
      threadId: jsonIntOrNull(json['thread_id']),
      thread: ChatThreadPreview.fromJson(json['thread'], siteUrl),
      bookmark: chatMessageBookmarkFromJson(json),
      reactions: List.unmodifiable([
        for (final entry in jsonObjects(
          json['reactions'],
        ).take(maximumReactionsPerMessage))
          ChatReaction.fromJson(entry),
      ]),
      uploads: List.unmodifiable([
        for (final entry in jsonObjects(
          json['uploads'],
        ).take(maximumUploadsPerMessage))
          ChatUpload.fromJson(entry),
      ]),
    );
  }

  static ChatMessagePage parsePage(
    Map<String, dynamic> json,
    String siteUrl, {
    ChatMessagePageWindow window = ChatMessagePageWindow.retainNewest,
    int maximumMessages = maximumPageSize,
  }) {
    if (maximumMessages < 1 || maximumMessages > maximumPageSize) {
      throw RangeError.range(
        maximumMessages,
        1,
        maximumPageSize,
        'maximumMessages',
      );
    }
    final meta = jsonObject(json['meta']);
    final bounded = _boundedPageEntries(
      json['messages'],
      window: window,
      maximumMessages: maximumMessages,
      targetMessageId: jsonIntOrNull(meta['target_message_id']),
    );
    return (
      messages: List.unmodifiable([
        for (final entry in bounded.entries)
          ChatMessage.fromJson(entry, siteUrl),
      ]),
      canLoadMorePast:
          bounded.omittedPast || meta['can_load_more_past'] == true,
      canLoadMoreFuture:
          bounded.omittedFuture || meta['can_load_more_future'] == true,
      targetMessageId: jsonIntOrNull(meta['target_message_id']),
    );
  }

  static ({
    Iterable<Map<String, dynamic>> entries,
    bool omittedPast,
    bool omittedFuture,
  })
  _boundedPageEntries(
    Object? value, {
    required ChatMessagePageWindow window,
    required int maximumMessages,
    required int? targetMessageId,
  }) {
    if (value is! List) {
      return (
        entries: const <Map<String, dynamic>>[],
        omittedPast: false,
        omittedFuture: false,
      );
    }

    final length = value.length;
    if (length <= maximumMessages) {
      return (
        entries: value.whereType<Map<String, dynamic>>(),
        omittedPast: false,
        omittedFuture: false,
      );
    }

    final latestStart = length - maximumMessages;
    var start = switch (window) {
      ChatMessagePageWindow.retainOldest => 0,
      ChatMessagePageWindow.retainNewest => latestStart,
      ChatMessagePageWindow.aroundTarget => latestStart,
    };
    if (window == ChatMessagePageWindow.aroundTarget &&
        targetMessageId != null) {
      final targetIndex = value.indexWhere(
        (entry) =>
            entry is Map<String, dynamic> &&
            jsonIntOrNull(entry['id']) == targetMessageId,
      );
      if (targetIndex >= 0) {
        start = targetIndex - maximumMessages ~/ 2;
        if (start < 0) start = 0;
        if (start > latestStart) start = latestStart;
      }
    }
    final end = start + maximumMessages;
    return (
      entries: value.getRange(start, end).whereType<Map<String, dynamic>>(),
      omittedPast: start > 0,
      omittedFuture: end < length,
    );
  }

  final int id;
  final int channelId;
  final String cooked;
  final ChatMessageAuthor author;
  final Map<String, UserStatusReference> mentionedUserStatuses;
  final String raw;
  final DateTime? createdAt;

  final DateTime? deletedAt;
  final int? deletedById;
  final bool pinned;
  final List<String> availableFlags;
  final int? userFlagStatus;
  final int? reviewableId;

  final bool edited;

  /// Webhook messages never collapse into author message runs.
  final bool isWebhook;

  /// Replies break grouping unless they answer the immediately preceding row.
  final ChatReplyTo? replyTo;

  final int? threadId;

  final ChatThreadPreview? thread;

  final Bookmark? bookmark;
  final List<ChatReaction> reactions;
  final List<ChatUpload> uploads;

  /// Raw Markdown shown until canonical cooked HTML arrives.
  final String? optimisticRaw;

  /// App-owned, non-authoritative provisional presentation.
  final ChatPreviewResult? preview;

  /// Correlation token echoed through MessageBus.
  final String? stagedId;

  /// Canonical ID retained while the overlay keeps its negative row ID.
  final int? serverId;

  /// Independent of [cooked], because an empty canonical body is authoritative.
  final bool canonicalReceived;

  final ChatMessageDelivery delivery;
  final String? sendError;

  /// Informational only: Discourse does not make `staged_id` idempotent.
  final bool deliveryUncertain;

  bool get isDeleted => deletedAt != null;
  bool get isOptimistic => stagedId != null;

  /// Projects the write because Discourse returns no updated message; naming
  /// the current user preserves complete-versus-truncated reactor semantics.
  ChatMessage withReaction(String emoji, {required bool reacted, int? userId}) {
    final index = reactions.indexWhere((reaction) => reaction.emoji == emoji);
    if (index < 0) {
      if (!reacted) return this;
      return _withReactions([
        ...reactions,
        ChatReaction(
          emoji: emoji,
          count: 1,
          reacted: true,
          reactorIds: [?userId],
        ),
      ]);
    }

    final held = reactions[index];
    if (held.reacted == reacted) return this;
    final updated = held.withReacted(reacted, userId: userId);
    final next = [...reactions];
    if (updated.count == 0) {
      next.removeAt(index);
    } else {
      next[index] = updated;
    }
    return _withReactions(next);
  }

  ChatMessage _withReactions(List<ChatReaction> reactions) => ChatMessage(
    id: id,
    channelId: channelId,
    cooked: cooked,
    author: author,
    mentionedUserStatuses: mentionedUserStatuses,
    raw: raw,
    createdAt: createdAt,
    deletedAt: deletedAt,
    deletedById: deletedById,
    pinned: pinned,
    availableFlags: availableFlags,
    userFlagStatus: userFlagStatus,
    reviewableId: reviewableId,
    edited: edited,
    isWebhook: isWebhook,
    replyTo: replyTo,
    threadId: threadId,
    thread: thread,
    bookmark: bookmark,
    reactions: List.unmodifiable(reactions),
    uploads: uploads,
    optimisticRaw: optimisticRaw,
    preview: preview,
    stagedId: stagedId,
    serverId: serverId,
    canonicalReceived: canonicalReceived,
    delivery: delivery,
    sendError: sendError,
    deliveryUncertain: deliveryUncertain,
  );

  ChatMessage withSendState({
    required ChatMessageDelivery delivery,
    int? serverId,
    String? error,
    bool deliveryUncertain = false,
  }) => ChatMessage(
    id: id,
    channelId: channelId,
    cooked: cooked,
    author: author,
    mentionedUserStatuses: mentionedUserStatuses,
    raw: raw,
    createdAt: createdAt,
    deletedAt: deletedAt,
    deletedById: deletedById,
    pinned: pinned,
    availableFlags: availableFlags,
    userFlagStatus: userFlagStatus,
    reviewableId: reviewableId,
    edited: edited,
    isWebhook: isWebhook,
    replyTo: replyTo,
    threadId: threadId,
    thread: thread,
    bookmark: bookmark,
    reactions: reactions,
    uploads: uploads,
    optimisticRaw: optimisticRaw,
    preview: preview,
    stagedId: stagedId,
    serverId: serverId ?? this.serverId,
    canonicalReceived: canonicalReceived,
    delivery: delivery,
    sendError: error,
    deliveryUncertain: deliveryUncertain,
  );

  /// Keeps the local row identity stable until a page retires the overlay.
  ChatMessage withCanonical(ChatMessage canonical) => ChatMessage(
    id: id,
    channelId: canonical.channelId,
    cooked: canonical.cooked,
    author: canonical.author,
    mentionedUserStatuses: canonical.mentionedUserStatuses,
    raw: canonical.raw,
    createdAt: canonical.createdAt,
    deletedAt: canonical.deletedAt,
    deletedById: canonical.deletedById,
    pinned: canonical.pinned,
    availableFlags: canonical.availableFlags,
    userFlagStatus: canonical.userFlagStatus,
    reviewableId: canonical.reviewableId,
    edited: canonical.edited,
    isWebhook: canonical.isWebhook,
    replyTo: canonical.replyTo,
    threadId: canonical.threadId,
    thread: canonical.thread,
    bookmark: canonical.bookmark,
    reactions: canonical.reactions,
    uploads: canonical.uploads,
    optimisticRaw: optimisticRaw,
    preview: preview,
    stagedId: stagedId,
    serverId: canonical.id,
    canonicalReceived: true,
    delivery: ChatMessageDelivery.sent,
  );

  ChatMessage withThreadPreview(ChatThreadPreview? thread) => ChatMessage(
    id: id,
    channelId: channelId,
    cooked: cooked,
    author: author,
    mentionedUserStatuses: mentionedUserStatuses,
    raw: raw,
    createdAt: createdAt,
    deletedAt: deletedAt,
    deletedById: deletedById,
    pinned: pinned,
    availableFlags: availableFlags,
    userFlagStatus: userFlagStatus,
    reviewableId: reviewableId,
    edited: edited,
    isWebhook: isWebhook,
    replyTo: replyTo,
    threadId: threadId,
    thread: thread,
    bookmark: bookmark,
    reactions: reactions,
    uploads: uploads,
    optimisticRaw: optimisticRaw,
    preview: preview,
    stagedId: stagedId,
    serverId: serverId,
    canonicalReceived: canonicalReceived,
    delivery: delivery,
    sendError: sendError,
    deliveryUncertain: deliveryUncertain,
  );

  ChatMessage withReactions(List<ChatReaction> reactions) => ChatMessage(
    id: id,
    channelId: channelId,
    cooked: cooked,
    author: author,
    mentionedUserStatuses: mentionedUserStatuses,
    raw: raw,
    createdAt: createdAt,
    deletedAt: deletedAt,
    deletedById: deletedById,
    pinned: pinned,
    availableFlags: availableFlags,
    userFlagStatus: userFlagStatus,
    reviewableId: reviewableId,
    edited: edited,
    isWebhook: isWebhook,
    replyTo: replyTo,
    threadId: threadId,
    thread: thread,
    bookmark: bookmark,
    reactions: List.unmodifiable(reactions),
    uploads: uploads,
    optimisticRaw: optimisticRaw,
    preview: preview,
    stagedId: stagedId,
    serverId: serverId,
    canonicalReceived: canonicalReceived,
    delivery: delivery,
    sendError: sendError,
    deliveryUncertain: deliveryUncertain,
  );

  ChatMessage withDeletedAt(
    DateTime? deletedAt, {
    int? deletedById,
    bool clearDeletedById = false,
  }) => ChatMessage(
    id: id,
    channelId: channelId,
    cooked: cooked,
    author: author,
    mentionedUserStatuses: mentionedUserStatuses,
    raw: raw,
    createdAt: createdAt,
    deletedAt: deletedAt,
    deletedById: clearDeletedById ? null : deletedById ?? this.deletedById,
    pinned: pinned,
    availableFlags: availableFlags,
    userFlagStatus: userFlagStatus,
    reviewableId: reviewableId,
    edited: edited,
    isWebhook: isWebhook,
    replyTo: replyTo,
    threadId: threadId,
    thread: thread,
    bookmark: bookmark,
    reactions: reactions,
    uploads: uploads,
    optimisticRaw: optimisticRaw,
    preview: preview,
    stagedId: stagedId,
    serverId: serverId,
    canonicalReceived: canonicalReceived,
    delivery: delivery,
    sendError: sendError,
    deliveryUncertain: deliveryUncertain,
  );

  ChatMessage withPendingEdit(
    String raw,
    ChatPreviewResult preview, {
    List<ChatUpload>? uploads,
  }) => ChatMessage(
    id: id,
    channelId: channelId,
    cooked: cooked,
    author: author,
    mentionedUserStatuses: mentionedUserStatuses,
    raw: raw,
    createdAt: createdAt,
    deletedAt: deletedAt,
    deletedById: deletedById,
    pinned: pinned,
    availableFlags: availableFlags,
    userFlagStatus: userFlagStatus,
    reviewableId: reviewableId,
    edited: true,
    isWebhook: isWebhook,
    replyTo: replyTo,
    threadId: threadId,
    thread: thread,
    bookmark: bookmark,
    reactions: reactions,
    uploads: List.unmodifiable(uploads ?? this.uploads),
    optimisticRaw: raw,
    preview: preview,
    stagedId: stagedId,
    serverId: serverId,
    canonicalReceived: false,
    delivery: delivery,
    sendError: sendError,
    deliveryUncertain: deliveryUncertain,
  );

  /// Preserves state that may have changed concurrently with a rejected edit.
  ChatMessage withContentOf(ChatMessage source) => ChatMessage(
    id: id,
    channelId: channelId,
    cooked: source.cooked,
    author: author,
    mentionedUserStatuses: source.mentionedUserStatuses,
    raw: source.raw,
    createdAt: createdAt,
    deletedAt: deletedAt,
    deletedById: deletedById,
    pinned: pinned,
    availableFlags: availableFlags,
    userFlagStatus: userFlagStatus,
    reviewableId: reviewableId,
    edited: source.edited,
    isWebhook: isWebhook,
    replyTo: replyTo,
    threadId: threadId,
    thread: thread,
    bookmark: bookmark,
    reactions: reactions,
    uploads: source.uploads,
    optimisticRaw: source.optimisticRaw,
    preview: source.preview,
    stagedId: stagedId,
    serverId: serverId,
    canonicalReceived: source.canonicalReceived,
    delivery: delivery,
    sendError: sendError,
    deliveryUncertain: deliveryUncertain,
  );

  ChatMessage withBookmark(Bookmark? bookmark) => ChatMessage(
    id: id,
    channelId: channelId,
    cooked: cooked,
    author: author,
    mentionedUserStatuses: mentionedUserStatuses,
    raw: raw,
    createdAt: createdAt,
    deletedAt: deletedAt,
    deletedById: deletedById,
    pinned: pinned,
    availableFlags: availableFlags,
    userFlagStatus: userFlagStatus,
    reviewableId: reviewableId,
    edited: edited,
    isWebhook: isWebhook,
    replyTo: replyTo,
    threadId: threadId,
    thread: thread,
    bookmark: bookmark,
    reactions: reactions,
    uploads: uploads,
    optimisticRaw: optimisticRaw,
    preview: preview,
    stagedId: stagedId,
    serverId: serverId,
    canonicalReceived: canonicalReceived,
    delivery: delivery,
    sendError: sendError,
    deliveryUncertain: deliveryUncertain,
  );

  ChatMessage withBookmarkOf(ChatMessage other) => withBookmark(other.bookmark);

  ChatMessage withPinned(bool pinned) => ChatMessage(
    id: id,
    channelId: channelId,
    cooked: cooked,
    author: author,
    mentionedUserStatuses: mentionedUserStatuses,
    raw: raw,
    createdAt: createdAt,
    deletedAt: deletedAt,
    deletedById: deletedById,
    pinned: pinned,
    availableFlags: availableFlags,
    userFlagStatus: userFlagStatus,
    reviewableId: reviewableId,
    edited: edited,
    isWebhook: isWebhook,
    replyTo: replyTo,
    threadId: threadId,
    thread: thread,
    bookmark: bookmark,
    reactions: reactions,
    uploads: uploads,
    optimisticRaw: optimisticRaw,
    preview: preview,
    stagedId: stagedId,
    serverId: serverId,
    canonicalReceived: canonicalReceived,
    delivery: delivery,
    sendError: sendError,
    deliveryUncertain: deliveryUncertain,
  );

  ChatMessage withUserFlagStatus(int status) => ChatMessage(
    id: id,
    channelId: channelId,
    cooked: cooked,
    author: author,
    mentionedUserStatuses: mentionedUserStatuses,
    raw: raw,
    createdAt: createdAt,
    deletedAt: deletedAt,
    deletedById: deletedById,
    pinned: pinned,
    availableFlags: availableFlags,
    userFlagStatus: status,
    reviewableId: reviewableId,
    edited: edited,
    isWebhook: isWebhook,
    replyTo: replyTo,
    threadId: threadId,
    thread: thread,
    bookmark: bookmark,
    reactions: reactions,
    uploads: uploads,
    optimisticRaw: optimisticRaw,
    preview: preview,
    stagedId: stagedId,
    serverId: serverId,
    canonicalReceived: canonicalReceived,
    delivery: delivery,
    sendError: sendError,
    deliveryUncertain: deliveryUncertain,
  );

  ChatMessage withReviewableId(int reviewableId) => ChatMessage(
    id: id,
    channelId: channelId,
    cooked: cooked,
    author: author,
    mentionedUserStatuses: mentionedUserStatuses,
    raw: raw,
    createdAt: createdAt,
    deletedAt: deletedAt,
    deletedById: deletedById,
    pinned: pinned,
    availableFlags: availableFlags,
    userFlagStatus: userFlagStatus,
    reviewableId: reviewableId,
    edited: edited,
    isWebhook: isWebhook,
    replyTo: replyTo,
    threadId: threadId,
    thread: thread,
    bookmark: bookmark,
    reactions: reactions,
    uploads: uploads,
    optimisticRaw: optimisticRaw,
    preview: preview,
    stagedId: stagedId,
    serverId: serverId,
    canonicalReceived: canonicalReceived,
    delivery: delivery,
    sendError: sendError,
    deliveryUncertain: deliveryUncertain,
  );

  /// Restores state deliberately absent from anonymous live serializers.
  ChatMessage withPersonalizedStateOf(
    ChatMessage held, {
    required int? currentUserId,
  }) {
    final heldReactions = {
      for (final reaction in held.reactions) reaction.emoji: reaction,
    };
    return ChatMessage(
      id: id,
      channelId: channelId,
      cooked: cooked,
      author: author,
      mentionedUserStatuses: mentionedUserStatuses,
      raw: raw,
      createdAt: createdAt,
      deletedAt: deletedAt,
      deletedById: deletedById,
      pinned: pinned,
      availableFlags: held.availableFlags,
      userFlagStatus: held.userFlagStatus,
      reviewableId: held.reviewableId,
      edited: edited,
      isWebhook: isWebhook,
      replyTo: replyTo,
      threadId: threadId,
      thread: thread,
      bookmark: held.bookmark,
      reactions: List.unmodifiable([
        for (final reaction in reactions)
          if (heldReactions[reaction.emoji] case final personalized?)
            reaction.withPersonalizationOf(personalized, userId: currentUserId)
          else
            reaction,
      ]),
      uploads: uploads,
      optimisticRaw: optimisticRaw,
      preview: preview,
      stagedId: stagedId,
      serverId: serverId,
      canonicalReceived: canonicalReceived,
      delivery: delivery,
      sendError: sendError,
      deliveryUncertain: deliveryUncertain,
    );
  }

  /// Avoids waking rows for unchanged records in overlapping pages.
  @override
  ChatMessage merge(ChatMessage incoming) => this == incoming ? this : incoming;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          other.id == id &&
          other.channelId == channelId &&
          other.cooked == cooked &&
          other.author == author &&
          mapEquals(other.mentionedUserStatuses, mentionedUserStatuses) &&
          other.raw == raw &&
          other.createdAt == createdAt &&
          other.deletedAt == deletedAt &&
          other.deletedById == deletedById &&
          other.pinned == pinned &&
          listEquals(other.availableFlags, availableFlags) &&
          other.userFlagStatus == userFlagStatus &&
          other.reviewableId == reviewableId &&
          other.edited == edited &&
          other.isWebhook == isWebhook &&
          other.replyTo == replyTo &&
          other.threadId == threadId &&
          other.thread == thread &&
          other.bookmark == bookmark &&
          listEquals(other.reactions, reactions) &&
          listEquals(other.uploads, uploads) &&
          other.optimisticRaw == optimisticRaw &&
          other.preview == preview &&
          other.stagedId == stagedId &&
          other.serverId == serverId &&
          other.canonicalReceived == canonicalReceived &&
          other.delivery == delivery &&
          other.sendError == sendError &&
          other.deliveryUncertain == deliveryUncertain;

  @override
  int get hashCode => Object.hashAll([
    id,
    channelId,
    cooked,
    author,
    Object.hashAllUnordered(mentionedUserStatuses.entries),
    raw,
    createdAt,
    Object.hash(
      deletedAt,
      deletedById,
      pinned,
      Object.hashAll(availableFlags),
      userFlagStatus,
      reviewableId,
    ),
    edited,
    isWebhook,
    replyTo,
    threadId,
    thread,
    bookmark,
    Object.hashAll(reactions),
    Object.hashAll(uploads),
    optimisticRaw,
    preview,
    stagedId,
    serverId,
    Object.hash(canonicalReceived, delivery, sendError, deliveryUncertain),
  ]);

  @override
  Object get storeId => id;
}
