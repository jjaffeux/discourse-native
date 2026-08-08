import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../../models/json.dart';
import '../../models/post.dart';
import '../../models/sidebar.dart';

/// What a channel is attached to, which is what decides how it is drawn.
///
/// `chatable_type` is an open vocabulary server side — `Site` already exists
/// beside these two and is not a thing this app has a row for — so unknown
/// values land in [other] rather than throwing. A channel nothing knows how to
/// draw is still a channel with a title.
enum ChatChannelKind {
  category,
  directMessage,
  other;

  static ChatChannelKind read(Object? chatableType) => switch (chatableType) {
    'Category' => ChatChannelKind.category,
    'DirectMessage' => ChatChannelKind.directMessage,
    _ => ChatChannelKind.other,
  };
}

/// One account in a direct message channel.
///
/// Thin, like `PostReactor`: this is a name and a face beside a sidebar row,
/// and the card behind either is a separate fetch that only happens on a tap.
@immutable
class ChatUser {
  const ChatUser({
    required this.id,
    required this.username,
    this.name,
    this.avatarUrl,
  });

  factory ChatUser.fromJson(Map<String, dynamic> json, String siteUrl) {
    return ChatUser(
      id: jsonInt(json['id']),
      username: jsonString(json['username']),
      // Absent on a site with `enable_names` off, where the username is the
      // only name anyone has.
      name: jsonText(json['name']),
      avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
    );
  }

  final int id;
  final String username;
  final String? name;
  final String? avatarUrl;

  String get displayName => name ?? username;

  @override
  bool operator ==(Object other) =>
      other is ChatUser &&
      other.id == id &&
      other.username == username &&
      other.name == name &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(id, username, name, avatarUrl);
}

/// This account's standing in one channel.
///
/// Not a record of its own: it has no identity apart from the channel it
/// arrives inside, and it is only ever one reader's view of one channel.
@immutable
class ChatMembership {
  const ChatMembership({
    this.following = false,
    this.muted = false,
    this.lastReadMessageId,
  });

  /// A channel the reader has no membership row for. `/chat/api/me/channels`
  /// only returns followed channels, so this is the shape a payload that has
  /// left the key out takes rather than a state the sidebar ever draws.
  static const ChatMembership none = ChatMembership();

  static ChatMembership fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return none;
    return ChatMembership(
      following: value['following'] == true,
      muted: value['muted'] == true,
      lastReadMessageId: jsonIntOrNull(value['last_read_message_id']),
    );
  }

  final bool following;
  final bool muted;

  /// The newest message the reader has been credited with seeing, or null on a
  /// channel they have never opened.
  ///
  /// Written by `ChatController.markRead` as the reader scrolls, and by the
  /// site's own answer whenever the channel list is fetched again — so on a
  /// channel this app has not had on screen it is where the reader left off on
  /// some other client.
  final int? lastReadMessageId;

  /// This membership with the reader credited up to [messageId].
  ///
  /// Deliberately not guarded here: going backwards is a question about
  /// *whether to write*, which `ChatController.markRead` answers before it
  /// gets this far, and a silent clamp inside a value type would hide a caller
  /// that had it wrong.
  ChatMembership withLastRead(int messageId) => ChatMembership(
    following: following,
    muted: muted,
    lastReadMessageId: messageId,
  );

  @override
  bool operator ==(Object other) =>
      other is ChatMembership &&
      other.following == following &&
      other.muted == muted &&
      other.lastReadMessageId == lastReadMessageId;

  @override
  int get hashCode => Object.hash(following, muted, lastReadMessageId);
}

/// How much of a channel this account has not seen.
///
/// Arrives in a sibling map rather than on the channel — `tracking:
/// {channel_tracking: {...}}` — and is folded onto the record at parse time, so
/// that the sidebar row watches one thing rather than reading two.
@immutable
class ChatTracking {
  const ChatTracking({
    this.unreadCount = 0,
    this.mentionCount = 0,
    this.watchedThreadsUnreadCount = 0,
  });

  /// A channel the report said nothing about, which the server also reads as
  /// three zeroes — `Chat::TrackingStateInfo.new(nil)`.
  static const ChatTracking none = ChatTracking();

