import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

final class PollGlobalSearch extends GlobalSearchContribution {
  const PollGlobalSearch() : super('poll');
  @override
  List<GlobalSearchFilter> get filters => [
    GlobalSearchFilter(
      id: "polls",
      label: appL10n.polls,
      scope: GlobalSearchScope.forum,
      kind: GlobalSearchFilterKind.choice,
      icon: "status",
      group: appL10n.extensions,
      operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
      help: appL10n.findPostsContainingPolls,
      choices: [
        GlobalSearchFilterChoice(
          value: "polls",
          label: appL10n.containsAPoll,
          token: "in:polls",
        ),
      ],
    ),
  ];
  @override
  bool available(
    Map<String, dynamic> settings,
    Map<String, dynamic> user,
    bool authenticated,
  ) => settings['poll_enabled'] == true;
}
