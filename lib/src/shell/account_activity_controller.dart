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

part 'account_totals_refresh.dart';
part 'notification_feed_load.dart';
part 'account_bookmark_refresh.dart';

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
  final _children = _AccountActivityChildren();
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
  final _personActivityChanges = _ActivityAspect();
  late final _activityListenable = Listenable.merge([
    _userActivityOwner,
    _personActivityChanges,
  ]);
  Listenable get userActivityListenable => _activityListenable;

  UserActivityOwner? _activityOwner(String siteUrl, String? username) {
    if (_children.closed) return null;
    if (username == null) return _userActivityOwner;
    final key = (siteUrl, username.toLowerCase());
    return _children.admit(
      _children.people,
      key,
      () => UserActivityOwner(
        api: api,
        credentials: credentials,
        lifecycle: lifecycle,
        username: username,
        changed: () {
          _personActivityChanges.changed();
          notifySafely();
        },
      ),
    );
  }

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
  final Map<String, _AccountTotalsRefresh> _totalsRefreshes = {};
  final Map<String, _NotificationFeedLoad> _notificationLoads = {};
  final Map<String, _NotificationFeedLoad> _replyNotificationLoads = {};
  final Map<String, _NotificationFeedLoad> _likeNotificationLoads = {};
  final Map<String, _NotificationFeedLoad> _otherNotificationLoads = {};
  final Map<String, _AccountBookmarkRefresh> _bookmarkRefreshes = {};
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
      _children.closed
      ? const _InactiveActivityListenable()
      : _pluginNotificationState(id).changes;

  NotificationFeed pluginNotificationsFor(
    PluginNotificationFeedId id,
    String? siteUrl,
  ) {
    final state = _children.pluginFeeds[id];
    return state == null
        ? const NotificationFeed()
        : _feedFor(siteUrl, state.slot);
  }

  bool hasTrackedPluginNotifications(String siteUrl) =>
      _children.pluginFeeds.values.any(
        (state) =>
            _existingReconciliation(siteUrl)?.hasPublished(state.slot) ==
                true ||
            state.loads.containsKey(siteUrl),
      );

  BookmarkFeed bookmarksFor(String? siteUrl) => _feedFor(siteUrl, _bookmarks);

  BookmarkListFeed bookmarkListFor(String? siteUrl) =>
      _bookmarkListOwner.feedFor(siteUrl);

  UserActivityFeed userActivityFor(String? siteUrl, {String? username}) {
    if (siteUrl == null) return const UserActivityFeed();
    final owner = username == null
        ? _userActivityOwner
        : _children.people[(siteUrl, username.toLowerCase())];
    return owner?.feedFor(siteUrl) ?? const UserActivityFeed();
  }

  static const int userActivityPageSize = UserActivityOwner.pageSize;

  Future<NotificationTotals?> refresh(
    DiscourseInstance instance, {
    bool force = false,
  }) {
    if (isDisposed) return Future.value();
    final lease = lifecycle.capture(instance.url);
    var account = _totalsRefreshes[instance.url];
    if (account != null && !account.isCurrent) {
      account.retire();
      account = _totalsRefreshes[instance.url];
    }
    if (account == null) {
      account = _AccountTotalsRefresh(this, instance.url, lease);
      _totalsRefreshes[instance.url] = account;
      account.observeRetirement();
    }
    return account.refresh(instance, force: force);
  }

  Future<void> loadNotifications(DiscourseInstance instance) =>
      _coalescedActivityLoad(
        instance.url,
        loads: _notificationLoads,
        start: (load) => _loadNotificationFeed(
          instance,
          load: load,
          slot: _notifications,
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
        loads: _replyNotificationLoads,
        start: (load) => _loadNotificationFeed(
          instance,
          load: load,
          slot: _replyNotifications,
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
        loads: _likeNotificationLoads,
        start: (load) => _loadNotificationFeed(
          instance,
          load: load,
          slot: _likeNotifications,
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
    loads: _otherNotificationLoads,
    start: (load) => _loadNotificationFeed(
      instance,
      load: load,
      slot: _otherNotifications,
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
    if (_children.closed) return Future.value();
    final registered = _children.pluginSources[source.id];
    if (registered != null && registered != source) {
      return Future<void>.error(
        StateError('Conflicting notification feed ${source.id.id}.'),
      );
    }
    _children.pluginSources[source.id] = source;
    final state = _pluginNotificationState(source.id);
    return _coalescedActivityLoad(
      instance.url,
      loads: state.loads,
      start: (load) => _loadNotificationFeed(
        instance,
        load: load,
        slot: state.slot,
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
      _children.pluginSources.values,
    );
    await Future.wait([
      for (final source in sources)
        if (_existingReconciliation(
                  instance.url,
                )?.hasPublished(_pluginNotificationState(source.id).slot) ==
                true ||
            _pluginNotificationState(source.id).loads.containsKey(instance.url))
          _refreshLoadedPluginNotifications(instance, source, lease),
    ]);
  }

  Future<void> _refreshLoadedPluginNotifications(
    DiscourseInstance instance,
    PluginNotificationFeedSource source,
    SiteLease lease,
  ) async {
    final state = _pluginNotificationState(source.id);
    final active = state.loads[instance.url];
    if (active != null) await active.future;
    if (isDisposed || !lease.isCurrent) return;
    await loadPluginNotifications(instance, source);
  }

  Future<void> dismissPluginNotifications(
    DiscourseInstance instance,
    PluginNotificationFeedSource source,
  ) {
    if (_children.closed) return Future.value();
    if (source.dismissal == null) {
      return Future<void>.error(
        StateError(
          'Notification feed ${source.id.id} does not support dismissal.',
        ),
      );
    }
    final registered = _children.pluginSources[source.id];
    if (registered != null && registered != source) {
      return Future<void>.error(
        StateError('Conflicting notification feed ${source.id.id}.'),
      );
    }
    _children.pluginSources[source.id] = source;

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
        final active = _notificationLoads[siteUrl];
        if (active != null) await active.future;
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
  ) =>
      _children.admit(_children.pluginFeeds, id, _PluginNotificationState.new)!;

  Future<void> _coalescedActivityLoad(
    String siteUrl, {
    required Map<String, _NotificationFeedLoad> loads,
    required Future<void> Function(_NotificationFeedLoad load) start,
  }) {
    if (isDisposed) return Future<void>.value();
    final active = loads[siteUrl];
    if (active != null && active.isCurrent) return active.future;
    active?.finish();

    final load = _NotificationFeedLoad(lifecycle.capture(siteUrl));
    // Loading publication can re-enter before credential IO. Install the load
    // and its retirement cleanup before invoking any domain callbacks.
    loads[siteUrl] = load;
    load.observeRetirement(() {
      if (identical(loads[siteUrl], load)) loads.remove(siteUrl);
    });
    try {
      unawaited(
        start(load).then<void>(
          (_) => load.finish(),
          onError: (Object error, StackTrace stackTrace) =>
              load.finish(error, stackTrace),
        ),
      );
    } catch (error, stackTrace) {
      load.finish(error, stackTrace);
    }
    return load.future;
  }

  Future<void> _loadNotificationFeed(
    DiscourseInstance instance, {
    required NotificationFeedSlot<NotificationFeed> slot,
    required _NotificationFeedLoad load,
    required Future<List<DiscourseNotification>> Function(
      String apiKey,
      bool Function() ownsRequest,
    )
    fetch,
    required String reconnectMessage,
    required String failureMessage,
  }) async {
    if (isDisposed || !instance.isConnected || !load.isCurrent) return;
    final lease = load.lease;
    final owner = _reconciliationFor(instance.url, lease: lease);
    final held = owner.hasPublished(slot) ? owner.feed(slot) : null;

    bool ownsRequest() => !isDisposed && load.isCurrent;

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
          if (!ownsRequest()) return;
          fail(reconnectMessage);
        });
        return;
      }
      final notifications = await auth.run(() => fetch(apiKey, ownsRequest));
      _commit(lease, () {
        if (!ownsRequest()) return;
        owner.publish(slot, NotificationFeed.of(notifications));
      });
    } on SiteLookupException catch (error) {
      if (!ownsRequest()) {
        return;
      }

      _commit(lease, () {
        if (!ownsRequest()) return;
        fail(
          error.failure == SiteLookupFailure.notDiscourse
              ? appL10n.notAllowedTryReconnectingTo((instance.host).toString())
              : appL10n.couldnTReach((instance.host).toString()),
        );
      });
    } catch (error) {
      if (!ownsRequest()) {
        return;
      }

      _commit(lease, () {
        if (!ownsRequest()) return;
        fail(failureMessage);
      });
    }
  }

  Future<void> loadBookmarks(DiscourseInstance instance, {bool force = false}) {
    if (isDisposed) return Future<void>.value();
    final lease = lifecycle.capture(instance.url);
    var account = _bookmarkRefreshes[instance.url];
    if (account != null && !account.isCurrent) {
      account.retire();
      account = _bookmarkRefreshes[instance.url];
    }
    if (account == null) {
      account = _AccountBookmarkRefresh(this, instance.url, lease);
      _bookmarkRefreshes[instance.url] = account;
      account.observeRetirement();
    }
    return account.load(instance, force: force);
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
    String? username,
    bool refresh = false,
    bool loadMore = false,
    bool loadPrevious = false,
  }) =>
      _activityOwner(instance.url, username)?.load(
        instance,
        refresh: refresh,
        loadMore: loadMore,
        loadPrevious: loadPrevious,
      ) ??
      Future.value();

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
    for (final state in _children.pluginFeeds.values) {
      state.loads.remove(siteUrl)?.finish();
    }
    final hadBookmarkList = _bookmarkListOwner.retire(siteUrl);
    final hadUserActivity = _userActivityOwner.retire(siteUrl);
    final retired = _children.people.keys
        .where((key) => key.$1 == siteUrl)
        .toList();
    for (final key in retired) {
      _children.people.remove(key)!.dispose();
    }
    if (retired.isNotEmpty) _personActivityChanges.changed();
    _totalsRefreshes.remove(siteUrl)?.retire();
    _notificationLoads.remove(siteUrl)?.finish();
    _replyNotificationLoads.remove(siteUrl)?.finish();
    _likeNotificationLoads.remove(siteUrl)?.finish();
    _otherNotificationLoads.remove(siteUrl)?.finish();
    _bookmarkRefreshes.remove(siteUrl)?.retire();
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
    if (isDisposed) return;
    super.dispose();
    _children.close();
    final totalsRefreshes = _totalsRefreshes.values.toList();
    _totalsRefreshes.clear();
    for (final account in totalsRefreshes) {
      account.retire();
    }
    final bookmarkRefreshes = _bookmarkRefreshes.values.toList();
    _bookmarkRefreshes.clear();
    for (final account in bookmarkRefreshes) {
      account.retire();
    }
    for (final load in _notificationLoads.values.toList()) {
      load.finish();
    }
    for (final load in _replyNotificationLoads.values.toList()) {
      load.finish();
    }
    for (final load in _likeNotificationLoads.values.toList()) {
      load.finish();
    }
    for (final load in _otherNotificationLoads.values.toList()) {
      load.finish();
    }
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
    _personActivityChanges.dispose();
  }
}

