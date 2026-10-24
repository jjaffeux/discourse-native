import 'package:discourse_native/l10n/strings.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/current_user_reconciler.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/do_not_disturb.dart';
import '../models/user_status.dart';
import 'do_not_disturb_controller.dart';
import 'user_status_overrides.dart';

abstract interface class ProfileCurrentUser {
  DiscourseInstance? instanceFor(String siteUrl);
  CurrentUserReconciler reconcilerFor(String siteUrl);
  Future<void> refresh(String siteUrl, String apiKey, SiteLease lease);
  void confirmPresence(String siteUrl, bool hidden);
  void confirmStatus(String siteUrl, int userId, UserStatus? status);
  void persist();
}

sealed class _ProfileStatusIntent {
  const _ProfileStatusIntent();
}

final class _SetProfileStatus extends _ProfileStatusIntent {
  const _SetProfileStatus({
    required this.description,
    required this.emoji,
    this.endsAt,
    this.pauseNotifications,
  });

  final String description;
  final String emoji;
  final DateTime? endsAt;
  final bool? pauseNotifications;
}

final class _ClearProfileStatus extends _ProfileStatusIntent {
  const _ClearProfileStatus();
}

sealed class _ProfileStatusResult {
  const _ProfileStatusResult(this.message);

  final String? message;
}

final class _ProfileStatusSaved extends _ProfileStatusResult {
  const _ProfileStatusSaved({String? notificationError})
    : super(notificationError);
}

final class _ProfileStatusUnconfirmed extends _ProfileStatusResult {
  const _ProfileStatusUnconfirmed(super.message);
}

final class _ProfilePresenceWrite {
  const _ProfilePresenceWrite(this.lease, this.username, this.desired);

  final SiteLease lease;
  final String username;
  final bool desired;
}

final class _ProfileStatusWrite {
  const _ProfileStatusWrite(this.lease, this.userId, this.intent);

  final SiteLease lease;
  final int userId;
  final _ProfileStatusIntent intent;
}

final class _ProfileWriteState {
  _ProfilePresenceWrite? presence;
  String? presenceError;
  _ProfileStatusWrite? status;
}

