import 'package:flutter/foundation.dart';

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
    final tracking =
        json['topic_tracking'] as Map<String, dynamic>? ?? const {};
    return NotificationTotals(
      unreadNotifications: _int(json['unread_notifications']),
      unreadPersonalMessages: _int(json['unread_personal_messages']),
      unseenReviewables: _int(json['unseen_reviewables']),
      chatNotifications: _int(json['chat_notifications']),
      topicTrackingUnread: _int(tracking['unread']),
      topicTrackingNew: _int(tracking['new']),
      username: json['username'] as String?,
      // The key is only present when the site has chat enabled.
      hasChatEnabled: json['chat_notifications'] is num,
    );
  }

  static int _int(Object? value) => switch (value) {
    final num n => n.toInt(),
    final String s => int.tryParse(s) ?? 0,
    _ => 0,
  };

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
      other.topicTrackingNew == topicTrackingNew;

  @override
  int get hashCode => Object.hash(
    unreadNotifications,
    unreadPersonalMessages,
    unseenReviewables,
    chatNotifications,
    topicTrackingUnread,
    topicTrackingNew,
  );
}
