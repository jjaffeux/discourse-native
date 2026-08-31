import '../models/discourse_instance.dart';
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

enum AccountConnectionOutcome { connected, cancelled, failed, stale, missing }

final class AccountConnectionResult {
  const AccountConnectionResult._({
    required this.outcome,
    this.instance,
    this.apiKey,
    this.message,
    this.refreshSignedOutPresentation = false,
  });

  const AccountConnectionResult.connected(
    DiscourseInstance instance,
    String apiKey,
  ) : this._(
        outcome: AccountConnectionOutcome.connected,
        instance: instance,
        apiKey: apiKey,
      );

  const AccountConnectionResult.cancelled()
    : this._(outcome: AccountConnectionOutcome.cancelled);

  const AccountConnectionResult.failed(
    String message, {
    bool refreshSignedOutPresentation = false,
  }) : this._(
         outcome: AccountConnectionOutcome.failed,
         message: message,
         refreshSignedOutPresentation: refreshSignedOutPresentation,
       );

  const AccountConnectionResult.stale()
    : this._(outcome: AccountConnectionOutcome.stale);

  const AccountConnectionResult.missing()
    : this._(outcome: AccountConnectionOutcome.missing);

  final AccountConnectionOutcome outcome;
  final DiscourseInstance? instance;
  final String? apiKey;
  final String? message;
  final bool refreshSignedOutPresentation;
}

enum AccountDisconnectionOutcome { disconnected, failed, stale, missing }

final class AccountDisconnectionResult {
  const AccountDisconnectionResult._(this.outcome, [this.lease]);

  const AccountDisconnectionResult.disconnected(SiteLease lease)
    : this._(AccountDisconnectionOutcome.disconnected, lease);

  const AccountDisconnectionResult.failed()
    : this._(AccountDisconnectionOutcome.failed);

  const AccountDisconnectionResult.stale(SiteLease lease)
    : this._(AccountDisconnectionOutcome.stale, lease);

  const AccountDisconnectionResult.missing()
    : this._(AccountDisconnectionOutcome.missing);

  final AccountDisconnectionOutcome outcome;
  final SiteLease? lease;
}

