import 'package:flutter/foundation.dart';

import '../../data/store.dart';
import '../../models/bookmark.dart';
import '../../models/composer_upload.dart';
import '../../models/json.dart';
import '../../models/user_status.dart';
import 'chat_preview.dart';

/// One message accepted by the optimistic send boundary.
///
/// The trusted seed is typed metadata from an app-owned picker, never inferred
/// from arbitrary Markdown entered by the reader.
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

/// The terminal result of an accepted optimistic send.
enum ChatSendResult { sent, failed, cancelled }

/// Synchronous proof that a message was staged, with non-throwing settlement.
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

/// Who wrote a message.
///
/// Its own type rather than [ChatUser] because a message's author carries what
/// a channel member does not — the staff flags that decide how the name is
/// drawn — and a channel member carries nothing an author needs.
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
      // `staff` is the union of the other two server side and is serialised
      // beside them, so any of the three is an answer.
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

/// One emoji on a message, and how many gave it.
///
/// The site serialises at most five of the accounts behind each emoji while
/// [count] is the true total, so the two disagree on any popular reaction.
/// [reactorIds] is not what draws the reactor panel — that has an endpoint of
/// its own — it is what lets a live reaction event be recognised as one this
/// row has already counted. See `ChatController._applyReactionEvent`.
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

  /// Maximum accounts retained for one reaction row.
  ///
  /// The site names five and live events append the rest, so this bounds a
  /// long-lived popular reaction rather than a malformed response. Reaching it
  /// costs nothing but [namesEveryReactor], which is already false by then.
  static const int maximumReactorsNamed = 50;

  final String emoji;
  final int count;

  /// Whether this reader is one of them.
  final bool reacted;

  /// The accounts behind [count] this row can name, newest last.
  ///
  /// Truncated by the site, and left behind by any event that moved [count]
  /// without naming an account, so it is a subset rather than the roll.
  final List<int> reactorIds;

  /// Whether [reactorIds] accounts for all of [count].
  ///
  /// Only then does "this row does not name them" mean "they did not react".
  /// While the list is short of [count], somebody unnamed may still be one of
  /// the reactors the site declined to serialise.
  bool get namesEveryReactor => reactorIds.length >= count;

  /// Whether this row already counts [userId] among its reactors.
  bool hasReactor(int userId) => reactorIds.contains(userId);

  /// This row with [userId] added or dropped, bounded by
  /// [maximumReactorsNamed]. A null id leaves the roll alone, which reads as
  /// truncation and so keeps the row on the counting path.
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

/// What kind of thing an upload is, which decides how it is drawn.
///
/// Read from the filename rather than from a field, because there is no field:
/// `UploadSerializer` reports an extension and a size and leaves the
/// classification to the client. Mirrors `discourse/lib/uploads`.
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

/// A file attached to a message.
///
/// **Not in `cooked`.** `Chat::Message#cook` cooks the raw `message` and not
/// `to_markdown`, so unlike a post — where Discourse bakes uploads into the
/// HTML and the lightbox markup comes free — a chat message's attachments
/// arrive only in this array and have to be drawn from it.
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
      // Six hex digits with no `#`, the same shape a category colour arrives
      // in. Shown behind an image while it loads so the row does not flash.
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

  /// A smaller copy for the row to draw, when the site made one. [url] is the
  /// full-size image either way.
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

/// The message a message is answering.
///
/// `Chat::InReplyToSerializer` carries no raw markdown, only the cooked body
/// and an excerpt — which is all a one-line indicator wants anyway.
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

/// What a thread looks like from the message that started it.
///
/// Only ever present on a thread's original message, and only in a channel with
/// threading on — where the replies themselves are not in this stream at all
/// and this summary is the only trace of them.
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

  /// Reads the `thread` block, or null when the message did not start one.
  ///
  /// The block is only serialised on a thread's original message, so its mere
  /// presence is the answer to "did this start a thread"; the `preview` inside
  /// is what it looks like now. A block without one is tolerated rather than
  /// dropped — the count is on the thread itself, and a row that says how many
  /// replies there are without naming the last of them is still worth drawing.
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

  /// The author of the newest reply. The older scalar accessors remain while
  /// existing summary-card callers migrate to this typed representation.
  final ChatMessageAuthor? lastReplyUser;

  /// Total distinct participants, which can exceed [participantUsers] because
  /// the server deliberately serializes only a small representative set.
  final int? participantCount;
  final List<ChatMessageAuthor> participantUsers;

  /// Compatibility scalars used by the existing compact preview tile.
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

