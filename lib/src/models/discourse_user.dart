import 'package:flutter/foundation.dart';

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
    this.staff = false,
    this.groups = const [],
    this.hasChatEnabled,
    this.chatHeaderIndicatorPreference = ChatHeaderIndicatorPreference.allNew,
    this.doNotDisturbUntil,
    this.lastChatChannelId,
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
    staff: json['staff'] == true,
    groups: List.unmodifiable(
      jsonArray(json['groups']).map(jsonText).whereType<String>(),
    ),
    // Nullable only for accounts persisted before this capability was stored.
    hasChatEnabled: json['hasChatEnabled'] as bool?,
    chatHeaderIndicatorPreference: ChatHeaderIndicatorPreference.read(
      json['chatHeaderIndicatorPreference'],
    ),
    doNotDisturbUntil: jsonDate(json['doNotDisturbUntil']),
    lastChatChannelId: jsonIntOrNull(json['lastChatChannelId']),
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

  /// Whether the current account is an administrator or moderator.
  final bool staff;

  /// Group names from the freshly loaded current-user payload.
  final List<String> groups;

  /// Whether the Chat plugin, its guardian and this account's own option all
  /// allow chat. Null means an older stored account has not been refreshed yet.
  final bool? hasChatEnabled;

  final ChatHeaderIndicatorPreference chatHeaderIndicatorPreference;

  /// While this lies in the future Discourse suppresses the header indicator.
  final DateTime? doNotDisturbUntil;

  /// The channel Discourse last served to this account, used by `/chat` on
  /// desktop and by the native shortcut as its first destination.
  final int? lastChatChannelId;

  bool get isInDoNotDisturb =>
      doNotDisturbUntil?.isAfter(DateTime.now()) ?? false;

  Map<String, dynamic> toJson() => {
    'username': username,
    'id': id,
    'name': name,
    'avatarUrl': avatarUrl,
    'draftCount': draftCount,
    'canCreatePoll': canCreatePoll,
    'staff': staff,
    'groups': groups,
    'hasChatEnabled': hasChatEnabled,
    'chatHeaderIndicatorPreference': chatHeaderIndicatorPreference.wireName,
    'doNotDisturbUntil': doNotDisturbUntil?.toIso8601String(),
    'lastChatChannelId': lastChatChannelId,
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
      other.staff == staff &&
      listEquals(other.groups, groups) &&
      other.hasChatEnabled == hasChatEnabled &&
      other.chatHeaderIndicatorPreference == chatHeaderIndicatorPreference &&
      other.doNotDisturbUntil == doNotDisturbUntil &&
      other.lastChatChannelId == lastChatChannelId;

  @override
  int get hashCode => Object.hash(
    username,
    id,
    name,
    avatarUrl,
    draftCount,
    canCreatePoll,
    staff,
    Object.hashAll(groups),
    hasChatEnabled,
    chatHeaderIndicatorPreference,
    doNotDisturbUntil,
    lastChatChannelId,
  );
}
