import 'package:discourse_native/discourse_plugin_sdk.dart';

final class SolvedGlobalSearch extends GlobalSearchContribution {
  const SolvedGlobalSearch() : super('discourse-solved');
  @override
  List<GlobalSearchFilter> get filters => const [
    GlobalSearchFilter(
      id: "solved",
      label: "Solution",
      scope: GlobalSearchScope.forum,
      kind: GlobalSearchFilterKind.choice,
      icon: "status",
      group: "Extensions",
      operators: [GlobalSearchFilterOperator("is", "is")],
      help:
          "Find solved topics or unsolved topics in categories that support solutions.",
      choices: [
        GlobalSearchFilterChoice(
          value: "solved",
          label: "Solved",
          token: "status:solved",
        ),
        GlobalSearchFilterChoice(
          value: "unsolved",
          label: "Unsolved",
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
