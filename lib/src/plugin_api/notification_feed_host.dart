import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/foundation.dart';

import '../models/notification.dart';
import '../models/notification_feed.dart';

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
  });

  final PluginNotificationFeedId id;
  final List<NotificationTypeName> filterByTypes;
  final String reconnectMessage;
  final String failureMessage;
  final String emptyMessage;

  @override
  bool operator ==(Object other) =>
      other is PluginNotificationFeedSource &&
      other.id == id &&
      listEquals(other.filterByTypes, filterByTypes) &&
      other.reconnectMessage == reconnectMessage &&
      other.failureMessage == failureMessage &&
      other.emptyMessage == emptyMessage;

  @override
  int get hashCode => Object.hash(
    id,
    Object.hashAll(filterByTypes),
    reconnectMessage,
    failureMessage,
    emptyMessage,
  );
}

/// Notification-feed-only facade exposed to plugin-rendered menu sections.
///
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
  void readPluginNotification(
    String siteUrl,
    DiscourseNotification notification,
  );
  String pluginAbsoluteUrl(String path, {required String siteUrl});
  Future<bool> openPluginNotificationUrl(String url);
}
