import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/shell/group_page.dart';
import 'package:discourse_native/src/shell/group_pages_coordinator.dart';
import 'package:discourse_native/src/shell/group_pages_shell_port.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _group = Group(id: 9, name: 'support', canAdminGroup: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (destination, acknowledgmentOnly, retryHydration) in [
    for (final destination in ['opening', 'other tab', 'directory', 'retired'])
      for (final acknowledgmentOnly in [false, true])
        (destination, acknowledgmentOnly, false),
    ('opening', true, true),
  ]) {
    for (final confirmed in [false, true]) {
      test(
        'rename ${acknowledgmentOnly ? 'acknowledgment' : 'full group'} ${retryHydration ? 'retry' : 'immediate'} ${confirmed ? 'confirmation' : 'save'} preserves $destination navigation',
        () async {
          final server = _Server(
            confirm: confirmed,
            acknowledgmentOnly: acknowledgmentOnly,
            idFailures: retryHydration ? 1 : 0,
          );
          addTearDown(server.api.close);
          final store = FakeForumTabStore([_workspace()]);
          final shell = ShellController(
            api: server.api,
            instanceStore: FakeInstanceStore([
              instance('meta.discourse.org').copyWith(
                user: const DiscourseUser(
                  id: 7,
                  username: 'reader',
                  admin: true,
                ),
              ),
            ]),
            forumTabs: store,
            authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
            drafts: FakeDraftStore(),
            trackers: FakeSiteTracker.reset(),
            updater: FakeUpdater(),
            updateStore: FakeUpdateStore(),
            ownsApi: false,
          );
          addTearDown(shell.dispose);
          await shell.load();
          await pumpEventQueue();
          final unchanged = shell.currentWorkspace!.tabById('opening');
          shell.replaceOpeningGroupName(
            siteUrl: _site,
            tabId: 'opening',
            previousName: 'support',
            group: _group,
          );
          expect(shell.currentWorkspace!.tabById('opening'), same(unchanged));
          final port = ShellGroupPagesPort(shell, tabId: 'opening');
          final GroupPagesOwner owner = (
            siteUrl: _site,
            accountIdentity: shell.currentAccountIdentity!,
            sessionIdentity: shell.lifecycle.capture(_site).session,
            tabId: 'opening',
          );
          Future<GroupWriteOutcome<void>> pending;
          if (confirmed) {
            final confirmation =
                await port.saveManage(
                      owner,
                      _group,
                      GroupManageUpdate(
                        subsection: GroupRoute.membership,
                        values: const {'name': 'requested'},
                      ),
                    )
                    as GroupUpdateConfirmation;
            expect(shell.currentContent?.groupRoute?.groupName, 'support');
            pending = port.confirmManage(
              owner,
              confirmation,
              applyToExistingUsers: true,
            );
          } else {
            pending = port.saveManage(
              owner,
              _group,
              GroupManageUpdate(
                subsection: GroupRoute.membership,
                values: const {'name': 'requested'},
              ),
            );
          }
          await server.started.future;
          if (destination == 'other tab') {
            shell.selectTab('other');
          }
          final directoryCoordinator = GroupPagesCoordinator();
          addTearDown(directoryCoordinator.dispose);
          if (destination == 'directory') {
            shell.pushContent(ContentRoute.group(const GroupRoute.directory()));
            directoryCoordinator.bind(
              port,
              GroupPagesRouteSnapshot(
                owner: owner,
                routeId: shell.currentContent!.id,
                groupNamespace: true,
                route: const GroupRoute.directory(),
                canPopContent: true,
              ),
            );
            await directoryCoordinator.requestLoad();
            expect(
              port
                  .directoryState(owner, directoryCoordinator.directoryQuery)
                  .loaded,
              isTrue,
            );
          }
          if (destination == 'retired') {
            shell.lifecycle.invalidate(_site);
            shell.groups.forget(_site);
          }
          final activeTab = shell.activeTabId;
          final content = shell.currentContent;
          final other = shell.currentWorkspace!.tabById('other');
          final openingBefore = shell.currentWorkspace!.tabById('opening')!;
          server.release.complete();
          final result = await pending;
          if (retryHydration) {
            expect(
              result,
              isA<GroupWriteAccepted<Group>>().having(
                (result) => result.projection,
                'freshness',
                GroupProjectionFreshness.stale,
              ),
            );
            expect(shell.currentContent?.groupRoute?.groupName, 'support');
            await port.loadDetail(
              owner,
              GroupRoute.detail('support', section: GroupRoute.manage),
              refresh: true,
            );
            expect(server.idLoads, 2);
          }
          if (destination == 'directory') {
            await directoryCoordinator.requestLoad();
            final directory = port.directoryState(
              owner,
              directoryCoordinator.directoryQuery,
            );
            expect(directory.loaded, isTrue);
            expect(directory.groups.map((group) => group.name), [
              'canonical',
              'unrelated',
            ]);
            expect(server.directoryLoads, 1);
          }
          if (destination != 'retired') {
            expect(
              shell.groups.detailState(_site, 'canonical').detail?.group.name,
              'canonical',
            );
          }
          expect(
            result,
            isA<GroupWriteAccepted<Group>>().having(
              (result) => result.projection,
              'projection',
              destination == 'retired'
                  ? GroupProjectionFreshness.retired
                  : acknowledgmentOnly && !retryHydration
                  ? GroupProjectionFreshness.refreshed
                  : GroupProjectionFreshness.stale,
            ),
          );
          expect(shell.activeTabId, activeTab);
          expect(shell.currentWorkspace!.tabById('other'), same(other));
          if (destination != 'opening') {
            expect(shell.currentContent, same(content));
          }
          final opening = shell.currentWorkspace!.tabById('opening')!;
          if (destination == 'retired') {
            expect(opening, same(openingBefore));
            expect(shell.groups.detailState(_site, 'canonical').detail, isNull);
            return;
          }
          expect(
            shell.groups.detailState(_site, 'canonical').detail?.group.name,
            'canonical',
          );
          expect(opening.backHistory.length, openingBefore.backHistory.length);
          expect(
            opening.forwardHistory.length,
            openingBefore.forwardHistory.length,
          );
          final routes = [
            ...opening.contentStack,
            for (final entry in opening.backHistory) ...entry.contentStack,
            for (final entry in opening.forwardHistory) ...entry.contentStack,
          ].where((content) => content.groupRoute?.isDetail == true).toList();
          expect(routes, isNotEmpty);
          expect(routes.map((route) => route.groupRoute!.groupName).toSet(), {
            'canonical',
          });
          final manage = routes.firstWhere(
            (route) => route.groupRoute!.section == GroupRoute.manage,
          );
          expect(manage.groupRoute!.subsection, GroupRoute.membership);
          expect(manage.title, 'Canonical team');
          final messages = routes.firstWhere(
            (route) => route.groupRoute!.section == GroupRoute.messages,
          );
          expect(
            messages.feedPath,
            '/topics/private-messages-group/reader/canonical/archive.json',
          );
          final plugin = routes.firstWhere(
            (route) => route.groupRoute!.isPlugin,
          );
          expect(plugin.groupRoute!.pluginOwner, 'example');
          expect(plugin.groupRoute!.section, 'extras');
          expect(plugin.groupRoute!.subsection, 'details');
          expect(plugin.feedPath, '/plugin/feed.json');
          expect(plugin.subtitle, 'Plugin metadata');
          if (destination != 'directory') {
            final topics = opening.forwardHistory.single.contentStack.single;
            expect(topics.feedPath, '/topics/groups/canonical.json');
          }
          expect(
            store.workspaces.single.tabById('opening')!.currentContent,
            opening.currentContent,
          );
        },
      );
    }
  }
}

