import 'package:flutter/foundation.dart';

import '../../data/store.dart';
import '../../models/json.dart';

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
  final bool isStaff;

  String get displayName => name ?? username;

  @override
  bool operator ==(Object other) =>
      other is ChatMessageAuthor &&
      other.id == id &&
      other.username == username &&
      other.name == name &&
      other.avatarUrl == avatarUrl &&
      other.isStaff == isStaff;

  @override
  int get hashCode => Object.hash(id, username, name, avatarUrl, isStaff);
}

/// One emoji on a message, and how many gave it.
///
/// The site serialises at most five of the accounts behind each emoji while
/// [count] is the true total, so the two disagree on any popular reaction. Only
/// [count] is read here: the names are for a panel this step does not draw.
@immutable
class ChatReaction {
  const ChatReaction({
    required this.emoji,
    required this.count,
    this.reacted = false,
  });

  factory ChatReaction.fromJson(Map<String, dynamic> json) => ChatReaction(
    emoji: jsonString(json['emoji']),
    count: jsonInt(json['count']),
    reacted: json['reacted'] == true,
  );

  final String emoji;
  final int count;

  /// Whether this reader is one of them.
  final bool reacted;

  @override
  bool operator ==(Object other) =>
      other is ChatReaction &&
      other.emoji == emoji &&
      other.count == count &&
      other.reacted == reacted;

  @override
  int get hashCode => Object.hash(emoji, count, reacted);
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
    return w / h;
  }

  @override
  bool operator ==(Object other) =>
      other is ChatUpload &&
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
      excerpt: jsonText(json['excerpt']) ?? '',
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
    return ChatThreadPreview(
      threadId: jsonInt(value['id']),
      replyCount: jsonInt(value['reply_count']),
      title: jsonText(value['title']),
      lastReplyAt: jsonDate(preview['last_reply_created_at']),
      lastReplyExcerpt: jsonText(preview['last_reply_excerpt']),
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
      other.lastReplyUsername == lastReplyUsername &&
      other.lastReplyAvatarUrl == lastReplyAvatarUrl;

  @override
  int get hashCode => Object.hash(
    threadId,
    replyCount,
    title,
    lastReplyAt,
    lastReplyExcerpt,
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
});

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
    this.createdAt,
    this.deletedAt,
    this.edited = false,
    this.isWebhook = false,
    this.replyTo,
    this.threadId,
    this.thread,
    this.reactions = const [],
    this.uploads = const [],
    this.optimisticRaw,
    this.stagedId,
    this.serverId,
    this.delivery = ChatMessageDelivery.sent,
    this.sendError,
    this.deliveryUncertain = false,
  });

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
    required ChatMessageAuthor author,
    required DateTime createdAt,
  }) {
    assert(id < 0);
    return ChatMessage(
      id: id,
      channelId: channelId,
      cooked: '',
      author: author,
      createdAt: createdAt,
      optimisticRaw: raw,
      stagedId: stagedId,
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
      createdAt: jsonDate(json['created_at']),
      // Only ever sent to someone allowed to see it — for everyone else a
      // trashed message is simply not in the stream.
      deletedAt: jsonDate(json['deleted_at']),
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
      // The key is left out entirely when nobody has reacted, which is most
      // messages — so the empty list is the default rather than something to
      // parse.
      reactions: List.unmodifiable([
        for (final entry in jsonObjects(json['reactions']))
          ChatReaction.fromJson(entry),
      ]),
      uploads: List.unmodifiable([
        for (final entry in jsonObjects(json['uploads']))
          ChatUpload.fromJson(entry),
      ]),
    );
  }

  /// Reads a `Chat::MessagesSerializer` payload. See [ChatMessagePage] for why
  /// both flags are read as `== true` rather than defaulted.
  static ChatMessagePage parsePage(Map<String, dynamic> json, String siteUrl) {
    final meta = jsonObject(json['meta']);
    return (
      messages: List.unmodifiable([
        for (final entry in jsonObjects(json['messages']))
          ChatMessage.fromJson(entry, siteUrl),
      ]),
      canLoadMorePast: meta['can_load_more_past'] == true,
      canLoadMoreFuture: meta['can_load_more_future'] == true,
    );
  }

  final int id;
  final int channelId;
  final String cooked;
  final ChatMessageAuthor author;
  final DateTime? createdAt;

  /// When it was trashed, or null. Present only for a reader who may see it.
  final DateTime? deletedAt;

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

  final List<ChatReaction> reactions;
  final List<ChatUpload> uploads;

  /// Raw markdown shown as plain text until the site echoes canonical cooked
  /// HTML. Present only on a locally staged row.
  final String? optimisticRaw;

  /// The arbitrary correlation token sent as `staged_id` and echoed through
  /// MessageBus. Null on a message read from the site.
  final String? stagedId;

  /// The id returned by a successful POST or its canonical MessageBus echo.
  ///
  /// The record itself intentionally keeps its negative local [id] until a
  /// normal page fetch includes this server id and retires the overlay row.
  final int? serverId;

  final ChatMessageDelivery delivery;
  final String? sendError;

  /// Whether a transport failure may still have committed on the site.
  ///
  /// Discourse does not make `staged_id` an idempotency key, so this state is
  /// deliberately informational rather than an invitation to resend.
  final bool deliveryUncertain;

  bool get isDeleted => deletedAt != null;
  bool get isOptimistic => stagedId != null;

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
    createdAt: createdAt,
    deletedAt: deletedAt,
    edited: edited,
    isWebhook: isWebhook,
    replyTo: replyTo,
    threadId: threadId,
    thread: thread,
    reactions: reactions,
    uploads: uploads,
    optimisticRaw: optimisticRaw,
    stagedId: stagedId,
    serverId: serverId ?? this.serverId,
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
    createdAt: canonical.createdAt,
    deletedAt: canonical.deletedAt,
    edited: canonical.edited,
    isWebhook: canonical.isWebhook,
    replyTo: canonical.replyTo,
    threadId: canonical.threadId,
    thread: canonical.thread,
    reactions: canonical.reactions,
    uploads: canonical.uploads,
    optimisticRaw: optimisticRaw,
    stagedId: stagedId,
    serverId: canonical.id,
    delivery: ChatMessageDelivery.sent,
  );

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
          other.createdAt == createdAt &&
          other.deletedAt == deletedAt &&
          other.edited == edited &&
          other.isWebhook == isWebhook &&
          other.replyTo == replyTo &&
          other.threadId == threadId &&
          other.thread == thread &&
          listEquals(other.reactions, reactions) &&
          listEquals(other.uploads, uploads) &&
          other.optimisticRaw == optimisticRaw &&
          other.stagedId == stagedId &&
          other.serverId == serverId &&
          other.delivery == delivery &&
          other.sendError == sendError &&
          other.deliveryUncertain == deliveryUncertain;

  @override
  int get hashCode => Object.hash(
    id,
    channelId,
    cooked,
    author,
    createdAt,
    deletedAt,
    edited,
    isWebhook,
    replyTo,
    threadId,
    thread,
    Object.hashAll(reactions),
    Object.hashAll(uploads),
    optimisticRaw,
    stagedId,
    serverId,
    delivery,
    sendError,
    deliveryUncertain,
  );

  @override
  Object get storeId => id;
}
