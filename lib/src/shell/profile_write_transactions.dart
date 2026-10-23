part of 'shell_controller.dart';

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

final class _ProfileWriteTransactions {
  _ProfileWriteTransactions(this._shell);

  final ShellController _shell;
  final Map<String, _ProfileWriteState> _sites = {};

  _ProfileWriteState _stateFor(String siteUrl) =>
      _sites.putIfAbsent(siteUrl, _ProfileWriteState.new);

  bool? hidePresenceFor(String siteUrl) => switch (_sites[siteUrl]?.presence) {
    _ProfilePresenceWrite(:final desired) => desired,
    _ => _shell._instanceAt(siteUrl)?.user?.hidePresence,
  };

  bool presenceInFlight(String siteUrl) =>
      _sites[siteUrl]?.presence is _ProfilePresenceWrite;

  String? presenceErrorFor(String siteUrl) => _sites[siteUrl]?.presenceError;

  bool statusInFlight(String siteUrl) =>
      _sites[siteUrl]?.status?.lease.isCurrent ?? false;

  void currentUserReadFailed(String siteUrl) {
    if (_shell._instanceAt(siteUrl)?.user?.hidePresence != null ||
        presenceInFlight(siteUrl)) {
      return;
    }
    _stateFor(siteUrl).presenceError =
        appL10n.couldnTLoadThePresenceSettingTryAgain;
    _shell._notify();
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
    final instance = _shell._instanceAt(siteUrl);
    if (instance?.user == null || hidePresenceFor(siteUrl) != null) return;
    final lease = _shell.lifecycle.capture(siteUrl);
    final state = _stateFor(siteUrl);
    state.presenceError = null;
    _shell._notify();

    try {
      final credential = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(_shell.credentials);
      if (!lease.isCurrent) return;
      final apiKey = credential.apiKey;
      if (apiKey == null) {
        lease.commit(() {
          state.presenceError =
              appL10n.reconnectThisAccountToLoadItsPresenceSetting;
          _shell._notify();
        });
        return;
      }
      await _shell._sessionUser(siteUrl, apiKey, lease: lease, force: true);
    } catch (error) {
      if (_shell.accountSessionDisposed || !lease.isCurrent) return;

      lease.commit(() {
        state.presenceError = appL10n.couldnTLoadThePresenceSettingTryAgain;
        _shell._notify();
      });
    }
  }

  bool _ownsPresence(String siteUrl, _ProfilePresenceWrite write) =>
      !_shell.accountSessionDisposed &&
      write.lease.isCurrent &&
      identical(_sites[siteUrl]?.presence, write);

  Future<void> togglePresence(String siteUrl) async {
    final instance = _shell._instanceAt(siteUrl);
    final user = instance?.user;
    final held = hidePresenceFor(siteUrl);
    if (instance == null || user == null || held == null) return;
    if (presenceInFlight(siteUrl)) return;

    final write = _ProfilePresenceWrite(
      _shell.lifecycle.capture(siteUrl),
      user.username,
      !held,
    );
    final state = _stateFor(siteUrl);
    state.presence = write;
    state.presenceError = null;
    _shell._currentUserReconcilerFor(siteUrl).presenceWriteStarted();
    _shell._notify();

    try {
      final credential = await _shell._credentialForWrite(
        siteUrl,
        lease: write.lease,
        withClientId: true,
      );
      if (!_ownsPresence(siteUrl, write)) return;
      if (credential.failure case final failure?) {
        _settlePresence(siteUrl, write, error: _presenceError(failure));
        return;
      }
      await credential.request!.run(
        () => _shell.api.site.updateHidePresence(
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
      _shell._currentUserReconcilerFor(siteUrl).presenceWriteSettled();
      if (error == null) {
        final instance = _shell._instanceAt(siteUrl);
        final user = instance?.user;
        if (instance != null && user != null && confirmed != null) {
          _shell._replaceInstance(
            instance,
            instance.copyWith(user: user.withHidePresence(confirmed)),
          );
          _shell.instanceStore.save(List.of(_shell._instances)).ignore();
        }
      }
      _shell._notify();
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
      !_shell.accountSessionDisposed &&
      write.lease.isCurrent &&
      identical(_sites[siteUrl]?.status, write);

  Future<_ProfileStatusResult> writeStatus(
    String siteUrl,
    _ProfileStatusIntent submittedIntent,
  ) async {
    final instance = _shell._instanceAt(siteUrl);
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
      _shell.lifecycle.capture(siteUrl),
      userId,
      submittedIntent,
    );
    final intent = write.intent;
    final state = _stateFor(siteUrl);
    state.status = write;
    _shell._notify();
    try {
      if (!_ownsStatus(siteUrl, write)) {
        return const _ProfileStatusUnconfirmed(null);
      }
      final credential = await _shell._credentialForWrite(
        siteUrl,
        lease: write.lease,
        withClientId: true,
      );
      if (!_ownsStatus(siteUrl, write)) {
        return const _ProfileStatusUnconfirmed(null);
      }
      if (credential.failure case final failure?) {
        return _ProfileStatusUnconfirmed(failure.message);
      }
      final clientId = credential.request!.clientId;
      if (intent case _SetProfileStatus(:final endsAt?)) {
        if (!endsAt.isAfter(_shell._clock())) {
          return _ProfileStatusUnconfirmed(appL10n.chooseATimeInTheFuture);
        }
      }
      await credential.request!.run(
        () => switch (intent) {
          _SetProfileStatus() => _shell.api.site.setUserStatus(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            description: intent.description,
            emoji: intent.emoji,
            endsAt: intent.endsAt,
            clientId: clientId,
          ),
          _ClearProfileStatus() => _shell.api.site.clearUserStatus(
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
        _shell.userStatuses.record(siteUrl, write.userId, status);
        _shell._applyOwnUserStatus(siteUrl, write.userId, status);
        _shell._notify();
        _shell.instanceStore.save(List.of(_shell._instances)).ignore();
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
      final now = _shell._clock();
      if (pause && endsAt != null && !endsAt.isAfter(now)) {
        return const _ProfileStatusSaved();
      }
      final error = pause
          ? await _shell.doNotDisturb.pause(
              siteUrl,
              doNotDisturbDurationUntil(
                endsAt ?? eternalDoNotDisturbUntil,
                now: now,
              ),
            )
          : await _shell.doNotDisturb.resume(siteUrl);
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
        if (write.lease.isCurrent && !_shell.accountSessionDisposed) {
          _shell._notify();
        }
      }
    }
  }

  void forget(String siteUrl) => _sites.remove(siteUrl);

  void dispose() => _sites.clear();
}
