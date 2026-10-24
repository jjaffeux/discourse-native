import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';

import '../foundation/frame_safe_notifier.dart';
import '../models/bookmark_feed.dart';
import '../models/discourse_instance.dart';
import '../models/json.dart';
import '../models/notification.dart';
import '../models/notification_totals.dart';
import '../models/notification_type_counts.dart';
import '../models/user_activity_feed.dart';
import '../plugin_api/notification_counters.dart';
import '../plugin_api/notification_feed_host.dart';
import 'account_history_feed_owners.dart';
import 'notification_reconciliation.dart';

typedef TotalsLoaded =
    void Function(DiscourseInstance instance, NotificationTotals totals);
typedef TotalsChanged =
    void Function(String siteUrl, NotificationTotals totals);
typedef GroupedUnreadAuthorityAdvanced = void Function(String siteUrl);
typedef OtherNotificationTypes =
    Future<List<NotificationTypeName>> Function(String apiKey);

final class AccountActivityController extends FrameSafeNotifier {
  AccountActivityController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    this.likeNotificationTypes = userMenuLikeNotificationTypes,
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
  final List<NotificationTypeName> likeNotificationTypes;
  final TotalsLoaded? onTotalsLoaded;
  final TotalsChanged? onTotalsChanged;
  final GroupedUnreadAuthorityAdvanced? onGroupedUnreadAuthorityAdvanced;
  final Duration minimumRefreshInterval;
  final DateTime Function() _clock;

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
  late final _bookmarkListOwner = BookmarkListOwner(
    api: api,
    credentials: credentials,
    lifecycle: lifecycle,
    changed: notifySafely,
  );
  late final _userActivityOwner = UserActivityOwner(
    api: api,
    credentials: credentials,
    lifecycle: lifecycle,
    changed: notifySafely,
  );

  Listenable get totalsListenable => _totalsChanges;
  Listenable get notificationsListenable => _notificationChanges;
  Listenable get replyNotificationsListenable => _replyNotificationChanges;
  Listenable get likeNotificationsListenable => _likeNotificationChanges;
  Listenable get otherNotificationsListenable => _otherNotificationChanges;
  Listenable get bookmarksListenable => _bookmarkChanges;
  Listenable get bookmarkListListenable => _bookmarkListOwner;
  Listenable get userActivityListenable => _userActivityOwner;

  final Map<String, NotificationReconciliation> _reconciliations = {};
  late final _notifications = NotificationFeedSlot.notifications(
    _notificationChanges.changed,
  );
  late final _replyNotifications = NotificationFeedSlot.notifications(
    _replyNotificationChanges.changed,
  );
  late final _likeNotifications = NotificationFeedSlot.notifications(
    _likeNotificationChanges.changed,
  );
  late final _otherNotifications = NotificationFeedSlot.notifications(
    _otherNotificationChanges.changed,
  );
  late final _bookmarks = NotificationFeedSlot.reminders(
    _bookmarkChanges.changed,
  );
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
  final Map<String, ({DiscourseInstance instance, SiteLease lease})>
  _pendingBookmarks = {};
  final Map<String, Completer<void>> _pendingBookmarkWaiters = {};
  final Map<String, Completer<void>> _replayingBookmarkWaiters = {};
  final Map<String, Object> _notificationRequests = {};
  final Map<String, Object> _replyNotificationRequests = {};
  final Map<String, Object> _likeNotificationRequests = {};
  final Map<String, Object> _otherNotificationRequests = {};
  final Map<String, Object> _bookmarkRequests = {};
  final Map<(String, int), Object> _notificationReadRequests = {};
  final Map<(String, PluginNotificationFeedId), Future<void>>
  _pluginNotificationDismissTasks = {};
  NotificationReconciliation? _existingReconciliation(String siteUrl) {
    final owner = _reconciliations[siteUrl];
    if (owner == null || owner.isCurrent) return owner;
    owner.retire();
    _reconciliations.remove(siteUrl);
    return null;
  }

  NotificationReconciliation _reconciliationFor(
    String siteUrl, {
    SiteLease? lease,
  }) {
    final currentLease = lease ?? lifecycle.capture(siteUrl);
    final held = _existingReconciliation(siteUrl);
    if (held != null && identical(held.lease.session, currentLease.session)) {
      return held;
    }
    held?.retire();
    return _reconciliations[siteUrl] = NotificationReconciliation(
      lease: currentLease,
      totalsChanged: (totals) => onTotalsChanged?.call(siteUrl, totals),
      totalsAspectChanged: _totalsChanges.changed,
      changed: notifySafely,
      groupedUnreadAuthorityAdvanced: () =>
          onGroupedUnreadAuthorityAdvanced?.call(siteUrl),
    );
  }

