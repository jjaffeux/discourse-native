import 'package:flutter/foundation.dart';

import '../../models/discourse_user.dart';
import '../../models/json.dart';
import '../../models/site_config.dart';
import '../../plugin_api/plugin_data.dart';

const PluginDataKey<ChatSettings> chatSettingsDataKey = PluginDataKey(
  owner: 'chat',
  name: 'site-settings',
);

const PluginDataKey<ChatCurrentUser> chatCurrentUserDataKey = PluginDataKey(
  owner: 'chat',
  name: 'current-user',
);

const chatSettingsPersistenceCodec = ChatSettingsPersistenceCodec();
const chatCurrentUserPersistenceCodec = ChatCurrentUserPersistenceCodec();

enum ChatSeparateSidebarMode {
  siteDefault('default'),
  never('never'),
  always('always'),
  fullscreen('fullscreen');

  const ChatSeparateSidebarMode(this.wireName);

  final String wireName;

  static ChatSeparateSidebarMode readSiteSetting(Object? value) =>
      switch (_read(value)) {
        final mode? when mode != ChatSeparateSidebarMode.siteDefault => mode,
        _ => ChatSeparateSidebarMode.never,
      };

  static ChatSeparateSidebarMode readUserOption(Object? value) => value == null
      ? ChatSeparateSidebarMode.siteDefault
      : _read(value) ?? ChatSeparateSidebarMode.never;

  static ChatSeparateSidebarMode? _read(Object? value) {
    for (final mode in values) {
      if (value == mode.wireName) return mode;
    }
    return null;
  }

  ChatSeparateSidebarMode resolveAgainst(ChatSeparateSidebarMode siteSetting) =>
      switch (this) {
        ChatSeparateSidebarMode.siteDefault =>
          siteSetting == ChatSeparateSidebarMode.siteDefault
              ? ChatSeparateSidebarMode.never
              : siteSetting,
        _ => this,
      };
}

/// The server-selected landing tab for Chat when no starred channels take
/// precedence. Unknown values retain the stable Channels default.
enum ChatPreferredIndex {
  channels('channels'),
  directMessages('direct_messages'),
  myThreads('my_threads');

  const ChatPreferredIndex(this.wireName);

  final String wireName;

  static ChatPreferredIndex read(Object? value) {
    for (final index in values) {
      if (value == index.wireName) return index;
    }
    return channels;
  }
}

@immutable
final class ChatSettings {
  const ChatSettings({
    this.chatEnabled = true,
    this.uploadsEnabled = true,
    this.searchEnabled = false,
    this.publicChannelsEnabled = true,
    this.threadsEnabled = true,
    this.preferredIndex = ChatPreferredIndex.channels,
    this.channelRetentionDays = 0,
    this.directMessageRetentionDays = 0,
    this.maximumDirectMessageUsers = defaultMaximumDirectMessageUsers,
    this.separateSidebarMode = ChatSeparateSidebarMode.never,
  });

  static const int defaultMaximumDirectMessageUsers = 20;
  static const int maximumDirectMessageUsersLimit = 100;

  factory ChatSettings.fromSettings(Map<String, dynamic> json) => ChatSettings(
    chatEnabled: json['chat_enabled'] != false,
    uploadsEnabled: json['chat_allow_uploads'] != false,
    searchEnabled: json['chat_search_enabled'] == true,
    publicChannelsEnabled: json['enable_public_channels'] != false,
    threadsEnabled: json['chat_threads_enabled'] != false,
    preferredIndex: ChatPreferredIndex.read(json['chat_preferred_index']),
    channelRetentionDays: _retentionDays(json['chat_channel_retention_days']),
    directMessageRetentionDays: _retentionDays(json['chat_dm_retention_days']),
    maximumDirectMessageUsers: _maximumDirectMessageUsers(
      json['chat_max_direct_message_users'],
    ),
    separateSidebarMode: ChatSeparateSidebarMode.readSiteSetting(
      json['chat_separate_sidebar_mode'],
    ),
  );

  factory ChatSettings.fromStored(Map<String, dynamic> json) => ChatSettings(
    chatEnabled: json['chatEnabled'] != false,
    uploadsEnabled: json['uploadsEnabled'] != false,
    searchEnabled: json['searchEnabled'] == true,
    publicChannelsEnabled: json['publicChannelsEnabled'] != false,
    threadsEnabled: json['threadsEnabled'] != false,
    preferredIndex: ChatPreferredIndex.read(json['preferredIndex']),
    channelRetentionDays: _retentionDays(json['channelRetentionDays']),
    directMessageRetentionDays: _retentionDays(
      json['directMessageRetentionDays'],
    ),
    maximumDirectMessageUsers: _maximumDirectMessageUsers(
      json['maximumDirectMessageUsers'],
    ),
    separateSidebarMode: ChatSeparateSidebarMode.readSiteSetting(
      json['separateSidebarMode'],
    ),
  );

