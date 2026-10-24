part of 'shell_controller.dart';

final class _SiteLiveDemand {
  const _SiteLiveDemand({
    required this.foreground,
    required this.selected,
    required this.connected,
    required this.loginRequired,
    required this.retained,
  });

  final bool foreground;
  final bool selected;
  final bool connected;
  final bool loginRequired;
  final bool retained;

  bool get shouldPoll =>
      (!loginRequired || connected) &&
      (retained || (foreground && (selected || connected)));

  bool get watchesVisibleTopics => shouldPoll && foreground && selected;
}

final class _SiteLiveSessions {
  _SiteLiveSessions(this._shell);

  final ShellController _shell;
  final Map<String, _SiteLiveSession> _sessions = {};
  bool _disposed = false;

  _SiteLiveDemand demandFor(String siteUrl) {
    final site = _shell._instanceAt(siteUrl);
    return _SiteLiveDemand(
      foreground: _shell._foreground,
      selected: site != null && _shell.currentInstance?.url == siteUrl,
      connected: site?.isConnected ?? false,
      loginRequired: site?.loginRequired ?? true,
      retained: _shell._backgroundRetention.retains(siteUrl),
    );
  }

  _SiteLiveSession _forSite(String siteUrl) {
    final held = _sessions[siteUrl];
    if (held != null && held.isCurrent) return held;
    held?.retire();
    return _sessions[siteUrl] = _SiteLiveSession(
      _shell,
      siteUrl,
      _shell.lifecycle.capture(siteUrl),
      this,
    );
  }

  SiteTracker? trackerFor(String siteUrl) => _sessions[siteUrl]?.tracker;
  Future<void>? starting(String siteUrl) => _sessions[siteUrl]?.starting;

  void synchronize() {
    if (_disposed) return;
    for (final session in _sessions.values.toList()) {
      session.synchronize();
    }
    for (final site in List.of(_shell._instances)) {
      if (demandFor(site.url).shouldPoll) _forSite(site.url).synchronize();
    }
  }

  void resume({required bool resyncTracking}) {
    for (final session in _sessions.values.toList()) {
      session.resume(resyncTracking: resyncTracking);
    }
  }

  void retryTracking(String siteUrl) => _sessions[siteUrl]?.retryTracking();
  void clearRetry(String siteUrl) => _sessions[siteUrl]?.clearRetry();

  void accountChanged(String siteUrl, SiteLease lease) {
    if (_disposed || !lease.isCurrent) return;
    final session = _sessions[siteUrl];
    if (session == null || !identical(session.lease.session, lease.session)) {
      return;
    }
    session.clearRetry();
    if (session._state is! _SiteLiveReady) return;
    forget(siteUrl);
    if (lease.isCurrent && demandFor(siteUrl).shouldPoll) {
      _forSite(siteUrl).synchronize();
    }
  }

  Future<void> loadTracking({
    required String siteUrl,
    required String username,
    required SiteLease lease,
    required TopicTrackingReconciler tracking,
    required TopicTrackingSnapshot ticket,
    Future<void> Function()? refreshCategoryPreferences,
    AccountRequestCredentials? requestCredentials,
  }) async {
    if (_disposed || !lease.isCurrent) return;
    final account = _shell._topicTracking.matching(siteUrl, lease, tracking);
    if (account == null) return;
    await _forSite(siteUrl).loadTracking(
      username: username,
      account: account,
      ticket: ticket,
      refreshCategoryPreferences: refreshCategoryPreferences,
      requestCredentials: requestCredentials,
    );
  }

  void forget(String siteUrl) => _sessions.remove(siteUrl)?.retire();

  void dispose() {
    _disposed = true;
    for (final session in _sessions.values) {
      session.retire();
    }
    _sessions.clear();
  }
}

sealed class _SiteLiveState {}

final class _SiteLiveIdle extends _SiteLiveState {}

final class _SiteLiveStarting extends _SiteLiveState {
  final settled = Completer<void>();
  SiteTracker? tracker;
}

