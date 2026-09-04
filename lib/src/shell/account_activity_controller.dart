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
import '../models/notification_totals.dart';
import '../models/notification_type_counts.dart';
import '../models/user_activity_feed.dart';
import '../plugin_api/notification_counters.dart';
import '../plugin_api/notification_feed_host.dart';

typedef TotalsLoaded =
    void Function(DiscourseInstance instance, NotificationTotals totals);
typedef TotalsChanged =
    void Function(String siteUrl, NotificationTotals totals);
typedef GroupedUnreadAuthorityAdvanced = void Function(String siteUrl);
typedef OtherNotificationTypes =
    Future<List<NotificationTypeName>> Function(String apiKey);

typedef _GroupedUnreadAuthorityToken = ({
  int snapshotRevision,
  Map<NotificationTypeId, int> typeRevisions,
});

final class AccountActivityController extends FrameSafeNotifier {
  AccountActivityController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    this.onTotalsLoaded,
    this.onTotalsChanged,
    this.onGroupedUnreadAuthorityAdvanced,
    this.minimumRefreshInterval = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : assert(minimumRefreshInterval >= Duration.zero),
       _clock = clock ?? DateTime.now;

  final AccountActivityApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;
  final TotalsLoaded? onTotalsLoaded;
  final TotalsChanged? onTotalsChanged;
  final GroupedUnreadAuthorityAdvanced? onGroupedUnreadAuthorityAdvanced;
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
  final _likeNotificationChanges = _ActivityAspect();
  final _otherNotificationChanges = _ActivityAspect();
  final Map<PluginNotificationFeedId, _PluginNotificationState>
  _pluginNotifications = {};
  final Map<PluginNotificationFeedId, PluginNotificationFeedSource>
  _pluginNotificationSources = {};
  final _bookmarkChanges = _ActivityAspect();
  final _userActivityChanges = _ActivityAspect();

  Listenable get totalsListenable => _totalsChanges;
  Listenable get notificationsListenable => _notificationChanges;
  Listenable get replyNotificationsListenable => _replyNotificationChanges;
  Listenable get likeNotificationsListenable => _likeNotificationChanges;
  Listenable get otherNotificationsListenable => _otherNotificationChanges;
  Listenable get bookmarksListenable => _bookmarkChanges;
  Listenable get userActivityListenable => _userActivityChanges;

  final Map<String, NotificationTotals> _totals = {};
  final Map<String, NotificationFeed> _notifications = {};
  final Map<String, NotificationFeed> _replyNotifications = {};
  final Map<String, NotificationFeed> _likeNotifications = {};
  final Map<String, NotificationFeed> _otherNotifications = {};
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
  final Map<String, Future<void>> _likeNotificationTasks = {};
  final Map<String, Future<void>> _otherNotificationTasks = {};
  final Map<String, Future<void>> _bookmarkTasks = {};
  final Map<String, Future<void>> _userActivityTasks = {};
  final Map<String, DiscourseInstance> _pendingBookmarks = {};
  final Map<String, Completer<void>> _pendingBookmarkWaiters = {};
  final Map<String, Completer<void>> _replayingBookmarkWaiters = {};
  final Map<String, Object> _notificationRequests = {};
  final Map<String, Object> _replyNotificationRequests = {};
  final Map<String, Object> _likeNotificationRequests = {};
  final Map<String, Object> _otherNotificationRequests = {};
  final Map<String, Object> _bookmarkRequests = {};
  final Map<String, Object> _userActivityRequests = {};
  final Map<(String, int), Object> _notificationReadRequests = {};
  final Map<String, Set<int>> _locallyReadNotificationIds = {};
  final Map<(String, int), int> _notificationRowAuthorityRevisions = {};
  final Map<(String, PluginNotificationFeedId), Future<void>>
  _pluginNotificationDismissTasks = {};
  final Map<String, int> _groupedUnreadSnapshotRevisions = {};
  final Map<(String, NotificationTypeId), int> _groupedUnreadTypeRevisions = {};

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