  final bool chatEnabled;
  final bool uploadsEnabled;
  final bool searchEnabled;
  final bool publicChannelsEnabled;
  final bool threadsEnabled;
  final ChatPreferredIndex preferredIndex;
  final int channelRetentionDays;
  final int directMessageRetentionDays;
  final int maximumDirectMessageUsers;
  final ChatSeparateSidebarMode separateSidebarMode;

  Map<String, Object?> toStored() => {
    if (!chatEnabled) 'chatEnabled': false,
    'uploadsEnabled': uploadsEnabled,
    'searchEnabled': searchEnabled,
    if (!publicChannelsEnabled) 'publicChannelsEnabled': false,
    if (!threadsEnabled) 'threadsEnabled': false,
    'preferredIndex': preferredIndex.wireName,
    'channelRetentionDays': channelRetentionDays,
    'directMessageRetentionDays': directMessageRetentionDays,
    'maximumDirectMessageUsers': maximumDirectMessageUsers,
    'separateSidebarMode': separateSidebarMode.wireName,
  };

  @override
  bool operator ==(Object other) =>
      other is ChatSettings &&
      other.chatEnabled == chatEnabled &&
      other.uploadsEnabled == uploadsEnabled &&
      other.searchEnabled == searchEnabled &&
      other.publicChannelsEnabled == publicChannelsEnabled &&
      other.threadsEnabled == threadsEnabled &&
      other.preferredIndex == preferredIndex &&
      other.channelRetentionDays == channelRetentionDays &&
      other.directMessageRetentionDays == directMessageRetentionDays &&
      other.maximumDirectMessageUsers == maximumDirectMessageUsers &&
      other.separateSidebarMode == separateSidebarMode;

  @override
  int get hashCode => Object.hash(
    chatEnabled,
    uploadsEnabled,
    searchEnabled,
    publicChannelsEnabled,
    threadsEnabled,
    preferredIndex,
    channelRetentionDays,
    directMessageRetentionDays,
    maximumDirectMessageUsers,
    separateSidebarMode,
  );
}

/// Preserves unknown `chat_header_indicator_preference` values as the server
/// default instead of disabling the indicator.
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

/// Nullable capabilities represent only legacy warm-start records; fresh
/// session responses resolve absent keys to false.
@immutable
final class ChatCurrentUser {
  const ChatCurrentUser({
    this.hasChatEnabled,
    this.canChat,
    this.canDirectMessage,
    this.headerIndicatorPreference = ChatHeaderIndicatorPreference.allNew,
    this.separateSidebarMode = ChatSeparateSidebarMode.siteDefault,
    this.lastChannelId,
    this.ignoredUsernames = const [],
  });

  factory ChatCurrentUser.fromCurrentUser(Map<String, dynamic> json) {
    final userOption = _jsonMap(json['user_option']) ?? const {};
    final customFields = _jsonMap(json['custom_fields']) ?? const {};
    return ChatCurrentUser(
      hasChatEnabled: json['has_chat_enabled'] == true,
      canChat: json['can_chat'] == true,
      canDirectMessage: json['can_direct_message'] == true,
      headerIndicatorPreference: ChatHeaderIndicatorPreference.read(
        userOption['chat_header_indicator_preference'],
      ),
      separateSidebarMode: ChatSeparateSidebarMode.readUserOption(
        userOption['chat_separate_sidebar_mode'],
      ),
      lastChannelId: jsonIntOrNull(customFields['last_chat_channel_id']),
      ignoredUsernames: _usernames(json['ignored_users']),
    );
  }

  factory ChatCurrentUser.fromStored(Map<String, dynamic> json) =>
      ChatCurrentUser(
        hasChatEnabled: switch (json['hasChatEnabled']) {
          final bool value => value,
          _ => null,
        },
        canChat: switch (json['canChat']) {
          final bool value => value,
          _ => null,
        },
        canDirectMessage: switch (json['canDirectMessage']) {
          final bool value => value,
          _ => null,
        },
        headerIndicatorPreference: ChatHeaderIndicatorPreference.read(
          json['headerIndicatorPreference'],
        ),
        separateSidebarMode: ChatSeparateSidebarMode.readUserOption(
          json['separateSidebarMode'],
        ),
        lastChannelId: jsonIntOrNull(json['lastChannelId']),
        ignoredUsernames: _usernames(json['ignoredUsernames']),
      );

