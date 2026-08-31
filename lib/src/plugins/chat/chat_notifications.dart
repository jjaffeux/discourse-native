import '../../models/json.dart';
import '../../models/notification.dart';
import '../../plugin_api/notification_types.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../theme/d_icons.dart';

abstract final class ChatNotificationTypes {
  static const mention = NotificationWireType(29, 'chat_mention');
  static const message = NotificationWireType(30, 'chat_message');
  static const invitation = NotificationWireType(31, 'chat_invitation');
  static const quoted = NotificationWireType(33, 'chat_quoted');
  static const watchedThread = NotificationWireType(40, 'chat_watched_thread');
}

const chatNotificationTypes = <PluginNotificationType>[
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: PluginId('chat'), name: 'mention'),
    wireType: ChatNotificationTypes.mention,
    decode: _decodeChatNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: PluginId('chat'), name: 'message'),
    wireType: ChatNotificationTypes.message,
    decode: _decodeChatNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: PluginId('chat'), name: 'invitation'),
    wireType: ChatNotificationTypes.invitation,
    decode: _decodeChatNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: PluginId('chat'), name: 'quoted'),
    wireType: ChatNotificationTypes.quoted,
    decode: _decodeChatNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('chat'),
      name: 'watched-thread',
    ),
    wireType: ChatNotificationTypes.watchedThread,
    decode: _decodeChatNotification,
  ),
];

ResolvedNotification? _decodeChatNotification(
  DiscourseNotification notification,
) {
  final type = notification.typeId.value;
  if (type != ChatNotificationTypes.mention.wireId &&
      type != ChatNotificationTypes.message.wireId &&
      type != ChatNotificationTypes.invitation.wireId &&
      type != ChatNotificationTypes.quoted.wireId &&
      type != ChatNotificationTypes.watchedThread.wireId) {
    return null;
  }

  final data = notification.data;
  final watched = type == ChatNotificationTypes.watchedThread.wireId;
  final actor = watched
      ? null
      : jsonText(
              data['display_username'] ??
                  data['mentioned_by_username'] ??
                  data['invited_by_username'] ??
                  data['username'] ??
                  data['original_username'],
            ) ??
            'Someone';
  final channel = jsonText(data['chat_channel_title']) ?? 'chat';

  return ResolvedNotification(
    presentation: NotificationPresentation(
      icon: switch (type) {
        29 || 30 => DIcons.comment,
        31 => DIcons.link,
        33 => DIcons.quoteRight,
        40 => DIcons.reply,
        _ => DIcons.bell,
      },
      actor: actor,
      phrase: switch (type) {
        29 => 'mentioned you in $channel',
        30 => 'sent a message in $channel',
        31 => 'invited you to $channel',
        33 => 'quoted your chat message',
        40 => 'There is a new reply in a thread you follow',
        _ => 'New chat notification',
      },
    ),
    path: type == ChatNotificationTypes.quoted.wireId
        ? notificationTopicPath(notification)
        : _chatPath(notification, omitThreadMessage: type == 29),
  );
}

String? _chatPath(
  DiscourseNotification notification, {
  required bool omitThreadMessage,
}) {
  final data = notification.data;
  final channelId = _positiveInt(data['chat_channel_id']);
  if (channelId == null) return null;

  final buffer = StringBuffer('/chat/c/-/$channelId');
  final threadId = _positiveInt(data['chat_thread_id']);
  if (threadId != null) {
    buffer.write('/t/$threadId');
    if (omitThreadMessage) return buffer.toString();
  }
  final messageId = _positiveInt(data['chat_message_id']);
  if (messageId != null) buffer.write('/$messageId');
  return buffer.toString();
}

int? _positiveInt(Object? value) {
  final parsed = jsonIntOrNull(value);
  return parsed != null && parsed > 0 ? parsed : null;
}
