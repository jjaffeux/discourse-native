import 'package:discourse_native/src/plugins/assign/assigned_group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assignment filters have stable route and cache identities', () {
    const everyone = AssignedGroupFilter.everyone();
    const direct = AssignedGroupFilter.directGroup();
    final member = AssignedGroupFilter.member(' SaM ');

    expect(everyone.routeSegment('support'), 'everyone');
    expect(direct.routeSegment('support'), 'support');
    expect(member.routeSegment('support'), 'sam');
    expect(member, AssignedGroupFilter.member('SAM'));
    expect(everyone, isNot(direct));
  });

  test('member payload is bounded and keeps optional fields optional', () {
    final page = AssignedGroupMembersPage.fromJson(
      const {
        'members': [
          {
            'id': 7,
            'username': 'Sam',
            'avatar_template': '/sam/{size}.png',
            'assignments_count': 4,
          },
          {'id': 'broken', 'username': 'ignored'},
        ],
        'assignment_count': -1,
        'group_assignment_count': 2,
      },
      'https://meta.example.com',
      offset: 0,
      limit: 2,
    );

    expect(page.members, const [
      AssignedGroupMember(
        id: 7,
        username: 'Sam',
        usernameLower: 'sam',
        avatarUrl: 'https://meta.example.com/sam/90.png',
        assignmentsCount: 4,
      ),
    ]);
    expect(page.assignmentCount, 0);
    expect(page.groupAssignmentCount, 2);
    expect(page.hasMore, isTrue, reason: 'wire slots, not valid rows, page');
  });

  test('member paging counts retained rows once with latest direct count', () {
    final first = AssignedGroupMembersPage(
      members: const [
        AssignedGroupMember(
          id: 1,
          username: 'one',
          usernameLower: 'one',
          assignmentsCount: 4,
        ),
      ],
      assignmentCount: 7,
      groupAssignmentCount: 3,
      offset: 0,
      limit: 50,
      hasMore: true,
    );
    final second = AssignedGroupMembersPage(
      members: const [
        AssignedGroupMember(
          id: 1,
          username: 'one',
          usernameLower: 'one',
          assignmentsCount: 8,
        ),
        AssignedGroupMember(
          id: 2,
          username: 'two',
          usernameLower: 'two',
          assignmentsCount: 5,
        ),
      ],
      assignmentCount: 14,
      groupAssignmentCount: 1,
      offset: 50,
      limit: 50,
      hasMore: false,
    );

    final state = const AssignedGroupMembersState()
        .withPage(first)
        .withPage(second);

    expect(state.members.map((member) => member.id), [1, 2]);
    expect(state.assignmentCount, 10);
    expect(state.exactAssignmentCount, 10);
    expect(state.groupAssignmentCount, 1);
    expect(state.nextOffset, 100);
    expect(state.hasMore, isFalse);
  });

  test('full pages expose a subtotal until an exhausted page arrives', () {
    var state = const AssignedGroupMembersState();
    expect(state.exactAssignmentCount, isNull);
    state = state.withPage(_page([_member(1), _member(2)]));
    expect(state.assignmentCount, 4);
    expect(state.exactAssignmentCount, isNull);
    state = state.withPage(_page([_member(3), _member(4)], offset: 2));
    expect(state.assignmentCount, 6);
    expect(state.exactAssignmentCount, isNull);
    state = state.withPage(_page([], offset: 4));
    expect(state.assignmentCount, 6);
    expect(state.exactAssignmentCount, 6);
    expect(state.loadingFirst().exactAssignmentCount, isNull);
  });

  for (final count in [null, -1, 'invalid']) {
    test('unknown member count $count prevents a complete total', () {
      final state = const AssignedGroupMembersState().withPage(
        _page([_member(1, count: count)]),
      );
      expect(state.assignmentCount, 2);
      expect(state.exactAssignmentCount, isNull);
    });

    test('unknown direct count $count prevents a complete total', () {
      final state = const AssignedGroupMembersState().withPage(
        _page([_member(1)], direct: count),
      );
      expect(state.groupAssignmentCount, isNull);
      expect(state.assignmentCount, 1);
      expect(state.exactAssignmentCount, isNull);
    });
  }

  test('a later direct snapshot recovers an unknown direct count', () {
    final state = const AssignedGroupMembersState()
        .withPage(_page([_member(1), _member(2)], direct: null))
        .withPage(_page([], offset: 2, direct: 3));
    expect(state.exactAssignmentCount, 5);
  });

  test('dropped member rows stay incomplete until replacement refresh', () {
    final first = _page([
      _member(1),
      {'id': 'broken', 'username': 'lost'},
    ]);
    expect(first.hasMore, isTrue);
    var state = const AssignedGroupMembersState()
        .withPage(first)
        .loadingNextPage()
        .withError('Try again', page: true);
    expect(state.exactAssignmentCount, isNull);
    state = state.withPage(_page([_member(3)], offset: 2));
    expect(state.hasMore, isFalse);
    expect(state.assignmentCount, 4);
    expect(state.exactAssignmentCount, isNull);
    state = state.loadingFirst().withPage(_page([], direct: 0));
    expect(state.members, isEmpty);
    expect(state.exactAssignmentCount, 0);
  });

  for (final members in [null, 'broken', <String, Object?>{}]) {
    test('invalid members container $members is not a known empty group', () {
      final page = AssignedGroupMembersPage.fromJson(
        {
          'members': members,
          'assignment_count': 2,
          'group_assignment_count': 2,
        },
        'https://meta.example.com',
        offset: 0,
        limit: 50,
      );
      final state = const AssignedGroupMembersState().withPage(page);
      expect(state.exactAssignmentCount, isNull);
    });
  }

  test('filtered results never expose their subtotal as Everyone total', () {
    final state = const AssignedGroupMembersState().withPage(
      _page([_member(1)]),
      filtered: true,
    );
    expect(state.assignmentCount, 3);
    expect(state.exactAssignmentCount, isNull);
    expect(state.loadingFirst().filtered, isTrue);
    expect(state.loadingNextPage().filtered, isTrue);
    expect(state.withError('Try again').exactAssignmentCount, isNull);
    expect(state.withPage(_page([_member(2)])).exactAssignmentCount, 3);
  });
}

Map<String, Object?> _member(int id, {Object? count = 1}) => {
  'id': id,
  'username': 'member$id',
  'assignments_count': count,
};

AssignedGroupMembersPage _page(
  List<Object?> members, {
  int offset = 0,
  Object? direct = 2,
}) => AssignedGroupMembersPage.fromJson(
  {
    'members': members,
    'assignment_count': members.fold<int>(
      direct is int && direct >= 0 ? direct : 0,
      (total, member) =>
          total +
          (member is Map &&
                  member['assignments_count'] is int &&
                  (member['assignments_count'] as int) >= 0
              ? member['assignments_count'] as int
              : 0),
    ),
    'group_assignment_count': direct,
  },
  'https://meta.example.com',
  offset: offset,
  limit: 2,
);
