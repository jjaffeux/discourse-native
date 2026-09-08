import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/assign/assign_group_data.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const siteUrl = 'https://forum.example';
  final extensions = PluginRegistry.validated(const [AssignPlugin()]);

  for (final kind in ['members', 'requesters']) {
    for (final scenario in [
      (
        name: 'empty rows with a stale total',
        rows: <Map<String, Object?>>[],
        limit: 30,
      ),
      (
        name: 'a zero page limit',
        rows: [
          {'id': 1, 'username': 'sam'},
        ],
        limit: 0,
      ),
      (
        name: 'a negative page limit',
        rows: [
          {'id': 1, 'username': 'sam'},
        ],
        limit: -1,
      ),
    ]) {
      test('$kind stop paging after ${scenario.name}', () {
        final payload = <String, dynamic>{
          'members': scenario.rows,
          'meta': {'offset': 30, 'limit': scenario.limit, 'total': 100},
        };
        final hasMore = kind == 'members'
            ? GroupMembersPage.fromWire(
                payload,
                siteUrl,
                groupName: 'support',
              ).hasMore
            : GroupRequestersPage.fromWire(payload, siteUrl).hasMore;
        expect(hasMore, isFalse);
      });
    }
  }

  test(
    'a full activity page without a timestamp cannot offer a continuation',
    () {
      final page = GroupActivityPage.fromWire({
        'posts': [
          for (var id = 1; id <= 20; id++) {'id': id, 'topic_id': id},
        ],
      }, siteUrl);
      expect(page.posts, hasLength(20));
      expect(page.hasMore, isFalse);
    },
  );

  for (final scenario in [
    (name: 'a null slot', row: null, slots: 20),
    (name: 'a non-object slot', row: 'malformed', slots: 20),
    (name: 'an object beyond the raw cap', row: null, slots: 21),
  ]) {
    test('activity preserves its raw page boundary with ${scenario.name}', () {
      final page = GroupActivityPage.fromWire({
        'posts': [
          for (var id = 1; id <= scenario.slots; id++)
            if (id == 10)
              scenario.row
            else
              {
                'id': id,
                'topic_id': id,
                'created_at': DateTime.utc(
                  2026,
                  9,
                  1,
                  12,
                  0,
                  20 - id,
                ).toIso8601String(),
              },
        ],
      }, siteUrl);

      expect(page.rawPostCount, 20);
      expect(page.posts, hasLength(19));
      expect(page.posts.map((post) => post.id), [
        for (var id = 1; id <= 20; id++)
          if (id != 10) id,
      ]);
      expect(page.before, DateTime.utc(2026, 9, 1, 12));
      expect(page.hasMore, isTrue);
    });
  }

  test('activity cannot use a timestamp beyond the raw page cap', () {
    final page = GroupActivityPage.fromWire({
      'posts': [
        ...List<Object?>.filled(20, null),
        const {'id': 21, 'topic_id': 21, 'created_at': '2026-09-01T12:00:00Z'},
      ],
    }, siteUrl);

    expect(page.rawPostCount, 20);
    expect(page.posts, isEmpty);
    expect(page.before, isNull);
    expect(page.hasMore, isFalse);
  });

  for (final timestamp in [null, 'invalid']) {
    test('mixed activity stops when its final timestamp is $timestamp', () {
      final page = GroupActivityPage.fromWire({
        'posts': [
          for (var id = 1; id <= 20; id++)
            if (id == 10)
              null
            else
              {
                'id': id,
                'topic_id': id,
                'created_at': id == 20 ? timestamp : '2026-09-01T12:00:00Z',
              },
        ],
      }, siteUrl);

      expect(page.rawPostCount, 20);
      expect(page.posts, hasLength(19));
      expect(page.before, isNull);
      expect(page.hasMore, isFalse);
    });
  }

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

  test('activity decodes posts, categories, and its absent continuation', () {
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

    expect(activity.posts.single.topicTitle, 'An & B');
    expect(activity.posts.single.plainExcerpt, 'Hello world');
    expect(activity.categories.single.id, 4);
    expect(activity.hasMore, isFalse);
  });

  test('requesters decode their membership reason', () {
    final requesters = GroupRequestersPage.fromWire(const {
      'members': [
        {'id': 31, 'username': 'new-user', 'reason': 'I can help'},
      ],
      'meta': {'total': 1, 'limit': 50, 'offset': 0},
    }, siteUrl);

    expect(requesters.requesters.single.reason, 'I can help');
  });

  test('permissions decode the category access level', () {
    final permission = GroupPermission.fromWire(const {
      'permission_type': 2,
      'category': {'id': 4, 'name': 'Help', 'color': '0088CC'},
    });

    expect(permission.type, GroupPermissionType.createPost);
  });

  test('logs retain the actor and incomplete-page marker', () {
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

    expect(logs.logs.single.actingUser?.username, 'admin');
    expect(logs.allLoaded, isFalse);
  });
}
