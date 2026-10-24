import 'package:discourse_native/l10n/strings.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/current_user_reconciler.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../models/discourse_user.dart';
import '../models/do_not_disturb.dart';
import '../models/user_status.dart';
import 'do_not_disturb_controller.dart';
import 'user_status_overrides.dart';

final class ProfileUserSnapshot {
  const ProfileUserSnapshot({required this.user, required this.statusEnabled});

  final DiscourseUser? user;
  final bool statusEnabled;
}

abstract interface class ProfileCurrentUser {
  ProfileUserSnapshot? snapshotFor(String siteUrl);
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
  const _ProfilePresenceWrite(this.account, this.username, this.desired);

  final _ProfileAccount account;
  final String username;
  final bool desired;
}

final class _ProfileStatusWrite {
  const _ProfileStatusWrite(this.account, this.userId, this.intent);

  final _ProfileAccount account;
  final int userId;
  final _ProfileStatusIntent intent;
}

final class _ProfileAccount {
  _ProfileAccount(this.siteUrl, this.lease, this.reconciler);

  final String siteUrl;
  final SiteLease lease;
  final CurrentUserReconciler reconciler;
  _ProfilePresenceWrite? presence;
  String? presenceError;
  _ProfileStatusWrite? status;
  void Function()? detach;
  bool _retired = false;

  bool get isCurrent => !_retired && lease.isCurrent;

  void retire() {
    if (_retired) return;
    _retired = true;
    detach?.call();
    detach = null;
    if (presence != null) reconciler.presenceWriteSettled();
    presence = null;
    presenceError = null;
    status = null;
  }
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

