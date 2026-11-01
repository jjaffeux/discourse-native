import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';

import 'gamification_api.dart';
import 'gamification_models.dart';
import 'gamification_navigation.dart';

const gamificationControllerKey = PluginServiceKey<GamificationController>(
  owner: gamificationPluginId,
  name: 'controller',
);

enum GamificationAppend { idle, loading, failed, exhausted }

sealed class GamificationViewState {
  const GamificationViewState();
}

final class GamificationLoading extends GamificationViewState {
  const GamificationLoading();
}

final class GamificationUnavailable extends GamificationViewState {
  const GamificationUnavailable();
}

final class GamificationRestricted extends GamificationViewState {
  const GamificationRestricted();
}

final class GamificationFailed extends GamificationViewState {
  const GamificationFailed(this.error);
  final Object error;
}

final class GamificationUnsupported extends GamificationViewState {
  const GamificationUnsupported();
}

final class GamificationPreparing extends GamificationViewState {
  const GamificationPreparing(this.reason);
  final String reason;
}

final class GamificationSnapshot {
  GamificationSnapshot({
    required this.query,
    required this.board,
    required List<GamificationRankedUser> users,
    required this.personal,
    required this.page,
    required this.fetchedAt,
  }) : users = List.unmodifiable(users);
  final GamificationQuery query;
  final GamificationLeaderboard board;
  final List<GamificationRankedUser> users;
  final GamificationPersonalRank personal;
  final int page;
  final DateTime fetchedAt;
}

final class GamificationReady extends GamificationViewState {
  const GamificationReady(
    this.snapshot, {
    this.refreshing = false,
    this.append = GamificationAppend.idle,
    this.error,
  });
  final GamificationSnapshot snapshot;
  final bool refreshing;
  final GamificationAppend append;
  final Object? error;
}

