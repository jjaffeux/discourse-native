import 'package:flutter/foundation.dart';

import '../plugin_api/notification_counters.dart';
import 'json.dart';

/// Everything `/notifications/totals.json` reports in one call: the rail badge
/// and every sidebar count come from here rather than from per-section
/// requests.
@immutable
class NotificationTotals {
  const NotificationTotals({
    this.unreadNotifications = 0,
    this.unreadPersonalMessages = 0,
    this.unseenReviewables = 0,
    this.topicTrackingUnread = 0,
    this.topicTrackingNew = 0,
    this.username,
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
      if (plugins.isNotEmpty) 'plugins': plugins,
    };
  }

  static int _count(Object? value) => _optionalCount(value) ?? 0;

  /// Reads a live count while preserving absence as "no update".
  ///
  /// Negative counts are impossible server state, but treating a present one
  /// as zero keeps badge arithmetic total and prevents reversed clamp bounds.
  static int? _optionalCount(Object? value) {
    final count = jsonIntOrNull(value);
    if (count == null) return null;
    return count < 0 ? 0 : count;
  }

  /// Folds a `/notification/{id}` message onto these totals.
  ///
  /// Published by `User#publish_notifications_state` every time anything about
  /// the account's notifications changes. Returns a value equal to this one
  /// when the message says nothing we hold, so the caller can skip a redraw.
  ///
  /// The arithmetic is the trap. The message carries its own
  /// `unread_notifications`, and it is **not** the one this class holds:
  /// `UserNotificationTotalSerializer` derives that field as
  /// `all_unread_notifications_count - new_personal_messages_notifications_count`,
  /// so private messages are counted once, under their own name. Reading the
  /// message's field straight across would make the number jump the moment the
  /// first message arrived and never agree with the endpoint again.
  NotificationTotals withNotification(Object? message) {
    if (message is! Map) return this;

    final all = _optionalCount(message['all_unread_notifications_count']);
    final messages = _optionalCount(
      message['new_personal_messages_notifications_count'],
    );
    if (all == null && messages == null) return this;

    final personal = messages ?? unreadPersonalMessages;
    return copyWith(
      unreadNotifications: all == null ? null : (all - personal).clamp(0, all),
      unreadPersonalMessages: personal,
    );
  }

  /// Folds a `/reviewable_counts/{id}` message onto these totals.
  ///
  /// A separate channel from the notifications one, and published only to
  /// staff, so most accounts never see one. `reviewable_count` is the size of
  /// the queue and `unseen_reviewable_count` is what has appeared in it since
  /// the user last looked — the second is the one anything here counts.
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
      pluginCounters: pluginCounters ?? this.pluginCounters,
    );
  }

  int pluginCounter(PluginNotificationCounterId id) => pluginCounters.count(id);

  bool hasPluginCounter(PluginNotificationCounterId id) =>
      pluginCounters.isAvailable(id);

  NotificationTotals updatePluginCounter(
    PluginNotificationCounter counter,
    int Function(int current) reduce,
  ) => copyWith(pluginCounters: pluginCounters.update(counter, reduce));

  /// Reconciles a refresh with account events received while it was in flight.
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
    pluginCounters: PluginNotificationCounters.mergeRefresh(
      response: response.pluginCounters,
      before: before.pluginCounters,
      live: live.pluginCounters,
    ),
  );

  final int unreadNotifications;
  final int unreadPersonalMessages;
  final int unseenReviewables;

  /// Topics with unread posts, and topics never seen — the two sources for the
  /// Topics sidebar count.
  final int topicTrackingUnread;
  final int topicTrackingNew;

  /// The number core's Topics sidebar row shows.
  ///
  /// Legacy New prioritizes unread topics and falls back to new topics. With
  /// unified New the server puts the combined new-and-unread total in
  /// [topicTrackingNew] and omits [topicTrackingUnread], so the same selection
  /// works for both modes without retaining another current-user preference.
  int get topicTrackingSidebarCount =>
      topicTrackingUnread > 0 ? topicTrackingUnread : topicTrackingNew;

  final String? username;
  final PluginNotificationCounters pluginCounters;

  /// What the rail badge shows: things addressed to you, not merely unread
  /// topics. Matches how DiscourseMobile totals it.
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
      other.pluginCounters == pluginCounters;

  @override
  int get hashCode => Object.hash(
    unreadNotifications,
    unreadPersonalMessages,
    unseenReviewables,
    topicTrackingUnread,
    topicTrackingNew,
    username,
    pluginCounters,
  );
}
