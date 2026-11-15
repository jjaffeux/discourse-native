import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../data/user_summaries_api.dart';
import '../foundation/frame_safe_notifier.dart';
import '../foundation/site_scoped_state.dart';
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

final class _SummaryEntry {
  UserSummaryState state = const UserSummaryState();
  Object? request;
}

final class _SummaryAccount {
  _SummaryAccount(this.lease);

  final SiteLease lease;
  final Map<String, _SummaryEntry> entries = {};
  void Function()? detach;

  void dispose() {
    detach?.call();
    detach = null;
    entries.clear();
  }
}

/// Summaries by site, then by lowercased username, for the account session
/// that asked.
final class UserSummaryController extends FrameSafeNotifier
    with AccountScopedState {
  UserSummaryController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
  });

  final UserSummariesApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;

  final Map<String, _SummaryAccount> _accounts = {};

  _SummaryAccount? _accountFor(String siteUrl) {
    final account = _accounts[siteUrl];
    return account?.lease.isCurrent == true ? account : null;
  }

  _SummaryAccount _ensureAccount(String siteUrl) {
    final held = _accountFor(siteUrl);
    if (held != null) return held;
    final account = _SummaryAccount(lifecycle.capture(siteUrl));
    _accounts[siteUrl] = account;
    account.detach = account.lease.onRetire(() {
      final owned = identical(_accounts[siteUrl], account);
      if (owned) _accounts.remove(siteUrl);
      account.dispose();
      if (owned) notifySafely();
    });
    return account;
  }

  UserSummaryState stateFor(String? siteUrl, String? username) =>
      siteUrl == null || username == null
      ? const UserSummaryState()
      : _accountFor(siteUrl)?.entries[username.toLowerCase()]?.state ??
            const UserSummaryState();

  /// Loads [username]'s summary, or the signed-in reader's own without one.
  Future<void> load(
    DiscourseInstance instance, {
    String? username,
    bool refresh = false,
  }) async {
    if (isDisposed || !instance.isConnected) return;
    final user = instance.user;
    if (user == null) return;
    final person = username ?? user.username;
    final own = person.toLowerCase() == user.username.toLowerCase();
    final siteUrl = instance.url;
    final account = _ensureAccount(siteUrl);
    final entry = account.entries.putIfAbsent(
      person.toLowerCase(),
      _SummaryEntry.new,
    );
    final held = entry.state;
    if (entry.request != null || (!refresh && held.loaded)) return;

    final request = Object();
    final lease = account.lease;
    entry.request = request;
    entry.state = held.loadingNow();
    notifySafely();
    if (!_isCurrent(siteUrl, account, entry, request)) return;

    try {
      final auth = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(credentials);
      final apiKey = auth.apiKey;
      if (!_isCurrent(siteUrl, account, entry, request)) return;
      if (apiKey == null) {
        _commit(siteUrl, account, entry, request, () {
          entry.state = entry.state.withError(
            own
                ? appL10n.reconnectToToSeeYourSummary(instance.host)
                : appL10n.reconnectToSeeThisSummary(instance.host),
          );
        });
        return;
      }

      final summary = await auth.run(
        () =>
            api.userSummary(siteUrl: siteUrl, apiKey: apiKey, username: person),
      );
      _commit(siteUrl, account, entry, request, () {
        entry.state = entry.state.withSummary(summary);
      });
    } catch (error) {
      if (!_isCurrent(siteUrl, account, entry, request)) return;

      _commit(siteUrl, account, entry, request, () {
        entry.state = entry.state.withError(
          own
              ? appL10n.couldnTLoadYourSummaryFrom(instance.host)
              : appL10n.couldnTLoadThisSummaryFrom(instance.host),
        );
      });
    } finally {
      if (identical(entry.request, request)) entry.request = null;
    }
  }

  @override
  void forget(String siteUrl) {
    final account = _accounts.remove(siteUrl);
    account?.dispose();
    if (account != null) notifySafely();
  }

  bool _isCurrent(
    String siteUrl,
    _SummaryAccount account,
    _SummaryEntry entry,
    Object request,
  ) =>
      !isDisposed &&
      account.lease.isCurrent &&
      identical(_accounts[siteUrl], account) &&
      identical(entry.request, request);

  void _commit(
    String siteUrl,
    _SummaryAccount account,
    _SummaryEntry entry,
    Object request,
    VoidCallback mutation,
  ) {
    if (!_isCurrent(siteUrl, account, entry, request)) return;
    account.lease.commit(() {
      mutation();
      notifySafely();
    });
  }

  @override
  void dispose() {
    for (final account in _accounts.values) {
      account.dispose();
    }
    _accounts.clear();
    super.dispose();
  }
}
