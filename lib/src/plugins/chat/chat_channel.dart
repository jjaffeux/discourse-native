import 'package:flutter/foundation.dart'
    show immutable, listEquals, mapEquals, setEquals;
import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../../models/json.dart';
import '../../models/sidebar.dart';
import '../../models/user_status.dart';

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

/// Whether the channel accepts new messages from this account.
enum ChatChannelStatus {
  open,
  readOnly,
  closed,
  archived;

  static ChatChannelStatus read(Object? value) => switch (value) {
    'read_only' => readOnly,
    'closed' => closed,
    'archived' => archived,
    _ => open,
  };
}

/// Server-side status buckets exposed by Discourse's Browse Channels route.
enum ChatChannelBrowseStatus { all, open, closed, archived }

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
    this.status,
  });

  factory ChatUser.fromJson(Map<String, dynamic> json, String siteUrl) {
    return ChatUser(
      id: jsonInt(json['id']),
      username: jsonString(json['username']),
      // Absent on a site with `enable_names` off, where the username is the
      // only name anyone has.
      name: jsonText(json['name']),
      avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
      status: UserStatus.fromJson(json['status']),
    );
  }

  final int id;
  final String username;
  final String? name;
  final String? avatarUrl;
  final UserStatus? status;

  String get displayName => name ?? username;

  @override
  bool operator ==(Object other) =>
      other is ChatUser &&
      other.id == id &&
      other.username == username &&
      other.name == name &&
      other.avatarUrl == avatarUrl &&
      other.status == status;

  @override
  int get hashCode => Object.hash(id, username, name, avatarUrl, status);
}

/// This account's standing in one channel.
///
/// Not a record of its own: it has no identity apart from the channel it
/// arrives inside, and it is only ever one reader's view of one channel.
enum ChatChannelNotificationLevel {
  never,
  mention,
  always;

  static ChatChannelNotificationLevel read(Object? value) => switch (value) {
    'never' || 0 => never,
    'always' || 2 => always,
    _ => mention,
  };
}

@immutable
class ChatMembership {
  const ChatMembership({
    this.following = false,
    this.muted = false,
    this.notificationLevel = ChatChannelNotificationLevel.mention,
    this.starred = false,
    this.lastReadMessageId,
    this.lastViewedAt,
    this.lastViewedPinsAt,
    this.hasUnseenPins = false,
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
      notificationLevel: ChatChannelNotificationLevel.read(
        value['notification_level'],
      ),
      starred: value['starred'] == true,
      lastReadMessageId: jsonIntOrNull(value['last_read_message_id']),
      lastViewedAt: jsonDate(value['last_viewed_at']),
      lastViewedPinsAt: jsonDate(value['last_viewed_pins_at']),
      hasUnseenPins: value['has_unseen_pins'] == true,
    );
  }

  final bool following;
  final bool muted;
  final ChatChannelNotificationLevel notificationLevel;

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
  final DateTime? lastViewedPinsAt;
  final bool hasUnseenPins;

  /// This membership with the reader credited up to [messageId].
  ///
  /// Deliberately not guarded here: going backwards is a question about
  /// *whether to write*, which `ChatController.markRead` answers before it
  /// gets this far, and a silent clamp inside a value type would hide a caller
  /// that had it wrong.
  ChatMembership withLastRead(int messageId) => ChatMembership(
    following: following,
    muted: muted,
    notificationLevel: notificationLevel,
    starred: starred,
    lastReadMessageId: messageId,
    lastViewedAt: lastViewedAt,
    lastViewedPinsAt: lastViewedPinsAt,
    hasUnseenPins: hasUnseenPins,
  );

  /// Adopts the replacement read position published with a delete event.
  /// Null is meaningful when no earlier visible message remains.
  ChatMembership withLastReadAfterDelete(int? messageId) => ChatMembership(
    following: following,
    muted: muted,
    notificationLevel: notificationLevel,
    starred: starred,
    lastReadMessageId: messageId,
    lastViewedAt: lastViewedAt,
    lastViewedPinsAt: lastViewedPinsAt,
    hasUnseenPins: hasUnseenPins,
  );

  /// This membership after the channel pane was in front of the reader.
  ChatMembership withLastViewedAt(DateTime viewedAt) => ChatMembership(
    following: following,
    muted: muted,
    notificationLevel: notificationLevel,
    starred: starred,
    lastReadMessageId: lastReadMessageId,
    lastViewedAt: viewedAt,
    lastViewedPinsAt: lastViewedPinsAt,
    hasUnseenPins: hasUnseenPins,
  );

  ChatMembership withStarred(bool starred) => ChatMembership(
    following: following,
    muted: muted,
    notificationLevel: notificationLevel,
    starred: starred,
    lastReadMessageId: lastReadMessageId,
    lastViewedAt: lastViewedAt,
    lastViewedPinsAt: lastViewedPinsAt,
    hasUnseenPins: hasUnseenPins,
  );

