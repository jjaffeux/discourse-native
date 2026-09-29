import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'chat_services.dart';

PluginNotificationFeedSource get chatNotificationFeed =>
    PluginNotificationFeedSource(
      id: const PluginNotificationFeedId(
        owner: PluginId('chat'),
        name: 'notifications',
      ),
      filterByTypes: const [
        NotificationTypeName('chat_invitation'),
        NotificationTypeName('chat_mention'),
        NotificationTypeName('chat_message'),
        NotificationTypeName('chat_quoted'),
        NotificationTypeName('chat_watched_thread'),
      ],
      reconnectMessage: appL10n.reconnectToThisForumToSeeChatNotifications,
      failureMessage: appL10n.couldnTLoadChatNotificationsFromThisForum,
      emptyMessage: appL10n.youDonTHaveAnyChatNotificationsYet,
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
