import 'dart:convert';

import 'package:discourse_native/src/data/site_message_bus_bootstrap.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SiteMessageBusBootstrap', () {
    test('decodes core snapshots and every supplied channel position', () {
      final document = _document({
        'currentUser': jsonEncode({
          'id': 42,
          'username': 'sam',
          'notification_channel_position': 901,
          'all_unread_notifications_count': 5,
          'new_personal_messages_notifications_count': 2,
          'do_not_disturb_channel_position': 902,
          'status': {
            'description': 'Heads down',
            'emoji': 'hammer_and_wrench',
            'message_bus_last_id': 903,
          },
        }),
        'topicTrackingStates': jsonEncode([
          {
            'topic_id': 7,
            'highest_post_number': 3,
            'last_read_post_number': 1,
            'notification_level': 2,
          },
        ]),
        'topicTrackingStateMeta': jsonEncode({
          'message_bus_last_ids': {
            '/latest': 904,
            '/new': 905,
            '/unread': 906,
            '/unread/42': 907,
            '/delete': 908,
            '/recover': 909,
            '/destroy': 910,
            'not-a-channel': 999,
            '/invalid': -1,
          },
        }),
      });

      final bootstrap = SiteMessageBusBootstrap.fromHtml(
        document,
        siteUrl: 'https://example.com',
        models: const DiscourseModelCodec.core(),
      );

      expect(bootstrap?.currentUser?.id, 42);
      expect(bootstrap?.notificationChannelPosition, 901);
      expect(bootstrap?.hasCompleteTopicTrackingSnapshot(42), isTrue);
      expect(bootstrap?.topicTrackingState?.newActivityCounts, (
        newTopics: 0,
        newReplies: 1,
      ));
      expect(bootstrap?.initialLastIds(userId: 42), {
        '/latest': 904,
        '/new': 905,
        '/unread': 906,
        '/unread/42': 907,
        '/delete': 908,
        '/recover': 909,
        '/destroy': 910,
        '/notification/42': 901,
        '/user-status': 903,
        '/do-not-disturb/42': 902,
      });
      expect(bootstrap?.currentUserState?['all_unread_notifications_count'], 5);
    });

    test('keeps independent tracking data when current user is malformed', () {
      final document = _document({
        'currentUser': jsonEncode({'id': 42}),
        'topicTrackingStates': jsonEncode([
          {'topic_id': 7, 'highest_post_number': 1},
        ]),
        'topicTrackingStateMeta': jsonEncode({
          'message_bus_last_ids': {'/latest': 15},
        }),
      });

      final bootstrap = SiteMessageBusBootstrap.fromHtml(
        document,
        siteUrl: 'https://example.com',
        models: const DiscourseModelCodec.core(),
      );

      expect(bootstrap?.currentUser, isNull);
      expect(bootstrap?.hasCompleteTopicTrackingSnapshot(42), isFalse);
      expect(bootstrap?.topicTrackingState?.topics.single.topicId, 7);
      expect(bootstrap?.topicTrackingLastIds, {'/latest': 15});
    });

    test('returns null when the core preload element is absent', () {
      final bootstrap = SiteMessageBusBootstrap.fromHtml(
        '<html><body></body></html>',
        siteUrl: 'https://example.com',
        models: const DiscourseModelCodec.core(),
      );

      expect(bootstrap, isNull);
    });
  });
}

String _document(Map<String, String> entries) =>
    '''
<!doctype html>
<html>
  <body>
    <script type="application/json" id="data-preloaded">
      ${jsonEncode(entries)}
    </script>
  </body>
</html>
''';
