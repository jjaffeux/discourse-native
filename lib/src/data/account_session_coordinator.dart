import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import '../models/discourse_instance.dart';
import 'account_request_session.dart';
import 'authenticator.dart';
import 'discourse_api_contracts.dart';
import 'draft_store.dart';
import 'instance_store.dart';
import 'site_lifecycle.dart';
import 'user_api_key.dart';

enum AccountSessionPhase {
  connecting,
  connected,
  disconnecting,
  disconnected,
  restored,
  rolledBack,
}

abstract interface class AccountSessionHost {
  bool get accountSessionDisposed;

  List<DiscourseInstance> get accountSessionInstances;

  DiscourseInstance? accountSessionInstance(String siteUrl);

  void clearAccountSessionState(String siteUrl);

  DiscourseInstance? applyAccountSessionInstance(
    DiscourseInstance replacement,
    AccountSessionPhase phase,
  );
}

sealed class AccountConnectionResult {
  const AccountConnectionResult._();
}

final class AccountConnected extends AccountConnectionResult {
  const AccountConnected(this.instance, this.apiKey) : super._();

  final DiscourseInstance instance;
  final String apiKey;
}

final class AccountConnectionCancelled extends AccountConnectionResult {
  const AccountConnectionCancelled() : super._();
}

final class AccountConnectionFailed extends AccountConnectionResult {
  const AccountConnectionFailed(
    this.message, {
    required this.refreshSignedOutPresentation,
  }) : super._();

  final String message;
  final bool refreshSignedOutPresentation;
}

final class AccountConnectionStale extends AccountConnectionResult {
  const AccountConnectionStale() : super._();
}

final class AccountConnectionMissing extends AccountConnectionResult {
  const AccountConnectionMissing() : super._();
}

sealed class AccountDisconnectionResult {
  const AccountDisconnectionResult._();
}

final class AccountDisconnected extends AccountDisconnectionResult {
  const AccountDisconnected(this.lease) : super._();

  final SiteLease lease;
}

final class AccountDisconnectionFailed extends AccountDisconnectionResult {
  const AccountDisconnectionFailed() : super._();
}

final class AccountDisconnectionStale extends AccountDisconnectionResult {
  const AccountDisconnectionStale(this.lease) : super._();

  final SiteLease lease;
}

final class AccountDisconnectionMissing extends AccountDisconnectionResult {
  const AccountDisconnectionMissing() : super._();
}

/// Owns the durable account boundary across public metadata and private state.
///
/// A forum is signed out in its durable instance snapshot before a replacement
/// credential is written or an existing credential is deleted. Lifecycle and
/// cache rotations surround every published identity, so no completion from a
/// retired account can enter the replacement session.
final class AccountSessionCoordinator {
  AccountSessionCoordinator({
    required this.authenticator,
    required this.instances,
    required this.drafts,
    required this.lifecycle,
    required this.api,
    required this.host,
  });

  final Authenticator authenticator;
  final InstanceStore instances;
  final DraftStore drafts;
  final SiteLifecycle lifecycle;
  final ShellSiteApi api;
  final AccountSessionHost host;

  final Map<String, Object> _operations = {};

