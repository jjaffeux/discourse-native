import 'package:discourse_native/l10n/strings.dart';

import '../data/destination_bookmarks_store.dart';
import '../data/site_lifecycle.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/content_route.dart';
import '../models/destination_bookmark.dart';
import '../plugin_api/bookmark_host.dart';

final class DestinationBookmarkAction {
  const DestinationBookmarkAction({
    required this.bookmarked,
    required this.invoke,
  });
  final bool bookmarked;
  final Future<BookmarkWriteResult> Function() invoke;
}

/// The signed-in account's local destination bookmarks.
///
/// A toggle is captured against one account session and one account identity.
/// It reads them again inside the store's write queue, since a sign-out may
/// land while it waits there, and again once the write is durable.
final class AccountDestinationBookmarks extends FrameSafeNotifier {
  AccountDestinationBookmarks({
    required this._store,
    required this._lifecycle,
    required this._isConnected,
    required this._currentSiteUrl,
    required this._accountIdentityFor,
  });

  final DestinationBookmarksStore _store;
  final SiteLifecycle _lifecycle;
  final bool Function(String siteUrl) _isConnected;
  final String? Function() _currentSiteUrl;
  final String Function(String siteUrl) _accountIdentityFor;

  List<DestinationBookmark> entriesFor(String siteUrl) =>
      _store.entriesFor(siteUrl, _accountIdentityFor(siteUrl));

  DestinationBookmarkAction? actionFor(ContentRoute route, {String? siteUrl}) {
    final site = siteUrl ?? _currentSiteUrl();
    final bookmark = DestinationBookmark.fromRoute(route);
    if (site == null || !_isConnected(site) || bookmark == null) return null;
    final account = _accountIdentityFor(site);
    final lease = _lifecycle.capture(site);
    final bookmarked = entriesFor(
      site,
    ).any((entry) => entry.identity == bookmark.identity);
    bool current() =>
        !isDisposed && lease.isCurrent && _accountIdentityFor(site) == account;
    return DestinationBookmarkAction(
      bookmarked: bookmarked,
      invoke: () async {
        if (!current()) {
          return BookmarkWriteResult.refused(
            appL10n.bookmarkChangedRefreshMenu,
          );
        }
        try {
          await _store.set(
            site,
            account,
            bookmark,
            bookmarked: !bookmarked,
            isCurrent: current,
          );
          if (!current()) {
            return BookmarkWriteResult.refused(
              appL10n.bookmarkChangedRefreshMenu,
            );
          }
          notifySafely();
          return const BookmarkWriteResult.saved();
        } catch (error) {
          return BookmarkWriteResult.refused(appL10n.couldNotSaveChanges);
        }
      },
    );
  }
}
