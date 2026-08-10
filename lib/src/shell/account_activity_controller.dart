import 'dart:async';

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
    this.minimumRefreshInterval = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : assert(minimumRefreshInterval >= Duration.zero),
       _clock = clock ?? DateTime.now;

  final AccountActivityApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;
  final TotalsLoaded? onTotalsLoaded;
  final Duration minimumRefreshInterval;
  final DateTime Function() _clock;

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
  final _replyNotificationChanges = _ActivityAspect();
  final _chatNotificationChanges = _ActivityAspect();
  final _bookmarkChanges = _ActivityAspect();

  Listenable get totalsListenable => _totalsChanges;
  Listenable get notificationsListenable => _notificationChanges;
  Listenable get replyNotificationsListenable => _replyNotificationChanges;
  Listenable get chatNotificationsListenable => _chatNotificationChanges;
  Listenable get bookmarksListenable => _bookmarkChanges;

  final Map<String, NotificationTotals> _totals = {};
  final Map<String, NotificationFeed> _notifications = {};
  final Map<String, NotificationFeed> _replyNotifications = {};
  final Map<String, NotificationFeed> _chatNotifications = {};
  final Map<String, BookmarkFeed> _bookmarks = {};
  final Map<String, Object> _totalsRequests = {};
  final Map<String, Future<NotificationTotals?>> _totalsTasks = {};
  final Map<String, DateTime> _totalsAttemptedAt = {};
  final Map<String, DiscourseInstance> _pendingTotals = {};
  final Map<String, Completer<NotificationTotals?>> _pendingTotalsWaiters = {};
  final Map<String, Object> _notificationRequests = {};
  final Map<String, Object> _replyNotificationRequests = {};
  final Map<String, Object> _chatNotificationRequests = {};
  final Map<String, Object> _bookmarkRequests = {};
  final Map<(String, int), Object> _notificationReadRequests = {};
  final Map<String, Set<int>> _locallyReadNotificationIds = {};

  NotificationTotals? totalsFor(String siteUrl) => _totals[siteUrl];

  NotificationFeed notificationsFor(String? siteUrl) => siteUrl == null
      ? const NotificationFeed()
      : _notifications[siteUrl] ?? const NotificationFeed();

  NotificationFeed replyNotificationsFor(String? siteUrl) => siteUrl == null
      ? const NotificationFeed()
      : _replyNotifications[siteUrl] ?? const NotificationFeed();

  NotificationFeed chatNotificationsFor(String? siteUrl) => siteUrl == null
      ? const NotificationFeed()
      : _chatNotifications[siteUrl] ?? const NotificationFeed();

  BookmarkFeed bookmarksFor(String? siteUrl) => siteUrl == null
      ? const BookmarkFeed()
      : _bookmarks[siteUrl] ?? const BookmarkFeed();

  Future<void> refreshAll(Iterable<DiscourseInstance> instances) async {
    await Future.wait(
      instances.where((instance) => instance.isConnected).map(refresh),
    );
  }

  Future<NotificationTotals?> refresh(
    DiscourseInstance instance, {
    bool force = false,
  }) async {
    final active = _totalsTasks[instance.url];
    if (active != null) {
      // Ordinary lifecycle and navigation callers all want the same snapshot.
      // Replaying after it lands doubled `/notifications/totals.json` whenever
      // two of them overlapped. Only a write that can invalidate the active
      // snapshot is allowed to queue one reconciliation behind it.
      if (!force) return active;
      _pendingTotals[instance.url] = instance;
      return _pendingTotalsWaiters
          .putIfAbsent(instance.url, Completer<NotificationTotals?>.new)
          .future;
    }
    if (!force && _recentlyAttempted(instance.url)) {
      return _totals[instance.url];
    }
    return _startTotalsRefresh(instance);
  }

  bool _recentlyAttempted(String siteUrl) {
    final attemptedAt = _totalsAttemptedAt[siteUrl];
    return attemptedAt != null &&
        _clock().difference(attemptedAt) < minimumRefreshInterval;
  }

  Future<NotificationTotals?> _startTotalsRefresh(DiscourseInstance instance) {
    late final Future<NotificationTotals?> task;
    task = _performTotalsRefresh(instance).whenComplete(() {
      _finishTotalsRefresh(instance.url, task);
    });
    _totalsTasks[instance.url] = task;
    return task;
  }

  Future<NotificationTotals?> _performTotalsRefresh(
    DiscourseInstance instance,
  ) async {
    if (isDisposed) return null;
    _totalsAttemptedAt[instance.url] = _clock();
    final lease = lifecycle.capture(instance.url);
    final request = Object();
    _totalsRequests[instance.url] = request;
    final before = _totals[instance.url] ?? const NotificationTotals();
    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      if (apiKey == null ||
          !_ownsRequest(lease, _totalsRequests[instance.url], request)) {
        return null;
      }
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

  void _finishTotalsRefresh(String siteUrl, Future<NotificationTotals?> task) {
    if (!identical(_totalsTasks[siteUrl], task)) return;
    final removed = _totalsTasks.remove(siteUrl);
    assert(identical(removed, task));

    final pending = _pendingTotals.remove(siteUrl);
    final waiter = _pendingTotalsWaiters.remove(siteUrl);
    if (pending == null || waiter == null || isDisposed) {
      if (waiter != null && !waiter.isCompleted) waiter.complete(null);
      return;
    }

    final replay = _startTotalsRefresh(pending);
    unawaited(
      replay.then<void>(
        (totals) {
          if (!waiter.isCompleted) waiter.complete(totals);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!waiter.isCompleted) waiter.completeError(error, stackTrace);
        },
      ),
    );
  }

  Future<void> loadNotifications(DiscourseInstance instance) =>
      _loadNotificationFeed(
        instance,
        feeds: _notifications,
        requests: _notificationRequests,
        fetch: (apiKey) =>
            api.notifications(siteUrl: instance.url, apiKey: apiKey),
        reconnectMessage: 'Reconnect to ${instance.host} to see notifications.',
        failureMessage: "Couldn't load notifications from ${instance.host}.",
        operation: 'account.loadNotifications',
        notify: _notifyNotifications,
      );

  Future<void> loadReplyNotifications(DiscourseInstance instance) =>
      _loadNotificationFeed(
        instance,
        feeds: _replyNotifications,
        requests: _replyNotificationRequests,
        fetch: (apiKey) => api.notifications(
          siteUrl: instance.url,
          apiKey: apiKey,
          filterByTypes: userMenuReplyNotificationKinds,
        ),
        reconnectMessage: 'Reconnect to ${instance.host} to see replies.',
        failureMessage: "Couldn't load replies from ${instance.host}.",
        operation: 'account.loadReplyNotifications',
        notify: _notifyReplyNotifications,
      );

  Future<void> loadChatNotifications(DiscourseInstance instance) =>
      _loadNotificationFeed(
        instance,
        feeds: _chatNotifications,
        requests: _chatNotificationRequests,
        fetch: (apiKey) => api.notifications(
          siteUrl: instance.url,
          apiKey: apiKey,
          filterByTypes: userMenuChatNotificationKinds,
        ),
        reconnectMessage:
            'Reconnect to ${instance.host} to see chat notifications.',
        failureMessage:
            "Couldn't load chat notifications from ${instance.host}.",
        operation: 'account.loadChatNotifications',
        notify: _notifyChatNotifications,
      );

  Future<void> _loadNotificationFeed(
    DiscourseInstance instance, {
    required Map<String, NotificationFeed> feeds,
    required Map<String, Object> requests,
    required Future<List<DiscourseNotification>> Function(String apiKey) fetch,
    required String reconnectMessage,
    required String failureMessage,
    required String operation,
    required VoidCallback notify,
  }) async {
    if (isDisposed || !instance.isConnected) return;
    final lease = lifecycle.capture(instance.url);
    if (requests.containsKey(instance.url)) return;
    final request = Object();
    requests[instance.url] = request;
    final held = feeds[instance.url];

    if (held == null || held.error != null) {
      feeds[instance.url] = const NotificationFeed.loading();
      notify();
    }

    void fail(String message) {
      if (held != null && held.notifications.isNotEmpty) return;
      feeds[instance.url] = NotificationFeed.failed(message);
    }

    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      if (!_ownsRequest(lease, requests[instance.url], request)) {
        return;
      }
      if (apiKey == null) {
        _commit(lease, () {
          if (!identical(requests[instance.url], request)) return;
          fail(reconnectMessage);
          notify();
        });
        return;
      }
      final notifications = await fetch(apiKey);
      _commit(lease, () {
        if (!identical(requests[instance.url], request)) return;
        feeds[instance.url] = NotificationFeed.of(
          _preservingLocalReads(instance.url, notifications),
        );
        notify();
      });
    } on SiteLookupException catch (error, stackTrace) {
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(requests[instance.url], request)) {
        return;
      }
      _report(error, stackTrace, operation);
      _commit(lease, () {
        if (!identical(requests[instance.url], request)) return;
        fail(
          error.failure == SiteLookupFailure.notDiscourse
              ? 'Not allowed — try reconnecting to ${instance.host}.'
              : "Couldn't reach ${instance.host}.",
        );
        notify();
      });
    } catch (error, stackTrace) {
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(requests[instance.url], request)) {
        return;
      }
      _report(error, stackTrace, operation);
      _commit(lease, () {
        if (!identical(requests[instance.url], request)) return;
        fail(failureMessage);
        notify();
      });
    } finally {
      _commit(lease, () {
        if (identical(requests[instance.url], request)) {
          requests.remove(instance.url);
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
      if (!_ownsRequest(lease, _bookmarkRequests[instance.url], request)) {
        return;
      }
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
        _bookmarks[instance.url] = BookmarkFeed.of((
          reminders: _preservingLocalReads(instance.url, bookmarks.reminders),
          bookmarks: bookmarks.bookmarks,
        ));
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
    _markNotificationRead(instance, notification, request).whenComplete(() {
      if (identical(_notificationReadRequests[key], request)) {
        _notificationReadRequests.remove(key);
      }
    }).ignore();
  }

  Future<void> _markNotificationRead(
    DiscourseInstance instance,
    DiscourseNotification notification,
    Object request,
  ) async {
    final lease = lifecycle.capture(instance.url);
    _locallyReadNotificationIds
        .putIfAbsent(instance.url, () => <int>{})
        .add(notification.id);
    var notificationChanged = false;
    var replyNotificationChanged = false;
    var chatNotificationChanged = false;
    var bookmarkChanged = false;
    if (_notifications[instance.url] case final feed?) {
      final updated = feed.withRead(notification.id);
      if (!identical(updated, feed)) {
        _notifications[instance.url] = updated;
        notificationChanged = true;
      }
    }
    if (_replyNotifications[instance.url] case final feed?) {
      final updated = feed.withRead(notification.id);
      if (!identical(updated, feed)) {
        _replyNotifications[instance.url] = updated;
        replyNotificationChanged = true;
      }
    }
    if (_chatNotifications[instance.url] case final feed?) {
      final updated = feed.withRead(notification.id);
      if (!identical(updated, feed)) {
        _chatNotifications[instance.url] = updated;
        chatNotificationChanged = true;
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
    if (replyNotificationChanged) _replyNotificationChanges.changed();
    if (chatNotificationChanged) _chatNotificationChanges.changed();
    if (bookmarkChanged) _bookmarkChanges.changed();
    if (notificationChanged ||
        replyNotificationChanged ||
        chatNotificationChanged ||
        bookmarkChanged) {
      notifySafely();
    }

    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      final key = (instance.url, notification.id);
      if (!_ownsRequest(lease, _notificationReadRequests[key], request)) {
        return;
      }
      if (apiKey == null) {
        _discardLocalRead(instance.url, notification.id);
        return;
      }
      await api.markNotificationRead(
        siteUrl: instance.url,
        apiKey: apiKey,
        id: notification.id,
      );
    } catch (error, stackTrace) {
      final key = (instance.url, notification.id);
      if (!_ownsRequest(lease, _notificationReadRequests[key], request)) {
        return;
      }
      _discardLocalRead(instance.url, notification.id);
      _report(error, stackTrace, 'account.markNotificationRead');
      return;
    }

    final key = (instance.url, notification.id);
    if (!_ownsRequest(lease, _notificationReadRequests[key], request)) return;
    await refresh(instance, force: true);
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
    final hadReplyNotifications = _replyNotifications.remove(siteUrl) != null;
    final hadChatNotifications = _chatNotifications.remove(siteUrl) != null;
    final hadBookmarks = _bookmarks.remove(siteUrl) != null;
    _totalsRequests.remove(siteUrl);
    _totalsAttemptedAt.remove(siteUrl);
    final abandonedTotals = _totalsTasks.remove(siteUrl);
    abandonedTotals?.ignore();
    _pendingTotals.remove(siteUrl);
    _pendingTotalsWaiters.remove(siteUrl)?.complete(null);
    _notificationRequests.remove(siteUrl);
    _replyNotificationRequests.remove(siteUrl);
    _chatNotificationRequests.remove(siteUrl);
    _bookmarkRequests.remove(siteUrl);
    _notificationReadRequests.removeWhere((key, _) => key.$1 == siteUrl);
    _locallyReadNotificationIds.remove(siteUrl);
    final changed =
        hadTotals ||
        hadNotifications ||
        hadReplyNotifications ||
        hadChatNotifications ||
        hadBookmarks;
    if (hadTotals) _totalsChanges.changed();
    if (hadNotifications) _notificationChanges.changed();
    if (hadReplyNotifications) _replyNotificationChanges.changed();
    if (hadChatNotifications) _chatNotificationChanges.changed();
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

  void _notifyReplyNotifications() {
    _replyNotificationChanges.changed();
    notifySafely();
  }

  void _notifyChatNotifications() {
    _chatNotificationChanges.changed();
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

  bool _ownsRequest(SiteLease lease, Object? held, Object request) =>
      !isDisposed && lease.isCurrent && identical(held, request);

  List<DiscourseNotification> _preservingLocalReads(
    String siteUrl,
    List<DiscourseNotification> notifications,
  ) {
    final readIds = _locallyReadNotificationIds[siteUrl];
    if (readIds == null || readIds.isEmpty) return notifications;

    List<DiscourseNotification>? updated;
    for (var index = 0; index < notifications.length; index++) {
      final notification = notifications[index];
      if (notification.isUnread && readIds.contains(notification.id)) {
        updated ??= List<DiscourseNotification>.of(notifications);
        updated[index] = notification.asRead();
      }
    }
    return updated ?? notifications;
  }

  void _discardLocalRead(String siteUrl, int notificationId) {
    final readIds = _locallyReadNotificationIds[siteUrl];
    if (readIds == null) return;
    readIds.remove(notificationId);
    if (readIds.isEmpty) _locallyReadNotificationIds.remove(siteUrl);
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
    for (final waiter in _pendingTotalsWaiters.values) {
      if (!waiter.isCompleted) waiter.complete(null);
    }
    _pendingTotalsWaiters.clear();
    _pendingTotals.clear();
    _totalsTasks.clear();
    _notificationReadRequests.clear();
    _locallyReadNotificationIds.clear();
    _totalsChanges.dispose();
    _notificationChanges.dispose();
    _replyNotificationChanges.dispose();
    _chatNotificationChanges.dispose();
    _bookmarkChanges.dispose();
    super.dispose();
  }
}

final class _ActivityAspect extends FrameSafeNotifier {
  void changed() => notifySafely();
}
