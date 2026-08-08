import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/bookmark_feed.dart';
import '../models/discourse_instance.dart';
import '../models/notification.dart';
import '../models/notification_feed.dart';
import '../models/notification_totals.dart';

typedef TotalsLoaded =
    void Function(DiscourseInstance instance, NotificationTotals totals);

/// Account-specific activity held independently from shell navigation state.
final class AccountActivityController extends FrameSafeNotifier {
  AccountActivityController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    this.onTotalsLoaded,
  });

  final AccountActivityApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;
  final TotalsLoaded? onTotalsLoaded;

  void _report(Object error, StackTrace stackTrace, String operation) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'account',
      handled: true,
      degraded: true,
    );
  }

  final _totalsChanges = _ActivityAspect();
  final _notificationChanges = _ActivityAspect();
  final _bookmarkChanges = _ActivityAspect();

  Listenable get totalsListenable => _totalsChanges;
  Listenable get notificationsListenable => _notificationChanges;
  Listenable get bookmarksListenable => _bookmarkChanges;

  final Map<String, NotificationTotals> _totals = {};
  final Map<String, NotificationFeed> _notifications = {};
  final Map<String, BookmarkFeed> _bookmarks = {};
  final Map<String, Object> _totalsRequests = {};
  final Map<String, Object> _notificationRequests = {};
  final Map<String, Object> _bookmarkRequests = {};
  final Map<(String, int), Object> _notificationReadRequests = {};

  NotificationTotals? totalsFor(String siteUrl) => _totals[siteUrl];

  NotificationFeed notificationsFor(String? siteUrl) => siteUrl == null
      ? const NotificationFeed()
      : _notifications[siteUrl] ?? const NotificationFeed();

  BookmarkFeed bookmarksFor(String? siteUrl) => siteUrl == null
      ? const BookmarkFeed()
      : _bookmarks[siteUrl] ?? const BookmarkFeed();

  Future<void> refreshAll(Iterable<DiscourseInstance> instances) async {
    await Future.wait(
      instances.where((instance) => instance.isConnected).map(refresh),
    );
  }

  Future<NotificationTotals?> refresh(DiscourseInstance instance) async {
    if (isDisposed) return null;
    final lease = lifecycle.capture(instance.url);
    final request = Object();
    _totalsRequests[instance.url] = request;
    final before = _totals[instance.url] ?? const NotificationTotals();
    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      if (apiKey == null) return null;
      final totals = await api.notificationTotals(
        siteUrl: instance.url,
        apiKey: apiKey,
      );
      NotificationTotals? applied;
      final accepted = _commit(lease, () {
        if (!identical(_totalsRequests[instance.url], request)) return;
        final current = _totals[instance.url];
        final resolved = current != null
            ? _mergeChangedCounts(totals, before, current)
            : totals;
        applied = resolved;
        if (current != resolved) {
          _totals[instance.url] = resolved;
          _notifyTotals();
        }
        onTotalsLoaded?.call(instance, resolved);
      });
      return accepted ? applied : null;
    } catch (error, stackTrace) {
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(_totalsRequests[instance.url], request)) {
        return null;
      }
      _report(error, stackTrace, 'account.refreshTotals');
      return null;
    } finally {
      _commit(lease, () {
        if (identical(_totalsRequests[instance.url], request)) {
          _totalsRequests.remove(instance.url);
        }
      });
    }
  }

  Future<void> loadNotifications(DiscourseInstance instance) async {
    if (isDisposed || !instance.isConnected) return;
    final lease = lifecycle.capture(instance.url);
    if (_notificationRequests.containsKey(instance.url)) return;
    final request = Object();
    _notificationRequests[instance.url] = request;
    final held = _notifications[instance.url];

    if (held == null || held.error != null) {
      _notifications[instance.url] = const NotificationFeed.loading();
      _notifyNotifications();
    }

    void fail(String message) {
      if (held != null && held.notifications.isNotEmpty) return;
      _notifications[instance.url] = NotificationFeed.failed(message);
    }

    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      if (apiKey == null) {
        _commit(lease, () {
          if (!identical(_notificationRequests[instance.url], request)) return;
          fail('Reconnect to ${instance.host} to see notifications.');
          _notifyNotifications();
        });
        return;
      }
      final notifications = await api.notifications(
        siteUrl: instance.url,
        apiKey: apiKey,
      );
      _commit(lease, () {
        if (!identical(_notificationRequests[instance.url], request)) return;
        _notifications[instance.url] = NotificationFeed.of(notifications);
        _notifyNotifications();
      });
    } on SiteLookupException catch (error, stackTrace) {
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(_notificationRequests[instance.url], request)) {
        return;
      }
      _report(error, stackTrace, 'account.loadNotifications');
      _commit(lease, () {
        if (!identical(_notificationRequests[instance.url], request)) return;
        fail(
          error.failure == SiteLookupFailure.notDiscourse
              ? 'Not allowed — try reconnecting to ${instance.host}.'
              : "Couldn't reach ${instance.host}.",
        );
        _notifyNotifications();
      });
    } catch (error, stackTrace) {
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(_notificationRequests[instance.url], request)) {
        return;
      }
      _report(error, stackTrace, 'account.loadNotifications');
      _commit(lease, () {
        if (!identical(_notificationRequests[instance.url], request)) return;
        fail("Couldn't load notifications from ${instance.host}.");
        _notifyNotifications();
      });
    } finally {
      _commit(lease, () {
        if (identical(_notificationRequests[instance.url], request)) {
          _notificationRequests.remove(instance.url);
        }
      });
    }
  }

  Future<void> loadBookmarks(DiscourseInstance instance) async {
    if (isDisposed) return;
    final username = instance.user?.username;
    if (username == null) return;
    final lease = lifecycle.capture(instance.url);
    if (_bookmarkRequests.containsKey(instance.url)) return;
    final request = Object();
    _bookmarkRequests[instance.url] = request;
    final held = _bookmarks[instance.url];

    if (held == null || held.error != null) {
      _bookmarks[instance.url] = const BookmarkFeed.loading();
      _notifyBookmarks();
    }

    void fail(String message) {
      if (held != null && held.hasRows) return;
      _bookmarks[instance.url] = BookmarkFeed.failed(message);
    }

    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      if (apiKey == null) {
        _commit(lease, () {
          if (!identical(_bookmarkRequests[instance.url], request)) return;
          fail('Reconnect to ${instance.host} to see your bookmarks.');
          _notifyBookmarks();
        });
        return;
      }
      final bookmarks = await api.bookmarks(
        siteUrl: instance.url,
        apiKey: apiKey,
        username: username,
      );
      _commit(lease, () {
        if (!identical(_bookmarkRequests[instance.url], request)) return;
        _bookmarks[instance.url] = BookmarkFeed.of(bookmarks);
        _notifyBookmarks();
      });
    } on SiteLookupException catch (error, stackTrace) {
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(_bookmarkRequests[instance.url], request)) {
        return;
      }
      _report(error, stackTrace, 'account.loadBookmarks');
      _commit(lease, () {
        if (!identical(_bookmarkRequests[instance.url], request)) return;
        fail(
          error.failure == SiteLookupFailure.notDiscourse
              ? 'Not allowed — try reconnecting to ${instance.host}.'
              : "Couldn't reach ${instance.host}.",
        );
        _notifyBookmarks();
      });
    } catch (error, stackTrace) {
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(_bookmarkRequests[instance.url], request)) {
        return;
      }
      _report(error, stackTrace, 'account.loadBookmarks');
      _commit(lease, () {
        if (!identical(_bookmarkRequests[instance.url], request)) return;
        fail("Couldn't load bookmarks from ${instance.host}.");
        _notifyBookmarks();
      });
    } finally {
      _commit(lease, () {
        if (identical(_bookmarkRequests[instance.url], request)) {
          _bookmarkRequests.remove(instance.url);
        }
      });
    }
  }

  void readNotification(
    DiscourseInstance instance,
    DiscourseNotification notification,
  ) {
    if (isDisposed || notification.read) return;
    final key = (instance.url, notification.id);
    if (_notificationReadRequests.containsKey(key)) return;

    final request = Object();
    _notificationReadRequests[key] = request;
    _markNotificationRead(instance, notification).whenComplete(() {
      if (identical(_notificationReadRequests[key], request)) {
        _notificationReadRequests.remove(key);
      }
    }).ignore();
  }

  Future<void> _markNotificationRead(
    DiscourseInstance instance,
    DiscourseNotification notification,
  ) async {
    final lease = lifecycle.capture(instance.url);
    var notificationChanged = false;
    var bookmarkChanged = false;
    if (_notifications[instance.url] case final feed?) {
      final updated = feed.withRead(notification.id);
      if (!identical(updated, feed)) {
        _notifications[instance.url] = updated;
        notificationChanged = true;
      }
    }
    if (_bookmarks[instance.url] case final feed?) {
      final updated = feed.withRead(notification.id);
      if (!identical(updated, feed)) {
        _bookmarks[instance.url] = updated;
        bookmarkChanged = true;
      }
    }
    if (notificationChanged) _notificationChanges.changed();
    if (bookmarkChanged) _bookmarkChanges.changed();
    if (notificationChanged || bookmarkChanged) notifySafely();

    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      if (apiKey == null || !lease.isCurrent) return;
      await api.markNotificationRead(
        siteUrl: instance.url,
        apiKey: apiKey,
        id: notification.id,
      );
    } catch (error, stackTrace) {
      final key = (instance.url, notification.id);
      if (isDisposed ||
          !lease.isCurrent ||
          !_notificationReadRequests.containsKey(key)) {
        return;
      }
      _report(error, stackTrace, 'account.markNotificationRead');
      return;
    }

    if (!lease.isCurrent) return;
    await refresh(instance);
  }

  void applyCounts(
    String siteUrl,
    NotificationTotals Function(NotificationTotals held) fold,
  ) {
    if (isDisposed) return;
    final held = _totals[siteUrl] ?? const NotificationTotals();
    final updated = fold(held);
    if (updated == held) return;
    _totals[siteUrl] = updated;
    _notifyTotals();
  }

  void forget(String siteUrl) {
    if (isDisposed) return;
    final hadTotals = _totals.remove(siteUrl) != null;
    final hadNotifications = _notifications.remove(siteUrl) != null;
    final hadBookmarks = _bookmarks.remove(siteUrl) != null;
    _totalsRequests.remove(siteUrl);
    _notificationRequests.remove(siteUrl);
    _bookmarkRequests.remove(siteUrl);
    _notificationReadRequests.removeWhere((key, _) => key.$1 == siteUrl);
    final changed = hadTotals || hadNotifications || hadBookmarks;
    if (hadTotals) _totalsChanges.changed();
    if (hadNotifications) _notificationChanges.changed();
    if (hadBookmarks) _bookmarkChanges.changed();
    if (changed) notifySafely();
  }

  void _notifyTotals() {
    _totalsChanges.changed();
    notifySafely();
  }

  void _notifyNotifications() {
    _notificationChanges.changed();
    notifySafely();
  }

  void _notifyBookmarks() {
    _bookmarkChanges.changed();
    notifySafely();
  }

  bool _commit(SiteLease lease, SiteMutation mutation) {
    if (isDisposed) return false;
    return lease.commit(mutation);
  }

  static NotificationTotals _mergeChangedCounts(
    NotificationTotals response,
    NotificationTotals before,
    NotificationTotals live,
  ) => NotificationTotals(
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
    chatNotifications: live.chatNotifications != before.chatNotifications
        ? live.chatNotifications
        : response.chatNotifications,
    topicTrackingUnread: response.topicTrackingUnread,
    topicTrackingNew: response.topicTrackingNew,
    username: response.username,
    hasChatEnabled: response.hasChatEnabled,
  );

  @override
  void dispose() {
    _notificationReadRequests.clear();
    _totalsChanges.dispose();
    _notificationChanges.dispose();
    _bookmarkChanges.dispose();
    super.dispose();
  }
}

final class _ActivityAspect extends FrameSafeNotifier {
  void changed() => notifySafely();
}
