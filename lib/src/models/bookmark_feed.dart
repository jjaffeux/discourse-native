import 'package:flutter/foundation.dart';

import 'account_feed_window.dart';
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
    this.loadingPrevious = false,
    this.loaded = false,
    this.hasMore = true,
    this.nextPage = 0,
    this.retryFromStart = false,
    this.retryPrevious = false,
    this.error,
    this.window = const AccountFeedWindow(),
  });

  final List<Bookmark> bookmarks;
  final bool loading;
  final bool loadingPrevious;
  final bool loaded;
  final bool hasMore;
  final int nextPage;
  final bool retryFromStart;
  final bool retryPrevious;
  final String? error;
  final AccountFeedWindow<Bookmark> window;

  int get firstPage => window.start;
  bool get hasPrevious => firstPage > 0;
  int get previousPage => (firstPage - 1).clamp(0, firstPage);
  int get retainedPageCount => window.packets.length;
  int get estimatedRetainedBytes => window.estimatedBytes(_estimate);
  bool get isEmpty =>
      loaded && !hasPrevious && !hasMore && error == null && bookmarks.isEmpty;

  BookmarkListFeed loadingPage({bool prepend = false}) => BookmarkListFeed(
    bookmarks: bookmarks,
    loading: true,
    loadingPrevious: prepend,
    loaded: loaded,
    hasMore: hasMore,
    nextPage: nextPage,
    window: window,
  );

  BookmarkListFeed withPage(
    BookmarkListPage page, {
    required bool replace,
    bool prepend = false,
    int? requestPage,
  }) {
    final start = requestPage ?? (replace ? 0 : nextPage);
    final base = replace ? const AccountFeedWindow<Bookmark>() : _heldWindow;
    final updated = base.withPage(
      incoming: page.bookmarks,
      start: start,
      end: start + 1,
      prepend: prepend,
      identity: (bookmark) => bookmark.id,
      merge: (_, incoming) => incoming,
      estimate: _estimate,
    );
    return BookmarkListFeed(
      bookmarks: updated.items,
      loaded: true,
      hasMore: prepend ? hasMore || updated.end < nextPage : page.hasMore,
      nextPage: updated.end,
      window: updated,
    );
  }

  AccountFeedWindow<Bookmark> get _heldWindow =>
      window.packets.isNotEmpty || bookmarks.isEmpty
      ? window
      : AccountFeedWindow(
          packets: [
            AccountFeedPacket(start: 0, end: nextPage, items: bookmarks),
          ],
        );

  BookmarkListFeed withError(String message, {required bool retryFromStart}) =>
      BookmarkListFeed(
        bookmarks: bookmarks,
        loaded: true,
        hasMore: hasMore,
        nextPage: nextPage,
        retryFromStart: retryFromStart,
        retryPrevious: loadingPrevious,
        error: message,
        window: window,
      );

  static int _estimate(Bookmark item) => accountFeedStringBytes([
    item.title,
    item.name,
    item.author,
    item.path,
    item.bookmarkableType,
  ]);
}
