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
import '../models/user_activity_feed.dart';
import '../plugin_api/notification_counters.dart';
import '../plugin_api/notification_feed_host.dart';

typedef TotalsLoaded =
    void Function(DiscourseInstance instance, NotificationTotals totals);
typedef TotalsChanged =
    void Function(String siteUrl, NotificationTotals totals);

final class AccountActivityController extends FrameSafeNotifier {
  AccountActivityController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    this.onTotalsLoaded,
    this.onTotalsChanged,
    this.minimumRefreshInterval = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : assert(minimumRefreshInterval >= Duration.zero),
       _clock = clock ?? DateTime.now;

  final AccountActivityApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;
  final TotalsLoaded? onTotalsLoaded;
  final TotalsChanged? onTotalsChanged;
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
  final Map<PluginNotificationFeedId, _PluginNotificationState>
  _pluginNotifications = {};
  final Map<PluginNotificationFeedId, PluginNotificationFeedSource>
  _pluginNotificationSources = {};
  final _bookmarkChanges = _ActivityAspect();
  final _userActivityChanges = _ActivityAspect();

  Listenable get totalsListenable => _totalsChanges;
  Listenable get notificationsListenable => _notificationChanges;
  Listenable get replyNotificationsListenable => _replyNotificationChanges;
  Listenable get bookmarksListenable => _bookmarkChanges;
  Listenable get userActivityListenable => _userActivityChanges;

  final Map<String, NotificationTotals> _totals = {};
  final Map<String, NotificationFeed> _notifications = {};
  final Map<String, NotificationFeed> _replyNotifications = {};
  final Map<String, BookmarkFeed> _bookmarks = {};
  final Map<String, UserActivityFeed> _userActivity = {};
  final Map<String, Object> _totalsRequests = {};
  final Map<String, Future<NotificationTotals?>> _totalsTasks = {};
  final Map<String, DateTime> _totalsAttemptedAt = {};
  final Map<String, DiscourseInstance> _pendingTotals = {};
  final Map<String, Completer<NotificationTotals?>> _pendingTotalsWaiters = {};
  final Map<String, Completer<NotificationTotals?>> _replayingTotalsWaiters =
      {};
  final Map<String, Future<void>> _notificationTasks = {};
  final Map<String, Future<void>> _replyNotificationTasks = {};
  final Map<String, Future<void>> _bookmarkTasks = {};
  final Map<String, Future<void>> _userActivityTasks = {};
  final Map<String, DiscourseInstance> _pendingBookmarks = {};
  final Map<String, Completer<void>> _pendingBookmarkWaiters = {};
  final Map<String, Completer<void>> _replayingBookmarkWaiters = {};
  final Map<String, Object> _notificationRequests = {};
  final Map<String, Object> _replyNotificationRequests = {};
  final Map<String, Object> _bookmarkRequests = {};
  final Map<String, Object> _userActivityRequests = {};
  final Map<(String, int), Object> _notificationReadRequests = {};
  final Map<String, Set<int>> _locallyReadNotificationIds = {};

  NotificationTotals? totalsFor(String siteUrl) => _totals[siteUrl];

  void restoreTotals(String siteUrl, NotificationTotals totals) {
    if (isDisposed) return;
    _totals[siteUrl] = totals;
  }

  NotificationFeed notificationsFor(String? siteUrl) => siteUrl == null
      ? const NotificationFeed()
      : _notifications[siteUrl] ?? const NotificationFeed();

  NotificationFeed replyNotificationsFor(String? siteUrl) => siteUrl == null
      ? const NotificationFeed()
      : _replyNotifications[siteUrl] ?? const NotificationFeed();

  Listenable pluginNotificationsListenable(PluginNotificationFeedId id) =>
      _pluginNotificationState(id).changes;

  NotificationFeed pluginNotificationsFor(
    PluginNotificationFeedId id,
    String? siteUrl,
  ) => siteUrl == null
      ? const NotificationFeed()
      : _pluginNotificationState(id).feeds[siteUrl] ?? const NotificationFeed();

  BookmarkFeed bookmarksFor(String? siteUrl) => siteUrl == null
      ? const BookmarkFeed()
      : _bookmarks[siteUrl] ?? const BookmarkFeed();

  UserActivityFeed userActivityFor(String? siteUrl) => siteUrl == null
      ? const UserActivityFeed()
      : _userActivity[siteUrl] ?? const UserActivityFeed();

