import 'dart:async';

import 'package:discourse_native/src/data/groups_api.dart';
import 'package:discourse_native/src/data/plugin_transport.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/shell/groups_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://forum.example';
const _instance = DiscourseInstance(url: _site, title: 'Forum');
const _connectedInstance = DiscourseInstance(
  url: _site,
  title: 'Forum',
  user: DiscourseUser(username: 'sam'),
);

Completer<T> _completed<T>(T value) => Completer<T>()..complete(value);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('group state snapshots defensively own every exposed list', () {
    final groups = [const Group(id: 1, name: 'alpha')];
    final typeFilters = ['public'];
    final members = [const GroupMember(id: 2, username: 'sam')];
    final requesters = [const GroupRequester(id: 3, username: 'lee')];
    final posts = [
      const GroupActivityPost(
        id: 4,
        topicId: 40,
        postNumber: 1,
        topicTitle: 'Update',
        topicSlug: 'update',
        excerpt: 'News',
      ),
    ];
    final permissions = [
      const GroupPermission(
        type: GroupPermissionType.full,
        category: TopicCategory(id: 5, name: 'Support', color: '0088CC'),
      ),
    ];
    final logs = [const GroupLogEntry(action: 'add_user')];

    final directory = GroupDirectoryState(
      groups: groups,
      typeFilters: typeFilters,
    );
    final memberState = GroupMembersState(members: members);
    final requesterState = GroupRequestersState(requesters: requesters);
    final activity = GroupActivityState(posts: posts);
    final permissionState = GroupPermissionsState(permissions: permissions);
    final logState = GroupLogsState(logs: logs);

    groups.add(const Group(id: 6, name: 'beta'));
    typeFilters.add('private');
    members.add(const GroupMember(id: 7, username: 'alex'));
    requesters.add(const GroupRequester(id: 8, username: 'pat'));
    posts.add(
      const GroupActivityPost(
        id: 9,
        topicId: 90,
        postNumber: 1,
        topicTitle: 'Late update',
        topicSlug: 'late-update',
        excerpt: 'Late news',
      ),
    );
    permissions.add(
      const GroupPermission(
        type: GroupPermissionType.readOnly,
        category: TopicCategory(id: 10, name: 'Staff', color: '00AA00'),
      ),
    );
    logs.add(const GroupLogEntry(action: 'remove_user'));

    expect(directory.groups.map((group) => group.id), [1]);
    expect(directory.typeFilters, ['public']);
    expect(memberState.members.map((member) => member.id), [2]);
    expect(requesterState.requesters.map((requester) => requester.id), [3]);
    expect(activity.posts.map((post) => post.id), [4]);
    expect(
      permissionState.permissions.map((permission) => permission.category.id),
      [5],
    );
    expect(logState.logs.map((log) => log.action), ['add_user']);

    expect(
      () => directory.groups.add(const Group(id: 11, name: 'gamma')),
      throwsUnsupportedError,
    );
    expect(
      () => directory.typeFilters.add('automatic'),
      throwsUnsupportedError,
    );
    expect(
      () =>
          memberState.members.add(const GroupMember(id: 12, username: 'jules')),
      throwsUnsupportedError,
    );
    expect(
      () => requesterState.requesters.add(
        const GroupRequester(id: 13, username: 'morgan'),
      ),
      throwsUnsupportedError,
    );
    expect(() => activity.posts.clear(), throwsUnsupportedError);
    expect(() => permissionState.permissions.clear(), throwsUnsupportedError);
    expect(() => logState.logs.clear(), throwsUnsupportedError);
  });

  test(
    'directory pagination merges by ID and preserves the confirmed page',
    () async {
      final firstPayload = <String, dynamic>{
        'groups': [
          {'id': 1, 'name': 'alpha'},
        ],
        'total_rows_groups': 2,
        'load_more_groups': '/groups?page=1',
      };
      final transport = _ControlledGroupTransport()
        ..objects.addAll([
          _completed(firstPayload),
          _completed({
            'groups': [
              {'id': 1, 'name': 'alpha'},
              {'id': 2, 'name': 'beta'},
            ],
            'total_rows_groups': 2,
          }),
        ]);
      final controller = _controller(transport);
      addTearDown(controller.dispose);
      const query = GroupDirectoryQuery();

      await controller.loadDirectory(_instance, query);
      final confirmed = controller.directoryState(_site, query);
      (firstPayload['groups'] as List<Object?>).add({'id': 99, 'name': 'late'});

      expect(confirmed.groups.map((group) => group.id), [1]);
      expect(
        () => confirmed.groups.add(const Group(id: 99, name: 'late')),
        throwsUnsupportedError,
      );

      final paging = controller.loadDirectory(_instance, query, more: true);
      final loading = controller.directoryState(_site, query);
      expect(loading.groups, same(confirmed.groups));
      await paging;

      final state = controller.directoryState(_site, query);
      expect(state.groups.map((group) => group.id), [1, 2]);
      expect(state.totalRows, 2);
      expect(state.hasMore, isFalse);
      expect(controller.presentedDirectoryState(_site), same(state));
      expect(transport.gets.map((request) => request.path), [
        '/groups.json',
        '/groups.json?page=1',
      ]);
      expect(transport.gets.every((request) => request.apiKey == null), isTrue);
    },
  );

  test('member filters have independent caches and paging windows', () async {
    final transport = _ControlledGroupTransport()
      ..objects.addAll([
        _completed({
          'members': [
            {'id': 1, 'username': 'sam'},
          ],
          'owners': <Object?>[],
          'meta': {'total': 1, 'limit': 50, 'offset': 0},
        }),
        _completed({
          'members': [
            {'id': 2, 'username': 'lee'},
          ],
          'owners': <Object?>[],
          'meta': {'total': 1, 'limit': 50, 'offset': 0},
        }),
      ]);
    final controller = _controller(transport);
    addTearDown(controller.dispose);

    await controller.loadMembers(_instance, 'support');
    await controller.loadMembers(_instance, 'support', filter: 'lee');

    expect(controller.membersState(_site, 'support').members.single.id, 1);
    expect(
      controller
          .membersState(_site, 'support', filter: 'lee')
          .members
          .single
          .id,
      2,
    );
  });

  test(
    'member roles update every sorted cache after a confirmed write',
    () async {
      final transport = _ControlledGroupTransport()
        ..objects.add(
          _completed({
            'members': [
              {'id': 1, 'username': 'sam'},
            ],
            'owners': <Object?>[],
            'meta': {'total': 1, 'limit': 50, 'offset': 0},
          }),
        );
      final credentials = FakeApiCredentialReader(
        clientIdValue: 'native-client',
      )..keys[_site] = 'secret';
      final controller = _controller(transport, credentials: credentials);
      addTearDown(controller.dispose);
      const group = Group(id: 7, name: 'support');

      await controller.loadMembers(
        _connectedInstance,
        group.name,
        order: 'last_seen_at',
        ascending: false,
      );
      final member = controller
          .membersState(
            _site,
            group.name,
            order: 'last_seen_at',
            ascending: false,
          )
          .members
          .single;
      final saved = await controller.setMemberOwner(
        _connectedInstance,
        group,
        member,
        owner: true,
      );

      expect(saved, isTrue);
      expect(
        controller
            .membersState(
              _site,
              group.name,
              order: 'last_seen_at',
              ascending: false,
            )
            .members
            .single
            .owner,
        isTrue,
      );
      expect(transport.writes.single.path, '/groups/7/owners.json');
      expect(transport.writes.single.clientId, 'native-client');
    },
  );

  test('permissions remain available to an anonymous group visitor', () async {
    final transport = _ControlledGroupTransport()
      ..lists.add(
        _completed([
          {
            'permission_type': 1,
            'category': {'id': 4, 'name': 'Support'},
          },
        ]),
      );
    final controller = _controller(transport);
    addTearDown(controller.dispose);

    await controller.loadPermissions(_instance, 'support');

    final state = controller.permissionsState(_site, 'support');
    expect(state.permissions.single.category.name, 'Support');
    expect(transport.listGets.single.apiKey, isNull);
    expect(transport.listGets.single.clientId, isNull);
  });

  test(
    'authenticated reads send the user API client ID with the key',
    () async {
      final transport = _ControlledGroupTransport()
        ..objects.add(
          _completed({
            'group': {'id': 7, 'name': 'support'},
          }),
        );
      final credentials = FakeApiCredentialReader(
        clientIdValue: 'native-client',
      )..keys[_site] = 'secret';
      final controller = _controller(transport, credentials: credentials);
      addTearDown(controller.dispose);

      await controller.loadDetail(_connectedInstance, 'support');

      expect(transport.gets.single.apiKey, 'secret');
      expect(transport.gets.single.clientId, 'native-client');
    },
  );

  test(
    'forget plus lifecycle invalidation rejects a late group response',
    () async {
      final detail = Completer<Map<String, dynamic>>();
      final transport = _ControlledGroupTransport()..objects.add(detail);
      final lifecycle = SiteLifecycle();
      final controller = _controller(transport, lifecycle: lifecycle);
      addTearDown(controller.dispose);

      final load = controller.loadDetail(_instance, 'support');
      await pumpEventQueue();
      lifecycle.invalidate(_site);
      controller.forget(_site);
      detail.complete({
        'group': {'id': 7, 'name': 'support'},
      });
      await load;

      final state = controller.detailState(_site, 'support');
      expect(state.loaded, isFalse);
      expect(state.detail, isNull);
    },
  );

  test('a stale directory response cannot replace a newer request', () async {
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    final transport = _ControlledGroupTransport()
      ..objects.addAll([first, second]);
    final lifecycle = SiteLifecycle();
    final controller = _controller(transport, lifecycle: lifecycle);
    addTearDown(controller.dispose);
    const query = GroupDirectoryQuery();

    final staleLoad = controller.loadDirectory(_instance, query);
    await pumpEventQueue();
    expect(transport.gets, hasLength(1));

    lifecycle.invalidate(_site);
    controller.forget(_site);
    final currentLoad = controller.loadDirectory(_instance, query);
    await pumpEventQueue();
    expect(transport.gets, hasLength(2));

    second.complete({
      'groups': [
        {'id': 2, 'name': 'current'},
      ],
      'total_rows_groups': 1,
    });
    await currentLoad;
    first.complete({
      'groups': [
        {'id': 1, 'name': 'stale'},
      ],
      'total_rows_groups': 1,
    });
    await staleLoad;

    final state = controller.directoryState(_site, query);
    expect(state.groups.map((group) => group.name), ['current']);
    expect(state.totalRows, 1);
  });
}

GroupsController _controller(
  _ControlledGroupTransport transport, {
  SiteLifecycle? lifecycle,
  FakeApiCredentialReader? credentials,
}) => GroupsController(
  api: GroupsApi(transport, const DiscourseModelCodec.core()),
  credentials: credentials ?? FakeApiCredentialReader(),
  lifecycle: lifecycle ?? SiteLifecycle(),
);

final class _ControlledGroupTransport
    implements PluginApiTransport, PluginJsonListTransport {
  final List<Completer<Map<String, dynamic>>> objects = [];
  final List<Completer<List<Map<String, dynamic>>>> lists = [];
  final List<({String path, String? apiKey, String? clientId})> gets = [];
  final List<({String path, String? apiKey, String? clientId})> listGets = [];
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
  }) {
    gets.add((path: path, apiKey: apiKey, clientId: clientId));
    return objects.removeAt(0).future;
  }

  @override
  Future<List<Map<String, dynamic>>> pluginGetJsonList({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) {
    listGets.add((path: path, apiKey: apiKey, clientId: clientId));
    return lists.removeAt(0).future;
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
    return const {};
  }
}