  NotificationFeed likeNotificationsFor(String? siteUrl) => siteUrl == null
      ? const NotificationFeed()
      : _likeNotifications[siteUrl] ?? const NotificationFeed();

  NotificationFeed otherNotificationsFor(String? siteUrl) => siteUrl == null
      ? const NotificationFeed()
      : _otherNotifications[siteUrl] ?? const NotificationFeed();

  Listenable pluginNotificationsListenable(PluginNotificationFeedId id) =>
      _pluginNotificationState(id).changes;

  NotificationFeed pluginNotificationsFor(
    PluginNotificationFeedId id,
    String? siteUrl,
  ) => siteUrl == null
      ? const NotificationFeed()
      : _pluginNotificationState(id).feeds[siteUrl] ?? const NotificationFeed();

  bool hasTrackedPluginNotifications(String siteUrl) =>
      _pluginNotifications.values.any(
        (state) =>
            state.feeds.containsKey(siteUrl) ||
            state.tasks.containsKey(siteUrl),
      );

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
          if (resolved.groupedUnreadNotifications.isAvailable &&
              current?.groupedUnreadNotifications !=
                  resolved.groupedUnreadNotifications) {
            _advanceGroupedUnreadSnapshotAuthority(instance.url);
          }
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

  Future<void> loadLikeNotifications(DiscourseInstance instance) =>
      _coalescedActivityLoad(
        instance.url,
        tasks: _likeNotificationTasks,
        start: () => _loadNotificationFeed(
          instance,
          feeds: _likeNotifications,
          requests: _likeNotificationRequests,
          fetch: (apiKey) => api.notifications(
            siteUrl: instance.url,
            apiKey: apiKey,
            filterByTypes: userMenuLikeNotificationTypes,
          ),
          reconnectMessage: 'Reconnect to ${instance.host} to see likes.',
          failureMessage: "Couldn't load likes from ${instance.host}.",
          operation: 'account.loadLikeNotifications',
          notify: _notifyLikeNotifications,
        ),
      );

