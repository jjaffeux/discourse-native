import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

const registry = PluginRegistry([ChatPlugin()]);

DiscourseNotification chatNotification(
  int type, {
  int? topicId,
  int? postNumber,
  String slug = '',
  Map<String, dynamic> data = const {},
}) => DiscourseNotification.fromJson({
  'id': 1,
  'notification_type': type,
  'topic_id': topicId,
  'post_number': postNumber,
  'slug': slug,
  'data': data,
});

void main() {
  test('Chat owns its wording, actor aliases and icon', () {
    final resolved = registry.resolveNotification(
      chatNotification(
        29,
        data: const {
          'mentioned_by_username': 'sam',
          'chat_channel_title': 'dev',
          'chat_channel_id': 9,
          'chat_message_id': 44,
        },
      ),
    );

    expect(resolved.presentation.actor, 'sam');
    expect(resolved.presentation.phrase, 'mentioned you in dev');
    expect(resolved.presentation.icon, DIcons.comment);
    expect(resolved.path, '/chat/c/-/9/44');
  });

  test('Chat owns thread and quote destinations', () {
    const data = {
      'chat_channel_id': 9,
      'chat_thread_id': 3,
      'chat_message_id': 44,
    };

    expect(
      registry.resolveNotification(chatNotification(29, data: data)).path,
      '/chat/c/-/9/t/3',
    );
    expect(
      registry.resolveNotification(chatNotification(40, data: data)).path,
      '/chat/c/-/9/t/3/44',
    );
    expect(
      registry
          .resolveNotification(
            chatNotification(
              33,
              topicId: 12,
              slug: 'chat-transcript',
              postNumber: 4,
              data: data,
            ),
          )
          .path,
      '/t/chat-transcript/12/4',
    );
  });

  test('malformed Chat route data stays visible without an unsafe path', () {
    final resolved = registry.resolveNotification(
      chatNotification(
        31,
        data: const {
          'invited_by_username': 'david',
          'chat_channel_title': 'team',
          'chat_channel_id': -1,
        },
      ),
    );

    expect(resolved.presentation.actor, 'david');
    expect(resolved.presentation.phrase, 'invited you to team');
    expect(resolved.path, isNull);
  });
}
