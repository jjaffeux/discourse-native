import 'package:flutter/foundation.dart';

import 'notification.dart';

/// What the notifications tab knows about one site's list, at one moment.
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

  /// True once a request has finished, so an empty list can be told apart from
  /// one that has not been fetched.
  final bool loaded;

  bool get isEmpty => loaded && error == null && notifications.isEmpty;

  /// The same list with one row no longer unread.
  ///
  /// Tapping a notification marks it read on the site, and the row should stop
  /// standing out the moment it is tapped rather than when the request lands.
  NotificationFeed withRead(int id) {
    return NotificationFeed(
      notifications: [
        for (final notification in notifications)
          notification.id == id ? notification.asRead() : notification,
      ],
      loading: loading,
      error: error,
      loaded: loaded,
    );
  }
}