  final bool? hasChatEnabled;
  final bool? canChat;
  final bool? canDirectMessage;
  final ChatHeaderIndicatorPreference headerIndicatorPreference;
  final ChatSeparateSidebarMode separateSidebarMode;
  final int? lastChannelId;

  final List<String> ignoredUsernames;

  Map<String, Object?> toStored() => {
    'hasChatEnabled': hasChatEnabled,
    if (canChat != null) 'canChat': canChat,
    if (canDirectMessage != null) 'canDirectMessage': canDirectMessage,
    'headerIndicatorPreference': headerIndicatorPreference.wireName,
    'separateSidebarMode': separateSidebarMode.wireName,
    'lastChannelId': lastChannelId,
    'ignoredUsernames': ignoredUsernames,
  };

  @override
  bool operator ==(Object other) =>
      other is ChatCurrentUser &&
      other.hasChatEnabled == hasChatEnabled &&
      other.canChat == canChat &&
      other.canDirectMessage == canDirectMessage &&
      other.headerIndicatorPreference == headerIndicatorPreference &&
      other.separateSidebarMode == separateSidebarMode &&
      other.lastChannelId == lastChannelId &&
      listEquals(other.ignoredUsernames, ignoredUsernames);

  @override
  int get hashCode => Object.hash(
    hasChatEnabled,
    canChat,
    canDirectMessage,
    headerIndicatorPreference,
    separateSidebarMode,
    lastChannelId,
    Object.hashAll(ignoredUsernames),
  );
}

final class ChatSettingsPersistenceCodec
    extends PluginDataPersistenceCodec<ChatSettings> {
  const ChatSettingsPersistenceCodec();

  @override
  PluginDataKey<ChatSettings> get key => chatSettingsDataKey;

  @override
  ChatSettings? decode(Object? value) {
    final json = _jsonMap(value);
    return json == null ? null : ChatSettings.fromStored(json);
  }

  @override
  Object? encode(ChatSettings value) => value.toStored();

  @override
  ChatSettings? decodeLegacy(Map<String, dynamic> json) =>
      _containsAny(json, _legacyChatSettingsKeys)
      ? ChatSettings(
          uploadsEnabled: json['chatUploadsEnabled'] != false,
          searchEnabled: json['chatSearchEnabled'] == true,
          channelRetentionDays: _retentionDays(
            json['chatChannelRetentionDays'],
          ),
          directMessageRetentionDays: _retentionDays(
            json['chatDmRetentionDays'],
          ),
          maximumDirectMessageUsers: _maximumDirectMessageUsers(
            json['chatMaximumDirectMessageUsers'],
          ),
          preferredIndex: ChatPreferredIndex.read(json['chatPreferredIndex']),
        )
      : null;
}

final class ChatCurrentUserPersistenceCodec
    extends PluginDataPersistenceCodec<ChatCurrentUser> {
  const ChatCurrentUserPersistenceCodec();

  @override
  PluginDataKey<ChatCurrentUser> get key => chatCurrentUserDataKey;

  @override
  ChatCurrentUser? decode(Object? value) {
    final json = _jsonMap(value);
    return json == null ? null : ChatCurrentUser.fromStored(json);
  }

  @override
  Object? encode(ChatCurrentUser value) => value.toStored();

  @override
  ChatCurrentUser? decodeStored({
    required Object? namespacedValue,
    required bool hasNamespacedValue,
    required Map<String, dynamic> record,
  }) {
    final decoded = super.decodeStored(
      namespacedValue: namespacedValue,
      hasNamespacedValue: hasNamespacedValue,
      record: record,
    );
    if (!hasNamespacedValue ||
        !record.containsKey('ignoredUsernames') ||
        _jsonMap(namespacedValue)?.containsKey('ignoredUsernames') == true) {
      return decoded;
    }

    return ChatCurrentUser(
      hasChatEnabled: decoded?.hasChatEnabled,
      canChat: decoded?.canChat,
      canDirectMessage: decoded?.canDirectMessage,
      headerIndicatorPreference:
          decoded?.headerIndicatorPreference ??
          ChatHeaderIndicatorPreference.allNew,
      separateSidebarMode:
          decoded?.separateSidebarMode ?? ChatSeparateSidebarMode.siteDefault,
      lastChannelId: decoded?.lastChannelId,
      ignoredUsernames: _usernames(record['ignoredUsernames']),
    );
  }

  @override
  ChatCurrentUser? decodeLegacy(Map<String, dynamic> json) =>
      _containsAny(json, _legacyChatCurrentUserKeys)
      ? ChatCurrentUser(
          hasChatEnabled: switch (json['hasChatEnabled']) {
            final bool value => value,
            _ => null,
          },
          canChat: switch (json['canChat']) {
            final bool value => value,
            _ => null,
          },
          canDirectMessage: switch (json['canDirectMessage']) {
            final bool value => value,
            _ => null,
          },
          headerIndicatorPreference: ChatHeaderIndicatorPreference.read(
            json['chatHeaderIndicatorPreference'],
          ),
          lastChannelId: jsonIntOrNull(json['lastChatChannelId']),
          ignoredUsernames: _usernames(json['ignoredUsernames']),
        )
      : null;
}

