import 'package:discourse_native/src/data/groups_api.dart';
import 'package:discourse_native/src/data/plugin_transport.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const siteUrl = 'https://forum.example';

  test(
    'directory and detail use public reads and preserve query semantics',
    () async {
      final transport = _RecordingTransport()
        ..getResponse = {
          'groups': [
            {'id': 1, 'name': 'team+ops', 'user_count': 3},
          ],
          'total_rows_groups': 1,
        };
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

      final directory = await api.directory(
        siteUrl: siteUrl,
        page: 2,
        filter: ' support ',
        type: 'my',
        order: 'user_count',
        ascending: false,
        username: 'sam',
      );

      final directoryUri = Uri.parse(transport.gets.single.path);
      expect(directoryUri.path, '/groups.json');
      expect(directoryUri.queryParameters, {
        'page': '2',
        'filter': 'support',
        'type': 'my',
        'order': 'user_count',
        'asc': 'false',
        'username': 'sam',
      });
      expect(transport.gets.single.apiKey, isNull);
      expect(directory.groups.single.name, 'team+ops');

      transport.getResponse = {
        'group': {'id': 1, 'name': 'team+ops'},
        'extras': {
          'visible_group_names': ['team+ops'],
        },
      };
      final detail = await api.detail(
        siteUrl: siteUrl,
        groupName: 'team+ops',
        apiKey: 'secret',
      );

      expect(transport.gets.last.path, '/groups/team%2Bops.json');
      expect(detail.visibleGroupNames, ['team+ops']);
    },
  );

  test(
    'member, requester, activity, and log reads map exact filters',
    () async {
      final transport = _RecordingTransport();
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

      transport.getResponse = {
        'members': [
          {'id': 2, 'username': 'sam'},
        ],
        'owners': <Map<String, Object?>>[],
        'meta': {'total': 1, 'limit': 25, 'offset': 50},
      };
      final members = await api.members(
        siteUrl: siteUrl,
        apiKey: 'secret',
        groupName: 'support',
        offset: 50,
        limit: 25,
        order: 'last_seen_at',
        ascending: false,
        filter: ' Sam ',
        includeCustomFields: true,
      );
      expect(Uri.parse(transport.gets.last.path).queryParameters, {
        'offset': '50',
        'limit': '25',
        'order': 'last_seen_at',
        'asc': 'false',
        'filter': 'Sam',
        'include_custom_fields': 'true',
      });
      expect(members.members.single.username, 'sam');

      transport.getResponse = {
        'members': [
          {'id': 3, 'username': 'lee', 'reason': 'Please'},
        ],
        'meta': {'total': 1, 'limit': 50, 'offset': 0},
      };
      final requesters = await api.requesters(
        siteUrl: siteUrl,
        apiKey: 'secret',
        groupName: 'support',
      );
      expect(
        Uri.parse(transport.gets.last.path).queryParameters['requesters'],
        'true',
      );
      expect(requesters.requesters.single.reason, 'Please');

      transport.getResponse = {
        'posts': [
          {
            'id': 5,
            'topic_id': 6,
            'post_number': 1,
            'topic_title': 'Hello',
            'topic_slug': 'hello',
            'excerpt': 'Body',
          },
        ],
      };
      final before = DateTime.utc(2026, 8, 28, 10, 30);
      final activity = await api.mentions(
        siteUrl: siteUrl,
        groupName: 'support',
        before: before,
        categoryId: 4,
      );
      final activityUri = Uri.parse(transport.gets.last.path);
      expect(activityUri.path, '/groups/support/mentions.json');
      expect(activityUri.queryParameters, {
        'before': '2026-08-28T10:30:00.000Z',
        'category_id': '4',
      });
      expect(activity.posts.single.id, 5);

      transport.getResponse = {
        'logs': [
          {'action': 'add_user_to_group'},
        ],
        'all_loaded': true,
      };
      final logs = await api.logs(
        siteUrl: siteUrl,
        apiKey: 'secret',
        groupName: 'support',
        offset: 25,
        action: 'add_user_to_group',
        actingUsername: 'admin',
        targetUsername: 'sam',
        subject: 'Support',
      );
      expect(Uri.parse(transport.gets.last.path).queryParameters, {
        'offset': '25',
        'filters[action]': 'add_user_to_group',
        'filters[acting_username]': 'admin',
        'filters[target_username]': 'sam',
        'filters[subject]': 'Support',
      });
      expect(logs.logs.single.action, 'add_user_to_group');
    },
  );

  test(
    'topic tabs decode through the model codec and constrain cursors',
    () async {
      final transport = _RecordingTransport()
        ..getResponse = {
          'topic_list': {
            'topics': [
              {'id': 8, 'title': 'Team topic', 'slug': 'team-topic'},
            ],
          },
        };
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

      final topics = await api.topics(siteUrl: siteUrl, groupName: 'team+ops');
      await api.messages(
        siteUrl: siteUrl,
        apiKey: 'secret',
        username: 'sam',
        groupName: 'team+ops',
        archived: true,
      );
      await api.topicPage(
        siteUrl: siteUrl,
        path: '/topics/groups/team+ops?page=1',
      );

      expect(transport.gets[0].path, '/topics/groups/team%2Bops.json');
      expect(
        transport.gets[1].path,
        '/topics/private-messages-group/sam/team%2Bops/archive.json',
      );
      expect(transport.gets[2].path, '/topics/groups/team+ops.json?page=1');
      expect(topics.topics.single.id, 8);
      expect(
        () => api.topicPage(
          siteUrl: siteUrl,
          path: 'https://outside.example/topics.json',
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'permissions use the bare-array transport at the compatibility path',
    () async {
      final transport = _RecordingTransport()
        ..listResponse = [
          {
            'permission_type': 1,
            'category': {'id': 4, 'name': 'Help', 'color': '0088CC'},
          },
        ];
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

      final permissions = await api.permissions(
        siteUrl: siteUrl,
        apiKey: 'secret',
        groupName: 'support',
      );

      expect(transport.listGets.single.path, '/g/support/permissions');
      expect(permissions.single.type, GroupPermissionType.full);
      expect(permissions.single.category.name, 'Help');
    },
  );

  test('membership mutations use the core group routes and payloads', () async {
    final transport = _RecordingTransport();
    final api = GroupsApi(transport, const DiscourseModelCodec.core());

    await api.join(siteUrl: siteUrl, apiKey: 'secret', groupId: 7);
    await api.leave(siteUrl: siteUrl, apiKey: 'secret', groupId: 7);
    transport.writeResponse = {'relative_url': '/g/support/requests'};
    final requestUrl = await api.requestMembership(
      siteUrl: siteUrl,
      apiKey: 'secret',
      groupName: 'support',
      reason: ' I can help ',
    );
    await api.setNotificationLevel(
      siteUrl: siteUrl,
      apiKey: 'secret',
      groupName: 'support',
      notificationLevel: 3,
      userId: 2,
    );

    transport.writeResponse = {
      'usernames': ['sam'],
      'emails': ['lee@example.com'],
      'skipped_usernames': ['missing'],
    };
    final added = await api.addMembers(
      siteUrl: siteUrl,
      apiKey: 'secret',
      groupId: 7,
      usernames: const [' sam '],
      emails: const [' lee@example.com '],
      notifyUsers: false,
      skipEmail: true,
    );
    await api.removeMembers(
      siteUrl: siteUrl,
      apiKey: 'secret',
      groupId: 7,
      userIds: const [2, 3],
    );
    await api.handleMembershipRequest(
      siteUrl: siteUrl,
      apiKey: 'secret',
      groupId: 7,
      userId: 4,
      accept: false,
    );

    expect(requestUrl, '/g/support/requests');
    expect(added.usernames, ['sam']);
    expect(transport.writes[0].method, 'PUT');
    expect(transport.writes[0].path, '/groups/7/join.json');
    expect(transport.writes[0].body, isEmpty);
    expect(transport.writes[1].method, 'DELETE');
    expect(transport.writes[2].body, {'reason': 'I can help'});
    expect(transport.writes[3].body, {'notification_level': 3, 'user_id': 2});
    expect(transport.writes[4].body, {
      'usernames': 'sam',
      'emails': 'lee@example.com',
      'notify_users': false,
      'skip_email': 'true',
    });
    expect(transport.writes[5].body, {'user_ids': '2,3'});
    expect(transport.writes[6].body, {'user_id': 4});
  });

  test(
    'owner, settings, SMTP, count, create, and delete routes are exact',
    () async {
      final transport = _RecordingTransport();
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

      await api.addOwners(
        siteUrl: siteUrl,
        apiKey: 'secret',
        groupId: 7,
        usernames: const ['sam'],
      );
      await api.removeOwners(
        siteUrl: siteUrl,
        apiKey: 'secret',
        groupId: 7,
        usernames: const ['sam'],
      );
      await api.setPrimaryGroup(
        siteUrl: siteUrl,
        apiKey: 'secret',
        groupId: 7,
        usernames: const ['sam'],
        primary: false,
      );

      transport.writeResponse = {
        'basic_group': {'id': 8, 'name': 'new-group'},
      };
      final created = await api.createGroup(
        siteUrl: siteUrl,
        apiKey: 'secret',
        values: const {'name': 'new-group'},
      );
      transport.writeResponse = {
        'group': {'id': 7, 'name': 'support', 'full_name': 'Support Team'},
      };
      final updated = await api.updateGroup(
        siteUrl: siteUrl,
        apiKey: 'secret',
        groupId: 7,
        values: const {'full_name': 'Support Team'},
        updateExistingUsers: true,
      );
      await api.testSmtpSettings(
        siteUrl: siteUrl,
        apiKey: 'secret',
        groupId: 7,
        smtpServer: 'smtp.example.com',
        smtpPort: 587,
        smtpSslMode: 1,
        emailUsername: 'group@example.com',
        emailPassword: 'secret',
        emailFromAlias: 'support',
      );
      transport.writeResponse = {'user_count': 12};
      final count = await api.automaticMembershipCount(
        siteUrl: siteUrl,
        apiKey: 'secret',
        emailDomains: ' example.com ',
      );
      await api.deleteGroup(siteUrl: siteUrl, apiKey: 'secret', groupId: 7);

      expect(created.name, 'new-group');
      expect(updated.fullName, 'Support Team');
      expect(count, 12);
      expect(transport.writes[0].path, '/groups/7/owners.json');
      expect(transport.writes[1].path, '/admin/groups/7/owners.json');
      expect(transport.writes[1].body, {
        'group': {'usernames': 'sam'},
      });
      expect(transport.writes[2].body, {
        'group': {'usernames': 'sam'},
        'primary': 'false',
      });
      expect(transport.writes[3].path, '/admin/groups.json');
      expect(transport.writes[4].body, {
        'group': {'full_name': 'Support Team'},
        'update_existing_users': 'true',
      });
      expect(transport.writes[5].path, '/groups/7/test_email_settings.json');
      expect(
        transport.writes[6].path,
        '/admin/groups/automatic_membership_count.json',
      );
      expect(transport.writes.last.path, '/admin/groups/7.json');
    },
  );

  test('input validation rejects unsafe names, windows, and cursors', () {
    final api = GroupsApi(
      _RecordingTransport(),
      const DiscourseModelCodec.core(),
    );

    expect(
      () => api.detail(siteUrl: siteUrl, groupName: '../admin'),
      throwsArgumentError,
    );
    expect(
      () => api.members(siteUrl: siteUrl, groupName: 'support', limit: 1001),
      throwsRangeError,
    );
    expect(
      () => api.requestMembership(
        siteUrl: siteUrl,
        apiKey: 'secret',
        groupName: 'support',
        reason: ' ',
      ),
      throwsArgumentError,
    );
  });
}

final class _RecordingTransport
    implements PluginApiTransport, PluginJsonListTransport {
  Map<String, dynamic> getResponse = const {};
  List<Map<String, dynamic>> listResponse = const [];
  Map<String, dynamic> writeResponse = const {};
  final List<({String path, String? apiKey})> gets = [];
  final List<({String path, String? apiKey})> listGets = [];
  final List<({String method, String path, Map<String, Object?> body})> writes =
      [];

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    gets.add((path: path, apiKey: apiKey));
    return getResponse;
  }

  @override
  Future<List<Map<String, dynamic>>> pluginGetJsonList({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    listGets.add((path: path, apiKey: apiKey));
    return listResponse;
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
    writes.add((method: method, path: path, body: body));
    return writeResponse;
  }
}
