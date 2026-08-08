import 'package:flutter/foundation.dart';

import 'bookmark.dart';
import 'notification.dart';

/// What the bookmarks tab knows about one site's list, at one moment.
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

  /// Reminders that have fired and not been read, shown above the bookmarks
  /// the way Discourse shows them.
  final List<DiscourseNotification> reminders;

  final List<Bookmark> bookmarks;
  final bool loading;
  final String? error;

  /// True once a request has finished, so an empty list can be told apart from
  /// one that has not been fetched.
  final bool loaded;

  bool get hasRows => reminders.isNotEmpty || bookmarks.isNotEmpty;

  bool get isEmpty => loaded && error == null && !hasRows;

  /// The same lists with one reminder no longer unread.
  ///
  /// Does nothing when [id] is not one of them, which is the usual case: this
  /// is called for every notification read anywhere, since the same reminder
  /// can be sitting in both this tab and the notifications one.
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
}
