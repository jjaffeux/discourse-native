import '../../data/plugin_transport.dart';
import '../../models/json.dart';
import 'assignment.dart';

final class AssignApi {
  const AssignApi(this._transport);

  final PluginApiTransport _transport;

  Future<AssignmentSuggestions> suggestions({
    required String siteUrl,
    required String apiKey,
    required AssignmentTarget target,
    String? clientId,
  }) async => AssignmentSuggestions.fromJson(
    await _transport.pluginGetJson(
      siteUrl: siteUrl,
      path: Uri(
        path: '/assign/suggestions.json',
        queryParameters: {
          'target_id': '${target.id}',
          'target_type': target.type.wireName,
        },
      ).toString(),
      apiKey: apiKey,
      clientId: clientId,
    ),
    siteUrl,
  );

  /// Search results cannot broaden the suggestion response's target-scoped
  /// user and group authority.
  Future<List<AssignmentAssignee>> searchAssignees({
    required String siteUrl,
    required String apiKey,
    required String term,
    required AssignmentSuggestions suggestions,
    int limit = 50,
    String? clientId,
  }) async {
    final boundedLimit = limit < 1 ? 1 : (limit > 50 ? 50 : limit);
    final allowedGroups = {
      for (final name in suggestions.assignAllowedForGroups)
        name.toLowerCase(): name,
    };
    final normalizedTerm = term.trim().toLowerCase();

    // Omitting an empty `groups[]` makes core UserSearch unrestricted.
    if (suggestions.assignAllowedOnGroups.isEmpty) {
      return List.unmodifiable([
        for (final user in suggestions.users)
          if (normalizedTerm.isEmpty ||
              user.username.toLowerCase().contains(normalizedTerm) ||
              (user.name?.toLowerCase().contains(normalizedTerm) ?? false))
            user,
        for (final entry in allowedGroups.entries)
          if (normalizedTerm.isEmpty || entry.key.contains(normalizedTerm))
            AssignmentGroup(name: entry.value),
      ]);
    }

    final body = await _transport.pluginGetJson(
      siteUrl: siteUrl,
      path: Uri(
        path: '/u/search/users.json',
        queryParameters: <String, dynamic>{
          'term': term,
          'include_groups': 'true',
          'assignable_groups': 'true',
          'groups[]': suggestions.assignAllowedOnGroups,
          'limit': '$boundedLimit',
        },
      ).toString(),
      apiKey: apiKey,
      clientId: clientId,
    );

    final assignees = <AssignmentAssignee>[];
    final seenUsers = <String>{};
    for (final value in jsonObjects(body['users'])) {
      final username = jsonText(value['username']);
      if (username == null || !seenUsers.add(username.toLowerCase())) continue;
      assignees.add(
        AssignmentUser(
          id: jsonIntOrNull(value['id']),
          username: username,
          name: jsonText(value['name']),
          avatarUrl: resolveAvatarUrl(
            jsonText(value['avatar_template']),
            siteUrl,
          ),
        ),
      );
    }

    final seenGroups = <String>{};
    for (final value in jsonObjects(body['groups'])) {
      final name = jsonText(value['name']);
      if (name == null) continue;
      final normalized = name.toLowerCase();
      if (!allowedGroups.containsKey(normalized) ||
          !seenGroups.add(normalized)) {
        continue;
      }
      assignees.add(
        AssignmentGroup(
          id: jsonIntOrNull(value['id']),
          name: name,
          fullName:
              jsonText(value['full_name']) ?? jsonText(value['display_name']),
        ),
      );
    }

    for (final entry in allowedGroups.entries) {
      if (seenGroups.contains(entry.key) ||
          (normalizedTerm.isNotEmpty && !entry.key.contains(normalizedTerm))) {
        continue;
      }
      seenGroups.add(entry.key);
      assignees.add(AssignmentGroup(name: entry.value));
    }

    return List.unmodifiable(assignees);
  }

  Future<void> assign({
    required String siteUrl,
    required String apiKey,
    required AssignmentTarget target,
    required AssignmentAssignee assignee,
    String? note,
    String? status,
    bool? shouldNotify,
    String? clientId,
  }) async {
    final assignment = switch (assignee) {
      AssignmentUser(:final username) when username.trim().isNotEmpty => {
        'username': username,
      },
      AssignmentGroup(name: final groupName) when groupName.trim().isNotEmpty =>
        {'group_name': groupName},
      _ => throw ArgumentError.value(
        assignee.identifier,
        'assignee',
        'An assignment assignee must have a non-empty identifier.',
      ),
    };

    await _transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: '/assign/assign.json',
      method: 'PUT',
      apiKey: apiKey,
      body: {
        'target_id': target.id,
        'target_type': target.type.wireName,
        ...assignment,
        'note': ?note,
        'status': ?status,
        // Rails treats JSON false as blank; only the string suppresses notices.
        'should_notify': ?shouldNotify?.toString(),
      },
      clientId: clientId,
    );
  }

  Future<void> unassign({
    required String siteUrl,
    required String apiKey,
    required AssignmentTarget target,
    String? clientId,
  }) async {
    await _transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: '/assign/unassign.json',
      method: 'PUT',
      apiKey: apiKey,
      body: {'target_id': target.id, 'target_type': target.type.wireName},
      clientId: clientId,
    );
  }
}
