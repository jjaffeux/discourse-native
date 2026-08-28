import 'package:flutter/foundation.dart';

import 'bookmark.dart';
import 'json.dart';
import 'user_status.dart';

/// Which chat activity the account wants called out on the header shortcut.
///
/// These are the four values Discourse's Chat plugin serializes from
/// `UserOption#chat_header_indicator_preference`. Unknown values keep the
/// server's default behaviour rather than silently turning the indicator off.
enum ChatHeaderIndicatorPreference {
  allNew('all_new'),
  directMessagesAndMentions('dm_and_mentions'),
  onlyMentions('only_mentions'),
  never('never');

  const ChatHeaderIndicatorPreference(this.wireName);

  final String wireName;

  static ChatHeaderIndicatorPreference read(Object? value) {
    for (final preference in values) {
      if (value == preference.wireName) return preference;
    }
    return allNew;
  }
}

/// The account an API key belongs to, from `/session/current.json`.
@immutable
class DiscourseUser {
  const DiscourseUser({
    required this.username,
    this.id,
    this.name,
    this.avatarUrl,
    this.status,
    this.draftCount = 0,
    this.canCreatePoll,
    this.canAssign,
    this.canAssignGlobally,
    this.canChangePostOwner = false,
    this.staff = false,
    this.groups = const [],
    this.ignoredUsernames = const [],
    this.sidebarCategoryIds = const [],
    this.trackedCategoryIds,
    this.watchedCategoryIds,
    this.watchedFirstPostCategoryIds,
    this.hasChatEnabled,
    this.chatHeaderIndicatorPreference = ChatHeaderIndicatorPreference.allNew,
    this.doNotDisturbUntil,
    this.doNotDisturbChannelPosition,
    this.lastChatChannelId,
    this.timezone,
    this.hidePresence,
    this.bookmarkAutoDeletePreference =
        BookmarkAutoDeletePreference.clearReminder,
  });

