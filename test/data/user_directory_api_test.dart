import 'package:discourse_native/src/data/plugin_transport.dart';
import 'package:discourse_native/src/data/user_directory_api.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const siteUrl = 'https://example.com';

  test('loads column metadata and merges visible group names', () async {
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
      ..responses['/groups.json?order=name&asc=true'] = {
        'groups': [
          {'id': 4, 'name': 'design'},
        ],
        'total_rows_groups': 1,
      };
    final api = UserDirectoryApi(transport, const DiscourseModelCodec.core());

    final metadata = await api.metadata(
      siteUrl: siteUrl,
      apiKey: 'secret',
      fallbackGroupNames: const ['staff'],
    );

    expect(metadata.columns.single.name, 'likes_received');
    expect(metadata.groupNames, ['design', 'staff']);
    expect(transport.requests.map((request) => request.apiKey).toSet(), {
      'secret',
    });
  });

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
}

final class _DirectoryTransport implements PluginApiTransport {
  final Map<String, Map<String, dynamic>> responses = {};
  final List<({String path, String? apiKey})> requests = [];

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    requests.add((path: path, apiKey: apiKey));
    return responses[path] ??
        const {
          'directory_items': <Map<String, Object?>>[],
          'meta': <String, Object?>{},
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
  }) => throw UnimplementedError();
}