/// One page of a channel, always oldest first, and whether the site says there
/// is more on either side of it.
///
/// Both flags are read as `== true` rather than defaulted, because the site
/// only answers the one the request was about: a page asked for by direction
/// leaves the other local unassigned, and Ruby serialises that as `nil`. So a
/// missing flag is "the site did not say", which for a stream that already
/// holds the messages in that direction is the same as "no more" — the shape
/// `Post.canEdit` already uses.
typedef ChatMessagePage = ({
  List<ChatMessage> messages,
  bool canLoadMorePast,
  bool canLoadMoreFuture,
  int? targetMessageId,
});

/// Which edge of an oldest-first chat response is adjacent to the caller's
/// current window.
///
/// This matters only for a nonconforming oversized response. Past/newest
/// requests retain the newest edge, future requests retain the oldest edge,
/// and the last-read request retains a window around the server's target.
enum ChatMessagePageWindow { retainNewest, retainOldest, aroundTarget }

/// Where a locally staged message is in its trip to the site.
///
/// Canonical messages are [sent] too. [ChatMessage.isOptimistic] distinguishes
/// those server records from the temporary rows this state is drawn on.
enum ChatMessageDelivery { sending, sent, failed }

/// One message in a channel.
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

  /// Maximum distinct reaction rows retained for one message.
  ///
  /// The message tile eagerly builds a badge and emoji image for each entry,
  /// so a malformed response must not turn one message into unbounded work.
  static const int maximumReactionsPerMessage = 50;

  /// Maximum attachment rows retained for one message.
  ///
  /// This matches the app's local upload-concurrency ceiling and bounds the
  /// eager attachment column and image gallery built by a visible message.
  static const int maximumUploadsPerMessage = 30;

  /// The absolute page size accepted from either chat message endpoint.
  ///
  /// Discourse caps ordinary pages at 50. Bounding raw slots before model
  /// construction keeps a malformed response from eagerly cooking an
  /// arbitrary number of message trees.
  static const int maximumPageSize = 50;

  /// Native preview and edit ceiling; core's default maximum is 20,000.
  static const int maximumEditLength = 20000;

  /// A row inserted before credentials or the network are awaited.
  ///
  /// Its negative [id] belongs only to the native store. [stagedId] is the
  /// opaque correlation token Discourse echoes on `/chat/{channel}`; the two
  /// deliberately stay separate so canonical positive ids remain a contiguous
  /// paging window.
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
      // Server-rendered, and the same bargain a post makes: Discourse does the
      // markdown, the mentions, the oneboxes and the emoji.
      cooked: jsonString(json['cooked']),
      author: ChatMessageAuthor.fromJson(json['user'], siteUrl),
      mentionedUserStatuses: userStatusesByUsername(json['mentioned_users']),
      // Core keeps the source alongside cooked HTML so an edit starts from
      // Markdown rather than trying to reverse rendered output.
      raw: jsonString(json['message']),
      createdAt: jsonDate(json['created_at']),
      // Only ever sent to someone allowed to see it — for everyone else a
      // trashed message is simply not in the stream.
      deletedAt: jsonDate(json['deleted_at']),
      deletedById: jsonIntOrNull(json['deleted_by_id']),
      pinned: json['pinned'] == true,
      availableFlags: List.unmodifiable([
        for (final value in jsonArray(json['available_flags']).take(20))
          ?jsonText(value),
      ]),
      userFlagStatus: jsonIntOrNull(json['user_flag_status']),
      reviewableId: jsonIntOrNull(json['reviewable_id']),
      // The key is written only when it is true and dropped otherwise, so
      // absence is the answer rather than a missing field. Same shape as
      // `actions_summary`.
      edited: json['edited'] == true,
      isWebhook: json['chat_webhook_event'] != null,
      replyTo: replyTo == null ? null : ChatReplyTo.fromJson(replyTo, siteUrl),
      // Only serialised in a channel with threading on, or for a thread forced
      // into one without it.
      threadId: jsonIntOrNull(json['thread_id']),
      thread: ChatThreadPreview.fromJson(json['thread'], siteUrl),
      bookmark: Bookmark.fromChatMessageJson(json),
      // The key is left out entirely when nobody has reacted, which is most
      // messages — so the empty list is the default rather than something to
      // parse.
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

  /// Reads a `Chat::MessagesSerializer` payload. See [ChatMessagePage] for why
  /// both flags are read as `== true` rather than defaulted.
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

  /// When it was trashed, or null. Present only for a reader who may see it.
  final DateTime? deletedAt;
  final int? deletedById;
  final bool pinned;
  final List<String> availableFlags;
  final int? userFlagStatus;
  final int? reviewableId;

  final bool edited;

  /// Whether an integration posted this rather than a person.
  ///
  /// Load-bearing beyond the badge: a run of webhook messages is not a person
  /// talking, so it never collapses into the message above it.
  final bool isWebhook;

  /// The message this one answers, or null.
  ///
  /// Also load-bearing for grouping: a reply that is not answering the message
  /// directly above it breaks the run, because the two are not consecutive in
  /// the conversation even though they are consecutive in the list.
  final ChatReplyTo? replyTo;

  final int? threadId;

  /// The thread this message started, or null if it started none.
  final ChatThreadPreview? thread;

  final Bookmark? bookmark;
  final List<ChatReaction> reactions;
  final List<ChatUpload> uploads;

  /// Raw markdown shown as plain text until the site echoes canonical cooked
  /// HTML. Present only on a locally staged row.
  final String? optimisticRaw;

  /// App-owned provisional presentation. Never authoritative and never HTML.
  /// Present only while a locally staged row is waiting for canonical cooked
  /// content from the site.
  final ChatPreviewResult? preview;

  /// The arbitrary correlation token sent as `staged_id` and echoed through
  /// MessageBus. Null on a message read from the site.
  final String? stagedId;

  /// The id returned by a successful POST or its canonical MessageBus echo.
  ///
  /// The record itself intentionally keeps its negative local [id] until a
  /// normal page fetch includes this server id and retires the overlay row.
  final int? serverId;

  /// Whether the site has supplied the canonical serialized message.
  ///
  /// This is deliberately independent of [cooked]: an empty canonical body is
  /// still an authoritative answer and must replace the optimistic preview.
  final bool canonicalReceived;

  final ChatMessageDelivery delivery;
  final String? sendError;

  /// Whether a transport failure may still have committed on the site.
  ///
  /// Discourse does not make `staged_id` an idempotency key, so this state is
  /// deliberately informational rather than an invitation to resend.
  final bool deliveryUncertain;

  bool get isDeleted => deletedAt != null;
  bool get isOptimistic => stagedId != null;

  /// Adds or removes this reader from one reaction without disturbing any of
  /// the other reactions a chat message may hold.
  ///
  /// The server answers the write with success rather than an updated message,
  /// so this is both the optimistic projection and the state retained after a
  /// successful request. Applying the same state twice is intentionally a
  /// no-op, which makes rollback and a repeated UI callback harmless.
  ///
  /// [userId] is this reader's account, and naming it keeps
  /// [ChatReaction.reactorIds] whole across the reader's own write — without
  /// it the projection would report a roll one short of [ChatReaction.count]
  /// and read as truncated for every event that followed.
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

  /// Applies the site's canonical echo without changing the local row id.
  ///
  /// Keeping that identity stable is the native equivalent of the web client
  /// mutating its staged object in place. The next page containing [serverId]
  /// removes this overlay, with no duplicate ever entering the stream.
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

  /// Replaces only the thread summary embedded on an original message.
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

  /// Replaces the reaction aggregate after an incremental MessageBus event.
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

  /// Replaces only the server deletion timestamp.
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

  /// Projects an edit while the canonical cooked echo is in flight.
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

  /// Restores only editable presentation state after a rejected write.
  /// Reactions, bookmarks, deletion state and thread previews may have changed
  /// concurrently and therefore remain those of this message.
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

  /// Projects the server's pin state without disturbing a concurrent edit,
  /// reaction, bookmark, deletion, or thread-preview update.
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

  /// Paging windows overlap at their boundary; an unchanged copy should not
  /// wake the row already drawing this record.
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
