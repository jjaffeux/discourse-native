import 'package:flutter/foundation.dart';

import 'notification.dart';

@immutable
class NotificationFeed {
  const NotificationFeed({
    this.notifications = const [],
    this.loading = false,
    this.error,
    this.loaded = false,
  });

  const NotificationFeed.loading() : this(loading: true);

  const NotificationFeed.failed(String message)
    : this(error: message, loaded: true);

  const NotificationFeed.of(List<DiscourseNotification> notifications)
    : this(notifications: notifications, loaded: true);

  final List<DiscourseNotification> notifications;
  final bool loading;
  final String? error;

  final bool loaded;

  bool get isEmpty => loaded && error == null && notifications.isEmpty;

  NotificationFeed withRead(int id) {
    final index = notifications.indexWhere(
      (notification) => notification.id == id && notification.isUnread,
    );
    if (index < 0) return this;

    final updated = List<DiscourseNotification>.of(notifications);
    updated[index] = updated[index].asRead();
    return NotificationFeed(
      notifications: updated,
      loading: loading,
      error: error,
      loaded: loaded,
    );
  }
}
