import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
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

  test('rename refreshes the server canonical name', () async {
    final transport = _ControlledGroupTransport()
      ..objects.add(
        _completed({
          'group': {'id': 7, 'name': 'support'},
        }),
      )
      ..onWrite = (_) => {
        'group': {'id': 7, 'name': 'canonical'},
      };
    final credentials = FakeApiCredentialReader()..keys[_site] = 'secret';
    final controller = _controller(transport, credentials: credentials);
    addTearDown(controller.dispose);
    await controller.loadDetail(_connectedInstance, 'support');
    transport.onGet = (path) {
      if (path == '/groups/support.json') {
        throw StateError('old group no longer exists');
      }
    };
    transport.objects.add(
      _completed({
        'group': {'id': 7, 'name': 'canonical'},
      }),
    );

    final result = await controller.updateGroup(
      _connectedInstance,
      const Group(id: 7, name: 'support'),
      GroupUpdateCommand(const {'name': 'requested'}),
    );

    expect(result.canApplyLocally, isTrue);
    expect(transport.gets.last.path, '/groups/canonical.json');
    expect(
      controller.detailState(_site, 'canonical').detail?.group.name,
      'canonical',
    );
    expect(controller.detailState(_site, 'support').detail, isNull);
  });

  group('accepted group rename', () {
    const original = Group(id: 7, name: 'support');
    const canonical = {
      'group': {'id': 7, 'name': 'canonical', 'full_name': 'Saved'},
    };

    for (final cache in _GroupPageCache.values) {
      for (final name in ['support', 'canonical']) {
        test('revokes delayed $name ${cache.name} reads', () async {
          final transport = _ControlledGroupTransport()
            ..onWrite = (_) => canonical;
          final credentials = FakeApiCredentialReader()..keys[_site] = 'secret';
          final controller = _controller(transport, credentials: credentials);
          addTearDown(controller.dispose);
          final respond = cache.hold(transport);
          final oldRead = cache.load(controller, _connectedInstance, name);
          await pumpEventQueue();
          transport.objects.add(_completed(canonical));
          final saved = await controller.updateGroup(
            _connectedInstance,
            original,
            GroupUpdateCommand(const {'name': 'requested'}),
          );
          expect(saved.canApplyLocally, isTrue);
          respond(99);
          await oldRead;
          expect(controller.detailState(_site, 'support').detail, isNull);
          expect(
            controller.detailState(_site, 'canonical').detail?.group.id,
            7,
          );
          if (cache != _GroupPageCache.detail) {
            expect(cache.ids(controller, _site, name), isEmpty);
          }
        });
      }
    }

    for (final cache in _SearchableGroupCache.values) {
      test('settles delayed ${cache.name} pages after rename', () async {
        final transport = _ControlledGroupTransport()
          ..onWrite = (_) => canonical;
        final credentials = FakeApiCredentialReader()..keys[_site] = 'secret';
        final controller = _controller(transport, credentials: credentials);
        addTearDown(controller.dispose);
        final response = Completer<Map<String, dynamic>>();
        transport.objects.add(response);
        final oldRead = cache.load(controller, _connectedInstance, '');
        await pumpEventQueue();
        transport.objects.add(_completed(canonical));
        await controller.updateGroup(
          _connectedInstance,
          original,
          GroupUpdateCommand(const {}),
        );
        response.complete(cache.page(7));
        await oldRead;
        if (cache == _SearchableGroupCache.directory) {
          final directory = controller.directoryState(
            _site,
            const GroupDirectoryQuery(),
          );
          expect(directory.loaded, isTrue);
          expect(directory.loading, isFalse);
          expect(directory.groups.single.name, 'canonical');
          transport.objects.add(
            _completed({
              'groups': [
                {'id': 7, 'name': 'reconciled'},
              ],
              'total_rows_groups': 1,
            }),
          );
          await controller.loadDirectory(
            _connectedInstance,
            const GroupDirectoryQuery(),
            refresh: true,
          );
          expect(
            controller
                .directoryState(_site, const GroupDirectoryQuery())
                .groups
                .single
                .name,
            'reconciled',
          );
        } else {
          expect(cache.ids(controller, _site, ''), isEmpty);
        }
        expect(
          controller.detailState(_site, 'canonical').detail?.group.name,
          'canonical',
        );
      });
    }

    test(
      'rename preserves another site directory and pending refresh',
      () async {
        const other = DiscourseInstance(
          url: 'https://other.example',
          title: 'Other',
        );
        const query = GroupDirectoryQuery();
        final response = Completer<Map<String, dynamic>>();
        final page = _SearchableGroupCache.directory.page(7);
        final transport = _ControlledGroupTransport()
          ..onWrite = ((_) => canonical)
          ..objects.addAll([_completed(page), response]);
        final controller = _controller(
          transport,
          credentials: FakeApiCredentialReader()..keys[_site] = 'secret',
        );
        addTearDown(controller.dispose);
        await controller.loadDirectory(other, query);
        final pending = controller.loadDirectory(other, query, refresh: true);
        await pumpEventQueue();
        final held = controller.directoryState(other.url, query);
        transport.objects.add(_completed(canonical));
        await controller.updateGroup(
          _connectedInstance,
          original,
          GroupUpdateCommand(const {'name': 'requested'}),
        );
        expect(controller.directoryState(other.url, query), same(held));
        response.complete(page);
        await pending;
        final completed = controller.directoryState(other.url, query);
        expect(completed.loaded, isTrue);
        expect(completed.loading, isFalse);
        expect(completed.groups.single.name, 'group-7');
      },
    );

    for (final more in [false, true]) {
      test('rename preserves a loaded directory during '
          '${more ? 'pagination' : 'refresh'}', () async {
        final transport = _ControlledGroupTransport()
          ..onWrite = ((_) => canonical)
          ..objects.add(
            _completed({
              'groups': [
                {'id': 7, 'name': 'support'},
                {'id': 8, 'name': 'unrelated'},
              ],
              'extras': {
                'type_filters': ['public'],
              },
              'total_rows_groups': 4,
              'load_more_groups': '/groups?page=1',
            }),
          );
        final controller = _controller(
          transport,
          credentials: FakeApiCredentialReader()..keys[_site] = 'secret',
        );
        addTearDown(controller.dispose);
        const query = GroupDirectoryQuery();
        await controller.loadDirectory(_connectedInstance, query);
        final held = controller.directoryState(_site, query);
        final unrelated = held.groups.last;
        final response = Completer<Map<String, dynamic>>();
        transport.objects.add(response);
        final pending = controller.loadDirectory(
          _connectedInstance,
          query,
          refresh: !more,
          more: more,
        );
        await pumpEventQueue();
        transport.objects.add(_completed(canonical));
        await controller.updateGroup(
          _connectedInstance,
          original,
          GroupUpdateCommand(const {'name': 'requested'}),
        );
        final projected = controller.directoryState(_site, query);
        expect(projected.loaded, isTrue);
        expect(projected.loading, !more);
        expect(projected.loadingMore, more);
        expect(projected.hasMore, held.hasMore);
        expect(projected.nextPage, held.nextPage);
        expect(projected.totalRows, held.totalRows);
        expect(projected.typeFilters, held.typeFilters);
        expect(projected.groups.map((group) => group.name), [
          'canonical',
          'unrelated',
        ]);
        expect(projected.groups.last, same(unrelated));
        expect(held.groups.first.name, 'support');
        response.complete({
          'groups': [
            {'id': 7, 'name': 'support'},
            {'id': 8, 'name': 'unrelated'},
            {'id': 10, 'name': 'another'},
          ],
          'total_rows_groups': 3,
        });
        await pending;
        final completed = controller.directoryState(_site, query);
        expect(completed.loaded, isTrue);
        expect(completed.loading, isFalse);
        expect(completed.loadingMore, isFalse);
        expect(completed.groups.map((group) => group.name), [
          'canonical',
          'unrelated',
          'another',
        ]);
        expect(completed.nextPage, more ? 2 : 1);
        expect(completed.hasMore, isFalse);
        expect(
          transport.gets.where(
            (request) => request.path.startsWith('/groups.json'),
          ),
          hasLength(2),
        );
      });
    }

    test(
      'retains returned fields and visible names when canonical refresh fails',
      () async {
        final transport = _ControlledGroupTransport()
          ..objects.add(
            _completed({
              'group': {'id': 7, 'name': 'support'},
              'extras': {
                'visible_group_names': ['staff'],
              },
            }),
          )
          ..onWrite = (_) => canonical;
        final controller = _controller(
          transport,
          credentials: FakeApiCredentialReader()..keys[_site] = 'secret',
        );
        addTearDown(controller.dispose);
        await controller.loadDetail(_connectedInstance, original.name);
        transport.onGet = (_) => throw StateError('refresh failed');
        final result = await controller.updateGroup(
          _connectedInstance,
          original,
          GroupUpdateCommand(const {}),
        );
        expect(
          result,
          isA<GroupWriteAccepted<Group>>()
              .having(
                (result) => result.projection,
                'projection',
                GroupProjectionFreshness.stale,
              )
              .having(
                (result) => result.value.name,
                'accepted name',
                'canonical',
              ),
        );
        final detail = controller.detailState(_site, 'canonical');
        expect(detail.detail?.group.fullName, 'Saved');
        expect(detail.detail?.visibleGroupNames, ['staff']);
        expect(detail.error, isNotNull);
        expect(detail.mutating, isFalse);
        expect(controller.detailState(_site, 'support').detail, isNull);
      },
    );

    for (final response in [
      {'success': 'OK'},
      {
        'group': {'id': 8, 'name': 'someone-else'},
      },
      {
        'group': {'id': 7, 'name': '../unsafe'},
      },
    ]) {
      test(
        'unusable update identity refreshes the opening group $response',
        () async {
          final transport = _ControlledGroupTransport()
            ..onWrite = ((_) => response)
            ..objects.add(
              _completed({
                'group': {'id': 7, 'name': 'support'},
              }),
            );
          final controller = _controller(
            transport,
            credentials: FakeApiCredentialReader()..keys[_site] = 'secret',
          );
          addTearDown(controller.dispose);
          final result = await controller.updateGroup(
            _connectedInstance,
            original,
            GroupUpdateCommand(const {'name': 'requested'}),
          );
          expect(
            result,
            isA<GroupWriteAccepted<Group>>().having(
              (result) => result.value.name,
              'name',
              'support',
            ),
          );
          expect(transport.gets.single.path, '/groups/support.json');
        },
      );
    }

    test('retirement blocks canonical projection after acceptance', () async {
      final transport = _ControlledGroupTransport()..onWrite = (_) => canonical;
      final lifecycle = SiteLifecycle();
      final controller = _controller(
        transport,
        lifecycle: lifecycle,
        credentials: FakeApiCredentialReader()..keys[_site] = 'secret',
      );
      addTearDown(controller.dispose);
      final write = transport.holdWrite();
      final pending = controller.updateGroup(
        _connectedInstance,
        original,
        GroupUpdateCommand(const {}),
      );
      await write.started.future;
      lifecycle.invalidate(_site);
      controller.forget(_site);
      write.release.complete();
      final result = await pending;
      expect(
        result,
        isA<GroupWriteAccepted<Group>>()
            .having((result) => result.value.name, 'server name', 'canonical')
            .having(
              (result) => result.projection,
              'projection',
              GroupProjectionFreshness.retired,
            ),
      );
      expect(result.canApplyLocally, isFalse);
      expect(controller.detailState(_site, 'canonical').detail, isNull);
      expect(transport.gets, isEmpty);
    });

    test(
      'confirmation projects only the accepted canonical identity',
      () async {
        var writes = 0;
        final transport = _ControlledGroupTransport()
          ..onWrite = (_) {
            if (writes++ == 0) {
              throw const WriteException(
                WriteFailure.validation,
                statusCode: 422,
                affectedUserCount: 3,
              );
            }
            return canonical;
          }
          ..objects.add(_completed(canonical));
        final controller = _controller(
          transport,
          credentials: FakeApiCredentialReader()..keys[_site] = 'secret',
        );
        addTearDown(controller.dispose);
        final confirmation =
            await controller.updateGroup(
                  _connectedInstance,
                  original,
                  GroupUpdateCommand(const {'name': 'requested'}),
                )
                as GroupUpdateConfirmation;
        expect(controller.detailState(_site, 'canonical').detail, isNull);
        expect(transport.gets, isEmpty);
        final result = await controller.confirmUpdate(
          confirmation,
          applyToExistingUsers: true,
        );
        expect(
          result,
          isA<GroupWriteAccepted<Group>>().having(
            (result) => result.value.name,
            'name',
            'canonical',
          ),
        );
        expect(transport.gets.single.path, '/groups/canonical.json');
        expect(controller.detailState(_site, 'support').detail, isNull);
      },
    );
  });

  const previewGroup = Group(
    id: 1,
    name: 'support',
    userCount: 12,
    canSeeMembers: true,
  );

  test(
    'directory member preview requests four members without filling member pagination',
    () async {
      final transport = _ControlledGroupTransport()
        ..objects.add(
          _completed({
            'members': [
              for (var id = 1; id <= 5; id++) {'id': id, 'username': 'user$id'},
            ],
            'meta': {'total': 12, 'limit': 4, 'offset': 0},
          }),
        );
      final controller = _controller(transport);
      addTearDown(controller.dispose);
      final members = await controller.loadMemberPreview(
        _instance,
        previewGroup,
      );
      expect(
        Uri.parse(transport.gets.single.path).queryParameters['limit'],
        '4',
      );
      expect(members.map((member) => member.username), [
        'user1',
        'user2',
        'user3',
        'user4',
      ]);
      expect(controller.membersState(_site, 'support').loaded, isFalse);
    },
  );

  test('directory member preview skips hidden and empty groups', () async {
    final transport = _ControlledGroupTransport();
    final controller = _controller(transport);
    addTearDown(controller.dispose);
    for (final group in [
      const Group(id: 1, name: 'hidden', userCount: 3),
      const Group(id: 2, name: 'empty', userCount: 0, canSeeMembers: true),
    ]) {
      expect(await controller.loadMemberPreview(_instance, group), isEmpty);
    }
    expect(transport.gets, isEmpty);
  });

  test(
    'directory member preview discards a forgotten account response',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      final transport = _ControlledGroupTransport()
        ..objects.add(pending)
        ..onGet = (_) => started.complete();
      final controller = _controller(transport);
      addTearDown(controller.dispose);
      final loading = controller.loadMemberPreview(_instance, previewGroup);
      await started.future;
      controller.forget(_site);
      pending.complete({
        'members': [
          {'id': 1, 'username': 'old-account-member'},
        ],
      });
      expect(await loading, isEmpty);
    },
  );

  final publicReads = <String, Future<void> Function(GroupsController)>{
    'member preview': (controller) async {
      await controller.loadMemberPreview(_instance, previewGroup);
    },
    'directory': (controller) =>
        controller.loadDirectory(_instance, const GroupDirectoryQuery()),
    'detail': (controller) => controller.loadDetail(_instance, 'support'),
    'members': (controller) => controller.loadMembers(_instance, 'support'),
    'activity': (controller) =>
        controller.loadActivity(_instance, 'support', mentions: false),
    'permissions': (controller) =>
        controller.loadPermissions(_instance, 'support'),
  };
  for (final read in publicReads.entries) {
    test(
      '${read.key} does not send after its account is forgotten during credential lookup',
      () async {
        final transport = _ControlledGroupTransport()
          ..objects.add(_completed(<String, dynamic>{}))
          ..lists.add(_completed(<Map<String, dynamic>>[]));
        final controller = _controller(transport);
        addTearDown(controller.dispose);

        final loading = read.value(controller);
        controller.forget(_site);
        await loading;

        expect(transport.gets, isEmpty);
        expect(transport.listGets, isEmpty);
      },
    );
  }

  test(
    'a group write cannot report success into an account replaced by its completion observer',
    () async {
      final transport = _ControlledGroupTransport();
      final lifecycle = SiteLifecycle();
      final credentials = FakeApiCredentialReader()..keys[_site] = 'secret';
      final controller = _controller(
        transport,
        credentials: credentials,
        lifecycle: lifecycle,
      );
      addTearDown(controller.dispose);
      var replaced = false;
      controller.addListener(() {
        if (replaced ||
            transport.writes.isEmpty ||
            controller.detailState(_site, 'support').mutating) {
          return;
        }
        replaced = true;
        lifecycle.invalidate(_site);
        controller.forget(_site);
      });

      final deleted = await controller.deleteGroup(
        _connectedInstance,
        const Group(id: 7, name: 'support'),
      );

      expect(transport.writes, hasLength(1));
      expect(replaced, isTrue);
      expect(deleted.canApplyLocally, isFalse);
    },
  );

  for (final kind in _SearchableGroupCache.values) {
    group('${kind.name} query retention', () {
      test(
        'keeps sixteen recent queries per forum and refreshes reuse order',
        () async {
          const other = DiscourseInstance(
            url: 'https://other.example',
            title: 'Other',
            user: DiscourseUser(username: 'sam'),
          );
          final transport = _ControlledGroupTransport();
          final credentials = FakeApiCredentialReader()
            ..keys[_site] = 'key'
            ..keys[other.url] = 'other-key';
          final controller = _controller(transport, credentials: credentials);
          addTearDown(controller.dispose);
          transport.objects.add(_completed(kind.page(99)));
          await kind.load(controller, other, 'other');
          for (var index = 0; index < 16; index++) {
            transport.objects.add(_completed(kind.page(index)));
            await kind.load(controller, _connectedInstance, 'query-$index');
          }
          await kind.load(controller, _connectedInstance, 'query-0');
          transport.objects.add(_completed(kind.page(16)));
          await kind.load(controller, _connectedInstance, 'query-16');

          expect(kind.ids(controller, _site, 'query-0'), [0]);
          expect(kind.ids(controller, _site, 'query-1'), isEmpty);
          expect(kind.ids(controller, _site, 'query-16'), [16]);
          expect(kind.ids(controller, other.url, 'other'), [99]);
          expect(transport.gets, hasLength(18));

          transport.objects.add(_completed(kind.page(101)));
          await kind.load(controller, _connectedInstance, 'query-1');
          expect(kind.ids(controller, _site, 'query-1'), [101]);
          expect(transport.gets, hasLength(19));
        },
      );

      test(
        'evicts request ownership so late completion cannot replace a reload',
        () async {
          final firstStarted = Completer<void>();
          final first = Completer<Map<String, dynamic>>();
          addTearDown(() {
            if (!first.isCompleted) first.complete(kind.page(1));
          });
          final transport = _ControlledGroupTransport()
            ..objects.add(first)
            ..onGet = (_) {
              if (!firstStarted.isCompleted) firstStarted.complete();
            };
          final credentials = FakeApiCredentialReader()..keys[_site] = 'key';
          final controller = _controller(transport, credentials: credentials);
          addTearDown(controller.dispose);
          final loading = kind.load(controller, _connectedInstance, 'old');
          await firstStarted.future;
          for (var index = 0; index < 16; index++) {
            transport.objects.add(_completed(kind.page(index + 10)));
            await kind.load(controller, _connectedInstance, 'query-$index');
          }
          transport.objects.add(_completed(kind.page(100)));
          await kind.load(controller, _connectedInstance, 'old');
          first.complete(kind.page(1));
          await loading;

          expect(kind.ids(controller, _site, 'old'), [100]);
          expect(transport.gets, hasLength(18));
        },
      );
    });
  }

  for (final kind in _GroupPageCache.values) {
    group('group ${kind.name} retention', () {
      test(
        'keeps sixteen recent groups per forum and refreshes reuse order',
        () async {
          const other = DiscourseInstance(
            url: 'https://other.example',
            title: 'Other',
            user: DiscourseUser(username: 'sam'),
          );
          final transport = _ControlledGroupTransport();
          final credentials = FakeApiCredentialReader()
            ..keys[_site] = 'key'
            ..keys[other.url] = 'other-key';
          final controller = _controller(transport, credentials: credentials);
          addTearDown(controller.dispose);
          kind.respond(transport, 99);
          await kind.load(controller, other, 'other');
          for (var index = 0; index <= 16; index++) {
            kind.respond(transport, index);
            await kind.load(controller, _connectedInstance, 'group-$index');
          }

          expect(kind.ids(controller, _site, 'group-0'), isEmpty);
          for (var index = 1; index <= 16; index++) {
            expect(kind.ids(controller, _site, 'group-$index'), [index]);
          }
          expect(kind.ids(controller, other.url, 'other'), [99]);
          expect(kind.requests(transport), 18);

          await kind.load(controller, _connectedInstance, 'group-1');
          kind.respond(transport, 17);
          await kind.load(controller, _connectedInstance, 'group-17');
          expect(kind.ids(controller, _site, 'group-1'), [1]);
          expect(kind.ids(controller, _site, 'group-2'), isEmpty);
          expect(kind.ids(controller, _site, 'group-17'), [17]);
          expect(kind.requests(transport), 19);

          kind.respond(transport, 100);
          await kind.load(controller, _connectedInstance, 'group-0');
          expect(kind.ids(controller, _site, 'group-0'), [100]);
          expect(kind.requests(transport), 20);
        },
      );

      test('a late page for an evicted group does not repopulate it', () async {
        final started = Completer<void>();
        final transport = _ControlledGroupTransport()
          ..onGet = (_) {
            if (!started.isCompleted) started.complete();
          };
        final release = kind.hold(transport);
        addTearDown(() => release(1));
        final credentials = FakeApiCredentialReader()..keys[_site] = 'key';
        final controller = _controller(transport, credentials: credentials);
        addTearDown(controller.dispose);
        final loading = kind.load(controller, _connectedInstance, 'old');
        await started.future;
        for (var index = 0; index < 16; index++) {
          kind.respond(transport, index + 10);
          await kind.load(controller, _connectedInstance, 'group-$index');
        }
        release(1);
        await loading;

        expect(kind.ids(controller, _site, 'old'), isEmpty);
        for (var index = 0; index < 16; index++) {
          expect(kind.ids(controller, _site, 'group-$index'), [index + 10]);
        }
      });

      test(
        'evicts request ownership so a late page cannot replace a reload',
        () async {
          final started = Completer<void>();
          final transport = _ControlledGroupTransport()
            ..onGet = (_) {
              if (!started.isCompleted) started.complete();
            };
          final release = kind.hold(transport);
          addTearDown(() => release(1));
          final credentials = FakeApiCredentialReader()..keys[_site] = 'key';
          final controller = _controller(transport, credentials: credentials);
          addTearDown(controller.dispose);
          final loading = kind.load(controller, _connectedInstance, 'old');
          await started.future;
          for (var index = 0; index < 16; index++) {
            kind.respond(transport, index + 10);
            await kind.load(controller, _connectedInstance, 'group-$index');
          }
          kind.respond(transport, 100);
          await kind.load(controller, _connectedInstance, 'old');
          release(1);
          await loading;

          expect(kind.ids(controller, _site, 'old'), [100]);
          expect(kind.requests(transport), 18);
        },
      );
    });
  }

  test(
    'a group detail with a write in flight outlives the retention bound',
    () async {
      final transport = _ControlledGroupTransport();
      final credentials = FakeApiCredentialReader()..keys[_site] = 'key';
      final controller = _controller(transport, credentials: credentials);
      addTearDown(controller.dispose);
      const detail = _GroupPageCache.detail;
      detail.respond(transport, 1);
      await controller.loadDetail(_connectedInstance, 'busy');
      final write = transport.holdWrite();
      final joining = controller.join(
        _connectedInstance,
        const Group(id: 1, name: 'busy'),
      );
      await write.started.future;
      for (var index = 0; index < 16; index++) {
        detail.respond(transport, index + 10);
        await controller.loadDetail(_connectedInstance, 'group-$index');
      }

      final pending = controller.detailState(_site, 'busy');
      expect(pending.detail?.group.id, 1);
      expect(pending.mutating, isTrue);
      expect(detail.ids(controller, _site, 'group-0'), [10]);

      detail.respond(transport, 2);
      write.release.complete();
      expect((await joining).canApplyLocally, isTrue);

      expect(detail.ids(controller, _site, 'busy'), [2]);
      expect(detail.ids(controller, _site, 'group-0'), isEmpty);
      expect(detail.ids(controller, _site, 'group-1'), [11]);
    },
  );

  for (final requesters in [false, true]) {
    test(
      '${requesters ? 'requesters' : 'members'} stop when the server repeats an offset',
      () async {
        final transport = _ControlledGroupTransport()
          ..objects.addAll([
            for (var id = 1; id <= 2; id++)
              _completed({
                'members': [
                  {'id': id, 'username': 'user$id'},
                ],
                'meta': {'total': 100, 'limit': 30, 'offset': 0},
              }),
          ]);
        final credentials = FakeApiCredentialReader()..keys[_site] = 'key';
        final controller = _controller(transport, credentials: credentials);
        addTearDown(controller.dispose);
        Future<void> load({bool more = false}) => requesters
            ? controller.loadRequesters(
                _connectedInstance,
                'support',
                more: more,
              )
            : controller.loadMembers(_connectedInstance, 'support', more: more);
        await load();
        await load(more: true);
        final ids = requesters
            ? controller
                  .requestersState(_site, 'support')
                  .requesters
                  .map((member) => member.id)
            : controller
                  .membersState(_site, 'support')
                  .members
                  .map((member) => member.id);
        final hasMore = requesters
            ? controller.requestersState(_site, 'support').hasMore
            : controller.membersState(_site, 'support').hasMore;
        expect(ids, [1, 2]);
        expect(hasMore, isFalse);
        await load(more: true);
        expect(
          transport.gets.map(
            (request) => Uri.parse(request.path).queryParameters['offset'],
          ),
          ['0', '30'],
        );
      },
    );
  }

  for (final removal in _GroupListRemoval.values) {
    group('${removal.name} offset pagination', () {
      late _OffsetGroupTransport transport;
      late GroupsController controller;

      setUp(() {
        transport = _OffsetGroupTransport();
        controller = _controller(
          transport,
          credentials: FakeApiCredentialReader()..keys[_site] = 'key',
        );
        addTearDown(controller.dispose);
      });

      Future<void> drain({String filter = ''}) async {
        for (var page = 0; page < 5; page++) {
          if (!removal.state(controller, filter: filter).hasMore) return;
          await removal.load(controller, filter: filter, more: true);
        }
        fail('Pagination did not terminate.');
      }

      test(
        'keeps every remaining row and only adjusts matching caches',
        () async {
          await removal.load(controller);
          await removal.load(controller, filter: 'alpha');
          await removal.load(controller, filter: 'bravo');
          final unrelated = removal.state(controller, filter: 'alpha');

          expect((await removal.remove(controller, 7)).canApplyLocally, isTrue);

          expect(removal.state(controller).ids, [91, 204]);
          expect(removal.state(controller).total, 9);
          expect(removal.state(controller).nextOffset, 2);
          final unchanged = removal.state(controller, filter: 'alpha');
          expect(unchanged.ids, unrelated.ids);
          expect(unchanged.total, unrelated.total);
          expect(unchanged.nextOffset, unrelated.nextOffset);
          expect(unchanged.hasMore, unrelated.hasMore);
          expect(removal.state(controller, filter: 'bravo').total, 4);
          expect(removal.state(controller, filter: 'bravo').nextOffset, 2);
          expect(transport.pages, hasLength(3));

          await drain();
          await drain(filter: 'alpha');
          await drain(filter: 'bravo');

          for (final filter in ['', 'alpha', 'bravo']) {
            final state = removal.state(controller, filter: filter);
            expect(state.ids, transport.ids(filter));
            expect(state.total, transport.ids(filter).length);
            expect(state.hasMore, isFalse);
            final offsets = transport.pages
                .where((page) => page.filter == filter)
                .map((page) => page.offset);
            expect(
              offsets,
              filter.isEmpty ? [0, 2, 5, 8] : [0, filter == 'alpha' ? 3 : 2],
            );
            expect(
              state.nextOffset,
              offsets.last + _OffsetGroupTransport.pageSize,
            );
          }
          final count = transport.pages.length;
          await removal.load(controller, more: true);
          expect(transport.pages, hasLength(count));
        },
      );

      for (final snapshotBeforeRemoval in [true, false]) {
        test(
          'retries an in-flight page sampled ${snapshotBeforeRemoval ? 'before' : 'after'} removal',
          () async {
            await removal.load(controller);
            final pending = transport.holdPage(
              snapshotBeforeRelease: snapshotBeforeRemoval,
            );
            final loading = removal.load(controller, more: true);
            await pending.started.future;

            expect(
              (await removal.remove(controller, 7)).canApplyLocally,
              isTrue,
            );
            expect(removal.state(controller).ids, [91, 204]);
            expect(removal.state(controller).total, 9);
            expect(removal.state(controller).nextOffset, 2);
            expect(removal.state(controller).loadingMore, isTrue);

            pending.release.complete();
            await loading;
            expect(removal.state(controller).ids, [91, 204, 36, 808, 12]);
            expect(removal.state(controller).total, 9);
            expect(removal.state(controller).nextOffset, 5);
            expect(removal.state(controller).loadingMore, isFalse);
            await drain();

            expect(removal.state(controller).ids, transport.ids(''));
            expect(removal.state(controller).total, 9);
            expect(transport.pages.map((page) => page.offset), [0, 3, 2, 5, 8]);
          },
        );
      }

      test('coalesces multiple removals into one page retry', () async {
        await removal.load(controller);
        final pending = transport.holdPage();
        final loading = removal.load(controller, more: true);
        await pending.started.future;

        expect((await removal.remove(controller, 7)).canApplyLocally, isTrue);
        expect((await removal.remove(controller, 91)).canApplyLocally, isTrue);
        expect(removal.state(controller).ids, [204]);
        expect(removal.state(controller).nextOffset, 1);
        pending.release.complete();
        await loading;
        await drain();

        expect(removal.state(controller).ids, transport.ids(''));
        expect(removal.state(controller).total, 8);
        expect(transport.pages.map((page) => page.offset), [0, 3, 1, 4, 7]);
      });

      test(
        'waits for a removal whose response arrives after the page',
        () async {
          await removal.load(controller);
          final pending = transport.holdPage(snapshotBeforeRelease: false);
          final loading = removal.load(controller, more: true);
          await pending.started.future;
          final writing = transport.holdWrite();
          final removing = removal.remove(controller, 7);
          await writing.started.future;

          pending.release.complete();
          await pumpEventQueue();
          writing.release.complete();
          expect((await removing).canApplyLocally, isTrue);
          await loading;
          await drain();

          expect(removal.state(controller).ids, transport.ids(''));
          expect(removal.state(controller).total, 9);
          expect(transport.pages.map((page) => page.offset), [0, 3, 2, 5, 8]);
        },
      );

      test(
        'a failed removal releases the page without changing its window',
        () async {
          await removal.load(controller);
          final pending = transport.holdPage();
          final loading = removal.load(controller, more: true);
          await pending.started.future;
          final writing = transport.holdWrite();
          transport.rejectWrites = true;
          final removing = removal.remove(controller, 7);
          await writing.started.future;

          pending.release.complete();
          await pumpEventQueue();
          writing.release.complete();
          expect((await removing).canApplyLocally, isFalse);
          await loading;
          await drain();

          expect(removal.state(controller).ids, transport.ids(''));
          expect(removal.state(controller).total, 10);
          expect(transport.pages.map((page) => page.offset), [0, 3, 6, 9]);
        },
      );

      test('forget releases a page waiting for a removal response', () async {
        await removal.load(controller);
        final pending = transport.holdPage();
        final loading = removal.load(controller, more: true);
        await pending.started.future;
        final writing = transport.holdWrite();
        final removing = removal.remove(controller, 7);
        await writing.started.future;

        pending.release.complete();
        await pumpEventQueue();
        controller.forget(_site);
        await loading;
        expect(removal.state(controller).ids, isEmpty);
        expect(transport.pages, hasLength(2));
        writing.release.complete();
        expect((await removing).canApplyLocally, isFalse);
      });

      test('a refresh cannot resurrect a removed row', () async {
        await removal.load(controller);
        final pending = transport.holdPage();
        final loading = removal.load(controller, refresh: true);
        await pending.started.future;
        expect((await removal.remove(controller, 7)).canApplyLocally, isTrue);
        final observed = <int>[];
        controller.addListener(
          () => observed.addAll(removal.state(controller).ids),
        );

        pending.release.complete();
        await loading;
        await drain();

        expect(observed, isNot(contains(7)));
        expect(removal.state(controller).ids, transport.ids(''));
        expect(removal.state(controller).total, 9);
        expect(transport.pages.map((page) => page.offset), [0, 0, 0, 3, 6]);
      });

      test('leaves an unrelated filtered page in flight alone', () async {
        await removal.load(controller);
        await removal.load(controller, filter: 'alpha');
        final pending = transport.holdPage();
        final loading = removal.load(controller, filter: 'alpha', more: true);
        await pending.started.future;

        expect((await removal.remove(controller, 7)).canApplyLocally, isTrue);
        final state = removal.state(controller, filter: 'alpha');
        expect(state.total, 5);
        expect(state.nextOffset, 3);
        expect(state.loadingMore, isTrue);
        pending.release.complete();
        await loading;

        expect(
          removal.state(controller, filter: 'alpha').ids,
          transport.ids('alpha'),
        );
        expect(removal.state(controller, filter: 'alpha').total, 5);
        expect(transport.pages.map((page) => page.offset), [0, 0, 3]);
      });
    });
  }

  test(
    'group logs stop after an empty page despite an incomplete marker',
    () async {
      final transport = _ControlledGroupTransport()
        ..objects.add(_completed({'logs': <Object?>[], 'all_loaded': false}));
      final credentials = FakeApiCredentialReader()..keys[_site] = 'key';
      final controller = _controller(transport, credentials: credentials);
      addTearDown(controller.dispose);
      await controller.loadLogs(_connectedInstance, 'support');
      expect(controller.logsState(_site, 'support').hasMore, isFalse);
      await controller.loadLogs(_connectedInstance, 'support', more: true);
      expect(transport.gets, hasLength(1));
    },
  );

  test(
    'activity stops when a full page repeats the same timestamp cursor',
    () async {
      final payload = <String, dynamic>{
        'posts': [
          for (var id = 1; id <= 20; id++)
            {'id': id, 'topic_id': id, 'created_at': '2026-09-01T12:00:00Z'},
        ],
      };
      final transport = _ControlledGroupTransport()
        ..objects.addAll([_completed(payload), _completed(payload)]);
      final controller = _controller(transport);
      addTearDown(controller.dispose);
      await controller.loadActivity(_instance, 'support', mentions: false);
      expect(
        controller.activityState(_site, 'support', mentions: false).hasMore,
        isTrue,
      );
      await controller.loadActivity(
        _instance,
        'support',
        mentions: false,
        more: true,
      );
      final state = controller.activityState(_site, 'support', mentions: false);
      expect(
        state.posts.map((post) => post.id),
        List.generate(20, (index) => index + 1),
      );
      expect(state.hasMore, isFalse);
      await controller.loadActivity(
        _instance,
        'support',
        mentions: false,
        more: true,
      );
      expect(transport.gets, hasLength(2));
    },
  );

  for (final mentions in [false, true]) {
    final kind = mentions ? 'mentions' : 'posts';
    test(
      '$kind continues after a full raw page with a non-object slot',
      () async {
        final transport = _ControlledGroupTransport()
          ..objects.addAll([
            _completed({
              'posts': [
                for (var id = 1; id <= 20; id++)
                  if (id == 10)
                    null
                  else
                    {
                      'id': id,
                      'topic_id': id,
                      'created_at': DateTime.utc(
                        2026,
                        9,
                        1,
                        12,
                        0,
                        20 - id,
                      ).toIso8601String(),
                    },
              ],
            }),
            _completed({
              'posts': [
                {
                  'id': 21,
                  'topic_id': 21,
                  'created_at': '2026-08-31T12:00:00Z',
                },
                {
                  'id': 22,
                  'topic_id': 22,
                  'created_at': '2026-08-30T12:00:00Z',
                },
              ],
            }),
          ]);
        final controller = _controller(transport);
        addTearDown(controller.dispose);

        await controller.loadActivity(_instance, 'support', mentions: mentions);
        final first = controller.activityState(
          _site,
          'support',
          mentions: mentions,
        );
        expect(first.error, isNull);
        expect(first.posts, hasLength(19));
        expect(first.hasMore, isTrue);
        expect(transport.gets.single.path, '/groups/support/$kind.json');

        await controller.loadActivity(
          _instance,
          'support',
          mentions: mentions,
          more: true,
        );
        final state = controller.activityState(
          _site,
          'support',
          mentions: mentions,
        );
        expect(state.error, isNull);
        expect(state.posts.map((post) => post.id), [
          for (var id = 1; id <= 22; id++)
            if (id != 10) id,
        ]);
        expect(state.hasMore, isFalse);
        expect(transport.gets, hasLength(2));
        final request = Uri.parse(transport.gets.last.path);
        expect(request.path, '/groups/support/$kind.json');
        expect(request.queryParameters, {'before': '2026-09-01T12:00:00.000Z'});

        await controller.loadActivity(
          _instance,
          'support',
          mentions: mentions,
          more: true,
        );
        expect(transport.gets, hasLength(2));
      },
    );

    test('$kind stops when a mixed page has no final timestamp', () async {
      final transport = _ControlledGroupTransport()
        ..objects.add(
          _completed({
            'posts': [
              for (var id = 1; id <= 20; id++)
                if (id == 10)
                  null
                else
                  {
                    'id': id,
                    'topic_id': id,
                    if (id < 20) 'created_at': '2026-09-01T12:00:00Z',
                  },
            ],
          }),
        );
      final controller = _controller(transport);
      addTearDown(controller.dispose);

      await controller.loadActivity(_instance, 'support', mentions: mentions);
      final state = controller.activityState(
        _site,
        'support',
        mentions: mentions,
      );
      expect(state.error, isNull);
      expect(state.posts, hasLength(19));
      expect(state.hasMore, isFalse);

      await controller.loadActivity(
        _instance,
        'support',
        mentions: mentions,
        more: true,
      );
      expect(transport.gets, hasLength(1));
    });
  }

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
            'load_more_groups': '/groups?page=2',
          }),
        ]);
      final controller = _controller(transport);
      addTearDown(controller.dispose);
      const query = GroupDirectoryQuery();

      await controller.loadDirectory(_instance, query);
      final confirmed = controller.directoryState(_site, query);
      (firstPayload['groups'] as List<Object?>).add({'id': 99, 'name': 'late'});

      expect(confirmed.groups.map((group) => group.id), [1]);
      expect(confirmed.hasMore, isTrue);
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
      await controller.loadDirectory(_instance, query, more: true);
      expect(transport.gets.map((request) => request.path), [
        '/groups.json?asc=true',
        '/groups.json?page=1&asc=true',
      ]);
      expect(transport.gets.every((request) => request.apiKey == null), isTrue);
    },
  );

  for (final count in [0, 1]) {
    test(
      'directory stops when the first page contains all $count groups',
      () async {
        final transport = _ControlledGroupTransport()
          ..objects.add(
            _completed({
              'groups': [
                for (var i = 0; i < count; i++) {'id': i, 'name': 'group-$i'},
              ],
              'total_rows_groups': count,
              'load_more_groups': '/groups?page=1',
            }),
          );
        final controller = _controller(transport);
        addTearDown(controller.dispose);
        const query = GroupDirectoryQuery();

        await controller.loadDirectory(_instance, query);

        final state = controller.directoryState(_site, query);
        expect(state.groups, hasLength(count));
        expect(state.hasMore, isFalse);
        await controller.loadDirectory(_instance, query, more: true);
        expect(transport.gets, hasLength(1));
      },
    );
  }

  test(
    'directory stops after an empty page even if the total is stale',
    () async {
      final transport = _ControlledGroupTransport()
        ..objects.addAll([
          _completed({
            'groups': [
              {'id': 1, 'name': 'alpha'},
            ],
            'total_rows_groups': 2,
            'load_more_groups': '/groups?page=1',
          }),
          _completed({
            'groups': <Object?>[],
            'total_rows_groups': 2,
            'load_more_groups': '/groups?page=2',
          }),
        ]);
      final controller = _controller(transport);
      addTearDown(controller.dispose);
      const query = GroupDirectoryQuery();

      await controller.loadDirectory(_instance, query);
      await controller.loadDirectory(_instance, query, more: true);

      final state = controller.directoryState(_site, query);
      expect(state.groups.map((group) => group.id), [1]);
      expect(state.hasMore, isFalse);
      expect(state.loadingMore, isFalse);
      expect(state.error, isNull);
      await controller.loadDirectory(_instance, query, more: true);
      expect(transport.gets, hasLength(2));
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

      expect(saved.canApplyLocally, isTrue);
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

  test('a member removed while the next page loads stays removed', () async {
    final nextPage = Completer<Map<String, dynamic>>();
    final transport = _ControlledGroupTransport()
      ..objects.addAll([
        _completed({
          'members': [
            {'id': 1, 'username': 'sam'},
            {'id': 2, 'username': 'lee'},
          ],
          'owners': <Object?>[],
          'meta': {'total': 3, 'limit': 2, 'offset': 0},
        }),
        nextPage,
        _completed(<String, dynamic>{}),
        _completed({
          'members': [
            {'id': 3, 'username': 'kim'},
          ],
          'meta': {'total': 2, 'limit': 2, 'offset': 1},
        }),
      ]);
    final credentials = FakeApiCredentialReader(clientIdValue: 'native-client')
      ..keys[_site] = 'secret';
    final controller = _controller(transport, credentials: credentials);
    addTearDown(controller.dispose);
    const group = Group(id: 7, name: 'support');

    await controller.loadMembers(_connectedInstance, group.name);
    final held = controller.membersState(_site, group.name);
    expect(held.hasMore, isTrue);
    final pageLoad = controller.loadMembers(
      _connectedInstance,
      group.name,
      more: true,
    );
    await pumpEventQueue();
    expect(transport.gets, hasLength(2));

    final removed = await controller.removeMember(
      _connectedInstance,
      group,
      held.members.first,
    );
    expect(removed.canApplyLocally, isTrue);
    expect(
      controller.membersState(_site, group.name).members.map((m) => m.id),
      [2],
    );

    nextPage.complete({
      'members': [
        {'id': 1, 'username': 'sam'},
        {'id': 3, 'username': 'kim'},
      ],
      'owners': <Object?>[],
      'meta': {'total': 3, 'limit': 2, 'offset': 2},
    });
    await pageLoad;

    final state = controller.membersState(_site, group.name);
    expect(state.members.map((member) => member.id), [2, 3]);
    expect(state.total, 2);
    expect(state.nextOffset, 3);
    expect(state.loadingMore, isFalse);
  });

  test(
    'members added while the next page loads are shown by the refresh',
    () async {
      final nextPage = Completer<Map<String, dynamic>>();
      final transport = _ControlledGroupTransport()
        ..objects.addAll([
          _completed({
            'members': [
              {'id': 1, 'username': 'sam'},
              {'id': 2, 'username': 'lee'},
            ],
            'owners': <Object?>[],
            'meta': {'total': 3, 'limit': 2, 'offset': 0},
          }),
          nextPage,
          _completed(<String, dynamic>{}),
          _completed({
            'members': [
              {'id': 1, 'username': 'sam'},
              {'id': 2, 'username': 'lee'},
              {'id': 4, 'username': 'ada'},
            ],
            'owners': <Object?>[],
            'meta': {'total': 4, 'limit': 50, 'offset': 0},
          }),
        ]);
      final credentials = FakeApiCredentialReader(
        clientIdValue: 'native-client',
      )..keys[_site] = 'secret';
      final controller = _controller(transport, credentials: credentials);
      addTearDown(controller.dispose);
      const group = Group(id: 7, name: 'support');

      await controller.loadMembers(_connectedInstance, group.name);
      final pageLoad = controller.loadMembers(
        _connectedInstance,
        group.name,
        more: true,
      );
      await pumpEventQueue();
      expect(transport.gets, hasLength(2));

      final added = await controller.addMembers(
        _connectedInstance,
        group,
        GroupAddMembersCommand(usernames: const ['ada']),
      );
      expect(added.canApplyLocally, isTrue);
      expect(transport.gets, hasLength(4));
      expect(
        controller.membersState(_site, group.name).members.map((m) => m.id),
        [1, 2, 4],
      );

      nextPage.complete({
        'members': [
          {'id': 3, 'username': 'kim'},
        ],
        'owners': <Object?>[],
        'meta': {'total': 3, 'limit': 2, 'offset': 2},
      });
      await pageLoad;

      final state = controller.membersState(_site, group.name);
      expect(state.members.map((member) => member.id), [1, 2, 4]);
      expect(state.total, 4);
      expect(state.loadingMore, isFalse);
    },
  );

  test('a member removed while the next page fails stays removed', () async {
    final nextPage = Completer<Map<String, dynamic>>();
    final transport = _ControlledGroupTransport()
      ..objects.addAll([
        _completed({
          'members': [
            {'id': 1, 'username': 'sam'},
            {'id': 2, 'username': 'lee'},
          ],
          'owners': <Object?>[],
          'meta': {'total': 3, 'limit': 2, 'offset': 0},
        }),
        nextPage,
        _completed(<String, dynamic>{}),
      ]);
    final credentials = FakeApiCredentialReader(clientIdValue: 'native-client')
      ..keys[_site] = 'secret';
    final controller = _controller(transport, credentials: credentials);
    addTearDown(controller.dispose);
    const group = Group(id: 7, name: 'support');

    await controller.loadMembers(_connectedInstance, group.name);
    final held = controller.membersState(_site, group.name);
    final pageLoad = controller.loadMembers(
      _connectedInstance,
      group.name,
      more: true,
    );
    await pumpEventQueue();
    expect(
      (await controller.removeMember(
        _connectedInstance,
        group,
        held.members.first,
      )).canApplyLocally,
      isTrue,
    );

    nextPage.completeError(StateError('members unavailable'));
    await pageLoad;

    final state = controller.membersState(_site, group.name);
    expect(state.members.map((member) => member.id), [2]);
    expect(state.total, 2);
    expect(state.pageError, isTrue);
    expect(state.loadingMore, isFalse);
  });

  test(
    'a deleted group directory can reload before its old page returns',
    () async {
      final pageStarted = Completer<void>();
      final nextPage = Completer<Map<String, dynamic>>();
      final transport = _ControlledGroupTransport()
        ..onGet = (path) {
          if (path == '/groups.json?page=1&asc=true') pageStarted.complete();
        }
        ..objects.addAll([
          _completed({
            'groups': [
              {'id': 7, 'name': 'support'},
              {'id': 8, 'name': 'other'},
            ],
            'total_rows_groups': 3,
            'load_more_groups': '/groups?page=1',
          }),
          nextPage,
          _completed({
            'groups': [
              {'id': 8, 'name': 'other'},
              {'id': 9, 'name': 'third'},
            ],
            'total_rows_groups': 2,
          }),
        ]);
      final credentials = FakeApiCredentialReader(
        clientIdValue: 'native-client',
      )..keys[_site] = 'secret';
      final controller = _controller(transport, credentials: credentials);
      addTearDown(controller.dispose);
      const query = GroupDirectoryQuery();

      await controller.loadDirectory(_connectedInstance, query);
      expect(controller.directoryState(_site, query).hasMore, isTrue);
      final pageLoad = controller.loadDirectory(
        _connectedInstance,
        query,
        more: true,
      );
      await pageStarted.future;
      expect(transport.gets, hasLength(2));
      expect(
        (await controller.deleteGroup(
          _connectedInstance,
          const Group(id: 7, name: 'support'),
        )).canApplyLocally,
        isTrue,
      );

      await controller.loadDirectory(_connectedInstance, query);
      final reloaded = controller.directoryState(_site, query);
      expect(reloaded.loaded, isTrue);
      expect(reloaded.groups.map((group) => group.id), [8, 9]);
      expect(reloaded.totalRows, 2);

      nextPage.complete({
        'groups': [
          {'id': 9, 'name': 'third'},
        ],
        'total_rows_groups': 3,
      });
      await pageLoad;

      final state = controller.directoryState(_site, query);
      expect(state, same(reloaded));
      expect(state.loadingMore, isFalse);
    },
  );

  test(
    'deleted group reads cannot restore its detail or permissions',
    () async {
      final readsStarted = Completer<void>();
      var starts = 0;
      final detail = Completer<Map<String, dynamic>>();
      final otherDetail = Completer<Map<String, dynamic>>();
      final permissions = Completer<List<Map<String, dynamic>>>();
      final transport = _ControlledGroupTransport()
        ..onGet = (_) {
          if (++starts == 3) readsStarted.complete();
        }
        ..objects.addAll([detail, otherDetail])
        ..lists.add(permissions);
      final credentials = FakeApiCredentialReader(
        clientIdValue: 'native-client',
      )..keys[_site] = 'secret';
      final controller = _controller(transport, credentials: credentials);
      addTearDown(controller.dispose);

      final detailLoad = controller.loadDetail(_connectedInstance, 'support');
      final permissionLoad = controller.loadPermissions(
        _connectedInstance,
        'support',
      );
      final otherLoad = controller.loadDetail(_connectedInstance, 'other');
      await readsStarted.future;
      expect(transport.gets, hasLength(2));
      expect(transport.listGets, hasLength(1));

      expect(
        (await controller.deleteGroup(
          _connectedInstance,
          const Group(id: 7, name: 'Support'),
        )).canApplyLocally,
        isTrue,
      );
      detail.complete({
        'group': {'id': 7, 'name': 'support'},
      });
      permissions.complete([]);
      otherDetail.complete({
        'group': {'id': 8, 'name': 'other'},
      });
      await Future.wait([detailLoad, permissionLoad, otherLoad]);

      expect(controller.detailState(_site, 'support').loaded, isFalse);
      expect(controller.permissionsState(_site, 'support').loaded, isFalse);
      expect(controller.detailState(_site, 'other').detail?.group.id, 8);
    },
  );

  test(
    'an expired group mutation does not refresh the new account members',
    () async {
      final detailStarted = Completer<void>();
      final detail = Completer<Map<String, dynamic>>();
      final transport = _ControlledGroupTransport()
        ..onGet = (path) {
          if (path == '/groups/support.json') detailStarted.complete();
        }
        ..objects.addAll([
          detail,
          _completed({'members': <Object?>[]}),
        ]);
      final lifecycle = SiteLifecycle();
      final credentials = FakeApiCredentialReader(
        clientIdValue: 'native-client',
      )..keys[_site] = 'old-secret';
      final controller = _controller(
        transport,
        credentials: credentials,
        lifecycle: lifecycle,
      );
      addTearDown(controller.dispose);

      final mutation = controller.addMembers(
        _connectedInstance,
        const Group(id: 7, name: 'support'),
        GroupAddMembersCommand(usernames: const ['lee']),
      );
      await detailStarted.future;
      expect(transport.writes, hasLength(1));
      expect(transport.gets.map((request) => request.path), [
        '/groups/support.json',
      ]);
      lifecycle.invalidate(_site);
      controller.forget(_site);
      credentials.keys[_site] = 'new-secret';
      detail.complete({
        'group': {'id': 7, 'name': 'support'},
      });

      expect((await mutation).canApplyLocally, isFalse);
      expect(transport.gets, [
        (
          path: '/groups/support.json',
          apiKey: 'old-secret',
          clientId: 'native-client',
        ),
      ]);
      expect(controller.membersState(_site, 'support').loaded, isFalse);
    },
  );

  test('a request handled while the next page loads stays handled', () async {
    final nextPage = Completer<Map<String, dynamic>>();
    final transport = _ControlledGroupTransport()
      ..objects.addAll([
        _completed({
          'members': [
            {'id': 1, 'username': 'sam'},
            {'id': 2, 'username': 'lee'},
          ],
          'meta': {'total': 3, 'limit': 2, 'offset': 0},
        }),
        nextPage,
        _completed({
          'members': [
            {'id': 3, 'username': 'kim'},
          ],
          'meta': {'total': 2, 'limit': 2, 'offset': 1},
        }),
      ]);
    final credentials = FakeApiCredentialReader(clientIdValue: 'native-client')
      ..keys[_site] = 'secret';
    final controller = _controller(transport, credentials: credentials);
    addTearDown(controller.dispose);
    const group = Group(id: 7, name: 'support');

    await controller.loadRequesters(_connectedInstance, group.name);
    final held = controller.requestersState(_site, group.name);
    expect(held.hasMore, isTrue);
    final pageLoad = controller.loadRequesters(
      _connectedInstance,
      group.name,
      more: true,
    );
    await pumpEventQueue();
    expect(transport.gets, hasLength(2));

    final handled = await controller.handleRequest(
      _connectedInstance,
      group,
      held.requesters.first,
      accept: true,
    );
    expect(handled.canApplyLocally, isTrue);

    nextPage.complete({
      'members': [
        {'id': 3, 'username': 'kim'},
      ],
      'meta': {'total': 3, 'limit': 2, 'offset': 2},
    });
    await pageLoad;

    final state = controller.requestersState(_site, group.name);
    expect(state.requesters.map((requester) => requester.id), [2, 3]);
    expect(state.total, 2);
    expect(state.nextOffset, 3);
  });

  test(
    'a sent membership request answers with the message it opened',
    () async {
      final transport = _ControlledGroupTransport()
        ..onWrite = (_) => {
          'success': 'OK',
          'relative_url': '/t/membership-request-from-sam-to-support/42',
        };
      final credentials = FakeApiCredentialReader(
        clientIdValue: 'native-client',
      )..keys[_site] = 'secret';
      final controller = _controller(transport, credentials: credentials);
      addTearDown(controller.dispose);

      final result = await controller.requestMembership(
        _connectedInstance,
        const Group(id: 7, name: 'support', allowMembershipRequests: true),
        'I run the help desk.',
      );

      expect(
        result,
        isA<GroupWriteAccepted<String?>>().having(
          (sent) => sent.value,
          'messageUrl',
          '/t/membership-request-from-sam-to-support/42',
        ),
      );
      expect(
        transport.writes.single.path,
        '/groups/support/request_membership.json',
      );
      // Nothing the group payload reports changes, so the message is not held
      // behind a re-read of the group.
      expect(transport.gets, isEmpty);
      expect(controller.detailState(_site, 'support').mutating, isFalse);
    },
  );

  for (final (name, failure, message) in [
    (
      'the site refusal',
      const WriteException(
        WriteFailure.conflict,
        errors: ['You have already requested membership for this group.'],
        statusCode: 409,
      ),
      'You have already requested membership for this group.',
    ),
    (
      'the generic failure without a site message',
      const WriteException(WriteFailure.unreachable),
      "Couldn't save that group change.",
    ),
    (
      'the generic failure for a local error',
      StateError('unexpected'),
      "Couldn't save that group change.",
    ),
  ]) {
    test('a failed membership request answers with $name', () async {
      final transport = _ControlledGroupTransport()
        ..onWrite = (_) => throw failure;
      final credentials = FakeApiCredentialReader(
        clientIdValue: 'native-client',
      )..keys[_site] = 'secret';
      final controller = _controller(transport, credentials: credentials);
      addTearDown(controller.dispose);

      final result = await controller.requestMembership(
        _connectedInstance,
        const Group(id: 7, name: 'support', allowMembershipRequests: true),
        'I run the help desk.',
      );

      expect(
        result,
        isA<GroupWriteFailed<String?>>().having(
          (failed) =>
              failed.error is WriteException &&
                  (failed.error as WriteException).errors.isNotEmpty
              ? (failed.error as WriteException).message
              : "Couldn't save that group change.",
          'message',
          message,
        ),
      );
      expect(controller.detailState(_site, 'support').mutating, isFalse);
    });
  }

  test('a superseded membership request answers with nothing', () async {
    final transport = _ControlledGroupTransport()
      ..onWrite = (_) => throw const WriteException(
        WriteFailure.conflict,
        errors: ['You have already requested membership for this group.'],
        statusCode: 409,
      );
    final credentials = FakeApiCredentialReader(clientIdValue: 'native-client')
      ..keys[_site] = 'secret';
    final lifecycle = SiteLifecycle();
    final controller = _controller(
      transport,
      credentials: credentials,
      lifecycle: lifecycle,
    );
    addTearDown(controller.dispose);
    final write = transport.holdWrite();

    final request = controller.requestMembership(
      _connectedInstance,
      const Group(id: 7, name: 'support', allowMembershipRequests: true),
      'I run the help desk.',
    );
    await write.started.future;
    lifecycle.invalidate(_site);
    controller.forget(_site);
    write.release.complete();

    expect(await request, isA<GroupWriteFailed<String?>>());
  });

  group('group write outcomes', () {
    const target = Group(id: 7, name: 'support');

    test('server acceptance survives a failed detail refresh', () async {
      final transport = _ControlledGroupTransport()
        ..objects.add(
          _completed({
            'group': {'id': 7, 'name': 'support'},
          }),
        )
        ..onGet = (_) => throw StateError('refresh failed');
      final credentials = FakeApiCredentialReader()..keys[_site] = 'secret';
      final controller = _controller(transport, credentials: credentials);
      addTearDown(controller.dispose);
      final result = await controller.updateGroup(
        _connectedInstance,
        target,
        GroupUpdateCommand(const {'full_name': 'Saved'}),
      );
      expect(
        result,
        isA<GroupWriteAccepted<void>>().having(
          (value) => value.projection,
          'projection',
          GroupProjectionFreshness.stale,
        ),
      );
      expect(result.canApplyLocally, isTrue);
      expect(controller.detailState(_site, target.name).error, isNotNull);
      expect(transport.writes, hasLength(1));
    });

    for (final notSent in [true, false]) {
      test('unreachable retains notSent=$notSent without a retry', () async {
        final transport = _ControlledGroupTransport()
          ..onWrite = (_) =>
              throw WriteException(WriteFailure.unreachable, notSent: notSent);
        final credentials = FakeApiCredentialReader()..keys[_site] = 'secret';
        final controller = _controller(transport, credentials: credentials);
        addTearDown(controller.dispose);
        final result = await controller.requestMembership(
          _connectedInstance,
          target,
          'reason',
        );
        expect(
          result,
          isA<GroupWriteFailed<String?>>().having(
            (value) => value.delivery,
            'delivery',
            notSent ? GroupWriteDelivery.notSent : GroupWriteDelivery.uncertain,
          ),
        );
        expect(transport.writes, hasLength(1));
      });
    }

    test(
      'an accepted answer after retirement keeps its server truth',
      () async {
        final transport = _ControlledGroupTransport()
          ..onWrite = (_) => {'relative_url': '/t/request/42'};
        final credentials = FakeApiCredentialReader()..keys[_site] = 'secret';
        final lifecycle = SiteLifecycle();
        final controller = _controller(
          transport,
          credentials: credentials,
          lifecycle: lifecycle,
        );
        addTearDown(controller.dispose);
        final write = transport.holdWrite();
        final pending = controller.requestMembership(
          _connectedInstance,
          target,
          'reason',
        );
        await write.started.future;
        lifecycle.invalidate(_site);
        controller.forget(_site);
        write.release.complete();
        final result = await pending;
        expect(
          result,
          isA<GroupWriteAccepted<String?>>()
              .having((value) => value.value, 'message', '/t/request/42')
              .having(
                (value) => value.projection,
                'projection',
                GroupProjectionFreshness.retired,
              ),
        );
        expect(result.canApplyLocally, isFalse);
        expect(controller.detailState(_site, target.name).detail, isNull);
      },
    );

    test('admission reports missing credentials and busy separately', () async {
      final transport = _ControlledGroupTransport();
      final credentials = FakeApiCredentialReader();
      final controller = _controller(transport, credentials: credentials);
      addTearDown(controller.dispose);
      expect(
        await controller.join(_connectedInstance, target),
        isA<GroupWriteNotAdmitted<void>>().having(
          (value) => value.reason,
          'reason',
          GroupWriteAdmission.noCredentials,
        ),
      );
      expect(controller.detailState(_site, target.name).mutating, isFalse);
      credentials.keys[_site] = 'secret';
      final write = transport.holdWrite();
      final first = controller.requestMembership(
        _connectedInstance,
        target,
        'reason',
      );
      await write.started.future;
      expect(
        await controller.join(_connectedInstance, target),
        isA<GroupWriteNotAdmitted<void>>().having(
          (value) => value.reason,
          'reason',
          GroupWriteAdmission.busy,
        ),
      );
      write.release.complete();
      await first;
      expect(transport.writes, hasLength(1));
    });

    test(
      'member command snapshots lazy inputs before credential loading',
      () async {
        final usernames = ['lee'];
        final emails = ['lee@example.com'];
        final credentials = _HeldGroupCredentials();
        final transport = _ControlledGroupTransport()
          ..objects.addAll([
            _completed({
              'group': {'id': 7, 'name': 'support'},
            }),
            _completed({'members': <Object?>[]}),
          ]);
        final controller = _controller(transport, credentials: credentials);
        addTearDown(controller.dispose);
        final pending = controller.addMembers(
          _connectedInstance,
          target,
          GroupAddMembersCommand(
            usernames: usernames.where((_) => true),
            emails: emails,
          ),
        );
        usernames.add('changed');
        emails.clear();
        credentials.key.complete('secret');
        final result = await pending;
        expect(result.canApplyLocally, isTrue);
        expect(transport.writes.single.body, {
          'usernames': 'lee',
          'emails': 'lee@example.com',
          'notify_users': true,
        });
      },
    );
  });

  group('a save core holds for existing members', () {
    const values = {'default_notification_level': 2};
    const held = WriteException(
      WriteFailure.validation,
      errors: ['This change affects 3 existing group members.'],
      statusCode: 422,
      affectedUserCount: 3,
    );

    ({_ControlledGroupTransport transport, GroupsController controller})
    heldSave({SiteLifecycle? lifecycle, WriteException first = held}) {
      final transport = _ControlledGroupTransport();
      var writes = 0;
      transport.onWrite = (_) {
        if (writes++ == 0) throw first;
        return const {'success': 'OK'};
      };
      transport.objects.add(
        _completed({
          'group': {'id': 7, 'name': 'support'},
        }),
      );
      final credentials = FakeApiCredentialReader(
        clientIdValue: 'native-client',
      )..keys[_site] = 'secret';
      final controller = _controller(
        transport,
        credentials: credentials,
        lifecycle: lifecycle,
      );
      addTearDown(controller.dispose);
      return (transport: transport, controller: controller);
    }

    for (final (answer, sent) in [(true, 'true'), (false, 'false')]) {
      test('is sent again with the answer $answer', () async {
        final (:transport, :controller) = heldSave();
        final result = await controller.updateGroup(
          _connectedInstance,
          const Group(id: 7, name: 'support'),
          GroupUpdateCommand(values),
        );
        expect(
          result,
          isA<GroupUpdateConfirmation>().having(
            (value) => value.affectedUserCount,
            'affected users',
            3,
          ),
        );
        final saved = await controller.confirmUpdate(
          result as GroupUpdateConfirmation,
          applyToExistingUsers: answer,
        );
        expect(saved.canApplyLocally, isTrue);
        expect(transport.writes.map((write) => write.body), [
          {'group': values},
          {'group': values, 'update_existing_users': sent},
        ]);
        expect(controller.detailState(_site, 'support').mutating, isFalse);
      });
    }

    Future<GroupUpdateConfirmation> confirmation(
      GroupsController controller, [
      Map<String, Object?> input = values,
    ]) async =>
        await controller.updateGroup(
              _connectedInstance,
              const Group(id: 7, name: 'support'),
              GroupUpdateCommand(input),
            )
            as GroupUpdateConfirmation;

    test('is abandoned when the question is dismissed', () async {
      final (:transport, :controller) = heldSave();
      final pending = await confirmation(controller);
      controller.cancelUpdate(pending);
      expect(
        (await controller.confirmUpdate(
          pending,
          applyToExistingUsers: true,
        )).canApplyLocally,
        isFalse,
      );
      expect(transport.writes, hasLength(1));
    });

    test('is not sent again for another account', () async {
      final lifecycle = SiteLifecycle();
      final (:transport, :controller) = heldSave(lifecycle: lifecycle);
      final pending = await confirmation(controller);
      lifecycle.invalidate(_site);
      expect(
        (await controller.confirmUpdate(
          pending,
          applyToExistingUsers: true,
        )).canApplyLocally,
        isFalse,
      );
      expect(transport.writes, hasLength(1));
    });

    test(
      'a refusal without a member count does not create a continuation',
      () async {
        final (:transport, :controller) = heldSave(
          first: const WriteException(
            WriteFailure.validation,
            errors: ['Name has already been taken'],
            statusCode: 422,
          ),
        );
        final result = await controller.updateGroup(
          _connectedInstance,
          const Group(id: 7, name: 'support'),
          GroupUpdateCommand(values),
        );
        expect(
          result,
          isA<GroupWriteFailed<void>>().having(
            (value) => value.delivery,
            'delivery',
            GroupWriteDelivery.refused,
          ),
        );
        expect(transport.writes, hasLength(1));
      },
    );

    test(
      'confirmation preserves original nested input across both attempts',
      () async {
        final (:transport, :controller) = heldSave();
        final ids = [1, 2];
        final input = <String, Object?>{
          'watching_category_ids': ids,
          'bio_raw': '  original\n',
        };
        final saving = controller.updateGroup(
          _connectedInstance,
          const Group(id: 7, name: 'support'),
          GroupUpdateCommand(input),
        );
        ids.add(3);
        input['bio_raw'] = 'changed before credentials';
        final pending = await saving as GroupUpdateConfirmation;
        ids.clear();
        input.clear();
        expect(
          (await controller.confirmUpdate(
            pending,
            applyToExistingUsers: false,
          )).canApplyLocally,
          isTrue,
        );
        for (final write in transport.writes) {
          expect(write.body['group'], {
            'watching_category_ids': [1, 2],
            'bio_raw': '  original\n',
          });
        }
      },
    );

    test('another admitted write expires a pending confirmation', () async {
      final (:transport, :controller) = heldSave();
      final pending = await confirmation(controller);
      await controller.createInvite(
        _connectedInstance,
        const Group(id: 7, name: 'support'),
      );
      final result = await controller.confirmUpdate(
        pending,
        applyToExistingUsers: true,
      );
      expect(
        result,
        isA<GroupWriteNotAdmitted<void>>().having(
          (value) => value.reason,
          'reason',
          GroupWriteAdmission.expiredConfirmation,
        ),
      );
      expect(transport.writes, hasLength(2));
    });

    test(
      'confirmation belongs to its controller and can only be used once',
      () async {
        final (:transport, :controller) = heldSave();
        final other = _controller(_ControlledGroupTransport());
        addTearDown(other.dispose);
        final pending = await confirmation(controller);
        expect(
          (await other.confirmUpdate(
            pending,
            applyToExistingUsers: true,
          )).canApplyLocally,
          isFalse,
        );
        expect(
          (await controller.confirmUpdate(
            pending,
            applyToExistingUsers: true,
          )).canApplyLocally,
          isTrue,
        );
        expect(
          (await controller.confirmUpdate(
            pending,
            applyToExistingUsers: true,
          )).canApplyLocally,
          isFalse,
        );
        expect(transport.writes, hasLength(2));
      },
    );

    test(
      'a completion observer cannot attach an old confirmation to a newer attempt',
      () async {
        final (:transport, :controller) = heldSave();
        Future<GroupWriteOutcome<GroupInvite>>? intervening;
        controller.addListener(() {
          if (intervening != null ||
              transport.writes.isEmpty ||
              controller.detailState(_site, 'support').mutating) {
            return;
          }
          intervening = controller.createInvite(
            _connectedInstance,
            const Group(id: 7, name: 'support'),
          );
        });
        final result = await controller.updateGroup(
          _connectedInstance,
          const Group(id: 7, name: 'support'),
          GroupUpdateCommand(values),
        );
        expect(result, isA<GroupWriteFailed<void>>());
        await intervening;
        expect(transport.writes, hasLength(2));
      },
    );
  });
}

GroupsController _controller(
  PluginApiTransport transport, {
  SiteLifecycle? lifecycle,
  FakeApiCredentialReader? credentials,
}) => GroupsController(
  api: GroupsApi(transport, const DiscourseModelCodec.core()),
  credentials: credentials ?? FakeApiCredentialReader(),
  lifecycle: lifecycle ?? SiteLifecycle(),
);

typedef _GroupListSnapshot = ({
  List<int> ids,
  int total,
  int nextOffset,
  bool hasMore,
  bool loadingMore,
});

enum _GroupListRemoval {
  member,
  accept,
  deny;

  Future<void> load(
    GroupsController controller, {
    String filter = '',
    bool more = false,
    bool refresh = false,
  }) => this == member
      ? controller.loadMembers(
          _connectedInstance,
          'support',
          filter: filter,
          more: more,
          refresh: refresh,
        )
      : controller.loadRequesters(
          _connectedInstance,
          'support',
          filter: filter,
          more: more,
          refresh: refresh,
        );

  Future<GroupWriteOutcome<void>> remove(GroupsController controller, int id) =>
      this == member
      ? controller.removeMember(
          _connectedInstance,
          const Group(id: 7, name: 'support'),
          GroupMember(id: id, username: 'user$id'),
        )
      : controller.handleRequest(
          _connectedInstance,
          const Group(id: 7, name: 'support'),
          GroupRequester(id: id, username: 'user$id'),
          accept: this == accept,
        );

  _GroupListSnapshot state(GroupsController controller, {String filter = ''}) {
    if (this == member) {
      final state = controller.membersState(_site, 'support', filter: filter);
      return (
        ids: state.members.map((member) => member.id).toList(),
        total: state.total,
        nextOffset: state.nextOffset,
        hasMore: state.hasMore,
        loadingMore: state.loadingMore,
      );
    }
    final state = controller.requestersState(_site, 'support', filter: filter);
    return (
      ids: state.requesters.map((requester) => requester.id).toList(),
      total: state.total,
      nextOffset: state.nextOffset,
      hasMore: state.hasMore,
      loadingMore: state.loadingMore,
    );
  }
}

final class _PendingOffsetPage {
  _PendingOffsetPage({required this.snapshotBeforeRelease});

  final bool snapshotBeforeRelease;
  final started = Completer<void>();
  final release = Completer<void>();
}

final class _OffsetGroupTransport implements PluginApiTransport {
  static const pageSize = 3;
  final _rows = [
    for (final (index, id) in [
      91,
      7,
      204,
      36,
      808,
      12,
      65,
      503,
      22,
      107,
    ].indexed)
      (id: id, username: '${index.isEven ? 'alpha' : 'bravo'}$id'),
  ];
  final List<({String filter, int offset})> pages = [];
  bool rejectWrites = false;
  _PendingOffsetPage? _pending;
  ({Completer<void> started, Completer<void> release})? _pendingWrite;

  List<int> ids(String filter) => [
    for (final row in _rows)
      if (row.username.contains(filter)) row.id,
  ];

  _PendingOffsetPage holdPage({bool snapshotBeforeRelease = true}) {
    final pending = _PendingOffsetPage(
      snapshotBeforeRelease: snapshotBeforeRelease,
    );
    _pending = pending;
    addTearDown(() {
      if (!pending.release.isCompleted) pending.release.complete();
    });
    return pending;
  }

  ({Completer<void> started, Completer<void> release}) holdWrite() {
    final pending = (started: Completer<void>(), release: Completer<void>());
    _pendingWrite = pending;
    addTearDown(() {
      if (!pending.release.isCompleted) pending.release.complete();
    });
    return pending;
  }

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final uri = Uri.parse(path);
    if (uri.path == '/groups/support.json') return const {};
    expect(uri.path, '/groups/support/members.json');
    final offset = int.parse(uri.queryParameters['offset']!);
    final limit = int.parse(uri.queryParameters['limit']!);
    final filter = uri.queryParameters['filter'] ?? '';
    expect(limit, greaterThanOrEqualTo(pageSize));
    pages.add((filter: filter, offset: offset));

    Map<String, dynamic> snapshot() {
      final matching = _rows
          .where((row) => row.username.contains(filter))
          .toList();
      return {
        'members': [
          for (final row in matching.skip(offset).take(pageSize))
            {'id': row.id, 'username': row.username},
        ],
        'meta': {'total': matching.length, 'limit': pageSize, 'offset': offset},
      };
    }

    final pending = _pending;
    if (pending == null) return snapshot();
    _pending = null;
    final before = pending.snapshotBeforeRelease ? snapshot() : null;
    pending.started.complete();
    await pending.release.future;
    return before ?? snapshot();
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
    final id = path.endsWith('/handle_membership_request.json')
        ? body['user_id'] as int
        : int.parse(body['user_ids'] as String);
    if (!rejectWrites) _rows.removeWhere((row) => row.id == id);
    final pending = _pendingWrite;
    if (pending != null) {
      _pendingWrite = null;
      pending.started.complete();
      await pending.release.future;
    }
    if (rejectWrites) throw StateError('Removal failed.');
    return const {};
  }
}

