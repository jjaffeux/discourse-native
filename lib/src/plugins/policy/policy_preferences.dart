import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'policy_email_preferences.dart';

export 'policy_email_preferences.dart';

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
