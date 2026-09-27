import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

const discourseAiSettingsDataKey = PluginDataKey<DiscourseAiSettings>(
  owner: 'discourse-ai',
  name: 'site-settings',
);

const discourseAiCurrentUserDataKey = PluginDataKey<DiscourseAiCurrentUser>(
  owner: 'discourse-ai',
  name: 'current-user',
);

const discourseAiSettingsPersistenceCodec =
    DiscourseAiSettingsPersistenceCodec();
const discourseAiCurrentUserPersistenceCodec =
    DiscourseAiCurrentUserPersistenceCodec();

@immutable
final class DiscourseAiSettings {
  const DiscourseAiSettings({
    required this.enabled,
    required this.helperEnabled,
    required this.helperAllowedInPrivateMessages,
    required this.helperContextMenuEnabled,
  });

  factory DiscourseAiSettings.fromWire(Map<String, dynamic> json) =>
      DiscourseAiSettings(
        enabled: json['discourse_ai_enabled'] == true,
        helperEnabled: json['ai_helper_enabled'] == true,
        helperAllowedInPrivateMessages: json['ai_helper_allowed_in_pm'] == true,
        helperContextMenuEnabled: _listSetting(
          json['ai_helper_enabled_features'],
        ).contains('context_menu'),
      );

  final bool enabled;
  final bool helperEnabled;

  /// `ai_helper_allowed_in_pm`. Only upstream's own composer enforces it: the
  /// site proofreads message text from any client that sends it.
  final bool helperAllowedInPrivateMessages;

  /// `ai_helper_enabled_features` includes `context_menu`, the composer
  /// helper through which upstream offers Proofread.
  final bool helperContextMenuEnabled;

  bool get proofreadingAvailable =>
      enabled && helperEnabled && helperContextMenuEnabled;

  @override
  bool operator ==(Object other) =>
      other is DiscourseAiSettings &&
      other.enabled == enabled &&
      other.helperEnabled == helperEnabled &&
      other.helperAllowedInPrivateMessages == helperAllowedInPrivateMessages &&
      other.helperContextMenuEnabled == helperContextMenuEnabled;

  @override
  int get hashCode => Object.hash(
    enabled,
    helperEnabled,
    helperAllowedInPrivateMessages,
    helperContextMenuEnabled,
  );
}

@immutable
final class DiscourseAiCurrentUser {
  const DiscourseAiCurrentUser({
    required this.canUseAssistant,
    required this.canProofread,
  });

  static DiscourseAiCurrentUser? fromWire(Map<String, dynamic> json) {
    if (!json.containsKey('can_use_assistant')) return null;
    final prompts = json['ai_helper_prompts'];
    return DiscourseAiCurrentUser(
      canUseAssistant: json['can_use_assistant'] == true,
      canProofread:
          prompts is List &&
          prompts.any(
            (prompt) => prompt is Map && prompt['name'] == _proofreadPrompt,
          ),
    );
  }

  static const _proofreadPrompt = 'proofread';

  final bool canUseAssistant;

  /// `ai_helper_prompts` names `proofread`. The site refuses a proofread
  /// request from anyone outside its proofreader's groups.
  final bool canProofread;

  @override
  bool operator ==(Object other) =>
      other is DiscourseAiCurrentUser &&
      other.canUseAssistant == canUseAssistant &&
      other.canProofread == canProofread;

  @override
  int get hashCode => Object.hash(canUseAssistant, canProofread);
}

final class DiscourseAiSettingsPersistenceCodec
    extends PluginDataPersistenceCodec<DiscourseAiSettings> {
  const DiscourseAiSettingsPersistenceCodec();

  @override
  PluginDataKey<DiscourseAiSettings> get key => discourseAiSettingsDataKey;

  /// A record stored before a gate was read lacks it, and keeps that gate
  /// closed until the site is fetched again.
  @override
  DiscourseAiSettings? decode(Object? value) {
    final json = jsonObjectFields(value);
    final enabled = json?['enabled'];
    final helperEnabled = json?['helperEnabled'];
    if (enabled is! bool || helperEnabled is! bool) return null;
    return DiscourseAiSettings(
      enabled: enabled,
      helperEnabled: helperEnabled,
      helperAllowedInPrivateMessages:
          json?['helperAllowedInPrivateMessages'] == true,
      helperContextMenuEnabled: json?['helperContextMenuEnabled'] == true,
    );
  }

  @override
  Object encode(DiscourseAiSettings value) => <String, Object?>{
    'enabled': value.enabled,
    'helperEnabled': value.helperEnabled,
    'helperAllowedInPrivateMessages': value.helperAllowedInPrivateMessages,
    'helperContextMenuEnabled': value.helperContextMenuEnabled,
  };
}

final class DiscourseAiCurrentUserPersistenceCodec
    extends PluginDataPersistenceCodec<DiscourseAiCurrentUser> {
  const DiscourseAiCurrentUserPersistenceCodec();

  @override
  PluginDataKey<DiscourseAiCurrentUser> get key =>
      discourseAiCurrentUserDataKey;

  /// A record stored before `canProofread` was read lacks it, and reads as
  /// not permitted until the account is fetched again.
  @override
  DiscourseAiCurrentUser? decode(Object? value) {
    final json = jsonObjectFields(value);
    final canUseAssistant = json?['canUseAssistant'];
    return canUseAssistant is bool
        ? DiscourseAiCurrentUser(
            canUseAssistant: canUseAssistant,
            canProofread: json?['canProofread'] == true,
          )
        : null;
  }

  @override
  Object encode(DiscourseAiCurrentUser value) => <String, Object?>{
    'canUseAssistant': value.canUseAssistant,
    'canProofread': value.canProofread,
  };
}

extension DiscourseAiPluginDataRead on PluginData {
  DiscourseAiSettings? get discourseAiSettings =>
      get(discourseAiSettingsDataKey);

  DiscourseAiCurrentUser? get discourseAiCurrentUser =>
      get(discourseAiCurrentUserDataKey);
}

extension DiscourseAiSiteConfigData on SiteConfig {
  DiscourseAiSettings? get discourseAiSettings => plugins.discourseAiSettings;
}

extension DiscourseAiUserData on DiscourseUser {
  DiscourseAiCurrentUser? get discourseAiCurrentUser =>
      plugins.discourseAiCurrentUser;
}

/// A list site setting arrives pipe-joined; tolerate a JSON list as well.
Iterable<String> _listSetting(Object? value) => switch (value) {
  final String value => value.split('|').map((item) => item.trim()),
  final List<dynamic> value => value.whereType<String>().map(
    (item) => item.trim(),
  ),
  _ => const <String>[],
};
