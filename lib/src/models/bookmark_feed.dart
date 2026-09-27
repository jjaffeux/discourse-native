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

/// The bookmarks page's own feed: every bookmark, paged from
/// `/u/{username}/bookmarks.json`, rather than the menu's twenty-row
/// [BookmarkFeed].
@immutable
class BookmarkListFeed {
  const BookmarkListFeed({
    this.bookmarks = const [],
    this.loading = false,
    this.loaded = false,
    this.hasMore = true,
    this.nextPage = 0,
    this.retryFromStart = false,
    this.error,
  });

  final List<Bookmark> bookmarks;
  final bool loading;
  final bool loaded;
  final bool hasMore;
  final int nextPage;
  final bool retryFromStart;
  final String? error;

  bool get isEmpty => loaded && error == null && bookmarks.isEmpty;

  /// Held rows stay mounted until a refresh's replacement arrives, so a
  /// failed refresh still has them to fall back to.
  BookmarkListFeed loadingPage() => BookmarkListFeed(
    bookmarks: bookmarks,
    loading: true,
    loaded: loaded,
    hasMore: hasMore,
    nextPage: nextPage,
  );

  BookmarkListFeed withPage(BookmarkListPage page, {required bool replace}) {
    final held = replace ? const <Bookmark>[] : bookmarks;
    // Core pages by offset, so a bookmark added or removed between two
    // requests shifts the next page by a row. Its id keeps it from being
    // listed twice; the newer copy wins.
    final byId = <int, Bookmark>{
      for (final bookmark in held) bookmark.id: bookmark,
      for (final bookmark in page.bookmarks) bookmark.id: bookmark,
    };
    return BookmarkListFeed(
      bookmarks: List.unmodifiable(byId.values),
      loaded: true,
      hasMore: page.hasMore,
      nextPage: (replace ? 0 : nextPage) + 1,
    );
  }

  BookmarkListFeed withError(String message, {required bool retryFromStart}) =>
      BookmarkListFeed(
        bookmarks: bookmarks,
        loaded: true,
        hasMore: hasMore,
        nextPage: nextPage,
        retryFromStart: retryFromStart,
        error: message,
      );
}
