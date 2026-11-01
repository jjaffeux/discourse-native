import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

const policyPostKey = PluginDataKey<PolicyPostData>(
  owner: 'discourse-policy',
  name: 'post',
);
const policySettingsKey = PluginDataKey<PolicySettings>(
  owner: 'discourse-policy',
  name: 'settings',
);
const policyCurrentUserKey = PluginDataKey<PolicyCurrentUser>(
  owner: 'discourse-policy',
  name: 'current-user',
);
const policySettingsPersistenceCodec = PolicySettingsPersistenceCodec();
const policyCurrentUserPersistenceCodec = PolicyCurrentUserPersistenceCodec();

extension PolicyPluginDataRead on PluginData {
  PolicyPostData? get policy => get(policyPostKey);
  PolicySettings? get policySettings => get(policySettingsKey);
  PolicyCurrentUser? get policyCurrentUser => get(policyCurrentUserKey);
}

@immutable
final class PolicySettings {
  const PolicySettings({required this.enabled});
  final bool enabled;

  static PolicySettings? fromWire(Map<String, dynamic> json) =>
      switch (json['policy_enabled']) {
        final bool enabled => PolicySettings(enabled: enabled),
        _ => null,
      };

  @override
  bool operator ==(Object other) =>
      other is PolicySettings && other.enabled == enabled;
  @override
  int get hashCode => enabled.hashCode;
}

@immutable
final class PolicyCurrentUser {
  const PolicyCurrentUser({required this.canCreate});
  final bool canCreate;

  static PolicyCurrentUser? fromWire(Map<String, dynamic> json) =>
      switch (json['can_create_policy']) {
        final bool canCreate => PolicyCurrentUser(canCreate: canCreate),
        _ => null,
      };

  @override
  bool operator ==(Object other) =>
      other is PolicyCurrentUser && other.canCreate == canCreate;
  @override
  int get hashCode => canCreate.hashCode;
}

final class PolicySettingsPersistenceCodec
    extends PluginDataPersistenceCodec<PolicySettings> {
  const PolicySettingsPersistenceCodec();
  @override
  PluginDataKey<PolicySettings> get key => policySettingsKey;
  @override
  PolicySettings? decode(Object? value) {
    final json = jsonObjectFields(value);
    final enabled = json?['enabled'];
    return enabled is bool ? PolicySettings(enabled: enabled) : null;
  }

  @override
  Object encode(PolicySettings value) => {'enabled': value.enabled};
}

final class PolicyCurrentUserPersistenceCodec
    extends PluginDataPersistenceCodec<PolicyCurrentUser> {
  const PolicyCurrentUserPersistenceCodec();
  @override
  PluginDataKey<PolicyCurrentUser> get key => policyCurrentUserKey;
  @override
  PolicyCurrentUser? decode(Object? value) {
    final json = jsonObjectFields(value);
    final canCreate = json?['canCreate'];
    return canCreate is bool ? PolicyCurrentUser(canCreate: canCreate) : null;
  }

  @override
  Object encode(PolicyCurrentUser value) => {'canCreate': value.canCreate};
}

@immutable
final class PolicyPostData {
  const PolicyPostData({
    required this.canAccept,
    required this.canRevoke,
    required this.accepted,
    required this.revoked,
    required this.statistics,
  });
  final bool canAccept;
  final bool canRevoke;
  final bool accepted;
  final bool revoked;
  final PolicyStatistics statistics;

  static PolicyPostData? fromWire(Map<String, dynamic> json, String siteUrl) {
    final canAccept = json['policy_can_accept'];
    final canRevoke = json['policy_can_revoke'];
    final accepted = json['policy_accepted'];
    final revoked = json['policy_revoked'];
    if (canAccept is! bool ||
        canRevoke is! bool ||
        accepted is! bool ||
        revoked is! bool) {
      return null;
    }
    return PolicyPostData(
      canAccept: canAccept,
      canRevoke: canRevoke,
      accepted: accepted,
      revoked: revoked,
      statistics: _statistics(json),
    );
  }

