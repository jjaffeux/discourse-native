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

  test('member paging de-duplicates rows and preserves first-page totals', () {
    final first = AssignedGroupMembersPage(
      members: const [
        AssignedGroupMember(id: 1, username: 'one', usernameLower: 'one'),
      ],
      assignmentCount: 12,
      groupAssignmentCount: 3,
      offset: 0,
      limit: 50,
      hasMore: true,
    );
    final second = AssignedGroupMembersPage(
      members: const [
        AssignedGroupMember(id: 1, username: 'one', usernameLower: 'one'),
        AssignedGroupMember(id: 2, username: 'two', usernameLower: 'two'),
      ],
      assignmentCount: 4,
      groupAssignmentCount: 1,
      offset: 50,
      limit: 50,
      hasMore: false,
    );

    final state = const AssignedGroupMembersState()
        .withPage(first)
        .withPage(second);

    expect(state.members.map((member) => member.id), [1, 2]);
    expect(state.assignmentCount, 12);
    expect(state.groupAssignmentCount, 3);
    expect(state.nextOffset, 100);
    expect(state.hasMore, isFalse);
  });
}
