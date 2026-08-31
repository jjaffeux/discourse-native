import 'package:flutter/foundation.dart';

import '../plugin_api/notification_counters.dart';
import 'json.dart';
import 'notification_type_counts.dart';

@immutable
class NotificationTotals {
  const NotificationTotals({
    this.unreadNotifications = 0,
    this.unreadPersonalMessages = 0,
    this.unseenReviewables = 0,
    this.topicTrackingUnread = 0,
    this.topicTrackingNew = 0,
    this.username,
    this.groupedUnreadNotifications = NotificationTypeCounts.unavailable,
    this.pluginCounters = PluginNotificationCounters.none,
  });

  factory NotificationTotals.fromJson(
    Map<String, dynamic> json, {
    PluginNotificationCounterCodec counterCodec =
        const EmptyPluginNotificationCounterCodec(),
  }) {
    final tracking = jsonObject(json['topic_tracking']);
    return NotificationTotals(
      unreadNotifications: _count(json['unread_notifications']),
      unreadPersonalMessages: _count(json['unread_personal_messages']),
      unseenReviewables: _count(json['unseen_reviewables']),
      topicTrackingUnread: _count(tracking['unread']),
      topicTrackingNew: _count(tracking['new']),
      username: jsonText(json['username']),
      groupedUnreadNotifications: NotificationTypeCounts.fromWire(
        json['grouped_unread_notifications'],
      ),
      pluginCounters: counterCodec.readLiveNotificationCounters(json),
    );
  }

  factory NotificationTotals.fromStoredJson(
    Map<String, dynamic> json, {
    PluginNotificationCounterCodec counterCodec =
        const EmptyPluginNotificationCounterCodec(),
  }) => NotificationTotals(
    unreadNotifications: _count(json['unreadNotifications']),
    unreadPersonalMessages: _count(json['unreadPersonalMessages']),
    unseenReviewables: _count(json['unseenReviewables']),
    topicTrackingUnread: _count(json['topicTrackingUnread']),
    topicTrackingNew: _count(json['topicTrackingNew']),
    username: jsonText(json['username']),
    groupedUnreadNotifications: NotificationTypeCounts.fromWire(
      json['groupedUnreadNotifications'],
    ),
    pluginCounters: counterCodec.readStoredNotificationCounters(
      json['plugins'],
    ),
  );

  Map<String, Object?> toStoredJson({
    PluginNotificationCounterCodec counterCodec =
        const EmptyPluginNotificationCounterCodec(),
  }) {
    final plugins = counterCodec.writeStoredNotificationCounters(
      pluginCounters,
    );
    return <String, Object?>{
      'unreadNotifications': unreadNotifications,
      'unreadPersonalMessages': unreadPersonalMessages,
      'unseenReviewables': unseenReviewables,
      'topicTrackingUnread': topicTrackingUnread,
      'topicTrackingNew': topicTrackingNew,
      'username': ?username,
      'groupedUnreadNotifications': ?groupedUnreadNotifications.toJson(),
      if (plugins.isNotEmpty) 'plugins': plugins,
    };
  }

  static int _count(Object? value) => _optionalCount(value) ?? 0;

  static int? _optionalCount(Object? value) {
    final count = jsonIntOrNull(value);
    if (count == null) return null;
    return count < 0 ? 0 : count;
  }

  NotificationTotals withNotification(Object? message) {
    if (message is! Map) return this;

    final all = _optionalCount(message['all_unread_notifications_count']);
    final messages = _optionalCount(
      message['new_personal_messages_notifications_count'],
    );
    final grouped = NotificationTypeCounts.fromWire(
      message['grouped_unread_notifications'],
    );
    if (all == null && messages == null && !grouped.isAvailable) return this;

    final personal = messages ?? unreadPersonalMessages;
    return copyWith(
      unreadNotifications: all == null ? null : (all - personal).clamp(0, all),
      unreadPersonalMessages: personal,
      groupedUnreadNotifications: grouped.isAvailable ? grouped : null,
    );
  }

  NotificationTotals withReviewableCounts(Object? message) {
    if (message is! Map) return this;

    final unseen = _optionalCount(message['unseen_reviewable_count']);
    if (unseen == null) return this;
    return copyWith(unseenReviewables: unseen);
  }

