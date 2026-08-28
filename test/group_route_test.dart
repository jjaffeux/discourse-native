import 'dart:convert';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroupRoute', () {
    test('parses the directory and every built-in route shape', () {
      expect(
        GroupRoute.parse('https://forum.example/g'),
        const GroupRoute.directory(),
      );
      expect(GroupRoute.parse('/g/team'), GroupRoute.detail('team'));
      expect(GroupRoute.parse('/g/team/members'), GroupRoute.detail('team'));
      expect(
        GroupRoute.parse('/g/team/activity/topics'),
        GroupRoute.detail(
          'team',
          section: GroupRoute.activity,
          subsection: GroupRoute.topics,
        ),
      );
      expect(
        GroupRoute.parse('/g/team/messages/archive'),
        GroupRoute.detail(
          'team',
          section: GroupRoute.messages,
          subsection: GroupRoute.archive,
        ),
      );
      expect(
        GroupRoute.parse('/g/team/manage/categories'),
        GroupRoute.detail(
          'team',
          section: GroupRoute.manage,
          subsection: GroupRoute.categories,
        ),
      );
    });

    test('leaves plugin and unsupported routes unclaimed', () {
      expect(GroupRoute.parse('/g/team/assigned/everyone'), isNull);
      expect(GroupRoute.parse('/g/custom/new'), isNull);
      expect(GroupRoute.parse('/g/team/members/extra'), isNull);
      expect(GroupRoute.parse('/g/team/activity/unknown'), isNull);
      expect(GroupRoute.parse('/groups/team'), isNull);
    });

    test('builds built-in topic feeds with encoded identities', () {
      final topics = GroupRoute.detail(
        'support team',
        section: GroupRoute.activity,
        subsection: GroupRoute.topics,
      );
      final archive = GroupRoute.detail(
        'support team',
        section: GroupRoute.messages,
        subsection: GroupRoute.archive,
      );

      expect(topics.topicFeedPath('sam'), '/topics/groups/support%20team.json');
      expect(
        archive.topicFeedPath('Sam Example'),
        '/topics/private-messages-group/Sam%20Example/'
        'support%20team/archive.json',
      );
    });

    test('round-trips core and plugin content routes', () {
      final routes = [
        ContentRoute.group(const GroupRoute.directory()),
        ContentRoute.group(
          GroupRoute.detail(
            'team',
            section: GroupRoute.activity,
            subsection: GroupRoute.topics,
          ),
          feedPath: '/topics/groups/team.json',
        ),
        ContentRoute.group(
          GroupRoute.plugin(
            groupName: 'team',
            owner: 'discourse-assign',
            section: 'assigned',
            subsection: 'everyone',
          ),
        ),
      ];

      for (final route in routes) {
        final restored = ContentRoute.fromJson(
          jsonDecode(jsonEncode(route.toJson())) as Map<String, dynamic>,
        );
        expect(restored.groupRoute, route.groupRoute);
        expect(restored.feedPath, route.feedPath);
        expect(restored.id, route.id);
      }
    });
  });
}
