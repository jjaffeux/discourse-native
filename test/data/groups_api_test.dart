import 'package:discourse_native/src/data/groups_api.dart';
import 'package:discourse_native/src/data/plugin_transport.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const siteUrl = 'https://forum.example';

  group('directory, member, and topic reads', () {
    test('directory is public and preserves every query dimension', () async {
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

      final request = transport.gets.single;
      final directoryUri = Uri.parse(request.path);
      expect(directoryUri.path, '/groups.json');
      expect(directoryUri.queryParameters, {
        'page': '2',
        'filter': 'support',
        'type': 'my',
        'order': 'user_count',
        'asc': 'false',
        'username': 'sam',
      });
      expect(request.apiKey, isNull);
      expect(directory.groups.single.name, 'team+ops');
    });

    test('detail encodes the group name and decodes visible groups', () async {
      final transport = _RecordingTransport()
        ..getResponse = {
          'group': {'id': 1, 'name': 'team+ops'},
          'extras': {
            'visible_group_names': ['team+ops'],
          },
        };
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

      final detail = await api.detail(
        siteUrl: siteUrl,
        groupName: 'team+ops',
        apiKey: 'secret',
      );

      expect(transport.gets.single.path, '/groups/team%2Bops.json');
      expect(detail.visibleGroupNames, ['team+ops']);
    });

    test('members maps every paging, ordering, and filter query', () async {
      final transport = _RecordingTransport()
        ..getResponse = {
          'members': [
            {'id': 2, 'username': 'sam'},
          ],
          'owners': <Map<String, Object?>>[],
          'meta': {'total': 1, 'limit': 25, 'offset': 50},
        };
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

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

      expect(Uri.parse(transport.gets.single.path).queryParameters, {
        'offset': '50',
        'limit': '25',
        'order': 'last_seen_at',
        'asc': 'false',
        'filter': 'Sam',
        'include_custom_fields': 'true',
      });
      expect(members.members.single.username, 'sam');
    });

    test('requesters sets its discriminator and decodes reasons', () async {
      final transport = _RecordingTransport()
        ..getResponse = {
          'members': [
            {'id': 3, 'username': 'lee', 'reason': 'Please'},
          ],
          'meta': {'total': 1, 'limit': 50, 'offset': 0},
        };
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

      final requesters = await api.requesters(
        siteUrl: siteUrl,
        apiKey: 'secret',
        groupName: 'support',
      );

      expect(Uri.parse(transport.gets.single.path).queryParameters, {
        'requesters': 'true',
        'offset': '0',
        'limit': '50',
      });
      expect(requesters.requesters.single.reason, 'Please');
    });

    test('mentions maps its cursor and category filter exactly', () async {
      final transport = _RecordingTransport()
        ..getResponse = {
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
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

      final activity = await api.mentions(
        siteUrl: siteUrl,
        groupName: 'support',
        before: DateTime.utc(2026, 8, 28, 10, 30),
        categoryId: 4,
      );

      final activityUri = Uri.parse(transport.gets.single.path);
      expect(activityUri.path, '/groups/support/mentions.json');
      expect(activityUri.queryParameters, {
        'before': '2026-08-28T10:30:00.000Z',
        'category_id': '4',
      });
      expect(activity.posts.single.id, 5);
    });

    test('logs maps every administrative filter exactly', () async {
      final transport = _RecordingTransport()
        ..getResponse = {
          'logs': [
            {'action': 'add_user_to_group'},
          ],
          'all_loaded': true,
        };
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

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

      expect(Uri.parse(transport.gets.single.path).queryParameters, {
        'offset': '25',
        'filters[action]': 'add_user_to_group',
        'filters[acting_username]': 'admin',
        'filters[target_username]': 'sam',
        'filters[subject]': 'Support',
      });
      expect(logs.logs.single.action, 'add_user_to_group');
    });

    test(
      'topics encodes the group name and decodes through the model codec',
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

        final topics = await api.topics(
          siteUrl: siteUrl,
          groupName: 'team+ops',
        );

        expect(transport.gets.single.path, '/topics/groups/team%2Bops.json');
        expect(topics.topics.single.id, 8);
      },
    );

    test('messages encodes its group and archived mailbox path', () async {
      final transport = _RecordingTransport()
        ..getResponse = {
          'topic_list': {'topics': <Map<String, Object?>>[]},
        };
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

      await api.messages(
        siteUrl: siteUrl,
        apiKey: 'secret',
        username: 'sam',
        groupName: 'team+ops',
        archived: true,
      );

      expect(
        transport.gets.single.path,
        '/topics/private-messages-group/sam/team%2Bops/archive.json',
      );
    });

    test('topic-page cursors stay on the forum origin', () async {
      final transport = _RecordingTransport()
        ..getResponse = {
          'topic_list': {'topics': <Map<String, Object?>>[]},
        };
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

      await api.topicPage(
        siteUrl: siteUrl,
        path: '/topics/groups/team+ops?page=1',
      );

      expect(transport.gets.single.path, '/topics/groups/team+ops.json?page=1');
      expect(
        () => api.topicPage(
          siteUrl: siteUrl,
          path: 'https://outside.example/topics.json',
        ),
        throwsArgumentError,
      );
    });

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
  });

  group('membership mutations', () {
    test('join and leave use the core group routes', () async {
      final transport = _RecordingTransport();
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

      await api.join(siteUrl: siteUrl, apiKey: 'secret', groupId: 7);
      await api.leave(siteUrl: siteUrl, apiKey: 'secret', groupId: 7);

      expect(transport.writes.map((write) => (write.method, write.path)), [
        ('PUT', '/groups/7/join.json'),
        ('DELETE', '/groups/7/leave.json'),
      ]);
      expect(transport.writes.map((write) => write.body), [
        <String, Object?>{},
        <String, Object?>{},
      ]);
    });

    test('membership request trims its reason and returns its route', () async {
      final transport = _RecordingTransport()
        ..writeResponse = {'relative_url': '/g/support/requests'};
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

      final requestUrl = await api.requestMembership(
        siteUrl: siteUrl,
        apiKey: 'secret',
        groupName: 'support',
        reason: ' I can help ',
      );

      expect(requestUrl, '/g/support/requests');
      expect(transport.writes.single.body, {'reason': 'I can help'});
    });

    test('notification level sends the selected level and user', () async {
      final transport = _RecordingTransport();
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

      await api.setNotificationLevel(
        siteUrl: siteUrl,
        apiKey: 'secret',
        groupName: 'support',
        notificationLevel: 3,
        userId: 2,
      );

      expect(transport.writes.single.body, {
        'notification_level': 3,
        'user_id': 2,
      });
    });

    test('member writes normalize additions and encode removal IDs', () async {
      final transport = _RecordingTransport()
        ..writeResponse = {
          'usernames': ['sam'],
          'emails': ['lee@example.com'],
          'skipped_usernames': ['missing'],
        };
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

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

      expect(added.usernames, ['sam']);
      expect(transport.writes.first.body, {
        'usernames': 'sam',
        'emails': 'lee@example.com',
        'notify_users': false,
        'skip_email': 'true',
      });
      expect(transport.writes.last.body, {'user_ids': '2,3'});
    });

    test('membership-request refusal sends the target user', () async {
      final transport = _RecordingTransport();
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

      await api.handleMembershipRequest(
        siteUrl: siteUrl,
        apiKey: 'secret',
        groupId: 7,
        userId: 4,
        accept: false,
      );

      expect(transport.writes.single.body, {'user_id': 4});
    });

    test(
      'group invitations support both email delivery and one-use links',
      () async {
        final transport = _RecordingTransport();
        final api = GroupsApi(transport, const DiscourseModelCodec.core());

        transport.writeResponse = {
          'id': 42,
          'email': 'lee@example.com',
          'expires_at': '2026-09-01T12:00:00.000Z',
        };
        final emailed = await api.createInvite(
          siteUrl: siteUrl,
          apiKey: 'secret',
          groupId: 7,
          email: ' lee@example.com ',
          customMessage: ' Welcome ',
          expiresAt: DateTime.utc(2026, 9, 1, 12),
        );

        transport.writeResponse = {'id': 43, 'link': '/invites/abc'};
        final linked = await api.createInvite(
          siteUrl: siteUrl,
          apiKey: 'secret',
          groupId: 7,
        );

        expect(emailed.email, 'lee@example.com');
        expect(transport.writes.first.path, '/invites.json');
        expect(transport.writes.first.method, 'POST');
        expect(transport.writes.first.body, {
          'group_ids': '7',
          'email': 'lee@example.com',
          'custom_message': 'Welcome',
          'expires_at': '2026-09-01T12:00:00.000Z',
        });
        expect(linked.link, '/invites/abc');
        expect(transport.writes.last.body, {
          'group_ids': '7',
          'max_redemptions_allowed': 1,
        });
      },
    );
  });

  group('administrative mutations', () {
    test(
      'owner and primary-group writes use their exact admin contracts',
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

        expect(transport.writes.map((write) => (write.method, write.path)), [
          ('PUT', '/groups/7/owners.json'),
          ('DELETE', '/admin/groups/7/owners.json'),
          ('PUT', '/admin/groups/7/primary.json'),
        ]);
        expect(transport.writes.map((write) => write.body), [
          <String, Object?>{'usernames': 'sam'},
          <String, Object?>{
            'group': {'usernames': 'sam'},
          },
          <String, Object?>{
            'group': {'usernames': 'sam'},
            'primary': 'false',
          },
        ]);
      },
    );

    test(
      'create and update send group values and decode their responses',
      () async {
        final transport = _RecordingTransport()
          ..writeResponse = {
            'basic_group': {'id': 8, 'name': 'new-group'},
          };
        final api = GroupsApi(transport, const DiscourseModelCodec.core());

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

        expect(created.name, 'new-group');
        expect(updated.fullName, 'Support Team');
        expect(transport.writes.first.path, '/admin/groups.json');
        expect(transport.writes.first.body, {
          'group': {'name': 'new-group'},
        });
        expect(transport.writes.last.path, '/groups/7.json');
        expect(transport.writes.last.body, {
          'group': {'full_name': 'Support Team'},
          'update_existing_users': 'true',
        });
      },
    );

    test('SMTP check sends every connection field', () async {
      final transport = _RecordingTransport();
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

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

      expect(
        transport.writes.single.path,
        '/groups/7/test_email_settings.json',
      );
      expect(transport.writes.single.body, {
        'smtp_server': 'smtp.example.com',
        'smtp_port': 587,
        'smtp_ssl_mode': 1,
        'email_username': 'group@example.com',
        'email_password': 'secret',
        'email_from_alias': 'support',
      });
    });

    test(
      'automatic membership count trims domains and decodes the count',
      () async {
        final transport = _RecordingTransport()
          ..writeResponse = {'user_count': 12};
        final api = GroupsApi(transport, const DiscourseModelCodec.core());

        final count = await api.automaticMembershipCount(
          siteUrl: siteUrl,
          apiKey: 'secret',
          emailDomains: ' example.com ',
        );

        expect(count, 12);
        expect(
          transport.writes.single.path,
          '/admin/groups/automatic_membership_count.json',
        );
        expect(transport.writes.single.body, {
          'automatic_membership_email_domains': 'example.com',
        });
      },
    );

    test('delete uses the exact administrative group route', () async {
      final transport = _RecordingTransport();
      final api = GroupsApi(transport, const DiscourseModelCodec.core());

      await api.deleteGroup(siteUrl: siteUrl, apiKey: 'secret', groupId: 7);

      final write = transport.writes.single;
      expect((write.method, write.path), ('DELETE', '/admin/groups/7.json'));
      expect(write.body, isEmpty);
    });
  });

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
