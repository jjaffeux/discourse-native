import 'package:flutter/widgets.dart';

import '../../plugin_api/notification_feed_host.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../shell/notification_list.dart';
import 'assign_notifications.dart';
import 'assign_services.dart';

class AssignUserMenuNotifications extends StatelessWidget {
  const AssignUserMenuNotifications({
    super.key,
    required this.siteUrl,
    required this.onOpened,
    required this.unreadCount,
    required this.viewAllPath,
  });

  final String siteUrl;
  final VoidCallback onOpened;
  final int unreadCount;
  final String viewAllPath;

  @override
  Widget build(BuildContext context) => PluginNotificationsSection(
    siteUrl: siteUrl,
    onOpened: onOpened,
    host: PluginUiScope.require(context, assignNotificationHostService),
    source: assignNotificationFeed,
    unreadCount: unreadCount,
    viewAll: PluginNotificationFeedLink(
      label: 'View all assigned',
      path: viewAllPath,
    ),
    emptyStateAction: const PluginNotificationFeedLink(
      label: 'Notification preferences',
      path: '/my/preferences/notifications',
    ),
  );
}
