import 'package:flutter/foundation.dart';

import '../../models/discourse_user.dart';
import '../../models/json.dart';
import '../../models/site_config.dart';
import '../../plugin_api/site_plugin_api.dart';

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

/// Poll's client settings from `/site/settings.json`.
@immutable
final class PollSettings {
  const PollSettings({
    this.maximumOptions = defaultMaximumOptions,
    this.defaultPublic = true,
  });

  static const int defaultMaximumOptions = 20;

  factory PollSettings.fromWire(Map<String, dynamic> json) => PollSettings(
    maximumOptions: _wireMaximumOptions(json['poll_maximum_options']),
    defaultPublic: json['poll_default_public'] != false,
  );

  final int maximumOptions;
  final bool defaultPublic;

  @override
  bool operator ==(Object other) =>
      other is PollSettings &&
      other.maximumOptions == maximumOptions &&
      other.defaultPublic == defaultPublic;

  @override
  int get hashCode => Object.hash(maximumOptions, defaultPublic);
}

/// Poll's capability fields from `/session/current.json`.
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

/// The namespaced warm-start representation of [PollSettings].
final class PollSettingsPersistenceCodec
    extends PluginDataPersistenceCodec<PollSettings> {
  const PollSettingsPersistenceCodec();

  @override
  PluginDataKey<PollSettings> get key => pollSettingsDataKey;

  @override
  PollSettings? decode(Object? value) {
    final json = _objectFields(value);
    if (json == null) return null;
    return PollSettings(
      maximumOptions: _storedMaximumOptions(json['maximumOptions']),
      defaultPublic: json['defaultPublic'] != false,
    );
  }

  @override
  Object encode(PollSettings value) => <String, Object?>{
    'maximumOptions': value.maximumOptions,
    'defaultPublic': value.defaultPublic,
  };

  @override
  PollSettings? decodeLegacy(Map<String, dynamic> json) {
    if (!json.containsKey('pollMaximumOptions') &&
        !json.containsKey('pollDefaultPublic')) {
      return null;
    }
    return PollSettings(
      maximumOptions: _storedMaximumOptions(json['pollMaximumOptions']),
      defaultPublic: json['pollDefaultPublic'] != false,
    );
  }
}

/// The namespaced warm-start representation of [PollCurrentUser].
final class PollCurrentUserPersistenceCodec
    extends PluginDataPersistenceCodec<PollCurrentUser> {
  const PollCurrentUserPersistenceCodec();

  @override
  PluginDataKey<PollCurrentUser> get key => pollCurrentUserDataKey;

  @override
  PollCurrentUser? decode(Object? value) {
    final json = _objectFields(value);
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

/// Source-compatible Poll settings access for plugin-owned UI.
extension PollSiteConfigData on SiteConfig {
  PollSettings get pollSettings => plugins.pollSettings;

  int get pollMaximumOptions => pollSettings.maximumOptions;

  bool get pollDefaultPublic => pollSettings.defaultPublic;
}

/// Source-compatible Poll capability access for plugin-owned UI.
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

Map<String, Object?>? _objectFields(Object? value) {
  if (value is! Map) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}