ForumWorkspace _workspace() => ForumWorkspace(
  siteUrl: _site,
  accountIdentity: 'user:reader',
  activeTabId: 'opening',
  tabs: [
    ForumTab(
      id: 'opening',
      rootDestinationId: 'groups',
      contentStack: [
        ContentRoute.group(
          GroupRoute.detail(
            'support',
            section: GroupRoute.manage,
            subsection: GroupRoute.membership,
          ),
        ),
      ],
      backHistory: [
        ForumTabLocation(
          rootDestinationId: 'groups',
          contentStack: [
            ContentRoute.group(
              GroupRoute.detail(
                'support',
                section: GroupRoute.messages,
                subsection: GroupRoute.archive,
              ),
              feedPath:
                  '/topics/private-messages-group/reader/support/archive.json',
            ),
            ContentRoute.group(
              GroupRoute.plugin(
                groupName: 'support',
                owner: 'example',
                section: 'extras',
                subsection: 'details',
              ),
              feedPath: '/plugin/feed.json',
            ).withDisplay(subtitle: 'Plugin metadata'),
          ],
        ),
      ],
      forwardHistory: [
        ForumTabLocation(
          rootDestinationId: 'groups',
          contentStack: [
            ContentRoute.group(
              GroupRoute.detail(
                'support',
                section: GroupRoute.activity,
                subsection: GroupRoute.topics,
              ),
              feedPath: '/topics/groups/support.json',
            ),
          ],
        ),
      ],
    ),
    ForumTab(
      id: 'other',
      rootDestinationId: 'groups',
      contentStack: [ContentRoute.group(GroupRoute.detail('support'))],
    ),
  ],
);