final class _ActivityAspect extends FrameSafeNotifier {
  void changed() => notifySafely();
}

final class _PluginNotificationState {
  final _ActivityAspect changes = _ActivityAspect();
  late final slot = NotificationFeedSlot.notifications(changes.changed);
  final Map<String, _NotificationFeedLoad> loads = {};

  void dispose() {
    for (final load in loads.values.toList()) {
      load.finish();
    }
    changes.dispose();
  }
}

/// Owns dynamic children; lookups never admit work and close precedes callbacks.
final class _AccountActivityChildren {
  final pluginFeeds = <PluginNotificationFeedId, _PluginNotificationState>{};
  final pluginSources =
      <PluginNotificationFeedId, PluginNotificationFeedSource>{};
  final people = <(String, String), UserActivityOwner>{};
  bool closed = false;

  V? admit<K, V>(Map<K, V> children, K key, V Function() create) =>
      closed ? null : children.putIfAbsent(key, create);

  void close() {
    if (closed) return;
    closed = true;
    final feeds = pluginFeeds.values.toList();
    final owners = people.values.toList();
    pluginFeeds.clear();
    pluginSources.clear();
    people.clear();
    for (final feed in feeds) {
      feed.dispose();
    }
    for (final owner in owners) {
      owner.dispose();
    }
  }
}

final class _InactiveActivityListenable implements Listenable {
  const _InactiveActivityListenable();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
