import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/policy/policy_data.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> flags() => {
  'policy_can_accept': true,
  'policy_can_revoke': false,
  'policy_accepted': false,
  'policy_revoked': false,
};
Map<String, dynamic> user(int id) => {
  'id': id,
  'username': 'member$id',
  'avatar_template': '/avatar/{size}/$id.png',
};
void main() {
  test('record absence and malformed flags never grant policy authority', () {
    expect(PolicyPostData.fromWire({}, 'https://example.com'), isNull);
    for (final key in flags().keys) {
      final missing = flags()..remove(key);
      expect(PolicyPostData.fromWire(missing, 'https://example.com'), isNull);
      final malformed = flags()..[key] = 'true';
      expect(PolicyPostData.fromWire(malformed, 'https://example.com'), isNull);
    }
  });
  test('hidden statistics cannot disclose stray arrays or appear empty', () {
    final policy = PolicyPostData.fromWire({
      ...flags(),
      'policy_accepted_by': [user(1)],
      'policy_accepted_by_count': 1,
    }, 'https://example.com')!;
    expect(policy.canAccept, isTrue);
    expect(policy.statistics, const PolicyStatisticsHidden());
    final empty = PolicyPostData.fromWire({
      ...flags(),
      'policy_stats': true,
      'policy_accepted_by': <Object?>[],
      'policy_not_accepted_by': <Object?>[],
      'policy_accepted_by_count': 0,
      'policy_not_accepted_by_count': 0,
    }, 'https://example.com')!;
    final stats = empty.statistics as PolicyStatisticsVisible;
    expect(stats.acceptedCount, 0);
    expect(stats.outstandingCount, 0);
  });
  test(
    'malformed disclosed statistics fail closed without inventing users',
    () {
      final policy = PolicyPostData.fromWire({
        ...flags(),
        'policy_stats': true,
        'policy_accepted_by': [
          user(1),
          {'id': 2},
        ],
        'policy_not_accepted_by': <Object?>[],
        'policy_accepted_by_count': 2,
        'policy_not_accepted_by_count': 0,
      }, 'https://example.com')!;
      expect(policy.statistics, const PolicyStatisticsHidden());
    },
  );
  test(
    'accepted counts and users remain independent of outstanding audience',
    () {
      final policy = PolicyPostData.fromWire({
        ...flags(),
        'policy_can_revoke': true,
        'policy_accepted': true,
        'policy_stats': true,
        'policy_accepted_by': [user(-1), user(4)],
        'policy_not_accepted_by': [user(5)],
        'policy_accepted_by_count': 36,
        'policy_not_accepted_by_count': 7,
      }, 'https://example.com')!;
      expect(policy.canAccept, isTrue);
      expect(policy.canRevoke, isTrue);
      final stats = policy.statistics as PolicyStatisticsVisible;
      expect(stats.acceptedPreview.map((u) => u.id), [-1, 4]);
      expect(stats.acceptedCount, 36);
      expect(stats.outstandingCount, 7);
      expect(() => stats.acceptedPreview.clear(), throwsUnsupportedError);
    },
  );
  test(
    'settings and creation permission distinguish absent, false and true',
    () {
      expect(PolicySettings.fromWire({}), isNull);
      expect(PolicySettings.fromWire({'policy_enabled': 'true'}), isNull);
      expect(
        PolicySettings.fromWire({'policy_enabled': false}),
        const PolicySettings(enabled: false),
      );
      expect(PolicyCurrentUser.fromWire({}), isNull);
      expect(
        PolicyCurrentUser.fromWire({'can_create_policy': true}),
        const PolicyCurrentUser(canCreate: true),
      );
      expect(
        PolicyCurrentUser.fromWire({'can_create_policy': false}),
        const PolicyCurrentUser(canCreate: false),
      );
      expect(PluginData.none.policy, isNull);
      expect(PluginData.none.policySettings, isNull);
    },
  );
  test(
    'owned persistence codecs round trip and reject malformed authority',
    () {
      const settings = PolicySettings(enabled: false);
      const permission = PolicyCurrentUser(canCreate: true);
      expect(
        policySettingsPersistenceCodec.decode(
          policySettingsPersistenceCodec.encode(settings),
        ),
        settings,
      );
      expect(
        policyCurrentUserPersistenceCodec.decode(
          policyCurrentUserPersistenceCodec.encode(permission),
        ),
        permission,
      );
      expect(policySettingsPersistenceCodec.decode({'enabled': 1}), isNull);
      expect(
        policyCurrentUserPersistenceCodec.decode({'canCreate': 'true'}),
        isNull,
      );
    },
  );
}