  Future<AccountConnectionResult> connect(String siteUrl) async {
    final operation = _begin(siteUrl);
    final initial = host.accountSessionInstance(siteUrl);
    if (initial == null) {
      _finish(siteUrl, operation);
      return const AccountConnectionMissing();
    }

    String? previousKey;
    UserApiCredentials? credentials;
    var pendingPublished = false;
    var credentialsPersisted = false;

    try {
      previousKey = await authenticator.apiKeyFor(siteUrl);
      if (!_isCurrent(siteUrl, operation)) {
        return const AccountConnectionStale();
      }

      credentials = await authenticator.authorize(siteUrl);
      if (!_isCurrent(siteUrl, operation)) {
        await _revokeIssued(siteUrl, credentials.key);
        return const AccountConnectionStale();
      }

      final pendingLease = _rotate(siteUrl, operation);
      if (pendingLease == null) {
        await _revokeIssued(siteUrl, credentials.key);
        return const AccountConnectionStale();
      }
      final held = host.accountSessionInstance(siteUrl);
      if (held == null) {
        await _revokeIssued(siteUrl, credentials.key);
        return const AccountConnectionMissing();
      }
      final pending = held.copyWith(
        apiVersion: credentials.apiVersion,
        clearUser: true,
        clearConfig: true,
        clearAppearance: true,
      );
      if (host.applyAccountSessionInstance(
            pending,
            AccountSessionPhase.connecting,
          ) ==
          null) {
        await _revokeIssued(siteUrl, credentials.key);
        return const AccountConnectionMissing();
      }
      pendingPublished = true;
      if (!_isCurrent(siteUrl, operation, pendingLease)) {
        await _revokeIssued(siteUrl, credentials.key);
        return const AccountConnectionStale();
      }
      await instances.save(List.of(host.accountSessionInstances));
      if (!_isCurrent(siteUrl, operation, pendingLease)) {
        await _revokeIssued(siteUrl, credentials.key);
        return const AccountConnectionStale();
      }

      final user = await api.currentUser(
        siteUrl: siteUrl,
        apiKey: credentials.key,
      );
      if (!_isCurrent(siteUrl, operation, pendingLease)) {
        await _revokeIssued(siteUrl, credentials.key);
        return const AccountConnectionStale();
      }

      await authenticator.persistCredentials(siteUrl, credentials);
      credentialsPersisted = true;
      if (!_isCurrent(siteUrl, operation, pendingLease)) {
        return const AccountConnectionStale();
      }

      if (previousKey != null && previousKey != credentials.key) {
        await _revokeBestEffort(
          siteUrl,
          previousKey,

          ifCurrent: () => _isCurrent(siteUrl, operation, pendingLease),
        );
      }
      if (!_isCurrent(siteUrl, operation, pendingLease)) {
        return const AccountConnectionStale();
      }

      final connectedLease = _rotate(siteUrl, operation);
      if (connectedLease == null) {
        return const AccountConnectionStale();
      }
      final latest = host.accountSessionInstance(siteUrl);
      if (latest == null) return const AccountConnectionMissing();
      final applied = host.applyAccountSessionInstance(
        latest.copyWith(user: user, apiVersion: credentials.apiVersion),
        AccountSessionPhase.connected,
      );
      if (applied == null) return const AccountConnectionMissing();
      if (!_isCurrent(siteUrl, operation, connectedLease)) {
        return const AccountConnectionStale();
      }
      await instances.save(List.of(host.accountSessionInstances));
      if (!_isCurrent(siteUrl, operation, connectedLease)) {
        return const AccountConnectionStale();
      }
      return AccountConnected(applied, credentials.key);
    } on UserApiAuthException catch (error) {
      if (credentials != null) {
        final recovered = await _recoverConnection(
          siteUrl: siteUrl,
          operation: operation,
          initial: initial,
          credentials: credentials,
          credentialsPersisted: credentialsPersisted,
          error: error,
        );
        return recovered;
      }
      if (!_isCurrent(siteUrl, operation)) {
        return const AccountConnectionStale();
      }
      if (error.failure == UserApiAuthFailure.cancelled) {
        return const AccountConnectionCancelled();
      }

      return AccountConnectionFailed(
        error.message,
        refreshSignedOutPresentation: false,
      );
    } on SiteLookupException catch (error) {
      if (credentials == null) {
        if (!_isCurrent(siteUrl, operation)) {
          return const AccountConnectionStale();
        }

        return AccountConnectionFailed(
          error.message,
          refreshSignedOutPresentation: false,
        );
      }
      final recovered = await _recoverConnection(
        siteUrl: siteUrl,
        operation: operation,
        initial: initial,
        credentials: credentials,
        credentialsPersisted: credentialsPersisted,
        error: error,
      );
      return recovered;
    } catch (error) {
      if (credentials == null || !pendingPublished) {
        if (credentials != null) {
          await _revokeIssued(siteUrl, credentials.key);
        }
        if (!_isCurrent(siteUrl, operation)) {
          return const AccountConnectionStale();
        }

        return AccountConnectionFailed(
          appL10n.couldNotConnectTo((initial.host).toString()),
          refreshSignedOutPresentation: false,
        );
      }
      final recovered = await _recoverConnection(
        siteUrl: siteUrl,
        operation: operation,
        initial: initial,
        credentials: credentials,
        credentialsPersisted: credentialsPersisted,
        error: error,
      );
      return recovered;
    } finally {
      _finish(siteUrl, operation);
    }
  }