  NotificationTotals copyWith({
    int? unreadNotifications,
    int? unreadPersonalMessages,
    int? unseenReviewables,
    NotificationTypeCounts? groupedUnreadNotifications,
    PluginNotificationCounters? pluginCounters,
  }) {
    return NotificationTotals(
      unreadNotifications: unreadNotifications ?? this.unreadNotifications,
      unreadPersonalMessages:
          unreadPersonalMessages ?? this.unreadPersonalMessages,
      unseenReviewables: unseenReviewables ?? this.unseenReviewables,
      topicTrackingUnread: topicTrackingUnread,
      topicTrackingNew: topicTrackingNew,
      username: username,
      groupedUnreadNotifications:
          groupedUnreadNotifications ?? this.groupedUnreadNotifications,
      pluginCounters: pluginCounters ?? this.pluginCounters,
    );
  }

  NotificationTotals withGroupedUnreadNotifications(
    NotificationTypeCounts counts,
  ) => !counts.isAvailable || counts == groupedUnreadNotifications
      ? this
      : copyWith(groupedUnreadNotifications: counts);

  int pluginCounter(PluginNotificationCounterId id) => pluginCounters.count(id);

  bool hasPluginCounter(PluginNotificationCounterId id) =>
      pluginCounters.isAvailable(id);

  NotificationTotals updatePluginCounter(
    PluginNotificationCounter counter,
    int Function(int current) reduce,
  ) => copyWith(pluginCounters: pluginCounters.update(counter, reduce));

  static NotificationTotals mergeRefresh({
    required NotificationTotals response,
    required NotificationTotals before,
    required NotificationTotals live,
  }) => NotificationTotals(
    unreadNotifications: live.unreadNotifications != before.unreadNotifications
        ? live.unreadNotifications
        : response.unreadNotifications,
    unreadPersonalMessages:
        live.unreadPersonalMessages != before.unreadPersonalMessages
        ? live.unreadPersonalMessages
        : response.unreadPersonalMessages,
    unseenReviewables: live.unseenReviewables != before.unseenReviewables
        ? live.unseenReviewables
        : response.unseenReviewables,
    topicTrackingUnread: response.topicTrackingUnread,
    topicTrackingNew: response.topicTrackingNew,
    username: response.username,
    groupedUnreadNotifications:
        live.groupedUnreadNotifications != before.groupedUnreadNotifications
        ? live.groupedUnreadNotifications
        : response.groupedUnreadNotifications.isAvailable
        ? response.groupedUnreadNotifications
        : live.groupedUnreadNotifications,
    pluginCounters: PluginNotificationCounters.mergeRefresh(
      response: response.pluginCounters,
      before: before.pluginCounters,
      live: live.pluginCounters,
    ),
  );

  final int unreadNotifications;
  final int unreadPersonalMessages;
  final int unseenReviewables;

  final int topicTrackingUnread;
  final int topicTrackingNew;

  int get topicTrackingSidebarCount =>
      topicTrackingUnread > 0 ? topicTrackingUnread : topicTrackingNew;

  final String? username;
  final NotificationTypeCounts groupedUnreadNotifications;
  final PluginNotificationCounters pluginCounters;

  int get badge =>
      unreadNotifications +
      unreadPersonalMessages +
      unseenReviewables +
      pluginCounters.badge;

  @override
  bool operator ==(Object other) =>
      other is NotificationTotals &&
      other.unreadNotifications == unreadNotifications &&
      other.unreadPersonalMessages == unreadPersonalMessages &&
      other.unseenReviewables == unseenReviewables &&
      other.topicTrackingUnread == topicTrackingUnread &&
      other.topicTrackingNew == topicTrackingNew &&
      other.username == username &&
      other.groupedUnreadNotifications == groupedUnreadNotifications &&
      other.pluginCounters == pluginCounters;

  @override
  int get hashCode => Object.hash(
    unreadNotifications,
    unreadPersonalMessages,
    unseenReviewables,
    topicTrackingUnread,
    topicTrackingNew,
    username,
    groupedUnreadNotifications,
    pluginCounters,
  );
}