final class _Server {
  _Server({
    required this.confirm,
    required this.acknowledgmentOnly,
    this.idFailures = 0,
  });
  int idFailures;
  int idLoads = 0;
  final bool acknowledgmentOnly;
  final bool confirm;
  int writes = 0;
  bool saved = false;
  int directoryLoads = 0;
  final started = Completer<void>();
  final release = Completer<void>();
  late final api = DiscourseApi(
    client: MockClient((request) async {
      if (request.method == 'PUT') {
        expect(request.url.path, '/groups/9.json');
        if (confirm && writes++ == 0) {
          return http.Response(
            jsonEncode({
              'errors': ['Affects existing members'],
              'user_count': 3,
            }),
            422,
          );
        }
        started.complete();
        await release.future;
        saved = true;
        if (acknowledgmentOnly) return http.Response('{"success":"OK"}', 200);
        return http.Response(
          jsonEncode({
            'group': {
              'id': 9,
              'name': 'canonical',
              'full_name': 'Canonical team',
              'can_admin_group': true,
            },
          }),
          200,
        );
      }
      if (saved && request.url.path == '/groups/support.json') {
        return http.Response('{}', 404);
      }
      if (request.url.path == '/groups/by-id/9.json') {
        idLoads++;
        if (idFailures-- > 0) return http.Response('{}', 500);
        return http.Response(
          jsonEncode({
            'group': {
              'id': 9,
              'name': 'canonical',
              'full_name': 'Canonical team',
              'can_admin_group': true,
            },
          }),
          200,
        );
      }
      if (request.url.path == '/groups/canonical.json') {
        return http.Response('{}', 500);
      }
      if (request.url.path == '/groups.json') directoryLoads++;
      final Object body = switch (request.url.path) {
        '/session/current.json' => {
          'current_user': {'id': 7, 'username': 'reader', 'admin': true},
        },
        '/site/basic-info.json' => {'title': 'Test forum'},
        '/site/settings.json' => {
          'site_settings': {'default_homepage': 'latest'},
        },
        '/groups/support.json' => {
          'group': {'id': 9, 'name': 'support', 'can_admin_group': true},
        },
        '/groups.json' => {
          'groups': [
            {'id': 9, 'name': 'support'},
            {'id': 10, 'name': 'unrelated'},
          ],
          'total_rows_groups': 2,
        },
        '/latest.json' => {
          'topic_list': {'topics': <Object?>[]},
        },
        _ => <String, Object?>{},
      };
      return http.Response(jsonEncode(body), 200);
    }),
  );
}
