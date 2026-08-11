import 'package:flutter/foundation.dart'
    show immutable, listEquals, mapEquals, setEquals;
import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../../models/json.dart';
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
    this.starred = false,
    this.lastReadMessageId,
    this.lastViewedAt,
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
      starred: value['starred'] == true,
      lastReadMessageId: jsonIntOrNull(value['last_read_message_id']),
      lastViewedAt: jsonDate(value['last_viewed_at']),
    );
  }

  final bool following;
  final bool muted;

  /// Whether the reader promoted this channel into Discourse's leading
  /// "Starred channels" sidebar section.
  ///
  /// Older sites omit the key, which deliberately reads as false so their
  /// existing channel and direct-message sections are unchanged.
  final bool starred;

  /// The newest message the reader has been credited with seeing, or null on a
  /// channel they have never opened.
  ///
  /// Written by `ChatController.markRead` as the reader scrolls, and by the
  /// site's own answer whenever the channel list is fetched again — so on a
  /// channel this app has not had on screen it is where the reader left off on
  /// some other client.
  final int? lastReadMessageId;

  /// When this channel was last opened, used by core to distinguish newly
  /// active unread threads from older thread state.
  final DateTime? lastViewedAt;

  /// This membership with the reader credited up to [messageId].
  ///
  /// Deliberately not guarded here: going backwards is a question about
  /// *whether to write*, which `ChatController.markRead` answers before it
  /// gets this far, and a silent clamp inside a value type would hide a caller
  /// that had it wrong.
  ChatMembership withLastRead(int messageId) => ChatMembership(
    following: following,
    muted: muted,
    starred: starred,
    lastReadMessageId: messageId,
    lastViewedAt: lastViewedAt,
  );

  /// This membership after the channel pane was in front of the reader.
  ChatMembership withLastViewedAt(DateTime viewedAt) => ChatMembership(
    following: following,
    muted: muted,
    starred: starred,
    lastReadMessageId: lastReadMessageId,
    lastViewedAt: viewedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is ChatMembership &&
      other.following == following &&
      other.muted == muted &&
      other.starred == starred &&
      other.lastReadMessageId == lastReadMessageId &&
      other.lastViewedAt == lastViewedAt;

  @override
  int get hashCode =>
      Object.hash(following, muted, starred, lastReadMessageId, lastViewedAt);
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

/// Who the global chat presence channel says is online.
///
/// Discourse includes this snapshot in `/chat/api/me/channels`, then publishes
/// joins and leaves on `/presence/chat/online`. Keeping the cursor beside the
/// ids lets the live subscription begin exactly where the HTTP answer ended.
@immutable
class ChatPresence {
  const ChatPresence({this.userIds = const {}, this.lastMessageId});

  factory ChatPresence.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const ChatPresence();
    return ChatPresence(
      userIds: Set.unmodifiable([
        for (final user in jsonObjects(value['users']))
          if (jsonIntOrNull(user['id']) case final id? when id > 0) id,
      ]),
      lastMessageId: jsonIntOrNull(value['last_message_id']),
    );
  }

  final Set<int> userIds;
  final int? lastMessageId;

  bool contains(int userId) => userIds.contains(userId);

  /// Applies one `PresenceChannel` message.
  ///
  /// Entering users carry their basic user objects; leaving users carry only
  /// ids. An unfamiliar payload leaves the snapshot alone so a future server
  /// addition cannot make everyone appear offline.
  ChatPresence withMessage(Object? value) {
    if (value is! Map<String, dynamic>) return this;
    final entered = <int>{
      for (final user in jsonObjects(value['entering_users']))
        if (jsonIntOrNull(user['id']) case final id? when id > 0) id,
    };
    final left = <int>{
      for (final id in jsonArray(value['leaving_user_ids']))
        if (jsonIntOrNull(id) case final userId? when userId > 0) userId,
    };
    if (entered.isEmpty && left.isEmpty) return this;

    return ChatPresence(
      userIds: Set.unmodifiable({...userIds, ...entered}..removeAll(left)),
      lastMessageId: lastMessageId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatPresence &&
      setEquals(other.userIds, userIds) &&
      other.lastMessageId == lastMessageId;

  @override
  int get hashCode =>
      Object.hash(Object.hashAllUnordered(userIds), lastMessageId);
}

/// Everything `/chat/api/me/channels` answers with.
///
/// Presence belongs to this snapshot even though it is not a channel: its
/// `last_message_id` is the cursor from which the live presence subscription
/// must start, so parsing it in a later request would open a race.
@immutable
class ChatChannels {
  const ChatChannels({
    this.public = const [],
    this.direct = const [],
    this.presence = const ChatPresence(),
    this.newMessageBusLastIds = const {},
    this.newChannelBusLastId,
    this.userTrackingBusLastId,
  });

  final List<ChatChannel> public;
  final List<ChatChannel> direct;
  final ChatPresence presence;

  /// The `/chat/{id}/new-messages` position captured with each channel.
  ///
  /// These are transport cursors rather than channel state, so they stay on
  /// the HTTP envelope and are retained by [ChatController] only while it owns
  /// the corresponding subscriptions.
  final Map<int, int?> newMessageBusLastIds;

  /// Envelope-level cursors captured by the same channel-list response.
  final int? newChannelBusLastId;
  final int? userTrackingBusLastId;
}

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
    this.unreadThreadOverview = const {},
    this.threadingEnabled = false,
    this.lastMessageId,
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
    Map<int, DateTime> unreadThreadOverview = const {},
  }) {
    final chatable = jsonObject(json['chatable']);
    final kind = ChatChannelKind.read(json['chatable_type']);
    final lastMessage = jsonObject(json['last_message']);

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
      unreadThreadOverview: Map.unmodifiable(unreadThreadOverview),
      threadingEnabled: json['threading_enabled'] == true,
      lastMessageId: jsonIntOrNull(lastMessage['id']),
      lastMessageAt: jsonDate(lastMessage['created_at']),
    );
  }

  /// Reads the whole `/chat/api/me/channels` payload.
  ///
  /// A `parse` rather than a `fromJson` because the payload yields more than one
  /// instance — the house rule `PostReactors.parse` and `TopicDetail.parse` set.
  ///
  /// Public channels are sorted here once because their slug order is static.
  /// Direct messages retain the server's activity order as their snapshot;
  /// `ChatController` refines the unstarred section from live activity and
  /// unread state whenever it is read.
  static ChatChannels parse(Map<String, dynamic> json, String siteUrl) {
    // `Chat::TrackingStateReport` is a Ruby hash keyed by integer channel id,
    // and JSON object keys are strings — so `9` is looked up as `'9'`. Getting
    // this wrong reads as "nothing is unread" rather than as an error, which is
    // exactly the kind of quiet wrong worth a test.
    final tracking = jsonObject(
      jsonObject(json['tracking'])['channel_tracking'],
    );
    final unreadThreadOverview = jsonObject(json['unread_thread_overview']);
    final envelopeLastIds = jsonObject(
      jsonObject(json['meta'])['message_bus_last_ids'],
    );

    ChatTracking trackingFor(int id) {
      final entry = tracking['$id'];
      return entry is Map<String, dynamic>
          ? ChatTracking.fromJson(entry)
          : ChatTracking.none;
    }

    final newMessageBusLastIds = <int, int?>{};

    ChatChannel readChannel(Map<String, dynamic> entry) {
      final id = jsonInt(entry['id']);
      final lastIds = jsonObject(
        jsonObject(entry['meta'])['message_bus_last_ids'],
      );
      newMessageBusLastIds[id] = jsonIntOrNull(lastIds['new_messages']);
      final threadOverview = <int, DateTime>{};
      for (final overviewEntry in jsonObject(
        unreadThreadOverview['$id'],
      ).entries) {
        final threadId = int.tryParse(overviewEntry.key);
        final createdAt = jsonDate(overviewEntry.value);
        if (threadId != null && threadId > 0 && createdAt != null) {
          threadOverview[threadId] = createdAt;
        }
      }
      return ChatChannel.fromJson(
        entry,
        siteUrl,
        tracking: trackingFor(id),
        unreadThreadOverview: threadOverview,
      );
    }

    List<ChatChannel> read(Object? bucket) => [
      for (final entry in jsonObjects(bucket)) readChannel(entry),
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

    // Direct messages keep the snapshot order they arrived in, already
    // `last_message.created_at DESC NULLS LAST`. The controller uses this as a
    // deterministic fallback when two live sidebar comparisons tie.
    return ChatChannels(
      public: List.unmodifiable(public),
      direct: List.unmodifiable(read(json['direct_message_channels'])),
      presence: ChatPresence.fromJson(json['global_presence_channel_state']),
      newMessageBusLastIds: Map.unmodifiable(newMessageBusLastIds),
      newChannelBusLastId: jsonIntOrNull(envelopeLastIds['new_channel']),
      userTrackingBusLastId: jsonIntOrNull(
        envelopeLastIds['user_tracking_state'],
      ),
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

  /// Unread thread ids and their most recent reply time. Core uses both the
  /// membership's last-viewed time and these dates when ordering DMs.
  final Map<int, DateTime> unreadThreadOverview;

  /// Threads with unread replies, including ordinary untracked threads.
  /// Mentions and watched threads remain separately counted in [tracking].
  int get unreadThreadCount => unreadThreadOverview.length;

  int get unreadThreadsCountSinceLastViewed {
    if (!threadingEnabled) return 0;
    final viewedAt = membership.lastViewedAt;
    if (viewedAt == null) return unreadThreadOverview.length;
    return unreadThreadOverview.values
        .where((createdAt) => !createdAt.isBefore(viewedAt))
        .length;
  }

  DateTime? get lastUnreadThreadAt {
    // Core currently sorts the overview newest-first and then takes its final
    // entry, so the oldest outstanding reply is the observed tie-breaker.
    DateTime? oldest;
    for (final createdAt in unreadThreadOverview.values) {
      if (oldest == null || createdAt.isBefore(oldest)) oldest = createdAt;
    }
    return oldest;
  }

  /// Whether replies in this channel form threads.
  ///
  /// Load-bearing for what the stream contains, not only for how it is drawn:
  /// with threading on, the messages endpoint returns unthreaded messages plus
  /// each thread's *original message only*, and the replies live behind their
  /// own route.
  final bool threadingEnabled;

  final int? lastMessageId;
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
    if (tracking.unreadCount > 0 || unreadThreadsCountSinceLastViewed > 0) {
      return const SidebarBadge.dot();
    }
    return SidebarBadge.none;
  }

  /// This channel after its pane was in front of the reader.
  ///
  /// Core keeps the unread-thread overview intact and advances this timestamp;
  /// the overview is also used by the thread list, while the sidebar filters
  /// it through [unreadThreadsCountSinceLastViewed].
  ChatChannel withLastViewedAt(DateTime viewedAt) => ChatChannel(
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
    membership: membership.withLastViewedAt(viewedAt),
    tracking: tracking,
    unreadThreadOverview: unreadThreadOverview,
    threadingEnabled: threadingEnabled,
    lastMessageId: lastMessageId,
    lastMessageAt: lastMessageAt,
  );

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
        tracking: caughtUp
            ? ChatTracking(
                watchedThreadsUnreadCount: tracking.watchedThreadsUnreadCount,
              )
            : tracking,
        // Reading the channel stream does not read its thread streams. Core
        // keeps this overview and advances lastViewedAt; the sidebar filters
        // old entries through unreadThreadsCountSinceLastViewed.
        unreadThreadOverview: unreadThreadOverview,
        threadingEnabled: threadingEnabled,
        lastMessageId: lastMessageId,
        lastMessageAt: lastMessageAt,
      );

  /// Applies the authoritative per-user tracking stream. The channel event is
  /// intentionally eager; this later snapshot corrects counts and reads made
  /// from another client.
  ChatChannel withTrackingState({
    required ChatTracking tracking,
    int? lastReadMessageId,
    Map<int, DateTime>? unreadThreadOverview,
  }) => ChatChannel(
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
    membership: lastReadMessageId == null
        ? membership
        : membership.withLastRead(lastReadMessageId),
    tracking: tracking,
    unreadThreadOverview: unreadThreadOverview ?? this.unreadThreadOverview,
    threadingEnabled: threadingEnabled,
    lastMessageId: lastMessageId,
    lastMessageAt: lastMessageAt,
  );

  /// Applies the activity and immediate unread projection from one live
  /// `/new-messages` event.
  ///
  /// The separate user-tracking stream remains authoritative for exact counts;
  /// this is the same eager increment the web client uses so navigation reacts
  /// in the turn the message arrives.
  ChatChannel withNewMessage(
    int messageId,
    DateTime createdAt, {
    required bool markRead,
    required bool incrementUnread,
    int? threadId,
    bool markThreadUnread = false,
    bool markThreadRead = false,
  }) {
    var nextThreadOverview = unreadThreadOverview;
    if (threadId != null && markThreadRead) {
      if (unreadThreadOverview.containsKey(threadId)) {
        nextThreadOverview = Map.unmodifiable(
          {...unreadThreadOverview}..remove(threadId),
        );
      }
    } else if (threadId != null &&
        markThreadUnread &&
        threadingEnabled &&
        (isDirectMessage || unreadThreadOverview.containsKey(threadId))) {
      // Every participant in a DM receives a membership for every thread.
      // Public channels only expose the memberships already represented in
      // the overview until native has a thread model of its own.
      nextThreadOverview = Map.unmodifiable({
        ...unreadThreadOverview,
        threadId: createdAt,
      });
    }

    return ChatChannel(
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
      membership: markRead ? membership.withLastRead(messageId) : membership,
      tracking: incrementUnread
          ? ChatTracking(
              unreadCount: tracking.unreadCount + 1,
              mentionCount: tracking.mentionCount,
              watchedThreadsUnreadCount: tracking.watchedThreadsUnreadCount,
            )
          : tracking,
      unreadThreadOverview: nextThreadOverview,
      threadingEnabled: threadingEnabled,
      lastMessageId: messageId,
      lastMessageAt: createdAt,
    );
  }

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
          mapEquals(other.unreadThreadOverview, unreadThreadOverview) &&
          other.threadingEnabled == threadingEnabled &&
          other.lastMessageId == lastMessageId &&
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
    Object.hashAllUnordered(
      unreadThreadOverview.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    threadingEnabled,
    lastMessageId,
    lastMessageAt,
  ]);

  @override
  Object get storeId => id;
}
