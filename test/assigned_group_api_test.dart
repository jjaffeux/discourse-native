import 'package:discourse_native/src/data/plugin_transport.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group_api.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RecordingTransport implements PluginApiTransport {
  Map<String, dynamic> response = const {};
  final List<String> paths = [];

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    paths.add(path);
    return response;
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) => throw UnimplementedError();
}

void main() {
  const siteUrl = 'https://meta.example.com';
  final models = DiscourseModelCodec(
    extensions: PluginRegistry.validated(const [AssignPlugin()]),
  );

  test('member request encodes paging and parses counts and users', () async {
    final transport = _RecordingTransport()
      ..response = {
        'members': [
          {
            'id': 7,
            'username': 'Sam',
            'username_lower': 'sam',
            'name': 'Sam Example',
            'avatar_template': '/sam/{size}.png',
            'assignments_count': 9,
          },
        ],
        'assignment_count': 11,
        'group_assignment_count': 2,
      };
    final api = AssignedGroupApiClient(transport, models);

    final page = await api.members(
      siteUrl: siteUrl,
      apiKey: 'key',
      groupName: 'team+ops',
      search: ' Sam ',
      offset: 50,
      limit: 25,
      clientId: 'client',
    );

    final uri = Uri.parse(transport.paths.single);
    expect(uri.path, '/assign/members/team%2Bops.json');
    expect(uri.queryParameters, {
      'offset': '50',
      'limit': '25',
      'filter': 'Sam',
    });
    expect(page.assignmentCount, 11);
    expect(page.groupAssignmentCount, 2);
    expect(page.members.single.usernameLower, 'sam');
  });

  test('filters map to exact endpoints and direct query semantics', () async {
    final transport = _RecordingTransport()
      ..response = {
        'topic_list': {
          'topics': [
            {
              'id': 42,
              'title': 'Assigned topic',
              'slug': 'assigned-topic',
              'can_assign': true,
              'assigned_to_group': {'name': 'support'},
            },
          ],
        },
      };
    final api = AssignedGroupApiClient(transport, models);

    final everyone = await api.topics(
      siteUrl: siteUrl,
      apiKey: 'key',
      groupName: 'support',
      filter: const AssignedGroupFilter.everyone(),
    );
    await api.topics(
      siteUrl: siteUrl,
      apiKey: 'key',
      groupName: 'support',
      filter: const AssignedGroupFilter.directGroup(),
      query: const AssignedGroupTopicQuery(
        order: AssignedGroupOrder.views,
        ascending: true,
        search: ' incident ',
      ),
    );
    await api.topics(
      siteUrl: siteUrl,
      apiKey: 'key',
      groupName: 'support',
      filter: AssignedGroupFilter.member('Sam'),
    );

    expect(
      Uri.parse(transport.paths[0]).path,
      '/topics/group-topics-assigned/support.json',
    );
    expect(Uri.parse(transport.paths[0]).queryParameters, isEmpty);
    expect(Uri.parse(transport.paths[1]).queryParameters, {
      'direct': 'true',
      'order': 'views',
      'ascending': 'true',
      'search': 'incident',
    });
    expect(
      Uri.parse(transport.paths[2]).path,
      '/topics/messages-assigned/sam.json',
    );
    expect(Uri.parse(transport.paths[2]).queryParameters, {'direct': 'true'});

    final assignments = everyone.topics.single.plugins.get(assignmentsDataKey);
    expect(assignments?.canAssign, isTrue);
    expect(
      assignments?.direct?.assignee,
      const AssignmentGroup(name: 'support'),
    );
  });

  test('topic pagination accepts only safe relative cursors', () async {
    final transport = _RecordingTransport()
      ..response = const {'topic_list': <String, dynamic>{}};
    final api = AssignedGroupApiClient(transport, models);

    await api.topicPage(
      siteUrl: siteUrl,
      apiKey: 'key',
      path: '/topics/group-topics-assigned/support?page=1',
    );
    expect(
      transport.paths.single,
      '/topics/group-topics-assigned/support.json?page=1',
    );
    expect(
      () => api.topicPage(
        siteUrl: siteUrl,
        apiKey: 'key',
        path: 'https://elsewhere.example/topics.json',
      ),
      throwsArgumentError,
    );
  });
}