final class GamificationController extends FrameSafeNotifier
    implements
        PluginCurrentUserObserver,
        PluginTrackerAttachment,
        PluginRouteHydrator,
        PluginSiteActivator {
  GamificationController({
    required this.api,
    required this.requests,
    required this.siteState,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final GamificationApi api;
  final PluginRequestHost requests;
  final PluginSiteStateHost siteState;
  final DateTime Function() now;
  final _handles = <GamificationHandle>{};
  final _admins = <GamificationAdminHandle>{};
  final _revisions = <String, int>{};
  final _forgotten = <String>{};
  final _enabledOverrides = <String, bool>{};
  final _settings = <String, (Listenable, VoidCallback)>{};
  final _channels = <String, PluginLiveChannelHandle>{};
  final _cache = <(String, int, GamificationQuery), GamificationSnapshot>{};
  bool _foreground = true;
  int revision(String site) => _revisions[site] ?? 0;
  bool installed(String site) =>
      !isDisposed &&
      !_forgotten.contains(site) &&
      siteState.siteConfigFor(site).plugins.get(gamificationSettingsKey) !=
          null;
  bool enabled(String site) =>
      installed(site) &&
      (_enabledOverrides[site] ??
          siteState
              .siteConfigFor(site)
              .plugins
              .get(gamificationSettingsKey)!
              .enabled);
  bool canManage(String site) =>
      installed(site) && siteState.currentUserFor(site)?.admin == true;
  bool current(
    String site,
    PluginSiteLease lease,
    int generation, {
    bool admin = false,
  }) =>
      !isDisposed &&
      lease.isCurrent &&
      revision(site) == generation &&
      (admin ? canManage(site) : enabled(site));
  void _observe(String site) {
    if (_settings.containsKey(site)) return;
    final listenable = siteState.siteConfigListenableFor?.call(site);
    if (listenable == null) return;
    void changed() {
      _enabledOverrides.remove(site);
      if (!enabled(site)) _invalidate(site);
      notifySafely();
    }

    _settings[site] = (listenable, changed);
    listenable.addListener(changed);
  }

  GamificationHandle acquire(
    String site,
    GamificationQuery query, {
    int? previewUserLimit,
  }) {
    _observe(site);
    final handle = GamificationHandle._(this, site, query, previewUserLimit);
    _handles.add(handle);
    final cached = previewUserLimit == null
        ? _cache[(site, revision(site), query)]
        : null;
    if (enabled(site) &&
        cached != null &&
        now().difference(cached.fetchedAt) < const Duration(seconds: 60)) {
      handle.state = GamificationReady(cached);
    } else {
      unawaited(handle.refresh());
    }
    return handle;
  }

  GamificationAdminHandle acquireAdmin(String site) {
    _observe(site);
    final handle = GamificationAdminHandle._(this, site);
    _admins.add(handle);
    handle._subscribe();
    unawaited(handle.refresh());
    return handle;
  }

  void _retain(GamificationHandle handle) {
    _handles.remove(handle);
    if (handle.previewUserLimit != null || !enabled(handle.site)) return;
    final state = handle.state;
    if (state is! GamificationReady) return;
    final key = (handle.site, revision(handle.site), handle.query);
    _cache.remove(key);
    _cache[key] = state.snapshot;
    while (_cache.length > 8) {
      _cache.remove(_cache.keys.first);
    }
  }

  void refreshPublic(String site) {
    _cache.removeWhere((key, _) => key.$1 == site);
    for (final handle in _handles.where((h) => h.site == site).toList()) {
      unawaited(handle.refresh());
    }
  }

  void _invalidate(String site) {
    _revisions[site] = revision(site) + 1;
    _enabledOverrides.remove(site);
    _cache.removeWhere((key, _) => key.$1 == site);
    for (final h in _handles.where((h) => h.site == site).toList()) {
      h._invalidate();
    }
    for (final h in _admins.where((h) => h.site == site).toList()) {
      h._invalidate();
    }
  }

  @override
  void pluginCurrentUserRefreshed(String siteUrl) {
    _invalidate(siteUrl);
    for (final h in _handles.where((h) => h.site == siteUrl).toList()) {
      unawaited(h.refresh());
    }
    for (final h in _admins.where((h) => h.site == siteUrl).toList()) {
      h._subscribe();
      unawaited(h.refresh());
    }
    notifySafely();
  }

  @override
  void attachPluginTracker(String siteUrl, PluginLiveChannelHandle channels) {
    final previous = _channels[siteUrl];
    _channels[siteUrl] = channels;
    for (final h in _admins.where((h) => h.site == siteUrl).toList()) {
      if (previous != null && !identical(previous, channels)) {
        h._connectionLost();
      }
      h._subscribe();
    }
  }

  @override
  bool handlesPluginRoute(String routeId) =>
      GamificationRoute.parse(routeId) != null;
  @override
  Future<void> hydratePluginRoute(
    String siteUrl,
    String routeId, {
    bool force = false,
  }) async {
    final route = GamificationRoute.parse(routeId);
    if (route == null) return;
    if (route.admin) return;
    final h = acquire(siteUrl, route.query);
    try {
      await h.refresh();
    } finally {
      h.release();
    }
  }

  @override
  void activatePluginSite(String siteUrl, {required bool connected}) =>
      _observe(siteUrl);
  void forget(String site) {
    _forgotten.add(site);
    _invalidate(site);
    final held = _settings.remove(site);
    if (held != null) held.$1.removeListener(held.$2);
    _channels.remove(site);
    notifySafely();
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    for (final h in _handles.toList()) {
      h._timer?.cancel();
      h._timer = null;
      if (foreground) unawaited(h.refresh());
    }
    for (final h in _admins.toList()) {
      if (!foreground) {
        h._connectionLost();
      } else {
        h._subscribe();
        unawaited(h.refresh());
      }
    }
  }

  @override
  void dispose() {
    for (final site in {
      ..._handles.map((h) => h.site),
      ..._admins.map((h) => h.site),
    }) {
      _invalidate(site);
    }
    for (final h in _handles.toList()) {
      h.release();
    }
    for (final h in _admins.toList()) {
      h.release();
    }
    for (final pair in _settings.values) {
      pair.$1.removeListener(pair.$2);
    }
    _settings.clear();
    _cache.clear();
    _channels.clear();
    super.dispose();
  }
}

final class GamificationHandle extends FrameSafeNotifier {
  GamificationHandle._(
    this.owner,
    this.site,
    this.query,
    this.previewUserLimit,
  );
  final GamificationController owner;
  final String site;
  GamificationQuery query;
  final int? previewUserLimit;
  GamificationViewState state = const GamificationLoading();
  int _generation = 0, _retry = 0;
  bool _released = false;
  Timer? _timer;
  Future<void>? _read;
  void _publish(GamificationViewState value) {
    if (!_released) {
      state = value;
      notifySafely();
    }
  }

  void _invalidate() {
    _generation++;
    _read = null;
    _timer?.cancel();
    _timer = null;
    _publish(const GamificationUnavailable());
  }

  Future<void> selectPeriod(GamificationPeriod period) {
    query = query.withPeriod(period);
    _generation++;
    _read = null;
    _retry = 0;
    _publish(const GamificationLoading());
    return refresh();
  }

  Future<void> refresh() {
    if (_released) return Future.value();
    if (!owner.enabled(site)) {
      _invalidate();
      return Future.value();
    }
    if (_read != null && state is GamificationLoading) return _read!;
    _timer?.cancel();
    _timer = null;
    final generation = ++_generation;
    final lease = owner.requests.capture(site), revision = owner.revision(site);
    final selected = query;
    final held = state is GamificationReady
        ? (state as GamificationReady).snapshot
        : null;
    _publish(
      held == null
          ? const GamificationLoading()
          : GamificationReady(held, refreshing: true),
    );
    bool current() =>
        !_released &&
        generation == _generation &&
        owner.current(site, lease, revision);
    final task = () async {
      try {
        final auth = await owner.requests.credentialsFor(site);
        if (!current()) return;
        final result = await auth.run(
          () => owner.api.readLeaderboard(
            site,
            auth,
            selected,
            previewUserLimit: previewUserLimit,
          ),
        );
        if (!current()) return;
        switch (result) {
          case LeaderboardPreparing(:final reason):
            _publish(GamificationPreparing(reason));
            const delays = [2, 5, 10, 20];
            if (_retry < delays.length && owner._foreground) {
              _timer = Timer(Duration(seconds: delays[_retry++]), () {
                if (current()) unawaited(refresh());
              });
            }
          case LeaderboardReady(:final board, :final users, :final personal):
            _retry = 0;
            final snapshot = GamificationSnapshot(
              query: selected,
              board: board,
              users: users,
              personal: personal,
              page: 0,
              fetchedAt: owner.now(),
            );
            _publish(
              GamificationReady(
                snapshot,
                append: users.isEmpty || previewUserLimit != null
                    ? GamificationAppend.exhausted
                    : GamificationAppend.idle,
              ),
            );
        }
      } catch (error) {
        if (!current()) return;
        if (_denied(error)) {
          _publish(const GamificationRestricted());
        } else if (error is GamificationUnsupportedResponse ||
            error is FormatException ||
            error is TypeError) {
          _publish(const GamificationUnsupported());
        } else {
          _publish(
            held == null
                ? GamificationFailed(error)
                : GamificationReady(held, error: error),
          );
        }
      }
    }();
    _read = task;
    return task.whenComplete(() {
      if (identical(_read, task)) _read = null;
    });
  }

  Future<void> loadNextPage() async {
    if (_released || previewUserLimit != null) return;
    final held = state;
    if (held is! GamificationReady ||
        held.refreshing ||
        held.append == GamificationAppend.loading ||
        held.append == GamificationAppend.exhausted) {
      return;
    }
    final generation = _generation,
        lease = owner.requests.capture(site),
        revision = owner.revision(site);
    bool current() =>
        !_released &&
        generation == _generation &&
        owner.current(site, lease, revision);
    _publish(
      GamificationReady(held.snapshot, append: GamificationAppend.loading),
    );
    try {
      final auth = await owner.requests.credentialsFor(site);
      if (!current()) return;
      final result = await auth.run(
        () => owner.api.readLeaderboard(
          site,
          auth,
          query,
          page: held.snapshot.page + 1,
        ),
      );
      if (!current()) return;
      if (result is! LeaderboardReady ||
          result.board.id != held.snapshot.board.id) {
        await refresh();
        return;
      }
      final ids = held.snapshot.users.map((u) => u.id).toSet();
      if (result.users.any((u) => !ids.add(u.id))) {
        await refresh();
        return;
      }
      _publish(
        GamificationReady(
          GamificationSnapshot(
            query: query,
            board: result.board,
            users: [...held.snapshot.users, ...result.users],
            personal: result.personal,
            page: held.snapshot.page + 1,
            fetchedAt: owner.now(),
          ),
          append: result.users.isEmpty
              ? GamificationAppend.exhausted
              : GamificationAppend.idle,
        ),
      );
    } catch (error) {
      if (!current()) return;
      _publish(
        _denied(error)
            ? const GamificationRestricted()
            : GamificationReady(
                held.snapshot,
                append: GamificationAppend.failed,
                error: error,
              ),
      );
    }
  }

  void release() {
    if (_released) return;
    owner._retain(this);
    _released = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}

bool _denied(Object error) => switch (error) {
  SiteLookupException(:final statusCode) ||
  WriteException(:final statusCode) => statusCode == 403 || statusCode == 404,
  _ => false,
};

enum GamificationMutationStatus { idle, submitting, saved, failed, unknown }

final class GamificationMutation {
  const GamificationMutation(this.status, {this.operation, this.error});
  final GamificationMutationStatus status;
  final String? operation;
  final Object? error;
}

sealed class GamificationRecalculationState {
  const GamificationRecalculationState();
}

final class RecalculationIdle extends GamificationRecalculationState {
  const RecalculationIdle();
}

final class RecalculationSubmitting extends GamificationRecalculationState {
  const RecalculationSubmitting();
}

final class RecalculationQueued extends GamificationRecalculationState {
  const RecalculationQueued(
    this.requester,
    this.fromDate,
    this.lease,
    this.revision,
  );
  final int requester, revision;
  final DCalendarDate fromDate;
  final PluginSiteLease lease;
}

final class RecalculationObserved extends GamificationRecalculationState {
  const RecalculationObserved();
}

final class RecalculationUnknown extends GamificationRecalculationState {
  const RecalculationUnknown();
}

final class RecalculationFailed extends GamificationRecalculationState {
  const RecalculationFailed(this.error);
  final Object error;
}

final class GamificationAdminHandle extends FrameSafeNotifier {
  GamificationAdminHandle._(this.owner, this.site);
  final GamificationController owner;
  final String site;
  GamificationAdminIndex? index;
  GamificationGlobalSettings? settings;
  List<GamificationScoreEvent>? events;
  ScoreEventQuery eventQuery = const ScoreEventQuery();
  GamificationMutation mutation = const GamificationMutation(
    GamificationMutationStatus.idle,
  );
  GamificationRecalculationState recalculation = const RecalculationIdle();
  Object? error;
  bool loading = true, _released = false;
  int _generation = 0, _eventGeneration = 0;
  int? createdBoardId;
  GamificationBoardDraft? pendingCreatedDraft;
  PluginLiveChannelSubscription? _subscription;
  bool get canManage => !_released && owner.canManage(site);
  bool get busy => mutation.status == GamificationMutationStatus.submitting;
  bool get mayMutate =>
      canManage &&
      !busy &&
      mutation.status != GamificationMutationStatus.unknown;
  void _changed() {
    if (!_released) notifySafely();
  }

  void _invalidate() {
    _generation++;
    _eventGeneration++;
    index = null;
    settings = null;
    events = null;
    createdBoardId = null;
    pendingCreatedDraft = null;
    error = null;
    mutation = const GamificationMutation(GamificationMutationStatus.idle);
    _connectionLost();
    _changed();
  }

  void _connectionLost() {
    _subscription?.cancel();
    _subscription = null;
    if (recalculation is RecalculationQueued ||
        recalculation is RecalculationSubmitting) {
      recalculation = const RecalculationUnknown();
      _changed();
    }
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription = null;
    if (!canManage || !owner.enabled(site) || !owner._foreground) return;
    _subscription = owner._channels[site]?.subscribe('/recalculate_scores', (
      data,
      _,
    ) {
      final queued = recalculation;
      if (queued is! RecalculationQueued ||
          data is! Map ||
          data['success'] != true ||
          data['user_id'] is! List ||
          !(data['user_id'] as List).contains(queued.requester) ||
          !owner.current(site, queued.lease, queued.revision, admin: true) ||
          owner.siteState.currentUserFor(site)?.id != queued.requester) {
        return;
      }
      recalculation = const RecalculationObserved();
      _changed();
      owner.refreshPublic(site);
      unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    if (!canManage) {
      _invalidate();
      loading = false;
      _changed();
      return;
    }
    final generation = ++_generation,
        lease = owner.requests.capture(site),
        revision = owner.revision(site);
    bool current() =>
        !_released &&
        generation == _generation &&
        owner.current(site, lease, revision, admin: true);
    loading = true;
    error = null;
    _changed();
    try {
      final auth = await owner.requests.credentialsFor(site);
      if (!current()) return;
      final global = await auth.run(
        () => owner.api.readGlobalSettings(site, auth),
      );
      if (!current()) return;
      settings = global;
      if (global.enabled && owner.enabled(site)) {
        final value = await auth.run(
          () => owner.api.readAdminIndex(site, auth),
        );
        if (!current()) return;
        index = value;
      } else {
        index = null;
        events = null;
      }
    } catch (failure) {
      if (!current()) return;
      error = failure;
      if (_denied(failure)) {
        index = null;
        settings = null;
        events = null;
      }
    } finally {
      if (current()) {
        loading = false;
        _changed();
      }
    }
  }

  Future<GamificationMutation> _mutate(
    String operation,
    Future<void> Function(
      PluginRequestCredentials auth,
      bool Function() current,
    )
    work, {
    bool requiresEnabled = true,
  }) async {
    if (!mayMutate || (requiresEnabled && !owner.enabled(site))) {
      return mutation;
    }
    final generation = _generation,
        lease = owner.requests.capture(site),
        revision = owner.revision(site);
    bool current() =>
        !_released &&
        generation == _generation &&
        owner.current(site, lease, revision, admin: true);
    mutation = GamificationMutation(
      GamificationMutationStatus.submitting,
      operation: operation,
    );
    _changed();
    try {
      final auth = await owner.requests.credentialsFor(site);
      if (!current()) return mutation;
      await auth.run(() => work(auth, current));
      if (!current()) return mutation;
      mutation = GamificationMutation(
        GamificationMutationStatus.saved,
        operation: operation,
      );
      owner.refreshPublic(site);
    } catch (failure) {
      if (!current()) return mutation;
      final unknown =
          (failure is GamificationAmbiguousWrite) ||
          failure is WriteException &&
              failure.failure == WriteFailure.unreachable &&
              !failure.notSent;
      mutation = GamificationMutation(
        unknown
            ? GamificationMutationStatus.unknown
            : GamificationMutationStatus.failed,
        operation: operation,
        error: failure,
      );
      if (_denied(failure)) {
        index = null;
        settings = null;
        events = null;
      }
    }
    _changed();
    return mutation;
  }

  Future<GamificationMutation> createAndConfigure(
    GamificationBoardDraft draft,
  ) async {
    if (!draft.valid) throw ArgumentError('Invalid leaderboard draft');
    pendingCreatedDraft = draft;
    return _mutate('create', (auth, current) async {
      if (createdBoardId == null) {
        final creator = owner.siteState.currentUserFor(site)?.id;
        if (creator == null) {
          throw const WriteException(WriteFailure.forbidden, notSent: true);
        }
        final board = await owner.api.createBoard(
          site,
          auth,
          name: draft.name,
          creatorId: creator,
        );
        if (!current()) return;
        createdBoardId = board.board.id;
        _changed();
      }
      await owner.api.updateBoard(site, auth, createdBoardId!, draft);
      if (!current()) return;
      final confirmed = await owner.api.readAdminIndex(site, auth);
      if (!current()) return;
      index = confirmed;
      createdBoardId = null;
      pendingCreatedDraft = null;
    });
  }

  Future<GamificationAdminBoard?> readBoard(int id) async {
    if (!canManage || !owner.enabled(site)) return null;
    final generation = _generation,
        lease = owner.requests.capture(site),
        revision = owner.revision(site);
    bool current() =>
        !_released &&
        generation == _generation &&
        owner.current(site, lease, revision, admin: true);
    try {
      final auth = await owner.requests.credentialsFor(site);
      if (!current()) return null;
      final board = await auth.run(
        () => owner.api.readAdminBoard(site, auth, id),
      );
      return current() ? board : null;
    } catch (failure) {
      if (current()) {
        error = failure;
        if (_denied(failure)) {
          index = null;
          events = null;
        }
        _changed();
      }
      return null;
    }
  }

  Future<GamificationMutation> saveBoard(
    int id,
    GamificationBoardDraft draft,
  ) => _mutate('board', (auth, current) async {
    await owner.api.updateBoard(site, auth, id, draft);
    if (!current()) return;
    await owner.api.readAdminBoard(site, auth, id);
    if (!current()) return;
    final value = await owner.api.readAdminIndex(site, auth);
    if (current()) index = value;
  });
  Future<GamificationMutation> deleteBoard(int id) =>
      _mutate('delete', (auth, current) async {
        await owner.api.deleteBoard(site, auth, id);
        if (!current()) return;
        final value = await owner.api.readAdminIndex(site, auth);
        if (current()) index = value;
      });
  Future<GamificationMutation> saveSettings(GamificationGlobalSettings value) =>
      _mutate('settings', (auth, current) async {
        await owner.api.saveGlobalSettings(site, auth, value);
        if (!current()) return;
        final confirmed = await owner.api.readGlobalSettings(site, auth);
        if (current()) {
          settings = confirmed;
          owner._enabledOverrides[site] = confirmed.enabled;
          if (!confirmed.enabled) {
            owner._cache.removeWhere((key, _) => key.$1 == site);
            for (final h
                in owner._handles.where((h) => h.site == site).toList()) {
              h._invalidate();
            }
            index = null;
            events = null;
            _connectionLost();
          } else {
            _subscribe();
            final refreshed = await owner.api.readAdminIndex(site, auth);
            if (!current()) return;
            index = refreshed;
          }
          owner.notifySafely();
        }
      }, requiresEnabled: false);
  Future<void> queryEvents(ScoreEventQuery query) async {
    if (!canManage || !owner.enabled(site)) return;
    final generation = ++_eventGeneration,
        revision = owner.revision(site),
        lease = owner.requests.capture(site);
    bool current() =>
        !_released &&
        generation == _eventGeneration &&
        owner.current(site, lease, revision, admin: true);
    eventQuery = query;
    error = null;
    try {
      final auth = await owner.requests.credentialsFor(site);
      if (!current()) return;
      final value = await auth.run(
        () => owner.api.readScoreEvents(site, auth, query),
      );
      if (current()) events = value;
    } catch (failure) {
      if (current()) {
        error = failure;
        if (_denied(failure)) events = null;
      }
    }
    if (current()) _changed();
  }

  Future<GamificationMutation> createEvent(CreateScoreEvent event) =>
      _mutate('event', (auth, current) async {
        await owner.api.createScoreEvent(site, auth, event);
        if (!current()) return;
        final value = await owner.api.readScoreEvents(site, auth, eventQuery);
        if (current()) events = value;
      });
  Future<GamificationMutation> editEvent(EditScoreEvent event) =>
      _mutate('event', (auth, current) async {
        await owner.api.editScoreEvent(site, auth, event);
        if (!current()) return;
        final value = await owner.api.readScoreEvents(site, auth, eventQuery);
        if (current()) events = value;
      });
  Future<GamificationMutation> recalculate(DCalendarDate fromDate) async {
    if (fromDate.isAfter(DCalendarDate.fromDateTime(owner.now().toUtc())) ||
        index?.recalculationsRemaining == 0 ||
        recalculation is RecalculationQueued ||
        recalculation is RecalculationSubmitting) {
      throw ArgumentError('Invalid recalculation');
    }
    final requester = owner.siteState.currentUserFor(site)?.id;
    final lease = owner.requests.capture(site), revision = owner.revision(site);
    recalculation = const RecalculationSubmitting();
    _changed();
    final result = await _mutate('recalculate', (auth, current) async {
      await owner.api.enqueueRecalculation(site, auth, fromDate: fromDate);
      if (current() && requester != null) {
        recalculation = owner._foreground && _subscription != null
            ? RecalculationQueued(requester, fromDate, lease, revision)
            : const RecalculationUnknown();
      }
    });
    if (!_released && owner.current(site, lease, revision, admin: true)) {
      if (result.status == GamificationMutationStatus.unknown) {
        recalculation = const RecalculationUnknown();
      } else if (result.status == GamificationMutationStatus.failed) {
        recalculation = RecalculationFailed(result.error!);
      }
      _changed();
      if (result.status == GamificationMutationStatus.saved) {
        unawaited(refresh());
      }
    }
    return result;
  }

  Future<void> finishCreateLater() async {
    if (busy || mutation.status == GamificationMutationStatus.unknown) return;
    createdBoardId = null;
    pendingCreatedDraft = null;
    await refresh();
  }

  Future<void> reviewUncertainWrite() async {
    await refresh();
    if (!_released && canManage && error == null) {
      if (mutation.operation == 'create' &&
          pendingCreatedDraft != null &&
          createdBoardId == null) {
        final matches =
            index?.boards
                .where(
                  (b) =>
                      b.draft.name == pendingCreatedDraft!.name &&
                      b.board.createdById ==
                          owner.siteState.currentUserFor(site)?.id,
                )
                .toList() ??
            [];
        if (matches.length != 1) return;
        createdBoardId = matches.single.board.id;
      }
      await queryEvents(eventQuery);
      if (!_released && canManage && error == null) {
        mutation = const GamificationMutation(GamificationMutationStatus.idle);
        _changed();
      }
    }
  }

  void release() {
    if (_released) return;
    _released = true;
    _generation++;
    _eventGeneration++;
    _subscription?.cancel();
    owner._admins.remove(this);
    super.dispose();
  }
}
