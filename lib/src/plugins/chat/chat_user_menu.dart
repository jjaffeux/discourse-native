import 'package:flutter/widgets.dart';

import '../../models/notification.dart';
import '../../plugin_api/notification_feed_host.dart';
import '../../shell/notification_list.dart';
import '../plugin_manifest.dart';
import '../plugin_scope.dart';
import '../plugin_services.dart';

const chatNotificationFeed = PluginNotificationFeedSource(
  id: PluginNotificationFeedId(owner: PluginId('chat'), name: 'notifications'),
  filterByTypes: [
    NotificationKind.chatInvitation,
    NotificationKind.chatMention,
    NotificationKind.chatMessage,
    NotificationKind.chatQuoted,
    NotificationKind.chatWatchedThread,
  ],
  reconnectMessage: 'Reconnect to this forum to see chat notifications.',
  failureMessage: "Couldn't load chat notifications from this forum.",
  emptyMessage: 'You don’t have any chat notifications yet.',
);

/// Chat-owned projection of its filtered notification feed.
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
    host: PluginScope.require(context, chatNotificationHostService),
    source: chatNotificationFeed,
  );
}
