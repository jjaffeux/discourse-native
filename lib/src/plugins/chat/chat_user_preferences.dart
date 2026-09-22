import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'chat_channel_list_preferences.dart';

enum ChatSeparateSidebarPreference {
  siteDefault('default'),
  always('always'),
  fullscreen('fullscreen'),
  never('never');

  const ChatSeparateSidebarPreference(this.wireValue);

  final String wireValue;

  static ChatSeparateSidebarPreference read(
    Object? value,
    ChatSeparateSidebarPreference fallback,
  ) {
    for (final preference in values) {
      if (value == preference.wireValue) return preference;
    }
    return fallback;
  }
}

const chatPreferenceSection = PreferenceSection.plugin(
  owner: 'chat',
  name: 'preferences',
);

final class ChatUserPreferences implements UserPreferenceValues {
  const ChatUserPreferences({
    this.separateSidebarMode = ChatSeparateSidebarPreference.siteDefault,
    this.channelList = const ChatChannelListPreferences(),
  });

  final ChatSeparateSidebarPreference separateSidebarMode;
  final ChatChannelListPreferences channelList;

  @override
  Map<String, Object?> get payload => {
    'chat_separate_sidebar_mode': separateSidebarMode.wireValue,
    ...channelList.wireValues,
  };

  @override
  bool operator ==(Object other) =>
      other is ChatUserPreferences &&
      other.separateSidebarMode == separateSidebarMode &&
      other.channelList == channelList;
  @override
  int get hashCode => Object.hash(separateSidebarMode, channelList);
}

final class ChatUserPreferenceCodec implements UserPreferenceCodec {
  const ChatUserPreferenceCodec();
  @override
  PreferenceSection get section => chatPreferenceSection;
  @override
  Set<String> get fields => {
    'chat_separate_sidebar_mode',
    for (final section in ChatChannelListSection.values) ...[
      section.filterField,
      section.sortField,
    ],
  };
  @override
  ChatUserPreferences decode(
    Map<String, dynamic> json,
    UserPreferenceValues? fallback,
  ) {
    final held = fallback is ChatUserPreferences
        ? fallback
        : const ChatUserPreferences();
    final options = jsonObject(json['user_option']);
    return ChatUserPreferences(
      separateSidebarMode: ChatSeparateSidebarPreference.read(
        options['chat_separate_sidebar_mode'],
        held.separateSidebarMode,
      ),
      channelList: ChatChannelListPreferences.read(
        options,
        fallback: held.channelList,
      ),
    );
  }
}

extension ChatPreferences on UserPreferences {
  ChatUserPreferences get chatPreferences =>
      pluginValues['chat/preferences'] as ChatUserPreferences? ??
      const ChatUserPreferences();

  UserPreferences withChatPreferences({
    ChatSeparateSidebarPreference? separateSidebarMode,
    ChatChannelListPreferences? channelList,
  }) => copyWith(
    pluginValues: {
      ...pluginValues,
      'chat/preferences': ChatUserPreferences(
        separateSidebarMode:
            separateSidebarMode ?? chatPreferences.separateSidebarMode,
        channelList: channelList ?? chatPreferences.channelList,
      ),
    },
  );
}
