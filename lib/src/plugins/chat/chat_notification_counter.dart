import '../../models/notification_totals.dart';
import '../../plugin_api/notification_counters.dart';
import 'chat_services.dart';

const chatNotificationCounter = PluginNotificationCounter(
  id: PluginNotificationCounterId(owner: chatPluginId, name: 'notifications'),
  wireName: 'chat_notifications',
);

PluginNotificationCounters chatNotificationCounters({
  int count = 0,
  bool available = true,
}) => PluginNotificationCounters.single(
  chatNotificationCounter,
  count: count,
  available: available,
);

NotificationTotals chatNotificationTotals({
  int unreadNotifications = 0,
  int unreadPersonalMessages = 0,
  int unseenReviewables = 0,
  int chatNotifications = 0,
  int topicTrackingUnread = 0,
  int topicTrackingNew = 0,
  String? username,
  bool available = true,
}) => NotificationTotals(
  unreadNotifications: unreadNotifications,
  unreadPersonalMessages: unreadPersonalMessages,
  unseenReviewables: unseenReviewables,
  topicTrackingUnread: topicTrackingUnread,
  topicTrackingNew: topicTrackingNew,
  username: username,
  pluginCounters: chatNotificationCounters(
    count: chatNotifications,
    available: available,
  ),
);

extension ChatNotificationTotals on NotificationTotals {
  bool get hasChatEnabled => hasPluginCounter(chatNotificationCounter.id);

  int get chatNotifications => pluginCounter(chatNotificationCounter.id);

  NotificationTotals withChatNotificationsDelta(int delta) =>
      updatePluginCounter(
        chatNotificationCounter,
        (current) => current + delta,
      );
}
