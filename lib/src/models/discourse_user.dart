import 'package:flutter/foundation.dart';

import '../plugin_api/plugin_data.dart';
import 'bookmark.dart';
import 'json.dart';
import 'sidebar_tag.dart';
import 'user_status.dart';

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
    this.canChangePostOwner = false,
    this.admin = false,
    this.staff = false,
    this.whisperer = false,
    this.canSendPrivateMessages = false,
    this.groups = const [],
    this.messageGroupNames = const [],
    this.sidebarCategoryIds = const [],
    this.sidebarTags = const [],
    this.displaySidebarTags = false,
    this.trackedCategoryIds,
    this.watchedCategoryIds,
    this.watchedFirstPostCategoryIds,
    this.doNotDisturbUntil,
    this.doNotDisturbChannelPosition,
    this.timezone,
    this.hidePresence,
    this.bookmarkAutoDeletePreference =
        BookmarkAutoDeletePreference.clearReminder,
    this.plugins = PluginData.none,
  });

  factory DiscourseUser.fromJson(
    Map<String, dynamic> json, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) => DiscourseUser(
    username: json['username'] as String,
    // Absent from anything stored before the live counters needed it, which is
    // why it is nullable rather than required — see `ShellController`, which
    // asks the site again when it finds one missing.
    id: jsonIntOrNull(json['id']),
    name: json['name'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    status: _storedStatus(json['status']),
    draftCount: jsonInt(json['draftCount']),
    canChangePostOwner: json['canChangePostOwner'] == true,
    admin: json['admin'] == true,
    staff: json['staff'] == true,
    whisperer: json['whisperer'] == true,
    canSendPrivateMessages: json['canSendPrivateMessages'] == true,
    groups: List.unmodifiable(
      jsonArray(json['groups']).map(jsonText).whereType<String>(),
    ),
    messageGroupNames: List.unmodifiable(
      jsonArray(json['messageGroupNames']).map(jsonText).whereType<String>(),
    ),
    sidebarCategoryIds: List.unmodifiable([
      for (final value in jsonArray(json['sidebarCategoryIds']))
        ?jsonIntOrNull(value),
    ]),
    sidebarTags: List.unmodifiable([
      for (final value in jsonArray(json['sidebarTags']))
        ?SidebarTag.fromJson(value),
    ]),
    displaySidebarTags: json['displaySidebarTags'] == true,
    trackedCategoryIds: _storedCategoryIds(json, 'trackedCategoryIds'),
    watchedCategoryIds: _storedCategoryIds(json, 'watchedCategoryIds'),
    watchedFirstPostCategoryIds: _storedCategoryIds(
      json,
      'watchedFirstPostCategoryIds',
    ),
    doNotDisturbUntil: jsonDate(json['doNotDisturbUntil']),
    doNotDisturbChannelPosition: jsonIntOrNull(
      json['doNotDisturbChannelPosition'],
    ),
    timezone: json['timezone'] as String?,
    // Null distinguishes an account stored before this preference was retained
    // from the server-confirmed "online" value false.
    hidePresence: json['hidePresence'] as bool?,
    bookmarkAutoDeletePreference: BookmarkAutoDeletePreference.read(
      json['bookmarkAutoDeletePreference'],
    ),
    plugins: extensions.readStoredCurrentUser(json),
  );

  final String username;

  /// The account's own id, which is how Discourse names the message_bus
  /// channels it publishes a user's counts on.
  final int? id;

  final String? name;
  final String? avatarUrl;
  final UserStatus? status;
  final int draftCount;

  /// Core's account-level guardian for reassigning post authorship.
  final bool canChangePostOwner;

  /// Administrators have access to group inboxes even without membership.
  final bool admin;

  /// Whether the current account is an administrator or moderator.
  final bool staff;

  /// Core's guardian-approved capability for creating staff-only replies.
  ///
  /// This is intentionally not inferred from [staff]: sites may grant whisper
  /// access to any configured group through `whispers_allowed_groups`.
  final bool whisperer;

  /// The server guardian's account-level private-message capability.
  final bool canSendPrivateMessages;

  /// Group names from the freshly loaded current-user payload.
  final List<String> groups;

  /// Groups whose private-message inboxes this account may enter.
  ///
  /// Discourse marks these with `has_messages` in the current-user payload.
  /// Keeping the narrower list separate prevents ordinary group membership
  /// from being presented as an inbox the server will refuse.
  final List<String> messageGroupNames;

  /// The categories this account chose for its sidebar. Core derives display
  /// order from the site's category ordering rather than this list's order.
  final List<int> sidebarCategoryIds;

  /// The tags this account chose for its navigation sidebar.
  ///
  /// An empty list means core falls back to the site's top tags. The separate
  /// [displaySidebarTags] flag retains the server's permission-aware answer to
  /// whether the section itself is meaningful when that fallback is empty.
  final List<SidebarTag> sidebarTags;
  final bool displaySidebarTags;

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

  /// While this lies in the future Discourse suppresses the header indicator.
  final DateTime? doNotDisturbUntil;

  /// Snapshot cursor for the account's private Do Not Disturb channel.
  final int? doNotDisturbChannelPosition;

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

  /// Values decoded by the installed feature manifest. Core intentionally
  /// cannot name or interpret anything in this bag.
  final PluginData plugins;

  bool get isInDoNotDisturb =>
      doNotDisturbUntil?.isAfter(DateTime.now()) ?? false;

  Map<String, dynamic> toJson({
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    final pluginJson = extensions.writeStoredCurrentUser(plugins);
    return {
      'username': username,
      'id': id,
      'name': name,
      'avatarUrl': avatarUrl,
      'status': status?.toJson(),
      'draftCount': draftCount,
      'canChangePostOwner': canChangePostOwner,
      'admin': admin,
      'staff': staff,
      'whisperer': whisperer,
      'canSendPrivateMessages': canSendPrivateMessages,
      'groups': groups,
      'messageGroupNames': messageGroupNames,
      'sidebarCategoryIds': sidebarCategoryIds,
      'sidebarTags': [for (final tag in sidebarTags) tag.toJson()],
      'displaySidebarTags': displaySidebarTags,
      if (trackedCategoryIds != null) 'trackedCategoryIds': trackedCategoryIds,
      if (watchedCategoryIds != null) 'watchedCategoryIds': watchedCategoryIds,
      if (watchedFirstPostCategoryIds != null)
        'watchedFirstPostCategoryIds': watchedFirstPostCategoryIds,
      'doNotDisturbUntil': doNotDisturbUntil?.toIso8601String(),
      'doNotDisturbChannelPosition': doNotDisturbChannelPosition,
      'timezone': timezone,
      if (hidePresence != null) 'hidePresence': hidePresence,
      'bookmarkAutoDeletePreference': bookmarkAutoDeletePreference.wireValue,
      if (pluginJson.isNotEmpty) 'plugins': pluginJson,
    };
  }

  /// Display name if the site has one, otherwise the username.
  String get displayName => (name?.isNotEmpty ?? false) ? name! : username;

  DiscourseUser withStatus(UserStatus? status) => DiscourseUser(
    username: username,
    id: id,
    name: name,
    avatarUrl: avatarUrl,
    status: status,
    draftCount: draftCount,
    canChangePostOwner: canChangePostOwner,
    admin: admin,
    staff: staff,
    whisperer: whisperer,
    canSendPrivateMessages: canSendPrivateMessages,
    groups: groups,
    messageGroupNames: messageGroupNames,
    sidebarCategoryIds: sidebarCategoryIds,
    sidebarTags: sidebarTags,
    displaySidebarTags: displaySidebarTags,
    trackedCategoryIds: trackedCategoryIds,
    watchedCategoryIds: watchedCategoryIds,
    watchedFirstPostCategoryIds: watchedFirstPostCategoryIds,
    doNotDisturbUntil: doNotDisturbUntil,
    doNotDisturbChannelPosition: doNotDisturbChannelPosition,
    timezone: timezone,
    hidePresence: hidePresence,
    bookmarkAutoDeletePreference: bookmarkAutoDeletePreference,
    plugins: plugins,
  );

  DiscourseUser withDoNotDisturbUntil(DateTime? until) => DiscourseUser(
    username: username,
    id: id,
    name: name,
    avatarUrl: avatarUrl,
    status: status,
    draftCount: draftCount,
    canChangePostOwner: canChangePostOwner,
    admin: admin,
    staff: staff,
    whisperer: whisperer,
    canSendPrivateMessages: canSendPrivateMessages,
    groups: groups,
    messageGroupNames: messageGroupNames,
    sidebarCategoryIds: sidebarCategoryIds,
    sidebarTags: sidebarTags,
    displaySidebarTags: displaySidebarTags,
    trackedCategoryIds: trackedCategoryIds,
    watchedCategoryIds: watchedCategoryIds,
    watchedFirstPostCategoryIds: watchedFirstPostCategoryIds,
    doNotDisturbUntil: until,
    doNotDisturbChannelPosition: doNotDisturbChannelPosition,
    timezone: timezone,
    hidePresence: hidePresence,
    bookmarkAutoDeletePreference: bookmarkAutoDeletePreference,
    plugins: plugins,
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
    canChangePostOwner: canChangePostOwner,
    admin: admin,
    staff: staff,
    whisperer: whisperer,
    canSendPrivateMessages: canSendPrivateMessages,
    groups: groups,
    messageGroupNames: messageGroupNames,
    sidebarCategoryIds: sidebarCategoryIds,
    sidebarTags: sidebarTags,
    displaySidebarTags: displaySidebarTags,
    trackedCategoryIds: trackedCategoryIds,
    watchedCategoryIds: watchedCategoryIds,
    watchedFirstPostCategoryIds: watchedFirstPostCategoryIds,
    doNotDisturbUntil: doNotDisturbUntil,
    doNotDisturbChannelPosition: doNotDisturbChannelPosition,
    timezone: timezone ?? this.timezone,
    hidePresence: hidePresence,
    bookmarkAutoDeletePreference:
        bookmarkAutoDeletePreference ?? this.bookmarkAutoDeletePreference,
    plugins: plugins,
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
    canChangePostOwner: canChangePostOwner,
    admin: admin,
    staff: staff,
    whisperer: whisperer,
    canSendPrivateMessages: canSendPrivateMessages,
    groups: groups,
    messageGroupNames: messageGroupNames,
    sidebarCategoryIds: sidebarCategoryIds,
    sidebarTags: sidebarTags,
    displaySidebarTags: displaySidebarTags,
    trackedCategoryIds: trackedCategoryIds,
    watchedCategoryIds: watchedCategoryIds,
    watchedFirstPostCategoryIds: watchedFirstPostCategoryIds,
    doNotDisturbUntil: doNotDisturbUntil,
    doNotDisturbChannelPosition: doNotDisturbChannelPosition,
    timezone: timezone,
    hidePresence: hidePresence,
    bookmarkAutoDeletePreference: bookmarkAutoDeletePreference,
    plugins: plugins,
  );

  DiscourseUser withPlugins(PluginData value) => DiscourseUser(
    username: username,
    id: id,
    name: name,
    avatarUrl: avatarUrl,
    status: status,
    draftCount: draftCount,
    canChangePostOwner: canChangePostOwner,
    admin: admin,
    staff: staff,
    whisperer: whisperer,
    canSendPrivateMessages: canSendPrivateMessages,
    groups: groups,
    messageGroupNames: messageGroupNames,
    sidebarCategoryIds: sidebarCategoryIds,
    sidebarTags: sidebarTags,
    displaySidebarTags: displaySidebarTags,
    trackedCategoryIds: trackedCategoryIds,
    watchedCategoryIds: watchedCategoryIds,
    watchedFirstPostCategoryIds: watchedFirstPostCategoryIds,
    doNotDisturbUntil: doNotDisturbUntil,
    doNotDisturbChannelPosition: doNotDisturbChannelPosition,
    timezone: timezone,
    hidePresence: hidePresence,
    bookmarkAutoDeletePreference: bookmarkAutoDeletePreference,
    plugins: value,
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
      other.canChangePostOwner == canChangePostOwner &&
      other.admin == admin &&
      other.staff == staff &&
      other.whisperer == whisperer &&
      other.canSendPrivateMessages == canSendPrivateMessages &&
      listEquals(other.groups, groups) &&
      listEquals(other.messageGroupNames, messageGroupNames) &&
      listEquals(other.sidebarCategoryIds, sidebarCategoryIds) &&
      listEquals(other.sidebarTags, sidebarTags) &&
      other.displaySidebarTags == displaySidebarTags &&
      listEquals(other.trackedCategoryIds, trackedCategoryIds) &&
      listEquals(other.watchedCategoryIds, watchedCategoryIds) &&
      listEquals(
        other.watchedFirstPostCategoryIds,
        watchedFirstPostCategoryIds,
      ) &&
      other.doNotDisturbUntil == doNotDisturbUntil &&
      other.doNotDisturbChannelPosition == doNotDisturbChannelPosition &&
      other.timezone == timezone &&
      other.hidePresence == hidePresence &&
      other.bookmarkAutoDeletePreference == bookmarkAutoDeletePreference &&
      other.plugins == plugins;

  @override
  int get hashCode => Object.hashAll([
    username,
    id,
    name,
    avatarUrl,
    status,
    draftCount,
    canChangePostOwner,
    admin,
    staff,
    whisperer,
    canSendPrivateMessages,
    Object.hashAll(groups),
    Object.hashAll(messageGroupNames),
    Object.hashAll(sidebarCategoryIds),
    Object.hashAll(sidebarTags),
    displaySidebarTags,
    Object.hashAll(trackedCategoryIds ?? const <int>[]),
    Object.hashAll(watchedCategoryIds ?? const <int>[]),
    Object.hashAll(watchedFirstPostCategoryIds ?? const <int>[]),
    doNotDisturbUntil,
    doNotDisturbChannelPosition,
    timezone,
    hidePresence,
    bookmarkAutoDeletePreference,
    plugins,
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
