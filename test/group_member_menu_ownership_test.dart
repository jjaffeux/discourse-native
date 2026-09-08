import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/shell/group_page.dart';
import 'package:discourse_native/src/shell/group_pages_coordinator.dart';
import 'package:discourse_native/src/shell/group_pages_host.dart';
import 'package:discourse_native/src/shell/group_pages_port.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _group = Group(
  id: 9,
  name: 'support',
  fullName: 'Support Team',
  canSeeMembers: true,
  canAdminGroup: true,
);
const _alice = GroupMember(id: 1, username: 'alice');
const _bob = GroupMember(id: 2, username: 'bob');
const _carol = GroupMember(id: 3, username: 'carol');

void main() {
  for (final width in [1180.0, 390.0]) {
    group('member menus at width $width', () {
      for (final action in [
        GroupMemberAction.makeOwner,
        GroupMemberAction.remove,
      ]) {
        testWidgets('$action still targets Alice after a member refresh', (
          tester,
        ) async {
          final port = await _pump(tester, width: width);
          await _openMenu(tester, _alice);

          port.replaceMembers([_alice.copyWith(primary: true), _bob]);
          await tester.pump();
          await _selectAction(tester, action);
          if (action == GroupMemberAction.remove) {
            port.replaceMembers([_alice.copyWith(primary: false), _bob]);
            await tester.pump();
            await _confirmRemoval(tester, _alice);
          }

          expect(port.actions, [_expectedAction(port, _alice, action)]);
          _expectNoStaleFeedback(tester);
        });

        for (final (change, members) in _rowChanges) {
          testWidgets('$action retires when Alice is $change', (tester) async {
            final port = await _pump(tester, width: width);
            await _openMenu(tester, _alice);

            port.replaceMembers(members);
            await tester.pump();
            await _selectAction(tester, action);

            expect(port.actions, isEmpty);
            expect(find.byType(AlertDialog), findsNothing);
            _expectNoStaleFeedback(tester);

            final current = members.first;
            await _openMenu(tester, current);
            await _selectAction(tester, action);
            if (action == GroupMemberAction.remove) {
              await _confirmRemoval(tester, current);
            }
            expect(port.actions, [_expectedAction(port, current, action)]);
          });
        }
      }

      for (final (change, members) in _rowChanges) {
        testWidgets('removal confirmation retires when Alice is $change', (
          tester,
        ) async {
          final port = await _pump(tester, width: width);
          await _openMenu(tester, _alice);
          await _selectAction(tester, GroupMemberAction.remove);
          expect(find.text('Remove @alice?'), findsOneWidget);

          port.replaceMembers(members);
          await tester.pump();
          await _confirmRemoval(tester, _alice);

          expect(port.actions, isEmpty);
          _expectNoStaleFeedback(tester);
        });
      }
    });
  }

  for (final confirming in [false, true]) {
    testWidgets(
      '${confirming ? 'removal confirmation' : 'member menu'} retires when the group ID changes',
      (tester) async {
        final port = await _pump(tester);
        await _openMenu(tester, _alice);
        if (confirming) {
          await _selectAction(tester, GroupMemberAction.remove);
        }

        port.group = const Group(
          id: 10,
          name: 'support',
          fullName: 'Replacement Support Team',
          canSeeMembers: true,
          canAdminGroup: true,
        );
        port.replaceMembers([_alice, _bob]);
        await tester.pump();
        if (confirming) {
          await _confirmRemoval(tester, _alice);
        } else {
          await _selectAction(tester, GroupMemberAction.makeOwner);
        }

        expect(port.actions, isEmpty);
        _expectNoStaleFeedback(tester);

        await _openMenu(tester, _alice);
        await _selectAction(tester, GroupMemberAction.makeOwner);
        expect(port.actions, [
          _expectedAction(port, _alice, GroupMemberAction.makeOwner),
        ]);
      },
    );
  }
}

const _rowChanges = [
  ('reordered', [_bob, _alice]),
  ('removed', [_bob]),
  ('replaced', [_carol, _bob]),
];

Future<_Port> _pump(WidgetTester tester, {double width = 1180}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final port = _Port();
  addTearDown(port.dispose);
  final coordinator = GroupPagesCoordinator();
  addTearDown(coordinator.dispose);
  final route = GroupRoute.detail(_group.name);
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
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: GroupPagesHost(
          key: ValueKey(coordinator.childIdentity),
          coordinator: coordinator,
          port: port,
          registry: PluginRegistry.empty,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(GroupPage), findsOneWidget);
  return port;
}

Future<void> _openMenu(WidgetTester tester, GroupMember member) async {
  await tester.tap(find.byTooltip('Manage @${member.username}'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('command-menu-surface')), findsOneWidget);
}

Future<void> _selectAction(
  WidgetTester tester,
  GroupMemberAction action,
) async {
  await tester.tap(
    find.text(
      action == GroupMemberAction.remove ? 'Remove from group' : 'Make owner',
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _confirmRemoval(WidgetTester tester, GroupMember member) async {
  expect(find.text('Remove @${member.username}?'), findsOneWidget);
  await tester.tap(find.text('Remove member'));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
}

void _expectNoStaleFeedback(WidgetTester tester) {
  expect(find.byKey(const ValueKey('command-menu-surface')), findsNothing);
  expect(find.text('The member could not be updated.'), findsNothing);
  expect(tester.takeException(), isNull);
}

typedef _Action = ({
  GroupPagesOwner owner,
  int groupId,
  String groupName,
  int memberId,
  String username,
  GroupMemberAction action,
});

_Action _expectedAction(
  _Port port,
  GroupMember member,
  GroupMemberAction action,
) => (
  owner: port.owner,
  groupId: port.group.id,
  groupName: port.group.name,
  memberId: member.id,
  username: member.username,
  action: action,
);

final class _Port extends ChangeNotifier implements GroupPagesPort {
  @override
  final Object controllerIdentity = Object();

  final GroupPagesOwner owner = (
    siteUrl: 'https://meta.example',
    accountIdentity: 'user:manager',
    tabId: 'tab-1',
  );
  Group group = _group;
  List<GroupMember> members = [_alice, _bob];
  final actions = <_Action>[];

  void replaceMembers(List<GroupMember> value) {
    members = value;
    notifyListeners();
  }

  @override
  Listenable get changes => this;

  @override
  bool isCurrent(GroupPagesOwner value) => value == owner;

  @override
  GroupPageData groupData(
    GroupPagesOwner owner,
    GroupRoute route,
    GroupPagesMemberQuery memberQuery,
  ) => GroupPageData(
    detail: GroupDetail(group: group),
    members: GroupMembersPage(members: members, total: members.length),
    loaded: true,
  );

  @override
  TopicFeed? topicFeed(GroupPagesOwner owner, String routeId) => null;

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

  @override
  Future<bool> memberAction(
    GroupPagesOwner owner,
    Group group,
    GroupMember member,
    GroupMemberAction action,
  ) async {
    actions.add((
      owner: owner,
      groupId: group.id,
      groupName: group.name,
      memberId: member.id,
      username: member.username,
      action: action,
    ));
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