typedef AccountSessionErrorReporter =
    void Function(
      Object error,
      StackTrace stackTrace,
      String operation, {
      required bool warning,
    });

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
    AccountSessionErrorReporter? reportError,
  }) : _reportError = reportError ?? _ignoreError;

  final Authenticator authenticator;
  final InstanceStore instances;
  final DraftStore drafts;
  final SiteLifecycle lifecycle;
  final ShellSiteApi api;
  final AccountSessionHost host;
  final AccountSessionErrorReporter _reportError;
  final Map<String, Object> _operations = {};

  Future<AccountConnectionResult> connect(String siteUrl) async {
    final operation = _begin(siteUrl);
    final initial = host.accountSessionInstance(siteUrl);
    if (initial == null) {
      _finish(siteUrl, operation);
      return const AccountConnectionResult.missing();
    }

    String? previousKey;
    UserApiCredentials? credentials;
    var pendingPublished = false;
    var credentialsPersisted = false;

    try {
      previousKey = await authenticator.apiKeyFor(siteUrl);
      if (!_isCurrent(siteUrl, operation)) {
        return const AccountConnectionResult.stale();
      }

      credentials = await authenticator.authorize(siteUrl);
      if (!_isCurrent(siteUrl, operation)) {
        await _revokeIssued(siteUrl, credentials.key);
        return const AccountConnectionResult.stale();
      }

      await drafts.clearSite(
        siteUrl,
        ifCurrent: () => _isCurrent(siteUrl, operation),
      );
      if (!_isCurrent(siteUrl, operation)) {
        await _revokeIssued(siteUrl, credentials.key);
        return const AccountConnectionResult.stale();
      }

      final pendingLease = _rotate(siteUrl, operation);
      if (pendingLease == null) {
        await _revokeIssued(siteUrl, credentials.key);
        return const AccountConnectionResult.stale();
      }
      final held = host.accountSessionInstance(siteUrl);
      if (held == null) {
        await _revokeIssued(siteUrl, credentials.key);
        return const AccountConnectionResult.missing();
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
        return const AccountConnectionResult.missing();
      }
      pendingPublished = true;
      if (!_isCurrent(siteUrl, operation, pendingLease)) {
        await _revokeIssued(siteUrl, credentials.key);
        return const AccountConnectionResult.stale();
      }
      await instances.save(List.of(host.accountSessionInstances));
      if (!_isCurrent(siteUrl, operation, pendingLease)) {
        await _revokeIssued(siteUrl, credentials.key);
        return const AccountConnectionResult.stale();
      }

      final user = await api.currentUser(
        siteUrl: siteUrl,
        apiKey: credentials.key,
      );
      if (!_isCurrent(siteUrl, operation, pendingLease)) {
        await _revokeIssued(siteUrl, credentials.key);
        return const AccountConnectionResult.stale();
      }

      await authenticator.persistCredentials(siteUrl, credentials);
      credentialsPersisted = true;
      if (!_isCurrent(siteUrl, operation, pendingLease)) {
        return const AccountConnectionResult.stale();
      }

      if (previousKey != null && previousKey != credentials.key) {
        await _revokeBestEffort(
          siteUrl,
          previousKey,
          operation: 'authentication.revokePreviousKey',
          ifCurrent: () => _isCurrent(siteUrl, operation, pendingLease),
        );
      }
      if (!_isCurrent(siteUrl, operation, pendingLease)) {
        return const AccountConnectionResult.stale();
      }

      final connectedLease = _rotate(siteUrl, operation);
      if (connectedLease == null) {
        return const AccountConnectionResult.stale();
      }
      final latest = host.accountSessionInstance(siteUrl);
      if (latest == null) return const AccountConnectionResult.missing();
      final applied = host.applyAccountSessionInstance(
        latest.copyWith(user: user, apiVersion: credentials.apiVersion),
        AccountSessionPhase.connected,
      );
      if (applied == null) return const AccountConnectionResult.missing();
      if (!_isCurrent(siteUrl, operation, connectedLease)) {
        return const AccountConnectionResult.stale();
      }
      await instances.save(List.of(host.accountSessionInstances));
      if (!_isCurrent(siteUrl, operation, connectedLease)) {
        return const AccountConnectionResult.stale();
      }
      return AccountConnectionResult.connected(applied, credentials.key);
    } on UserApiAuthException catch (error, stackTrace) {
      if (credentials != null) {
        final recovered = await _recoverConnection(
          siteUrl: siteUrl,
          operation: operation,
          initial: initial,
          credentials: credentials,
          credentialsPersisted: credentialsPersisted,
          error: error,
          stackTrace: stackTrace,
        );
        return recovered;
      }
      if (!_isCurrent(siteUrl, operation)) {
        return const AccountConnectionResult.stale();
      }
      if (error.failure == UserApiAuthFailure.cancelled) {
        return const AccountConnectionResult.cancelled();
      }
      _reportError(error, stackTrace, 'authentication.connect', warning: false);
      return AccountConnectionResult.failed(error.message);
    } on SiteLookupException catch (error, stackTrace) {
      if (credentials == null) {
        if (!_isCurrent(siteUrl, operation)) {
          return const AccountConnectionResult.stale();
        }
        _reportError(
          error,
          stackTrace,
          'authentication.loadAccount',
          warning: false,
        );
        return AccountConnectionResult.failed(error.message);
      }
      final recovered = await _recoverConnection(
        siteUrl: siteUrl,
        operation: operation,
        initial: initial,
        credentials: credentials,
        credentialsPersisted: credentialsPersisted,
        error: error,
        stackTrace: stackTrace,
      );
      return recovered;
    } catch (error, stackTrace) {
      if (credentials == null || !pendingPublished) {
        if (credentials != null) {
          await _revokeIssued(siteUrl, credentials.key);
        }
        if (!_isCurrent(siteUrl, operation)) {
          return const AccountConnectionResult.stale();
        }
        _reportError(
          error,
          stackTrace,
          'authentication.connect',
          warning: false,
        );
        return AccountConnectionResult.failed(
          'Could not connect to ${initial.host}.',
        );
      }
      final recovered = await _recoverConnection(
        siteUrl: siteUrl,
        operation: operation,
        initial: initial,
        credentials: credentials,
        credentialsPersisted: credentialsPersisted,
        error: error,
        stackTrace: stackTrace,
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
    required StackTrace stackTrace,
  }) async {
    if (!_isCurrent(siteUrl, operation)) {
      return const AccountConnectionResult.stale();
    }

    final failureOperation = error is SiteLookupException
        ? 'authentication.loadAccount'
        : 'authentication.connect';
    _reportError(error, stackTrace, failureOperation, warning: false);

    var refreshSignedOutPresentation = false;
    if (!credentialsPersisted) {
      final recoveryLease = _rotate(siteUrl, operation);
      if (recoveryLease == null) {
        return const AccountConnectionResult.stale();
      }
      host.applyAccountSessionInstance(initial, AccountSessionPhase.restored);
      await _repairSnapshot(siteUrl, operation, recoveryLease);
      await _revokeIssued(siteUrl, credentials.key);
    } else {
      final recoveryLease = _rotate(siteUrl, operation);
      if (recoveryLease == null) {
        return const AccountConnectionResult.stale();
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
        } catch (deleteError, deleteStackTrace) {
          _reportError(
            deleteError,
            deleteStackTrace,
            'authentication.deleteCredential',
            warning: true,
          );
        }
      }
    }

    if (!_isCurrent(siteUrl, operation)) {
      return const AccountConnectionResult.stale();
    }
    final message = switch (error) {
      UserApiAuthException(:final message) => message,
      SiteLookupException(:final message) => message,
      _ => 'Could not connect to ${initial.host}.',
    };
    return AccountConnectionResult.failed(
      message,
      refreshSignedOutPresentation: refreshSignedOutPresentation,
    );
  }

  Future<AccountDisconnectionResult> disconnect(String siteUrl) async {
    final operation = _begin(siteUrl);
    final initial = host.accountSessionInstance(siteUrl);
    if (initial == null) {
      _finish(siteUrl, operation);
      return const AccountDisconnectionResult.missing();
    }

    try {
      var lease = _rotate(siteUrl, operation);
      if (lease == null) {
        return AccountDisconnectionResult.stale(lifecycle.capture(siteUrl));
      }

      try {
        await drafts.clearSite(
          siteUrl,
          ifCurrent: () => _isCurrent(siteUrl, operation, lease),
        );
      } catch (error, stackTrace) {
        if (_isCurrent(siteUrl, operation, lease)) {
          _reportError(
            error,
            stackTrace,
            'authentication.clearDrafts',
            warning: false,
          );
        }
        return const AccountDisconnectionResult.failed();
      }
      if (!_isCurrent(siteUrl, operation, lease)) {
        return AccountDisconnectionResult.stale(lease);
      }

      final signedOut = initial.copyWith(
        clearUser: true,
        clearConfig: true,
        clearAppearance: true,
      );
      if (!await _persistProjectedSignedOut(
        siteUrl,
        signedOut,
        operation,
        lease,
      )) {
        return _isCurrent(siteUrl, operation, lease)
            ? const AccountDisconnectionResult.failed()
            : AccountDisconnectionResult.stale(lease);
      }
      if (!_isCurrent(siteUrl, operation, lease)) {
        return AccountDisconnectionResult.stale(lease);
      }
      if (host.applyAccountSessionInstance(
            signedOut,
            AccountSessionPhase.disconnecting,
          ) ==
          null) {
        return const AccountDisconnectionResult.missing();
      }
      if (!_isCurrent(siteUrl, operation, lease)) {
        return AccountDisconnectionResult.stale(lease);
      }

      String? apiKey;
      try {
        apiKey = await authenticator.apiKeyFor(siteUrl);
      } catch (error, stackTrace) {
        if (_isCurrent(siteUrl, operation, lease)) {
          _reportError(
            error,
            stackTrace,
            'authentication.readCredentialForDisconnect',
            warning: true,
          );
        }
      }
      if (!_isCurrent(siteUrl, operation, lease)) {
        return AccountDisconnectionResult.stale(lease);
      }
      if (apiKey != null) {
        await _revokeBestEffort(
          siteUrl,
          apiKey,
          operation: 'authentication.revokeKey',
          ifCurrent: () => _isCurrent(siteUrl, operation, lease),
        );
      }
      if (!_isCurrent(siteUrl, operation, lease)) {
        return AccountDisconnectionResult.stale(lease);
      }
      try {
        await authenticator.disconnect(siteUrl);
      } catch (error, stackTrace) {
        if (_isCurrent(siteUrl, operation, lease)) {
          _reportError(
            error,
            stackTrace,
            'authentication.deleteCredential',
            warning: true,
          );
        }
      }
      if (!_isCurrent(siteUrl, operation, lease)) {
        return AccountDisconnectionResult.stale(lease);
      }

      lease = _rotate(siteUrl, operation);
      if (lease == null) {
        return AccountDisconnectionResult.stale(lifecycle.capture(siteUrl));
      }
      final latest = host.accountSessionInstance(siteUrl);
      if (latest == null) return const AccountDisconnectionResult.missing();
      host.applyAccountSessionInstance(
        latest.copyWith(
          clearUser: true,
          clearConfig: true,
          clearAppearance: true,
        ),
        AccountSessionPhase.disconnected,
      );
      return AccountDisconnectionResult.disconnected(lease);
    } finally {
      _finish(siteUrl, operation);
    }
  }

  Future<bool> _persistProjectedSignedOut(
    String siteUrl,
    DiscourseInstance signedOut,
    Object operation,
    SiteLease lease,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!_isCurrent(siteUrl, operation, lease)) return false;
      final snapshot = [
        for (final instance in host.accountSessionInstances)
          if (instance.url == siteUrl) signedOut else instance,
      ];
      try {
        await instances.save(snapshot);
        return true;
      } catch (error, stackTrace) {
        _reportError(
          error,
          stackTrace,
          'authentication.persistSignedOut',
          warning: attempt == 0,
        );
      }
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
      } catch (error, stackTrace) {
        _reportError(
          error,
          stackTrace,
          'authentication.repairSnapshot',
          warning: true,
        );
      }
    }
  }

  Future<void> _revokeIssued(String siteUrl, String apiKey) =>
      _revokeBestEffort(siteUrl, apiKey, operation: 'authentication.revokeKey');

  Future<void> _revokeBestEffort(
    String siteUrl,
    String apiKey, {
    required String operation,
    bool Function()? ifCurrent,
  }) async {
    if (ifCurrent?.call() == false) return;
    try {
      await api.revokeApiKey(siteUrl: siteUrl, apiKey: apiKey);
    } catch (error, stackTrace) {
      if (ifCurrent?.call() != false) {
        _reportError(error, stackTrace, operation, warning: true);
      }
    }
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

  static void _ignoreError(
    Object error,
    StackTrace stackTrace,
    String operation, {
    required bool warning,
  }) {}
}