  Future<AccountConnectionResult> _recoverConnection({
    required String siteUrl,
    required Object operation,
    required DiscourseInstance initial,
    required UserApiCredentials credentials,
    required bool credentialsPersisted,
    required Object error,
  }) async {
    if (!_isCurrent(siteUrl, operation)) {
      return const AccountConnectionStale();
    }

    var refreshSignedOutPresentation = false;
    if (!credentialsPersisted) {
      final recoveryLease = _rotate(siteUrl, operation);
      if (recoveryLease == null) {
        return const AccountConnectionStale();
      }
      host.applyAccountSessionInstance(initial, AccountSessionPhase.restored);
      await _repairSnapshot(siteUrl, operation, recoveryLease);
      await _revokeIssued(siteUrl, credentials.key);
    } else {
      final recoveryLease = _rotate(siteUrl, operation);
      if (recoveryLease == null) {
        return const AccountConnectionStale();
      }
      final held = host.accountSessionInstance(siteUrl);
      if (held != null) {
        host.applyAccountSessionInstance(
          held.copyWith(
            apiVersion: credentials.apiVersion,
            clearUser: true,
            clearConfig: true,
            clearAppearance: true,
          ),
          AccountSessionPhase.rolledBack,
        );
      }
      await _repairSnapshot(siteUrl, operation, recoveryLease);
      await _revokeIssued(siteUrl, credentials.key);
      if (_isCurrent(siteUrl, operation, recoveryLease)) {
        try {
          await authenticator.disconnect(siteUrl);
          refreshSignedOutPresentation = initial.loginRequired == false;
        } catch (_) {}
      }
    }

    if (!_isCurrent(siteUrl, operation)) {
      return const AccountConnectionStale();
    }
    final message = switch (error) {
      UserApiAuthException(:final message) => message,
      SiteLookupException(:final message) => message,
      _ => appL10n.couldNotConnectTo((initial.host).toString()),
    };
    return AccountConnectionFailed(
      message,
      refreshSignedOutPresentation: refreshSignedOutPresentation,
    );
  }

  Future<AccountDisconnectionResult> disconnect(
    String siteUrl, {
    bool waitForRemoteRevocation = true,
  }) async {
    final operation = _begin(siteUrl);
    final initial = host.accountSessionInstance(siteUrl);
    if (initial == null) {
      _finish(siteUrl, operation);
      return const AccountDisconnectionMissing();
    }

    try {
      final lease = _rotate(siteUrl, operation);
      if (lease == null) {
        return AccountDisconnectionStale(lifecycle.capture(siteUrl));
      }

      if (await _enterSignedOut(siteUrl, operation, lease, initial)
          case final aborted?) {
        return aborted;
      }

      try {
        await drafts.clearSite(
          DraftStore.accountSiteKey(siteUrl, initial.localDraftAccount),
          ifCurrent: () => _isCurrent(siteUrl, operation, lease),
        );
      } catch (_) {
        return await _restoreFailedDisconnect(
          siteUrl,
          operation,
          lease,
          initial,
        );
      }
      if (!_isCurrent(siteUrl, operation, lease)) {
        return AccountDisconnectionStale(lease);
      }

      String? apiKey;
      try {
        apiKey = await authenticator.apiKeyFor(siteUrl);
      } catch (_) {}
      if (!_isCurrent(siteUrl, operation, lease)) {
        return AccountDisconnectionStale(lease);
      }
      if (apiKey != null) {
        final revocation = _revokeBestEffort(
          siteUrl,
          apiKey,

          ifCurrent: () => _isCurrent(siteUrl, operation, lease),
        );
        if (waitForRemoteRevocation) {
          await revocation;
        } else {
          // The captured key belongs to this account alone. A forum removal
          // can forget it locally while the request settles; a late answer
          // must neither hold the forum in the rail nor change a new account.
          unawaited(revocation);
        }
      }
      if (!_isCurrent(siteUrl, operation, lease)) {
        return AccountDisconnectionStale(lease);
      }
      return await _forgetCredential(siteUrl, operation, lease);
    } finally {
      _finish(siteUrl, operation);
    }
  }

