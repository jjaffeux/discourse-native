import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/plugin_transport.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/user_directory_api.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/shell/user_directory_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dispose in [false, true]) {
    test(
      'a ${dispose ? 'disposed' : 'forgotten'} directory does not start metadata after credential lookup',
      () async {
        final transport = _ControllerTransport();
        final controller = UserDirectoryController(
          api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
          credentials: const _Credentials(),
          lifecycle: SiteLifecycle(),
        );
        const instance = DiscourseInstance(
          url: 'https://example.com',
          title: 'Example',
        );

        final loading = controller.load(instance);
        if (dispose) {
          controller.dispose();
        } else {
          addTearDown(controller.dispose);
          controller.forget(instance.url);
        }
        await loading;

        expect(transport.requests, isEmpty);
        expect(controller.stateFor(instance.url).columns, isEmpty);
      },
    );
  }

  test('an immediate account replacement owns its metadata request', () async {
    final transport = _ControllerTransport();
    final lifecycle = SiteLifecycle();
    final controller = UserDirectoryController(
      api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
      credentials: const _Credentials(),
      lifecycle: lifecycle,
    );
    addTearDown(controller.dispose);
    const instance = DiscourseInstance(
      url: 'https://example.com',
      title: 'Example',
    );

    final signedOut = controller.load(instance);
    lifecycle.invalidate(instance.url);
    controller.forget(instance.url);
    final signedIn = controller.load(
      instance.copyWith(
        user: const DiscourseUser(username: 'admin', staff: true),
      ),
    );
    await Future.wait([signedOut, signedIn]);

    final state = controller.stateFor(instance.url);
    expect(state.loaded, isTrue);
    expect(state.canManageColumns, isTrue);
    expect(transport.requests, isNot(contains('/directory-columns.json')));
    expect(transport.requests.first, '/edit-directory-columns.json');
  });

  test('loads, paginates, changes query, and forgets per-site state', () async {
    final transport = _ControllerTransport();
    final controller = UserDirectoryController(
      api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
      credentials: const _Credentials(),
      lifecycle: SiteLifecycle(),
    );
    addTearDown(controller.dispose);
    const instance = DiscourseInstance(
      url: 'https://example.com',
      title: 'Example',
      user: DiscourseUser(username: 'reader', groups: ['staff']),
    );

    await controller.load(instance);

    var state = controller.stateFor(instance.url);
    expect(state.loaded, isTrue);
    expect(state.items.map((item) => item.user.username), ['sam', 'hawk']);
    expect(state.columns.single.name, 'likes_received');
    expect(state.groupNames, ['design', 'staff']);
    expect(state.totalRows, 75);
    expect(state.hasMore, isTrue);

    await controller.load(instance, more: true);
    state = controller.stateFor(instance.url);
    expect(state.items.map((item) => item.user.username), [
      'sam',
      'hawk',
      'lindsey',
    ]);
    expect(state.nextPage, 2);

    const query = UserDirectoryQuery(
      period: UserDirectoryPeriod.monthly,
      search: 'sam',
      order: 'username',
      ascending: true,
    );
    expect(controller.replaceQuery(instance.url, query), isTrue);
    await controller.load(instance);
    final uri = Uri.parse(
      transport.requests.lastWhere(
        (path) => path.startsWith('/directory_items.json'),
      ),
    );
    expect(uri.queryParameters['period'], 'monthly');
    expect(uri.queryParameters['name'], 'sam');
    expect(uri.queryParameters['asc'], 'true');
    expect(
      transport.requests.where((path) => path == '/directory-columns.json'),
      hasLength(1),
    );

    controller.forget(instance.url);
    expect(controller.queryFor(instance.url), const UserDirectoryQuery());
    expect(controller.stateFor(instance.url).loaded, isFalse);
  });

  test(
    'bounds directory history per forum and retains recently selected queries',
    () async {
      final transport = _ControllerTransport();
      final controller = UserDirectoryController(
        api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
        credentials: const _Credentials(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);
      const site = DiscourseInstance(
        url: 'https://example.com',
        title: 'Example',
      );
      const other = DiscourseInstance(
        url: 'https://another.example',
        title: 'Other',
      );
      await controller.load(other);
      for (var index = 0; index < 16; index++) {
        controller.replaceQuery(
          site.url,
          UserDirectoryQuery(search: 'query-$index'),
        );
        await controller.load(site);
      }
      final requestsBeforeRevisit = transport.requests.length;
      controller.replaceQuery(
        site.url,
        const UserDirectoryQuery(search: 'query-0'),
      );
      await controller.load(site);
      expect(transport.requests.length, requestsBeforeRevisit);

      controller.replaceQuery(
        site.url,
        const UserDirectoryQuery(search: 'query-16'),
      );
      await controller.load(site);

      expect(
        controller
            .stateFor(site.url, const UserDirectoryQuery(search: 'query-0'))
            .loaded,
        isTrue,
      );
      expect(
        controller
            .stateFor(site.url, const UserDirectoryQuery(search: 'query-1'))
            .loaded,
        isFalse,
      );
      expect(controller.stateFor(other.url).loaded, isTrue);
      controller.replaceQuery(
        site.url,
        const UserDirectoryQuery(search: 'query-1'),
      );
      await controller.load(site);
      expect(transport.requests.length, requestsBeforeRevisit + 2);
      expect(
        Uri.parse(transport.requests.last).queryParameters['name'],
        'query-1',
      );
    },
  );

  for (final replaces in [false, true]) {
    test(
      'evicted directory replies cannot ${replaces ? 'finish a replacement load' : 'repopulate the cache'}',
      () async {
        final transport = _ControllerTransport();
        final controller = UserDirectoryController(
          api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
          credentials: const _Credentials(),
          lifecycle: SiteLifecycle(),
        );
        addTearDown(controller.dispose);
        const site = DiscourseInstance(
          url: 'https://example.com',
          title: 'Example',
        );
        const originalQuery = UserDirectoryQuery(search: 'original');
        final oldStarted = Completer<void>();
        final oldReply = Completer<void>();
        final replacementStarted = Completer<void>();
        final replacementReply = Completer<void>();
        addTearDown(() {
          if (!oldReply.isCompleted) oldReply.complete();
          if (!replacementReply.isCompleted) replacementReply.complete();
        });
        transport.beforeDirectoryReply = (uri) async {
          if (uri.queryParameters['name'] != 'original') return;
          if (!oldStarted.isCompleted) {
            oldStarted.complete();
            await oldReply.future;
          } else {
            replacementStarted.complete();
            await replacementReply.future;
          }
        };
        controller.replaceQuery(site.url, originalQuery);
        final old = controller.load(site);
        await oldStarted.future;
        for (var index = 0; index < 16; index++) {
          controller.replaceQuery(
            site.url,
            UserDirectoryQuery(search: 'query-$index'),
          );
          await controller.load(site);
        }
        expect(controller.stateFor(site.url, originalQuery).loading, isFalse);

        Future<void>? replacement;
        if (replaces) {
          controller.replaceQuery(site.url, originalQuery);
          replacement = controller.load(site);
          await replacementStarted.future;
        }
        oldReply.complete();
        await old;
        expect(controller.stateFor(site.url, originalQuery).loaded, isFalse);
        expect(controller.stateFor(site.url, originalQuery).loading, replaces);
        if (replacement != null) {
          final requestsBeforeDuplicate = transport.requests.length;
          await controller.load(site);
          expect(transport.requests.length, requestsBeforeDuplicate);
          replacementReply.complete();
          await replacement;
          expect(controller.stateFor(site.url).loaded, isTrue);
        }
      },
    );
  }

  test('staff can load and update the complete column configuration', () async {
    final transport = _ControllerTransport();
    final controller = UserDirectoryController(
      api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
      credentials: const _Credentials(),
      lifecycle: SiteLifecycle(),
    );
    addTearDown(controller.dispose);
    const instance = DiscourseInstance(
      url: 'https://example.com',
      title: 'Example',
      user: DiscourseUser(username: 'admin', staff: true),
    );

    await controller.load(instance);

    var state = controller.stateFor(instance.url);
    expect(state.canManageColumns, isTrue);
    expect(state.columns.map((column) => column.name), ['likes_received']);
    expect(state.availableColumns.map((column) => column.name), [
      'likes_received',
      'solutions',
      'GitHub Username',
    ]);
    expect(
      transport.requests.where(
        (path) => path == '/edit-directory-columns.json',
      ),
      hasLength(1),
    );

    final update = controller.updateColumns(instance, [
      for (final column in state.availableColumns)
        column.name == 'solutions' ? column.copyWith(enabled: true) : column,
    ]);
    expect(controller.updatingColumnsFor(instance.url), isTrue);
    expect(await update, isTrue);
    expect(controller.updatingColumnsFor(instance.url), isFalse);

    state = controller.stateFor(instance.url);
    expect(state.columns.map((column) => column.name), [
      'likes_received',
      'solutions',
    ]);
    expect(transport.writes.single.path, '/edit-directory-columns.json');
  });

  test('forgotten metadata cannot repopulate a replacement account', () async {
    final transport = _ControllerTransport();
    final metadataStarted = Completer<void>();
    final oldMetadata = Completer<Map<String, dynamic>>();
    transport.nextColumns = () {
      metadataStarted.complete();
      return oldMetadata.future;
    };
    final controller = UserDirectoryController(
      api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
      credentials: const _Credentials(),
      lifecycle: SiteLifecycle(),
    );
    addTearDown(controller.dispose);
    const instance = DiscourseInstance(
      url: 'https://example.com',
      title: 'Example',
      user: DiscourseUser(username: 'former-account', groups: ['private']),
    );

    final loading = controller.load(instance);
    await metadataStarted.future;
    controller.forget(instance.url);
    oldMetadata.complete(const {
      'directory_columns': [
        {'id': 9, 'name': 'former-column', 'type': 'plugin'},
      ],
    });
    await loading;

    expect(controller.stateFor(instance.url).columns, isEmpty);
    expect(controller.stateFor(instance.url).groupNames, isEmpty);
    expect(transport.requests, [
      '/directory-columns.json',
      '/groups.json?order=name&asc=true',
    ]);

    await controller.load(
      instance.copyWith(user: const DiscourseUser(username: 'replacement')),
    );
    final replacement = controller.stateFor(instance.url);
    expect(replacement.columns.map((column) => column.name), [
      'likes_received',
    ]);
    expect(replacement.groupNames, ['design']);
  });

  test('updating columns invalidates cached directory queries', () async {
    final transport = _ControllerTransport();
    final controller = UserDirectoryController(
      api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
      credentials: const _Credentials(),
      lifecycle: SiteLifecycle(),
    );
    addTearDown(controller.dispose);
    const instance = DiscourseInstance(
      url: 'https://example.com',
      title: 'Example',
      user: DiscourseUser(username: 'admin', staff: true),
    );

    await controller.load(instance);
    controller.replaceQuery(
      instance.url,
      const UserDirectoryQuery(search: 'sam'),
    );
    await controller.load(instance);
    final columns = controller.stateFor(instance.url).availableColumns;
    expect(
      await controller.updateColumns(instance, [
        for (final column in columns)
          column.name == 'solutions' ? column.copyWith(enabled: true) : column,
      ]),
      isTrue,
    );

    controller.replaceQuery(instance.url, const UserDirectoryQuery());
    await controller.load(instance);

    expect(
      controller.stateFor(instance.url).columns.map((column) => column.name),
      ['likes_received', 'solutions'],
    );
    expect(
      Uri.parse(transport.requests.last).queryParameters['plugin_column_ids'],
      '9',
    );
  });
}

