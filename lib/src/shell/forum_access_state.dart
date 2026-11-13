import '../data/account_session_coordinator.dart';
import '../data/site_lifecycle.dart';
import '../models/discourse_instance.dart';
import '../plugin_api/shell_extensions.dart';

final class _ForumAccess {
  String? connectError;
  bool unavailable = false;

  /// The account a retry runs for. Its outcome speaks for this forum only
  /// while that account is current.
  SiteLease? retry;
}

/// Tracks what stands between the user and each forum, which is a failed
/// sign-in, an unreachable site, and the retry of it. Retiring a site is one
/// removal.
final class ForumAccessState {
  ForumAccessState({
    required this.instanceAt,
    required this.captureLease,
    required this.routeRetries,
    required this.connectAccount,
    required this.changed,
  });

  final DiscourseInstance? Function(String siteUrl) instanceAt;
  final SiteLease Function(String siteUrl) captureLease;
  final Iterable<PluginRouteRetry> Function() routeRetries;
  final Future<AccountConnectionResult> Function(String siteUrl) connectAccount;
  final void Function() changed;

  final Map<String, _ForumAccess> _sites = {};

  /// One slot rather than a per-site field, because the sign-in browser is
  /// app-wide and [forget] runs during a sign-in's own account rotations
  /// without ending it.
  String? _connectingSiteUrl;

  String? get connectingSiteUrl => _connectingSiteUrl;

  String? connectError(String? siteUrl) => _sites[siteUrl]?.connectError;

  bool isUnavailable(String? siteUrl) => _sites[siteUrl]?.unavailable ?? false;

  bool isRetrying(String? siteUrl) =>
      _sites[siteUrl]?.retry?.isCurrent ?? false;

  _ForumAccess _site(String siteUrl) =>
      _sites.putIfAbsent(siteUrl, _ForumAccess.new);

  void markUnavailable(String siteUrl) {
    if (instanceAt(siteUrl) == null || isUnavailable(siteUrl)) return;
    _site(siteUrl).unavailable = true;
    changed();
  }

  Future<void> retry(String siteUrl, String routeId) async {
    if (!isUnavailable(siteUrl) || isRetrying(siteUrl)) return;

    final lease = captureLease(siteUrl);
    _site(siteUrl).retry = lease;
    changed();
    try {
      for (final retry in routeRetries()) {
        final result = await retry.retryPluginRoute(siteUrl, routeId);
        if (!lease.isCurrent) return;
        if (result == PluginRouteRetryResult.notHandled) continue;
        if (result == PluginRouteRetryResult.succeeded) {
          _site(siteUrl).unavailable = false;
        }
        break;
      }
    } finally {
      if (lease.isCurrent) {
        _site(siteUrl).retry = null;
        changed();
      }
    }
  }

  /// [settled] runs while the sign-in still holds its slot, so a session read
  /// it starts stands aside; [released] runs just after.
  Future<void> connect(
    String siteUrl, {
    required void Function(AccountConnectionResult result) settled,
    required void Function() released,
  }) async {
    if (_connectingSiteUrl != null) return;

    _connectingSiteUrl = siteUrl;
    _sites[siteUrl]?.connectError = null;
    changed();

    try {
      final result = await connectAccount(siteUrl);
      switch (result) {
        case AccountConnected() || AccountConnectionCancelled():
          _sites[siteUrl]?.connectError = null;
        case AccountConnectionFailed(:final message):
          _site(siteUrl).connectError = message;
        case AccountConnectionStale() || AccountConnectionMissing():
          break;
      }
      settled(result);
    } finally {
      _connectingSiteUrl = null;
      released();
      changed();
    }
  }

  void offerSignIn(String siteUrl, String message) {
    _site(siteUrl).connectError = message;
    changed();
  }

  void forget(String siteUrl) {
    _sites.remove(siteUrl);
  }
}