final class _ControlledGroupTransport
    implements PluginApiTransport, PluginJsonListTransport {
  void Function(String path)? onGet;
  Map<String, dynamic> Function(String path)? onWrite;
  final List<Completer<Map<String, dynamic>>> objects = [];
  final List<Completer<List<Map<String, dynamic>>>> lists = [];
  final List<({String path, String? apiKey, String? clientId})> gets = [];
  final List<({String path, String? apiKey, String? clientId})> listGets = [];
  final List<
    ({String path, String method, Map<String, Object?> body, String? clientId})
  >
  writes = [];
  ({Completer<void> started, Completer<void> release})? _pendingWrite;

  ({Completer<void> started, Completer<void> release}) holdWrite() {
    final pending = (started: Completer<void>(), release: Completer<void>());
    _pendingWrite = pending;
    addTearDown(() {
      if (!pending.release.isCompleted) pending.release.complete();
    });
    return pending;
  }

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) {
    gets.add((path: path, apiKey: apiKey, clientId: clientId));
    onGet?.call(path);
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
    onGet?.call(path);
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
    final pending = _pendingWrite;
    if (pending != null) {
      _pendingWrite = null;
      pending.started.complete();
      await pending.release.future;
    }
    return onWrite?.call(path) ?? const {};
  }
}

