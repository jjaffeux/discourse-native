import '../data/origin_reachability.dart';

/// Decides when loads that ended in an error are worth asking for again.
///
/// Two moments qualify: the current site's origin answering after it could not
/// be connected to, and the app returning to the foreground. Neither re-drives
/// anything while the site is waiting out a rate limit, since the reader's
/// errored loads are exactly what that site asked not to receive.
final class NetworkRecovery {
  NetworkRecovery({
    required this._api,
    required this._currentSiteUrl,
    required this._reload,
  });

  final SiteReachabilityApi _api;
  final String? Function() _currentSiteUrl;
  final void Function(String siteUrl) _reload;
  void Function()? _detach;
  bool _disposed = false;

  /// Starts listening for origins that answer again.
  void attach() {
    if (_disposed) return;
    _detach ??= _api.reachability.onRecovered(_originRecovered);
  }

  /// The reachability of every origin, for a view that shows one of them.
  OriginReachability get reachability => _api.reachability;

  bool isReachable(String siteUrl) {
    final url = Uri.tryParse(siteUrl);
    return url == null || !url.hasAuthority || reachability.isUrlReachable(url);
  }

  /// Calls [listener] with the origin of each site that answers again after
  /// being unreachable, for work that was held back while it was away. The
  /// returned callback removes it.
  void Function() onSiteRecovered(void Function(String origin) listener) =>
      reachability.onRecovered(listener);

  /// An unreachable origin is probed at once; its recovery then reloads
  /// through [_originRecovered]. A reachable one is reloaded directly, which
  /// is what answers a failure that was never about the connection.
  void resumed() {
    if (_disposed) return;
    reachability.probeNow();
    final siteUrl = _currentSiteUrl();
    if (siteUrl != null && isReachable(siteUrl)) _reloadFailed(siteUrl);
  }

  void _originRecovered(String origin) {
    if (_disposed) return;
    final siteUrl = _currentSiteUrl();
    if (siteUrl == null || Uri.tryParse(siteUrl)?.origin != origin) return;
    _reloadFailed(siteUrl);
  }

  void _reloadFailed(String siteUrl) {
    if (_api.isCoolingDown(siteUrl)) return;
    _reload(siteUrl);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _detach?.call();
  }
}
