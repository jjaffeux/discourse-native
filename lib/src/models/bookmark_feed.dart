import 'package:flutter/foundation.dart';

import 'bookmark.dart';
import 'notification.dart';

@immutable
class BookmarkFeed {
  const BookmarkFeed({
    this.reminders = const [],
    this.bookmarks = const [],
    this.loading = false,
    this.error,
    this.loaded = false,
  });

  const BookmarkFeed.loading() : this(loading: true);

  const BookmarkFeed.failed(String message)
    : this(error: message, loaded: true);

  BookmarkFeed.of(BookmarkPayload payload)
    : this(
        reminders: payload.reminders,
        bookmarks: payload.bookmarks,
        loaded: true,
      );

  final List<DiscourseNotification> reminders;

  final List<Bookmark> bookmarks;
  final bool loading;
  final String? error;

  final bool loaded;

  bool get hasRows => reminders.isNotEmpty || bookmarks.isNotEmpty;

  bool get isEmpty => loaded && error == null && !hasRows;

  BookmarkFeed withRead(int id) {
    final index = reminders.indexWhere(
      (reminder) => reminder.id == id && reminder.isUnread,
    );
    if (index < 0) return this;

    final updated = List<DiscourseNotification>.of(reminders);
    updated[index] = updated[index].asRead();
    return BookmarkFeed(
      reminders: updated,
      bookmarks: bookmarks,
      loading: loading,
      error: error,
      loaded: loaded,
    );
  }

  BookmarkFeed withUnread(int id) {
    final index = reminders.indexWhere(
      (reminder) => reminder.id == id && reminder.read,
    );
    if (index < 0) return this;

    final updated = List<DiscourseNotification>.of(reminders);
    updated[index] = updated[index].asUnread();
    return BookmarkFeed(
      reminders: updated,
      bookmarks: bookmarks,
      loading: loading,
      error: error,
      loaded: loaded,
    );
  }
}