  ChatMembership withPinsViewed(DateTime viewedAt) => ChatMembership(
    following: following,
    muted: muted,
    notificationLevel: notificationLevel,
    starred: starred,
    lastReadMessageId: lastReadMessageId,
    lastViewedAt: lastViewedAt,
    lastViewedPinsAt: viewedAt,
    hasUnseenPins: false,
  );

  ChatMembership withUnseenPins(bool hasUnseenPins) => ChatMembership(
    following: following,
    muted: muted,
    notificationLevel: notificationLevel,
    starred: starred,
    lastReadMessageId: lastReadMessageId,
    lastViewedAt: lastViewedAt,
    lastViewedPinsAt: lastViewedPinsAt,
    hasUnseenPins: hasUnseenPins,
  );

  ChatMembership withNotifications({
    bool? muted,
    ChatChannelNotificationLevel? notificationLevel,
  }) => ChatMembership(
    following: following,
    muted: muted ?? this.muted,
    notificationLevel: notificationLevel ?? this.notificationLevel,
    starred: starred,
    lastReadMessageId: lastReadMessageId,
    lastViewedAt: lastViewedAt,
    lastViewedPinsAt: lastViewedPinsAt,
    hasUnseenPins: hasUnseenPins,
  );

  @override
  bool operator ==(Object other) =>
      other is ChatMembership &&
      other.following == following &&
      other.muted == muted &&
      other.notificationLevel == notificationLevel &&
      other.starred == starred &&
      other.lastReadMessageId == lastReadMessageId &&
      other.lastViewedAt == lastViewedAt &&
      other.lastViewedPinsAt == lastViewedPinsAt &&
      other.hasUnseenPins == hasUnseenPins;

  @override
  int get hashCode => Object.hash(
    following,
    muted,
    notificationLevel,
    starred,
    lastReadMessageId,
    lastViewedAt,
    lastViewedPinsAt,
    hasUnseenPins,
  );
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
  ChatPresence withMessage(Object? value, {int? lastMessageId}) {
    if (value is! Map<String, dynamic>) {
      return lastMessageId == null
          ? this
          : ChatPresence(userIds: userIds, lastMessageId: lastMessageId);
    }
    final entered = <int>{
      for (final user in jsonObjects(value['entering_users']))
        if (jsonIntOrNull(user['id']) case final id? when id > 0) id,
    };
    final left = <int>{
      for (final id in jsonArray(value['leaving_user_ids']))
        if (jsonIntOrNull(id) case final userId? when userId > 0) userId,
    };
    if (entered.isEmpty && left.isEmpty && lastMessageId == null) return this;

    return ChatPresence(
      userIds: Set.unmodifiable({...userIds, ...entered}..removeAll(left)),
      lastMessageId: lastMessageId ?? this.lastMessageId,
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

/// The MessageBus positions serialized with one channel snapshot.
///
/// Unlike presentation fields, these positions are only seeds: the controller
/// advances its owned cursors after every live event. Keeping the seeds on the
/// record matters for channels arriving outside the main list snapshot — from
/// Browse, search/detail, direct-message creation, or `/chat/new-channel`.
@immutable
class ChatChannelMessageBusState {
  const ChatChannelMessageBusState({
    this.channel,
    this.newMessages,
    this.newMentions,
    this.kick,
  });

  factory ChatChannelMessageBusState.fromJson(Object? value) {
    final json = jsonObject(value);
    return ChatChannelMessageBusState(
      channel: jsonIntOrNull(json['channel_message_bus_last_id']),
      newMessages: jsonIntOrNull(json['new_messages']),
      newMentions: jsonIntOrNull(json['new_mentions']),
      kick: jsonIntOrNull(json['kick']),
    );
  }

  final int? channel;
  final int? newMessages;
  final int? newMentions;
  final int? kick;

  @override
  bool operator ==(Object other) =>
      other is ChatChannelMessageBusState &&
      other.channel == channel &&
      other.newMessages == newMessages &&
      other.newMentions == newMentions &&
      other.kick == kick;

  @override
  int get hashCode => Object.hash(channel, newMessages, newMentions, kick);
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
    this.hasThreads = false,
    this.presence = const ChatPresence(),
    this.newMessageBusLastIds = const {},
    this.newMentionMessageBusLastIds = const {},
    this.kickMessageBusLastIds = const {},
    this.channelMessageBusLastIds = const {},
    this.newChannelBusLastId,
    this.userTrackingBusLastId,
    this.userHasThreadsBusLastId,
    this.channelMetadataBusLastId,
    this.channelEditsBusLastId,
    this.channelStatusBusLastId,
  });

  final List<ChatChannel> public;
  final List<ChatChannel> direct;

  /// Whether this account has at least one thread membership.
  ///
  /// Core serializes this on the channel-list envelope and uses it to decide
  /// whether the account-level "My Threads" destination exists. It is not the
  /// same as any one channel supporting threads: an account with no joined
  /// threads should not get an empty permanent navigation row.
  final bool hasThreads;
  final ChatPresence presence;

  /// The `/chat/{id}/new-messages` position captured with each channel.
  ///
  /// These are transport cursors rather than presentation state. The envelope
  /// makes the bounded list convenient to adopt in one pass; each record also
  /// keeps its seed for channels discovered through another endpoint.
  final Map<int, int?> newMessageBusLastIds;

  /// The personalized `/chat/{id}/new-mentions` position per followed channel.
  final Map<int, int?> newMentionMessageBusLastIds;

  /// The personalized `/chat/{id}/kick` position for public channels.
  final Map<int, int?> kickMessageBusLastIds;

  /// The `/chat/{id}` position captured with each channel.
  ///
  /// A mounted channel or thread consumes this root stream for channel
  /// messages and authoritative thread-preview updates. Retaining the cursor
  /// closes the gap between the HTTP snapshot and the subscription.
  final Map<int, int?> channelMessageBusLastIds;

  /// Envelope-level cursors captured by the same channel-list response.
  final int? newChannelBusLastId;
  final int? userTrackingBusLastId;
  final int? userHasThreadsBusLastId;
  final int? channelMetadataBusLastId;
  final int? channelEditsBusLastId;
  final int? channelStatusBusLastId;
}

/// One page from `/chat/api/channels`, including the server's continuation.
@immutable
class ChatChannelBrowsePage {
  const ChatChannelBrowsePage({this.channels = const [], this.hasMore = false});