final class ProfileWriteTransactions {
  ProfileWriteTransactions({
    required this.currentUser,
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.userStatuses,
    required this.doNotDisturb,
    required this.changed,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ProfileCurrentUser currentUser;
  final ShellSiteApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final UserStatusOverrides userStatuses;
  final DoNotDisturbController doNotDisturb;
  final void Function() changed;
  final DateTime Function() _clock;
  bool _disposed = false;

  Future<
    ({
      String? apiKey,
      AccountRequestCredentials? request,
      WriteException? failure,
    })
  >
  _credentialForWrite(String siteUrl, {required SiteLease lease}) async {
    try {
      final request = await AccountRequestSession(
        siteUrl,
        lease,
      ).credentials(credentials);
      return request.apiKey == null
          ? (
              apiKey: null,
              request: null,
              failure: const WriteException(WriteFailure.forbidden),
            )
          : (apiKey: request.apiKey, request: request, failure: null);
    } catch (error) {
      return (
        apiKey: null,
        request: null,
        failure: const WriteException(WriteFailure.unreachable),
      );
    }
  }

  Future<String?> setStatus(
    String siteUrl, {
    required String description,
    required String emoji,
    DateTime? endsAt,
    bool? pauseNotifications,
  }) async => (await _writeStatus(
    siteUrl,
    _SetProfileStatus(
      description: description,
      emoji: emoji,
      endsAt: endsAt,
      pauseNotifications: pauseNotifications,
    ),
  )).message;

  Future<String?> clearStatus(String siteUrl) async =>
      (await _writeStatus(siteUrl, const _ClearProfileStatus())).message;
  final Map<String, _ProfileWriteState> _sites = {};

  _ProfileWriteState _stateFor(String siteUrl) =>
      _sites.putIfAbsent(siteUrl, _ProfileWriteState.new);

  bool? hidePresenceFor(String siteUrl) => switch (_sites[siteUrl]?.presence) {
    _ProfilePresenceWrite(:final desired) => desired,
    _ => currentUser.instanceFor(siteUrl)?.user?.hidePresence,
  };

  bool presenceInFlight(String siteUrl) =>
      _sites[siteUrl]?.presence is _ProfilePresenceWrite;

  String? presenceErrorFor(String siteUrl) => _sites[siteUrl]?.presenceError;

  bool statusInFlight(String siteUrl) =>
      _sites[siteUrl]?.status?.lease.isCurrent ?? false;

  void currentUserReadFailed(String siteUrl) {
    if (currentUser.instanceFor(siteUrl)?.user?.hidePresence != null ||
        presenceInFlight(siteUrl)) {
      return;
    }
    _stateFor(siteUrl).presenceError =
        appL10n.couldnTLoadThePresenceSettingTryAgain;
    changed();
  }

  /// A site whose current user carries no presence setting has answered, so
  /// the setting is unavailable rather than still loading.
  void currentUserAccepted(String siteUrl, DiscourseUser user) {
    if (user.hidePresence == null && !presenceInFlight(siteUrl)) {
      _stateFor(siteUrl).presenceError =
          appL10n.couldnTLoadThePresenceSettingTryAgain;
      return;
    }
    _sites[siteUrl]?.presenceError = null;
  }

  Future<void> retryPresence(String siteUrl) async {
    final instance = currentUser.instanceFor(siteUrl);
    if (instance?.user == null || hidePresenceFor(siteUrl) != null) return;
    final lease = lifecycle.capture(siteUrl);
    final state = _stateFor(siteUrl);
    state.presenceError = null;
    changed();

    try {
      final credential = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(credentials);
      if (!lease.isCurrent) return;
      final apiKey = credential.apiKey;
      if (apiKey == null) {
        lease.commit(() {
          state.presenceError =
              appL10n.reconnectThisAccountToLoadItsPresenceSetting;
          changed();
        });
        return;
      }
      await currentUser.refresh(siteUrl, apiKey, lease);
    } catch (error) {
      if (_disposed || !lease.isCurrent) return;

      lease.commit(() {
        state.presenceError = appL10n.couldnTLoadThePresenceSettingTryAgain;
        changed();
      });
    }
  }

  bool _ownsPresence(String siteUrl, _ProfilePresenceWrite write) =>
      !_disposed &&
      write.lease.isCurrent &&
      identical(_sites[siteUrl]?.presence, write);

  Future<void> togglePresence(String siteUrl) async {
    final instance = currentUser.instanceFor(siteUrl);
    final user = instance?.user;
    final held = hidePresenceFor(siteUrl);
    if (instance == null || user == null || held == null) return;
    if (presenceInFlight(siteUrl)) return;

    final write = _ProfilePresenceWrite(
      lifecycle.capture(siteUrl),
      user.username,
      !held,
    );
    final state = _stateFor(siteUrl);
    state.presence = write;
    state.presenceError = null;
    currentUser.reconcilerFor(siteUrl).presenceWriteStarted();
    changed();

    try {
      final credential = await _credentialForWrite(siteUrl, lease: write.lease);
      if (!_ownsPresence(siteUrl, write)) return;
      if (credential.failure case final failure?) {
        _settlePresence(siteUrl, write, error: _presenceError(failure));
        return;
      }
      await credential.request!.run(
        () => api.updateHidePresence(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          username: write.username,
          hidePresence: write.desired,
          clientId: credential.request!.clientId,
        ),
      );
      _settlePresence(siteUrl, write, confirmed: write.desired);
    } on WriteException catch (error) {
      _settlePresence(siteUrl, write, error: _presenceError(error));
    } catch (error) {
      _settlePresence(
        siteUrl,
        write,
        error: appL10n.couldnTUpdatePresenceCheckTheConnectionAndTryAgain,
      );
    }
  }

  void _settlePresence(
    String siteUrl,
    _ProfilePresenceWrite write, {
    bool? confirmed,
    String? error,
  }) {
    if (!_ownsPresence(siteUrl, write)) return;
    write.lease.commit(() {
      final state = _sites[siteUrl]!;
      state.presence = null;
      state.presenceError = error;
      currentUser.reconcilerFor(siteUrl).presenceWriteSettled();
      if (error == null) {
        final instance = currentUser.instanceFor(siteUrl);
        final user = instance?.user;
        if (instance != null && user != null && confirmed != null) {
          currentUser.confirmPresence(siteUrl, confirmed);
          currentUser.persist();
        }
      }
      changed();
    });
  }

  String _presenceError(WriteException error) {
    if (error.errors.isNotEmpty) return error.errors.join('\n');
    return switch (error.failure) {
      WriteFailure.validation => appL10n.theSiteDidnTAcceptThatPresenceSetting,
      WriteFailure.rateLimited => switch (error.retryAfter) {
        final wait? => appL10n.tooFastTryChangingPresenceAgainInS(
          (wait.inSeconds).toString(),
        ),
        null => appL10n.tooFastTryChangingPresenceAgainInAMoment,
      },
      WriteFailure.forbidden =>
        appL10n.presenceCouldNotBeChangedReconnectThisAccountAndTryAgain,
      WriteFailure.conflict =>
        appL10n.presenceChangedSomewhereElseTryAgainToUseThisSetting,
      WriteFailure.unreachable =>
        appL10n.couldnTUpdatePresenceCheckTheConnectionAndTryAgain,
    };
  }

  bool _ownsStatus(String siteUrl, _ProfileStatusWrite write) =>
      !_disposed &&
      write.lease.isCurrent &&
      identical(_sites[siteUrl]?.status, write);

  Future<_ProfileStatusResult> _writeStatus(
    String siteUrl,
    _ProfileStatusIntent submittedIntent,
  ) async {
    final instance = currentUser.instanceFor(siteUrl);
    final userId = instance?.user?.id;
    if (instance == null ||
        userId == null ||
        !instance.config.userStatusEnabled) {
      return _ProfileStatusUnconfirmed(
        appL10n.customStatusIsNotAvailableForThisAccount,
      );
    }
    if (statusInFlight(siteUrl)) {
      return _ProfileStatusUnconfirmed(
        appL10n.anotherStatusChangeIsStillFinishing,
      );
    }
    final write = _ProfileStatusWrite(
      lifecycle.capture(siteUrl),
      userId,
      submittedIntent,
    );
    final intent = write.intent;
    final state = _stateFor(siteUrl);
    state.status = write;
    changed();
    try {
      if (!_ownsStatus(siteUrl, write)) {
        return const _ProfileStatusUnconfirmed(null);
      }
      final credential = await _credentialForWrite(siteUrl, lease: write.lease);
      if (!_ownsStatus(siteUrl, write)) {
        return const _ProfileStatusUnconfirmed(null);
      }
      if (credential.failure case final failure?) {
        return _ProfileStatusUnconfirmed(failure.message);
      }
      final clientId = credential.request!.clientId;
      if (intent case _SetProfileStatus(:final endsAt?)) {
        if (!endsAt.isAfter(_clock())) {
          return _ProfileStatusUnconfirmed(appL10n.chooseATimeInTheFuture);
        }
      }
      await credential.request!.run(
        () => switch (intent) {
          _SetProfileStatus() => api.setUserStatus(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            description: intent.description,
            emoji: intent.emoji,
            endsAt: intent.endsAt,
            clientId: clientId,
          ),
          _ClearProfileStatus() => api.clearUserStatus(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            clientId: clientId,
          ),
        },
      );
      if (!_ownsStatus(siteUrl, write)) {
        return const _ProfileStatusUnconfirmed(null);
      }
      final status = switch (intent) {
        _SetProfileStatus() => UserStatus(
          description: intent.description.trim(),
          emoji: intent.emoji
              .trim()
              .replaceFirst(RegExp(r'^:'), '')
              .replaceFirst(RegExp(r':$'), ''),
          endsAt: intent.endsAt?.toUtc(),
        ),
        _ClearProfileStatus() => null,
      };
      write.lease.commit(() {
        userStatuses.record(siteUrl, write.userId, status);
        currentUser.confirmStatus(siteUrl, write.userId, status);
        changed();
        currentUser.persist();
      });
      if (!_ownsStatus(siteUrl, write)) {
        return const _ProfileStatusUnconfirmed(null);
      }
      final pause = switch (intent) {
        _SetProfileStatus() => intent.pauseNotifications,
        _ClearProfileStatus() => false,
      };
      if (pause == null) return const _ProfileStatusSaved();
      final endsAt = switch (intent) {
        _SetProfileStatus() => intent.endsAt,
        _ClearProfileStatus() => null,
      };
      final now = _clock();
      if (pause && endsAt != null && !endsAt.isAfter(now)) {
        return const _ProfileStatusSaved();
      }
      final error = pause
          ? await doNotDisturb.pause(
              siteUrl,
              doNotDisturbDurationUntil(
                endsAt ?? eternalDoNotDisturbUntil,
                now: now,
              ),
            )
          : await doNotDisturb.resume(siteUrl);
      if (!_ownsStatus(siteUrl, write)) {
        return const _ProfileStatusUnconfirmed(null);
      }
      return _ProfileStatusSaved(notificationError: error);
    } on WriteException catch (error) {
      return _ProfileStatusUnconfirmed(
        _ownsStatus(siteUrl, write) ? error.message : null,
      );
    } catch (error) {
      if (!_ownsStatus(siteUrl, write)) {
        return const _ProfileStatusUnconfirmed(null);
      }

      return _ProfileStatusUnconfirmed(
        const WriteException(WriteFailure.unreachable).message,
      );
    } finally {
      if (identical(_sites[siteUrl]?.status, write)) {
        state.status = null;
        if (write.lease.isCurrent && !_disposed) {
          changed();
        }
      }
    }
  }

  void forget(String siteUrl) => _sites.remove(siteUrl);

  void dispose() {
    _disposed = true;
    _sites.clear();
  }
}
