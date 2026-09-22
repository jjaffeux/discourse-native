import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/widgets.dart';

import 'chat_services.dart';

const chatNotificationFeed = PluginNotificationFeedSource(
  id: PluginNotificationFeedId(owner: PluginId('chat'), name: 'notifications'),
  filterByTypes: [
    NotificationTypeName('chat_invitation'),
    NotificationTypeName('chat_mention'),
    NotificationTypeName('chat_message'),
    NotificationTypeName('chat_quoted'),
    NotificationTypeName('chat_watched_thread'),
  ],
  reconnectMessage: 'Reconnect to this forum to see chat notifications.',
  failureMessage: "Couldn't load chat notifications from this forum.",
  emptyMessage: 'You don’t have any chat notifications yet.',
);

class ChatUserMenuNotifications extends StatelessWidget {
  const ChatUserMenuNotifications({
    super.key,
    required this.siteUrl,
    required this.onOpened,
  });

  final String siteUrl;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) => PluginNotificationsSection(
    siteUrl: siteUrl,
    onOpened: onOpened,
    host: PluginUiScope.require(context, chatNotificationHostService),
    source: chatNotificationFeed,
  );
}
