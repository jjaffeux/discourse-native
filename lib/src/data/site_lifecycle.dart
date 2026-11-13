import 'dart:async';

typedef SiteMutation = void Function();

final class SiteLifecycle {
  final Map<String, _SiteSession> _sessions = {};

  SiteLease capture(String siteUrl) {
    final session = _sessions.putIfAbsent(siteUrl, _SiteSession.new);
    return SiteLease._(session, () => _sessions[siteUrl]);
  }

  bool owns(String siteUrl, SiteLease lease) =>
      identical(_sessions[siteUrl], lease._session);

  /// Runs every retirement observer, then rethrows the first failure with its
  /// original stack. A broken observer cannot skip another owner's cleanup.
  void invalidate(String siteUrl) {
    final session = _sessions.remove(siteUrl);
    session?.retire();
  }
}

final class _SiteSession {
  final Set<void Function()> _observers = {};
  bool retired = false;

  void retire() {
    retired = true;
    final observers = _observers.toList();
    _observers.clear();
    (Object, StackTrace)? firstFailure;
    for (final observer in observers) {
      try {
        observer();
      } catch (error, stackTrace) {
        firstFailure ??= (error, stackTrace);
      }
    }
    if (firstFailure case final failure?) {
      Error.throwWithStackTrace(failure.$1, failure.$2);
    }
  }
}

final class SiteLease {
  const SiteLease._(this._session, this._currentSession);

  final _SiteSession _session;
  final _SiteSession? Function() _currentSession;

  /// Stable identity for this account session, including after retirement.
  Object get session => _session;

  bool get isCurrent => identical(_session, _currentSession());

  /// Observe retirement until the returned removal callback is called.
  void Function() onRetire(void Function() observer) {
    if (_session.retired) {
      observer();
      return () {};
    }
    void registration() => observer();
    _session._observers.add(registration);
    return () => _session._observers.remove(registration);
  }

  /// Bounds an in-flight wait by the lease lifetime and an optional timeout.
  Future<T> waitWhileCurrent<T>(
    Future<T> operation,
    Object retirementError, {
    Duration? timeout,
  }) async {
    if (!isCurrent) {
      operation.ignore();
      throw retirementError;
    }
    final retired = Completer<Never>();
    final detach = onRetire(() => retired.completeError(retirementError));
    try {
      final pending = Future.any<T>([retired.future, operation]);
      final value = await (timeout == null
          ? pending
          : pending.timeout(timeout));
      if (!isCurrent) throw retirementError;
      return value;
    } finally {
      detach();
    }
  }

  bool commit(SiteMutation mutation) {
    if (!isCurrent) return false;
    mutation();
    return true;
  }
}
