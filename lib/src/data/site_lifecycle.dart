import 'dart:async';

typedef SiteMutation = void Function();

final class SiteLifecycle {
  final Map<String, SiteLease> _sessions = {};
  SiteLease? _closedLease;

  SiteLease capture(String siteUrl) =>
      _closedLease ?? _sessions.putIfAbsent(siteUrl, SiteLease._);

  bool owns(String siteUrl, SiteLease lease) =>
      _closedLease == null && identical(_sessions[siteUrl], lease);

  /// Runs every attached retirement observer, then rethrows the first failure
  /// with its original stack.
  void invalidate(String siteUrl) {
    final session = _sessions.remove(siteUrl);
    session?._retire();
  }

  void close() {
    if (_closedLease != null) return;
    _closedLease = SiteLease._().._retire();
    final leases = _sessions.values.toList();
    _sessions.clear();
    _retireAll(leases);
  }

  void invalidateSites(Iterable<String> siteUrls) {
    _retireAll(siteUrls.toList().map(_sessions.remove).nonNulls.toList());
  }

  void _retireAll(List<SiteLease> leases) {
    // Fence every lease before invoking observers on any site.
    for (final lease in leases) {
      lease._retired = true;
    }
    (Object, StackTrace)? firstFailure;
    for (final lease in leases) {
      try {
        lease._retire();
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
  SiteLease._();

  final Object session = Object();
  final Set<void Function()> _observers = {};
  bool _retired = false;

  void _retire() {
    _retired = true;
    final observers = _observers.toList();
    (Object, StackTrace)? firstFailure;
    for (final observer in observers) {
      if (!_observers.remove(observer)) continue;
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

  bool get isCurrent => !_retired;

  /// Observe retirement until the returned removal callback is called.
  void Function() onRetire(void Function() observer) {
    if (_retired) {
      observer();
      return () {};
    }
    void registration() => observer();
    _observers.add(registration);
    return () => _observers.remove(registration);
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
    } catch (error) {
      if (!isCurrent && !identical(error, retirementError)) {
        throw retirementError;
      }
      rethrow;
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
