import 'package:flutter/foundation.dart';

import '../plugin_api/plugin_data.dart';
import 'bookmark.dart';
import 'json.dart';
import 'sidebar_tag.dart';
import 'user_status.dart';

@immutable
class DiscourseUser {
  const DiscourseUser({
    required this.username,
    this.id,
    this.name,
    this.avatarUrl,
    this.status,
    this.draftCount = 0,
    this.canCreateTopic = false,
    this.canCreateGroup = false,
    this.canChangePostOwner = false,
    this.admin = false,
    this.staff = false,
    this.whisperer = false,
    this.canSendPrivateMessages = false,
    this.canInviteToForum = false,
    this.groups = const [],
    this.messageGroupNames = const [],
    this.sidebarCategoryIds = const [],
    this.sidebarTags = const [],
    this.displaySidebarTags = false,
    this.unifiedNewEnabled = false,
    this.sidebarShowCountOfNewItems = false,
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
    // Null in older snapshots forces the shell to refresh live counters.
    id: jsonIntOrNull(json['id']),
    name: json['name'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    status: _storedStatus(json['status']),
    draftCount: jsonInt(json['draftCount']),
    canCreateTopic: json['canCreateTopic'] == true,
    canCreateGroup: json['canCreateGroup'] == true,
    canChangePostOwner: json['canChangePostOwner'] == true,
    admin: json['admin'] == true,
    staff: json['staff'] == true,
    whisperer: json['whisperer'] == true,
    canSendPrivateMessages: json['canSendPrivateMessages'] == true,
    canInviteToForum: json['canInviteToForum'] == true,
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
    unifiedNewEnabled: json['unifiedNewEnabled'] == true,
    sidebarShowCountOfNewItems: json['sidebarShowCountOfNewItems'] == true,
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
    // Null distinguishes an old snapshot from a server-confirmed false.
    hidePresence: json['hidePresence'] as bool?,
    bookmarkAutoDeletePreference: BookmarkAutoDeletePreference.read(
      json['bookmarkAutoDeletePreference'],
    ),
    plugins: extensions.readStoredCurrentUser(json),
  );

  final String username;

  final int? id;

  final String? name;
  final String? avatarUrl;
  final UserStatus? status;
  final int draftCount;

  final bool canCreateTopic;

  final bool canCreateGroup;

  final bool canChangePostOwner;

  final bool admin;

  final bool staff;

  final bool whisperer;

  final bool canSendPrivateMessages;

  final bool canInviteToForum;

  final List<String> groups;

  final List<String> messageGroupNames;

  final List<int> sidebarCategoryIds;

  final List<SidebarTag> sidebarTags;
  final bool displaySidebarTags;

  final bool unifiedNewEnabled;

  final bool sidebarShowCountOfNewItems;

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

  final DateTime? doNotDisturbUntil;

  final int? doNotDisturbChannelPosition;

  final String? timezone;

  final bool? hidePresence;

  final BookmarkAutoDeletePreference bookmarkAutoDeletePreference;

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
      'canCreateTopic': canCreateTopic,
      'canCreateGroup': canCreateGroup,
      'canChangePostOwner': canChangePostOwner,
      'admin': admin,
      'staff': staff,
      'whisperer': whisperer,
      'canSendPrivateMessages': canSendPrivateMessages,
      'canInviteToForum': canInviteToForum,
      'groups': groups,
      'messageGroupNames': messageGroupNames,
      'sidebarCategoryIds': sidebarCategoryIds,
      'sidebarTags': [for (final tag in sidebarTags) tag.toJson()],
      'displaySidebarTags': displaySidebarTags,
      'unifiedNewEnabled': unifiedNewEnabled,
      'sidebarShowCountOfNewItems': sidebarShowCountOfNewItems,
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

  String get displayName => (name?.isNotEmpty ?? false) ? name! : username;

  DiscourseUser withStatus(UserStatus? status) => DiscourseUser(
    username: username,
    id: id,
    name: name,
    avatarUrl: avatarUrl,
    status: status,
    draftCount: draftCount,
    canCreateTopic: canCreateTopic,
    canCreateGroup: canCreateGroup,
    canChangePostOwner: canChangePostOwner,
    admin: admin,
    staff: staff,
    whisperer: whisperer,
    canSendPrivateMessages: canSendPrivateMessages,
    canInviteToForum: canInviteToForum,
    groups: groups,
    messageGroupNames: messageGroupNames,
    sidebarCategoryIds: sidebarCategoryIds,
    sidebarTags: sidebarTags,
    displaySidebarTags: displaySidebarTags,
    unifiedNewEnabled: unifiedNewEnabled,
    sidebarShowCountOfNewItems: sidebarShowCountOfNewItems,
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
    canCreateTopic: canCreateTopic,
    canCreateGroup: canCreateGroup,
    canChangePostOwner: canChangePostOwner,
    admin: admin,
    staff: staff,
    whisperer: whisperer,
    canSendPrivateMessages: canSendPrivateMessages,
    canInviteToForum: canInviteToForum,
    groups: groups,
    messageGroupNames: messageGroupNames,
    sidebarCategoryIds: sidebarCategoryIds,
    sidebarTags: sidebarTags,
    displaySidebarTags: displaySidebarTags,
    unifiedNewEnabled: unifiedNewEnabled,
    sidebarShowCountOfNewItems: sidebarShowCountOfNewItems,
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
    canCreateTopic: canCreateTopic,
    canCreateGroup: canCreateGroup,
    canChangePostOwner: canChangePostOwner,
    admin: admin,
    staff: staff,
    whisperer: whisperer,
    canSendPrivateMessages: canSendPrivateMessages,
    canInviteToForum: canInviteToForum,
    groups: groups,
    messageGroupNames: messageGroupNames,
    sidebarCategoryIds: sidebarCategoryIds,
    sidebarTags: sidebarTags,
    displaySidebarTags: displaySidebarTags,
    unifiedNewEnabled: unifiedNewEnabled,
    sidebarShowCountOfNewItems: sidebarShowCountOfNewItems,
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

  DiscourseUser withHidePresence(bool? hidePresence) => DiscourseUser(
    username: username,
    id: id,
    name: name,
    avatarUrl: avatarUrl,
    status: status,
    draftCount: draftCount,
    canCreateTopic: canCreateTopic,
    canCreateGroup: canCreateGroup,
    canChangePostOwner: canChangePostOwner,
    admin: admin,
    staff: staff,
    whisperer: whisperer,
    canSendPrivateMessages: canSendPrivateMessages,
    canInviteToForum: canInviteToForum,
    groups: groups,
    messageGroupNames: messageGroupNames,
    sidebarCategoryIds: sidebarCategoryIds,
    sidebarTags: sidebarTags,
    displaySidebarTags: displaySidebarTags,
    unifiedNewEnabled: unifiedNewEnabled,
    sidebarShowCountOfNewItems: sidebarShowCountOfNewItems,
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
    canCreateTopic: canCreateTopic,
    canCreateGroup: canCreateGroup,
    canChangePostOwner: canChangePostOwner,
    admin: admin,
    staff: staff,
    whisperer: whisperer,
    canSendPrivateMessages: canSendPrivateMessages,
    canInviteToForum: canInviteToForum,
    groups: groups,
    messageGroupNames: messageGroupNames,
    sidebarCategoryIds: sidebarCategoryIds,
    sidebarTags: sidebarTags,
    displaySidebarTags: displaySidebarTags,
    unifiedNewEnabled: unifiedNewEnabled,
    sidebarShowCountOfNewItems: sidebarShowCountOfNewItems,
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
      other.canCreateTopic == canCreateTopic &&
      other.canCreateGroup == canCreateGroup &&
      other.canChangePostOwner == canChangePostOwner &&
      other.admin == admin &&
      other.staff == staff &&
      other.whisperer == whisperer &&
      other.canSendPrivateMessages == canSendPrivateMessages &&
      other.canInviteToForum == canInviteToForum &&
      listEquals(other.groups, groups) &&
      listEquals(other.messageGroupNames, messageGroupNames) &&
      listEquals(other.sidebarCategoryIds, sidebarCategoryIds) &&
      listEquals(other.sidebarTags, sidebarTags) &&
      other.displaySidebarTags == displaySidebarTags &&
      other.unifiedNewEnabled == unifiedNewEnabled &&
      other.sidebarShowCountOfNewItems == sidebarShowCountOfNewItems &&
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
    canCreateTopic,
    canCreateGroup,
    canChangePostOwner,
    admin,
    staff,
    whisperer,
    canSendPrivateMessages,
    canInviteToForum,
    Object.hashAll(groups),
    Object.hashAll(messageGroupNames),
    Object.hashAll(sidebarCategoryIds),
    Object.hashAll(sidebarTags),
    displaySidebarTags,
    unifiedNewEnabled,
    sidebarShowCountOfNewItems,
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
