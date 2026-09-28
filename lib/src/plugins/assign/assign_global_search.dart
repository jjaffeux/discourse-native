import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

final class AssignGlobalSearch extends GlobalSearchContribution {
  const AssignGlobalSearch() : super('discourse-assign');
  @override
  List<GlobalSearchFilter> get filters => [
    GlobalSearchFilter(
      id: "assignment",
      label: appL10n.assignment,
      scope: GlobalSearchScope.forum,
      kind: GlobalSearchFilterKind.choice,
      icon: "user",
      group: appL10n.extensions,
      operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
      help: appL10n.requiresPermissionToViewAssignments,
      choices: [
        GlobalSearchFilterChoice(
          value: "assigned",
          label: appL10n.assigned,
          token: "in:assigned",
        ),
        GlobalSearchFilterChoice(
          value: "unassigned",
          label: appL10n.unassigned,
          token: "in:unassigned",
        ),
      ],
    ),
    GlobalSearchFilter(
      id: "assignee",
      lookup: GlobalSearchLookup.groups,
      singleIdentifier: true,
      rejectQuotes: true,
      label: appL10n.assignedToAssignmenttopiclist,
      scope: GlobalSearchScope.forum,
      kind: GlobalSearchFilterKind.text,
      icon: "user",
      group: appL10n.extensions,
      operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
      token: "assigned",
      placeholder: appL10n.usernameOrGroupName,
      help: appL10n.findTopicsAssignedToAPersonOrGroup,
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
