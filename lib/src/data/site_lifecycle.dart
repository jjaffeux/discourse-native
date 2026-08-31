typedef SiteMutation = void Function();

final class SiteLifecycle {
  final Map<String, Object> _tokens = {};

  SiteLease capture(String siteUrl) {
    final token = _tokens.putIfAbsent(siteUrl, Object.new);
    return SiteLease._(token, () => _tokens[siteUrl]);
  }

  void invalidate(String siteUrl) {
    // Absence invalidates an old token just as effectively as replacing it,
    // and lets a disconnected URL leave this process-wide lifecycle map.
    // A later capture creates a distinct token for the new account session.
    _tokens.remove(siteUrl);
  }
}

final class SiteLease {
  const SiteLease._(this._token, this._currentToken);

  final Object _token;
  final Object? Function() _currentToken;

  /// Stable identity for this account session. Work queues can use it to keep
  /// an old account's delayed operations from blocking or mutating a new
  /// account connected at the same URL.
  Object get session => _token;

  bool get isCurrent => identical(_token, _currentToken());

  bool commit(SiteMutation mutation) {
    if (!isCurrent) return false;
    mutation();
    return true;
  }
}
