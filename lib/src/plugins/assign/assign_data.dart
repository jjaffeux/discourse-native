import 'package:flutter/foundation.dart';

import '../../models/discourse_user.dart';
import '../../models/json.dart';
import '../../models/site_config.dart';
import '../../plugin_api/site_plugin_api.dart';

const assignSettingsDataKey = PluginDataKey<AssignSettings>(
  owner: 'discourse-assign',
  name: 'site-settings',
);

const assignCurrentUserDataKey = PluginDataKey<AssignCurrentUser>(
  owner: 'discourse-assign',
  name: 'current-user',
);

const assignSettingsPersistenceCodec = AssignSettingsPersistenceCodec();
const assignCurrentUserPersistenceCodec = AssignCurrentUserPersistenceCodec();

@immutable
final class AssignSettings {
  const AssignSettings({
    this.statusesEnabled = false,
    this.statuses = const [],
  });

  factory AssignSettings.fromWire(Map<String, dynamic> json) {
    final enabled = json['enable_assign_status'] == true;
    return AssignSettings(
      statusesEnabled: enabled,
      statuses: enabled ? _stringList(json['assign_statuses']) : const [],
    );
  }

  final bool statusesEnabled;
  final List<String> statuses;

  @override
  bool operator ==(Object other) =>
      other is AssignSettings &&
      other.statusesEnabled == statusesEnabled &&
      listEquals(other.statuses, statuses);

  @override
  int get hashCode => Object.hash(statusesEnabled, Object.hashAll(statuses));
}

@immutable
final class AssignCurrentUser {
  const AssignCurrentUser({this.canAssign, this.canAssignGlobally});

  static AssignCurrentUser? fromWire(Map<String, dynamic> json) {
    final hasCanAssign = json.containsKey('can_assign');
    final hasCanAssignGlobally = json.containsKey('can_assign_globally');
    if (!hasCanAssign && !hasCanAssignGlobally) return null;
    return AssignCurrentUser(
      canAssign: hasCanAssign ? json['can_assign'] == true : null,
      canAssignGlobally: hasCanAssignGlobally
          ? json['can_assign_globally'] == true
          : null,
    );
  }

  final bool? canAssign;
  final bool? canAssignGlobally;

  @override
  bool operator ==(Object other) =>
      other is AssignCurrentUser &&
      other.canAssign == canAssign &&
      other.canAssignGlobally == canAssignGlobally;

  @override
  int get hashCode => Object.hash(canAssign, canAssignGlobally);
}

final class AssignSettingsPersistenceCodec
    extends PluginDataPersistenceCodec<AssignSettings> {
  const AssignSettingsPersistenceCodec();

  @override
  PluginDataKey<AssignSettings> get key => assignSettingsDataKey;

  @override
  AssignSettings? decode(Object? value) {
    final json = jsonObjectFields(value);
    if (json == null) return null;
    final enabled = json['statusesEnabled'] == true;
    return AssignSettings(
      statusesEnabled: enabled,
      statuses: _stringList(json['statuses']),
    );
  }

  @override
  Object encode(AssignSettings value) => <String, Object?>{
    'statusesEnabled': value.statusesEnabled,
    'statuses': value.statuses,
  };

  @override
  AssignSettings? decodeLegacy(Map<String, dynamic> json) {
    if (!json.containsKey('assignStatusesEnabled') &&
        !json.containsKey('assignStatuses')) {
      return null;
    }
    final enabled = json['assignStatusesEnabled'] == true;
    return AssignSettings(
      statusesEnabled: enabled,
      statuses: _stringList(json['assignStatuses']),
    );
  }
}

final class AssignCurrentUserPersistenceCodec
    extends PluginDataPersistenceCodec<AssignCurrentUser> {
  const AssignCurrentUserPersistenceCodec();

  @override
  PluginDataKey<AssignCurrentUser> get key => assignCurrentUserDataKey;

  @override
  AssignCurrentUser? decode(Object? value) {
    final json = jsonObjectFields(value);
    if (json == null) return null;
    final canAssign = json['canAssign'];
    final canAssignGlobally = json['canAssignGlobally'];
    if (canAssign is! bool && canAssignGlobally is! bool) return null;
    return AssignCurrentUser(
      canAssign: canAssign is bool ? canAssign : null,
      canAssignGlobally: canAssignGlobally is bool ? canAssignGlobally : null,
    );
  }

  @override
  Object encode(AssignCurrentUser value) => <String, Object?>{
    if (value.canAssign != null) 'canAssign': value.canAssign,
    if (value.canAssignGlobally != null)
      'canAssignGlobally': value.canAssignGlobally,
  };

  @override
  AssignCurrentUser? decodeLegacy(Map<String, dynamic> json) {
    final canAssign = json['canAssign'];
    final canAssignGlobally = json['canAssignGlobally'];
    if (canAssign is! bool && canAssignGlobally is! bool) return null;
    return AssignCurrentUser(
      canAssign: canAssign is bool ? canAssign : null,
      canAssignGlobally: canAssignGlobally is bool ? canAssignGlobally : null,
    );
  }
}

extension AssignSiteConfigData on SiteConfig {
  AssignSettings get assignSettings =>
      plugins.get(assignSettingsDataKey) ?? const AssignSettings();

  bool get assignStatusesEnabled => assignSettings.statusesEnabled;

  List<String> get assignStatuses => assignSettings.statuses;
}

extension AssignDiscourseUserData on DiscourseUser {
  AssignCurrentUser? get assignCurrentUser =>
      plugins.get(assignCurrentUserDataKey);

  bool? get canAssign => assignCurrentUser?.canAssign;

  bool? get canAssignGlobally => assignCurrentUser?.canAssignGlobally;
}

List<String> _stringList(Object? value) {
  final values = switch (value) {
    final String value => value.split('|'),
    final List<dynamic> value => value.whereType<String>(),
    _ => const <String>[],
  };
  return List.unmodifiable(
    values.map((value) => value.trim()).where((value) => value.isNotEmpty),
  );
}