  static PolicyStatistics _statistics(Map<String, dynamic> json) {
    if (json['policy_stats'] != true) return const PolicyStatisticsHidden();
    final acceptedCount = json['policy_accepted_by_count'];
    final outstandingCount = json['policy_not_accepted_by_count'];
    final accepted = PolicyUserSummary.readList(json['policy_accepted_by']);
    final outstanding = PolicyUserSummary.readList(
      json['policy_not_accepted_by'],
    );
    if (acceptedCount is! int ||
        acceptedCount < 0 ||
        outstandingCount is! int ||
        outstandingCount < 0 ||
        accepted == null ||
        outstanding == null ||
        accepted.length > acceptedCount ||
        outstanding.length > outstandingCount) {
      return const PolicyStatisticsHidden();
    }
    return PolicyStatisticsVisible(
      acceptedCount: acceptedCount,
      outstandingCount: outstandingCount,
      acceptedPreview: accepted,
      outstandingPreview: outstanding,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PolicyPostData &&
      other.canAccept == canAccept &&
      other.canRevoke == canRevoke &&
      other.accepted == accepted &&
      other.revoked == revoked &&
      other.statistics == statistics;
  @override
  int get hashCode =>
      Object.hash(canAccept, canRevoke, accepted, revoked, statistics);
}

@immutable
sealed class PolicyStatistics {
  const PolicyStatistics();
}

final class PolicyStatisticsHidden extends PolicyStatistics {
  const PolicyStatisticsHidden();
  @override
  bool operator ==(Object other) => other is PolicyStatisticsHidden;
  @override
  int get hashCode => runtimeType.hashCode;
}

final class PolicyStatisticsVisible extends PolicyStatistics {
  PolicyStatisticsVisible({
    required this.acceptedCount,
    required this.outstandingCount,
    required List<PolicyUserSummary> acceptedPreview,
    required List<PolicyUserSummary> outstandingPreview,
  }) : acceptedPreview = List.unmodifiable(acceptedPreview),
       outstandingPreview = List.unmodifiable(outstandingPreview);
  final int acceptedCount;
  final int outstandingCount;
  final List<PolicyUserSummary> acceptedPreview;
  final List<PolicyUserSummary> outstandingPreview;
  @override
  bool operator ==(Object other) =>
      other is PolicyStatisticsVisible &&
      other.acceptedCount == acceptedCount &&
      other.outstandingCount == outstandingCount &&
      listEquals(other.acceptedPreview, acceptedPreview) &&
      listEquals(other.outstandingPreview, outstandingPreview);
  @override
  int get hashCode => Object.hash(
    acceptedCount,
    outstandingCount,
    Object.hashAll(acceptedPreview),
    Object.hashAll(outstandingPreview),
  );
}

@immutable
final class PolicyUserSummary {
  const PolicyUserSummary({
    required this.id,
    required this.username,
    required this.avatarTemplate,
    this.name,
  });
  final int id;
  final String username;
  final String avatarTemplate;
  final String? name;

  static PolicyUserSummary? fromWire(Object? value) {
    final json = jsonObjectFields(value);
    final id = json?['id'];
    final username = json?['username'];
    final avatar = json?['avatar_template'];
    final name = json?['name'];
    if (id is! int ||
        id == 0 ||
        username is! String ||
        username.isEmpty ||
        avatar is! String ||
        avatar.isEmpty ||
        (name != null && name is! String)) {
      return null;
    }
    return PolicyUserSummary(
      id: id,
      username: username,
      avatarTemplate: avatar,
      name: name as String?,
    );
  }

  static List<PolicyUserSummary>? readList(Object? value) {
    if (value is! List) return null;
    final users = <PolicyUserSummary>[];
    for (final raw in value) {
      final user = fromWire(raw);
      if (user == null) return null;
      users.add(user);
    }
    return List.unmodifiable(users);
  }

  @override
  bool operator ==(Object other) =>
      other is PolicyUserSummary &&
      other.id == id &&
      other.username == username &&
      other.avatarTemplate == avatarTemplate &&
      other.name == name;
  @override
  int get hashCode => Object.hash(id, username, avatarTemplate, name);
}
