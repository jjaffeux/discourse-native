import 'package:flutter/foundation.dart';

import '../../data/store.dart';
import '../../models/json.dart';
import '../../models/post.dart';

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

  factory ChatMessageAuthor.fromJson(
    Map<String, dynamic>? json,
    String siteUrl,
  ) {
    if (json == null) {
      return const ChatMessageAuthor(id: 0, username: '');
    }
    return ChatMessageAuthor(
      id: jsonInt(json['id']),
      username: (json['username'] ?? '') as String,
      name: jsonText(json['name']),
      avatarUrl: resolveAvatarUrl(json['avatar_template'] as String?, siteUrl),
      // `staff` is the union of the other two server side and is serialised
      // beside them, so any of the three is an answer.
      isStaff:
          json['admin'] == true ||
          json['moderator'] == true ||
          json['staff'] == true,
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
    emoji: (json['emoji'] ?? '') as String,
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
    final filename = (json['original_filename'] ?? '') as String;
    return ChatUpload(
      url: (json['url'] ?? '') as String,
      originalFilename: filename,
      kind: ChatUploadKind.read(jsonText(json['extension']), filename),
      thumbnailUrl: jsonText(
        (json['thumbnail'] as Map<String, dynamic>?)?['url'],
      ),
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
    required this.excerpt,
    required this.username,
    this.avatarUrl,
  });

  factory ChatReplyTo.fromJson(Map<String, dynamic> json, String siteUrl) {
    final user = json['user'] as Map<String, dynamic>?;
    return ChatReplyTo(
      id: jsonInt(json['id']),
      excerpt: jsonText(json['excerpt']) ?? '',
      username: (user?['username'] ?? '') as String,
      avatarUrl: resolveAvatarUrl(user?['avatar_template'] as String?, siteUrl),
    );
  }

  final int id;
  final String excerpt;
  final String username;
  final String? avatarUrl;

  @override
  bool operator ==(Object other) =>
      other is ChatReplyTo &&
      other.id == id &&
      other.excerpt == excerpt &&
      other.username == username &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(id, excerpt, username, avatarUrl);
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
  static ChatThreadPreview? fromJson(Map<String, dynamic>? json, String url) {
    if (json == null) return null;
    final preview = json['preview'] as Map<String, dynamic>? ?? const {};
    final user = preview['last_reply_user'] as Map<String, dynamic>?;
    return ChatThreadPreview(
      threadId: jsonInt(json['id']),
      replyCount: jsonInt(json['reply_count']),
      title: jsonText(json['title']),
      lastReplyAt: jsonDate(preview['last_reply_created_at']),
      lastReplyExcerpt: jsonText(preview['last_reply_excerpt']),
      lastReplyUsername: jsonText(user?['username']),
      lastReplyAvatarUrl: resolveAvatarUrl(
        user?['avatar_template'] as String?,
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
/// is more behind it.
///
/// `can_load_more_future` is deliberately absent. This app asks for messages in
/// exactly two shapes — the newest page, and the page before one it holds — and
/// on the first the server answers `false` while on the second it leaves the
/// local unassigned and Ruby serialises `nil`. Reading it would be reading a
/// null and calling it an answer. Nothing here pages forward, so nothing here
/// needs to know.
typedef ChatMessagePage = ({List<ChatMessage> messages, bool canLoadMorePast});

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
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, String siteUrl) {
    final replyTo = json['in_reply_to'] as Map<String, dynamic>?;
    return ChatMessage(
      id: jsonInt(json['id']),
      channelId: jsonInt(json['chat_channel_id']),
      // Server-rendered, and the same bargain a post makes: Discourse does the
      // markdown, the mentions, the oneboxes and the emoji.
      cooked: (json['cooked'] ?? '') as String,
      author: ChatMessageAuthor.fromJson(
        json['user'] as Map<String, dynamic>?,
        siteUrl,
      ),
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
      thread: ChatThreadPreview.fromJson(
        json['thread'] as Map<String, dynamic>?,
        siteUrl,
      ),
      // The key is left out entirely when nobody has reacted, which is most
      // messages — so the empty list is the default rather than something to
      // parse.
      reactions: [
        for (final entry in json['reactions'] as List<dynamic>? ?? const [])
          if (entry is Map<String, dynamic>) ChatReaction.fromJson(entry),
      ],
      uploads: [
        for (final entry in json['uploads'] as List<dynamic>? ?? const [])
          if (entry is Map<String, dynamic>) ChatUpload.fromJson(entry),
      ],
    );
  }

  /// Reads a `Chat::MessagesSerializer` payload.
  ///
  /// `can_load_more_past` is read as `== true` rather than defaulted, which
  /// turns the Ruby-`nil` it arrives as on a direction-paginated response into a
  /// non-event by construction — the shape `Post.canEdit` already uses.
  static ChatMessagePage parsePage(
    Map<String, dynamic> json,
    String siteUrl,
  ) {
    final meta = json['meta'] as Map<String, dynamic>? ?? const {};
    return (
      messages: [
        for (final entry in json['messages'] as List<dynamic>? ?? const [])
          if (entry is Map<String, dynamic>)
            ChatMessage.fromJson(entry, siteUrl),
      ],
      canLoadMorePast: meta['can_load_more_past'] == true,
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

  bool get isDeleted => deletedAt != null;

  @override
  Object get storeId => id;
}
