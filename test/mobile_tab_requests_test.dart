import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/mobile_place_order.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' as fixture;
import 'support/badge_fixtures.dart';
import 'support/boards_fixture.dart' show boardFixtureJson;
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');

final class _TabApi extends FakeDiscourseApi {
  _TabApi()
    : super(
        user: _user,
        bookmarkList: const [],
        feedGates: {},
        feeds: const {
          '/latest.json': [],
          '/topics/private-messages/reader.json': [],
        },
      );

  final reads = <String>[];
  String? pendingPath;
  Completer<void>? readGate;

  Future<T> _read<T>(String path, Future<T> Function() response) async {
    reads.add(path);
    if (path == pendingPath) await readGate?.future;
    return response();
  }

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) => _read(
    '/categories.json',
    () => super.loadCategories(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      page: page,
    ),
  );

  @override
  Future<BookmarkListPage> bookmarkListPage({
    required String siteUrl,
    required String apiKey,
    required String username,
    int page = 0,
    String? clientId,
  }) => _read(
    '/bookmarks.json',
    () => super.bookmarkListPage(
      siteUrl: siteUrl,
      apiKey: apiKey,
      username: username,
      page: page,
      clientId: clientId,
    ),
  );

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) => _read(Uri.parse(path).path, () async {
    return switch (Uri.parse(path).path) {
      '/directory-columns.json' => {'directory_columns': <Object>[]},
      '/directory_items.json' => {
        'directory_items': <Object>[],
        'total_rows_directory_items': 0,
      },
      '/groups.json' => {'groups': <Object>[], 'total_rows_groups': 0},
      '/badges.json' => badgeCatalogWire,
      _ => super.pluginGetJson(
        siteUrl: siteUrl,
        path: path,
        apiKey: apiKey,
        clientId: clientId,
      ),
    };
  });
}

Future<void> _showInBar(WidgetTester tester, String tab) async {
  final context = tester.element(find.byType(MobileForumRoot));
  await MobilePlaceOrderHost.maybeOf(context)!.set([tab, 'topics']);
  await tester.pumpAndSettle();
  expect(
    find.byKey(ValueKey('mobile-mode-$tab')).hitTestable(),
    findsOneWidget,
  );
}

void main() {
  for (final (tab, path) in [
    ('messages', '/topics/private-messages/reader.json'),
    ('users', '/directory_items.json'),
    ('destination/user-bookmarks', '/bookmarks.json'),
    ('destination/all-categories', '/categories.json'),
    ('destination/groups', '/groups.json'),
    ('destination/badges', '/badges.json'),
  ]) {
    testWidgets(
      'rapid $tab taps share a pending request',
      (tester) async {
        final api = _TabApi();
        await pumpShell(
          tester,
          phone,
          api: api,
          instances: [
            instance(
              'meta.discourse.org',
            ).copyWith(user: _user, config: const SiteConfig()),
          ],
          authenticator: FakeAuthenticator()..keys[_site] = 'key',
        );
        await _showInBar(tester, tab);
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        api.pendingPath = path;
        api.readGate = gate;
        api.feedGates[path] = gate;
        int requests() => path.contains('private-messages')
            ? api.feedPaths.where((value) => value == path).length
            : api.reads.where((value) => value == path).length;
        final before = requests();
        final button = find.byKey(ValueKey('mobile-mode-$tab'));

        for (var tap = 0; tap < 6; tap++) {
          await tester.tap(button);
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(requests() - before, 1);
        gate.complete();
        await tester.pumpAndSettle();
        expect(requests() - before, 1);
        final shell = ShellScope.read(
          tester.element(find.byType(MobileForumRoot)),
        );
        expect(shell.mobileNavigation.tab.name, tab);

        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(requests() - before, tab == 'destination/groups' ? 1 : 2);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }

  for (final tab in [
    'panel/chat',
    'destination/summary',
    'destination/activity',
    'destination/preferences',
    'destination/appearance',
    'destination/events-upcoming',
    'destination/boards',
    'destination/dashboard',
    'destination/drafts',
  ]) {
    testWidgets(
      'rapid $tab taps do not reload the current page',
      (tester) async {
        late FakeDiscourseApi api;
        final shell = await fixture.pumpMobileShellFixture(
          tester,
          events: true,
          board: boardFixtureJson(),
          user: const DiscourseUser(id: 7, username: 'reader', staff: true),
          onApi: (value) => api = value,
        );
        if (tab == 'destination/drafts') {
          api.userDraftList = const [
            UserDraft(
              key: 'new_topic',
              sequence: 1,
              data: ComposerDraft(title: 'Draft topic', reply: 'Draft body'),
            ),
          ];
          await shell.draftList.load(shell.currentInstance!, refresh: true);
          await tester.pumpAndSettle();
        }
        await _showInBar(tester, tab);
        final button = find.byKey(ValueKey('mobile-mode-$tab'));
        await tester.tap(button);
        await tester.pumpAndSettle();
        final requests = [
          List.of(api.pluginReadPaths),
          api.chatChannelsRequested.length,
          api.userSummaryRequests.length,
          api.userActivityRequests.length,
          api.userDraftRequests.length,
          api.userPreferenceLoads.length,
        ];
        for (var tap = 0; tap < 6; tap++) {
          await tester.tap(button);
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pumpAndSettle();
        expect([
          api.pluginReadPaths,
          api.chatChannelsRequested.length,
          api.userSummaryRequests.length,
          api.userActivityRequests.length,
          api.userDraftRequests.length,
          api.userPreferenceLoads.length,
        ], requests);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }
}
