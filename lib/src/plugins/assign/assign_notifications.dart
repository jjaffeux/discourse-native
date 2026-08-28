import '../../models/json.dart';
import '../../models/notification.dart';
import '../../plugin_api/notification_types.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../theme/d_icons.dart';

abstract final class AssignNotificationTypes {
  static const assigned = NotificationWireType(34, 'assigned');
}

const assignNotificationTypes = <PluginNotificationType>[
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('discourse-assign'),
      name: 'assigned',
    ),
    wireType: AssignNotificationTypes.assigned,
    decode: _decodeAssignedNotification,
  ),
];

ResolvedNotification? _decodeAssignedNotification(
  DiscourseNotification notification,
) {
  if (notification.typeId.value != AssignNotificationTypes.assigned.wireId) {
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
      icon: DIcons.userPlus,
      actor:
          jsonText(
            data['display_username'] ??
                data['username'] ??
                data['original_username'],
          ) ??
          'Someone',
      phrase: 'assigned $title to you',
    ),
    path: notificationTopicPath(notification),
  );
}
