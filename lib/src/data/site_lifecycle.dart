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

  bool get isCurrent => identical(_token, _currentToken());

  bool commit(SiteMutation mutation) {
    if (!isCurrent) return false;
    mutation();
    return true;
  }
}
