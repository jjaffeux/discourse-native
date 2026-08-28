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
  final payloadTitle = data['topic_title'];
  final title = payloadTitle is String && payloadTitle.isNotEmpty
      ? payloadTitle
      : notification.title.isEmpty
      ? 'a topic'
      : notification.title;
  return ResolvedNotification(
    presentation: NotificationPresentation(
      icon: DIcons.discourseEmojis,
      actor:
          jsonText(
            data['display_username'] ??
                data['username'] ??
                data['original_username'],
          ) ??
          'Someone',
      phrase: 'reacted to your post in $title',
    ),
    path: notificationTopicPath(notification),
  );
}
