import '../../models/json.dart';
import '../../plugin_api/notification_feed_host.dart';
import '../../plugin_api/notification_types.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../theme/d_icons.dart';
import 'assign_icons.dart';

abstract final class AssignNotificationTypes {
  static const assigned = NotificationWireType(34, 'assigned');
}

const assignNotificationFeed = PluginNotificationFeedSource(
  id: PluginNotificationFeedId(
    owner: PluginId('discourse-assign'),
    name: 'assign-list',
  ),
  filterByTypes: [NotificationTypeName('assigned')],
  reconnectMessage: 'Reconnect to this forum to see assignment notifications.',
  failureMessage: "Couldn't load assignment notifications from this forum.",
  emptyMessage: 'You don’t have any assignments yet.',
  compare: _compareAssignNotifications,
  dismissal: PluginNotificationFeedDismissal(
    notificationTypes: [AssignNotificationTypes.assigned],
    buttonLabel: 'Dismiss',
    buttonTooltip: 'Mark all unread assign notifications as read',
    confirmationMessage: _assignDismissConfirmation,
  ),
);

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
  // Core renders `fancy_title`, which can contain the viewer's localized
  // topic title. Older/custom serializers may expose only the Assign payload,
  // so keep that as the compatibility fallback.
  final title = notification.title.isNotEmpty
      ? notification.title
      : payloadTitle is String && payloadTitle.isNotEmpty
      ? payloadTitle
      : 'a topic';
  final isGroup =
      data['message'] == 'discourse_assign.assign_group_notification';
  final postNumber = notification.postNumber;
  final description = postNumber != null && postNumber > 1
      ? '$title (#$postNumber)'
      : title;
  return ResolvedNotification(
    presentation: NotificationPresentation(
      icon: isGroup ? AssignIcons.groupPlus : DIcons.userPlus,
      actor: isGroup ? jsonText(data['display_username']) ?? 'a group' : null,
      phrase: description,
    ),
    path: notificationTopicPath(notification),
  );
}

int _compareAssignNotifications(
  DiscourseNotification left,
  DiscourseNotification right,
) {
  if (left.isUnread != right.isUnread) return left.isUnread ? -1 : 1;

  final bumped = _compareDescending(
    jsonDate(left.wire['topic_bumped_at']),
    jsonDate(right.wire['topic_bumped_at']),
  );
  if (bumped != 0) return bumped;

  return _compareDescending(left.createdAt, right.createdAt);
}

String _assignDismissConfirmation(int unreadCount) {
  final notifications = unreadCount == 1 ? 'notification' : 'notifications';
  return 'Are you sure? You have $unreadCount unread assign $notifications.';
}

int _compareDescending(DateTime? left, DateTime? right) {
  if (left == null) return right == null ? 0 : 1;
  if (right == null) return -1;
  return right.compareTo(left);
}