  /// Signs a forum out locally once its site has refused [apiKey] itself.
  ///
  /// Nothing sent with a refused key can revoke it, so only the local copy is
  /// deleted. The refusal speaks for [apiKey] as read under [lease] alone: a
  /// connection or disconnection already under way owns the forum, and a key
  /// stored since belongs to a newer sign-in, so either leaves it untouched.
  /// Unsent drafts stay in their original account namespace for reconnection.
  Future<AccountDisconnectionResult> expireRejectedKey(
    String siteUrl, {
    required String apiKey,
    required SiteLease lease,
  }) => _expireStoredKey(siteUrl, apiKey, lease);

  /// Signs a signed-in forum out locally once reading its key storage has
  /// answered that it holds none.
  ///
  /// The account snapshot and its key are stored apart and can come back
  /// apart: an iPhone set up from another device's unencrypted backup gets the
  /// app's preferences but not its Keychain items, and Linux's private storage
  /// file can be lost while preferences survive. Such a forum reads
  /// anonymously and has every write refused while it still shows the account.
  /// Only an answer counts: a read that failed, as a locked Keychain or an
  /// undecodable file does, says nothing about the key and must not reach
  /// this. The guards of [expireRejectedKey] apply, so a key stored since the
  /// empty read belongs to a newer sign-in and leaves the forum alone.
  Future<AccountDisconnectionResult> expireMissingKey(
    String siteUrl, {
    required SiteLease lease,
  }) => _expireStoredKey(siteUrl, null, lease);

  /// Expires the key the forum was found holding under [lease], null when
  /// storage held none, unless storage now answers something else.
  Future<AccountDisconnectionResult> _expireStoredKey(
    String siteUrl,
    String? apiKey,
    SiteLease lease,
  ) async {
    if (_operations.containsKey(siteUrl) || !lease.isCurrent) {
      return AccountDisconnectionStale(lifecycle.capture(siteUrl));
    }
    final operation = _begin(siteUrl);

    try {
      final String? stored;
      try {
        stored = await authenticator.apiKeyFor(siteUrl);
      } catch (error) {
        return const AccountDisconnectionFailed();
      }
      final initial = host.accountSessionInstance(siteUrl);
      if (initial == null) return const AccountDisconnectionMissing();
      if (!_isCurrent(siteUrl, operation, lease) ||
          !initial.isConnected ||
          stored != apiKey) {
        return AccountDisconnectionStale(lease);
      }

      final signingOut = _rotate(siteUrl, operation);
      if (signingOut == null) {
        return AccountDisconnectionStale(lifecycle.capture(siteUrl));
      }
      if (await _enterSignedOut(siteUrl, operation, signingOut, initial)
          case final aborted?) {
        return aborted;
      }
      return await _forgetCredential(siteUrl, operation, signingOut);
    } finally {
      _finish(siteUrl, operation);
    }
  }

  /// Publishes [initial] signed out and saves that boundary, answering null
  /// once it is durable. Every later full snapshot must include this
  /// transition: a coalesced save can settle with another site's disconnect or
  /// an ordinary save. The credential is kept until persistence succeeds, and
  /// only this operation may restore the account if the boundary cannot be
  /// saved.
  Future<AccountDisconnectionResult?> _enterSignedOut(
    String siteUrl,
    Object operation,
    SiteLease lease,
    DiscourseInstance initial,
  ) async {
    final signedOut = initial.copyWith(
      clearUser: true,
      clearConfig: true,
      clearAppearance: true,
    );
    if (host.applyAccountSessionInstance(
          signedOut,
          AccountSessionPhase.disconnecting,
        ) ==
        null) {
      return const AccountDisconnectionMissing();
    }
    if (!_isCurrent(siteUrl, operation, lease)) {
      return AccountDisconnectionStale(lease);
    }
    if (!await _persistSignedOut(siteUrl, operation, lease)) {
      return _restoreFailedDisconnect(siteUrl, operation, lease, initial);
    }
    if (!_isCurrent(siteUrl, operation, lease)) {
      return AccountDisconnectionStale(lease);
    }
    return null;
  }

