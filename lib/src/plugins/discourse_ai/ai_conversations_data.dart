import 'package:discourse_native/discourse_plugin_sdk.dart';

const aiBotSettingsKey = PluginDataKey<AiBotSettings>(
  owner: 'discourse-ai',
  name: 'bot-settings',
);
const aiBotUserKey = PluginDataKey<AiBotUser>(
  owner: 'discourse-ai',
  name: 'bot-user',
);

final class AiBotSettings {
  const AiBotSettings({required this.enabled});
  final bool enabled;
  @override
  bool operator ==(Object other) =>
      other is AiBotSettings && other.enabled == enabled;
  @override
  int get hashCode => enabled.hashCode;
}

final class AiBotUser {
  const AiBotUser({required this.hasPersonalMessageBot});
  final bool hasPersonalMessageBot;

  // The two serializers cover group-enabled LLM bots and individually allowed
  // PM agents. Only ai_bot_allowed_groups members receive
  // ai_enabled_chat_bots. Servers whose agents carry their bot `user_id`
  // require that membership for agent PMs too; older servers allowed agents
  // outside the groups.
  factory AiBotUser.fromWire(Map<String, dynamic> json) {
    final inBotGroups = json.containsKey('ai_enabled_chat_bots');
    return AiBotUser(
      hasPersonalMessageBot:
          jsonObjects(json['ai_enabled_chat_bots']).any(
            (bot) =>
                bot['is_agent'] != true &&
                jsonInt(bot['id']) != 0 &&
                (jsonText(bot['username'])?.isNotEmpty ?? false),
          ) ||
          jsonObjects(json['ai_enabled_agents']).any(
            (agent) =>
                agent['allow_personal_messages'] == true &&
                (jsonText(agent['username'])?.isNotEmpty ?? false) &&
                (inBotGroups || !agent.containsKey('user_id')),
          ),
    );
  }
  @override
  bool operator ==(Object other) =>
      other is AiBotUser &&
      other.hasPersonalMessageBot == hasPersonalMessageBot;
  @override
  int get hashCode => hasPersonalMessageBot.hashCode;
}

final class AiBotSettingsCodec
    extends PluginDataPersistenceCodec<AiBotSettings> {
  const AiBotSettingsCodec();
  @override
  PluginDataKey<AiBotSettings> get key => aiBotSettingsKey;
  @override
  AiBotSettings? decode(Object? value) {
    final json = jsonObjectFields(value);
    return json == null
        ? null
        : AiBotSettings(enabled: json['enabled'] == true);
  }

  @override
  Object encode(AiBotSettings value) => {'enabled': value.enabled};
}

final class AiBotUserCodec extends PluginDataPersistenceCodec<AiBotUser> {
  const AiBotUserCodec();
  @override
  PluginDataKey<AiBotUser> get key => aiBotUserKey;
  @override
  AiBotUser? decode(Object? value) {
    final json = jsonObjectFields(value);
    return json == null
        ? null
        : AiBotUser(
            hasPersonalMessageBot: json['hasPersonalMessageBot'] == true,
          );
  }

  @override
  Object encode(AiBotUser value) => {
    'hasPersonalMessageBot': value.hasPersonalMessageBot,
  };
}

bool aiConversationsAvailable(SiteConfig config, DiscourseUser? user) =>
    config.plugins.get(aiBotSettingsKey)?.enabled == true &&
    user?.plugins.get(aiBotUserKey)?.hasPersonalMessageBot == true;