  factory ChatTracking.fromJson(Map<String, dynamic> json) => ChatTracking(
    unreadCount: jsonInt(json['unread_count']),
    mentionCount: jsonInt(json['mention_count']),
    watchedThreadsUnreadCount: jsonInt(json['watched_threads_unread_count']),
  );

  final int unreadCount;
  final int mentionCount;
  final int watchedThreadsUnreadCount;

  @override
  bool operator ==(Object other) =>
      other is ChatTracking &&
      other.unreadCount == unreadCount &&
      other.mentionCount == mentionCount &&
      other.watchedThreadsUnreadCount == watchedThreadsUnreadCount;

  @override
  int get hashCode =>
      Object.hash(unreadCount, mentionCount, watchedThreadsUnreadCount);
}

/// The two lists `/chat/api/me/channels` answers with.
///
/// A record rather than a class because it is a pair with no behaviour, the
/// shape `TopicPayload` and the reactor page already use.
typedef ChatChannels = ({List<ChatChannel> public, List<ChatChannel> direct});

/// One chat channel this account follows.
@immutable
class ChatChannel with Storable<ChatChannel> {
  const ChatChannel({
    required this.id,
    required this.title,
    required this.kind,
    this.slug,
    this.emoji,
    this.description,
    this.categoryColor,
    this.readRestricted = false,
    this.isGroup = false,
    this.users = const [],
    this.membership = ChatMembership.none,
    this.tracking = ChatTracking.none,
    this.unreadThreadCount = 0,
    this.threadingEnabled = false,
    this.lastMessageAt,
  });

  /// Reads one channel out of `Chat::ChannelSerializer`.
  ///
  /// [tracking] comes from a sibling map in the same payload rather than from
  /// [json], which is why it is a parameter — see [parse].
  factory ChatChannel.fromJson(
    Map<String, dynamic> json,
    String siteUrl, {
    ChatTracking tracking = ChatTracking.none,
    int unreadThreadCount = 0,
  }) {
    final chatable = jsonObject(json['chatable']);
    final kind = ChatChannelKind.read(json['chatable_type']);

    return ChatChannel(
      id: jsonInt(json['id']),
      // The site's own answer, and never recomputed here. `title` is
      // `name || title(scope.user)` server side, which for a group direct
      // message has already excluded the reader, sorted the rest by the site's
      // own naming rules, and truncated past seven into "and N others".
      // `unicode_title` is that same text with `:tada:` turned into 🎉 — what a
      // Text widget can draw, which is the argument `jsonTitle` already makes
      // for plain over fancy.
      title: jsonText(json['unicode_title']) ?? jsonText(json['title']) ?? '',
      kind: kind,
      slug: jsonText(json['slug']),
      // A bare name, `bug` rather than `:bug:`, and the key is dropped
      // altogether when a channel has none.
      emoji: jsonText(json['emoji']),
      description: jsonText(json['description']),
      categoryColor: kind == ChatChannelKind.category
          ? _hexColor(chatable['color'])
          : null,
      readRestricted: chatable['read_restricted'] == true,
      isGroup: chatable['group'] == true,
      users: kind == ChatChannelKind.directMessage
          ? List.unmodifiable([
              for (final entry in jsonObjects(chatable['users']))
                ChatUser.fromJson(entry, siteUrl),
            ])
          : const [],
      membership: ChatMembership.fromJson(json['current_user_membership']),
      tracking: tracking,
      unreadThreadCount: unreadThreadCount,
      threadingEnabled: json['threading_enabled'] == true,
      lastMessageAt: jsonDate(jsonObject(json['last_message'])['created_at']),
    );
  }

