import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/foundation.dart';

import 'gamification_api.dart';
import 'gamification_models.dart';
import 'gamification_route.dart';

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
    required this.lease,
    required this.permissionRevision,
  }) : users = List.unmodifiable(users);
  final GamificationQuery query;
  final GamificationLeaderboard board;
  final List<GamificationRankedUser> users;
  final GamificationPersonalRank personal;
  final int page;
  final DateTime fetchedAt;
  final PluginSiteLease lease;
  final int permissionRevision;
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
  final _enabledOverrides = <String, bool>{};
  int _permissionRevision = 0;
  final _deniedBoards = <(String, int), int>{};
  final _deniedSites = <String, int>{};
  bool _permits(String site, int board, int revision) =>
      (_deniedSites[site] ?? 0) <= revision &&
      (_deniedBoards[(site, board)] ?? 0) <= revision;
  bool _usableSnapshot(String site, GamificationSnapshot snapshot) =>
      !isDisposed &&
      snapshot.lease.isCurrent &&
      _permits(site, snapshot.board.id, snapshot.permissionRevision);
  void _deny(String site, GamificationQuery query) {
    final board = query.target.id;
    final revision = ++_permissionRevision;
    if (board == null) {
      _deniedSites[site] = revision;
    } else {
      _deniedBoards[(site, board)] = revision;
    }
    _cache.removeWhere(
      (key, snapshot) =>
          key.$1 == site && (board == null || snapshot.board.id == board),
    );
    for (final h
        in _handles
            .where(
              (h) =>
                  h.site == site &&
                  (board == null ||
                      h.query.target.id == board ||
                      h._heldBoardId == board),
            )
            .toList()) {
      h._restrict();
    }
  }

  final _settings = <String, (Listenable, VoidCallback)>{};
  final _channels = <String, PluginLiveChannelHandle>{};
  final _cache = <(String, int, GamificationQuery), GamificationSnapshot>{};
  bool _foreground = true;
  int revision(String site) => _revisions[site] ?? 0;
  bool installed(String site) =>
      !isDisposed &&
      siteState.siteConfigFor(site).plugins.get(gamificationSettingsKey) !=
          null;
  bool enabled(String site) {
    _observe(site);
    return installed(site) &&
        (_enabledOverrides[site] ??
            siteState
                .siteConfigFor(site)
                .plugins
                .get(gamificationSettingsKey)!
                .enabled);
  }

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
    if (isDisposed || _settings.containsKey(site)) return;
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
    if (enabled(site) && cached != null && _usableSnapshot(site, cached)) {
      handle.state = GamificationReady(cached);
      if (elapsedSince(cached.fetchedAt, now: now()) >=
          const Duration(seconds: 60)) {
        unawaited(handle.refresh());
      }
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
    if (state is! GamificationReady ||
        state.error != null ||
        !_usableSnapshot(handle.site, state.snapshot)) {
      return;
    }
    final key = (handle.site, revision(handle.site), handle.query);
    _cache.remove(key);
    _cache[key] = state.snapshot;
    while (_cache.length > 8) {
      _cache.remove(_cache.keys.first);
    }
  }

  void _confirmEnablement(
    String site,
    bool value,
    GamificationAdminHandle source,
  ) {
    final wasEnabled = enabled(site);
    _enabledOverrides[site] = value;
    if (!value) {
      _cache.removeWhere((key, _) => key.$1 == site);
      for (final h in _handles.where((h) => h.site == site).toList()) {
        h._invalidate();
      }
      source.index = null;
      source.events = null;
      source._connectionLost();
      if (wasEnabled) {
        for (final h
            in _admins
                .where((h) => h.site == site && !identical(h, source))
                .toList()) {
          h._invalidate();
          unawaited(h.refresh());
        }
      }
    }
    notifySafely();
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
    _invalidate(site);
    final held = _settings.remove(site);
    if (held != null) held.$1.removeListener(held.$2);
    _channels.remove(site);
    _deniedSites.remove(site);
    _deniedBoards.removeWhere((key, _) => key.$1 == site);
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
    _deniedBoards.clear();
    _deniedSites.clear();
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
  GamificationViewState _state = const GamificationLoading();
  int? get _heldBoardId => _state is GamificationReady
      ? (_state as GamificationReady).snapshot.board.id
      : null;
  GamificationViewState get state {
    final held = _state;
    if (held is GamificationReady) {
      if (owner.isDisposed || !held.snapshot.lease.isCurrent) {
        return const GamificationUnavailable();
      }
      if (!owner._usableSnapshot(site, held.snapshot)) {
        return const GamificationRestricted();
      }
    }
    return held;
  }

  set state(GamificationViewState value) {
    _state = value;
  }

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

  void _restrict() {
    _generation++;
    _read = null;
    _timer?.cancel();
    _timer = null;
    _publish(const GamificationRestricted());
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
    final selected = query, permissionRevision = owner._permissionRevision;
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
        final resolved = switch (result) {
          LeaderboardReady(:final board) => board,
          LeaderboardPreparing(:final board) => board,
        };
        if (resolved != null &&
            !owner._permits(site, resolved.id, permissionRevision)) {
          _publish(const GamificationRestricted());
          return;
        }
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
              lease: lease,
              permissionRevision: permissionRevision,
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
          owner._deny(site, selected);
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
        revision = owner.revision(site),
        permissionRevision = owner._permissionRevision;
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
      if (!owner._permits(site, result.board.id, permissionRevision)) {
        _publish(const GamificationRestricted());
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
            lease: lease,
            permissionRevision: permissionRevision,
          ),
          append: result.users.isEmpty
              ? GamificationAppend.exhausted
              : GamificationAppend.idle,
        ),
      );
    } catch (error) {
      if (!current()) return;
      if (_denied(error)) {
        owner._deny(site, query);
      } else {
        _publish(
          GamificationReady(
            held.snapshot,
            append: GamificationAppend.failed,
            error: error,
          ),
        );
      }
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

sealed class RecalculationPending extends GamificationRecalculationState {
  const RecalculationPending(
    this.requester,
    this.fromDate,
    this.lease,
    this.revision,
  );
  final int requester, revision;
  final DCalendarDate fromDate;
  final PluginSiteLease lease;
}

final class RecalculationSubmitting extends RecalculationPending {
  const RecalculationSubmitting(
    super.requester,
    super.fromDate,
    super.lease,
    super.revision,
  );
}

final class RecalculationQueued extends RecalculationPending {
  const RecalculationQueued(
    super.requester,
    super.fromDate,
    super.lease,
    super.revision,
  );
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
  GamificationAdminHandle._(this.owner, this.site)
    : _accountLease = owner.requests.capture(site);
  final GamificationController owner;
  final String site;
  PluginSiteLease _accountLease;
  GamificationAdminIndex? _index;
  GamificationGlobalSettings? _globalSettings;
  List<GamificationScoreEvent>? _events;
  GamificationAdminIndex? get index => canManage ? _index : null;
  set index(GamificationAdminIndex? value) {
    _index = value;
  }

  GamificationGlobalSettings? get settings =>
      canManage ? _globalSettings : null;
  set settings(GamificationGlobalSettings? value) {
    _globalSettings = value;
  }

  List<GamificationScoreEvent>? get events => canManage ? _events : null;
  set events(List<GamificationScoreEvent>? value) {
    _events = value;
  }

  ScoreEventQuery eventQuery = const ScoreEventQuery();
  GamificationMutation mutation = const GamificationMutation(
    GamificationMutationStatus.idle,
  );
  GamificationRecalculationState recalculation = const RecalculationIdle();
  Object? error;
  bool loading = true, eventsLoading = false, _released = false;
  int _generation = 0, _readGeneration = 0, _eventGeneration = 0;
  bool _refreshAfterMutation = false, _eventsAfterMutation = false;
  int? createdBoardId;
  GamificationBoardDraft? pendingCreatedDraft;
  PluginLiveChannelSubscription? _subscription;
  Timer? _completionTimer;
  bool get canManage =>
      !_released && _accountLease.isCurrent && owner.canManage(site);
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
    _accountLease = owner.requests.capture(site);
    _readGeneration++;
    _eventGeneration++;
    _refreshAfterMutation = false;
    _eventsAfterMutation = false;
    index = null;
    settings = null;
    events = null;
    createdBoardId = null;
    pendingCreatedDraft = null;
    lastCreatedEvent = null;
    error = null;
    mutation = const GamificationMutation(GamificationMutationStatus.idle);
    _connectionLost();
    recalculation = const RecalculationIdle();
    eventsLoading = false;
    _changed();
  }

  void _connectionLost() {
    _completionTimer?.cancel();
    _completionTimer = null;
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
      if (queued is! RecalculationPending ||
          data is! Map ||
          data['success'] != true ||
          data['user_id'] is! List ||
          !(data['user_id'] as List).contains(queued.requester) ||
          !owner.current(site, queued.lease, queued.revision, admin: true) ||
          owner.siteState.currentUserFor(site)?.id != queued.requester) {
        return;
      }
      _completionTimer?.cancel();
      _completionTimer = null;
      recalculation = const RecalculationObserved();
      _changed();
      owner.refreshPublic(site);
      if (!busy) unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    if (!canManage) {
      _invalidate();
      loading = false;
      _changed();
      return;
    }
    if (busy) {
      _refreshAfterMutation = true;
      return;
    }
    final generation = ++_readGeneration,
        lifetime = _generation,
        lease = owner.requests.capture(site),
        revision = owner.revision(site);
    bool current() =>
        !_released &&
        generation == _readGeneration &&
        lifetime == _generation &&
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
      owner._confirmEnablement(site, global.enabled, this);
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
    if (!canManage || (requiresEnabled && !owner.enabled(site))) {
      return const GamificationMutation(
        GamificationMutationStatus.failed,
        error: WriteException(WriteFailure.forbidden, notSent: true),
      );
    }
    if (!mayMutate) return mutation;
    _readGeneration++;
    _eventGeneration++;
    loading = false;
    eventsLoading = false;
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
    final refreshDeferred = _refreshAfterMutation,
        eventsDeferred = _eventsAfterMutation;
    _refreshAfterMutation = false;
    _eventsAfterMutation = false;
    if (refreshDeferred) unawaited(refresh());
    if (eventsDeferred) unawaited(queryEvents(eventQuery));
    return mutation;
  }

  Future<GamificationMutation> createAndConfigure(
    GamificationBoardDraft draft,
  ) async {
    if (!canManage) {
      return const GamificationMutation(
        GamificationMutationStatus.failed,
        error: WriteException(WriteFailure.forbidden, notSent: true),
      );
    }
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
    if (!canManage || !owner.enabled(site) || busy) return null;
    final generation = _generation,
        readGeneration = _readGeneration,
        lease = owner.requests.capture(site),
        revision = owner.revision(site);
    bool current() =>
        !_released &&
        generation == _generation &&
        readGeneration == _readGeneration &&
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
          owner._confirmEnablement(site, confirmed.enabled, this);
          if (confirmed.enabled) {
            _subscribe();
            final refreshed = await owner.api.readAdminIndex(site, auth);
            if (!current()) return;
            index = refreshed;
          }
        }
      }, requiresEnabled: false);
  Future<void> queryEvents(ScoreEventQuery query) async {
    if (!canManage || !owner.enabled(site)) return;
    if (busy) {
      eventQuery = query;
      events = null;
      eventsLoading = true;
      _eventsAfterMutation = true;
      _changed();
      return;
    }
    final generation = ++_eventGeneration,
        revision = owner.revision(site),
        lease = owner.requests.capture(site);
    bool current() =>
        !_released &&
        generation == _eventGeneration &&
        owner.current(site, lease, revision, admin: true);
    eventQuery = query;
    events = null;
    eventsLoading = true;
    error = null;
    _changed();
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
    if (current()) {
      eventsLoading = false;
      _changed();
    }
  }

  GamificationScoreEvent? lastCreatedEvent;
  Future<GamificationMutation> createEvent(CreateScoreEvent event) async {
    final result = await _mutate('event', (auth, current) async {
      final saved = await owner.api.createScoreEvent(site, auth, event);
      if (current()) lastCreatedEvent = saved;
    });
    if (result.status == GamificationMutationStatus.saved) {
      await queryEvents(eventQuery);
    }
    return result;
  }

  Future<GamificationMutation> editEvent(EditScoreEvent event) async {
    final result = await _mutate('event', (auth, current) async {
      await owner.api.editScoreEvent(site, auth, event);
    });
    if (result.status == GamificationMutationStatus.saved) {
      await queryEvents(eventQuery);
    }
    return result;
  }

  Future<GamificationMutation> recalculate(DCalendarDate fromDate) async {
    if (!canManage || !owner.enabled(site)) {
      return const GamificationMutation(
        GamificationMutationStatus.failed,
        error: WriteException(WriteFailure.forbidden, notSent: true),
      );
    }
    if (fromDate.isAfter(DCalendarDate.fromDateTime(owner.now().toUtc())) ||
        index?.recalculationsRemaining == 0 ||
        recalculation is RecalculationQueued ||
        recalculation is RecalculationSubmitting) {
      throw ArgumentError('Invalid recalculation');
    }
    final requester = owner.siteState.currentUserFor(site)?.id;
    final lease = owner.requests.capture(site), revision = owner.revision(site);
    if (requester == null) return mutation;
    recalculation = RecalculationSubmitting(
      requester,
      fromDate,
      lease,
      revision,
    );
    _changed();
    final result = await _mutate('recalculate', (auth, current) async {
      await owner.api.enqueueRecalculation(site, auth, fromDate: fromDate);
      if (current() && recalculation is RecalculationSubmitting) {
        recalculation = owner._foreground && _subscription != null
            ? RecalculationQueued(requester, fromDate, lease, revision)
            : const RecalculationUnknown();
        if (recalculation is RecalculationQueued) {
          _completionTimer?.cancel();
          _completionTimer = Timer(const Duration(minutes: 5), () {
            if (!_released &&
                recalculation is RecalculationQueued &&
                owner.current(site, lease, revision, admin: true)) {
              recalculation = const RecalculationUnknown();
              _changed();
            }
          });
        }
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
    _readGeneration++;
    _eventGeneration++;
    _subscription?.cancel();
    _completionTimer?.cancel();
    owner._admins.remove(this);
    super.dispose();
  }
}
