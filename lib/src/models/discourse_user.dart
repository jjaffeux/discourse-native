import 'package:flutter/foundation.dart';

import 'bookmark.dart';
import 'json.dart';

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
    this.draftCount = 0,
    this.canCreatePoll,
    this.canAssign,
    this.canAssignGlobally,
    this.staff = false,
    this.groups = const [],
    this.ignoredUsernames = const [],
    this.sidebarCategoryIds = const [],
    this.hasChatEnabled,
    this.chatHeaderIndicatorPreference = ChatHeaderIndicatorPreference.allNew,
    this.doNotDisturbUntil,
    this.lastChatChannelId,
    this.timezone,
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
    draftCount: jsonInt(json['draftCount']),
    // Optional so accounts persisted before Poll support remain readable. A
    // stored value is display state only; ShellController requires a fresh
    // session read before it treats this as a capability.
    canCreatePoll: json['canCreatePoll'] as bool?,
    canAssign: json['canAssign'] as bool?,
    canAssignGlobally: json['canAssignGlobally'] as bool?,
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
    // Nullable only for accounts persisted before this capability was stored.
    hasChatEnabled: json['hasChatEnabled'] as bool?,
    chatHeaderIndicatorPreference: ChatHeaderIndicatorPreference.read(
      json['chatHeaderIndicatorPreference'],
    ),
    doNotDisturbUntil: jsonDate(json['doNotDisturbUntil']),
    lastChatChannelId: jsonIntOrNull(json['lastChatChannelId']),
    timezone: json['timezone'] as String?,
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

  /// Whether the Chat plugin, its guardian and this account's own option all
  /// allow chat. Null means an older stored account has not been refreshed yet.
  final bool? hasChatEnabled;

  final ChatHeaderIndicatorPreference chatHeaderIndicatorPreference;

  /// While this lies in the future Discourse suppresses the header indicator.
  final DateTime? doNotDisturbUntil;

  /// The channel Discourse last served to this account, used by `/chat` on
  /// desktop and by the native shortcut as its first destination.
  final int? lastChatChannelId;

  /// The IANA timezone selected in this account's Discourse preferences.
  ///
  /// Rendering normally follows the device, like the web client. This is the
  /// source-zone default for newly authored dates and the fallback when the
  /// operating system cannot report an IANA identifier.
  final String? timezone;

  final BookmarkAutoDeletePreference bookmarkAutoDeletePreference;

  bool get isInDoNotDisturb =>
      doNotDisturbUntil?.isAfter(DateTime.now()) ?? false;

  Map<String, dynamic> toJson() => {
    'username': username,
    'id': id,
    'name': name,
    'avatarUrl': avatarUrl,
    'draftCount': draftCount,
    'canCreatePoll': canCreatePoll,
    'canAssign': canAssign,
    'canAssignGlobally': canAssignGlobally,
    'staff': staff,
    'groups': groups,
    'ignoredUsernames': ignoredUsernames,
    'sidebarCategoryIds': sidebarCategoryIds,
    'hasChatEnabled': hasChatEnabled,
    'chatHeaderIndicatorPreference': chatHeaderIndicatorPreference.wireName,
    'doNotDisturbUntil': doNotDisturbUntil?.toIso8601String(),
    'lastChatChannelId': lastChatChannelId,
    'timezone': timezone,
    'bookmarkAutoDeletePreference': bookmarkAutoDeletePreference.wireValue,
  };

  /// Display name if the site has one, otherwise the username.
  String get displayName => (name?.isNotEmpty ?? false) ? name! : username;

  @override
  bool operator ==(Object other) =>
      other is DiscourseUser &&
      other.username == username &&
      other.id == id &&
      other.name == name &&
      other.avatarUrl == avatarUrl &&
      other.draftCount == draftCount &&
      other.canCreatePoll == canCreatePoll &&
      other.canAssign == canAssign &&
      other.canAssignGlobally == canAssignGlobally &&
      other.staff == staff &&
      listEquals(other.groups, groups) &&
      listEquals(other.ignoredUsernames, ignoredUsernames) &&
      listEquals(other.sidebarCategoryIds, sidebarCategoryIds) &&
      other.hasChatEnabled == hasChatEnabled &&
      other.chatHeaderIndicatorPreference == chatHeaderIndicatorPreference &&
      other.doNotDisturbUntil == doNotDisturbUntil &&
      other.lastChatChannelId == lastChatChannelId &&
      other.timezone == timezone &&
      other.bookmarkAutoDeletePreference == bookmarkAutoDeletePreference;

  @override
  int get hashCode => Object.hash(
    username,
    id,
    name,
    avatarUrl,
    draftCount,
    canCreatePoll,
    canAssign,
    canAssignGlobally,
    staff,
    Object.hashAll(groups),
    Object.hashAll(ignoredUsernames),
    Object.hashAll(sidebarCategoryIds),
    hasChatEnabled,
    chatHeaderIndicatorPreference,
    doNotDisturbUntil,
    lastChatChannelId,
    timezone,
    bookmarkAutoDeletePreference,
  );
}