enum _SearchableGroupCache {
  directory,
  members,
  requesters;

  Future<void> load(
    GroupsController controller,
    DiscourseInstance instance,
    String filter,
  ) => switch (this) {
    directory => controller.loadDirectory(
      instance,
      GroupDirectoryQuery(filter: filter),
    ),
    members => controller.loadMembers(instance, 'support', filter: filter),
    requesters => controller.loadRequesters(
      instance,
      'support',
      filter: filter,
    ),
  };

  Iterable<int> ids(
    GroupsController controller,
    String siteUrl,
    String filter,
  ) => switch (this) {
    directory =>
      controller
          .directoryState(siteUrl, GroupDirectoryQuery(filter: filter))
          .groups
          .map((group) => group.id),
    members =>
      controller
          .membersState(siteUrl, 'support', filter: filter)
          .members
          .map((member) => member.id),
    requesters =>
      controller
          .requestersState(siteUrl, 'support', filter: filter)
          .requesters
          .map((member) => member.id),
  };

  Map<String, dynamic> page(int id) => switch (this) {
    directory => {
      'groups': [
        {'id': id, 'name': 'group-$id'},
      ],
      'total_rows_groups': 1,
    },
    members || requesters => {
      'members': [
        {'id': id, 'username': 'user$id'},
      ],
      'meta': {'total': 1, 'limit': 30, 'offset': 0},
    },
  };
}

