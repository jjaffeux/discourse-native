import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

const pollSettingsDataKey = PluginDataKey<PollSettings>(
  owner: 'poll',
  name: 'site-settings',
);

const pollCurrentUserDataKey = PluginDataKey<PollCurrentUser>(
  owner: 'poll',
  name: 'current-user',
);

const pollSettingsPersistenceCodec = PollSettingsPersistenceCodec();
const pollCurrentUserPersistenceCodec = PollCurrentUserPersistenceCodec();

extension PollPluginDataRead on PluginData {
  PollSettings get pollSettings =>
      get(pollSettingsDataKey) ?? const PollSettings();

  PollCurrentUser? get pollCurrentUser => get(pollCurrentUserDataKey);
}

@immutable
final class PollSettings {
  const PollSettings({
    this.enabled = true,
    this.maximumOptions = defaultMaximumOptions,
    this.defaultPublic = true,
  });

  static const int defaultMaximumOptions = 20;

  factory PollSettings.fromWire(Map<String, dynamic> json) => PollSettings(
    enabled: json['poll_enabled'] != false,
    maximumOptions: _wireMaximumOptions(json['poll_maximum_options']),
    defaultPublic: json['poll_default_public'] != false,
  );

  final bool enabled;
  final int maximumOptions;
  final bool defaultPublic;

  @override
  bool operator ==(Object other) =>
      other is PollSettings &&
      other.enabled == enabled &&
      other.maximumOptions == maximumOptions &&
      other.defaultPublic == defaultPublic;

  @override
  int get hashCode => Object.hash(enabled, maximumOptions, defaultPublic);
}

@immutable
final class PollCurrentUser {
  const PollCurrentUser({required this.canCreatePoll});

  static PollCurrentUser? fromWire(Map<String, dynamic> json) {
    if (!json.containsKey('can_create_poll')) return null;
    return PollCurrentUser(canCreatePoll: json['can_create_poll'] == true);
  }

  final bool canCreatePoll;

  @override
  bool operator ==(Object other) =>
      other is PollCurrentUser && other.canCreatePoll == canCreatePoll;

  @override
  int get hashCode => canCreatePoll.hashCode;
}

final class PollSettingsPersistenceCodec
    extends PluginDataPersistenceCodec<PollSettings> {
  const PollSettingsPersistenceCodec();

  @override
  PluginDataKey<PollSettings> get key => pollSettingsDataKey;

  @override
  PollSettings? decode(Object? value) {
    final json = jsonObjectFields(value);
    if (json == null) return null;
    return PollSettings(
      enabled: json['enabled'] != false,
      maximumOptions: _storedMaximumOptions(json['maximumOptions']),
      defaultPublic: json['defaultPublic'] != false,
    );
  }

  @override
  Object encode(PollSettings value) => <String, Object?>{
    'enabled': value.enabled,
    'maximumOptions': value.maximumOptions,
    'defaultPublic': value.defaultPublic,
  };

  @override
  PollSettings? decodeLegacy(Map<String, dynamic> json) {
    if (!json.containsKey('pollEnabled') &&
        !json.containsKey('pollMaximumOptions') &&
        !json.containsKey('pollDefaultPublic')) {
      return null;
    }
    return PollSettings(
      enabled: json['pollEnabled'] != false,
      maximumOptions: _storedMaximumOptions(json['pollMaximumOptions']),
      defaultPublic: json['pollDefaultPublic'] != false,
    );
  }
}

final class PollCurrentUserPersistenceCodec
    extends PluginDataPersistenceCodec<PollCurrentUser> {
  const PollCurrentUserPersistenceCodec();

  @override
  PluginDataKey<PollCurrentUser> get key => pollCurrentUserDataKey;

  @override
  PollCurrentUser? decode(Object? value) {
    final json = jsonObjectFields(value);
    final canCreatePoll = json?['canCreatePoll'];
    return canCreatePoll is bool
        ? PollCurrentUser(canCreatePoll: canCreatePoll)
        : null;
  }

  @override
  Object encode(PollCurrentUser value) => <String, Object?>{
    'canCreatePoll': value.canCreatePoll,
  };

  @override
  PollCurrentUser? decodeLegacy(Map<String, dynamic> json) {
    final canCreatePoll = json['canCreatePoll'];
    return canCreatePoll is bool
        ? PollCurrentUser(canCreatePoll: canCreatePoll)
        : null;
  }
}

extension PollSiteConfigData on SiteConfig {
  PollSettings get pollSettings => plugins.pollSettings;

  int get pollMaximumOptions => pollSettings.maximumOptions;

  bool get pollDefaultPublic => pollSettings.defaultPublic;
}

extension PollDiscourseUserData on DiscourseUser {
  PollCurrentUser? get pollCurrentUser => plugins.pollCurrentUser;

  bool? get canCreatePoll => pollCurrentUser?.canCreatePoll;
}

int _wireMaximumOptions(Object? value) => switch (jsonIntOrNull(value)) {
  final value? when value >= 2 => value,
  _ => PollSettings.defaultMaximumOptions,
};

int _storedMaximumOptions(Object? value) =>
    jsonIntOrNull(value) ?? PollSettings.defaultMaximumOptions;