final class _SiteLiveReady extends _SiteLiveState {
  _SiteLiveReady(this.tracker);
  final SiteTracker tracker;
}

final class _SiteLiveRetired extends _SiteLiveState {}

final class _SiteLiveSession {
  _SiteLiveSession(this._shell, this.siteUrl, this.lease, this._owner) {
    _unobserveRetirement = lease.onRetire(retire);
  }

  final ShellController _shell;
  final String siteUrl;
  final SiteLease lease;
  final _SiteLiveSessions _owner;
  _SiteLiveState _state = _SiteLiveIdle();
  void Function() _unobserveRetirement = () {};
  ({
    TopicTrackingAccount account,
    Future<void> Function(TopicTrackingSnapshot) load,
  })?
  _retry;

  bool get isCurrent =>
      _state is! _SiteLiveRetired && !_owner._disposed && lease.isCurrent;
  _SiteLiveDemand get demand => _owner.demandFor(siteUrl);
  Future<void>? get starting => switch (_state) {
    _SiteLiveStarting(:final settled) => settled.future,
    _ => null,
  };
  SiteTracker? get tracker => !isCurrent
      ? null
      : switch (_state) {
          _SiteLiveStarting(:final tracker) => tracker,
          _SiteLiveReady(:final tracker) => tracker,
          _ => null,
        };

  void synchronize() {
    if (!isCurrent) return;
    final desired = demand;
    if (_state case _SiteLiveReady(:final tracker)) {
      if (!desired.selected) tracker.unwatchTopic();
      if (desired.watchesVisibleTopics) {
        _shell._syncTopicWatch(siteUrl, tracker);
      }
      if (!isCurrent) return;
      if (demand.shouldPoll) {
        tracker.start();
      } else {
        tracker.stop();
      }
    } else if (_state is _SiteLiveIdle && desired.shouldPoll) {
      final instance = _shell._instanceAt(siteUrl);
      if (instance == null) return;
      final attempt = _SiteLiveStarting();
      _state = attempt;
      attempt.settled.complete(
        _start(instance, attempt).whenComplete(() {
          if (identical(_state, attempt)) {
            _state = _SiteLiveIdle();
            attempt.tracker?.dispose().ignore();
          }
        }),
      );
      unawaited(attempt.settled.future);
    }
  }

  void resume({required bool resyncTracking}) {
    if (!isCurrent || !demand.shouldPoll) return;
    if (_state case _SiteLiveReady(:final tracker)) {
      tracker.pollNow();
      retryTracking();
      if (resyncTracking) this.resyncTracking();
    }
  }

  void clearRetry() => _retry = null;

  void retryTracking() {
    final retry = _retry;
    clearRetry();
    if (retry == null || !isCurrent || !retry.account.isCurrent) {
      return;
    }
    final ticket = retry.account.reconciler.beginSnapshot();
    if (ticket != null) unawaited(retry.load(ticket));
  }

  void retire() {
    final closing = switch (_state) {
      _SiteLiveStarting(:final tracker) => tracker,
      _SiteLiveReady(:final tracker) => tracker,
      _ => null,
    };
    _state = _SiteLiveRetired();
    clearRetry();
    _unobserveRetirement();
    closing?.dispose().ignore();
  }