  Future<void> loadOtherNotifications(
    DiscourseInstance instance,
    OtherNotificationTypes resolveTypes,
  ) => _coalescedActivityLoad(
    instance.url,
    tasks: _otherNotificationTasks,
    start: () => _loadNotificationFeed(
      instance,
      feeds: _otherNotifications,
      requests: _otherNotificationRequests,
      fetch: (apiKey) async {
        final types = await resolveTypes(apiKey);
        if (types.isEmpty) return const [];
        return api.notifications(
          siteUrl: instance.url,
          apiKey: apiKey,
          filterByTypes: types,
        );
      },
      reconnectMessage:
          'Reconnect to ${instance.host} to see other notifications.',
      failureMessage:
          "Couldn't load other notifications from ${instance.host}.",
      operation: 'account.loadOtherNotifications',
      notify: _notifyOtherNotifications,
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
        fetch: (apiKey) async => source.arrange(
          await api.notifications(
            siteUrl: instance.url,
            apiKey: apiKey,
            filterByTypes: source.filterByTypes,
          ),
        ),
        reconnectMessage: source.reconnectMessage,
        failureMessage: source.failureMessage,
        operation: 'account.loadPluginNotifications.${source.id.id}',
        notify: state.notify,
      ),
    );
  }

  /// Re-fetches only plugin feeds which have an active request or have already
  /// published a state for this site. A live invalidation that overlaps an
  /// active fetch waits for it and then performs one newer read instead of
  /// joining a potentially stale response.
  Future<void> refreshLoadedPluginNotifications(
    DiscourseInstance instance,
  ) async {
    if (isDisposed || !instance.isConnected) return;
    final lease = lifecycle.capture(instance.url);
    final sources = List<PluginNotificationFeedSource>.of(
      _pluginNotificationSources.values,
    );
    await Future.wait([
      for (final source in sources)
        if (_pluginNotificationState(
              source.id,
            ).feeds.containsKey(instance.url) ||
            _pluginNotificationState(source.id).tasks.containsKey(instance.url))
          _refreshLoadedPluginNotifications(instance, source, lease),
    ]);
  }

  Future<void> _refreshLoadedPluginNotifications(
    DiscourseInstance instance,
    PluginNotificationFeedSource source,
    SiteLease lease,
  ) async {
    final state = _pluginNotificationState(source.id);
    final active = state.tasks[instance.url];
    if (active != null) await active;
    if (isDisposed || !lease.isCurrent) return;
    await loadPluginNotifications(instance, source);
  }

  Future<void> dismissPluginNotifications(
    DiscourseInstance instance,
    PluginNotificationFeedSource source,
  ) {
    if (source.dismissal == null) {
      return Future<void>.error(
        StateError(
          'Notification feed ${source.id.id} does not support dismissal.',
        ),
      );
    }
    final registered = _pluginNotificationSources[source.id];
    if (registered != null && registered != source) {
      return Future<void>.error(
        StateError('Conflicting notification feed ${source.id.id}.'),
      );
    }
    _pluginNotificationSources[source.id] = source;

    final key = (instance.url, source.id);
    final active = _pluginNotificationDismissTasks[key];
    if (active != null) return active;

    late final Future<void> task;
    task = _dismissPluginNotifications(instance, source).whenComplete(() {
      if (identical(_pluginNotificationDismissTasks[key], task)) {
        final _ = _pluginNotificationDismissTasks.remove(key);
      }
    });
    _pluginNotificationDismissTasks[key] = task;
    return task;
  }

  Future<void> _dismissPluginNotifications(
    DiscourseInstance instance,
    PluginNotificationFeedSource source,
  ) async {
    if (isDisposed || !instance.isConnected) return;
    final siteUrl = instance.url;
    final lease = lifecycle.capture(siteUrl);
    // A current-user snapshot which started before this write cannot be allowed
    // to restore its pre-write grouped counts. Publish another boundary after a
    // successful response so snapshots started while the write was in flight
    // are stale as well, including when the local bucket is absent or zero.
    onGroupedUnreadAuthorityAdvanced?.call(siteUrl);
    final dismissedTypeNames = List<NotificationTypeName>.unmodifiable(
      source.filterByTypes,
    );
    final dismissedTypeIds = <NotificationTypeId>{
      for (final type in source.dismissal!.notificationTypes)
        NotificationTypeId(type.wireId),
    };
    final authority = _captureGroupedUnreadAuthority(siteUrl, dismissedTypeIds);
    final cachedNotificationIds = _cachedPluginDismissNotificationIds(
      siteUrl,
      source,
    );

    try {
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (isDisposed || !lease.isCurrent) return;
      if (apiKey == null) {
        throw StateError(
          'Reconnect to ${instance.host} to dismiss notifications.',
        );
      }
      await api.markNotificationsRead(
        siteUrl: siteUrl,
        apiKey: apiKey,
        types: dismissedTypeNames,
      );
      if (isDisposed || !lease.isCurrent) return;

      onGroupedUnreadAuthorityAdvanced?.call(siteUrl);
      final newerAuthorityAccepted = !_groupedUnreadAuthorityIsCurrent(
        siteUrl,
        authority,
      );
      // A successful bulk write is an authoritative boundary for older
      // optimistic per-row reads. Advance it even when a newer MessageBus
      // count means this write must not clear the local grouped snapshot.
      _advanceGroupedUnreadTypeAuthorities(siteUrl, dismissedTypeIds);
      _advanceNotificationRowAuthorities(siteUrl, cachedNotificationIds);
      _markCachedNotificationIdsRead(siteUrl, cachedNotificationIds);
      if (!newerAuthorityAccepted) {
        _clearGroupedUnreadTypes(siteUrl, dismissedTypeIds);
      }

      // Mirror Discourse's user-menu dismiss action: reconcile the filtered
      // list authoritatively after the write. Only the pre-write cache snapshot
      // is locally pinned read, so a newer row received during the write stays
      // unread while this fetch resolves the final list.
      await _refreshLoadedPluginNotifications(instance, source, lease);

      // `/notifications/totals.json` does not currently return grouped type
      // counts. It is still useful for the aggregate unread total, while the
      // guarded mutation above reconciles the plugin badge without replacing
      // any newer live grouped-count snapshot.
      await refresh(instance, force: true);
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _report(
        error,
        stackTrace,
        'account.dismissPluginNotifications.${source.id.id}',
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
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
      // Rows that arrived while the request was out stay on screen.
      final current = feeds[instance.url];
      if (current != null && current.notifications.isNotEmpty) return;
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
      // Rows that arrived while the request was out stay on screen.
      final current = _bookmarks[instance.url];
      if (current != null && current.hasRows) return;
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
    final notificationKey = (instance.url, notification.id);
    final rowAuthorityRevision =
        _notificationRowAuthorityRevisions[notificationKey] ?? 0;
    final hadLocalRead =
        _locallyReadNotificationIds[instance.url]?.contains(notification.id) ==
        true;
    // Invalidate current-user snapshots on both sides of the write. This is
    // deliberately independent of the numeric optimistic decrement: a stale
    // snapshot must not resurrect a bucket which was absent or already zero.
    onGroupedUnreadAuthorityAdvanced?.call(instance.url);
    final groupedAuthority = _captureGroupedUnreadAuthority(instance.url, {
      notification.typeId,
    });
    final groupedCountDecremented = _adjustGroupedUnreadCount(
      instance.url,
      notification.typeId,
      -1,
    );
    _markCachedNotificationIdsRead(instance.url, {notification.id});

    void abandonOptimisticRead() {
      // Grouped snapshots and type-wide revisions say nothing about whether
      // this particular row was covered. Only a successful write whose
      // pre-write snapshot contained this ID supersedes its rollback.
      if (!hadLocalRead &&
          (_notificationRowAuthorityRevisions[notificationKey] ?? 0) ==
              rowAuthorityRevision) {
        _discardLocalRead(instance.url, notification.id);
        _markCachedNotificationIdsUnread(instance.url, {notification.id});
      }

      if (groupedCountDecremented &&
          _groupedUnreadAuthorityIsCurrent(instance.url, groupedAuthority)) {
        _adjustGroupedUnreadCount(instance.url, notification.typeId, 1);
      }
    }

    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      final key = (instance.url, notification.id);
      if (!_ownsRequest(lease, _notificationReadRequests[key], request)) {
        return;
      }
      if (apiKey == null) {
        abandonOptimisticRead();
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
      abandonOptimisticRead();
      _report(error, stackTrace, 'account.markNotificationRead');
      return;
    }

    final key = (instance.url, notification.id);
    if (!_ownsRequest(lease, _notificationReadRequests[key], request)) return;
    onGroupedUnreadAuthorityAdvanced?.call(instance.url);
    await refresh(instance, force: true);
  }

  Set<int> _cachedPluginDismissNotificationIds(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) {
    final names = source.filterByTypes.toSet();
    final typeIds = <NotificationTypeId>{
      for (final type
          in source.dismissal?.notificationTypes ??
              const <NotificationWireType>[])
        NotificationTypeId(type.wireId),
    };
    final notificationIds = <int>{};

    void collect(
      Iterable<DiscourseNotification> notifications, {
      bool trustedServerFilter = false,
    }) {
      for (final notification in notifications) {
        if (!trustedServerFilter &&
            !names.contains(notification.typeName) &&
            !typeIds.contains(notification.typeId)) {
          continue;
        }
        // Include matching rows already shown as read. One may be carrying an
        // optimistic per-row read which can still fail before this bulk write
        // succeeds; the successful bulk response must then re-pin that row.
        // The snapshot still excludes rows first received during the write.
        notificationIds.add(notification.id);
      }
    }

    if (_pluginNotificationState(source.id).feeds[siteUrl] case final feed?) {
      // This feed was fetched with exactly [source.filterByTypes], so its rows
      // remain useful even on servers which omit `notification_type_name`.
      collect(feed.notifications, trustedServerFilter: true);
    }
    if (_notifications[siteUrl] case final feed?) {
      collect(feed.notifications);
    }
    if (_replyNotifications[siteUrl] case final feed?) {
      collect(feed.notifications);
    }
    if (_likeNotifications[siteUrl] case final feed?) {
      collect(feed.notifications);
    }
    if (_otherNotifications[siteUrl] case final feed?) {
      collect(feed.notifications);
    }
    for (final state in _pluginNotifications.values) {
      if (state.feeds[siteUrl] case final feed?) {
        collect(feed.notifications);
      }
    }
    if (_bookmarks[siteUrl] case final feed?) collect(feed.reminders);
    return notificationIds;
  }

  void _markCachedNotificationIdsRead(String siteUrl, Set<int> ids) {
    if (ids.isEmpty) return;
    _locallyReadNotificationIds.putIfAbsent(siteUrl, () => <int>{}).addAll(ids);
    _markCachedNotificationIds(
      siteUrl,
      ids,
      markNotification: (feed, id) => feed.withRead(id),
      markBookmark: (feed, id) => feed.withRead(id),
    );
  }

  void _markCachedNotificationIdsUnread(String siteUrl, Set<int> ids) {
    if (ids.isEmpty) return;
    _markCachedNotificationIds(
      siteUrl,
      ids,
      markNotification: (feed, id) => feed.withUnread(id),
      markBookmark: (feed, id) => feed.withUnread(id),
    );
  }

  /// Walks every cached feed holding [siteUrl]'s rows, applies [markNotification]
  /// and [markBookmark] per id, and notifies exactly the aspects that changed.
  void _markCachedNotificationIds(
    String siteUrl,
    Set<int> ids, {
    required NotificationFeed Function(NotificationFeed feed, int id)
    markNotification,
    required BookmarkFeed Function(BookmarkFeed feed, int id) markBookmark,
  }) {
    NotificationFeed markFeed(NotificationFeed feed) {
      var updated = feed;
      for (final id in ids) {
        updated = markNotification(updated, id);
      }
      return updated;
    }

    var notificationChanged = false;
    var replyNotificationChanged = false;
    var likeNotificationChanged = false;
    var otherNotificationChanged = false;
    final pluginNotificationChanges = <_PluginNotificationState>[];
    var bookmarkChanged = false;
    if (_notifications[siteUrl] case final feed?) {
      final updated = markFeed(feed);
      if (!identical(updated, feed)) {
        _notifications[siteUrl] = updated;
        notificationChanged = true;
      }
    }
    if (_replyNotifications[siteUrl] case final feed?) {
      final updated = markFeed(feed);
      if (!identical(updated, feed)) {
        _replyNotifications[siteUrl] = updated;
        replyNotificationChanged = true;
      }
    }
    if (_likeNotifications[siteUrl] case final feed?) {
      final updated = markFeed(feed);
      if (!identical(updated, feed)) {
        _likeNotifications[siteUrl] = updated;
        likeNotificationChanged = true;
      }
    }
    if (_otherNotifications[siteUrl] case final feed?) {
      final updated = markFeed(feed);
      if (!identical(updated, feed)) {
        _otherNotifications[siteUrl] = updated;
        otherNotificationChanged = true;
      }
    }
    for (final state in _pluginNotifications.values) {
      if (state.feeds[siteUrl] case final feed?) {
        final updated = markFeed(feed);
        if (!identical(updated, feed)) {
          state.feeds[siteUrl] = updated;
          pluginNotificationChanges.add(state);
        }
      }
    }
    if (_bookmarks[siteUrl] case final feed?) {
      var updated = feed;
      for (final id in ids) {
        updated = markBookmark(updated, id);
      }
      if (!identical(updated, feed)) {
        _bookmarks[siteUrl] = updated;
        bookmarkChanged = true;
      }
    }
    if (notificationChanged) _notificationChanges.changed();
    if (replyNotificationChanged) _replyNotificationChanges.changed();
    if (likeNotificationChanged) _likeNotificationChanges.changed();
    if (otherNotificationChanged) _otherNotificationChanges.changed();
    for (final state in pluginNotificationChanges) {
      state.changes.changed();
    }
    if (bookmarkChanged) _bookmarkChanges.changed();
    if (notificationChanged ||
        replyNotificationChanged ||
        likeNotificationChanged ||
        otherNotificationChanged ||
        pluginNotificationChanges.isNotEmpty ||
        bookmarkChanged) {
      notifySafely();
    }
  }

  bool _adjustGroupedUnreadCount(
    String siteUrl,
    NotificationTypeId typeId,
    int delta,
  ) {
    final held = _totals[siteUrl];
    final counts = held?.groupedUnreadNotifications;
    final wire = counts?.toJson();
    if (held == null || wire == null) return false;

    final key = '${typeId.value}';
    final current = wire[key] ?? 0;
    final next = (current + delta).clamp(0, 0x7fffffff);
    if (next == current) return false;
    final updatedWire = Map<String, int>.of(wire);
    if (next == 0) {
      updatedWire.remove(key);
    } else {
      updatedWire[key] = next;
    }
    final updated = held.copyWith(
      groupedUnreadNotifications: NotificationTypeCounts.fromWire(updatedWire),
    );
    _totals[siteUrl] = updated;
    _notifyTotals(siteUrl, updated);
    return true;
  }

  void _clearGroupedUnreadTypes(
    String siteUrl,
    Set<NotificationTypeId> typeIds,
  ) {
    final held = _totals[siteUrl];
    final wire = held?.groupedUnreadNotifications.toJson();
    if (held == null || wire == null || wire.isEmpty) return;

    final updatedWire = Map<String, int>.of(wire);
    for (final typeId in typeIds) {
      updatedWire.remove('${typeId.value}');
    }
    if (mapEquals(updatedWire, wire)) return;
    final updated = held.copyWith(
      groupedUnreadNotifications: NotificationTypeCounts.fromWire(updatedWire),
    );
    _totals[siteUrl] = updated;
    _notifyTotals(siteUrl, updated);
  }

  void _advanceGroupedUnreadSnapshotAuthority(String siteUrl) {
    _groupedUnreadSnapshotRevisions.update(
      siteUrl,
      (revision) => revision + 1,
      ifAbsent: () => 1,
    );
  }

  _GroupedUnreadAuthorityToken _captureGroupedUnreadAuthority(
    String siteUrl,
    Set<NotificationTypeId> typeIds,
  ) => (
    snapshotRevision: _groupedUnreadSnapshotRevisions[siteUrl] ?? 0,
    typeRevisions: Map.unmodifiable({
      for (final typeId in typeIds)
        typeId: _groupedUnreadTypeRevisions[(siteUrl, typeId)] ?? 0,
    }),
  );

  bool _groupedUnreadAuthorityIsCurrent(
    String siteUrl,
    _GroupedUnreadAuthorityToken authority,
  ) =>
      (_groupedUnreadSnapshotRevisions[siteUrl] ?? 0) ==
          authority.snapshotRevision &&
      _groupedUnreadTypeAuthoritiesAreCurrent(siteUrl, authority);

  bool _groupedUnreadTypeAuthoritiesAreCurrent(
    String siteUrl,
    _GroupedUnreadAuthorityToken authority,
  ) => authority.typeRevisions.entries.every(
    (entry) =>
        (_groupedUnreadTypeRevisions[(siteUrl, entry.key)] ?? 0) == entry.value,
  );

  void _advanceGroupedUnreadTypeAuthorities(
    String siteUrl,
    Set<NotificationTypeId> typeIds,
  ) {
    for (final typeId in typeIds) {
      _groupedUnreadTypeRevisions.update(
        (siteUrl, typeId),
        (revision) => revision + 1,
        ifAbsent: () => 1,
      );
    }
  }

  void _advanceNotificationRowAuthorities(String siteUrl, Set<int> ids) {
    for (final id in ids) {
      _notificationRowAuthorityRevisions.update(
        (siteUrl, id),
        (revision) => revision + 1,
        ifAbsent: () => 1,
      );
    }
  }

  void applyCounts(
    String siteUrl,
    NotificationTotals Function(NotificationTotals held) fold,
  ) {
    if (isDisposed) return;
    final held = _totals[siteUrl] ?? const NotificationTotals();
    final updated = fold(held);
    if (updated == held) return;
    if (updated.groupedUnreadNotifications != held.groupedUnreadNotifications) {
      _advanceGroupedUnreadSnapshotAuthority(siteUrl);
    }
    _totals[siteUrl] = updated;
    _notifyTotals(siteUrl, updated);
  }

  void applyGroupedUnreadSnapshot(
    String siteUrl,
    NotificationTypeCounts counts,
  ) {
    if (isDisposed || !counts.isAvailable) return;
    // A complete current-user snapshot supersedes every older typed local
    // write, even when its numeric values happen to be identical.
    _advanceGroupedUnreadSnapshotAuthority(siteUrl);
    final held = _totals[siteUrl] ?? const NotificationTotals();
    final updated = held.withGroupedUnreadNotifications(counts);
    if (updated == held) return;
    _totals[siteUrl] = updated;
    _notifyTotals(siteUrl, updated);
  }

  void applyLiveNotificationState(String siteUrl, Object? data) {
    if (isDisposed) return;
    if (data is Map &&
        NotificationTypeCounts.fromWire(
          data['grouped_unread_notifications'],
        ).isAvailable) {
      // Every grouped snapshot is a new authority boundary, even when it has
      // the same numeric values. An older local write must not clear or roll
      // back counts after a newer live snapshot has been accepted.
      _advanceGroupedUnreadSnapshotAuthority(siteUrl);
    }
    final held = _totals[siteUrl] ?? const NotificationTotals();
    final updated = held.withNotification(data);
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
    final hadLikeNotifications = _likeNotifications.remove(siteUrl) != null;
    final hadOtherNotifications = _otherNotifications.remove(siteUrl) != null;
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
    _likeNotificationTasks.remove(siteUrl)?.ignore();
    _otherNotificationTasks.remove(siteUrl)?.ignore();
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
    _likeNotificationRequests.remove(siteUrl);
    _otherNotificationRequests.remove(siteUrl);
    _bookmarkRequests.remove(siteUrl);
    _userActivityRequests.remove(siteUrl);
    _notificationReadRequests.removeWhere((key, _) => key.$1 == siteUrl);
    _locallyReadNotificationIds.remove(siteUrl);
    _notificationRowAuthorityRevisions.removeWhere(
      (key, _) => key.$1 == siteUrl,
    );
    _pluginNotificationDismissTasks.removeWhere((key, task) {
      if (key.$1 != siteUrl) return false;
      task.ignore();
      return true;
    });
    _groupedUnreadSnapshotRevisions.remove(siteUrl);
    _groupedUnreadTypeRevisions.removeWhere((key, _) => key.$1 == siteUrl);
    final changed =
        hadTotals ||
        hadNotifications ||
        hadReplyNotifications ||
        hadLikeNotifications ||
        hadOtherNotifications ||
        hadPluginNotifications ||
        hadBookmarks ||
        hadUserActivity;
    if (hadTotals) _totalsChanges.changed();
    if (hadNotifications) _notificationChanges.changed();
    if (hadReplyNotifications) _replyNotificationChanges.changed();
    if (hadLikeNotifications) _likeNotificationChanges.changed();
    if (hadOtherNotifications) _otherNotificationChanges.changed();
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

  void _notifyLikeNotifications() {
    _likeNotificationChanges.changed();
    notifySafely();
  }

  void _notifyOtherNotifications() {
    _otherNotificationChanges.changed();
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
    _likeNotificationTasks.clear();
    _otherNotificationTasks.clear();
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
    _likeNotificationRequests.clear();
    _otherNotificationRequests.clear();
    _bookmarkRequests.clear();
    _userActivityRequests.clear();
    _notificationReadRequests.clear();
    _locallyReadNotificationIds.clear();
    _notificationRowAuthorityRevisions.clear();
    _pluginNotificationDismissTasks.clear();
    _groupedUnreadSnapshotRevisions.clear();
    _groupedUnreadTypeRevisions.clear();
    _totalsChanges.dispose();
    _notificationChanges.dispose();
    _replyNotificationChanges.dispose();
    _likeNotificationChanges.dispose();
    _otherNotificationChanges.dispose();
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
