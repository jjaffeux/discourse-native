// Kept free of testWidgets so construction stays independent of a binding.
import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/shell/group_pages_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroupPagesCoordinator route resolution', () {
    test('restored routes resolve to their native child identities', () {
      final restoredDirectory = ContentRoute.fromJson(
        ContentRoute.group(const GroupRoute.directory()).toJson(),
      );
      final restoredDetail = ContentRoute.fromJson(
        ContentRoute.group(
          GroupRoute.detail(
            'staff',
            section: GroupRoute.activity,
            subsection: GroupRoute.posts,
          ),
        ).toJson(),
      );
      const owner = (
        siteUrl: 'https://one.example',
        accountIdentity: 'user:one',
        tabId: 'tab-1',
      );

      final directory = GroupPagesCoordinator.resolve(
        _snapshot(owner: owner, content: restoredDirectory),
      );
      final detail = GroupPagesCoordinator.resolve(
        _snapshot(owner: owner, content: restoredDetail),
      );

      expect(directory.kind, GroupPagesPageKind.directory);
      expect(detail.kind, GroupPagesPageKind.detail);
      expect(detail.route, restoredDetail.groupRoute);
    });

    test('unknown group namespace routes are owned but never loaded', () async {
      final port = _Port();
      final subject = GroupPagesCoordinator();
      addTearDown(subject.dispose);

      subject.bind(
        port,
        GroupPagesRouteSnapshot(
          owner: port.owner,
          routeId: 'group-corrupt',
          groupNamespace: true,
          route: null,
          canPopContent: false,
        ),
      );
      await subject.requestLoad();

      expect(subject.page.kind, GroupPagesPageKind.unknown);
      expect(subject.childIdentity?.pageId, 'unknown:group-corrupt');
      expect(port.loads, isEmpty);
    });

    test('non-group routes are declined', () {
      final port = _Port();
      final subject = GroupPagesCoordinator();
      addTearDown(subject.dispose);

      subject.bind(
        port,
        GroupPagesRouteSnapshot(
          owner: port.owner,
          routeId: 'latest',
          groupNamespace: false,
          route: null,
          canPopContent: false,
        ),
      );

      expect(subject.page.kind, GroupPagesPageKind.none);
      expect(subject.childIdentity, isNull);
    });
  });

  group('GroupPagesCoordinator lifecycle', () {
    test('section transitions retain the group child and member query', () {
      final port = _Port();
      final subject = GroupPagesCoordinator();
      addTearDown(subject.dispose);
      final members = GroupRoute.detail('staff');
      final activity = GroupRoute.detail(
        'staff',
        section: GroupRoute.activity,
        subsection: GroupRoute.topics,
      );

      subject.bind(port, _groupSnapshot(port.owner, members));
      final child = subject.childIdentity;
      subject.replaceMemberQuery(
        const GroupPagesMemberQuery(
          filter: 'sam',
          order: 'username',
          ascending: true,
        ),
      );
      subject.bind(port, _groupSnapshot(port.owner, activity));
      subject.selectRoute(members);

      expect(subject.childIdentity, child);
      expect(subject.memberQuery.filter, 'sam');
      expect(port.selected.single.route, members);
      expect(port.selected.single.feedPath, isNull);
    });

    test(
      'site switch and account rotation replace page ownership and filters',
      () {
        final port = _Port();
        final subject = GroupPagesCoordinator();
        addTearDown(subject.dispose);
        final route = GroupRoute.detail('staff');

        subject.bind(port, _groupSnapshot(port.owner, route));
        subject
          ..replaceDirectoryQuery(
            const GroupPagesDirectoryQuery(filter: 'team', type: 'my'),
          )
          ..replaceMemberQuery(const GroupPagesMemberQuery(filter: 'sam'));
        final first = subject.childIdentity;

        port.owner = (
          siteUrl: port.owner.siteUrl,
          accountIdentity: 'user:two',
          tabId: port.owner.tabId,
        );
        subject.bind(port, _groupSnapshot(port.owner, route));
        final rotated = subject.childIdentity;

        expect(rotated, isNot(first));
        expect(subject.directoryQuery, const GroupPagesDirectoryQuery());
        expect(subject.memberQuery, const GroupPagesMemberQuery());

        port.owner = (
          siteUrl: 'https://two.example',
          accountIdentity: 'user:two',
          tabId: 'tab-2',
        );
        subject.bind(port, _groupSnapshot(port.owner, route));

        expect(subject.childIdentity, isNot(rotated));
        expect(subject.childIdentity?.owner.siteUrl, 'https://two.example');
      },
    );

    test('stale detail completion cannot start a section load', () async {
      final port = _Port()..detailGate = Completer<void>();
      final subject = GroupPagesCoordinator();
      addTearDown(subject.dispose);
      final first = GroupRoute.detail('staff');
      final second = GroupRoute.detail('moderators');

      subject.bind(port, _groupSnapshot(port.owner, first));
      final load = subject.requestLoad();
      await Future<void>.delayed(Duration.zero);
      expect(port.loads, ['detail:staff']);

      subject.bind(port, _groupSnapshot(port.owner, second));
      port.detailGate!.complete();
      await load;

      expect(port.loads, ['detail:staff']);
    });

    test('account rotation rejects an in-flight detail continuation', () async {
      final port = _Port()..detailGate = Completer<void>();
      final subject = GroupPagesCoordinator();
      addTearDown(subject.dispose);
      final route = GroupRoute.detail('staff');

      subject.bind(port, _groupSnapshot(port.owner, route));
      final load = subject.requestLoad();
      await Future<void>.delayed(Duration.zero);
      port.owner = (
        siteUrl: port.owner.siteUrl,
        accountIdentity: 'user:rotated',
        tabId: port.owner.tabId,
      );
      subject.bind(port, _groupSnapshot(port.owner, route));
      port.detailGate!.complete();
      await load;

      expect(port.loads, ['detail:staff']);
    });
  });

  group('GroupPagesCoordinator back navigation', () {
    test('derives pop, sidebar, and none intents at the boundary', () {
      final port = _Port();
      final subject = GroupPagesCoordinator();
      addTearDown(subject.dispose);
      final route = GroupRoute.detail('staff');

      subject.bind(
        port,
        _groupSnapshot(port.owner, route, canPopContent: true),
      );
      expect(
        subject.backIntent(canReturnToSidebar: false),
        GroupPagesBackIntent.popContent,
      );
      expect(subject.handleBack(canReturnToSidebar: false), isTrue);
      expect(port.backRequests, [false]);

      subject.bind(port, _groupSnapshot(port.owner, route));
      expect(
        subject.backIntent(canReturnToSidebar: true),
        GroupPagesBackIntent.showSidebar,
      );
      expect(
        subject.backIntent(canReturnToSidebar: false),
        GroupPagesBackIntent.none,
      );
      expect(subject.handleBack(canReturnToSidebar: true), isTrue);
      expect(port.backRequests, [false, true]);
    });
  });
}