  static const int userActivityPageSize = 30;

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
            ? NotificationTotals.mergeRefresh(
                response: totals,
                before: before,
                live: current,
              )
            : totals;
        applied = resolved;
        if (current != resolved) {
          _totals[instance.url] = resolved;
          _notifyTotals(instance.url, resolved);
        }
        // Publishing can synchronously dispose this owner through a listener.
        // Do not let its post-load hook start work for a replacement shell.
        if (!isDisposed) onTotalsLoaded?.call(instance, resolved);
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

    _replayingTotalsWaiters[siteUrl] = waiter;
    final replay = _startTotalsRefresh(pending);
    unawaited(
      replay.then<void>(
        (totals) {
          if (identical(_replayingTotalsWaiters[siteUrl], waiter)) {
            _replayingTotalsWaiters.remove(siteUrl);
          }
          if (!waiter.isCompleted) waiter.complete(totals);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (identical(_replayingTotalsWaiters[siteUrl], waiter)) {
            _replayingTotalsWaiters.remove(siteUrl);
          }
          if (!waiter.isCompleted) waiter.completeError(error, stackTrace);
        },
      ),
    );
  }

  Future<void> loadNotifications(DiscourseInstance instance) =>
      _coalescedActivityLoad(
        instance.url,
        tasks: _notificationTasks,
        start: () => _loadNotificationFeed(
          instance,
          feeds: _notifications,
          requests: _notificationRequests,
          fetch: (apiKey) =>
              api.notifications(siteUrl: instance.url, apiKey: apiKey),
          reconnectMessage:
              'Reconnect to ${instance.host} to see notifications.',
          failureMessage: "Couldn't load notifications from ${instance.host}.",
          operation: 'account.loadNotifications',
          notify: _notifyNotifications,
        ),
      );

  Future<void> loadReplyNotifications(DiscourseInstance instance) =>
      _coalescedActivityLoad(
        instance.url,
        tasks: _replyNotificationTasks,
        start: () => _loadNotificationFeed(
          instance,
          feeds: _replyNotifications,
          requests: _replyNotificationRequests,
          fetch: (apiKey) => api.notifications(
            siteUrl: instance.url,
            apiKey: apiKey,
            filterByTypes: userMenuReplyNotificationTypes,
          ),
          reconnectMessage: 'Reconnect to ${instance.host} to see replies.',
          failureMessage: "Couldn't load replies from ${instance.host}.",
          operation: 'account.loadReplyNotifications',
          notify: _notifyReplyNotifications,
        ),
      );

  Future<void> loadPluginNotifications(
    DiscourseInstance instance,
    PluginNotificationFeedSource source,
  ) {
    final registered = _pluginNotificationSources[source.id];
    if (registered != null && registered != source) {
      return Future<void>.error(
        StateError('Conflicting notification feed ${source.id.id}.'),
      );
    }
    _pluginNotificationSources[source.id] = source;
    final state = _pluginNotificationState(source.id);
    return _coalescedActivityLoad(
      instance.url,
      tasks: state.tasks,
      start: () => _loadNotificationFeed(
        instance,
        feeds: state.feeds,
        requests: state.requests,
        fetch: (apiKey) => api.notifications(
          siteUrl: instance.url,
          apiKey: apiKey,
          filterByTypes: source.filterByTypes,
        ),
        reconnectMessage: source.reconnectMessage,
        failureMessage: source.failureMessage,
        operation: 'account.loadPluginNotifications.${source.id.id}',
        notify: state.notify,
      ),
    );
  }

  _PluginNotificationState _pluginNotificationState(
    PluginNotificationFeedId id,
  ) => _pluginNotifications.putIfAbsent(
    id,
    () => _PluginNotificationState(notifySafely),
  );

  Future<void> _coalescedActivityLoad(
    String siteUrl, {
    required Map<String, Future<void>> tasks,
    required Future<void> Function() start,
  }) {
    if (isDisposed) return Future<void>.value();
    final active = tasks[siteUrl];
    if (active != null) return active;

    final result = Completer<void>();
    final task = result.future;
    // Publish the shared future before [start]. Loading state notifications can
    // synchronously re-enter through a listener, and that caller must join the
    // same task rather than start a duplicate request.
    tasks[siteUrl] = task;

    void finish([Object? error, StackTrace? stackTrace]) {
      if (identical(tasks[siteUrl], task)) {
        final _ = tasks.remove(siteUrl);
      }
      if (result.isCompleted) return;
      if (error == null) {
        result.complete();
      } else {
        result.completeError(error, stackTrace!);
      }
    }

    try {
      unawaited(
        start().then<void>(
          (_) => finish(),
          onError: (Object error, StackTrace stackTrace) =>
              finish(error, stackTrace),
        ),
      );
    } catch (error, stackTrace) {
      finish(error, stackTrace);
    }
    return task;
  }

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

  Future<void> loadBookmarks(DiscourseInstance instance, {bool force = false}) {
    final active = _bookmarkTasks[instance.url];
    if (active != null) {
      if (!force) return active;
      _pendingBookmarks[instance.url] = instance;
      return _pendingBookmarkWaiters
          .putIfAbsent(instance.url, Completer<void>.new)
          .future;
    }
    return _startBookmarksLoad(instance);
  }

  Future<void> _startBookmarksLoad(DiscourseInstance instance) {
    final result = Completer<void>();
    final task = result.future;
    _bookmarkTasks[instance.url] = task;
    try {
      unawaited(
        _loadBookmarks(instance).then<void>(
          (_) {
            _finishBookmarksLoad(instance.url, task);
            if (!result.isCompleted) result.complete();
          },
          onError: (Object error, StackTrace stackTrace) {
            _finishBookmarksLoad(instance.url, task);
            if (!result.isCompleted) result.completeError(error, stackTrace);
          },
        ),
      );
    } catch (error, stackTrace) {
      _finishBookmarksLoad(instance.url, task);
      result.completeError(error, stackTrace);
    }
    return task;
  }

  void _finishBookmarksLoad(String siteUrl, Future<void> task) {
    if (!identical(_bookmarkTasks[siteUrl], task)) return;
    final _ = _bookmarkTasks.remove(siteUrl);
    final pending = _pendingBookmarks.remove(siteUrl);
    final waiter = _pendingBookmarkWaiters.remove(siteUrl);
    if (pending == null || waiter == null || isDisposed) {
      if (waiter != null && !waiter.isCompleted) waiter.complete();
      return;
    }

    _replayingBookmarkWaiters[siteUrl] = waiter;
    final replay = _startBookmarksLoad(pending);
    unawaited(
      replay.then<void>(
        (_) {
          if (identical(_replayingBookmarkWaiters[siteUrl], waiter)) {
            _replayingBookmarkWaiters.remove(siteUrl);
          }
          if (!waiter.isCompleted) waiter.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (identical(_replayingBookmarkWaiters[siteUrl], waiter)) {
            _replayingBookmarkWaiters.remove(siteUrl);
          }
          if (!waiter.isCompleted) waiter.completeError(error, stackTrace);
        },
      ),
    );
  }

  Future<void> _loadBookmarks(DiscourseInstance instance) async {
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

  Future<void> loadUserActivity(
    DiscourseInstance instance, {
    bool refresh = false,
    bool loadMore = false,
  }) {
    assert(!(refresh && loadMore));
    if (isDisposed || !instance.isConnected) return Future<void>.value();

    final siteUrl = instance.url;
    final held = userActivityFor(siteUrl);
    if (!refresh && !loadMore && held.loaded) return Future<void>.value();
    if (loadMore && (!held.loaded || !held.hasMore)) {
      return Future<void>.value();
    }

    final active = _userActivityTasks[siteUrl];
    if (active != null && !refresh) return active;

    final replace = refresh || !held.loaded;
    final request = Object();
    final lease = lifecycle.capture(siteUrl);
    final offset = replace ? 0 : held.nextOffset;
    final result = Completer<void>();
    final task = result.future;
    _userActivityRequests[siteUrl] = request;
    _userActivityTasks[siteUrl] = task;
    _userActivity[siteUrl] = held.loadingPage(replace: replace);

    void finish([Object? error, StackTrace? stackTrace]) {
      if (identical(_userActivityTasks[siteUrl], task)) {
        final _ = _userActivityTasks.remove(siteUrl);
      }
      if (result.isCompleted) return;
      if (error == null) {
        result.complete();
      } else {
        result.completeError(error, stackTrace!);
      }
    }

    _notifyUserActivity();
    // Publishing loading state can synchronously dispose this controller.
    // Do not cross into credential storage for its replacement generation.
    if (!_ownsRequest(lease, _userActivityRequests[siteUrl], request)) {
      finish();
      return task;
    }

    try {
      unawaited(
        _loadUserActivityPage(
          instance,
          lease: lease,
          request: request,
          offset: offset,
          replace: replace,
        ).then<void>(
          (_) => finish(),
          onError: (Object error, StackTrace stackTrace) =>
              finish(error, stackTrace),
        ),
      );
    } catch (error, stackTrace) {
      finish(error, stackTrace);
    }
    return task;
  }

  Future<void> _loadUserActivityPage(
    DiscourseInstance instance, {
    required SiteLease lease,
    required Object request,
    required int offset,
    required bool replace,
  }) async {
    final siteUrl = instance.url;
    final username = instance.user?.username;
    if (username == null) return;

    void fail(String message) {
      final held = userActivityFor(siteUrl);
      _userActivity[siteUrl] = held.withError(message, retryFromStart: replace);
    }

    try {
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (!_ownsRequest(lease, _userActivityRequests[siteUrl], request)) {
        return;
      }
      if (apiKey == null) {
        _commit(lease, () {
          if (!identical(_userActivityRequests[siteUrl], request)) return;
          fail('Reconnect to ${instance.host} to see your activity.');
          _notifyUserActivity();
        });
        return;
      }
      final page = await api.userActivity(
        siteUrl: siteUrl,
        apiKey: apiKey,
        username: username,
        offset: offset,
        limit: userActivityPageSize,
      );
      _commit(lease, () {
        if (!identical(_userActivityRequests[siteUrl], request)) return;
        _userActivity[siteUrl] = userActivityFor(
          siteUrl,
        ).withPage(page, limit: userActivityPageSize, replace: replace);
        _notifyUserActivity();
      });
    } on SiteLookupException catch (error, stackTrace) {
      if (!_ownsRequest(lease, _userActivityRequests[siteUrl], request)) {
        return;
      }
      _report(error, stackTrace, 'account.loadUserActivity');
      _commit(lease, () {
        if (!identical(_userActivityRequests[siteUrl], request)) return;
        fail(
          error.failure == SiteLookupFailure.notDiscourse
              ? 'Not allowed — try reconnecting to ${instance.host}.'
              : "Couldn't reach ${instance.host}.",
        );
        _notifyUserActivity();
      });
    } catch (error, stackTrace) {
      if (!_ownsRequest(lease, _userActivityRequests[siteUrl], request)) {
        return;
      }
      _report(error, stackTrace, 'account.loadUserActivity');
      _commit(lease, () {
        if (!identical(_userActivityRequests[siteUrl], request)) return;
        fail("Couldn't load activity from ${instance.host}.");
        _notifyUserActivity();
      });
    } finally {
      _commit(lease, () {
        if (identical(_userActivityRequests[siteUrl], request)) {
          _userActivityRequests.remove(siteUrl);
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
    final pluginNotificationChanges = <_PluginNotificationState>[];
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
    for (final state in _pluginNotifications.values) {
      if (state.feeds[instance.url] case final feed?) {
        final updated = feed.withRead(notification.id);
        if (!identical(updated, feed)) {
          state.feeds[instance.url] = updated;
          pluginNotificationChanges.add(state);
        }
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
    for (final state in pluginNotificationChanges) {
      state.changes.changed();
    }
    if (bookmarkChanged) _bookmarkChanges.changed();
    if (notificationChanged ||
        replyNotificationChanged ||
        pluginNotificationChanges.isNotEmpty ||
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
    _notifyTotals(siteUrl, updated);
  }

  void applyPluginCounter(
    String siteUrl,
    PluginNotificationCounter counter,
    int Function(int current) reduce,
  ) {
    applyCounts(siteUrl, (held) => held.updatePluginCounter(counter, reduce));
  }

  void forget(String siteUrl) {
    if (isDisposed) return;
    final hadTotals = _totals.remove(siteUrl) != null;
    final hadNotifications = _notifications.remove(siteUrl) != null;
    final hadReplyNotifications = _replyNotifications.remove(siteUrl) != null;
    var hadPluginNotifications = false;
    for (final state in _pluginNotifications.values) {
      final changed = state.feeds.remove(siteUrl) != null;
      hadPluginNotifications |= changed;
      state.tasks.remove(siteUrl)?.ignore();
      state.requests.remove(siteUrl);
      if (changed) state.changes.changed();
    }
    final hadBookmarks = _bookmarks.remove(siteUrl) != null;
    final hadUserActivity = _userActivity.remove(siteUrl) != null;
    _totalsRequests.remove(siteUrl);
    _totalsAttemptedAt.remove(siteUrl);
    final abandonedTotals = _totalsTasks.remove(siteUrl);
    abandonedTotals?.ignore();
    _pendingTotals.remove(siteUrl);
    _pendingTotalsWaiters.remove(siteUrl)?.complete(null);
    final replayingTotalsWaiter = _replayingTotalsWaiters.remove(siteUrl);
    if (replayingTotalsWaiter != null && !replayingTotalsWaiter.isCompleted) {
      replayingTotalsWaiter.complete(null);
    }
    _notificationTasks.remove(siteUrl)?.ignore();
    _replyNotificationTasks.remove(siteUrl)?.ignore();
    _bookmarkTasks.remove(siteUrl)?.ignore();
    _userActivityTasks.remove(siteUrl)?.ignore();
    _pendingBookmarks.remove(siteUrl);
    _pendingBookmarkWaiters.remove(siteUrl)?.complete();
    final replayingBookmarkWaiter = _replayingBookmarkWaiters.remove(siteUrl);
    if (replayingBookmarkWaiter != null &&
        !replayingBookmarkWaiter.isCompleted) {
      replayingBookmarkWaiter.complete();
    }
    _notificationRequests.remove(siteUrl);
    _replyNotificationRequests.remove(siteUrl);
    _bookmarkRequests.remove(siteUrl);
    _userActivityRequests.remove(siteUrl);
    _notificationReadRequests.removeWhere((key, _) => key.$1 == siteUrl);
    _locallyReadNotificationIds.remove(siteUrl);
    final changed =
        hadTotals ||
        hadNotifications ||
        hadReplyNotifications ||
        hadPluginNotifications ||
        hadBookmarks ||
        hadUserActivity;
    if (hadTotals) _totalsChanges.changed();
    if (hadNotifications) _notificationChanges.changed();
    if (hadReplyNotifications) _replyNotificationChanges.changed();
    if (hadBookmarks) _bookmarkChanges.changed();
    if (hadUserActivity) _userActivityChanges.changed();
    if (changed) notifySafely();
  }

  void _notifyTotals(String siteUrl, NotificationTotals totals) {
    onTotalsChanged?.call(siteUrl, totals);
    if (isDisposed) return;
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

  void _notifyBookmarks() {
    _bookmarkChanges.changed();
    notifySafely();
  }

  void _notifyUserActivity() {
    _userActivityChanges.changed();
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

  @override
  void dispose() {
    for (final waiter in _pendingTotalsWaiters.values) {
      if (!waiter.isCompleted) waiter.complete(null);
    }
    for (final waiter in _replayingTotalsWaiters.values) {
      if (!waiter.isCompleted) waiter.complete(null);
    }
    for (final waiter in _pendingBookmarkWaiters.values) {
      if (!waiter.isCompleted) waiter.complete();
    }
    for (final waiter in _replayingBookmarkWaiters.values) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _pendingTotalsWaiters.clear();
    _replayingTotalsWaiters.clear();
    _pendingTotals.clear();
    _pendingBookmarkWaiters.clear();
    _replayingBookmarkWaiters.clear();
    _pendingBookmarks.clear();
    _totalsTasks.clear();
    _notificationTasks.clear();
    _replyNotificationTasks.clear();
    for (final state in _pluginNotifications.values) {
      for (final task in state.tasks.values) {
        task.ignore();
      }
      state.dispose();
    }
    _pluginNotifications.clear();
    _pluginNotificationSources.clear();
    _bookmarkTasks.clear();
    _userActivityTasks.clear();
    _totalsRequests.clear();
    _notificationRequests.clear();
    _replyNotificationRequests.clear();
    _bookmarkRequests.clear();
    _userActivityRequests.clear();
    _notificationReadRequests.clear();
    _locallyReadNotificationIds.clear();
    _totalsChanges.dispose();
    _notificationChanges.dispose();
    _replyNotificationChanges.dispose();
    _bookmarkChanges.dispose();
    _userActivityChanges.dispose();
    super.dispose();
  }
}

final class _ActivityAspect extends FrameSafeNotifier {
  void changed() => notifySafely();
}

final class _PluginNotificationState {
  _PluginNotificationState(this._notifyOwner);

  final VoidCallback _notifyOwner;
  final _ActivityAspect changes = _ActivityAspect();
  final Map<String, NotificationFeed> feeds = {};
  final Map<String, Future<void>> tasks = {};
  final Map<String, Object> requests = {};

  void notify() {
    changes.changed();
    _notifyOwner();
  }

  void dispose() => changes.dispose();
}