  Future<void> _start(
    DiscourseInstance instance,
    _SiteLiveStarting attempt,
  ) async {
    if (!isCurrent || !demand.shouldPoll) return;

    final String? apiKey;
    final String? clientId;
    final AccountRequestCredentials requestCredentials;
    try {
      // The persisted account state, not a credential that may have failed
      // to delete, decides whether this session may open private channels.
      final requestSession = AccountRequestSession(siteUrl, lease);
      requestCredentials = instance.isConnected
          ? await requestSession.credentials(_shell.credentials)
          : requestSession.anonymousCredentials();
      apiKey = requestCredentials.apiKey;
      // An anonymous bus sends no client id, and a signed-out forum must not
      // raise the platform's notification prompt by reading one.
      clientId = apiKey == null ? null : requestCredentials.clientId;
    } catch (error) {
      if (!isCurrent) return;

      return;
    }

    if (!isCurrent) return;

    final currentUserOwner = _shell._currentUsers.reconcilerFor(siteUrl);
    final userSnapshot = currentUserOwner.beginSnapshot();
    final bootstrapTrackingAccount = apiKey == null || clientId == null
        ? null
        : _shell._topicTracking.capture(siteUrl, lease: lease);
    final bootstrapTrackingOwner = bootstrapTrackingAccount?.reconciler;
    final bootstrapTicket = bootstrapTrackingOwner?.beginBootstrap();
    final bootstrap = apiKey == null || clientId == null
        ? null
        : await _messageBusBootstrap(requestCredentials: requestCredentials);
    if (!isCurrent) return;
    final bootstrapUser = bootstrap?.currentUser;
    final freshBootstrapUser = bootstrapUser == null
        ? null
        : _shell._currentUsers.acceptSnapshot(
            siteUrl,
            bootstrapUser,
            lease,
            userSnapshot,
          );

    final userId = apiKey == null
        ? null
        : freshBootstrapUser?.id ??
              await _shell._accountId(siteUrl, apiKey: apiKey, lease: lease);
    if (!isCurrent) return;
    final initialLastIds =
        bootstrap?.initialLastIds(userId: userId) ?? const {};

    lease.commit(() {
      final current = _shell._instanceAt(siteUrl);
      if (!isCurrent || current == null) {
        if (bootstrapTicket != null) {
          bootstrapTrackingOwner?.cancelBootstrap(bootstrapTicket);
        }
        return;
      }

      if (!demand.shouldPoll) {
        if (bootstrapTicket != null) {
          bootstrapTrackingOwner?.cancelBootstrap(bootstrapTicket);
        }
        return;
      }

      bool ownsTracker() =>
          isCurrent &&
          switch (_state) {
            _SiteLiveStarting() => identical(_state, attempt),
            _SiteLiveReady(:final tracker) => identical(
              tracker,
              attempt.tracker,
            ),
            _ => false,
          };

      void commit(SiteMutation mutation) {
        if (ownsTracker()) lease.commit(mutation);
      }

      final account = _shell._topicTracking.capture(siteUrl, lease: lease);
      if (account == null) return;
      final tracking = account.reconciler;
      final bootstrapState = bootstrap?.currentUserState;
      if (bootstrapState != null) {
        _shell._acceptLiveNotificationState(siteUrl, bootstrapState, lease);
        if (!isCurrent || !account.isCurrent) return;
        _shell.accountActivity.applyReviewableCounts(siteUrl, bootstrapState);
      }
      if (!isCurrent || !account.isCurrent) return;

      final trackingUsername = apiKey == null
          ? null
          : freshBootstrapUser?.username ?? current.user?.username;
      final currentBootstrapTicket = identical(tracking, bootstrapTrackingOwner)
          ? bootstrapTicket
          : tracking.beginBootstrap();
      final bootstrapTracking = bootstrap?.topicTrackingState;
      if (trackingUsername != null &&
          userId != null &&
          bootstrapTracking != null &&
          currentBootstrapTicket != null &&
          currentUserOwner.categoryPreferencesAreCurrent(userSnapshot) &&
          bootstrap!.hasCompleteTopicTrackingSnapshot(userId) &&
          tracking.completeBootstrap(
            currentBootstrapTicket,
            bootstrapTracking,
          )) {
        clearRetry();
        if (_shell.currentInstance?.url == siteUrl) _shell._notify();
      } else if (currentBootstrapTicket != null) {
        tracking.cancelBootstrap(currentBootstrapTicket);
      }
      final loadTicket = trackingUsername == null || tracking.hasSnapshot
          ? null
          : tracking.beginSnapshot();
      final shouldLoadTopicTracking = loadTicket != null;
      if (shouldLoadTopicTracking) {
        clearRetry();
      }

      if (!isCurrent || !account.isCurrent) return;
      final SiteTracker tracker;
      try {
        tracker = _shell.trackers(
          siteUrl: siteUrl,
          userId: userId,
          apiKey: apiKey,
          clientId: clientId,
          initialLastIds: initialLastIds,
          shouldLongPoll: () => ownsTracker() && demand.shouldPoll,
          onIncomingTopics: () => commit(() {
            if (_shell.currentInstance?.url == siteUrl) {
              _shell._notifyLiveChange();
            }
          }),
          // A superseded account's tracker must not judge by, or leave hints
          // in, the filter its successor now owns at the same URL.
          admitIncoming: (data) =>
              ownsTracker() && account.admitsIncoming(data),
          onNotifications: (data) => commit(
            () => _shell._acceptLiveNotificationState(siteUrl, data, lease),
          ),
          onReviewableCounts: (data) => commit(
            () => _shell.accountActivity.applyReviewableCounts(siteUrl, data),
          ),
        );
      } catch (error) {
        if (loadTicket != null) tracking.cancelSnapshot(loadTicket);

        return;
      }
      if (!isCurrent || !account.isCurrent) {
        tracker.dispose().ignore();
        if (loadTicket != null) tracking.cancelSnapshot(loadTicket);
        return;
      }
      attempt.tracker = tracker;
      _shell._trackIncomingLists(siteUrl);
      if (apiKey != null && clientId != null) {
        if (userId != null) {
          try {
            tracker.watchTopicTrackingState(
              userId,
              (data) => commit(
                () => account.accept(data, retryBeforeAccept: retryTracking),
              ),
              lastIds: initialLastIds,
            );
          } catch (_) {}
        }
        if (shouldLoadTopicTracking) {
          unawaited(
            loadTracking(
              username: trackingUsername!,
              account: account,
              ticket: loadTicket,
              requestCredentials: requestCredentials,
            ),
          );
        }
        if (!isCurrent || !account.isCurrent) return;
        try {
          tracker.watchPluginChannel(
            '/user-status',
            (data) =>
                commit(() => _shell._applyUserStatusMessage(siteUrl, data)),
            lastId:
                bootstrap?.currentUser?.status?.messageBusLastId ??
                _shell._instanceAt(siteUrl)?.user?.status?.messageBusLastId,
          );
        } catch (_) {}
        try {
          tracker.watchPluginChannel(
            '/refresh-sidebar-sections',
            (_) => commit(
              () => _shell._customSidebar.invalidate(siteUrl, account: lease),
            ),
          );
        } catch (_) {}
        if (userId != null) {
          try {
            tracker.watchPluginChannel(
              '/user-drafts/$userId',
              (data) =>
                  commit(() => _shell._applyUserDraftsMessage(siteUrl, data)),
            );
          } catch (_) {}
          try {
            final user = _shell._instanceAt(siteUrl)?.user;
            tracker.watchPluginChannel(
              '/do-not-disturb/$userId',
              (data) =>
                  commit(() => _shell.doNotDisturb.applyMessage(siteUrl, data)),
              lastId:
                  bootstrap?.currentUser?.doNotDisturbChannelPosition ??
                  user?.doNotDisturbChannelPosition,
            );
          } catch (_) {}
        }
      }
      if (!isCurrent || !account.isCurrent) return;
      for (final owned
          in _shell._pluginSession
              .ownedCapabilities<PluginTrackerAttachment>()) {
        if (!isCurrent || !account.isCurrent) return;
        try {
          owned.capability.attachPluginTracker(
            siteUrl,
            tracker.pluginLiveChannels(
              _shell.plugins.liveChannelScopesFor(owned.owner),
            ),
          );
        } catch (_) {}
      }
      if (!isCurrent || !account.isCurrent) return;
      if (demand.watchesVisibleTopics) _shell._syncTopicWatch(siteUrl, tracker);
      if (!isCurrent || !account.isCurrent) return;
      _state = _SiteLiveReady(tracker);
      synchronize();
    });
  }