  /// Reads the whole `/chat/api/me/channels` payload, in the order the sidebar
  /// draws it.
  ///
  /// A `parse` rather than a `fromJson` because the payload yields more than one
  /// instance — the house rule `PostReactors.parse` and `TopicDetail.parse` set.
  ///
  /// Sorting happens here, once, rather than per build: the answer cannot change
  /// between fetches in this step, and a comparator run on every frame of a
  /// scroll would be work for a result that cannot have moved.
  static ChatChannels parse(Map<String, dynamic> json, String siteUrl) {
    // `Chat::TrackingStateReport` is a Ruby hash keyed by integer channel id,
    // and JSON object keys are strings — so `9` is looked up as `'9'`. Getting
    // this wrong reads as "nothing is unread" rather than as an error, which is
    // exactly the kind of quiet wrong worth a test.
    final tracking = jsonObject(
      jsonObject(json['tracking'])['channel_tracking'],
    );
    final unreadThreadOverview = jsonObject(json['unread_thread_overview']);

    ChatTracking trackingFor(int id) {
      final entry = tracking['$id'];
      return entry is Map<String, dynamic>
          ? ChatTracking.fromJson(entry)
          : ChatTracking.none;
    }

    List<ChatChannel> read(Object? bucket) => [
      for (final entry in jsonObjects(bucket))
        ChatChannel.fromJson(
          entry,
          siteUrl,
          tracking: trackingFor(jsonInt(entry['id'])),
          unreadThreadCount: jsonObject(
            unreadThreadOverview['${jsonInt(entry['id'])}'],
          ).length,
        ),
    ];

    final public = read(json['public_channels'])
      // By slug rather than by title, which is what Discourse's own sidebar
      // sorts on. The server orders these by `LOWER(name)`, and a channel's
      // name and its slug differ often enough that the two disagree.
      ..sort(
        (a, b) => (a.slug ?? a.title).toLowerCase().compareTo(
          (b.slug ?? b.title).toLowerCase(),
        ),
      );

    // Direct messages keep the order they arrived in, which is already
    // `last_message.created_at DESC NULLS LAST`. The web additionally floats
    // unread conversations to the top; nothing here changes tracking between
    // fetches yet, so that sort could never re-run and would only look as
    // though it worked.
    return (
      public: List.unmodifiable(public),
      direct: List.unmodifiable(read(json['direct_message_channels'])),
    );
  }

  final int id;

  /// What the row says, already computed by the site. See [fromJson].
  final String title;

  final ChatChannelKind kind;
  final String? slug;

  /// The bare emoji name a channel was given, or null. Resolved to artwork
  /// where it is drawn, through `ShellController.emojiUrlFor`, so a site's
  /// custom emoji and its chosen set apply here the way they do inside a post.
  final String? emoji;

  final String? description;

  /// The colour of the category a public channel lives in, which is what tints
  /// its glyph. Null for a direct message, which belongs to no category.
  final Color? categoryColor;

  final bool readRestricted;

  /// Whether a direct channel was opened as a group rather than one to one.
  /// True even when only one other person is in it.
  final bool isGroup;

  /// Who else is in a direct channel. The reader is already excluded server
  /// side whenever there is more than one of them, so this is "the other
  /// people" and not "the members".
  final List<ChatUser> users;

  final ChatMembership membership;
  final ChatTracking tracking;

  /// Threads with unread replies, including ordinary untracked threads.
  /// Mentions and watched threads remain separately counted in [tracking].
  final int unreadThreadCount;

  /// Whether replies in this channel form threads.
  ///
  /// Load-bearing for what the stream contains, not only for how it is drawn:
  /// with threading on, the messages endpoint returns unthreaded messages plus
  /// each thread's *original message only*, and the replies live behind their
  /// own route.
  final bool threadingEnabled;

  final DateTime? lastMessageAt;

  bool get isDirectMessage => kind == ChatChannelKind.directMessage;
  bool get isCategoryChannel => kind == ChatChannelKind.category;

  /// The one face to put on a row, or null where there is not exactly one.
  ///
  /// A conversation with one other person is that person, and Discourse's own
  /// sidebar draws them. Two or more and there is no single face to choose, so
  /// the row falls back to its glyph rather than stacking avatars.
  String? get avatarUrl =>
      isDirectMessage && users.length == 1 ? users.first.avatarUrl : null;