enum _GroupPageCache {
  detail,
  activity,
  permissions,
  logs;

  Future<void> load(
    GroupsController controller,
    DiscourseInstance instance,
    String groupName,
  ) => switch (this) {
    detail => controller.loadDetail(instance, groupName),
    activity => controller.loadActivity(instance, groupName, mentions: false),
    permissions => controller.loadPermissions(instance, groupName),
    logs => controller.loadLogs(instance, groupName),
  };

  Iterable<int> ids(
    GroupsController controller,
    String siteUrl,
    String groupName,
  ) => switch (this) {
    detail => [?controller.detailState(siteUrl, groupName).detail?.group.id],
    activity =>
      controller
          .activityState(siteUrl, groupName, mentions: false)
          .posts
          .map((post) => post.id),
    permissions =>
      controller
          .permissionsState(siteUrl, groupName)
          .permissions
          .map((permission) => permission.category.id),
    logs =>
      controller
          .logsState(siteUrl, groupName)
          .logs
          .map((log) => int.parse(log.subject!)),
  };

  int requests(_ControlledGroupTransport transport) =>
      transport.gets.length + transport.listGets.length;

  /// Queues a response for this page and returns its delivery.
  void Function(int id) hold(_ControlledGroupTransport transport) {
    if (this == permissions) {
      final pending = Completer<List<Map<String, dynamic>>>();
      transport.lists.add(pending);
      return (id) {
        if (pending.isCompleted) return;
        pending.complete([
          {
            'permission_type': 1,
            'category': {'id': id, 'name': 'Category $id'},
          },
        ]);
      };
    }
    final pending = Completer<Map<String, dynamic>>();
    transport.objects.add(pending);
    return (id) {
      if (pending.isCompleted) return;
      pending.complete(switch (this) {
        detail => {
          'group': {'id': id, 'name': 'group-$id'},
        },
        activity => {
          'posts': [
            {'id': id, 'topic_id': id, 'created_at': '2026-09-01T12:00:00Z'},
          ],
        },
        logs => {
          'logs': [
            {'action': 'change_group_setting', 'subject': '$id'},
          ],
          'all_loaded': true,
        },
        permissions => throw StateError('Permissions are a JSON list.'),
      });
    };
  }

  void respond(_ControlledGroupTransport transport, int id) =>
      hold(transport)(id);
}

final class _HeldGroupCredentials extends FakeApiCredentialReader {
  final key = Completer<String?>();

  @override
  Future<String?> apiKeyFor(String siteUrl) => key.future;
}
