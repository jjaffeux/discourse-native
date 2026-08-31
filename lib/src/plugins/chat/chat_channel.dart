import 'package:flutter/foundation.dart'
    show immutable, listEquals, mapEquals, setEquals;
import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../../models/json.dart';
import '../../models/sidebar.dart';
import '../../models/user_status.dart';

/// `chatable_type` is open-ended, so unknown values remain drawable as [other].
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

enum ChatChannelBrowseStatus { all, open, closed, archived }

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

  final bool starred;

  final int? lastReadMessageId;

  final DateTime? lastViewedAt;
  final DateTime? lastViewedPinsAt;
  final bool hasUnseenPins;

  /// Does not clamp backwards; the command boundary must reject stale writes.
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

/// Parsed from the payload's sibling `tracking.channel_tracking` map.
@immutable
class ChatTracking {
  const ChatTracking({
    this.unreadCount = 0,
    this.mentionCount = 0,
    this.watchedThreadsUnreadCount = 0,
  });

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

/// Couples the HTTP presence snapshot with its cursor so live updates begin
/// without a gap.
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

  /// Enter events carry users, leave events only ids; unknown events are no-ops.
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

/// Includes cursors for channels discovered outside the main list snapshot.
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

/// Parses presence atomically with channels to avoid a subscription gap.
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

  /// Account-level membership gate for “My Threads”, not channel capability.
  final bool hasThreads;
  final ChatPresence presence;

  final Map<int, int?> newMessageBusLastIds;

  final Map<int, int?> newMentionMessageBusLastIds;

  final Map<int, int?> kickMessageBusLastIds;

  final Map<int, int?> channelMessageBusLastIds;

  final int? newChannelBusLastId;
  final int? userTrackingBusLastId;
  final int? userHasThreadsBusLastId;
  final int? channelMetadataBusLastId;
  final int? channelEditsBusLastId;
  final int? channelStatusBusLastId;
}

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
      // Older serializers emitted load-more URLs even on short terminal pages.
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

typedef ChatChannelMembersPage = ({
  List<ChatUser> members,
  int totalRows,
  bool canLoadMore,
});

typedef ChatChannelMembersResult = ({
  ChatChannelMembersPage? page,
  String? error,
});

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

  /// Only enough users are retained to choose a single avatar or a group glyph.
  static const int maximumResolvedUsers = 2;

  static const int maximumPublicChannels = 100;

  static const int maximumDirectMessageChannels = 75;

  /// [tracking] comes from a sibling map rather than [json].
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
      title: jsonText(json['unicode_title']) ?? jsonText(json['title']) ?? '',
      kind: kind,
      chatableId: jsonIntOrNull(json['chatable_id']),
      slug: jsonText(json['slug']),
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

  /// Public channels sort by slug; direct messages retain server activity order.
  static ChatChannels parse(Map<String, dynamic> json, String siteUrl) {
    // Ruby integer hash keys become strings in a JSON object.
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
      // Match Discourse's slug ordering rather than display-title ordering.
      ..sort(
        (a, b) => (a.slug ?? a.title).toLowerCase().compareTo(
          (b.slug ?? b.title).toLowerCase(),
        ),
      );

    // Preserve server activity order as the live comparator's tie-breaker.
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

  final String title;

  final ChatChannelKind kind;
  final int? chatableId;
  final String? slug;

  final String? emoji;

  final String? description;

  final String? categoryName;

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

  /// Remains true for a group DM with only one other participant left.
  final bool isGroup;

  /// Server-provided DM participants exclude the reader.
  final List<ChatUser> users;

  final ChatMembership membership;
  final ChatTracking tracking;

  /// Core combines these reply dates with membership last-viewed time for DM order.
  final Map<int, DateTime> unreadThreadOverview;

  int get unreadThreadCount => unreadThreadOverview.length;

  int get unreadThreadsCountSinceLastViewed {
    final viewedAt = membership.lastViewedAt;
    if (viewedAt == null) return unreadThreadOverview.length;
    return unreadThreadOverview.values
        .where((createdAt) => !createdAt.isBefore(viewedAt))
        .length;
  }

  DateTime? get lastUnreadThreadAt {
    // Core uses the oldest outstanding reply as its final tie-breaker.
    DateTime? oldest;
    for (final createdAt in unreadThreadOverview.values) {
      if (oldest == null || createdAt.isBefore(oldest)) oldest = createdAt;
    }
    return oldest;
  }

  /// Changes the wire stream: threaded channels include original messages only;
  /// replies live behind their thread routes.
  final bool threadingEnabled;

  final int? lastMessageId;
  final DateTime? lastMessageAt;

  final ChatChannelMessageBusState messageBus;

  bool get isDirectMessage => kind == ChatChannelKind.directMessage;
  bool get isCategoryChannel => kind == ChatChannelKind.category;

  String? get avatarUrl =>
      isDirectMessage && users.length == 1 ? users.first.avatarUrl : null;

  /// Direct messages and mentions are urgent; other public unread is ordinary.
  SidebarBadge get badge {
    // This sidebar has no dimmed state, so muted channels suppress the badge.
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

  /// Advances channel view time without clearing the thread overview shared by
  /// the thread list.
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

  /// Merges partial membership-setting responses without dropping channel data.
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

  /// Counts clear only when [caughtUp]; the client cannot derive exact counts
  /// from a partial message window.
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
        // Reading a channel does not read its independent thread streams.
        unreadThreadOverview: unreadThreadOverview,
        threadingEnabled: threadingEnabled,
        lastMessageId: lastMessageId,
        lastMessageAt: lastMessageAt,
        messageBus: messageBus,
      );

  /// Authoritative tracking corrects eager channel events and other-client reads.
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

  /// Applies web-compatible eager unread activity; user tracking later supplies
  /// exact counts.
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
      // DMs grant every participant every thread membership; public channels do not.
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

  /// Settings responses omit tracking and thread overview state, which must
  /// survive metadata edits.
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

  static String routeId(int channelId) => '$_routePrefix$channelId';

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
