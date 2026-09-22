import 'package:discourse_native/discourse_plugin_sdk.dart';

final class AssignGlobalSearch extends GlobalSearchContribution {
  const AssignGlobalSearch() : super('discourse-assign');
  @override
  List<GlobalSearchFilter> get filters => const [
    GlobalSearchFilter(
      id: "assignment",
      label: "Assignment",
      scope: GlobalSearchScope.forum,
      kind: GlobalSearchFilterKind.choice,
      icon: "user",
      group: "Extensions",
      operators: [GlobalSearchFilterOperator("is", "is")],
      help: "Requires permission to view assignments.",
      choices: [
        GlobalSearchFilterChoice(
          value: "assigned",
          label: "Assigned",
          token: "in:assigned",
        ),
        GlobalSearchFilterChoice(
          value: "unassigned",
          label: "Unassigned",
          token: "in:unassigned",
        ),
      ],
    ),
    GlobalSearchFilter(
      id: "assignee",
      lookup: GlobalSearchLookup.groups,
      singleIdentifier: true,
      rejectQuotes: true,
      label: "Assigned to",
      scope: GlobalSearchScope.forum,
      kind: GlobalSearchFilterKind.text,
      icon: "user",
      group: "Extensions",
      operators: [GlobalSearchFilterOperator("is", "is")],
      token: "assigned",
      placeholder: "Username or group name",
      help: "Find topics assigned to a person or group.",
    ),
  ];
  @override
  bool available(
    Map<String, dynamic> settings,
    Map<String, dynamic> user,
    bool authenticated,
  ) =>
      settings['assign_enabled'] == true &&
      authenticated &&
      user['can_assign_globally'] == true;
}
