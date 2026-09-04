import 'package:flutter/foundation.dart';

import '../../models/discourse_user.dart';
import '../../models/json.dart';
import '../../models/site_config.dart';
import '../../plugin_api/site_plugin_api.dart';

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
  });

  factory DiscourseAiSettings.fromWire(Map<String, dynamic> json) =>
      DiscourseAiSettings(
        enabled: json['discourse_ai_enabled'] == true,
        helperEnabled: json['ai_helper_enabled'] == true,
      );

  final bool enabled;
  final bool helperEnabled;

  bool get proofreadingAvailable => enabled && helperEnabled;

  @override
  bool operator ==(Object other) =>
      other is DiscourseAiSettings &&
      other.enabled == enabled &&
      other.helperEnabled == helperEnabled;

  @override
  int get hashCode => Object.hash(enabled, helperEnabled);
}

@immutable
final class DiscourseAiCurrentUser {
  const DiscourseAiCurrentUser({required this.canUseAssistant});

  static DiscourseAiCurrentUser? fromWire(Map<String, dynamic> json) {
    if (!json.containsKey('can_use_assistant')) return null;
    return DiscourseAiCurrentUser(
      canUseAssistant: json['can_use_assistant'] == true,
    );
  }

  final bool canUseAssistant;

  @override
  bool operator ==(Object other) =>
      other is DiscourseAiCurrentUser &&
      other.canUseAssistant == canUseAssistant;

  @override
  int get hashCode => canUseAssistant.hashCode;
}

final class DiscourseAiSettingsPersistenceCodec
    extends PluginDataPersistenceCodec<DiscourseAiSettings> {
  const DiscourseAiSettingsPersistenceCodec();

  @override
  PluginDataKey<DiscourseAiSettings> get key => discourseAiSettingsDataKey;

  @override
  DiscourseAiSettings? decode(Object? value) {
    final json = jsonObjectFields(value);
    final enabled = json?['enabled'];
    final helperEnabled = json?['helperEnabled'];
    if (enabled is! bool || helperEnabled is! bool) return null;
    return DiscourseAiSettings(enabled: enabled, helperEnabled: helperEnabled);
  }

  @override
  Object encode(DiscourseAiSettings value) => <String, Object?>{
    'enabled': value.enabled,
    'helperEnabled': value.helperEnabled,
  };
}

final class DiscourseAiCurrentUserPersistenceCodec
    extends PluginDataPersistenceCodec<DiscourseAiCurrentUser> {
  const DiscourseAiCurrentUserPersistenceCodec();

  @override
  PluginDataKey<DiscourseAiCurrentUser> get key =>
      discourseAiCurrentUserDataKey;

  @override
  DiscourseAiCurrentUser? decode(Object? value) {
    final canUseAssistant = jsonObjectFields(value)?['canUseAssistant'];
    return canUseAssistant is bool
        ? DiscourseAiCurrentUser(canUseAssistant: canUseAssistant)
        : null;
  }

  @override
  Object encode(DiscourseAiCurrentUser value) => <String, Object?>{
    'canUseAssistant': value.canUseAssistant,
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
