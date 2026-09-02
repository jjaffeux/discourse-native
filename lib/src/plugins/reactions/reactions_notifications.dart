import '../../models/json.dart';
import '../../models/notification.dart';
import '../../plugin_api/notification_types.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../theme/d_icons.dart';

abstract final class ReactionsNotificationTypes {
  static const reaction = NotificationWireType(25, 'reaction');
}

const reactionsNotificationTypes = <PluginNotificationType>[
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('discourse-reactions'),
      name: 'reaction',
    ),
    wireType: ReactionsNotificationTypes.reaction,
    decode: _decodeReactionNotification,
  ),
];

ResolvedNotification? _decodeReactionNotification(
  DiscourseNotification notification,
) {
  if (notification.typeId.value != ReactionsNotificationTypes.reaction.wireId) {
    return null;
  }
  final data = notification.data;
  final consolidated = data['consolidated'] == true;
  final count = jsonInt(data['count']);
  final actor = jsonText(
    data['display_username'] ?? data['username'] ?? data['original_username'],
  );
  final payloadTitle = data['topic_title'];
  final title = payloadTitle is String && payloadTitle.isNotEmpty
      ? payloadTitle
      : notification.title.isEmpty
      ? 'a topic'
      : notification.title;
  return ResolvedNotification(
    presentation: NotificationPresentation(
      icon: DIcons.discourseEmojis,
      actor: actor ?? 'Someone',
      phrase: consolidated
          ? count > 0
                ? 'reacted to $count of your posts'
                : 'reacted to your posts'
          : 'reacted to your post in $title',
    ),
    path: consolidated
        ? Uri(
            path: '/my/notifications/reactions-received',
            queryParameters: {
              'acting_username': ?jsonText(data['username']) ?? actor,
              'include_likes': 'true',
            },
          ).toString()
        : notificationTopicPath(notification),
  );
}
