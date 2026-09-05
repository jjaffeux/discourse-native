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
}

final class _ControllerTransport implements PluginApiTransport {
  final List<String> requests = [];

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    requests.add(path);
    final uri = Uri.parse(path);
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
  }) => throw UnimplementedError();
}

final class _Credentials implements ApiCredentialReader {
  const _Credentials();

  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'secret';

  @override
  Future<String> clientId() async => 'client';
}
