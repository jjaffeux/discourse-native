part of 'shell_controller.dart';

abstract interface class _CurrentUserRefreshHost {
  bool _canAcceptCurrentUser(String siteUrl);
  DiscourseInstance? _instanceAt(String siteUrl);
  Future<DiscourseUser?> _readSessionUser(
    String siteUrl,
    String apiKey,
    SiteLease lease,
  );
  DiscourseUser _acceptDoNotDisturbSnapshot(String siteUrl, DiscourseUser user);
  bool _publishFreshCurrentUser(
    String siteUrl,
    SiteLease lease,
    DiscourseInstance previous,
    CurrentUserReconciliation accepted,
  );
}

final class _CurrentUserDirectory {
  _CurrentUserDirectory({
    required this.lifecycle,
    required this.models,
    required this._host,
  });

  final SiteLifecycle lifecycle;
  final DiscourseModelCodec models;
  final _CurrentUserRefreshHost _host;
  final Map<String, _CurrentUserAccount> _accounts = {};
  bool _disposed = false;

  _CurrentUserAccount _accountFor(String siteUrl, [SiteLease? lease]) {
    final held = _accounts[siteUrl];
    if (held != null && held.isCurrent) return held;
    held?.retire();
    final session = lease ?? lifecycle.capture(siteUrl);
    final account = _CurrentUserAccount(
      session,
      CurrentUserReconciler(lease: session, models: models),
    );
    _accounts[siteUrl] = account;
    account.detach = session.onRetire(() {
      account.retire();
      if (identical(_accounts[siteUrl], account)) _accounts.remove(siteUrl);
    });
    return account;
  }

  CurrentUserReconciler reconcilerFor(String siteUrl) =>
      _accountFor(siteUrl).reconciler;

  bool isFresh(String siteUrl) {
    final account = _accounts[siteUrl];
    return !_disposed && account != null && account.isCurrent && account.fresh;
  }

  DiscourseUser? freshUserFor(String siteUrl) =>
      isFresh(siteUrl) ? _host._instanceAt(siteUrl)?.user : null;

  void markConnectedUserFresh(String siteUrl, SiteLease lease) {
    if (_disposed || !lease.isCurrent) return;
    _accountFor(siteUrl, lease).fresh = true;
  }

  Future<DiscourseUser?> refresh(
    String siteUrl,
    String apiKey, {
    SiteLease? lease,
    bool force = false,
  }) {
    if (_disposed || _host._instanceAt(siteUrl) == null) return Future.value();
    final session = lease ?? lifecycle.capture(siteUrl);
    if (!session.isCurrent) return Future.value();
    final account = _accountFor(siteUrl, session);
    if (!force && account.fresh) {
      return Future.value(_host._instanceAt(siteUrl)?.user);
    }
    final refresh = account.refresh ??= CurrentUserRefresh(
      lease: account.lease,
      read: () async {
        final ticket = account.reconciler.beginSnapshot();
        final user = await _host._readSessionUser(
          siteUrl,
          apiKey,
          account.lease,
        );
        return user == null
            ? null
            : acceptSnapshot(siteUrl, user, account.lease, ticket);
      },
    );
    return refresh.request(force: force);
  }

  DiscourseUser? acceptSnapshot(
    String siteUrl,
    DiscourseUser response,
    SiteLease lease,
    CurrentUserSnapshot ticket,
  ) {
    final account = _accounts[siteUrl];
    bool ownsAcceptance() =>
        !_disposed &&
        account != null &&
        account.isCurrent &&
        lease.isCurrent &&
        identical(account.lease.session, lease.session) &&
        identical(_accounts[siteUrl], account) &&
        _host._canAcceptCurrentUser(siteUrl);

    if (!ownsAcceptance()) return null;
    final user = _host._acceptDoNotDisturbSnapshot(siteUrl, response);
    if (!ownsAcceptance()) return null;
    DiscourseUser? committed;
    lease.commit(() {
      final previous = _host._instanceAt(siteUrl);
      if (!ownsAcceptance() || previous == null) return;
      final accepted = account!.reconciler.reconcile(
        ticket,
        previous: previous.user,
        incoming: user,
      );
      if (accepted == null) return;
      account.fresh = true;
      if (_host._publishFreshCurrentUser(siteUrl, lease, previous, accepted)) {
        committed = accepted.user;
      }
    });
    return committed;
  }

  void forget(String siteUrl) => _accounts.remove(siteUrl)?.retire();

  void dispose() {
    _disposed = true;
    for (final account in _accounts.values.toList()) {
      account.retire();
    }
    _accounts.clear();
  }
}

final class _CurrentUserAccount {
  _CurrentUserAccount(this.lease, this.reconciler);

  final SiteLease lease;
  final CurrentUserReconciler reconciler;
  CurrentUserRefresh? refresh;
  bool fresh = false;
  bool _retired = false;
  void Function()? detach;

  bool get isCurrent => !_retired && lease.isCurrent;

  void retire() {
    if (_retired) return;
    _retired = true;
    detach?.call();
    detach = null;
    refresh?.retire();
    reconciler.retire();
    fresh = false;
  }
}
