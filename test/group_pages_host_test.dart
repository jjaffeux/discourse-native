import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/shell/group_page.dart';
import 'package:discourse_native/src/shell/group_pages_coordinator.dart';
import 'package:discourse_native/src/shell/group_pages_host.dart';
import 'package:discourse_native/src/shell/group_pages_port.dart';
import 'package:discourse_native/src/shell/groups_controller.dart';
import 'package:discourse_native/src/shell/groups_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('directory renders and dispatches its initial load', (
    tester,
  ) async {
    final port = _Port();
    addTearDown(port.dispose);
    final coordinator = GroupPagesCoordinator();
    addTearDown(coordinator.dispose);
    coordinator.bind(
      port,
      GroupPagesRouteSnapshot(
        owner: port.owner,
        routeId: 'groups',
        groupNamespace: true,
        route: const GroupRoute.directory(),
        canPopContent: false,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupPagesHost(
            coordinator: coordinator,
            port: port,
            registry: PluginRegistry.empty,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GroupsPage), findsOneWidget);
    expect(port.directoryLoads, 1);
  });

  testWidgets('unknown restored route renders a deterministic boundary state', (
    tester,
  ) async {
    final port = _Port();
    addTearDown(port.dispose);
    final coordinator = GroupPagesCoordinator();
    addTearDown(coordinator.dispose);
    coordinator.bind(
      port,
      GroupPagesRouteSnapshot(
        owner: port.owner,
        routeId: 'group-corrupt',
        groupNamespace: true,
        route: null,
        canPopContent: false,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupPagesHost(
            coordinator: coordinator,
            port: port,
            registry: PluginRegistry.empty,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('unknown-group-route')), findsOneWidget);
    expect(port.directoryLoads, 0);
  });

  testWidgets(
    'group messages render the selected feed without an inbox picker',
    (tester) async {
      final shell = _Shell();
      addTearDown(shell.dispose);
      final port = _Port()
        ..group = const GroupPageData(
          detail: GroupDetail(
            group: Group(
              id: 4,
              name: 'support',
              hasMessages: true,
              canAdminGroup: true,
            ),
          ),
          canSendPrivateMessages: true,
          loaded: true,
        )
        ..feed = const TopicFeed(loaded: true);
      addTearDown(port.dispose);
      final coordinator = GroupPagesCoordinator();
      addTearDown(coordinator.dispose);
      final route = GroupRoute.detail(
        'support',
        section: GroupRoute.messages,
        subsection: GroupRoute.inbox,
      );
      coordinator.bind(
        port,
        GroupPagesRouteSnapshot(
          owner: port.owner,
          routeId: route.id,
          groupNamespace: true,
          route: route,
          canPopContent: false,
        ),
      );

      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: GroupPagesHost(
                coordinator: coordinator,
                port: port,
                registry: PluginRegistry.empty,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TopicListView), findsOneWidget);
      expect(find.byKey(const ValueKey('message-inbox-picker')), findsNothing);
      expect(find.text('Nothing here yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

final class _Port implements GroupPagesPort {
  final ChangeNotifier _changes = ChangeNotifier();
  final GroupPagesOwner owner = (
    siteUrl: 'https://meta.example',
    accountIdentity: 'user:sam',
    tabId: 'tab-1',
  );
  int directoryLoads = 0;
  GroupPageData? group;
  TopicFeed? feed;

  @override
  Listenable get changes => _changes;

  @override
  bool isCurrent(GroupPagesOwner value) => value == owner;

  @override
  String? usernameFor(GroupPagesOwner owner) => 'sam';

  @override
  GroupDirectoryState directoryState(
    GroupPagesOwner owner,
    GroupPagesDirectoryQuery query,
  ) => GroupDirectoryState(loaded: true);

  @override
  bool canCreateGroup(GroupPagesOwner owner) => false;

  @override
  GroupPageData groupData(
    GroupPagesOwner owner,
    GroupRoute route,
    GroupPagesMemberQuery memberQuery,
  ) => group!;

  @override
  TopicFeed? topicFeed(GroupPagesOwner owner, String routeId) => feed;

  @override
  Future<void> loadDirectory(
    GroupPagesOwner owner,
    GroupPagesDirectoryQuery query, {
    required bool refresh,
    required bool more,
  }) async {
    directoryLoads++;
  }

  @override
  Future<void> loadDetail(
    GroupPagesOwner owner,
    GroupRoute route, {
    required bool refresh,
  }) async {}

  @override
  Future<void> loadSection(
    GroupPagesOwner owner,
    GroupRoute route,
    GroupPagesMemberQuery memberQuery, {
    required bool refresh,
    required bool more,
  }) async {}

  void dispose() => _changes.dispose();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Shell extends ShellController {
  _Shell()
    : super(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
      );
}