  NotificationTotals? totalsFor(String siteUrl) =>
      _existingReconciliation(siteUrl)?.totals;

  void restoreTotals(String siteUrl, NotificationTotals totals) {
    if (!isDisposed) _reconciliationFor(siteUrl).restoreTotals(totals);
  }

  T _feedFor<T>(String? siteUrl, NotificationFeedSlot<T> slot) =>
      siteUrl == null
      ? slot.empty
      : _existingReconciliation(siteUrl)?.feed(slot) ?? slot.empty;

  NotificationFeed notificationsFor(String? siteUrl) =>
      _feedFor(siteUrl, _notifications);
  NotificationFeed replyNotificationsFor(String? siteUrl) =>
      _feedFor(siteUrl, _replyNotifications);
  NotificationFeed likeNotificationsFor(String? siteUrl) =>
      _feedFor(siteUrl, _likeNotifications);
  NotificationFeed otherNotificationsFor(String? siteUrl) =>
      _feedFor(siteUrl, _otherNotifications);

  Listenable pluginNotificationsListenable(PluginNotificationFeedId id) =>
      _pluginNotificationState(id).changes;

  NotificationFeed pluginNotificationsFor(
    PluginNotificationFeedId id,
    String? siteUrl,
  ) => _feedFor(siteUrl, _pluginNotificationState(id).slot);

  bool hasTrackedPluginNotifications(String siteUrl) =>
      _pluginNotifications.values.any(
        (state) =>
            _existingReconciliation(siteUrl)?.hasPublished(state.slot) ==
                true ||
            state.tasks.containsKey(siteUrl),
      );

  BookmarkFeed bookmarksFor(String? siteUrl) => _feedFor(siteUrl, _bookmarks);

  BookmarkListFeed bookmarkListFor(String? siteUrl) =>
      _bookmarkListOwner.feedFor(siteUrl);

  UserActivityFeed userActivityFor(String? siteUrl) =>
      _userActivityOwner.feedFor(siteUrl);

