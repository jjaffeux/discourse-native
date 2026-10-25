import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_plugin.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://forum.example';

void main() {
  final registry = PluginRegistry.validated(const [ReactionsPlugin()]);

  test('reactions on one post open that post, whatever their count', () {
    final resolved = registry.resolveNotification(
      _siteUrl,
      DiscourseNotification.fromJson(const {
        'id': 6,
        'notification_type': 25,
        'topic_id': 7,
        'post_number': 12,
        'slug': 'better-image-handling',
        'data': {
          'topic_title': 'Better image handling',
          'display_username': 'sam',
          'username2': 'alex',
          'count': 2,
        },
      }),
    );

    expect(resolved.presentation.actor, 'sam');
    expect(
      resolved.presentation.phrase,
      'reacted to your post in Better image handling',
    );
    expect(resolved.presentation.icon, DIcons.discourseEmojis);
    expect(resolved.path, '/t/better-image-handling/7/12');
  });

  test('consolidated reactions count posts and filter by the actor', () {
    final resolved = registry.resolveNotification(
      _siteUrl,
      DiscourseNotification.fromJson(const {
        'id': 5,
        'notification_type': 25,
        'topic_id': null,
        'post_number': null,
        'data': {
          'topic_title': 'The last topic reacted to',
          'display_username': 'Sam',
          'username': 'sam&alex',
          'consolidated': true,
          'count': 3,
        },
      }),
    );

    expect(resolved.presentation.actor, 'Sam');
    expect(resolved.presentation.phrase, 'reacted to 3 of your posts');
    final uri = Uri.parse(resolved.path!);
    expect(uri.path, '/my/notifications/reactions-received');
    expect(uri.queryParameters, {
      'acting_username': 'sam&alex',
      'include_likes': 'true',
    });
  });
}
