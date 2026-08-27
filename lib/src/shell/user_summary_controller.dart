import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/user_summary.dart';

@immutable
final class UserSummaryState {
  const UserSummaryState({
    this.summary,
    this.loading = false,
    this.loaded = false,
    this.error,
  });

  final UserSummary? summary;
  final bool loading;
  final bool loaded;
  final String? error;

  UserSummaryState loadingNow() =>
      UserSummaryState(summary: summary, loading: true, loaded: loaded);

  UserSummaryState withSummary(UserSummary value) =>
      UserSummaryState(summary: value, loaded: true);

  UserSummaryState withError(String message) =>
      UserSummaryState(summary: summary, loaded: true, error: message);
}

/// Per-forum Summary state, isolated from shell-wide navigation rebuilds.
///
/// A site's lifecycle generation is also its account generation. Disconnect,
/// reconnect, removal, and credential rotation invalidate the lease, so a
/// private response from the former account cannot enter the replacement
/// account's cache.
final class UserSummaryController extends FrameSafeNotifier {
  UserSummaryController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
  });

  final UserSummariesApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;

  final Map<String, UserSummaryState> _states = {};
  final Map<String, Object> _requests = {};

  UserSummaryState stateFor(String? siteUrl) => siteUrl == null
      ? const UserSummaryState()
      : _states[siteUrl] ?? const UserSummaryState();

  Future<void> load(DiscourseInstance instance, {bool refresh = false}) async {
    if (isDisposed || !instance.isConnected) return;
    final user = instance.user;
    if (user == null) return;
    final siteUrl = instance.url;
    final held = stateFor(siteUrl);
    if (_requests.containsKey(siteUrl) || (!refresh && held.loaded)) return;

    final request = Object();
    final lease = lifecycle.capture(siteUrl);
    _requests[siteUrl] = request;
    _states[siteUrl] = held.loadingNow();
    notifySafely();
    if (!_isCurrent(lease, siteUrl, request)) return;

    try {
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (!_isCurrent(lease, siteUrl, request)) return;
      if (apiKey == null) {
        _commit(lease, siteUrl, request, () {
          _states[siteUrl] = stateFor(
            siteUrl,
          ).withError('Reconnect to ${instance.host} to see your summary.');
        });
        return;
      }

      final summary = await api.userSummary(
        siteUrl: siteUrl,
        apiKey: apiKey,
        username: user.username,
      );
      _commit(lease, siteUrl, request, () {
        _states[siteUrl] = stateFor(siteUrl).withSummary(summary);
      });
    } catch (error, stackTrace) {
      if (!_isCurrent(lease, siteUrl, request)) return;
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'summary.load',
        source: 'summary',
        handled: true,
        degraded: true,
      );
      _commit(lease, siteUrl, request, () {
        _states[siteUrl] = stateFor(
          siteUrl,
        ).withError("Couldn't load your summary from ${instance.host}.");
      });
    } finally {
      if (!isDisposed && identical(_requests[siteUrl], request)) {
        _requests.remove(siteUrl);
      }
    }
  }

  void forget(String siteUrl) {
    var changed = _states.remove(siteUrl) != null;
    changed = _requests.remove(siteUrl) != null || changed;
    if (changed) notifySafely();
  }

  bool _isCurrent(SiteLease lease, String siteUrl, Object request) =>
      !isDisposed && lease.isCurrent && identical(_requests[siteUrl], request);

  void _commit(
    SiteLease lease,
    String siteUrl,
    Object request,
    VoidCallback mutation,
  ) {
    if (!_isCurrent(lease, siteUrl, request)) return;
    lease.commit(() {
      if (!identical(_requests[siteUrl], request)) return;
      mutation();
      notifySafely();
    });
  }

  @override
  void dispose() {
    _requests.clear();
    super.dispose();
  }
}