  static const int userActivityPageSize = UserActivityOwner.pageSize;

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
      return totalsFor(instance.url);
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
    final owner = _reconciliationFor(instance.url, lease: lease);
    final ticket = owner.beginTotalsRefresh();
    try {
      final auth = await AccountRequestSession(
        instance.url,
        lease,
      ).keyCredentials(credentials);
      final apiKey = auth.apiKey;
      if (apiKey == null ||
          !_ownsRequest(lease, _totalsRequests[instance.url], request)) {
        return null;
      }
      final totals = await auth.run(
        () => api.notificationTotals(siteUrl: instance.url, apiKey: apiKey),
      );
      NotificationTotals? applied;
      final accepted = _commit(lease, () {
        if (!identical(_totalsRequests[instance.url], request)) return;
        final resolved = owner.acceptTotalsRefresh(ticket, totals);
        if (resolved == null) return;
        applied = resolved;
        // Publishing can synchronously retire this account through a listener.
        // Its post-load hook must retain the same request and account owner.
        if (_ownsRequest(lease, _totalsRequests[instance.url], request)) {
          onTotalsLoaded?.call(instance, resolved);
        }
      });
      return accepted ? applied : null;
    } catch (error) {
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(_totalsRequests[instance.url], request)) {
        return null;
      }

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
          slot: _notifications,
          requests: _notificationRequests,
          fetch: (apiKey, _) =>
              api.notifications(siteUrl: instance.url, apiKey: apiKey),
          reconnectMessage: appL10n.reconnectToToSeeNotifications(
            (instance.host).toString(),
          ),
          failureMessage: appL10n.couldnTLoadNotificationsFrom(
            (instance.host).toString(),
          ),
        ),
      );

  Future<void> loadReplyNotifications(DiscourseInstance instance) =>
      _coalescedActivityLoad(
        instance.url,
        tasks: _replyNotificationTasks,
        start: () => _loadNotificationFeed(
          instance,
          slot: _replyNotifications,
          requests: _replyNotificationRequests,
          fetch: (apiKey, _) => api.notifications(
            siteUrl: instance.url,
            apiKey: apiKey,
            filterByTypes: userMenuReplyNotificationTypes,
          ),
          reconnectMessage: appL10n.reconnectToToSeeReplies(
            (instance.host).toString(),
          ),
          failureMessage: appL10n.couldnTLoadRepliesFrom(
            (instance.host).toString(),
          ),
        ),
      );

  Future<void> loadLikeNotifications(DiscourseInstance instance) =>
      _coalescedActivityLoad(
        instance.url,
        tasks: _likeNotificationTasks,
        start: () => _loadNotificationFeed(
          instance,
          slot: _likeNotifications,
          requests: _likeNotificationRequests,
          fetch: (apiKey, _) => api.notifications(
            siteUrl: instance.url,
            apiKey: apiKey,
            filterByTypes: likeNotificationTypes,
          ),
          reconnectMessage: appL10n.reconnectToToSeeLikes(
            (instance.host).toString(),
          ),
          failureMessage: appL10n.couldnTLoadLikesFrom(
            (instance.host).toString(),
          ),
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
      slot: _otherNotifications,
      requests: _otherNotificationRequests,
      fetch: (apiKey, ownsRequest) async {
        final types = await resolveTypes(apiKey);
        // The catalog and notification requests share the original owner.
        if (!ownsRequest() || types.isEmpty) return const [];
        return api.notifications(
          siteUrl: instance.url,
          apiKey: apiKey,
          filterByTypes: types,
        );
      },
      reconnectMessage: appL10n.reconnectToToSeeOtherNotifications(
        (instance.host).toString(),
      ),
      failureMessage: appL10n.couldnTLoadOtherNotificationsFrom(
        (instance.host).toString(),
      ),
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
        slot: state.slot,
        requests: state.requests,
        fetch: (apiKey, _) async => source.arrange(
          await api.notifications(
            siteUrl: instance.url,
            apiKey: apiKey,
            filterByTypes: source.filterByTypes,
          ),
        ),
        reconnectMessage: source.reconnectMessage,
        failureMessage: source.failureMessage,
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
        if (_existingReconciliation(
                  instance.url,
                )?.hasPublished(_pluginNotificationState(source.id).slot) ==
                true ||
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

  /// Marks every server-defined notification type read for this account.
  Future<void> markAllNotificationsRead(
    DiscourseInstance instance,
    List<NotificationWireType> types,
  ) => _dismissNotificationTypes(instance, types: types);

  Future<void> _dismissPluginNotifications(
    DiscourseInstance instance,
    PluginNotificationFeedSource source,
  ) => _dismissNotificationTypes(
    instance,
    source: source,
    types: source.dismissal!.notificationTypes,
  );

  Future<void> _dismissNotificationTypes(
    DiscourseInstance instance, {
    PluginNotificationFeedSource? source,
    required List<NotificationWireType> types,
  }) async {
    if (isDisposed || !instance.isConnected) return;
    final siteUrl = instance.url;
    final lease = lifecycle.capture(siteUrl);
    final owner = _reconciliationFor(siteUrl, lease: lease);
    final attempt = owner.beginDismiss(
      types: types,
      names: source?.filterByTypes,
      source: source == null ? null : _pluginNotificationState(source.id).slot,
    );
    if (attempt == null || isDisposed || !lease.isCurrent) return;
    final dismissedTypeNames = List<NotificationTypeName>.unmodifiable(
      source?.filterByTypes ??
          [for (final type in types) NotificationTypeName(type.wireName)],
    );

    try {
      final auth = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(credentials);
      final apiKey = auth.apiKey;
      if (isDisposed || !lease.isCurrent) return;
      if (apiKey == null) {
        throw StateError(
          'Reconnect to ${instance.host} to dismiss notifications.',
        );
      }
      await auth.run(
        () => api.markNotificationsRead(
          siteUrl: siteUrl,
          apiKey: apiKey,
          types: dismissedTypeNames,
        ),
      );
      if (isDisposed || !lease.isCurrent) return;

      owner.confirmDismiss(attempt);
      if (isDisposed || !lease.isCurrent) return;

      // Mirror Discourse's user-menu dismiss action: reconcile the filtered
      // list authoritatively after the write. Only the pre-write cache snapshot
      // is locally pinned read, so a newer row received during the write stays
      // unread while this fetch resolves the final list.
      if (source != null) {
        await _refreshLoadedPluginNotifications(instance, source, lease);
      } else {
        final active = _notificationTasks[siteUrl];
        if (active != null) await active;
        if (isDisposed || !lease.isCurrent) return;
        await loadNotifications(instance);
      }

      // `/notifications/totals.json` does not currently return grouped type
      // counts. It is still useful for the aggregate unread total, while the
      // guarded mutation above reconciles the plugin badge without replacing
      // any newer live grouped-count snapshot.
      await refresh(instance, force: true);
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;

      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  _PluginNotificationState _pluginNotificationState(
    PluginNotificationFeedId id,
  ) => _pluginNotifications.putIfAbsent(id, _PluginNotificationState.new);

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
    required NotificationFeedSlot<NotificationFeed> slot,
    required Map<String, Object> requests,
    required Future<List<DiscourseNotification>> Function(
      String apiKey,
      bool Function() ownsRequest,
    )
    fetch,
    required String reconnectMessage,
    required String failureMessage,
  }) async {
    if (isDisposed || !instance.isConnected) return;
    final lease = lifecycle.capture(instance.url);
    if (requests.containsKey(instance.url)) return;
    final request = Object();
    requests[instance.url] = request;
    final owner = _reconciliationFor(instance.url, lease: lease);
    final held = owner.hasPublished(slot) ? owner.feed(slot) : null;

    bool ownsRequest() => _ownsRequest(lease, requests[instance.url], request);

    if (held == null || held.error != null) {
      owner.publish(slot, const NotificationFeed.loading());
    }

    void fail(String message) {
      // Rows that arrived while the request was out stay on screen.
      final current = owner.feed(slot);
      if (current.notifications.isNotEmpty) {
        owner.publish(slot, current);
        return;
      }
      owner.publish(slot, NotificationFeed.failed(message));
    }

    try {
      final auth = await AccountRequestSession(
        instance.url,
        lease,
      ).keyCredentials(credentials);
      final apiKey = auth.apiKey;
      if (!ownsRequest()) {
        return;
      }
      if (apiKey == null) {
        _commit(lease, () {
          if (!identical(requests[instance.url], request)) return;
          fail(reconnectMessage);
        });
        return;
      }
      final notifications = await auth.run(() => fetch(apiKey, ownsRequest));
      _commit(lease, () {
        if (!identical(requests[instance.url], request)) return;
        owner.publish(slot, NotificationFeed.of(notifications));
      });
    } on SiteLookupException catch (error) {
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(requests[instance.url], request)) {
        return;
      }

      _commit(lease, () {
        if (!identical(requests[instance.url], request)) return;
        fail(
          error.failure == SiteLookupFailure.notDiscourse
              ? appL10n.notAllowedTryReconnectingTo((instance.host).toString())
              : appL10n.couldnTReach((instance.host).toString()),
        );
      });
    } catch (error) {
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(requests[instance.url], request)) {
        return;
      }

      _commit(lease, () {
        if (!identical(requests[instance.url], request)) return;
        fail(failureMessage);
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
    final lease = lifecycle.capture(instance.url);
    final active = _bookmarkTasks[instance.url];
    if (active != null) {
      if (!force) return active;
      _pendingBookmarks[instance.url] = (instance: instance, lease: lease);
      return _pendingBookmarkWaiters
          .putIfAbsent(instance.url, Completer<void>.new)
          .future;
    }
    return _startBookmarksLoad(instance, lease);
  }

  Future<void> _startBookmarksLoad(
    DiscourseInstance instance,
    SiteLease lease,
  ) {
    if (isDisposed || !lease.isCurrent) return Future<void>.value();
    final result = Completer<void>();
    final task = result.future;
    _bookmarkTasks[instance.url] = task;
    try {
      unawaited(
        _loadBookmarks(instance, lease).then<void>(
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
    if (pending == null ||
        waiter == null ||
        isDisposed ||
        !pending.lease.isCurrent) {
      if (waiter != null && !waiter.isCompleted) waiter.complete();
      return;
    }

    _replayingBookmarkWaiters[siteUrl] = waiter;
    final replay = _startBookmarksLoad(pending.instance, pending.lease);
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

  Future<void> _loadBookmarks(
    DiscourseInstance instance,
    SiteLease lease,
  ) async {
    if (isDisposed || !lease.isCurrent) return;
    final username = instance.user?.username;
    if (username == null) return;
    if (_bookmarkRequests.containsKey(instance.url)) return;
    final request = Object();
    _bookmarkRequests[instance.url] = request;
    final owner = _reconciliationFor(instance.url, lease: lease);
    final held = owner.hasPublished(_bookmarks) ? owner.feed(_bookmarks) : null;

    if (held == null || held.error != null) {
      owner.publish(_bookmarks, const BookmarkFeed.loading());
    }

    void fail(String message) {
      // Rows that arrived while the request was out stay on screen.
      final current = owner.feed(_bookmarks);
      if (current.hasRows) {
        owner.publish(_bookmarks, current);
        return;
      }
      owner.publish(_bookmarks, BookmarkFeed.failed(message));
    }

    try {
      final auth = await AccountRequestSession(
        instance.url,
        lease,
      ).keyCredentials(credentials);
      final apiKey = auth.apiKey;
      if (!_ownsRequest(lease, _bookmarkRequests[instance.url], request)) {
        return;
      }
      if (apiKey == null) {
        _commit(lease, () {
          if (!identical(_bookmarkRequests[instance.url], request)) return;
          fail(
            appL10n.reconnectToToSeeYourBookmarks((instance.host).toString()),
          );
        });
        return;
      }
      final bookmarks = await auth.run(
        () => api.bookmarks(
          siteUrl: instance.url,
          apiKey: apiKey,
          username: username,
        ),
      );
      _commit(lease, () {
        if (!identical(_bookmarkRequests[instance.url], request)) return;
        owner.publish(_bookmarks, BookmarkFeed.of(bookmarks));
      });
    } on SiteLookupException catch (error) {
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(_bookmarkRequests[instance.url], request)) {
        return;
      }

      _commit(lease, () {
        if (!identical(_bookmarkRequests[instance.url], request)) return;
        fail(
          error.failure == SiteLookupFailure.notDiscourse
              ? appL10n.notAllowedTryReconnectingTo((instance.host).toString())
              : appL10n.couldnTReach((instance.host).toString()),
        );
      });
    } catch (error) {
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(_bookmarkRequests[instance.url], request)) {
        return;
      }

      _commit(lease, () {
        if (!identical(_bookmarkRequests[instance.url], request)) return;
        fail(appL10n.couldnTLoadBookmarksFrom((instance.host).toString()));
      });
    } finally {
      _commit(lease, () {
        if (identical(_bookmarkRequests[instance.url], request)) {
          _bookmarkRequests.remove(instance.url);
        }
      });
    }
  }

  Future<void> loadBookmarkList(
    DiscourseInstance instance, {
    bool refresh = false,
    bool loadMore = false,
    bool loadPrevious = false,
  }) => _bookmarkListOwner.load(
    instance,
    refresh: refresh,
    loadMore: loadMore,
    loadPrevious: loadPrevious,
  );

  Future<void> refreshLoadedBookmarkList(DiscourseInstance instance) =>
      _bookmarkListOwner.refreshLoaded(instance);

  Future<void> loadUserActivity(
    DiscourseInstance instance, {
    bool refresh = false,
    bool loadMore = false,
    bool loadPrevious = false,
  }) => _userActivityOwner.load(
    instance,
    refresh: refresh,
    loadMore: loadMore,
    loadPrevious: loadPrevious,
  );

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
    final key = (instance.url, notification.id);
    final owner = _reconciliationFor(instance.url, lease: lease);
    final attempt = owner.beginRead(notification);
    if (attempt == null ||
        !_ownsRequest(lease, _notificationReadRequests[key], request)) {
      return;
    }

    try {
      final auth = await AccountRequestSession(
        instance.url,
        lease,
      ).keyCredentials(credentials);
      final apiKey = auth.apiKey;
      if (!_ownsRequest(lease, _notificationReadRequests[key], request)) {
        return;
      }
      if (apiKey == null) {
        owner.failRead(attempt);
        return;
      }
      await auth.run(
        () => api.markNotificationRead(
          siteUrl: instance.url,
          apiKey: apiKey,
          id: notification.id,
        ),
      );
    } catch (error) {
      if (!_ownsRequest(lease, _notificationReadRequests[key], request)) {
        return;
      }
      owner.failRead(attempt);

      return;
    }

    if (!_ownsRequest(lease, _notificationReadRequests[key], request)) return;
    owner.confirmRead(attempt);
    if (!_ownsRequest(lease, _notificationReadRequests[key], request)) return;
    await refresh(instance, force: true);
  }

  void applyCounts(
    String siteUrl,
    NotificationTotals Function(NotificationTotals held) fold,
  ) {
    if (!isDisposed) _reconciliationFor(siteUrl).applyCounts(fold);
  }

  void applyGroupedUnreadSnapshot(
    String siteUrl,
    NotificationTypeCounts counts,
  ) {
    if (!isDisposed) _reconciliationFor(siteUrl).applyGroupedSnapshot(counts);
  }

  void applyLiveNotificationState(String siteUrl, Object? data) {
    if (isDisposed || data is! Map) return;
    _reconciliationFor(siteUrl).applyLiveCounts(
      LiveNotificationCounts(
        allUnread: _notificationCount(data['all_unread_notifications_count']),
        personal: _notificationCount(
          data['new_personal_messages_notifications_count'],
        ),
        grouped: NotificationTypeCounts.fromWire(
          data['grouped_unread_notifications'],
        ),
      ),
    );
  }

  void applyReviewableCounts(String siteUrl, Object? data) {
    if (isDisposed || data is! Map) return;
    final count = _notificationCount(data['unseen_reviewable_count']);
    if (count != null) _reconciliationFor(siteUrl).applyReviewables(count);
  }

  static int? _notificationCount(Object? value) {
    final count = jsonIntOrNull(value);
    return count == null
        ? null
        : count < 0
        ? 0
        : count;
  }

  void applyPluginCounter(
    String siteUrl,
    PluginNotificationCounter counter,
    int Function(int current) reduce,
  ) {
    if (!isDisposed) {
      _reconciliationFor(siteUrl).applyPluginCounter(counter, reduce);
    }
  }

  void forget(String siteUrl) {
    if (isDisposed) return;
    final owner = _reconciliations.remove(siteUrl);
    for (final state in _pluginNotifications.values) {
      state.tasks.remove(siteUrl)?.ignore();
      state.requests.remove(siteUrl);
    }
    final hadBookmarkList = _bookmarkListOwner.retire(siteUrl);
    final hadUserActivity = _userActivityOwner.retire(siteUrl);
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
    _notificationReadRequests.removeWhere((key, _) => key.$1 == siteUrl);
    _pluginNotificationDismissTasks.removeWhere((key, task) {
      if (key.$1 != siteUrl) return false;
      task.ignore();
      return true;
    });
    final changed = hadBookmarkList || hadUserActivity;
    final hadNotifications = owner?.retire(notify: true) ?? false;
    if (hadBookmarkList) _bookmarkListOwner.publishRetirement();
    if (hadUserActivity) _userActivityOwner.publishRetirement();
    if (changed || hadNotifications) notifySafely();
  }

  bool _commit(SiteLease lease, SiteMutation mutation) {
    if (isDisposed) return false;
    return lease.commit(mutation);
  }

  bool _ownsRequest(SiteLease lease, Object? held, Object request) =>
      !isDisposed && lease.isCurrent && identical(held, request);

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
    _totalsRequests.clear();
    _notificationRequests.clear();
    _replyNotificationRequests.clear();
    _likeNotificationRequests.clear();
    _otherNotificationRequests.clear();
    _bookmarkRequests.clear();
    _notificationReadRequests.clear();
    for (final owner in _reconciliations.values) {
      owner.retire();
    }
    _reconciliations.clear();
    _pluginNotificationDismissTasks.clear();
    _totalsChanges.dispose();
    _notificationChanges.dispose();
    _replyNotificationChanges.dispose();
    _likeNotificationChanges.dispose();
    _otherNotificationChanges.dispose();
    _bookmarkChanges.dispose();
    _bookmarkListOwner.dispose();
    _userActivityOwner.dispose();
    super.dispose();
  }
}

final class _ActivityAspect extends FrameSafeNotifier {
  void changed() => notifySafely();
}

final class _PluginNotificationState {
  final _ActivityAspect changes = _ActivityAspect();
  late final slot = NotificationFeedSlot.notifications(changes.changed);
  final Map<String, Future<void>> tasks = {};
  final Map<String, Object> requests = {};

  void dispose() => changes.dispose();
}