extension ChatPluginDataRead on PluginData {
  ChatSettings get chatSettings =>
      get(chatSettingsDataKey) ?? const ChatSettings();

  ChatCurrentUser? get chatCurrentUser => get(chatCurrentUserDataKey);
}

extension ChatSiteConfigData on SiteConfig {
  ChatSettings get chatSettings => plugins.chatSettings;

  bool get chatEnabled => chatSettings.chatEnabled;

  bool get chatUploadsEnabled => chatSettings.uploadsEnabled;

  bool get chatSearchEnabled => chatSettings.searchEnabled;

  ChatPreferredIndex get chatPreferredIndex => chatSettings.preferredIndex;

  int get chatChannelRetentionDays => chatSettings.channelRetentionDays;

  int get chatDmRetentionDays => chatSettings.directMessageRetentionDays;

  int get chatMaximumDirectMessageUsers =>
      chatSettings.maximumDirectMessageUsers;

  ChatSeparateSidebarMode get chatSeparateSidebarMode =>
      chatSettings.separateSidebarMode;
}

extension ChatDiscourseUserData on DiscourseUser {
  ChatCurrentUser? get chatCurrentUser => plugins.chatCurrentUser;

  bool? get hasChatEnabled => chatCurrentUser?.hasChatEnabled;

  bool? get canChat => chatCurrentUser?.canChat;

  bool? get canDirectMessage => chatCurrentUser?.canDirectMessage;

  ChatHeaderIndicatorPreference get chatHeaderIndicatorPreference =>
      chatCurrentUser?.headerIndicatorPreference ??
      ChatHeaderIndicatorPreference.allNew;

  ChatSeparateSidebarMode get chatSeparateSidebarMode =>
      chatCurrentUser?.separateSidebarMode ??
      ChatSeparateSidebarMode.siteDefault;

  int? get lastChatChannelId => chatCurrentUser?.lastChannelId;

  List<String> get ignoredUsernames =>
      chatCurrentUser?.ignoredUsernames ?? const [];
}

ChatSeparateSidebarMode effectiveChatSeparateSidebarMode({
  required ChatSettings settings,
  ChatCurrentUser? currentUser,
}) => (currentUser?.separateSidebarMode ?? ChatSeparateSidebarMode.siteDefault)
    .resolveAgainst(settings.separateSidebarMode);

const Set<String> _legacyChatSettingsKeys = {
  'chatUploadsEnabled',
  'chatSearchEnabled',
  'chatChannelRetentionDays',
  'chatDmRetentionDays',
  'chatMaximumDirectMessageUsers',
  'chatPreferredIndex',
};

const Set<String> _legacyChatCurrentUserKeys = {
  'hasChatEnabled',
  'canChat',
  'canDirectMessage',
  'chatHeaderIndicatorPreference',
  'lastChatChannelId',
  'ignoredUsernames',
};

int _retentionDays(Object? raw) => switch (jsonIntOrNull(raw)) {
  final value? when value >= 0 => value,
  _ => 0,
};

int _maximumDirectMessageUsers(Object? raw) =>
    jsonIntOrNull(raw)?.clamp(0, ChatSettings.maximumDirectMessageUsersLimit) ??
    ChatSettings.defaultMaximumDirectMessageUsers;

List<String> _usernames(Object? raw) =>
    List.unmodifiable(jsonArray(raw).map(jsonText).whereType<String>());

bool _containsAny(Map<String, dynamic> json, Set<String> keys) {
  for (final key in keys) {
    if (json.containsKey(key)) return true;
  }
  return false;
}

Map<String, dynamic>? _jsonMap(Object? value) {
  if (value is! Map) return null;
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}
