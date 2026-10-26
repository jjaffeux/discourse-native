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
      lookup: GlobalSearchLookup.contributed,
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

  /// `assigned:` matches a username before a group name, so suggest both, as
  /// the web's advanced search does.
  @override
  Future<List<GlobalSearchFilterChoice>> lookup(
    GlobalSearchReadContext context,
    GlobalSearchFilter filter,
    String term,
  ) async {
    if (!context.authenticated || filter.id != 'assignee') return const [];
    final body = await context.get(
      Uri(
        path: '/u/search/users.json',
        queryParameters: {
          'term': term,
          'include_groups': 'true',
          'assignable_groups': 'true',
          'limit': '20',
        },
      ).toString(),
    );
    return [
      for (final row in jsonObjects(body['users']))
        if (jsonText(row['username']) case final username?)
          GlobalSearchFilterChoice(
            value: username,
            label: jsonText(row['name']) ?? username,
          ),
      for (final row in jsonObjects(body['groups']))
        if (jsonText(row['name']) case final name?)
          GlobalSearchFilterChoice(
            value: name,
            label: jsonText(row['full_name']) ?? name,
          ),
    ].take(30).toList(growable: false);
  }
}
