import 'dart:async';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/current_user_reconciler.dart';
import '../data/discourse_api_contracts.dart';
import '../data/request_intent.dart';
import '../data/site_lifecycle.dart';
import '../data/site_message_bus_bootstrap.dart';
import '../data/site_tracker.dart';
import '../data/topic_tracking_reconciler.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../plugin_api/live_channels.dart';
import '../plugin_api/plugin_manifest.dart';
import 'topic_tracking_directory.dart';

abstract interface class SiteLiveCurrentUsers {
  DiscourseInstance? instanceAt(String siteUrl);
  CurrentUserReconciler reconcilerFor(String siteUrl);
  DiscourseUser? acceptSnapshot(
    String siteUrl,
    DiscourseUser user,
    SiteLease lease,
    CurrentUserSnapshot ticket,
  );
  Future<int?> accountId(
    String siteUrl, {
    required String apiKey,
    required SiteLease lease,
  });
}

enum SiteLiveMessage {
  notifications,
  reviewableCounts,
  userStatus,
  userDrafts,
  doNotDisturb,
  refreshSidebar,
}

enum SiteLiveChange { tracking, incomingTopics }

typedef SiteLivePluginAttachment = ({
  Set<PluginLiveChannelScope> scopes,
  void Function(String siteUrl, PluginLiveChannelHandle channels) attach,
});

abstract interface class SiteLiveComposition {
  void bootstrapReceived(String siteUrl, SiteMessageBusBootstrap bootstrap);
  void changed(String siteUrl, SiteLiveChange change);
  void acceptMessage(
    String siteUrl,
    SiteLease lease,
    SiteLiveMessage kind,
    Object? data,
  );
  void trackIncomingLists(String siteUrl);
  void synchronizeVisibleTopics(String siteUrl, SiteTracker tracker);
  Iterable<SiteLivePluginAttachment> get pluginAttachments;
}