  Future<({AccountRequestCredentials? request, WriteException? failure})>
  _credentialForWrite(_ProfileAccount account, bool Function() owns) async {
    try {
      final request = await AccountRequestSession(
        account.siteUrl,
        account.lease,
      ).credentials(_ProfileCredentials(credentials, owns));
      return request.apiKey == null
          ? (
              request: null,
              failure: const WriteException(WriteFailure.forbidden),
            )
          : (request: request, failure: null);
    } catch (error) {
      return (
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

  final Map<String, _ProfileAccount> _accounts = {};

  _ProfileAccount _accountFor(String siteUrl) {
    final held = _accounts[siteUrl];
    if (held != null && _owns(held)) return held;
    held?.retire();
    final account = _ProfileAccount(
      siteUrl,
      lifecycle.capture(siteUrl),
      currentUser.reconcilerFor(siteUrl),
    );
    _accounts[siteUrl] = account;
    account.detach = account.lease.onRetire(() {
      account.retire();
      if (identical(_accounts[siteUrl], account)) _accounts.remove(siteUrl);
    });
    return account;
  }

  bool _owns(_ProfileAccount account) =>
      !_disposed &&
      account.isCurrent &&
      identical(_accounts[account.siteUrl], account);

  _ProfileAccount? _existingAccount(String siteUrl) {
    final account = _accounts[siteUrl];
    return account != null && _owns(account) ? account : null;
  }

  bool? hidePresenceFor(String siteUrl) =>
      _existingAccount(siteUrl)?.presence?.desired ??
      currentUser.snapshotFor(siteUrl)?.user?.hidePresence;

  bool presenceInFlight(String siteUrl) =>
      _existingAccount(siteUrl)?.presence != null;

  String? presenceErrorFor(String siteUrl) =>
      _existingAccount(siteUrl)?.presenceError;

  bool statusInFlight(String siteUrl) =>
      _existingAccount(siteUrl)?.status != null;

  void currentUserReadFailed(String siteUrl) {
    if (_disposed ||
        currentUser.snapshotFor(siteUrl)?.user?.hidePresence != null ||
        presenceInFlight(siteUrl)) {
      return;
    }
    _accountFor(siteUrl).presenceError =
        appL10n.couldnTLoadThePresenceSettingTryAgain;
    changed();
  }

  /// A site whose current user carries no presence setting has answered, so
  /// the setting is unavailable rather than still loading.
  void currentUserAccepted(String siteUrl, DiscourseUser user) {
    if (_disposed) return;
    if (user.hidePresence == null && !presenceInFlight(siteUrl)) {
      _accountFor(siteUrl).presenceError =
          appL10n.couldnTLoadThePresenceSettingTryAgain;
      return;
    }
    _existingAccount(siteUrl)?.presenceError = null;
  }

  Future<void> retryPresence(String siteUrl) async {
    if (_disposed) return;
    final snapshot = currentUser.snapshotFor(siteUrl);
    if (snapshot?.user == null || hidePresenceFor(siteUrl) != null) return;
    final account = _accountFor(siteUrl);
    final lease = account.lease;
    account.presenceError = null;
    changed();

    try {
      if (!_owns(account)) return;
      final credential = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(_ProfileCredentials(credentials, () => _owns(account)));
      if (!_owns(account)) return;
      final apiKey = credential.apiKey;
      if (apiKey == null) {
        account.presenceError =
            appL10n.reconnectThisAccountToLoadItsPresenceSetting;
        changed();
        return;
      }
      await currentUser.refresh(siteUrl, apiKey, lease);
    } catch (error) {
      if (!_owns(account)) return;
      account.presenceError = appL10n.couldnTLoadThePresenceSettingTryAgain;
      changed();
    }
  }

  bool _ownsPresence(_ProfilePresenceWrite write) =>
      _owns(write.account) && identical(write.account.presence, write);

  Future<void> togglePresence(String siteUrl) async {
    if (_disposed) return;
    final snapshot = currentUser.snapshotFor(siteUrl);
    final user = snapshot?.user;
    final held = hidePresenceFor(siteUrl);
    if (snapshot == null || user == null || held == null) return;
    if (presenceInFlight(siteUrl)) return;

    final account = _accountFor(siteUrl);
    final write = _ProfilePresenceWrite(account, user.username, !held);
    account.presence = write;
    account.presenceError = null;
    account.reconciler.presenceWriteStarted();
    changed();

    try {
      if (!_ownsPresence(write)) return;
      final credential = await _credentialForWrite(
        account,
        () => _ownsPresence(write),
      );
      if (!_ownsPresence(write)) return;
      if (credential.failure case final failure?) {
        _settlePresence(write, error: _presenceError(failure));
        return;
      }
      await credential.request!.run(
        () => api.updateHidePresence(
          siteUrl: siteUrl,
          apiKey: credential.request!.apiKey!,
          username: write.username,
          hidePresence: write.desired,
          clientId: credential.request!.clientId,
        ),
      );
      _settlePresence(write, confirmed: write.desired);
    } on WriteException catch (error) {
      _settlePresence(write, error: _presenceError(error));
    } catch (error) {
      _settlePresence(
        write,
        error: appL10n.couldnTUpdatePresenceCheckTheConnectionAndTryAgain,
      );
    }
  }

  void _settlePresence(
    _ProfilePresenceWrite write, {
    bool? confirmed,
    String? error,
  }) {
    if (!_ownsPresence(write)) return;
    final account = write.account;
    account.presence = null;
    account.presenceError = error;
    account.reconciler.presenceWriteSettled();
    if (error == null && confirmed != null) {
      final user = currentUser.snapshotFor(account.siteUrl)?.user;
      if (!_owns(account)) return;
      if (user != null) {
        currentUser.confirmPresence(account.siteUrl, confirmed);
        if (!_owns(account)) return;
        currentUser.persist();
        if (!_owns(account)) return;
      }
    }
    changed();
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

  bool _ownsStatus(_ProfileStatusWrite write) =>
      _owns(write.account) && identical(write.account.status, write);

  Future<_ProfileStatusResult> _writeStatus(
    String siteUrl,
    _ProfileStatusIntent submittedIntent,
  ) async {
    if (_disposed) return const _ProfileStatusUnconfirmed(null);
    final snapshot = currentUser.snapshotFor(siteUrl);
    final userId = snapshot?.user?.id;
    if (snapshot == null || userId == null || !snapshot.statusEnabled) {
      return _ProfileStatusUnconfirmed(
        appL10n.customStatusIsNotAvailableForThisAccount,
      );
    }
    if (statusInFlight(siteUrl)) {
      return _ProfileStatusUnconfirmed(
        appL10n.anotherStatusChangeIsStillFinishing,
      );
    }
    final account = _accountFor(siteUrl);
    final write = _ProfileStatusWrite(account, userId, submittedIntent);
    final intent = write.intent;
    account.status = write;
    changed();
    try {
      if (!_ownsStatus(write)) {
        return const _ProfileStatusUnconfirmed(null);
      }
      final credential = await _credentialForWrite(
        account,
        () => _ownsStatus(write),
      );
      if (!_ownsStatus(write)) {
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
      if (!_ownsStatus(write)) return const _ProfileStatusUnconfirmed(null);
      await credential.request!.run(
        () => switch (intent) {
          _SetProfileStatus() => api.setUserStatus(
            siteUrl: siteUrl,
            apiKey: credential.request!.apiKey!,
            description: intent.description,
            emoji: intent.emoji,
            endsAt: intent.endsAt,
            clientId: clientId,
          ),
          _ClearProfileStatus() => api.clearUserStatus(
            siteUrl: siteUrl,
            apiKey: credential.request!.apiKey!,
            clientId: clientId,
          ),
        },
      );
      if (!_ownsStatus(write)) {
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
      account.lease.commit(() {
        userStatuses.record(siteUrl, write.userId, status);
        if (!_ownsStatus(write)) return;
        currentUser.confirmStatus(siteUrl, write.userId, status);
        if (!_ownsStatus(write)) return;
        changed();
        if (!_ownsStatus(write)) return;
        currentUser.persist();
      });
      if (!_ownsStatus(write)) {
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
      if (!_ownsStatus(write)) return const _ProfileStatusUnconfirmed(null);
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
      if (!_ownsStatus(write)) {
        return const _ProfileStatusUnconfirmed(null);
      }
      return _ProfileStatusSaved(notificationError: error);
    } on WriteException catch (error) {
      return _ProfileStatusUnconfirmed(
        _ownsStatus(write) ? error.message : null,
      );
    } catch (error) {
      if (!_ownsStatus(write)) {
        return const _ProfileStatusUnconfirmed(null);
      }

      return _ProfileStatusUnconfirmed(
        const WriteException(WriteFailure.unreachable).message,
      );
    } finally {
      if (identical(account.status, write)) {
        account.status = null;
        if (_owns(account)) changed();
      }
    }
  }

  void forget(String siteUrl) => _accounts.remove(siteUrl)?.retire();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final account in _accounts.values.toList()) {
      account.retire();
    }
    _accounts.clear();
  }
}

final class _ProfileCredentials implements ApiCredentialReader {
  const _ProfileCredentials(this._source, this._owns);

  final ApiCredentialReader _source;
  final bool Function() _owns;

  void _requireCurrent() {
    if (!_owns()) throw const AccountRequestRetiredException();
  }

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    _requireCurrent();
    final key = await _source.apiKeyFor(siteUrl);
    _requireCurrent();
    return key;
  }

  @override
  Future<String> clientId() async {
    _requireCurrent();
    final id = await _source.clientId();
    _requireCurrent();
    return id;
  }
}