  static const int pageSize = 25;

  factory ChatChannelBrowsePage.fromJson(
    Map<String, dynamic> json,
    String siteUrl, {
    int limit = pageSize,
  }) {
    final channels = List<ChatChannel>.unmodifiable([
      for (final entry in jsonObjects(json['channels']).take(limit))
        ChatChannel.fromJson(entry, siteUrl),
    ]);
    return ChatChannelBrowsePage(
      channels: channels,
      // Core supplies a load-more URL on non-terminal Collection pages. The
      // short-page guard also makes this robust against older serializers
      // which emitted the key unconditionally.
      hasMore:
          channels.length == limit &&
          jsonText(jsonObject(json['meta'])['load_more_url']) != null,
    );
  }

  final List<ChatChannel> channels;
  final bool hasMore;
}

typedef ChatChannelBrowseResult = ({
  ChatChannelBrowsePage? page,
  String? error,
});

/// One bounded page from a channel's privacy-safe member list.
typedef ChatChannelMembersPage = ({
  List<ChatUser> members,
  int totalRows,
  bool canLoadMore,
});

typedef ChatChannelMembersResult = ({
  ChatChannelMembersPage? page,
  String? error,
});

/// One chat channel this account follows.
@immutable
class ChatChannel with Storable<ChatChannel> {
  const ChatChannel({
    required this.id,
    required this.title,
    required this.kind,
    this.chatableId,
    this.slug,
    this.emoji,
    this.description,
    this.categoryName,
    this.categoryColor,
    this.readRestricted = false,
    this.status = ChatChannelStatus.open,
    this.userSilenced = false,
    this.canModerate = false,
    this.canDeleteSelf = false,
    this.canDeleteOthers = false,
    this.canManagePins = false,
    this.canFlag = false,
    this.pinnedMessagesCount = 0,
    this.membershipsCount = 0,
    this.canJoin = false,
    this.isGroup = false,
    this.users = const [],
    this.membership = ChatMembership.none,
    this.tracking = ChatTracking.none,
    this.unreadThreadOverview = const {},
    this.threadingEnabled = false,
    this.lastMessageId,
    this.lastMessageAt,
    this.messageBus = const ChatChannelMessageBusState(),
  });

  /// Enough resolved users to distinguish a one-to-one direct message from a
  /// group. No current presentation reads a third person: the server-computed
  /// title already names the group, while the row only needs one face or the
  /// group glyph.
  static const int maximumResolvedUsers = 2;

  /// The largest public-channel bucket returned by the channels endpoint.
  static const int maximumPublicChannels = 100;

