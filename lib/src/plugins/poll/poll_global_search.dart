import 'package:discourse_native/discourse_plugin_sdk.dart';

final class PollGlobalSearch extends GlobalSearchContribution {
  const PollGlobalSearch() : super('poll');
  @override
  List<GlobalSearchFilter> get filters => const [
    GlobalSearchFilter(
      id: "polls",
      label: "Polls",
      scope: GlobalSearchScope.forum,
      kind: GlobalSearchFilterKind.choice,
      icon: "status",
      group: "Extensions",
      operators: [GlobalSearchFilterOperator("is", "is")],
      help: "Find posts containing polls.",
      choices: [
        GlobalSearchFilterChoice(
          value: "polls",
          label: "Contains a poll",
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