final class SiteLiveDemand {
  const SiteLiveDemand({
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

final class SiteLiveSessions {
  SiteLiveSessions({
    required this._lifecycle,
    required this._credentials,
    required this._api,
    required this._trackers,
    required this._topicTracking,
    required this._currentUsers,
    required this._composition,
    required this._demandSnapshot,
  });

  final SiteLifecycle _lifecycle;
  final ApiCredentialReader _credentials;
  final ShellSiteApi _api;
  final SiteTrackerFactory _trackers;
  final TopicTrackingDirectory _topicTracking;
  final SiteLiveCurrentUsers _currentUsers;
  final SiteLiveComposition _composition;
  final Map<String, SiteLiveDemand> Function() _demandSnapshot;
  final Map<String, _SiteLiveSession> _sessions = {};
  bool _disposed = false;

  SiteLiveDemand demandFor(String siteUrl) =>
      _demandSnapshot()[siteUrl] ??
      const SiteLiveDemand(
        foreground: false,
        selected: false,
        connected: false,
        loginRequired: true,
        retained: false,
      );

  _SiteLiveSession _forSite(String siteUrl) {
    final held = _sessions[siteUrl];
    if (held != null && held.isCurrent) return held;
    held?.retire();
    return _sessions[siteUrl] = _SiteLiveSession(
      siteUrl,
      _lifecycle.capture(siteUrl),
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
    for (final siteUrl in _demandSnapshot().keys.toList()) {
      if (demandFor(siteUrl).shouldPoll) _forSite(siteUrl).synchronize();
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
    final account = _topicTracking.matching(siteUrl, lease, tracking);
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
  _SiteLiveSession(this.siteUrl, this.lease, this._owner) {
    _unobserveRetirement = lease.onRetire(retire);
  }

  final String siteUrl;
  final SiteLease lease;
  final SiteLiveSessions _owner;
  _SiteLiveState _state = _SiteLiveIdle();
  void Function() _unobserveRetirement = () {};
  ({
    TopicTrackingAccount account,
    Future<void> Function(TopicTrackingSnapshot) load,
  })?
  _retry;

  bool get isCurrent =>
      _state is! _SiteLiveRetired && !_owner._disposed && lease.isCurrent;
  SiteLiveDemand get demand => _owner.demandFor(siteUrl);
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
        _owner._composition.synchronizeVisibleTopics(siteUrl, tracker);
      }
      if (!isCurrent) return;
      if (demand.shouldPoll) {
        tracker.start();
      } else {
        tracker.stop();
      }
    } else if (_state is _SiteLiveIdle && desired.shouldPoll) {
      final instance = _owner._currentUsers.instanceAt(siteUrl);
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
          ? await requestSession.credentials(_owner._credentials)
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

    final currentUserOwner = _owner._currentUsers.reconcilerFor(siteUrl);
    final userSnapshot = currentUserOwner.beginSnapshot();
    final bootstrapTrackingAccount = apiKey == null || clientId == null
        ? null
        : _owner._topicTracking.capture(siteUrl, lease: lease);
    final bootstrapTrackingOwner = bootstrapTrackingAccount?.reconciler;
    final bootstrapTicket = bootstrapTrackingOwner?.beginBootstrap();
    final bootstrap = apiKey == null || clientId == null
        ? null
        : await _messageBusBootstrap(requestCredentials: requestCredentials);
    if (!isCurrent) return;
    final bootstrapUser = bootstrap?.currentUser;
    final freshBootstrapUser = bootstrapUser == null
        ? null
        : _owner._currentUsers.acceptSnapshot(
            siteUrl,
            bootstrapUser,
            lease,
            userSnapshot,
          );

    final userId = apiKey == null
        ? null
        : freshBootstrapUser?.id ??
              await _owner._currentUsers.accountId(
                siteUrl,
                apiKey: apiKey,
                lease: lease,
              );
    if (!isCurrent) return;
    final initialLastIds =
        bootstrap?.initialLastIds(userId: userId) ?? const {};

    lease.commit(() {
      final current = _owner._currentUsers.instanceAt(siteUrl);
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

      final account = _owner._topicTracking.capture(siteUrl, lease: lease);
      if (account == null) return;
      final tracking = account.reconciler;
      final bootstrapState = bootstrap?.currentUserState;
      if (bootstrapState != null) {
        _owner._composition.acceptMessage(
          siteUrl,
          lease,
          SiteLiveMessage.notifications,
          bootstrapState,
        );
        if (!isCurrent || !account.isCurrent) return;
        _owner._composition.acceptMessage(
          siteUrl,
          lease,
          SiteLiveMessage.reviewableCounts,
          bootstrapState,
        );
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
        _owner._composition.changed(siteUrl, SiteLiveChange.tracking);
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
        tracker = _owner._trackers(
          siteUrl: siteUrl,
          userId: userId,
          apiKey: apiKey,
          clientId: clientId,
          initialLastIds: initialLastIds,
          shouldLongPoll: () => ownsTracker() && demand.shouldPoll,
          onIncomingTopics: () => commit(() {
            _owner._composition.changed(siteUrl, SiteLiveChange.incomingTopics);
          }),
          // A superseded account's tracker must not judge by, or leave hints
          // in, the filter its successor now owns at the same URL.
          admitIncoming: (data) =>
              ownsTracker() && account.admitsIncoming(data),
          onNotifications: (data) => commit(
            () => _owner._composition.acceptMessage(
              siteUrl,
              lease,
              SiteLiveMessage.notifications,
              data,
            ),
          ),
          onReviewableCounts: (data) => commit(
            () => _owner._composition.acceptMessage(
              siteUrl,
              lease,
              SiteLiveMessage.reviewableCounts,
              data,
            ),
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
      _owner._composition.trackIncomingLists(siteUrl);
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
            (data) => commit(
              () => _owner._composition.acceptMessage(
                siteUrl,
                lease,
                SiteLiveMessage.userStatus,
                data,
              ),
            ),
            lastId:
                bootstrap?.currentUser?.status?.messageBusLastId ??
                _owner._currentUsers
                    .instanceAt(siteUrl)
                    ?.user
                    ?.status
                    ?.messageBusLastId,
          );
        } catch (_) {}
        try {
          tracker.watchPluginChannel(
            '/refresh-sidebar-sections',
            (_) => commit(
              () => _owner._composition.acceptMessage(
                siteUrl,
                lease,
                SiteLiveMessage.refreshSidebar,
                null,
              ),
            ),
          );
        } catch (_) {}
        if (userId != null) {
          try {
            tracker.watchPluginChannel(
              '/user-drafts/$userId',
              (data) => commit(
                () => _owner._composition.acceptMessage(
                  siteUrl,
                  lease,
                  SiteLiveMessage.userDrafts,
                  data,
                ),
              ),
            );
          } catch (_) {}
          try {
            final user = _owner._currentUsers.instanceAt(siteUrl)?.user;
            tracker.watchPluginChannel(
              '/do-not-disturb/$userId',
              (data) => commit(
                () => _owner._composition.acceptMessage(
                  siteUrl,
                  lease,
                  SiteLiveMessage.doNotDisturb,
                  data,
                ),
              ),
              lastId:
                  bootstrap?.currentUser?.doNotDisturbChannelPosition ??
                  user?.doNotDisturbChannelPosition,
            );
          } catch (_) {}
        }
      }
      if (!isCurrent || !account.isCurrent) return;
      for (final attachment in _owner._composition.pluginAttachments) {
        if (!isCurrent || !account.isCurrent) return;
        try {
          attachment.attach(
            siteUrl,
            tracker.pluginLiveChannels(attachment.scopes),
          );
        } catch (_) {}
      }
      if (!isCurrent || !account.isCurrent) return;
      if (demand.watchesVisibleTopics) {
        _owner._composition.synchronizeVisibleTopics(siteUrl, tracker);
      }
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
          () => _owner._api.messageBusBootstrap(
            siteUrl: siteUrl,
            apiKey: requestCredentials.apiKey!,
            clientId: requestCredentials.clientId,
          ),
        ),
      );
      if (!isCurrent) return null;
      if (bootstrap != null) {
        _owner._composition.bootstrapReceived(siteUrl, bootstrap);
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
          ).credentials(_owner._credentials);
      heldCredentials = credential;
      if (!ownsLoad()) return;
      if (credential.apiKey == null) {
        tracking.cancelSnapshot(ticket);
        return;
      }
      final snapshot = await RequestIntent.background().run(
        () => credential.run(
          () => _owner._api.topicTrackingState(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            username: username,
            clientId: credential.clientId,
          ),
        ),
      );
      if (!ownsLoad()) return;
      final currentUsername = _owner._currentUsers
          .instanceAt(siteUrl)
          ?.user
          ?.username;
      if (currentUsername?.toLowerCase() != username.toLowerCase()) return;
      lease.commit(() {
        if (ownsLoad() && tracking.completeSnapshot(ticket, snapshot)) {
          clearRetry();
          _owner._composition.changed(siteUrl, SiteLiveChange.tracking);
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
    final username = _owner._currentUsers.instanceAt(siteUrl)?.user?.username;
    final account = _owner._topicTracking.existing(siteUrl);
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
        ).credentials(_owner._credentials);
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
