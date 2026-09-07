import '../../models/notification.dart';
import '../../plugin_api/notification_types.dart';
import '../../plugin_api/plugin_icon_catalog.dart';
import '../../theme/d_icon.dart';
import 'event_data.dart';

abstract final class EventIcons {
  static const calendar = DIconData(
    'events-calendar',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M7 2v6M17 2v6M3 11h18M7 15h3M14 15h3M7 18h3"/></svg>',
  );
}

const eventIconCatalog = PluginIconCatalog(
  owner: eventsPluginId,
  entries: {'events-calendar': EventIcons.calendar},
);
const eventNotificationTypes = [
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: eventsPluginId, name: 'reminder'),
    wireType: NotificationWireType(27, 'event_reminder'),
    decode: _reminder,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: eventsPluginId, name: 'invitation'),
    wireType: NotificationWireType(28, 'event_invitation'),
    decode: _invitation,
  ),
];

String _title(DiscourseNotification row) =>
    eventText(row.data['event_name']) ??
    eventText(row.data['topic_title']) ??
    'an event';

ResolvedNotification? _reminder(DiscourseNotification row) {
  if (row.typeId.value != 27) return null;
  final title = _title(row);
  final phrase = switch (row.data['message']) {
    'discourse_post_event.notifications.before_event_reminder' =>
      '$title is starting soon',
    'discourse_post_event.notifications.ongoing_event_reminder' =>
      '$title is happening now',
    'discourse_post_event.notifications.after_event_reminder' =>
      '$title has ended',
    _ => 'Reminder for $title',
  };
  // display_username on a reminder may identify the recipient, not an actor.
  return ResolvedNotification(
    presentation: NotificationPresentation(
      icon: EventIcons.calendar,
      phrase: phrase,
    ),
    path: notificationTopicPath(row),
  );
}

ResolvedNotification? _invitation(DiscourseNotification row) {
  if (row.typeId.value != 28) return null;
  final actor = eventText(row.data['display_username']);
  final predefined =
      row.data['message'] ==
      'discourse_post_event.notifications.invite_user_predefined_attendance_notification';
  return ResolvedNotification(
    presentation: NotificationPresentation(
      icon: EventIcons.calendar,
      actor: actor,
      phrase: predefined
          ? actor == null
                ? 'Your attendance was set for ${_title(row)}'
                : 'set your attendance and invited you to ${_title(row)}'
          : actor == null
          ? 'Invitation to ${_title(row)}'
          : 'invited you to ${_title(row)}',
    ),
    path: notificationTopicPath(row),
  );
}
