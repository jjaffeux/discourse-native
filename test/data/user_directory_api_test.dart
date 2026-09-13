import 'package:discourse_native/src/data/plugin_transport.dart';
import 'package:discourse_native/src/data/user_directory_api.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const siteUrl = 'https://example.com';

  test(
    'loads all custom groups with visible members from group search',
    () async {
      final transport = _DirectoryTransport()
        ..responses['/directory-columns.json'] = {
          'directory_columns': [
            {
              'id': 1,
              'name': 'likes_received',
              'type': 'automatic',
              'position': 1,
            },
          ],
        }
        ..failingPaths.add('/groups.json?order=name&asc=true')
        ..groupResponses = [
          for (var index = 0; index < 40; index++)
            {'id': index + 10, 'name': 'team-$index', 'can_see_members': true},
          {'id': 4, 'name': 'design', 'can_see_members': true},
          {'id': 4, 'name': 'design', 'can_see_members': true},
          {'id': 5, 'name': 'hidden-members', 'can_see_members': false},
          {'id': 6, 'name': 'unknown-members'},
          {
            'id': 3,
            'name': 'staff',
            'automatic': true,
            'can_see_members': true,
          },
        ];
      final api = UserDirectoryApi(transport, const DiscourseModelCodec.core());

      final metadata = await api.metadata(
        siteUrl: siteUrl,
        apiKey: 'secret',
        clientId: 'client',
      );

      expect(metadata.columns.single.name, 'likes_received');
      expect(metadata.groupNames, hasLength(41));
      expect(metadata.groupNames.first, 'design');
      expect(metadata.groupNames, contains('team-39'));
      expect(metadata.groupNames, isNot(contains('hidden-members')));
      expect(metadata.groupNames, isNot(contains('unknown-members')));
      expect(metadata.groupNames, isNot(contains('staff')));
      expect(transport.requests.map((request) => request.path), [
        '/directory-columns.json',
        '/groups/search.json?ignore_automatic=true',
      ]);
      expect(transport.requests.map((request) => request.clientId).toSet(), {
        'client',
      });
      expect(transport.requests.map((request) => request.apiKey).toSet(), {
        'secret',
      });
    },
  );

  for (final authenticated in [false, true]) {
    test(
      'group discovery ${authenticated ? 'failure' : 'without login'} keeps the directory usable',
      () async {
        final transport = _DirectoryTransport()
          ..failingPaths.add('/groups/search.json?ignore_automatic=true')
          ..responses['/directory-columns.json'] = {
            'directory_columns': [
              {'id': 1, 'name': 'likes_received', 'type': 'automatic'},
            ],
          };
        final metadata = await UserDirectoryApi(
          transport,
          const DiscourseModelCodec.core(),
        ).metadata(siteUrl: siteUrl, apiKey: authenticated ? 'secret' : null);

        expect(metadata.columns.single.name, 'likes_received');
        expect(metadata.groupNames, isEmpty);
        expect(transport.requests.map((request) => request.path), [
          '/directory-columns.json',
          if (authenticated) '/groups/search.json?ignore_automatic=true',
        ]);
      },
    );
  }

  test(
    'loads every editable column for staff and keeps disabled options',
    () async {
      final transport = _DirectoryTransport()
        ..responses['/edit-directory-columns.json'] = {
          'directory_columns': [
            {
              'id': 1,
              'name': 'likes_received',
              'type': 'automatic',
              'position': 1,
              'enabled': true,
            },
            {
              'id': 9,
              'name': 'solutions',
              'type': 'plugin',
              'position': 2,
              'enabled': false,
            },
          ],
        };
      final api = UserDirectoryApi(transport, const DiscourseModelCodec.core());

      final metadata = await api.metadata(
        siteUrl: siteUrl,
        apiKey: 'secret',
        canManageColumns: true,
      );

      expect(metadata.canManageColumns, isTrue);
      expect(metadata.columns.map((column) => column.name), ['likes_received']);
      expect(metadata.availableColumns.map((column) => column.name), [
        'likes_received',
        'solutions',
      ]);
      expect(
        transport.requests.map((request) => request.path),
        contains('/edit-directory-columns.json'),
      );
      expect(
        transport.requests.map((request) => request.path),
        isNot(contains('/directory-columns.json')),
      );
    },
  );

  test(
    'falls back to enabled columns when the editor is unavailable',
    () async {
      final transport = _DirectoryTransport()
        ..failingPaths.add('/edit-directory-columns.json')
        ..responses['/directory-columns.json'] = {
          'directory_columns': [
            {
              'id': 1,
              'name': 'likes_received',
              'type': 'automatic',
              'position': 1,
            },
          ],
        };
      final api = UserDirectoryApi(transport, const DiscourseModelCodec.core());

      final metadata = await api.metadata(
        siteUrl: siteUrl,
        apiKey: 'secret',
        canManageColumns: true,
      );

      expect(metadata.canManageColumns, isFalse);
      expect(metadata.availableColumns.single.name, 'likes_received');
    },
  );

  test(
    'maps the complete core query and omits descending asc parameter',
    () async {
      final transport = _DirectoryTransport();
      final api = UserDirectoryApi(transport, const DiscourseModelCodec.core());
      const columns = [
        UserDirectoryColumn(
          id: 1,
          name: 'likes_received',
          type: UserDirectoryColumnType.automatic,
          position: 1,
        ),
        UserDirectoryColumn(
          id: 8,
          name: 'Company',
          type: UserDirectoryColumnType.userField,
          position: 2,
          userFieldId: 23,
        ),
        UserDirectoryColumn(
          id: 9,
          name: 'solutions',
          type: UserDirectoryColumnType.plugin,
          position: 3,
        ),
      ];

      await api.directory(
        siteUrl: siteUrl,
        period: UserDirectoryPeriod.weekly,
        columns: columns,
        page: 2,
        order: 'likes_received',
        name: 'sam saffron',
        group: 'team+ops',
      );

      final uri = Uri.parse(transport.requests.single.path);
      expect(uri.path, '/directory_items.json');
      expect(uri.queryParameters, {
        'period': 'weekly',
        'order': 'likes_received',
        'page': '2',
        'name': 'sam saffron',
        'group': 'team+ops',
        'user_field_ids': '23',
        'plugin_column_ids': '9',
      });
      expect(uri.queryParameters, isNot(contains('asc')));

      transport.requests.clear();
      await api.directory(
        siteUrl: siteUrl,
        period: UserDirectoryPeriod.all,
        columns: columns,
        order: 'username',
        ascending: true,
      );
      expect(
        Uri.parse(transport.requests.single.path).queryParameters['asc'],
        'true',
      );
    },
  );

  test('validates core page and query limits', () {
    final api = UserDirectoryApi(
      _DirectoryTransport(),
      const DiscourseModelCodec.core(),
    );
    expect(
      () => api.directory(
        siteUrl: siteUrl,
        period: UserDirectoryPeriod.weekly,
        columns: const [],
        page: 11,
      ),
      throwsRangeError,
    );
    expect(
      () => api.directory(
        siteUrl: siteUrl,
        period: UserDirectoryPeriod.weekly,
        columns: const [],
        name: 'x' * 256,
      ),
      throwsArgumentError,
    );
  });

  test('saves enabled state and normalized column order', () async {
    final transport = _DirectoryTransport();
    final api = UserDirectoryApi(transport, const DiscourseModelCodec.core());
    const columns = [
      UserDirectoryColumn(
        id: 9,
        name: 'solutions',
        type: UserDirectoryColumnType.plugin,
        position: 8,
        enabled: false,
      ),
      UserDirectoryColumn(
        id: 1,
        name: 'likes_received',
        type: UserDirectoryColumnType.automatic,
        position: 3,
      ),
    ];

    await api.updateColumns(
      siteUrl: siteUrl,
      apiKey: 'secret',
      clientId: 'client',
      columns: columns,
    );

    final write = transport.writes.single;
    expect(write.path, '/edit-directory-columns.json');
    expect(write.method, 'PUT');
    expect(write.apiKey, 'secret');
    expect(write.clientId, 'client');
    expect(write.body, {
      'directory_columns': {
        '0': {'id': 9, 'enabled': false, 'position': 1},
        '1': {'id': 1, 'enabled': true, 'position': 2},
      },
    });
    await expectLater(
      api.updateColumns(
        siteUrl: siteUrl,
        apiKey: 'secret',
        columns: const [
          UserDirectoryColumn(
            id: 9,
            name: 'solutions',
            type: UserDirectoryColumnType.plugin,
            position: 1,
            enabled: false,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}

final class _DirectoryTransport
    implements PluginApiTransport, PluginJsonListTransport {
  final Map<String, Map<String, dynamic>> responses = {};
  List<Map<String, dynamic>> groupResponses = [];
  final Set<String> failingPaths = {};
  final List<({String path, String? apiKey, String? clientId})> requests = [];
  final List<
    ({
      String path,
      String method,
      String apiKey,
      String? clientId,
      Map<String, Object?> body,
    })
  >
  writes = [];

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    requests.add((path: path, apiKey: apiKey, clientId: clientId));
    if (failingPaths.contains(path)) throw StateError('Unavailable');
    return responses[path] ??
        const {
          'directory_items': <Map<String, Object?>>[],
          'meta': <String, Object?>{},
        };
  }

  @override
  Future<List<Map<String, dynamic>>> pluginGetJsonList({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    requests.add((path: path, apiKey: apiKey, clientId: clientId));
    if (failingPaths.contains(path)) throw StateError('Unavailable');
    return groupResponses;
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
    writes.add((
      path: path,
      method: method,
      apiKey: apiKey,
      clientId: clientId,
      body: body,
    ));
    return const {};
  }
}
