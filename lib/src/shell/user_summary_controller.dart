import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/user_summary.dart';

typedef _SummaryKey = ({String siteUrl, String username});

@immutable
class UserSummaryState {
  const UserSummaryState({
    this.summary,
    this.loaded = false,
    this.loading = false,
    this.error,
  });

  final UserSummary? summary;
  final bool loaded;
  final bool loading;
  final String? error;

  UserSummaryState loadingNow() =>
      UserSummaryState(summary: summary, loaded: loaded, loading: true);

  UserSummaryState succeeded(UserSummary value) =>
      UserSummaryState(summary: value, loaded: true);

  UserSummaryState failed(String message) =>
      UserSummaryState(summary: summary, loaded: true, error: message);
}

/// Owns profile-summary reads independently from shell navigation.
///
/// The cache key includes both forum and account. [SiteLifecycle] supplies the
/// stronger same-origin session boundary: reconnecting a different account at
/// the same URL invalidates the old request before it can dispatch credentials
/// or publish private summary data.
final class UserSummaryController extends FrameSafeNotifier {
  UserSummaryController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
  });

  final UserSummariesApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;

  final Map<_SummaryKey, UserSummaryState> _states = {};
  final Map<_SummaryKey, Future<void>> _tasks = {};
  final Map<_SummaryKey, Object> _requests = {};

  UserSummaryState stateFor(String siteUrl, String username) =>
      _states[_key(siteUrl, username)] ?? const UserSummaryState();

  Future<void> load(DiscourseInstance instance, {bool refresh = false}) {
    final user = instance.user;
    if (isDisposed || user == null) return Future<void>.value();
    final key = _key(instance.url, user.username);
    final active = _tasks[key];
    if (active != null) return active;
    final held = _states[key] ?? const UserSummaryState();
    if (!refresh && held.loaded && held.error == null) {
      return Future<void>.value();
    }

    final lease = lifecycle.capture(instance.url);
    final request = Object();
    _requests[key] = request;
    _states[key] = held.loadingNow();
    notifySafely();

    late final Future<void> task;
    task = _perform(instance, key, lease, request).whenComplete(() {
      if (identical(_tasks[key], task)) {
        unawaited(_tasks.remove(key)!);
      }
      if (identical(_requests[key], request)) {
        _requests.remove(key);
      }
    });
    _tasks[key] = task;
    return task;
  }

  Future<void> _perform(
    DiscourseInstance instance,
    _SummaryKey key,
    SiteLease lease,
    Object request,
  ) async {
    bool current() =>
        !isDisposed && lease.isCurrent && identical(_requests[key], request);

    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      if (!current()) return;
      if (apiKey == null) {
        _commit(lease, key, request, () {
          _states[key] = stateFor(
            key.siteUrl,
            key.username,
          ).failed('Reconnect to ${instance.host} to view your summary.');
        });
        return;
      }

      final summary = await api.userSummary(
        siteUrl: instance.url,
        apiKey: apiKey,
        username: instance.user!.username,
      );
      _commit(lease, key, request, () {
        _states[key] = stateFor(key.siteUrl, key.username).succeeded(summary);
      });
    } catch (error, stackTrace) {
      if (!current()) return;
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'userSummary.load',
        source: 'summary',
        handled: true,
        degraded: true,
      );
      _commit(lease, key, request, () {
        _states[key] = stateFor(
          key.siteUrl,
          key.username,
        ).failed("Couldn't load your summary from ${instance.host}.");
      });
    }
  }

  void _commit(
    SiteLease lease,
    _SummaryKey key,
    Object request,
    VoidCallback mutation,
  ) {
    if (isDisposed || !lease.isCurrent || !identical(_requests[key], request)) {
      return;
    }
    lease.commit(() {
      if (!identical(_requests[key], request)) return;
      mutation();
      notifySafely();
    });
  }

  void forget(String siteUrl) {
    final stateCount = _states.length;
    final taskCount = _tasks.length;
    final requestCount = _requests.length;
    _states.removeWhere((key, _) => key.siteUrl == siteUrl);
    _tasks.removeWhere((key, _) => key.siteUrl == siteUrl);
    _requests.removeWhere((key, _) => key.siteUrl == siteUrl);
    if (_states.length != stateCount ||
        _tasks.length != taskCount ||
        _requests.length != requestCount) {
      notifySafely();
    }
  }

  static _SummaryKey _key(String siteUrl, String username) =>
      (siteUrl: siteUrl, username: username.toLowerCase());

  @override
  void dispose() {
    _tasks.clear();
    _requests.clear();
    _states.clear();
    super.dispose();
  }
}
