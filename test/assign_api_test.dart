import 'package:discourse_native/src/data/plugin_transport.dart';
import 'package:discourse_native/src/plugins/assign/assign_api.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RecordingPluginTransport implements PluginApiTransport {
  Map<String, dynamic> getResponse = const {};
  final List<String> getPaths = [];
  final List<
    ({String path, String method, Map<String, Object?> body, String? clientId})
  >
  writes = [];

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    getPaths.add(path);
    return getResponse;
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    writes.add((path: path, method: method, body: body, clientId: clientId));
    return const {'success': 'OK'};
  }
}

void main() {
  const siteUrl = 'https://meta.example.com';
  const apiKey = 'secret';

  test('suggestions are scoped to the exact post target', () async {
    final transport = _RecordingPluginTransport()
      ..getResponse = {
        'assign_allowed_on_groups': ['staff'],
        'assign_allowed_for_groups': ['triage'],
        'suggestions': [
          {'id': 1, 'username': 'sam'},
        ],
      };
    final api = AssignApi(transport);

    final result = await api.suggestions(
      siteUrl: siteUrl,
      apiKey: apiKey,
      target: const AssignmentTarget.post(71, topicId: 42),
      clientId: 'client',
    );

    final uri = Uri.parse(transport.getPaths.single);
    expect(uri.path, '/assign/suggestions.json');
    expect(uri.queryParameters, {'target_id': '71', 'target_type': 'Post'});
    expect(result.users.single.username, 'sam');
    expect(result.assignAllowedOnGroups, ['staff']);
    expect(result.assignAllowedForGroups, ['triage']);
  });

  test(
    'search keeps the target restrictions and merges direct groups',
    () async {
      final transport = _RecordingPluginTransport()
        ..getResponse = {
          'users': [
            {
              'id': 1,
              'username': 'sam',
              'name': 'Sam',
              'avatar_template': '/sam/{size}.png',
            },
            {'id': 1, 'username': 'SAM'},
            {'id': 2},
          ],
          'groups': [
            {'id': 7, 'name': 'staff', 'full_name': 'Site Staff'},
            {'id': 8, 'name': 'admins'},
            {'id': 7, 'name': 'STAFF'},
          ],
        };
      final api = AssignApi(transport);
      final scope = AssignmentSuggestions(
        assignAllowedOnGroups: const ['engineering', 'support'],
        assignAllowedForGroups: const ['triage', 'staff'],
      );

      final result = await api.searchAssignees(
        siteUrl: siteUrl,
        apiKey: apiKey,
        term: '',
        suggestions: scope,
        limit: 500,
      );

      final uri = Uri.parse(transport.getPaths.single);
      expect(uri.path, '/u/search/users.json');
      expect(uri.queryParameters['term'], '');
      expect(uri.queryParameters['include_groups'], 'true');
      expect(uri.queryParameters['assignable_groups'], 'true');
      expect(uri.queryParameters['limit'], '50');
      expect(uri.queryParametersAll['groups[]'], ['engineering', 'support']);
      expect(result, const [
        AssignmentUser(
          id: 1,
          username: 'sam',
          name: 'Sam',
          avatarUrl: '$siteUrl/sam/90.png',
        ),
        AssignmentGroup(id: 7, name: 'staff', fullName: 'Site Staff'),
        AssignmentGroup(name: 'triage'),
      ]);
    },
  );

  test(
    'an empty user-group scope never broadens search beyond direct groups',
    () async {
      final transport = _RecordingPluginTransport();
      final api = AssignApi(transport);
      final scope = AssignmentSuggestions(
        users: const [AssignmentUser(username: 'triage-helper')],
        assignAllowedForGroups: const ['triage', 'support'],
      );

      final result = await api.searchAssignees(
        siteUrl: siteUrl,
        apiKey: apiKey,
        term: 'tri',
        suggestions: scope,
      );

      expect(transport.getPaths, isEmpty);
      expect(result, const [
        AssignmentUser(username: 'triage-helper'),
        AssignmentGroup(name: 'triage'),
      ]);
    },
  );

  test('assign writes exactly one assignee and exact target type', () async {
    final transport = _RecordingPluginTransport();
    final api = AssignApi(transport);

    await api.assign(
      siteUrl: siteUrl,
      apiKey: apiKey,
      target: const AssignmentTarget.topic(42),
      assignee: const AssignmentUser(username: 'sam'),
      note: '',
      status: '',
      shouldNotify: false,
      clientId: 'client',
    );
    await api.assign(
      siteUrl: siteUrl,
      apiKey: apiKey,
      target: const AssignmentTarget.post(71, topicId: 42),
      assignee: const AssignmentGroup(name: 'triage'),
    );

    expect(transport.writes[0].path, '/assign/assign.json');
    expect(transport.writes[0].method, 'PUT');
    expect(transport.writes[0].clientId, 'client');
    expect(transport.writes[0].body, {
      'target_id': 42,
      'target_type': 'Topic',
      'username': 'sam',
      'note': '',
      'status': '',
      // A string is required because Rails treats the JSON boolean false as
      // blank and otherwise turns notifications back on.
      'should_notify': 'false',
    });
    expect(transport.writes[1].body, {
      'target_id': 71,
      'target_type': 'Post',
      'group_name': 'triage',
    });
  });

  test('unassign removes only the exact topic or post target', () async {
    final transport = _RecordingPluginTransport();
    final api = AssignApi(transport);

    await api.unassign(
      siteUrl: siteUrl,
      apiKey: apiKey,
      target: const AssignmentTarget.topic(42),
    );
    await api.unassign(
      siteUrl: siteUrl,
      apiKey: apiKey,
      target: const AssignmentTarget.post(71, topicId: 42),
    );

    expect(transport.writes.map((write) => '${write.method} ${write.path}'), [
      'PUT /assign/unassign.json',
      'PUT /assign/unassign.json',
    ]);
    expect(transport.writes[0].body, {'target_id': 42, 'target_type': 'Topic'});
    expect(transport.writes[1].body, {'target_id': 71, 'target_type': 'Post'});
  });

  test('an empty assignee is rejected before writing', () async {
    final transport = _RecordingPluginTransport();
    final api = AssignApi(transport);

    await expectLater(
      api.assign(
        siteUrl: siteUrl,
        apiKey: apiKey,
        target: const AssignmentTarget.topic(42),
        assignee: const AssignmentUser(username: '   '),
      ),
      throwsArgumentError,
    );
    expect(transport.writes, isEmpty);
  });
}
