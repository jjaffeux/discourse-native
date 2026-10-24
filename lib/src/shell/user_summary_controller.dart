import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';

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

final class _SummaryAccount {
  _SummaryAccount(this.lease);

  final SiteLease lease;
  UserSummaryState state = const UserSummaryState();
  Object? request;
  void Function()? detach;

  void dispose() {
    detach?.call();
    detach = null;
    state = const UserSummaryState();
    request = null;
  }
}

final class UserSummaryController extends FrameSafeNotifier {
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

  UserSummaryState stateFor(String? siteUrl) => siteUrl == null
      ? const UserSummaryState()
      : _accountFor(siteUrl)?.state ?? const UserSummaryState();

  Future<void> load(DiscourseInstance instance, {bool refresh = false}) async {
    if (isDisposed || !instance.isConnected) return;
    final user = instance.user;
    if (user == null) return;
    final siteUrl = instance.url;
    final account = _ensureAccount(siteUrl);
    final held = account.state;
    if (account.request != null || (!refresh && held.loaded)) return;

    final request = Object();
    final lease = account.lease;
    account.request = request;
    account.state = held.loadingNow();
    notifySafely();
    if (!_isCurrent(siteUrl, account, request)) return;

    try {
      final auth = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(credentials);
      final apiKey = auth.apiKey;
      if (!_isCurrent(siteUrl, account, request)) return;
      if (apiKey == null) {
        _commit(siteUrl, account, request, () {
          account.state = account.state.withError(
            appL10n.reconnectToToSeeYourSummary((instance.host).toString()),
          );
        });
        return;
      }

      final summary = await auth.run(
        () => api.userSummary(
          siteUrl: siteUrl,
          apiKey: apiKey,
          username: user.username,
        ),
      );
      _commit(siteUrl, account, request, () {
        account.state = account.state.withSummary(summary);
      });
    } catch (error) {
      if (!_isCurrent(siteUrl, account, request)) return;

      _commit(siteUrl, account, request, () {
        account.state = account.state.withError(
          appL10n.couldnTLoadYourSummaryFrom((instance.host).toString()),
        );
      });
    } finally {
      if (identical(account.request, request)) account.request = null;
    }
  }

  void forget(String siteUrl) {
    final account = _accounts.remove(siteUrl);
    account?.dispose();
    if (account != null) notifySafely();
  }

  bool _isCurrent(String siteUrl, _SummaryAccount account, Object request) =>
      !isDisposed &&
      account.lease.isCurrent &&
      identical(_accounts[siteUrl], account) &&
      identical(account.request, request);

  void _commit(
    String siteUrl,
    _SummaryAccount account,
    Object request,
    VoidCallback mutation,
  ) {
    if (!_isCurrent(siteUrl, account, request)) return;
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
