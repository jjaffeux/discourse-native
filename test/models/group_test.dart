import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/assign/assign_group_data.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const siteUrl = 'https://forum.example';
  final extensions = PluginRegistry.validated(const [AssignPlugin()]);

  test('detail keeps capabilities, management settings, and plugin data', () {
    final detail = GroupDetail.fromWire(
      const {
        'group': {
          'id': 7,
          'name': 'support',
          'full_name': 'Customer Support',
          'user_count': 42,
          'bio_cooked': '<p>We <strong>help</strong>.</p>',
          'visibility_level': 2,
          'is_group_user': true,
          'is_group_owner': true,
          'can_see_members': true,
          'can_edit_group': true,
          'has_messages': true,
          'message_count': 9,
          'associated_group_ids': [1, -1, '2'],
          'watching_category_ids': [3],
          'watching_tags': [
            'urgent',
            {'id': 8, 'name': 'billing', 'slug': 'billing'},
          ],
          'smtp_enabled': true,
          'smtp_port': 587,
          'smtp_updated_at': '2026-08-28T12:00:00Z',
          'smtp_updated_by': {
            'id': 2,
            'username': 'admin',
            'avatar_template': '/user_avatar/forum.example/admin/{size}/1.png',
          },
          'assignable_level': 1,
          'can_show_assigned_tab': true,
          'assignment_count': 5,
        },
        'extras': {
          'visible_group_names': ['support', 'staff'],
        },
      },
      siteUrl,
      extensions: extensions,
    );

    final group = detail.group;
    expect(group.id, 7);
    expect(group.label, 'Customer Support');
    expect(group.plainBio, 'We help.');
    expect(group.userCount, 42);
    expect(group.isPrivate, isTrue);
    expect(group.canManage, isTrue);
    expect(
      group.canShowMessages(canSendPrivateMessages: true, isAdmin: false),
      isTrue,
    );
    expect(group.associatedGroupIds, [1, 2]);
    expect(group.watchingTags.map((tag) => tag.name), ['urgent', 'billing']);
    expect(group.smtpUpdatedBy?.avatarUrl, contains('/admin/90/1.png'));
    expect(detail.visibleGroupNames, ['support', 'staff']);

    final assign = group.plugins.get(assignGroupDataKey);
    expect(assign?.canShowAssignedTab, isTrue);
    expect(assign?.assignmentCount, 5);
  });

  test('directory exposes a safe continuation and withholds absent counts', () {
    final page = GroupDirectoryPage.fromWire(const {
      'groups': [
        {'id': 1, 'name': 'alpha'},
      ],
      'extras': {
        'type_filters': ['my', 'owner'],
      },
      'total_rows_groups': 81,
      'load_more_groups': '/groups?page=1&type=my',
    }, siteUrl);

    expect(page.groups.single.userCount, isNull);
    expect(page.typeFilters, ['my', 'owner']);
    expect(page.totalRows, 81);
    expect(page.nextPagePath, '/groups.json?page=1&type=my');

    final unsafe = GroupDirectoryPage.fromWire(const {
      'load_more_groups': 'https://attacker.example/groups?page=1',
    }, siteUrl);
    expect(unsafe.nextPagePath, isNull);
  });

  test(
    'members derive owner and primary status and retain paging metadata',
    () {
      final page = GroupMembersPage.fromWire(
        const {
          'members': [
            {
              'id': 11,
              'username': 'Sam',
              'name': 'Sam Example',
              'avatar_template': '/sam/{size}.png',
              'primary_group_name': 'Support',
              'last_posted_at': '2026-08-20T10:00:00Z',
            },
            {'id': 12, 'username': 'Lee'},
          ],
          'owners': [
            {'id': 11, 'username': 'Sam'},
          ],
          'meta': {'total': 55, 'limit': 25, 'offset': 25},
        },
        siteUrl,
        groupName: 'support',
      );

      expect(page.members.first.owner, isTrue);
      expect(page.members.first.primary, isTrue);
      expect(page.members.first.avatarUrl, 'https://forum.example/sam/90.png');
      expect(page.members.last.owner, isFalse);
      expect(page.hasMore, isTrue);
      expect(page.nextOffset, 50);
    },
  );

  test('activity, requester, permissions, and logs parse total defaults', () {
    final activity = GroupActivityPage.fromWire(const {
      'posts': [
        {
          'id': 20,
          'topic_id': 10,
          'post_number': 2,
          'topic_title': 'An & B',
          'topic_slug': 'an-b',
          'excerpt': '<p>Hello <b>world</b></p>',
          'created_at': '2026-08-28T08:00:00Z',
          'username': 'sam',
        },
      ],
      'categories': [
        {'id': 4, 'name': 'Help', 'color': '0088CC'},
      ],
    }, siteUrl);
    final requesters = GroupRequestersPage.fromWire(const {
      'members': [
        {'id': 31, 'username': 'new-user', 'reason': 'I can help'},
      ],
      'meta': {'total': 1, 'limit': 50, 'offset': 0},
    }, siteUrl);
    final permission = GroupPermission.fromWire(const {
      'permission_type': 2,
      'category': {'id': 4, 'name': 'Help', 'color': '0088CC'},
    });
    final logs = GroupLogsPage.fromWire(const {
      'logs': [
        {
          'action': 'add_user_to_group',
          'subject': 'new-user',
          'prev_value': 'outside',
          'new_value': 'member',
          'acting_user': {'id': 2, 'username': 'admin'},
        },
      ],
      'all_loaded': false,
    }, siteUrl);

    expect(activity.posts.single.topicTitle, 'An & B');
    expect(activity.posts.single.plainExcerpt, 'Hello world');
    expect(activity.categories.single.id, 4);
    expect(activity.hasMore, isFalse);
    expect(requesters.requesters.single.reason, 'I can help');
    expect(permission.type, GroupPermissionType.createPost);
    expect(logs.logs.single.actingUser?.username, 'admin');
    expect(logs.allLoaded, isFalse);
  });
}