  /// Deletes the local credential behind a durable signed-out boundary, then
  /// publishes the settled signed-out forum on a fresh lifecycle.
  Future<AccountDisconnectionResult> _forgetCredential(
    String siteUrl,
    Object operation,
    SiteLease lease,
  ) async {
    try {
      await authenticator.disconnect(siteUrl);
    } catch (_) {}
    if (!_isCurrent(siteUrl, operation, lease)) {
      return AccountDisconnectionStale(lease);
    }

    final signedOut = _rotate(siteUrl, operation);
    if (signedOut == null) {
      return AccountDisconnectionStale(lifecycle.capture(siteUrl));
    }
    final latest = host.accountSessionInstance(siteUrl);
    if (latest == null) return const AccountDisconnectionMissing();
    host.applyAccountSessionInstance(
      latest.copyWith(
        clearUser: true,
        clearConfig: true,
        clearAppearance: true,
      ),
      AccountSessionPhase.disconnected,
    );
    return AccountDisconnected(signedOut);
  }

  Future<AccountDisconnectionResult> _restoreFailedDisconnect(
    String siteUrl,
    Object operation,
    SiteLease lease,
    DiscourseInstance initial,
  ) async {
    if (!_isCurrent(siteUrl, operation, lease)) {
      return AccountDisconnectionStale(lease);
    }

    final restoredLease = _rotate(siteUrl, operation);
    if (restoredLease == null) {
      return AccountDisconnectionStale(lifecycle.capture(siteUrl));
    }
    if (host.applyAccountSessionInstance(
          initial,
          AccountSessionPhase.restored,
        ) ==
        null) {
      return const AccountDisconnectionMissing();
    }
    await _repairSnapshot(siteUrl, operation, restoredLease);
    return _isCurrent(siteUrl, operation, restoredLease)
        ? const AccountDisconnectionFailed()
        : AccountDisconnectionStale(restoredLease);
  }

  Future<bool> _persistSignedOut(
    String siteUrl,
    Object operation,
    SiteLease lease,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!_isCurrent(siteUrl, operation, lease)) return false;
      try {
        await instances.save(List.of(host.accountSessionInstances));
        return true;
      } catch (_) {}
    }
    return false;
  }

  Future<void> _repairSnapshot(
    String siteUrl,
    Object operation,
    SiteLease lease,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!_isCurrent(siteUrl, operation, lease)) return;
      try {
        await instances.save(List.of(host.accountSessionInstances));
        return;
      } catch (_) {}
    }
  }

  Future<void> _revokeIssued(String siteUrl, String apiKey) async {
    await _revokeBestEffort(siteUrl, apiKey);
  }

  Future<void> _revokeBestEffort(
    String siteUrl,
    String apiKey, {
    bool Function()? ifCurrent,
  }) async {
    if (ifCurrent?.call() == false) return;
    try {
      await AccountRequestScope.withoutSession(
        () => api.revokeApiKey(siteUrl: siteUrl, apiKey: apiKey),
      );
    } catch (_) {}
  }

  Object _begin(String siteUrl) {
    final operation = Object();
    _operations[siteUrl] = operation;
    return operation;
  }

  void _finish(String siteUrl, Object operation) {
    if (identical(_operations[siteUrl], operation)) {
      _operations.remove(siteUrl);
    }
  }

  SiteLease? _rotate(String siteUrl, Object operation) {
    if (!_isCurrent(siteUrl, operation)) return null;
    lifecycle.invalidate(siteUrl);
    host.clearAccountSessionState(siteUrl);
    final lease = lifecycle.capture(siteUrl);
    return _isCurrent(siteUrl, operation, lease) ? lease : null;
  }

  bool _isCurrent(String siteUrl, Object operation, [SiteLease? lease]) =>
      !host.accountSessionDisposed &&
      identical(_operations[siteUrl], operation) &&
      host.accountSessionInstance(siteUrl) != null &&
      (lease?.isCurrent ?? true);
}
