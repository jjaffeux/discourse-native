import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_plugin.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Reactions owns notification decoding, route, wording and icon', () {
    const registry = PluginRegistry([ReactionsPlugin()]);
    final notification = DiscourseNotification.fromJson(const {
      'id': 1,
      'notification_type': 25,
      'topic_id': 12,
      'post_number': 4,
      'slug': 'emoji',
      'data': {'display_username': 'sam', 'topic_title': 'Emoji'},
    });

    final resolved = registry.resolveNotification(notification);

    expect(resolved.presentation.actor, 'sam');
    expect(resolved.presentation.phrase, 'reacted to your post in Emoji');
    expect(resolved.presentation.icon, DIcons.discourseEmojis);
    expect(resolved.path, '/t/emoji/12/4');
  });
}