  /// The largest direct-message bucket returned by the channels endpoint.
  static const int maximumDirectMessageChannels = 75;

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
    final metadata = jsonObject(json['meta']);

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
      chatableId: jsonIntOrNull(json['chatable_id']),
      slug: jsonText(json['slug']),
      // A bare name, `bug` rather than `:bug:`, and the key is dropped
      // altogether when a channel has none.
      emoji: jsonText(json['emoji']),
      description: jsonText(json['description']),
      categoryName: kind == ChatChannelKind.category
          ? jsonText(chatable['name'])
          : null,
      categoryColor: kind == ChatChannelKind.category
          ? _hexColor(chatable['color'])
          : null,
      readRestricted: chatable['read_restricted'] == true,
      status: ChatChannelStatus.read(json['status']),
      userSilenced: metadata['user_silenced'] == true,
      canModerate: metadata['can_moderate'] == true,
      canDeleteSelf: metadata['can_delete_self'] == true,
      canDeleteOthers: metadata['can_delete_others'] == true,
      canManagePins: metadata['can_manage_pins'] == true,
      canFlag: metadata['can_flag'] == true,
      pinnedMessagesCount: jsonInt(json['pinned_messages_count']),
      membershipsCount: jsonInt(json['memberships_count']),
      canJoin: metadata['can_join_chat_channel'] == true,
      isGroup: chatable['group'] == true,
      users: kind == ChatChannelKind.directMessage
          ? List.unmodifiable([
              for (final entry in jsonObjects(
                chatable['users'],
              ).take(maximumResolvedUsers))
                ChatUser.fromJson(entry, siteUrl),
            ])
          : const [],
      membership: ChatMembership.fromJson(json['current_user_membership']),
      tracking: tracking,
      unreadThreadOverview: Map.unmodifiable(unreadThreadOverview),
      threadingEnabled: json['threading_enabled'] == true,
      lastMessageId: jsonIntOrNull(lastMessage['id']),
      lastMessageAt: jsonDate(lastMessage['created_at']),
      messageBus: ChatChannelMessageBusState.fromJson(
        metadata['message_bus_last_ids'],
      ),
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
    final newMentionMessageBusLastIds = <int, int?>{};
    final kickMessageBusLastIds = <int, int?>{};
    final channelMessageBusLastIds = <int, int?>{};

    ChatChannel readChannel(Map<String, dynamic> entry) {
      final id = jsonInt(entry['id']);
      final lastIds = jsonObject(
        jsonObject(entry['meta'])['message_bus_last_ids'],
      );
      if (lastIds.containsKey('new_messages')) {
        newMessageBusLastIds[id] = jsonIntOrNull(lastIds['new_messages']);
      }
      newMentionMessageBusLastIds[id] = jsonIntOrNull(lastIds['new_mentions']);
      if (ChatChannelKind.read(entry['chatable_type']) ==
          ChatChannelKind.category) {
        kickMessageBusLastIds[id] = jsonIntOrNull(lastIds['kick']);
      }
      if (lastIds.containsKey('channel_message_bus_last_id')) {
        channelMessageBusLastIds[id] = jsonIntOrNull(
          lastIds['channel_message_bus_last_id'],
        );
      }
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

    List<ChatChannel> read(Object? bucket, {required int maximum}) => [
      for (final entry in jsonObjects(bucket).take(maximum)) readChannel(entry),
    ];

    final public = read(json['public_channels'], maximum: maximumPublicChannels)
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
      direct: List.unmodifiable(
        read(
          json['direct_message_channels'],
          maximum: maximumDirectMessageChannels,
        ),
      ),
      hasThreads: json['has_threads'] == true,
      presence: ChatPresence.fromJson(json['global_presence_channel_state']),
      newMessageBusLastIds: Map.unmodifiable(newMessageBusLastIds),
      newMentionMessageBusLastIds: Map.unmodifiable(
        newMentionMessageBusLastIds,
      ),
      kickMessageBusLastIds: Map.unmodifiable(kickMessageBusLastIds),
      channelMessageBusLastIds: Map.unmodifiable(channelMessageBusLastIds),
      newChannelBusLastId: jsonIntOrNull(envelopeLastIds['new_channel']),
      userTrackingBusLastId: jsonIntOrNull(
        envelopeLastIds['user_tracking_state'],
      ),
      userHasThreadsBusLastId: jsonIntOrNull(
        envelopeLastIds['user_has_threads'],
      ),
      channelMetadataBusLastId: jsonIntOrNull(
        envelopeLastIds['channel_metadata'],
      ),
      channelEditsBusLastId: jsonIntOrNull(envelopeLastIds['channel_edits']),
      channelStatusBusLastId: jsonIntOrNull(envelopeLastIds['channel_status']),
    );
  }

  final int id;

  /// What the row says, already computed by the site. See [fromJson].
  final String title;

  final ChatChannelKind kind;
  final int? chatableId;
  final String? slug;

  /// The bare emoji name a channel was given, or null. Resolved to artwork
  /// where it is drawn, through the host emoji resolver, so a site's
  /// custom emoji and its chosen set apply here the way they do inside a post.
  final String? emoji;

  final String? description;

  /// The category a public channel belongs to, as core displays it on the
  /// routed settings page. Direct messages have no category.
  final String? categoryName;

  /// The colour of the category a public channel lives in, which is what tints
  /// its glyph. Null for a direct message, which belongs to no category.
  final Color? categoryColor;

