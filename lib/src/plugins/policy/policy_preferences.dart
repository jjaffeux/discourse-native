import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

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

Widget policyEmailPreference(
  BuildContext context,
  PluginUserPreferenceContext state,
) {
  final value =
      (state.preferences.pluginValues[policyEmailSection.id]
              as PolicyEmailPreferences?)
          ?.frequency ??
      PolicyEmailFrequency.never;
  return DField(
    children: [
      DSelect<PolicyEmailFrequency>(
        value: value,
        label: Text(context.l10n.policyEmailLabel),
        isExpanded: true,
        enabled: state.editable,
        entries: [
          DSelectItem(
            value: PolicyEmailFrequency.never,
            child: Text(context.l10n.policyEmailNever),
            textValue: context.l10n.policyEmailNever,
          ),
          DSelectItem(
            value: PolicyEmailFrequency.whenAway,
            child: Text(context.l10n.policyEmailAway),
            textValue: context.l10n.policyEmailAway,
          ),
          DSelectItem(
            value: PolicyEmailFrequency.always,
            child: Text(context.l10n.policyEmailAlways),
            textValue: context.l10n.policyEmailAlways,
          ),
        ],
        onChanged: (next) {
          if (next == null) return;
          state.onEdit(
            policyEmailSection,
            (current) => current.copyWith(
              pluginValues: {
                ...current.pluginValues,
                policyEmailSection.id: PolicyEmailPreferences(next),
              },
            ),
          );
        },
      ),
      if (value != PolicyEmailFrequency.never)
        DFieldDescription(
          child: Text(
            value == PolicyEmailFrequency.whenAway
                ? context.l10n.policyEmailAwayHelp
                : context.l10n.policyEmailAlwaysHelp,
          ),
        ),
    ],
  );
}
