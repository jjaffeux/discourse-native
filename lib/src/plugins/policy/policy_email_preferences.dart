import 'package:discourse_native/discourse_plugin_contracts.dart';

const policyEmailSection = PreferenceSection.plugin(
  owner: 'discourse-policy',
  name: 'emails',
);

enum PolicyEmailFrequency { never, whenAway, always }

final class PolicyEmailPreferences implements UserPreferenceValues {
  const PolicyEmailPreferences(this.frequency);
  final PolicyEmailFrequency frequency;
  @override
  Map<String, Object?> get payload => {
    'policy_email_frequency': switch (frequency) {
      PolicyEmailFrequency.never => 'never',
      PolicyEmailFrequency.whenAway => 'when_away',
      PolicyEmailFrequency.always => 'always',
    },
  };
  @override
  bool operator ==(Object other) =>
      other is PolicyEmailPreferences && other.frequency == frequency;
  @override
  int get hashCode => frequency.hashCode;
}

final class PolicyEmailCodec implements UserPreferenceCodec {
  const PolicyEmailCodec();
  @override
  PreferenceSection get section => policyEmailSection;
  @override
  Set<String> get fields => const {'policy_email_frequency'};
  @override
  PolicyEmailPreferences decode(
    Map<String, dynamic> json,
    UserPreferenceValues? fallback,
  ) {
    final options = jsonObject(json['user_option']);
    final raw = options['policy_email_frequency'];
    final value = switch (raw) {
      'never' => PolicyEmailFrequency.never,
      'when_away' => PolicyEmailFrequency.whenAway,
      'always' => PolicyEmailFrequency.always,
      _ =>
        fallback is PolicyEmailPreferences
            ? fallback.frequency
            : PolicyEmailFrequency.never,
    };
    return PolicyEmailPreferences(value);
  }
}