final class _ControllerTransport implements PluginApiTransport {
  final List<String> requests = [];
  final List<({String path, Map<String, Object?> body})> writes = [];
  final Map<int, bool> columnEnabled = {1: true, 9: false, 14: false};
  Future<Map<String, dynamic>> Function()? nextColumns;
  Future<void> Function(Uri uri)? beforeDirectoryReply;

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    requests.add(path);
    final uri = Uri.parse(path);
    if (nextColumns case final load?
        when uri.path == '/directory-columns.json' ||
            uri.path == '/edit-directory-columns.json') {
      nextColumns = null;
      return load();
    }
    if (uri.path == '/edit-directory-columns.json') {
      return {
        'directory_columns': [
          {
            'id': 1,
            'name': 'likes_received',
            'type': 'automatic',
            'position': 1,
            'enabled': columnEnabled[1],
          },
          {
            'id': 9,
            'name': 'solutions',
            'type': 'plugin',
            'position': 2,
            'enabled': columnEnabled[9],
          },
          {
            'id': 14,
            'name': 'GitHub Username',
            'type': 'user_field',
            'position': 3,
            'user_field_id': 42,
            'enabled': columnEnabled[14],
          },
        ],
      };
    }
    if (uri.path == '/directory-columns.json') {
      return const {
        'directory_columns': [
          {
            'id': 1,
            'name': 'likes_received',
            'type': 'automatic',
            'position': 1,
          },
        ],
      };
    }
    if (uri.path == '/groups.json') {
      return const {
        'groups': [
          {'id': 2, 'name': 'design'},
        ],
        'total_rows_groups': 1,
      };
    }
    await beforeDirectoryReply?.call(uri);
    final page = int.tryParse(uri.queryParameters['page'] ?? '0') ?? 0;
    final usernames = page == 0 ? const ['sam', 'hawk'] : const ['lindsey'];
    return {
      'directory_items': [
        for (var index = 0; index < usernames.length; index++)
          {
            'id': page * 10 + index + 1,
            'likes_received': 100 - index,
            'user': {'id': page * 10 + index + 1, 'username': usernames[index]},
          },
      ],
      'meta': {
        'total_rows_directory_items': 75,
        'last_updated_at': '2026-09-04T07:06:00Z',
        'load_more_directory_items':
            '/directory_items.json?period=weekly&page=${page + 1}',
      },
    };
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
    writes.add((path: path, body: body));
    final configuration = body['directory_columns'];
    if (configuration is Map) {
      for (final value in configuration.values) {
        if (value is Map) {
          final id = value['id'];
          final enabled = value['enabled'];
          if (id is int && enabled is bool) columnEnabled[id] = enabled;
        }
      }
    }
    return const {};
  }
}

final class _Credentials implements ApiCredentialReader {
  const _Credentials();

  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'secret';

  @override
  Future<String> clientId() async => 'client';
}
