import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://users.example';
const _users = ContentRoute(
  destination: PageDestination(CorePage.users),
  title: 'Users',
  icon: DIcons.users,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('unfocused displayed Users pane owns its search', (tester) async {
    final api = _DirectoryApi();
    final shell = ShellController(
      instanceStore: FakeInstanceStore([instance('users.example')]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    shell.desktopTopicTabs = true;
    shell.pushContent(_users);
    final mainId = shell.activeTabId!;
    shell.createTab(panel: ForumPanel.secondary);
    shell.pushContent(_users);
    final secondaryId = shell.activeTabId!;
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Material(
            child: ShellScope(
              controller: shell,
              child: Row(
                children: [
                  for (final (id, panel) in [
                    (mainId, ForumPanel.main),
                    (secondaryId, ForumPanel.secondary),
                  ])
                    Expanded(
                      child: ForumTabScope(
                        tabId: id,
                        panel: panel,
                        child: UsersDirectoryHost(
                          key: ValueKey(id),
                          siteUrl: _site,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pane = find.byKey(ValueKey(mainId));
    final search = find.descendant(
      of: pane,
      matching: find.byKey(const ValueKey('users-search')),
    );
    await tester.enterText(search, 'sam');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(shell.activeTabId, secondaryId);
    expect(shell.search.wordsFor(_site, mainId, 'users'), 'sam');
    expect(shell.search.wordsFor(_site, secondaryId, 'users'), isEmpty);
    final pages = tester.widgetList<UsersPage>(find.byType(UsersPage)).toList();
    expect(pages[0].data.query.search, 'sam');
    expect(pages[1].data.query.search, isEmpty);
    final held = pages.first;
    held.onPeriodChanged!(UserDirectoryPeriod.monthly);
    held.onGroupChanged!('design');
    held.onSortChanged!('username', true);
    await tester.pumpAndSettle();
    final first = shell.tabContext(mainId);
    const selected = UserDirectoryQuery(
      search: 'sam',
      period: UserDirectoryPeriod.monthly,
      group: 'design',
      order: 'username',
      ascending: true,
    );
    expect(first.usersQuery, selected);
    expect(
      shell.tabContext(secondaryId).usersQuery,
      const UserDirectoryQuery(),
    );
    final secondSearch = find.descendant(
      of: find.byKey(ValueKey(secondaryId)),
      matching: find.byKey(const ValueKey('users-search')),
    );
    await tester.enterText(secondSearch, 'hawk');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(first.usersQuery, selected);
    expect(shell.tabContext(secondaryId).usersQuery.search, 'hawk');
    await tester.tap(
      find.descendant(
        of: pane,
        matching: find.byKey(const ValueKey('users-period-filter')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(first.usersQuery.period, UserDirectoryPeriod.yearly);
    expect(
      shell.tabContext(secondaryId).usersQuery.period,
      UserDirectoryPeriod.weekly,
    );
    expect(shell.activeTabId, secondaryId);
    const evidence = String.fromEnvironment('USERS_EVIDENCE_DIR');
    if (evidence.isNotEmpty) {
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final pixels = await boundary.toImage();
        final bytes = await pixels.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$evidence/two-users-panes.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        pixels.dispose();
      });
    }
    final requests = api.pluginReadPaths.length;
    final visible = tester.widget<UsersPage>(
      find.descendant(of: pane, matching: find.byType(UsersPage)),
    );
    shell.closeTab(mainId);
    visible.onSearchChanged!('retired');
    visible.onPeriodChanged!(UserDirectoryPeriod.daily);
    await tester.pumpAndSettle();
    expect(shell.search.wordsFor(_site, mainId, 'users'), 'sam');
    expect(api.pluginReadPaths.length, requests);
    expect(shell.reopenClosedTab(mainId), isTrue);
    await tester.pumpAndSettle();
    expect(shell.tabContext(mainId).usersQuery.search, 'sam');
    expect(
      shell.tabContext(mainId).usersQuery.period,
      UserDirectoryPeriod.yearly,
    );
    final retiredRoute = tester.widget<UsersPage>(
      find.descendant(of: pane, matching: find.byType(UsersPage)),
    );
    shell.pushContent(ContentRoute.allCategories());
    retiredRoute.onSearchChanged!('wrong route');
    expect(shell.search.wordsFor(_site, mainId, 'users'), 'sam');
    shell.lifecycle.invalidate(_site);
    retiredRoute.onSortChanged!('likes_received', false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _DirectoryApi extends FakeDiscourseApi {
  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    pluginReadPaths.add(path);
    final uri = Uri.parse(path);
    if (uri.path == '/directory-columns.json') {
      return {
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
    if (uri.path == '/groups/search.json') {
      return {
        'groups': [
          {'name': 'design'},
        ],
      };
    }
    if (uri.path == '/directory_items.json') {
      return {
        'directory_items': [
          {
            'id': 1,
            'user': {
              'id': 1,
              'username': uri.queryParameters['name'] ?? 'reader',
            },
            'likes_received': 20,
          },
        ],
        'meta': {'total_rows_directory_items': 1},
      };
    }
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