  Future<SiteMessageBusBootstrap?> _messageBusBootstrap({
    required AccountRequestCredentials requestCredentials,
  }) async {
    try {
      final bootstrap = await RequestIntent.background().run(
        () => requestCredentials.run(
          () => _shell.api.site.messageBusBootstrap(
            siteUrl: siteUrl,
            apiKey: requestCredentials.apiKey!,
            clientId: requestCredentials.clientId,
          ),
        ),
      );
      if (!isCurrent) return null;
      if (bootstrap != null) {
        _shell._serverPluginNames[siteUrl] = bootstrap.serverPluginNames;
        _shell._notify();
      }
      return bootstrap;
    } catch (error) {
      return null;
    }
  }

  Future<void> loadTracking({
    required String username,
    required TopicTrackingAccount account,
    required TopicTrackingSnapshot ticket,
    Future<void> Function()? refreshCategoryPreferences,
    AccountRequestCredentials? requestCredentials,
  }) async {
    final tracking = account.reconciler;
    bool ownsLoad() => isCurrent && account.owns(ticket);
    AccountRequestCredentials? heldCredentials = requestCredentials;
    try {
      if (!ownsLoad()) return;
      if (refreshCategoryPreferences != null) {
        await refreshCategoryPreferences();
        if (!ownsLoad() || !tracking.preferencesReady(ticket)) return;
      }
      final credential =
          heldCredentials ??
          await AccountRequestSession(
            siteUrl,
            lease,
          ).credentials(_shell.credentials);
      heldCredentials = credential;
      if (!ownsLoad()) return;
      if (credential.apiKey == null) {
        tracking.cancelSnapshot(ticket);
        return;
      }
      final snapshot = await RequestIntent.background().run(
        () => credential.run(
          () => _shell.api.site.topicTrackingState(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            username: username,
            clientId: credential.clientId,
          ),
        ),
      );
      if (!ownsLoad()) return;
      final currentUsername = _shell._instanceAt(siteUrl)?.user?.username;
      if (currentUsername?.toLowerCase() != username.toLowerCase()) return;
      lease.commit(() {
        if (ownsLoad() && tracking.completeSnapshot(ticket, snapshot)) {
          clearRetry();
          if (_shell.currentInstance?.url == siteUrl) _shell._notify();
        }
      });
    } catch (error) {
      if (ownsLoad()) {
        tracking.failSnapshot(ticket);
        _retry = (
          account: account,
          load: (nextTicket) => loadTracking(
            username: username,
            account: account,
            ticket: nextTicket,
            refreshCategoryPreferences: refreshCategoryPreferences,
            requestCredentials: heldCredentials,
          ),
        );
      }
    } finally {
      if (ownsLoad()) tracking.cancelSnapshot(ticket);
    }
  }

  void resyncTracking() {
    if (!isCurrent) return;
    final username = _shell._instanceAt(siteUrl)?.user?.username;
    final account = _shell._topicTracking.existing(siteUrl);
    if (username == null || account?.reconciler.hasSnapshot != true) return;
    final tracking = account!.reconciler;
    final ticket = tracking.beginSnapshot();
    if (ticket == null) return;
    clearRetry();
    bool ownsResync() => isCurrent && account.owns(ticket);
    unawaited(() async {
      try {
        final requestCredentials = await AccountRequestSession(
          siteUrl,
          lease,
        ).credentials(_shell.credentials);
        if (!ownsResync()) return;
        if (requestCredentials.apiKey == null) {
          tracking.cancelSnapshot(ticket);
          return;
        }
        await loadTracking(
          username: username,
          account: account,
          ticket: ticket,
          requestCredentials: requestCredentials,
        );
      } catch (error) {
        if (ownsResync()) {
          tracking.cancelSnapshot(ticket);
        }
      }
    }());
  }
}
