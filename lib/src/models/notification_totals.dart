import 'package:flutter/foundation.dart';

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
    this.chatNotifications = 0,
    this.topicTrackingUnread = 0,
    this.topicTrackingNew = 0,
    this.username,
    this.hasChatEnabled = false,
  });

  factory NotificationTotals.fromJson(Map<String, dynamic> json) {
    final tracking = jsonObject(json['topic_tracking']);
    return NotificationTotals(
      unreadNotifications: jsonInt(json['unread_notifications']),
      unreadPersonalMessages: jsonInt(json['unread_personal_messages']),
      unseenReviewables: jsonInt(json['unseen_reviewables']),
      chatNotifications: jsonInt(json['chat_notifications']),
      topicTrackingUnread: jsonInt(tracking['unread']),
      topicTrackingNew: jsonInt(tracking['new']),
      username: jsonText(json['username']),
      // The key is only present when the site has chat enabled.
      hasChatEnabled: json['chat_notifications'] is num,
    );
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

    final all = jsonIntOrNull(message['all_unread_notifications_count']);
    final messages = jsonIntOrNull(
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

    final unseen = jsonIntOrNull(message['unseen_reviewable_count']);
    if (unseen == null) return this;
    return copyWith(unseenReviewables: unseen);
  }

  NotificationTotals copyWith({
    int? unreadNotifications,
    int? unreadPersonalMessages,
    int? unseenReviewables,
    int? chatNotifications,
  }) {
    return NotificationTotals(
      unreadNotifications: unreadNotifications ?? this.unreadNotifications,
      unreadPersonalMessages:
          unreadPersonalMessages ?? this.unreadPersonalMessages,
      unseenReviewables: unseenReviewables ?? this.unseenReviewables,
      chatNotifications: chatNotifications ?? this.chatNotifications,
      topicTrackingUnread: topicTrackingUnread,
      topicTrackingNew: topicTrackingNew,
      username: username,
      hasChatEnabled: hasChatEnabled,
    );
  }

  final int unreadNotifications;
  final int unreadPersonalMessages;
  final int unseenReviewables;
  final int chatNotifications;

  /// Topics with unread posts, and topics never seen — the two numbers the
  /// sidebar's Unread and New entries show.
  final int topicTrackingUnread;
  final int topicTrackingNew;

  final String? username;
  final bool hasChatEnabled;

  /// What the rail badge shows: things addressed to you, not merely unread
  /// topics. Matches how DiscourseMobile totals it.
  int get badge =>
      unreadNotifications +
      unreadPersonalMessages +
      chatNotifications +
      unseenReviewables;

  @override
  bool operator ==(Object other) =>
      other is NotificationTotals &&
      other.unreadNotifications == unreadNotifications &&
      other.unreadPersonalMessages == unreadPersonalMessages &&
      other.unseenReviewables == unseenReviewables &&
      other.chatNotifications == chatNotifications &&
      other.topicTrackingUnread == topicTrackingUnread &&
      other.topicTrackingNew == topicTrackingNew &&
      other.username == username &&
      other.hasChatEnabled == hasChatEnabled;

  @override
  int get hashCode => Object.hash(
    unreadNotifications,
    unreadPersonalMessages,
    unseenReviewables,
    chatNotifications,
    topicTrackingUnread,
    topicTrackingNew,
    username,
    hasChatEnabled,
  );
}
