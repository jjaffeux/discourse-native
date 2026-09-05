import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

void main() {
  testWidgets('the Users sidebar destination opens the native Matrix page', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      pluginResponses: const {
        'GET /directory-columns.json': {
          'directory_columns': [
            {
              'id': 1,
              'name': 'likes_received',
              'type': 'automatic',
              'position': 1,
            },
          ],
        },
        'GET /groups.json?order=name&asc=true': {
          'groups': <Map<String, Object?>>[],
          'total_rows_groups': 0,
        },
        'GET /directory_items.json?period=weekly&order=likes_received': {
          'directory_items': [
            {
              'id': 1,
              'likes_received': 42,
              'user': {'id': 1, 'username': 'sam', 'name': 'Sam Saffron'},
            },
          ],
          'meta': {
            'total_rows_directory_items': 1,
            'last_updated_at': '2026-09-04T07:06:00Z',
            'load_more_directory_items':
                '/directory_items.json?period=weekly&page=1',
          },
        },
      },
    );
    await pumpShell(
      tester,
      laptop,
      instances: [instance('meta.discourse.org')],
      api: api,
    );

    expect(sidebarDestination('Users'), findsOneWidget);
    await tester.tap(sidebarDestination('Users'));
    await tester.pumpAndSettle();

    final shell = ShellScope.read(tester.element(find.byType(MainContent)));
    expect(shell.currentContent?.id, 'users');
    expect(find.byType(UsersPage), findsOneWidget);
    expect(find.text('Users'), findsNWidgets(2));
    expect(find.text('Community signal'), findsNothing);
    expect(find.byKey(const ValueKey('user-row-sam')), findsOneWidget);
    expect(api.pluginReadPaths, contains('/directory-columns.json'));
    expect(
      api.pluginReadPaths,
      contains('/directory_items.json?period=weekly&order=likes_received'),
    );
    expect(tester.takeException(), isNull);
  });
}
