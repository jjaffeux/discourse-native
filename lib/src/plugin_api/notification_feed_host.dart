import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/foundation.dart';

import '../models/notification.dart';
import '../models/notification_feed.dart';

export '../models/notification.dart'
    show
        DiscourseNotification,
        NotificationTypeId,
        NotificationTypeName,
        NotificationWireType;
export '../models/notification_feed.dart' show NotificationFeed;

typedef PluginNotificationComparator =
    int Function(DiscourseNotification left, DiscourseNotification right);

typedef PluginNotificationDismissConfirmation =
    String Function(int unreadCount);

@immutable
final class PluginNotificationFeedLink {
  const PluginNotificationFeedLink({required this.label, required this.path})
    : assert(label != ''),
      assert(path != '');

  final String label;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is PluginNotificationFeedLink &&
      other.label == label &&
      other.path == path;

  @override
  int get hashCode => Object.hash(label, path);
}

/// Opts a plugin notification feed into the server's typed bulk-dismissal
/// contract. The feed's declared [PluginNotificationFeedSource.filterByTypes]
/// are the only notification types sent to the server.
@immutable
final class PluginNotificationFeedDismissal {
  const PluginNotificationFeedDismissal({
    required this.notificationTypes,
    required this.buttonLabel,
    required this.buttonTooltip,
    required this.confirmationMessage,
  });

  final List<NotificationWireType> notificationTypes;
  final String buttonLabel;
  final String buttonTooltip;
  final PluginNotificationDismissConfirmation confirmationMessage;

  @override
  bool operator ==(Object other) =>
      other is PluginNotificationFeedDismissal &&
      listEquals(other.notificationTypes, notificationTypes) &&
      other.buttonLabel == buttonLabel &&
      other.buttonTooltip == buttonTooltip &&
      other.confirmationMessage == confirmationMessage;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(notificationTypes),
    buttonLabel,
    buttonTooltip,
    confirmationMessage,
  );
}

@immutable
final class PluginNotificationFeedId {
  const PluginNotificationFeedId({required this.owner, required this.name});

  final PluginId owner;
  final String name;
  String get id => '${owner.value}/$name';

  @override
  bool operator ==(Object other) =>
      other is PluginNotificationFeedId &&
      other.owner == owner &&
      other.name == name;

  @override
  int get hashCode => Object.hash(owner, name);
}

@immutable
final class PluginNotificationFeedSource {
  const PluginNotificationFeedSource({
    required this.id,
    required this.filterByTypes,
    required this.reconnectMessage,
    required this.failureMessage,
    required this.emptyMessage,
    this.compare,
    this.dismissal,
  });

  final PluginNotificationFeedId id;
  final List<NotificationTypeName> filterByTypes;
  final String reconnectMessage;
  final String failureMessage;
  final String emptyMessage;
  final PluginNotificationComparator? compare;
  final PluginNotificationFeedDismissal? dismissal;

  List<DiscourseNotification> arrange(
    List<DiscourseNotification> notifications,
  ) {
    final compare = this.compare;
    if (compare == null || notifications.length < 2) return notifications;
    final arranged = List<DiscourseNotification>.of(notifications)
      ..sort(compare);
    return List.unmodifiable(arranged);
  }

  @override
  bool operator ==(Object other) =>
      other is PluginNotificationFeedSource &&
      other.id == id &&
      listEquals(other.filterByTypes, filterByTypes) &&
      other.reconnectMessage == reconnectMessage &&
      other.failureMessage == failureMessage &&
      other.emptyMessage == emptyMessage &&
      other.compare == compare &&
      other.dismissal == dismissal;

  @override
  int get hashCode => Object.hash(
    id,
    Object.hashAll(filterByTypes),
    reconnectMessage,
    failureMessage,
    emptyMessage,
    compare,
    dismissal,
  );
}

/// Session bindings scope feed ids and sources to the consuming plugin's
/// namespace. Navigation and marking a row read remain feed-neutral actions.
abstract interface class PluginNotificationFeedHost {
  Listenable notificationFeedListenable(PluginNotificationFeedId id);
  NotificationFeed notificationFeedFor(
    PluginNotificationFeedId id,
    String siteUrl,
  );
  Future<void> loadPluginNotificationFeed(
    String siteUrl,
    PluginNotificationFeedSource source,
  );
  Future<void> dismissPluginNotifications(
    String siteUrl,
    PluginNotificationFeedSource source,
  );
  void readPluginNotification(
    String siteUrl,
    DiscourseNotification notification,
  );
  String pluginAbsoluteUrl(String path, {required String siteUrl});
  Future<bool> openPluginNotificationUrl(String url);
}