  /// What the sidebar row says about what has not been read.
  ///
  /// A dot rather than a number, which is what Discourse draws here: the count
  /// in a busy channel moves faster than it is worth reading, and "someone
  /// spoke" is the whole message.
  ///
  /// Urgent — red — for anything addressed to the reader. A mention is; so is
  /// every message in a direct channel, by construction. An unread message in a
  /// public channel the reader merely follows is not, and gets the quieter
  /// colour. That is the same distinction `NotificationTotals.badge` already
  /// draws for the rail.
  SidebarBadge get badge {
    // Muting is the reader saying they do not want to be told. Discourse dims
    // the row and keeps the dot; this sidebar has no dimmed state, so the
    // honest rendering of "do not tell me" is to say nothing.
    if (membership.muted) return SidebarBadge.none;

    if (tracking.mentionCount > 0 ||
        tracking.watchedThreadsUnreadCount > 0 ||
        (isDirectMessage && tracking.unreadCount > 0)) {
      return const SidebarBadge.dot(urgent: true);
    }
    if (tracking.unreadCount > 0 || unreadThreadCount > 0) {
      return const SidebarBadge.dot();
    }
    return SidebarBadge.none;
  }

  /// This channel with the reader credited up to [messageId].
  ///
  /// [caughtUp] says the reader has reached the newest message there is, and
  /// is what empties the counts. Only then, which is Discourse's own rule:
  /// what is unread in the middle of a channel is a sum this client cannot
  /// compute — mentions, watched threads and plain messages are counted apart,
  /// and the site counts them from rows this app never fetched. So the counts
  /// go to zero when the answer is certainly zero, and otherwise stand until
  /// the site sends its own.
  ChatChannel withLastRead(int messageId, {required bool caughtUp}) =>
      ChatChannel(
        id: id,
        title: title,
        kind: kind,
        slug: slug,
        emoji: emoji,
        description: description,
        categoryColor: categoryColor,
        readRestricted: readRestricted,
        isGroup: isGroup,
        users: users,
        membership: membership.withLastRead(messageId),
        tracking: caughtUp ? ChatTracking.none : tracking,
        unreadThreadCount: caughtUp ? 0 : unreadThreadCount,
        threadingEnabled: threadingEnabled,
        lastMessageAt: lastMessageAt,
      );

  /// The id a channel's sidebar entry carries, and — because
  /// `ContentRoute.fromDestination` copies it — the id of the route it opens.
  ///
  /// Route ids are already this app's routing vocabulary (`topic-7`, `latest`,
  /// `messages`), so a plugin minting its own is the existing convention rather
  /// than a new one. It is also the whole of how `ChatPlugin.content`
  /// recognises a route as its own, which is why both directions live here
  /// together.
  static String routeId(int channelId) => '$_routePrefix$channelId';

  /// The channel behind a route id, or null for a route chat did not write.
  static int? channelIdIn(String routeId) => routeId.startsWith(_routePrefix)
      ? int.tryParse(routeId.substring(_routePrefix.length))
      : null;

  static const String _routePrefix = 'chat-c-';

  /// Discourse writes category colours as bare hex — `0088CC`, no leading
  /// `#` — because they land in a stylesheet where it is added back.
  static Color? _hexColor(Object? value) {
    final text = jsonText(value);
    if (text == null) return null;
    final digits = text.startsWith('#') ? text.substring(1) : text;
    if (digits.length != 6) return null;
    final parsed = int.tryParse(digits, radix: 16);
    return parsed == null ? null : Color(0xFF000000 | parsed);
  }

  @override
  ChatChannel merge(ChatChannel incoming) => this == incoming ? this : incoming;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatChannel &&
          other.id == id &&
          other.title == title &&
          other.kind == kind &&
          other.slug == slug &&
          other.emoji == emoji &&
          other.description == description &&
          other.categoryColor == categoryColor &&
          other.readRestricted == readRestricted &&
          other.isGroup == isGroup &&
          listEquals(other.users, users) &&
          other.membership == membership &&
          other.tracking == tracking &&
          other.unreadThreadCount == unreadThreadCount &&
          other.threadingEnabled == threadingEnabled &&
          other.lastMessageAt == lastMessageAt;

  @override
  int get hashCode => Object.hashAll([
    id,
    title,
    kind,
    slug,
    emoji,
    description,
    categoryColor,
    readRestricted,
    isGroup,
    Object.hashAll(users),
    membership,
    tracking,
    unreadThreadCount,
    threadingEnabled,
    lastMessageAt,
  ]);

  @override
  Object get storeId => id;
}
