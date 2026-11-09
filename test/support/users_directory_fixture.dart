import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const usersDirectorySite = 'https://users.example';
const usersDirectoryPageSize = 50;

const _viewer = DiscourseUser(id: 1, username: 'reader');
const _usersRoute = ContentRoute(
  destination: PageDestination(CorePage.users),
  title: 'Users',
  icon: DIcons.users,
);

/// The Users destination as a new object, the way a second navigation makes one.
ContentRoute freshUsersDirectoryRoute() =>
    // ignore: prefer_const_constructors
    ContentRoute(
      destination: _usersRoute.destination,
      title: _usersRoute.title,
      icon: _usersRoute.icon,
    );

const _automaticColumns = [
  'likes_received',
  'likes_given',
  'topic_count',
  'post_count',
  'topics_entered',
  'posts_read',
  'days_visited',
];

/// Serves the directory the way a site does: the seven default columns, a
/// groups lookup and pages of [usersDirectoryPageSize] rows. [beforeRead] runs
/// ahead of every response, so a caller decides when each one lands.
class UsersDirectoryApi extends FakeDiscourseApi {
  UsersDirectoryApi({
    this.beforeRead,
    this.totalRows = 300,
    required super.user,
  });

  final Future<void> Function(String path)? beforeRead;
  final int totalRows;
  final List<String> reads = [];

  Map<String, dynamic> _columns() => {
    'directory_columns': [
      for (final (index, name) in _automaticColumns.indexed)
        {
          'id': index + 1,
          'name': name,
          'type': 'automatic',
          'position': index + 1,
        },
    ],
  };

  Map<String, dynamic> _page(Uri uri) {
    final page = int.tryParse(uri.queryParameters['page'] ?? '') ?? 0;
    final search = uri.queryParameters['name'] ?? '';
    final start = page * usersDirectoryPageSize;
    final end = (start + usersDirectoryPageSize).clamp(0, totalRows);
    return {
      'directory_items': [
        for (var row = start; row < end; row++)
          {
            'id': row + 10,
            'user': {
              'id': row + 10,
              'username': 'member_$search$row',
              'name': row % 4 == 0 ? null : 'Community Member $row',
            },
            for (final (index, name) in _automaticColumns.indexed)
              name: (totalRows - row) * (index + 3) * 7,
          },
      ],
      'meta': {
        'total_rows_directory_items': totalRows,
        if (end < totalRows)
          'load_more_directory_items': '/directory_items.json?page=${page + 1}',
      },
    };
  }

  @override
  Future<List<Map<String, dynamic>>> pluginGetJsonList({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    reads.add(path);
    await beforeRead?.call(path);
    return [
      {'id': 4, 'name': 'design', 'can_see_members': true},
    ];
  }

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    reads.add(path);
    await beforeRead?.call(path);
    final uri = Uri.parse(path);
    return switch (uri.path) {
      '/directory-columns.json' => _columns(),
      '/directory_items.json' => _page(uri),
      _ => super.pluginGetJson(
        siteUrl: siteUrl,
        path: path,
        apiKey: apiKey,
        clientId: clientId,
      ),
    };
  }
}

class UsersDirectoryFixture {
  UsersDirectoryFixture(this.shell, this.api);

  final ShellController shell;
  final UsersDirectoryApi api;
}

/// The signed-in Users route, as the shell hosts it, at [size].
Future<UsersDirectoryFixture> pumpUsersDirectoryFixture(
  WidgetTester tester, {
  required Size size,
  required TargetPlatform platform,
  Future<void> Function(String path)? beforeRead,
  int totalRows = 300,
  double devicePixelRatio = 1,
  PluginManifest pluginManifest = const PluginManifest([]),
}) async {
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize = size * devicePixelRatio;
  addTearDown(tester.view.reset);
  final api = UsersDirectoryApi(
    beforeRead: beforeRead,
    totalRows: totalRows,
    user: _viewer,
  );
  final plugins = PluginInstaller.install(pluginManifest);
  final shell = ShellController(
    plugins: plugins,
    instanceStore: FakeInstanceStore([
      instance('users.example').copyWith(user: _viewer),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[usersDirectorySite] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  shell.pushContent(_usersRoute);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark.copyWith(platform: platform),
      home: Material(
        child: PluginScope(
          session: shell.pluginSession,
          registry: plugins.registry,
          child: ShellScope(
            controller: shell,
            child: const UsersDirectoryHost(siteUrl: usersDirectorySite),
          ),
        ),
      ),
    ),
  );
  return UsersDirectoryFixture(shell, api);
}
