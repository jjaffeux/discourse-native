import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/shell/group_pages_coordinator.dart';
import 'package:discourse_native/src/shell/group_pages_host.dart';
import 'package:discourse_native/src/shell/group_pages_port.dart';
import 'package:discourse_native/src/shell/groups_controller.dart';
import 'package:discourse_native/src/shell/groups_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

final class _Port implements GroupPagesPort {
  final ChangeNotifier _changes = ChangeNotifier();
  final GroupPagesOwner owner = (
    siteUrl: 'https://meta.example',
    accountIdentity: 'user:sam',
    tabId: 'tab-1',
  );
  int directoryLoads = 0;

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
  ) => const GroupDirectoryState(loaded: true);

  @override
  bool canCreateGroup(GroupPagesOwner owner) => false;

  @override
  Future<void> loadDirectory(
    GroupPagesOwner owner,
    GroupPagesDirectoryQuery query, {
    required bool refresh,
    required bool more,
  }) async {
    directoryLoads++;
  }

  void dispose() => _changes.dispose();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
