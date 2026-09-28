import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

final class SolvedGlobalSearch extends GlobalSearchContribution {
  const SolvedGlobalSearch() : super('discourse-solved');
  @override
  List<GlobalSearchFilter> get filters => [
    GlobalSearchFilter(
      id: "solved",
      label: appL10n.solution,
      scope: GlobalSearchScope.forum,
      kind: GlobalSearchFilterKind.choice,
      icon: "status",
      group: appL10n.extensions,
      operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
      help: appL10n
          .findSolvedTopicsOrUnsolvedTopicsInCategoriesThatSupportSolutions,
      choices: [
        GlobalSearchFilterChoice(
          value: "solved",
          label: appL10n.solved,
          token: "status:solved",
        ),
        GlobalSearchFilterChoice(
          value: "unsolved",
          label: appL10n.unsolved,
          token: "status:unsolved",
        ),
      ],
    ),
  ];
  @override
  bool available(
    Map<String, dynamic> settings,
    Map<String, dynamic> user,
    bool authenticated,
  ) => settings['solved_enabled'] == true;
}