  factory DiscourseUser.fromJson(Map<String, dynamic> json) => DiscourseUser(
    username: json['username'] as String,
    // Absent from anything stored before the live counters needed it, which is
    // why it is nullable rather than required — see `ShellController`, which
    // asks the site again when it finds one missing.
    id: jsonIntOrNull(json['id']),
    name: json['name'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    status: _storedStatus(json['status']),
    draftCount: jsonInt(json['draftCount']),
    // Optional so accounts persisted before Poll support remain readable. A
    // stored value is display state only; ShellController requires a fresh
    // session read before it treats this as a capability.
    canCreatePoll: json['canCreatePoll'] as bool?,
    canAssign: json['canAssign'] as bool?,
    canAssignGlobally: json['canAssignGlobally'] as bool?,
    canChangePostOwner: json['canChangePostOwner'] == true,
    staff: json['staff'] == true,
    groups: List.unmodifiable(
      jsonArray(json['groups']).map(jsonText).whereType<String>(),
    ),
    ignoredUsernames: List.unmodifiable(
      jsonArray(json['ignoredUsernames']).map(jsonText).whereType<String>(),
    ),
    sidebarCategoryIds: List.unmodifiable([
      for (final value in jsonArray(json['sidebarCategoryIds']))
        ?jsonIntOrNull(value),
    ]),
    trackedCategoryIds: _storedCategoryIds(json, 'trackedCategoryIds'),
    watchedCategoryIds: _storedCategoryIds(json, 'watchedCategoryIds'),
    watchedFirstPostCategoryIds: _storedCategoryIds(
      json,
      'watchedFirstPostCategoryIds',
    ),
    // Nullable only for accounts persisted before this capability was stored.
    hasChatEnabled: json['hasChatEnabled'] as bool?,
    chatHeaderIndicatorPreference: ChatHeaderIndicatorPreference.read(
      json['chatHeaderIndicatorPreference'],
    ),
    doNotDisturbUntil: jsonDate(json['doNotDisturbUntil']),
    doNotDisturbChannelPosition: jsonIntOrNull(
      json['doNotDisturbChannelPosition'],
    ),
    lastChatChannelId: jsonIntOrNull(json['lastChatChannelId']),
    timezone: json['timezone'] as String?,
    // Null distinguishes an account stored before this preference was retained
    // from the server-confirmed "online" value false.
    hidePresence: json['hidePresence'] as bool?,
    bookmarkAutoDeletePreference: BookmarkAutoDeletePreference.read(
      json['bookmarkAutoDeletePreference'],
    ),
  );

  final String username;

  /// The account's own id, which is how Discourse names the message_bus
  /// channels it publishes a user's counts on.
  final int? id;

  final String? name;
  final String? avatarUrl;
  final UserStatus? status;
  final int draftCount;

  /// The Poll plugin's session capability. Null means the plugin did not add
  /// it (or this account predates the field), rather than false.
  final bool? canCreatePoll;

  /// Assign's session capabilities. Null means the plugin did not add the
  /// serializer attributes (or this is an older persisted account), while
  /// false means Assign is active but this account does not have that scope.
  /// Individual topic and post payloads remain authoritative for a target.
  final bool? canAssign;
  final bool? canAssignGlobally;

  /// Core's account-level guardian for reassigning post authorship.
  final bool canChangePostOwner;

  /// Whether the current account is an administrator or moderator.
  final bool staff;

  /// Group names from the freshly loaded current-user payload.
  final List<String> groups;

  /// Usernames this account ignores.
  ///
  /// Discourse uses this list to suppress unread state for chat messages from
  /// ignored users. Persisting it keeps that behavior available between
  /// current-user refreshes.
  final List<String> ignoredUsernames;

  /// The categories this account chose for its sidebar. Core derives display
  /// order from the site's category ordering rather than this list's order.
  final List<int> sidebarCategoryIds;

  /// Direct category preferences at or above core's Tracking level.
  ///
  /// Null means this account was persisted before the current-user serializer
  /// fields were retained. A fresh server response uses an empty list when the
  /// account has no categories at that level, keeping migration state distinct
  /// from a real empty preference.
  final List<int>? trackedCategoryIds;
  final List<int>? watchedCategoryIds;
  final List<int>? watchedFirstPostCategoryIds;

  Set<int>? get followedCategoryIds {
    if (trackedCategoryIds == null ||
        watchedCategoryIds == null ||
        watchedFirstPostCategoryIds == null) {
      return null;
    }
    return {
      ...trackedCategoryIds!,
      ...watchedCategoryIds!,
      ...watchedFirstPostCategoryIds!,
    };
  }

  /// Whether the Chat plugin, its guardian and this account's own option all
  /// allow chat. Null means an older stored account has not been refreshed yet.
  final bool? hasChatEnabled;

  final ChatHeaderIndicatorPreference chatHeaderIndicatorPreference;

  /// While this lies in the future Discourse suppresses the header indicator.
  final DateTime? doNotDisturbUntil;

  /// Snapshot cursor for the account's private Do Not Disturb channel.
  final int? doNotDisturbChannelPosition;

  /// The channel Discourse last served to this account, used by `/chat` on
  /// desktop and by the native shortcut as its first destination.
  final int? lastChatChannelId;

  /// The IANA timezone selected in this account's Discourse preferences.
  ///
  /// Rendering normally follows the device, like the web client. This is the
  /// source-zone default for newly authored dates and the fallback when the
  /// operating system cannot report an IANA identifier.
  final String? timezone;

  /// Whether this account opted out of Discourse presence features.
  ///
  /// Null means no current-user payload carrying the option has been retained
  /// yet. False is an authoritative server value and means the account appears
  /// online where a presence feature is active.
  final bool? hidePresence;

  final BookmarkAutoDeletePreference bookmarkAutoDeletePreference;

  bool get isInDoNotDisturb =>
      doNotDisturbUntil?.isAfter(DateTime.now()) ?? false;

  Map<String, dynamic> toJson() => {
    'username': username,
    'id': id,
    'name': name,
    'avatarUrl': avatarUrl,
    'status': status?.toJson(),
    'draftCount': draftCount,
    'canCreatePoll': canCreatePoll,
    'canAssign': canAssign,
    'canAssignGlobally': canAssignGlobally,
    'canChangePostOwner': canChangePostOwner,
    'staff': staff,
    'groups': groups,
    'ignoredUsernames': ignoredUsernames,
    'sidebarCategoryIds': sidebarCategoryIds,
    if (trackedCategoryIds != null) 'trackedCategoryIds': trackedCategoryIds,
    if (watchedCategoryIds != null) 'watchedCategoryIds': watchedCategoryIds,
    if (watchedFirstPostCategoryIds != null)
      'watchedFirstPostCategoryIds': watchedFirstPostCategoryIds,
    'hasChatEnabled': hasChatEnabled,
    'chatHeaderIndicatorPreference': chatHeaderIndicatorPreference.wireName,
    'doNotDisturbUntil': doNotDisturbUntil?.toIso8601String(),
    'doNotDisturbChannelPosition': doNotDisturbChannelPosition,
    'lastChatChannelId': lastChatChannelId,
    'timezone': timezone,
    if (hidePresence != null) 'hidePresence': hidePresence,
    'bookmarkAutoDeletePreference': bookmarkAutoDeletePreference.wireValue,
  };

  /// Display name if the site has one, otherwise the username.
  String get displayName => (name?.isNotEmpty ?? false) ? name! : username;

  DiscourseUser withStatus(UserStatus? status) => DiscourseUser(
    username: username,
    id: id,
    name: name,
    avatarUrl: avatarUrl,
    status: status,
    draftCount: draftCount,
    canCreatePoll: canCreatePoll,
    canAssign: canAssign,
    canAssignGlobally: canAssignGlobally,
    canChangePostOwner: canChangePostOwner,
    staff: staff,
    groups: groups,
    ignoredUsernames: ignoredUsernames,
    sidebarCategoryIds: sidebarCategoryIds,
    trackedCategoryIds: trackedCategoryIds,
    watchedCategoryIds: watchedCategoryIds,
    watchedFirstPostCategoryIds: watchedFirstPostCategoryIds,
    hasChatEnabled: hasChatEnabled,
    chatHeaderIndicatorPreference: chatHeaderIndicatorPreference,
    doNotDisturbUntil: doNotDisturbUntil,
    doNotDisturbChannelPosition: doNotDisturbChannelPosition,
    lastChatChannelId: lastChatChannelId,
    timezone: timezone,
    bookmarkAutoDeletePreference: bookmarkAutoDeletePreference,
  );

  DiscourseUser withDoNotDisturbUntil(DateTime? until) => DiscourseUser(
    username: username,
    id: id,
    name: name,
    avatarUrl: avatarUrl,
    status: status,
    draftCount: draftCount,
    canCreatePoll: canCreatePoll,
    canAssign: canAssign,
    canAssignGlobally: canAssignGlobally,
    canChangePostOwner: canChangePostOwner,
    staff: staff,
    groups: groups,
    ignoredUsernames: ignoredUsernames,
    sidebarCategoryIds: sidebarCategoryIds,
    trackedCategoryIds: trackedCategoryIds,
    watchedCategoryIds: watchedCategoryIds,
    watchedFirstPostCategoryIds: watchedFirstPostCategoryIds,
    hasChatEnabled: hasChatEnabled,
    chatHeaderIndicatorPreference: chatHeaderIndicatorPreference,
    doNotDisturbUntil: until,
    doNotDisturbChannelPosition: doNotDisturbChannelPosition,
    lastChatChannelId: lastChatChannelId,
    timezone: timezone,
    bookmarkAutoDeletePreference: bookmarkAutoDeletePreference,
  );

  /// Applies the server-confirmed preference values consumed outside the
  /// Preferences page while preserving every capability from this session.
  ///
  /// This stored user is a warm-start mirror, not the owner of the values;
  /// Preferences writes always go to Discourse before this copy changes.
  DiscourseUser withPreferences({
    String? timezone,
    BookmarkAutoDeletePreference? bookmarkAutoDeletePreference,
  }) => DiscourseUser(
    username: username,
    id: id,
    name: name,
    avatarUrl: avatarUrl,
    status: status,
    draftCount: draftCount,
    canCreatePoll: canCreatePoll,
    canAssign: canAssign,
    canAssignGlobally: canAssignGlobally,
    canChangePostOwner: canChangePostOwner,
    staff: staff,
    groups: groups,
    ignoredUsernames: ignoredUsernames,
    sidebarCategoryIds: sidebarCategoryIds,
    trackedCategoryIds: trackedCategoryIds,
    watchedCategoryIds: watchedCategoryIds,
    watchedFirstPostCategoryIds: watchedFirstPostCategoryIds,
    hasChatEnabled: hasChatEnabled,
    chatHeaderIndicatorPreference: chatHeaderIndicatorPreference,
    doNotDisturbUntil: doNotDisturbUntil,
    lastChatChannelId: lastChatChannelId,
    timezone: timezone ?? this.timezone,
    hidePresence: hidePresence,
    bookmarkAutoDeletePreference:
        bookmarkAutoDeletePreference ?? this.bookmarkAutoDeletePreference,
  );

  /// Replaces the server-confirmed presence preference while retaining the
  /// rest of the freshest current-user payload.
  DiscourseUser withHidePresence(bool? hidePresence) => DiscourseUser(
    username: username,
    id: id,
    name: name,
    avatarUrl: avatarUrl,
    status: status,
    draftCount: draftCount,
    canCreatePoll: canCreatePoll,
    canAssign: canAssign,
    canAssignGlobally: canAssignGlobally,
    canChangePostOwner: canChangePostOwner,
    staff: staff,
    groups: groups,
    ignoredUsernames: ignoredUsernames,
    sidebarCategoryIds: sidebarCategoryIds,
    trackedCategoryIds: trackedCategoryIds,
    watchedCategoryIds: watchedCategoryIds,
    watchedFirstPostCategoryIds: watchedFirstPostCategoryIds,
    hasChatEnabled: hasChatEnabled,
    chatHeaderIndicatorPreference: chatHeaderIndicatorPreference,
    doNotDisturbUntil: doNotDisturbUntil,
    lastChatChannelId: lastChatChannelId,
    timezone: timezone,
    hidePresence: hidePresence,
    bookmarkAutoDeletePreference: bookmarkAutoDeletePreference,
  );

  @override
  bool operator ==(Object other) =>
      other is DiscourseUser &&
      other.username == username &&
      other.id == id &&
      other.name == name &&
      other.avatarUrl == avatarUrl &&
      other.status == status &&
      other.draftCount == draftCount &&
      other.canCreatePoll == canCreatePoll &&
      other.canAssign == canAssign &&
      other.canAssignGlobally == canAssignGlobally &&
      other.canChangePostOwner == canChangePostOwner &&
      other.staff == staff &&
      listEquals(other.groups, groups) &&
      listEquals(other.ignoredUsernames, ignoredUsernames) &&
      listEquals(other.sidebarCategoryIds, sidebarCategoryIds) &&
      listEquals(other.trackedCategoryIds, trackedCategoryIds) &&
      listEquals(other.watchedCategoryIds, watchedCategoryIds) &&
      listEquals(
        other.watchedFirstPostCategoryIds,
        watchedFirstPostCategoryIds,
      ) &&
      other.hasChatEnabled == hasChatEnabled &&
      other.chatHeaderIndicatorPreference == chatHeaderIndicatorPreference &&
      other.doNotDisturbUntil == doNotDisturbUntil &&
      other.doNotDisturbChannelPosition == doNotDisturbChannelPosition &&
      other.lastChatChannelId == lastChatChannelId &&
      other.timezone == timezone &&
      other.hidePresence == hidePresence &&
      other.bookmarkAutoDeletePreference == bookmarkAutoDeletePreference;

  @override
  int get hashCode => Object.hashAll([
    username,
    id,
    name,
    avatarUrl,
    status,
    draftCount,
    canCreatePoll,
    canAssign,
    canAssignGlobally,
    canChangePostOwner,
    staff,
    Object.hashAll(groups),
    Object.hashAll(ignoredUsernames),
    Object.hashAll(sidebarCategoryIds),
    Object.hashAll(trackedCategoryIds ?? const <int>[]),
    Object.hashAll(watchedCategoryIds ?? const <int>[]),
    Object.hashAll(watchedFirstPostCategoryIds ?? const <int>[]),
    hasChatEnabled,
    chatHeaderIndicatorPreference,
    doNotDisturbUntil,
    doNotDisturbChannelPosition,
    lastChatChannelId,
    timezone,
    hidePresence,
    bookmarkAutoDeletePreference,
  ]);
}

List<int>? _storedCategoryIds(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) return null;
  return List.unmodifiable([
    for (final value in jsonArray(json[key])) ?jsonIntOrNull(value),
  ]);
}

UserStatus? _storedStatus(Object? value) {
  if (value is! Map) return null;
  try {
    final json = Map<String, dynamic>.from(value);
    final description = jsonText(json['description']);
    final emoji = jsonText(json['emoji']);
    if (description == null ||
        description.isEmpty ||
        emoji == null ||
        emoji.isEmpty) {
      return null;
    }
    return UserStatus(
      description: description,
      emoji: emoji,
      endsAt: jsonDate(json['endsAt']),
      messageBusLastId: jsonIntOrNull(json['messageBusLastId']),
    );
  } catch (_) {
    return null;
  }
}
