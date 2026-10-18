typedef SiteMutation = void Function();

final class SiteLifecycle {
  final Map<String, _SiteSession> _sessions = {};

  SiteLease capture(String siteUrl) {
    final session = _sessions.putIfAbsent(siteUrl, _SiteSession.new);
    return SiteLease._(session, () => _sessions[siteUrl]);
  }

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
    for (final observer in observers) {
      observer();
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
    _session._observers.add(observer);
    return () => _session._observers.remove(observer);
  }

  bool commit(SiteMutation mutation) {
    if (!isCurrent) return false;
    mutation();
    return true;
  }
}
