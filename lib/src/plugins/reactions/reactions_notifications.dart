import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

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
    coreMenuSection: CoreNotificationMenuSection.likes,
  ),
];

ResolvedNotification? _decodeReactionNotification(
  String _,
  DiscourseNotification notification,
) {
  if (notification.typeId.value != ReactionsNotificationTypes.reaction.wireId) {
    return null;
  }
  final data = notification.data;
  final consolidated = data['consolidated'] == true;
  final count = jsonInt(data['count']);
  final reactor = jsonText(
    data['display_username'] ?? data['username'] ?? data['original_username'],
  );
  // A post several people reacted to keeps one row: `count` reactors, the
  // newest as the actor and the one before as `username2`. A by-user
  // consolidated row counts posts instead and carries no `username2`.
  final secondReactor = jsonText(data['username2']);
  final actor = switch (reactor) {
    final name? when secondReactor != null && count == 2 =>
      appL10n.likedByTwoUsers(name, secondReactor),
    final name? when secondReactor != null && count > 2 =>
      appL10n.likedByMultipleUsers(count - 1, name),
    _ => reactor,
  };
  final payloadTitle = data['topic_title'];
  final title = payloadTitle is String && payloadTitle.isNotEmpty
      ? payloadTitle
      : notification.title.isEmpty
      ? appL10n.aTopic
      : notification.title;
  return ResolvedNotification(
    presentation: NotificationPresentation(
      icon: DIcons.discourseEmojis,
      actor: actor ?? appL10n.someone,
      phrase: consolidated
          ? count > 0
                ? appL10n.reactedToOfYourPosts((count).toString())
                : appL10n.reactedToYourPosts
          : appL10n.reactedToYourPostIn((title).toString()),
    ),
    path: consolidated
        ? Uri(
            path: '/my/notifications/reactions-received',
            queryParameters: {
              'acting_username': ?jsonText(data['username']) ?? reactor,
              'include_likes': 'true',
            },
          ).toString()
        : notificationTopicPath(notification),
  );
}