GroupPagesRouteSnapshot _snapshot({
  required GroupPagesOwner owner,
  required ContentRoute content,
}) => GroupPagesRouteSnapshot(
  owner: owner,
  routeId: content.id,
  groupNamespace: true,
  route: content.groupRoute,
  canPopContent: false,
);

GroupPagesRouteSnapshot _groupSnapshot(
  GroupPagesOwner owner,
  GroupRoute route, {
  bool canPopContent = false,
}) => GroupPagesRouteSnapshot(
  owner: owner,
  routeId: route.id,
  groupNamespace: true,
  route: route,
  canPopContent: canPopContent,
);

final class _Port implements GroupPagesCoordinatorPort {
  GroupPagesOwner owner = (
    siteUrl: 'https://one.example',
    accountIdentity: 'user:one',
    tabId: 'tab-1',
  );
  Completer<void>? detailGate;
  final List<String> loads = [];
  final List<({GroupRoute route, String? feedPath})> selected = [];
  final List<bool> backRequests = [];

  @override
  bool isCurrent(GroupPagesOwner value) => value == owner;

  @override
  String? usernameFor(GroupPagesOwner owner) => 'sam';

  @override
  Future<void> loadDirectory(
    GroupPagesOwner owner,
    GroupPagesDirectoryQuery query, {
    required bool refresh,
    required bool more,
  }) async {
    loads.add('directory:${query.filter}:$refresh:$more');
  }

  @override
  Future<void> loadDetail(
    GroupPagesOwner owner,
    GroupRoute route, {
    required bool refresh,
  }) async {
    loads.add('detail:${route.groupName}');
    final gate = detailGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> loadSection(
    GroupPagesOwner owner,
    GroupRoute route,
    GroupPagesMemberQuery memberQuery, {
    required bool refresh,
    required bool more,
  }) async {
    loads.add('section:${route.groupName}:${route.section}');
  }

  @override
  void selectRoute(GroupRoute route, {String? feedPath}) {
    selected.add((route: route, feedPath: feedPath));
  }

  @override
  void replaceWithDirectory() {}

  @override
  bool handleBack({required bool canReturnToSidebar}) {
    backRequests.add(canReturnToSidebar);
    return true;
  }
}