  final bool readRestricted;
  final ChatChannelStatus status;
  final bool userSilenced;
  final bool canModerate;
  final bool canDeleteSelf;
  final bool canDeleteOthers;
  final bool canManagePins;
  final bool canFlag;
  final int pinnedMessagesCount;
  final int membershipsCount;
  final bool canJoin;

  bool get hasPinnedMessages => pinnedMessagesCount > 0;

  bool canModifyMessages({required bool isStaff}) =>
      !userSilenced &&
      status != ChatChannelStatus.readOnly &&
      status != ChatChannelStatus.archived &&
      (isStaff || status != ChatChannelStatus.closed);

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

  /// Snapshot positions used when this channel is first adopted by a live
  /// controller. They do not change as events arrive.
  final ChatChannelMessageBusState messageBus;

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
  /// Urgent for anything addressed to the reader. A mention is; so is every
  /// message in a direct channel, by construction. An unread message in a
  /// public channel the reader merely follows is not, and gets the quieter
  /// accent. The renderer maps urgent to core's success colour and ordinary
  /// unread to its subtle accent token.
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
    chatableId: chatableId,
    slug: slug,
    emoji: emoji,
    description: description,
    categoryName: categoryName,
    categoryColor: categoryColor,
    readRestricted: readRestricted,
    status: status,
    userSilenced: userSilenced,
    canModerate: canModerate,
    canDeleteSelf: canDeleteSelf,
    canDeleteOthers: canDeleteOthers,
    canManagePins: canManagePins,
    canFlag: canFlag,
    pinnedMessagesCount: pinnedMessagesCount,
    membershipsCount: membershipsCount,
    canJoin: canJoin,
    isGroup: isGroup,
    users: users,
    membership: membership.withLastViewedAt(viewedAt),
    tracking: tracking,
    unreadThreadOverview: unreadThreadOverview,
    threadingEnabled: threadingEnabled,
    lastMessageId: lastMessageId,
    lastMessageAt: lastMessageAt,
    messageBus: messageBus,
  );

  /// Applies the complete public metadata event published by core.
  ChatChannel withRemoteMetadata({
    required String title,
    required String slug,
    required String? description,
  }) => ChatChannel(
    id: id,
    title: title,
    kind: kind,
    chatableId: chatableId,
    slug: slug,
    emoji: emoji,
    description: description,
    categoryName: categoryName,
    categoryColor: categoryColor,
    readRestricted: readRestricted,
    status: status,
    userSilenced: userSilenced,
    canModerate: canModerate,
    canDeleteSelf: canDeleteSelf,
    canDeleteOthers: canDeleteOthers,
    canManagePins: canManagePins,
    canFlag: canFlag,
    pinnedMessagesCount: pinnedMessagesCount,
    membershipsCount: membershipsCount,
    canJoin: canJoin,
    isGroup: isGroup,
    users: users,
    membership: membership,
    tracking: tracking,
    unreadThreadOverview: unreadThreadOverview,
    threadingEnabled: threadingEnabled,
    lastMessageId: lastMessageId,
    lastMessageAt: lastMessageAt,
    messageBus: messageBus,
  );

  /// Applies core's account-wide channel-status event.
  ChatChannel withRemoteStatus(ChatChannelStatus status) => ChatChannel(
    id: id,
    title: title,
    kind: kind,
    chatableId: chatableId,
    slug: slug,
    emoji: emoji,
    description: description,
    categoryName: categoryName,
    categoryColor: categoryColor,
    readRestricted: readRestricted,
    status: status,
    userSilenced: userSilenced,
    canModerate: canModerate,
    canDeleteSelf: canDeleteSelf,
    canDeleteOthers: canDeleteOthers,
    canManagePins: canManagePins,
    canFlag: canFlag,
    pinnedMessagesCount: pinnedMessagesCount,
    membershipsCount: membershipsCount,
    canJoin: canJoin,
    isGroup: isGroup,
    users: users,
    membership: membership,
    tracking: status == ChatChannelStatus.archived
        ? ChatTracking.none
        : tracking,
    unreadThreadOverview: status == ChatChannelStatus.archived
        ? const {}
        : unreadThreadOverview,
    threadingEnabled: threadingEnabled,
    lastMessageId: lastMessageId,
    lastMessageAt: lastMessageAt,
    messageBus: messageBus,
  );

  ChatChannel withMembershipsCount(int count) => ChatChannel(
    id: id,
    title: title,
    kind: kind,
    chatableId: chatableId,
    slug: slug,
    emoji: emoji,
    description: description,
    categoryName: categoryName,
    categoryColor: categoryColor,
    readRestricted: readRestricted,
    status: status,
    userSilenced: userSilenced,
    canModerate: canModerate,
    canDeleteSelf: canDeleteSelf,
    canDeleteOthers: canDeleteOthers,
    canManagePins: canManagePins,
    canFlag: canFlag,
    pinnedMessagesCount: pinnedMessagesCount,
    membershipsCount: count < 0 ? 0 : count,
    canJoin: canJoin,
    isGroup: isGroup,
    users: users,
    membership: membership,
    tracking: tracking,
    unreadThreadOverview: unreadThreadOverview,
    threadingEnabled: threadingEnabled,
    lastMessageId: lastMessageId,
    lastMessageAt: lastMessageAt,
    messageBus: messageBus,
  );

  ChatChannel withLastReadAfterDelete(int? messageId) => ChatChannel(
    id: id,
    title: title,
    kind: kind,
    chatableId: chatableId,
    slug: slug,
    emoji: emoji,
    description: description,
    categoryName: categoryName,
    categoryColor: categoryColor,
    readRestricted: readRestricted,
    status: status,
    userSilenced: userSilenced,
    canModerate: canModerate,
    canDeleteSelf: canDeleteSelf,
    canDeleteOthers: canDeleteOthers,
    canManagePins: canManagePins,
    canFlag: canFlag,
    pinnedMessagesCount: pinnedMessagesCount,
    membershipsCount: membershipsCount,
    canJoin: canJoin,
    isGroup: isGroup,
    users: users,
    membership: membership.withLastReadAfterDelete(messageId),
    tracking: tracking,
    unreadThreadOverview: unreadThreadOverview,
    threadingEnabled: threadingEnabled,
    lastMessageId: lastMessageId,
    lastMessageAt: lastMessageAt,
    messageBus: messageBus,
  );

  /// Moves this channel into or out of the account's starred sidebar bucket.
  ChatChannel withStarred(bool starred) => ChatChannel(
    id: id,
    title: title,
    kind: kind,
    chatableId: chatableId,
    slug: slug,
    emoji: emoji,
    description: description,
    categoryName: categoryName,
    categoryColor: categoryColor,
    readRestricted: readRestricted,
    status: status,
    userSilenced: userSilenced,
    canModerate: canModerate,
    canDeleteSelf: canDeleteSelf,
    canDeleteOthers: canDeleteOthers,
    canManagePins: canManagePins,
    canFlag: canFlag,
    pinnedMessagesCount: pinnedMessagesCount,
    membershipsCount: membershipsCount,
    canJoin: canJoin,
    isGroup: isGroup,
    users: users,
    membership: membership.withStarred(starred),
    tracking: tracking,
    unreadThreadOverview: unreadThreadOverview,
    threadingEnabled: threadingEnabled,
    lastMessageId: lastMessageId,
    lastMessageAt: lastMessageAt,
    messageBus: messageBus,
  );

  /// Optimistically exposes or hides the channel's separate thread timeline.
  ChatChannel withThreadingEnabled(bool enabled) => ChatChannel(
    id: id,
    title: title,
    kind: kind,
    chatableId: chatableId,
    slug: slug,
    emoji: emoji,
    description: description,
    categoryName: categoryName,
    categoryColor: categoryColor,
    readRestricted: readRestricted,
    status: status,
    userSilenced: userSilenced,
    canModerate: canModerate,
    canDeleteSelf: canDeleteSelf,
    canDeleteOthers: canDeleteOthers,
    canManagePins: canManagePins,
    canFlag: canFlag,
    pinnedMessagesCount: pinnedMessagesCount,
    membershipsCount: membershipsCount,
    canJoin: canJoin,
    isGroup: isGroup,
    users: users,
    membership: membership,
    tracking: tracking,
    unreadThreadOverview: unreadThreadOverview,
    threadingEnabled: enabled,
    lastMessageId: lastMessageId,
    lastMessageAt: lastMessageAt,
    messageBus: messageBus,
  );

  /// This channel with the site's authoritative current-user membership.
  ///
  /// Membership-setting routes return only that nested record rather than a
  /// complete channel. Keeping the replacement here prevents one preference
  /// write from rebuilding and accidentally dropping unrelated channel data.
  ChatChannel withMembership(
    ChatMembership membership, {
    int? membershipsCount,
  }) => ChatChannel(
    id: id,
    title: title,
    kind: kind,
    chatableId: chatableId,
    slug: slug,
    emoji: emoji,
    description: description,
    categoryName: categoryName,
    categoryColor: categoryColor,
    readRestricted: readRestricted,
    status: status,
    userSilenced: userSilenced,
    canModerate: canModerate,
    canDeleteSelf: canDeleteSelf,
    canDeleteOthers: canDeleteOthers,
    canManagePins: canManagePins,
    canFlag: canFlag,
    pinnedMessagesCount: pinnedMessagesCount,
    membershipsCount: membershipsCount ?? this.membershipsCount,
    canJoin: canJoin,
    isGroup: isGroup,
    users: users,
    membership: membership,
    tracking: tracking,
    unreadThreadOverview: unreadThreadOverview,
    threadingEnabled: threadingEnabled,
    lastMessageId: lastMessageId,
    lastMessageAt: lastMessageAt,
    messageBus: messageBus,
  );

  ChatChannel withPinnedMessagesCount(int count, {bool? hasUnseenPins}) =>
      ChatChannel(
        id: id,
        title: title,
        kind: kind,
        chatableId: chatableId,
        slug: slug,
        emoji: emoji,
        description: description,
        categoryName: categoryName,
        categoryColor: categoryColor,
        readRestricted: readRestricted,
        status: status,
        userSilenced: userSilenced,
        canModerate: canModerate,
        canDeleteSelf: canDeleteSelf,
        canDeleteOthers: canDeleteOthers,
        canManagePins: canManagePins,
        canFlag: canFlag,
        pinnedMessagesCount: count < 0 ? 0 : count,
        membershipsCount: membershipsCount,
        canJoin: canJoin,
        isGroup: isGroup,
        users: users,
        membership: hasUnseenPins == null
            ? membership
            : membership.withUnseenPins(hasUnseenPins),
        tracking: tracking,
        unreadThreadOverview: unreadThreadOverview,
        threadingEnabled: threadingEnabled,
        lastMessageId: lastMessageId,
        lastMessageAt: lastMessageAt,
        messageBus: messageBus,
      );

  ChatChannel withPinsViewed(DateTime viewedAt) => ChatChannel(
    id: id,
    title: title,
    kind: kind,
    chatableId: chatableId,
    slug: slug,
    emoji: emoji,
    description: description,
    categoryName: categoryName,
    categoryColor: categoryColor,
    readRestricted: readRestricted,
    status: status,
    userSilenced: userSilenced,
    canModerate: canModerate,
    canDeleteSelf: canDeleteSelf,
    canDeleteOthers: canDeleteOthers,
    canManagePins: canManagePins,
    canFlag: canFlag,
    pinnedMessagesCount: pinnedMessagesCount,
    membershipsCount: membershipsCount,
    canJoin: canJoin,
    isGroup: isGroup,
    users: users,
    membership: membership.withPinsViewed(viewedAt),
    tracking: tracking,
    unreadThreadOverview: unreadThreadOverview,
    threadingEnabled: threadingEnabled,
    lastMessageId: lastMessageId,
    lastMessageAt: lastMessageAt,
    messageBus: messageBus,
  );

  ChatChannel withPinSnapshot({
    required int count,
    ChatMembership? membership,
  }) => ChatChannel(
    id: id,
    title: title,
    kind: kind,
    chatableId: chatableId,
    slug: slug,
    emoji: emoji,
    description: description,
    categoryName: categoryName,
    categoryColor: categoryColor,
    readRestricted: readRestricted,
    status: status,
    userSilenced: userSilenced,
    canModerate: canModerate,
    canDeleteSelf: canDeleteSelf,
    canDeleteOthers: canDeleteOthers,
    canManagePins: canManagePins,
    canFlag: canFlag,
    pinnedMessagesCount: count < 0 ? 0 : count,
    membershipsCount: membershipsCount,
    canJoin: canJoin,
    isGroup: isGroup,
    users: users,
    membership: membership ?? this.membership,
    tracking: tracking,
    unreadThreadOverview: unreadThreadOverview,
    threadingEnabled: threadingEnabled,
    lastMessageId: lastMessageId,
    lastMessageAt: lastMessageAt,
    messageBus: messageBus,
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
        chatableId: chatableId,
        slug: slug,
        emoji: emoji,
        description: description,
        categoryName: categoryName,
        categoryColor: categoryColor,
        readRestricted: readRestricted,
        status: status,
        userSilenced: userSilenced,
        canModerate: canModerate,
        canDeleteSelf: canDeleteSelf,
        canDeleteOthers: canDeleteOthers,
        canManagePins: canManagePins,
        canFlag: canFlag,
        pinnedMessagesCount: pinnedMessagesCount,
        membershipsCount: membershipsCount,
        canJoin: canJoin,
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
        messageBus: messageBus,
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
    chatableId: chatableId,
    slug: slug,
    emoji: emoji,
    description: description,
    categoryName: categoryName,
    categoryColor: categoryColor,
    readRestricted: readRestricted,
    status: status,
    userSilenced: userSilenced,
    canModerate: canModerate,
    canDeleteSelf: canDeleteSelf,
    canDeleteOthers: canDeleteOthers,
    canManagePins: canManagePins,
    canFlag: canFlag,
    pinnedMessagesCount: pinnedMessagesCount,
    membershipsCount: membershipsCount,
    canJoin: canJoin,
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
    messageBus: messageBus,
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
    bool threadMembershipKnown = false,
    bool forceThread = false,
    bool incrementWatchedThreadUnread = false,
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
        (threadingEnabled || forceThread) &&
        (isDirectMessage ||
            threadMembershipKnown ||
            unreadThreadOverview.containsKey(threadId))) {
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
      chatableId: chatableId,
      slug: slug,
      emoji: emoji,
      description: description,
      categoryName: categoryName,
      categoryColor: categoryColor,
      readRestricted: readRestricted,
      status: status,
      userSilenced: userSilenced,
      canModerate: canModerate,
      canDeleteSelf: canDeleteSelf,
      canDeleteOthers: canDeleteOthers,
      canManagePins: canManagePins,
      canFlag: canFlag,
      pinnedMessagesCount: pinnedMessagesCount,
      membershipsCount: membershipsCount,
      canJoin: canJoin,
      isGroup: isGroup,
      users: users,
      membership: markRead ? membership.withLastRead(messageId) : membership,
      tracking: incrementUnread || incrementWatchedThreadUnread
          ? ChatTracking(
              unreadCount: tracking.unreadCount + (incrementUnread ? 1 : 0),
              mentionCount: tracking.mentionCount,
              watchedThreadsUnreadCount:
                  tracking.watchedThreadsUnreadCount +
                  (incrementWatchedThreadUnread ? 1 : 0),
            )
          : tracking,
      unreadThreadOverview: nextThreadOverview,
      threadingEnabled: threadingEnabled,
      lastMessageId: messageId,
      lastMessageAt: createdAt,
      messageBus: messageBus,
    );
  }

  /// Applies an authoritative channel-settings response without discarding
  /// the reader state that response does not serialize.
  ///
  /// `/chat/api/channels/{id}` returns the channel and membership, but no
  /// sibling tracking report or unread-thread overview. Replacing the stored
  /// record literally would make every unread badge disappear after a rename.
  ChatChannel withServerSettings(ChatChannel incoming) {
    if (incoming.id != id) return this;
    return ChatChannel(
      id: incoming.id,
      title: incoming.title,
      kind: incoming.kind,
      chatableId: incoming.chatableId,
      slug: incoming.slug,
      emoji: incoming.emoji,
      description: incoming.description,
      categoryName: incoming.categoryName,
      categoryColor: incoming.categoryColor,
      readRestricted: incoming.readRestricted,
      status: incoming.status,
      userSilenced: incoming.userSilenced,
      canModerate: incoming.canModerate,
      canDeleteSelf: incoming.canDeleteSelf,
      canDeleteOthers: incoming.canDeleteOthers,
      canManagePins: incoming.canManagePins,
      canFlag: incoming.canFlag,
      pinnedMessagesCount: incoming.pinnedMessagesCount,
      membershipsCount: incoming.membershipsCount,
      canJoin: incoming.canJoin,
      isGroup: incoming.isGroup,
      users: incoming.users,
      membership: incoming.membership.following
          ? incoming.membership
          : membership,
      tracking: tracking,
      unreadThreadOverview: unreadThreadOverview,
      threadingEnabled: incoming.threadingEnabled,
      lastMessageId: incoming.lastMessageId ?? lastMessageId,
      lastMessageAt: incoming.lastMessageAt ?? lastMessageAt,
      messageBus: messageBus,
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
          other.chatableId == chatableId &&
          other.slug == slug &&
          other.emoji == emoji &&
          other.description == description &&
          other.categoryName == categoryName &&
          other.categoryColor == categoryColor &&
          other.readRestricted == readRestricted &&
          other.status == status &&
          other.userSilenced == userSilenced &&
          other.canModerate == canModerate &&
          other.canDeleteSelf == canDeleteSelf &&
          other.canDeleteOthers == canDeleteOthers &&
          other.canManagePins == canManagePins &&
          other.canFlag == canFlag &&
          other.pinnedMessagesCount == pinnedMessagesCount &&
          other.membershipsCount == membershipsCount &&
          other.canJoin == canJoin &&
          other.isGroup == isGroup &&
          listEquals(other.users, users) &&
          other.membership == membership &&
          other.tracking == tracking &&
          mapEquals(other.unreadThreadOverview, unreadThreadOverview) &&
          other.threadingEnabled == threadingEnabled &&
          other.lastMessageId == lastMessageId &&
          other.lastMessageAt == lastMessageAt &&
          other.messageBus == messageBus;

  @override
  int get hashCode => Object.hashAll([
    id,
    title,
    kind,
    chatableId,
    slug,
    emoji,
    description,
    categoryName,
    categoryColor,
    readRestricted,
    status,
    userSilenced,
    canModerate,
    canDeleteSelf,
    canDeleteOthers,
    canManagePins,
    canFlag,
    pinnedMessagesCount,
    membershipsCount,
    canJoin,
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
    messageBus,
  ]);

  @override
  Object get storeId => id;
}
