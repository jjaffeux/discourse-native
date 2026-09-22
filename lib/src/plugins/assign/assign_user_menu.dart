import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/widgets.dart';

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
