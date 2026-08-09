import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const siteUrl = 'https://meta.example.com';

  group('assignment payload presence', () {
    test('absent fields mean the optional plugin is absent', () {
      expect(Assignments.fromTopicJson(const {'id': 42}, siteUrl), isNull);
      expect(Assignments.fromPostJson(const {'id': 7}, siteUrl), isNull);
    });

    test('an explicit target permission preserves false', () {
      final assignments = Assignments.fromTopicJson(const {
        'id': 42,
        'can_assign': false,
      }, siteUrl);

      expect(assignments, isNotNull);
      expect(assignments!.canAssign, isFalse);
      expect(assignments.hasAssignments, isFalse);
    });

    test('a public assignment can be visible without a permission field', () {
      final assignments = Assignments.fromTopicJson(const {
        'assigned_to_user': {
          'username': 'sam',
          'name': 'Sam',
          'avatar_template': '/user_avatar/meta/sam/{size}/1.png',
        },
      }, siteUrl);

      expect(assignments?.canAssign, isNull);
      expect(
        assignments?.direct?.assignee,
        const AssignmentUser(
          username: 'sam',
          name: 'Sam',
          avatarUrl: '$siteUrl/user_avatar/meta/sam/90/1.png',
        ),
      );
    });
  });

  test('topic payload reads direct and indirect user/group assignments', () {
    final assignments = Assignments.fromTopicJson(const {
      'id': 42,
      'can_assign': true,
      'assigned_to_group': {
        'name': 'triage',
        'flair_icon': 'users',
        'flair_color': 'FFFFFF',
        'flair_bg_color': '0055AA',
      },
      'assignment_note': 'Own the incident',
      'assignment_status': 'In Progress',
      'indirectly_assigned_to': {
        '71': {
          'assigned_to': {
            'username': 'lee',
            'name': 'Lee',
            'avatar_template': '//cdn.example.com/lee/{size}.png',
          },
          'post_number': 3,
          'assignment_note': 'Check logs',
          'assignment_status': 'New',
        },
        '72': {
          'assigned_to': {'name': 'security'},
          'post_number': 4,
        },
        'bad-key': {
          'assigned_to': {'username': 'ignored'},
        },
        '73': {
          'assigned_to': {'id': 9},
        },
      },
    }, siteUrl)!;

    expect(assignments.canAssign, isTrue);
    expect(
      assignments.direct,
      const Assignment(
        assignee: AssignmentGroup(
          name: 'triage',
          flairIcon: 'users',
          flairColor: 'FFFFFF',
          flairBackgroundColor: '0055AA',
        ),
        note: 'Own the incident',
        status: 'In Progress',
      ),
    );
    expect(assignments.postAssignments.keys, [71, 72]);
    expect(
      assignments.forPost(71),
      const Assignment(
        assignee: AssignmentUser(
          username: 'lee',
          name: 'Lee',
          avatarUrl: 'https://cdn.example.com/lee/90.png',
        ),
        note: 'Check logs',
        status: 'New',
        postId: 71,
        postNumber: 3,
      ),
    );
    expect(
      assignments.forPost(72),
      const Assignment(
        assignee: AssignmentGroup(name: 'security'),
        postId: 72,
        postNumber: 4,
      ),
    );
  });

  test('post payload reads its own assignment and target metadata', () {
    final assignments = Assignments.fromPostJson(const {
      'id': 71,
      'post_number': 3,
      'can_assign': false,
      'assigned_to_user': {
        'id': 8,
        'username': 'sam',
        'name': 'Sam',
        'avatar_template': 'avatars/sam/{size}.png',
      },
      'assignment_note': 'Follow up',
      'assignment_status': 'Done',
    }, siteUrl)!;

    expect(assignments.canAssign, isFalse);
    expect(
      assignments.direct,
      const Assignment(
        assignee: AssignmentUser(
          id: 8,
          username: 'sam',
          name: 'Sam',
          avatarUrl: '$siteUrl/avatars/sam/90.png',
        ),
        note: 'Follow up',
        status: 'Done',
        postId: 71,
        postNumber: 3,
      ),
    );
  });

  test('suggestions discard malformed users and de-duplicate group names', () {
    final suggestions = AssignmentSuggestions.fromJson(const {
      'suggestions': [
        {'id': 1, 'username': 'sam', 'avatar_template': '/sam/{size}.png'},
        {'id': 2},
        'not-an-object',
      ],
      'assign_allowed_on_groups': ['staff', 'Staff', '', 2, 'support'],
      'assign_allowed_for_groups': ['triage', 'Triage'],
    }, siteUrl);

    expect(suggestions.users, const [
      AssignmentUser(id: 1, username: 'sam', avatarUrl: '$siteUrl/sam/90.png'),
    ]);
    expect(suggestions.assignAllowedOnGroups, ['staff', 'support']);
    expect(suggestions.assignAllowedForGroups, ['triage']);
    expect(suggestions.initialAssignees, [
      suggestions.users.single,
      const AssignmentGroup(name: 'triage'),
    ]);
  });
}
