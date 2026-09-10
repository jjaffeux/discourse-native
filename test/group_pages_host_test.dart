import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
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
      expect(find.byType(DMessageInboxMenu<String>), findsNothing);
      expect(find.text('Nothing here yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  group('group deletion navigation', () {
    for (final destination in _DeleteDestination.values) {
      for (final returnToOrigin in [false, true]) {
        testWidgets(
          'successful deletion preserves ${destination.name}'
          '${returnToOrigin ? ' after returning to the original page' : ''}',
          (tester) async {
            final host = _DeleteHost();
            addTearDown(host.dispose);
            await host.pump(tester);
            final originalPort = host.port;
            final originalOwner = originalPort.owner;
            final originalRoute = host.route;
            final deletion = tester
                .widget<GroupPage>(find.byType(GroupPage))
                .onDeleteGroup!();

            expect(originalPort.deleteRequests.single.owner, originalOwner);
            expect(originalPort.deleteRequests.single.group.name, 'staff');
            expect(originalPort.deletions, isEmpty);

            host.navigate(destination);
            await host.pump(tester);
            if (returnToOrigin) {
              host.port = originalPort;
              host.port.owner = originalOwner;
              host.route = originalRoute;
              await host.pump(tester);
            }
            final destinationRoute = host.route;
            final destinationOwner = host.port.owner;

            originalPort.deleteGate!.complete(true);
            expect(await deletion, isTrue);
            await host.pump(tester);

            expect(originalPort.deletions, originalPort.deleteRequests);
            expect(host.route, destinationRoute);
            expect(host.port.owner, destinationOwner);
            for (final port in host.ports) {
              expect(port.directoryReplacements, 0);
              if (port != originalPort) expect(port.deleteRequests, isEmpty);
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    for (final succeeds in [true, false]) {
      testWidgets(
        'confirmed deletion ${succeeds ? 'opens the directory' : 'shows failure and keeps the group'}',
        (tester) async {
          final host = _DeleteHost();
          addTearDown(host.dispose);
          await host.pump(tester);
          await tester.tap(find.byKey(const ValueKey('group-actions')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('delete-group')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('group-delete-confirmation')),
            'staff',
          );
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('confirm-delete-group')));
          await tester.pumpAndSettle();
          expect(host.port.deleteRequests, hasLength(1));

          // Ordinary rebuilds and query edits keep the initiating page active.
          host.coordinator.replaceMemberQuery(
            const GroupPagesMemberQuery(filter: 'sam'),
          );
          await host.pump(tester);
          host.port.deleteGate!.complete(succeeds);
          await tester.pumpAndSettle();
          await host.pump(tester);

          expect(host.port.directoryReplacements, succeeds ? 1 : 0);
          expect(host.port.deletions, hasLength(succeeds ? 1 : 0));
          expect(
            find.byType(succeeds ? GroupsPage : GroupPage),
            findsOneWidget,
          );
          expect(
            find.text('The group could not be deleted.'),
            succeeds ? findsNothing : findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('disposal does not cancel an admitted deletion', (
      tester,
    ) async {
      final host = _DeleteHost();
      addTearDown(host.dispose);
      await host.pump(tester);
      final deletion = tester
          .widget<GroupPage>(find.byType(GroupPage))
          .onDeleteGroup!();
      await tester.pumpWidget(const SizedBox.shrink());
      host.coordinator.dispose();

      host.port.deleteGate!.complete(true);
      expect(await deletion, isTrue);
      expect(host.port.deletions, host.port.deleteRequests);
      expect(host.port.directoryReplacements, 0);
      expect(tester.takeException(), isNull);
    });
  });
}

enum _DeleteDestination {
  group,
  section,
  topic,
  tab,
  account,
  site,
  controller,
}

final class _DeleteHost {
  final coordinator = GroupPagesCoordinator();
  final ports = <_Port>[];
  late _Port port = _newPort()..deleteGate = Completer<bool>();
  GroupRoute? route = GroupRoute.detail('staff');

  _Port _newPort() {
    final port = _Port();
    ports.add(port);
    return port;
  }

  void navigate(_DeleteDestination destination) {
    switch (destination) {
      case _DeleteDestination.group:
        route = GroupRoute.detail('moderators');
      case _DeleteDestination.section:
        route = GroupRoute.detail(
          'staff',
          section: GroupRoute.activity,
          subsection: GroupRoute.posts,
        );
      case _DeleteDestination.topic:
        route = null;
      case _DeleteDestination.tab:
        port.owner = (
          siteUrl: port.owner.siteUrl,
          accountIdentity: port.owner.accountIdentity,
          tabId: 'tab-2',
        );
      case _DeleteDestination.account:
        port.owner = (
          siteUrl: port.owner.siteUrl,
          accountIdentity: 'user:alex',
          tabId: port.owner.tabId,
        );
      case _DeleteDestination.site:
        port.owner = (
          siteUrl: 'https://other.example',
          accountIdentity: port.owner.accountIdentity,
          tabId: port.owner.tabId,
        );
      case _DeleteDestination.controller:
        port = _newPort();
    }
  }

  Future<void> pump(WidgetTester tester) async {
    coordinator.bind(
      port,
      GroupPagesRouteSnapshot(
        owner: port.owner,
        routeId: route?.id ?? 'topic-42',
        groupNamespace: route != null,
        route: route,
        canPopContent: false,
      ),
    );
    port.onReplaceWithDirectory = () => route = const GroupRoute.directory();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: coordinator.page.isOwned
              ? GroupPagesHost(
                  coordinator: coordinator,
                  port: port,
                  registry: PluginRegistry.empty,
                )
              : const Text('Topic 42'),
        ),
      ),
    );
    await tester.pump();
  }

  void dispose() {
    coordinator.dispose();
    for (final port in ports) {
      port.dispose();
    }
  }
}

final class _Port implements GroupPagesPort {
  final ChangeNotifier _changes = ChangeNotifier();
  @override
  final Object controllerIdentity = Object();

  GroupPagesOwner owner = (
    siteUrl: 'https://meta.example',
    accountIdentity: 'user:sam',
    tabId: 'tab-1',
  );
  int directoryLoads = 0;
  int directoryReplacements = 0;
  Completer<bool>? deleteGate;
  VoidCallback? onReplaceWithDirectory;
  final deleteRequests = <({GroupPagesOwner owner, Group group})>[];
  final deletions = <({GroupPagesOwner owner, Group group})>[];
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
  ) =>
      group ??
      GroupPageData(
        detail: GroupDetail(
          group: Group(
            id: route.groupName == 'staff' ? 4 : 5,
            name: route.groupName!,
          ),
        ),
        isAdmin: true,
        loaded: true,
      );

  @override
  Future<bool> deleteGroup(GroupPagesOwner owner, Group group) async {
    if (!isCurrent(owner)) return false;
    final request = (owner: owner, group: group);
    deleteRequests.add(request);
    final deleted = await deleteGate!.future;
    if (deleted) deletions.add(request);
    return deleted;
  }

  @override
  void replaceWithDirectory(GroupPagesOwner owner, String routeId) {
    directoryReplacements++;
    onReplaceWithDirectory?.call();
  }

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
