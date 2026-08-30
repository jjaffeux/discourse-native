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

/// The client-marked Chat settings used by native Chat surfaces.
@immutable
final class ChatSettings {
  const ChatSettings({
    this.uploadsEnabled = true,
    this.searchEnabled = false,
    this.channelRetentionDays = 0,
    this.directMessageRetentionDays = 0,
  });

  factory ChatSettings.fromSettings(Map<String, dynamic> json) => ChatSettings(
    uploadsEnabled: json['chat_allow_uploads'] != false,
    searchEnabled: json['chat_search_enabled'] == true,
    channelRetentionDays: _retentionDays(json['chat_channel_retention_days']),
    directMessageRetentionDays: _retentionDays(json['chat_dm_retention_days']),
  );

  factory ChatSettings.fromStored(Map<String, dynamic> json) => ChatSettings(
    uploadsEnabled: json['uploadsEnabled'] != false,
    searchEnabled: json['searchEnabled'] == true,
    channelRetentionDays: _retentionDays(json['channelRetentionDays']),
    directMessageRetentionDays: _retentionDays(
      json['directMessageRetentionDays'],
    ),
  );

  final bool uploadsEnabled;
  final bool searchEnabled;
  final int channelRetentionDays;
  final int directMessageRetentionDays;

  Map<String, Object?> toStored() => {
    'uploadsEnabled': uploadsEnabled,
    'searchEnabled': searchEnabled,
    'channelRetentionDays': channelRetentionDays,
    'directMessageRetentionDays': directMessageRetentionDays,
  };

  @override
  bool operator ==(Object other) =>
      other is ChatSettings &&
      other.uploadsEnabled == uploadsEnabled &&
      other.searchEnabled == searchEnabled &&
      other.channelRetentionDays == channelRetentionDays &&
      other.directMessageRetentionDays == directMessageRetentionDays;

  @override
  int get hashCode => Object.hash(
    uploadsEnabled,
    searchEnabled,
    channelRetentionDays,
    directMessageRetentionDays,
  );
}

/// Which Chat activity the account wants called out on the header shortcut.
///
/// These are the four values Chat serializes from
/// `UserOption#chat_header_indicator_preference`. Unknown values retain the
/// server's default behavior rather than silently disabling the indicator.
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

/// Chat's contribution to `/session/current.json`.
///
/// [hasChatEnabled] and [canDirectMessage] are nullable only for a warm-start
/// account stored before those capabilities were persisted. A fresh response
/// resolves absent wire keys to false, matching Chat's serializer contract.
@immutable
final class ChatCurrentUser {
  const ChatCurrentUser({
    this.hasChatEnabled,
    this.canDirectMessage,
    this.headerIndicatorPreference = ChatHeaderIndicatorPreference.allNew,
    this.lastChannelId,
    this.ignoredUsernames = const [],
  });

  factory ChatCurrentUser.fromCurrentUser(Map<String, dynamic> json) {
    final userOption = _jsonMap(json['user_option']) ?? const {};
    final customFields = _jsonMap(json['custom_fields']) ?? const {};
    return ChatCurrentUser(
      hasChatEnabled: json['has_chat_enabled'] == true,
      canDirectMessage: json['can_direct_message'] == true,
      headerIndicatorPreference: ChatHeaderIndicatorPreference.read(
        userOption['chat_header_indicator_preference'],
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
        canDirectMessage: switch (json['canDirectMessage']) {
          final bool value => value,
          _ => null,
        },
        headerIndicatorPreference: ChatHeaderIndicatorPreference.read(
          json['headerIndicatorPreference'],
        ),
        lastChannelId: jsonIntOrNull(json['lastChannelId']),
        ignoredUsernames: _usernames(json['ignoredUsernames']),
      );

  final bool? hasChatEnabled;
  final bool? canDirectMessage;
  final ChatHeaderIndicatorPreference headerIndicatorPreference;
  final int? lastChannelId;

  /// Usernames whose messages must not contribute Chat unread state.
  final List<String> ignoredUsernames;

  Map<String, Object?> toStored() => {
    'hasChatEnabled': hasChatEnabled,
    if (canDirectMessage != null) 'canDirectMessage': canDirectMessage,
    'headerIndicatorPreference': headerIndicatorPreference.wireName,
    'lastChannelId': lastChannelId,
    'ignoredUsernames': ignoredUsernames,
  };

  @override
  bool operator ==(Object other) =>
      other is ChatCurrentUser &&
      other.hasChatEnabled == hasChatEnabled &&
      other.canDirectMessage == canDirectMessage &&
      other.headerIndicatorPreference == headerIndicatorPreference &&
      other.lastChannelId == lastChannelId &&
      listEquals(other.ignoredUsernames, ignoredUsernames);

  @override
  int get hashCode => Object.hash(
    hasChatEnabled,
    canDirectMessage,
    headerIndicatorPreference,
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
      canDirectMessage: decoded?.canDirectMessage,
      headerIndicatorPreference:
          decoded?.headerIndicatorPreference ??
          ChatHeaderIndicatorPreference.allNew,
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

  bool get chatUploadsEnabled => chatSettings.uploadsEnabled;

  bool get chatSearchEnabled => chatSettings.searchEnabled;

  int get chatChannelRetentionDays => chatSettings.channelRetentionDays;

  int get chatDmRetentionDays => chatSettings.directMessageRetentionDays;
}

extension ChatDiscourseUserData on DiscourseUser {
  ChatCurrentUser? get chatCurrentUser => plugins.chatCurrentUser;

  bool? get hasChatEnabled => chatCurrentUser?.hasChatEnabled;

  bool? get canDirectMessage => chatCurrentUser?.canDirectMessage;

  ChatHeaderIndicatorPreference get chatHeaderIndicatorPreference =>
      chatCurrentUser?.headerIndicatorPreference ??
      ChatHeaderIndicatorPreference.allNew;

  int? get lastChatChannelId => chatCurrentUser?.lastChannelId;

  List<String> get ignoredUsernames =>
      chatCurrentUser?.ignoredUsernames ?? const [];
}

const Set<String> _legacyChatSettingsKeys = {
  'chatUploadsEnabled',
  'chatSearchEnabled',
  'chatChannelRetentionDays',
  'chatDmRetentionDays',
};

const Set<String> _legacyChatCurrentUserKeys = {
  'hasChatEnabled',
  'canDirectMessage',
  'chatHeaderIndicatorPreference',
  'lastChatChannelId',
  'ignoredUsernames',
};

int _retentionDays(Object? raw) => switch (jsonIntOrNull(raw)) {
  final value? when value >= 0 => value,
  _ => 0,
};

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
